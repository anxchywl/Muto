from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import and_, delete, desc, func, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.schemas import (
    ListingQueryParams,
    ListingResponse,
    ReportRequest,
    SellerProfileResponse,
)
from app.application.cursors import CursorCodec
from app.application.listing_service import browse_listings, serialize_listing_rows
from app.config import Settings
from app.domain.auth import Principal
from app.domain.errors import (
    ConflictError,
    ForbiddenError,
    GoneError,
    NotFoundError,
    RateLimitedError,
)
from app.domain.listings import PUBLIC_STATUSES, ListingStatus
from app.infrastructure.db.models import (
    Favorite,
    IdempotencyKey,
    Listing,
    Report,
    User,
)


async def favorite_ids(session: AsyncSession, principal: Principal) -> list[UUID]:
    values = await session.scalars(
        select(Favorite.listing_id)
        .where(Favorite.user_id == principal.user_id)
        .order_by(Favorite.listing_id)
    )
    return list(values)


async def favorite_page(
    session: AsyncSession,
    principal: Principal,
    cursor: str | None,
    limit: int | None,
    settings: Settings,
) -> tuple[list[ListingResponse], str | None]:
    page_size = min(limit or settings.default_page_size, settings.maximum_page_size)
    cursor_scope = f"favorites:{principal.user_id}"
    codec = CursorCodec(settings.cursor_secret.get_secret_value())
    payload = codec.decode(cursor) if cursor else None
    if payload is not None and payload.get("f") != cursor_scope:
        raise ConflictError(
            "cursor_filter_mismatch", "The cursor does not match this account."
        )
    query = (
        select(Listing, User)
        .join(Favorite, Favorite.listing_id == Listing.id)
        .join(User, User.id == Listing.owner_id)
        .where(
            Favorite.user_id == principal.user_id,
            Listing.status.in_([status.value for status in PUBLIC_STATUSES]),
            Listing.expires_at > func.now(),
        )
        .order_by(desc(Listing.updated_at), desc(Listing.id))
    )
    if payload:
        moment = datetime.fromisoformat(str(payload["v"]))
        listing_id = UUID(str(payload["id"]))
        query = query.where(
            or_(
                Listing.updated_at < moment,
                and_(Listing.updated_at == moment, Listing.id < listing_id),
            )
        )
    rows = list((await session.execute(query.limit(page_size + 1))).all())
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        last = rows[-1][0]
        next_cursor = codec.encode(
            {
                "f": cursor_scope,
                "v": last.updated_at.isoformat(),
                "id": str(last.id),
            }
        )
    listing_rows = [(listing, seller) for listing, seller in rows]
    return await serialize_listing_rows(session, listing_rows), next_cursor


async def add_favorite(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
) -> None:
    row = (
        await session.execute(
            select(Listing, User)
            .join(User, User.id == Listing.owner_id)
            .where(Listing.id == listing_id)
        )
    ).one_or_none()
    if row is None:
        raise NotFoundError("listing_not_found", "The listing was not found.")
    listing, seller = row
    if seller.account_status != "active":
        raise NotFoundError("listing_not_found", "The listing was not found.")
    if listing.status == ListingStatus.removed.value:
        raise GoneError()
    if listing.expires_at <= datetime.now(UTC):
        raise NotFoundError("listing_not_found", "The listing was not found.")
    if (
        listing.status == ListingStatus.hidden.value
        and listing.owner_id != principal.user_id
    ):
        raise NotFoundError("listing_not_found", "The listing was not found.")
    await session.execute(
        insert(Favorite)
        .values(user_id=principal.user_id, listing_id=listing_id)
        .on_conflict_do_nothing(constraint="uq_favorites_user_listing")
    )
    await session.commit()


async def remove_favorite(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
) -> None:
    await session.execute(
        delete(Favorite).where(
            Favorite.user_id == principal.user_id,
            Favorite.listing_id == listing_id,
        )
    )
    await session.commit()


async def seller_profile(
    session: AsyncSession,
    seller_id: UUID,
) -> SellerProfileResponse:
    first_listed_at = await session.scalar(
        select(func.min(Listing.created_at)).where(Listing.owner_id == seller_id)
    )
    if first_listed_at is None:
        raise NotFoundError("seller_not_found", "The seller was not found.")
    seller = await session.get(User, seller_id)
    if seller is None or seller.account_status != "active":
        raise NotFoundError("seller_not_found", "The seller was not found.")
    active_count = await session.scalar(
        select(func.count())
        .select_from(Listing)
        .where(
            Listing.owner_id == seller_id,
            Listing.status.in_([status.value for status in PUBLIC_STATUSES]),
            Listing.expires_at > func.now(),
        )
    )
    return SellerProfileResponse(
        seller_id=seller.id,
        display_name=seller.display_name or "Student",
        is_verified=seller.is_verified,
        active_listing_count=active_count or 0,
        first_listed_at=first_listed_at,
    )


async def seller_listings(
    session: AsyncSession,
    seller_id: UUID,
    cursor: str | None,
    limit: int | None,
    settings: Settings,
) -> tuple[list[ListingResponse], str | None]:
    return await browse_listings(
        session,
        ListingQueryParams(cursor=cursor, limit=limit),
        settings,
        public_owner_id=seller_id,
    )


async def submit_report(
    session: AsyncSession,
    principal: Principal,
    payload: ReportRequest,
    idempotency_key: str,
    settings: Settings,
) -> tuple[dict[str, bool], bool]:
    body = payload.model_dump(mode="json")
    fingerprint = hashlib.sha256(
        json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    lock_scope = f"report-submit:{principal.user_id}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(lock_scope, 0)))
    )
    now = datetime.now(UTC)
    existing = await session.scalar(
        select(IdempotencyKey).where(
            IdempotencyKey.user_id == principal.user_id,
            IdempotencyKey.operation == "report.submit",
            IdempotencyKey.key == idempotency_key,
        )
    )
    if existing:
        if existing.expires_at > now:
            if existing.request_fingerprint != fingerprint:
                raise ConflictError(
                    "idempotency_key_reused",
                    "The idempotency key was already used with another request.",
                )
            return {"accepted": True}, True
        await session.delete(existing)
        await session.flush()

    row = (
        await session.execute(
            select(Listing, User)
            .join(User, User.id == Listing.owner_id)
            .where(Listing.id == payload.listing_id)
        )
    ).one_or_none()
    if row is None:
        raise NotFoundError("listing_not_found", "The listing was not found.")
    listing, seller = row
    if seller.account_status != "active":
        raise NotFoundError("listing_not_found", "The listing was not found.")
    if listing.owner_id == principal.user_id:
        raise ForbiddenError("A student cannot report their own listing.")
    if listing.status == ListingStatus.removed.value:
        raise GoneError()
    if listing.status == ListingStatus.hidden.value:
        raise NotFoundError("listing_not_found", "The listing was not found.")

    window_start = now - timedelta(seconds=settings.report_window_seconds)
    count, oldest = (
        await session.execute(
            select(func.count(), func.min(IdempotencyKey.created_at)).where(
                IdempotencyKey.user_id == principal.user_id,
                IdempotencyKey.operation == "report.submit",
                IdempotencyKey.created_at > window_start,
            )
        )
    ).one()
    if count >= settings.report_burst_limit:
        retry_after = settings.report_window_seconds
        if oldest is not None:
            retry_after = max(1, int((oldest - window_start).total_seconds()) + 1)
        raise RateLimitedError(retry_after)

    await session.execute(
        insert(Report)
        .values(
            reporter_id=principal.user_id,
            listing_id=payload.listing_id,
            reason=payload.reason.value,
            note=payload.note,
        )
        .on_conflict_do_nothing(constraint="uq_reports_reporter_listing")
    )
    response = {"accepted": True}
    session.add(
        IdempotencyKey(
            user_id=principal.user_id,
            operation="report.submit",
            key=idempotency_key,
            request_fingerprint=fingerprint,
            response_status=202,
            response_body=response,
            expires_at=now + timedelta(hours=settings.idempotency_ttl_hours),
        )
    )
    await session.commit()
    return response, False
