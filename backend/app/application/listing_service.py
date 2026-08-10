from __future__ import annotations

import hashlib
import json
import re
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import Select, and_, desc, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.schemas import (
    ImageReference,
    ListingDraftRequest,
    ListingQueryParams,
    ListingResponse,
    MoneyResponse,
)
from app.application.cursors import CursorCodec
from app.application.image_service import (
    image_references_by_listing,
    redeem_listing_images,
    release_listing_images,
)
from app.config import Settings
from app.domain.auth import Principal
from app.domain.errors import (
    ConflictError,
    ForbiddenError,
    GoneError,
    NotFoundError,
)
from app.domain.listings import (
    EDITABLE_STATUSES,
    PUBLIC_STATUSES,
    ListingSort,
    ListingStatus,
    require_transition,
    validate_listing_values,
)
from app.infrastructure.db.models import IdempotencyKey, Listing, User


def serialize_listing(
    listing: Listing,
    seller: User,
    *,
    include_contact: bool = False,
    images: list[ImageReference] | None = None,
) -> ListingResponse:
    contact = None
    if include_contact:
        values = {
            "telegram_username": seller.telegram_username,
            "email": seller.email,
            "phone": seller.phone,
        }
        contact = {key: value for key, value in values.items() if value}
        if not contact:
            contact = None
    price = None
    if listing.price_minor_units is not None and listing.currency is not None:
        price = MoneyResponse(
            minor_units=listing.price_minor_units,
            currency=listing.currency,
        )
    return ListingResponse(
        id=listing.id,
        version=listing.version,
        kind=listing.kind,
        status=listing.status,
        title=listing.title,
        description=listing.description,
        condition=listing.condition,
        category=listing.category,
        images=images or [],
        seller_id=listing.owner_id,
        seller_display_name=seller.display_name or "Student",
        created_at=listing.created_at,
        updated_at=listing.updated_at,
        price=price,
        wanted_items=listing.wanted_items,
        contact=contact,
    )


async def serialize_listing_rows(
    session: AsyncSession,
    rows: list[tuple[Listing, User]],
) -> list[ListingResponse]:
    references = await image_references_by_listing(
        session,
        [listing.id for listing, _ in rows],
    )
    return [
        serialize_listing(
            listing,
            seller,
            images=references.get(listing.id, []),
        )
        for listing, seller in rows
    ]


def _query_fingerprint(
    params: ListingQueryParams,
    *,
    owner_id: UUID | None,
    scope: str,
) -> str:
    payload = params.model_dump(exclude={"cursor", "limit"}, mode="json")
    payload["owner_id"] = str(owner_id) if owner_id else None
    payload["scope"] = scope
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def _apply_filters(
    query: Select[tuple[Listing, User]], params: ListingQueryParams
) -> Select[tuple[Listing, User]]:
    query = query.where(
        Listing.status.in_([status.value for status in PUBLIC_STATUSES]),
        User.account_status == "active",
    )
    if params.q:
        query = query.where(
            Listing.search_vector.op("@@")(
                func.websearch_to_tsquery("simple", params.q)
            )
        )
    if params.category:
        query = query.where(Listing.category == params.category.value)
    if params.kind:
        query = query.where(Listing.kind == params.kind.value)
    if params.condition:
        query = query.where(Listing.condition == params.condition.value)
    if params.currency:
        query = query.where(Listing.currency == params.currency)
    if params.min_minor_units is not None:
        query = query.where(Listing.price_minor_units >= params.min_minor_units)
    if params.max_minor_units is not None:
        query = query.where(Listing.price_minor_units <= params.max_minor_units)
    return query


async def browse_listings(
    session: AsyncSession,
    params: ListingQueryParams,
    settings: Settings,
    *,
    owner_id: UUID | None = None,
    public_owner_id: UUID | None = None,
) -> tuple[list[ListingResponse], str | None]:
    limit = min(params.limit or settings.default_page_size, settings.maximum_page_size)
    scope = (
        "mine" if owner_id is not None else "seller" if public_owner_id else "browse"
    )
    fingerprint = _query_fingerprint(
        params,
        owner_id=owner_id or public_owner_id,
        scope=scope,
    )
    codec = CursorCodec(settings.cursor_secret.get_secret_value())
    query = select(Listing, User).join(User, User.id == Listing.owner_id)
    if owner_id is None:
        query = _apply_filters(query, params)
        if public_owner_id is not None:
            query = query.where(Listing.owner_id == public_owner_id)
    else:
        query = query.where(
            Listing.owner_id == owner_id, Listing.status != ListingStatus.removed.value
        )
        if params.status:
            query = query.where(Listing.status == params.status.value)
        if params.category:
            query = query.where(Listing.category == params.category.value)
        if params.kind:
            query = query.where(Listing.kind == params.kind.value)
        if params.condition:
            query = query.where(Listing.condition == params.condition.value)
    cursor_payload = codec.decode(params.cursor) if params.cursor else None
    if cursor_payload is not None and cursor_payload.get("f") != fingerprint:
        raise ConflictError(
            "cursor_filter_mismatch", "The cursor does not match these filters."
        )
    if params.sort == ListingSort.newest:
        query = query.order_by(desc(Listing.created_at), desc(Listing.id))
        if cursor_payload:
            moment = datetime.fromisoformat(str(cursor_payload["v"]))
            listing_id = UUID(str(cursor_payload["id"]))
            query = query.where(
                or_(
                    Listing.created_at < moment,
                    and_(Listing.created_at == moment, Listing.id < listing_id),
                )
            )
    else:
        ascending = params.sort == ListingSort.price_ascending
        order = (
            Listing.price_minor_units.asc()
            if ascending
            else Listing.price_minor_units.desc()
        )
        query = query.order_by(
            order, Listing.id.asc() if ascending else Listing.id.desc()
        )
        if cursor_payload:
            cursor_value = int(cursor_payload["v"])
            listing_id = UUID(str(cursor_payload["id"]))
            comparison = (
                Listing.price_minor_units > cursor_value
                if ascending
                else Listing.price_minor_units < cursor_value
            )
            id_comparison = (
                Listing.id > listing_id if ascending else Listing.id < listing_id
            )
            query = query.where(
                or_(
                    comparison,
                    and_(Listing.price_minor_units == cursor_value, id_comparison),
                )
            )
    rows = list((await session.execute(query.limit(limit + 1))).all())
    has_more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = None
    if has_more and rows:
        last = rows[-1][0]
        value: object = (
            last.created_at.isoformat()
            if params.sort == ListingSort.newest
            else last.price_minor_units
        )
        next_cursor = codec.encode({"f": fingerprint, "v": value, "id": str(last.id)})
    listing_rows = [(listing, seller) for listing, seller in rows]
    return await serialize_listing_rows(session, listing_rows), next_cursor


async def listing_suggestions(
    session: AsyncSession,
    prefix: str,
) -> list[str]:
    normalized = " ".join(prefix.lower().split())
    if len(normalized) < 2:
        return []
    titles = (
        await session.scalars(
            select(Listing.title)
            .where(Listing.status.in_([status.value for status in PUBLIC_STATUSES]))
            .order_by(desc(Listing.created_at))
            .limit(2_000)
        )
    ).all()
    counts: dict[str, int] = {}
    for title in titles:
        for word in re.findall(r"[^\W_]+", title.lower(), flags=re.UNICODE):
            if len(word) >= 2 and word.startswith(normalized):
                counts[word] = counts.get(word, 0) + 1
    return sorted(counts, key=lambda word: (-counts[word], word))[:6]


async def get_listing(
    session: AsyncSession,
    listing_id: UUID,
    principal: Principal,
) -> ListingResponse:
    row = (
        await session.execute(
            select(Listing, User).join(User).where(Listing.id == listing_id)
        )
    ).one_or_none()
    if row is None:
        raise NotFoundError("listing_not_found", "The listing was not found.")
    listing, seller = row
    if seller.account_status != "active":
        raise NotFoundError("listing_not_found", "The listing was not found.")
    if listing.status == ListingStatus.removed.value:
        raise GoneError()
    if (
        listing.status == ListingStatus.hidden.value
        and listing.owner_id != principal.user_id
    ):
        raise NotFoundError("listing_not_found", "The listing was not found.")
    references = await image_references_by_listing(session, [listing.id])
    return serialize_listing(
        listing,
        seller,
        include_contact=principal.is_verified,
        images=references.get(listing.id, []),
    )


def _apply_draft(listing: Listing, draft: ListingDraftRequest) -> None:
    validate_listing_values(
        kind=draft.kind,
        price_minor_units=draft.price_minor_units,
        currency=draft.currency,
        wanted_items=draft.wanted_items,
    )
    listing.kind = draft.kind.value
    listing.title = draft.title
    listing.description = draft.description
    listing.condition = draft.condition.value
    listing.category = draft.category.value
    listing.price_minor_units = draft.price_minor_units
    listing.currency = draft.currency
    listing.wanted_items = draft.wanted_items


async def create_listing(
    session: AsyncSession,
    principal: Principal,
    draft: ListingDraftRequest,
    idempotency_key: str,
    settings: Settings,
) -> tuple[ListingResponse, bool]:
    if not principal.is_verified:
        raise ForbiddenError("Only verified students may publish listings.")
    body = draft.model_dump(mode="json")
    fingerprint = hashlib.sha256(
        json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    scope = f"listing-create:{principal.user_id}:{idempotency_key}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(scope, 0)))
    )
    existing = await session.scalar(
        select(IdempotencyKey).where(
            IdempotencyKey.user_id == principal.user_id,
            IdempotencyKey.operation == "listing.create",
            IdempotencyKey.key == idempotency_key,
        )
    )
    if existing:
        if existing.expires_at > datetime.now(UTC):
            if existing.request_fingerprint != fingerprint:
                raise ConflictError(
                    "idempotency_key_reused",
                    "The idempotency key was already used with another request.",
                )
            return ListingResponse.model_validate(existing.response_body), True
        await session.delete(existing)
        await session.flush()
    listing = Listing(owner_id=principal.user_id)
    _apply_draft(listing, draft)
    session.add(listing)
    await session.flush()
    seller = await session.get(User, principal.user_id)
    if seller is None:
        raise RuntimeError("principal has no user")
    await redeem_listing_images(session, principal, listing.id, draft.images)
    response = serialize_listing(listing, seller, images=draft.images)
    session.add(
        IdempotencyKey(
            user_id=principal.user_id,
            operation="listing.create",
            key=idempotency_key,
            request_fingerprint=fingerprint,
            response_status=201,
            response_body=response.model_dump(mode="json"),
            expires_at=datetime.now(UTC)
            + timedelta(hours=settings.idempotency_ttl_hours),
        )
    )
    await session.commit()
    return response, False


async def update_listing(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
    draft: ListingDraftRequest,
    expected_version: int,
) -> ListingResponse:
    validate_listing_values(
        kind=draft.kind,
        price_minor_units=draft.price_minor_units,
        currency=draft.currency,
        wanted_items=draft.wanted_items,
    )
    result = await session.execute(
        update(Listing)
        .where(
            Listing.id == listing_id,
            Listing.owner_id == principal.user_id,
            Listing.version == expected_version,
            Listing.status.in_([status.value for status in EDITABLE_STATUSES]),
        )
        .values(
            kind=draft.kind.value,
            title=draft.title,
            description=draft.description,
            condition=draft.condition.value,
            category=draft.category.value,
            price_minor_units=draft.price_minor_units,
            currency=draft.currency,
            wanted_items=draft.wanted_items,
            version=Listing.version + 1,
            updated_at=datetime.now(UTC),
        )
        .returning(Listing)
    )
    listing = result.scalar_one_or_none()
    if listing is None:
        await _raise_mutation_failure(
            session, principal, listing_id, expected_version, require_editable=True
        )
        raise AssertionError("unreachable")
    await redeem_listing_images(session, principal, listing.id, draft.images)
    await session.commit()
    seller = await session.get(User, principal.user_id)
    if seller is None:
        raise RuntimeError("principal has no user")
    return serialize_listing(listing, seller, images=draft.images)


async def change_listing_status(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
    target: ListingStatus,
    expected_version: int,
    idempotency_key: str,
    settings: Settings,
) -> tuple[ListingResponse, bool]:
    fingerprint = hashlib.sha256(
        f"{listing_id}:{target.value}:{expected_version}".encode()
    ).hexdigest()
    scope = f"listing-status:{principal.user_id}:{idempotency_key}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(scope, 0)))
    )
    existing = await session.scalar(
        select(IdempotencyKey).where(
            IdempotencyKey.user_id == principal.user_id,
            IdempotencyKey.operation == "listing.status",
            IdempotencyKey.key == idempotency_key,
        )
    )
    if existing:
        if existing.expires_at > datetime.now(UTC):
            if existing.request_fingerprint != fingerprint:
                raise ConflictError(
                    "idempotency_key_reused",
                    "The idempotency key was already used with another request.",
                )
            return ListingResponse.model_validate(existing.response_body), True
        await session.delete(existing)
        await session.flush()
    current = await _owned_listing(session, principal, listing_id)
    _require_version(current, expected_version)
    require_transition(ListingStatus(current.status), target)
    result = await session.execute(
        update(Listing)
        .where(
            Listing.id == listing_id,
            Listing.owner_id == principal.user_id,
            Listing.version == expected_version,
            Listing.status == current.status,
        )
        .values(
            status=target.value,
            version=Listing.version + 1,
            updated_at=datetime.now(UTC),
        )
        .returning(Listing)
    )
    listing = result.scalar_one_or_none()
    if listing is None:
        await _raise_mutation_failure(session, principal, listing_id, expected_version)
        raise AssertionError("unreachable")
    seller = await session.get(User, principal.user_id)
    if seller is None:
        raise RuntimeError("principal has no user")
    references = await image_references_by_listing(session, [listing.id])
    response = serialize_listing(
        listing,
        seller,
        images=references.get(listing.id, []),
    )
    if target == ListingStatus.removed:
        await release_listing_images(session, listing.id)
    session.add(
        IdempotencyKey(
            user_id=principal.user_id,
            operation="listing.status",
            key=idempotency_key,
            request_fingerprint=fingerprint,
            response_status=200,
            response_body=response.model_dump(mode="json"),
            expires_at=datetime.now(UTC)
            + timedelta(hours=settings.idempotency_ttl_hours),
        )
    )
    await session.commit()
    return response, False


async def _owned_listing(
    session: AsyncSession, principal: Principal, listing_id: UUID
) -> Listing:
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise NotFoundError("listing_not_found", "The listing was not found.")
    if listing.status == ListingStatus.removed.value:
        raise GoneError()
    if listing.owner_id != principal.user_id:
        raise ForbiddenError("Only the listing owner may change it.")
    return listing


def _require_version(listing: Listing, expected_version: int) -> None:
    if listing.version != expected_version:
        raise ConflictError(
            "listing_version_conflict",
            "The listing changed before this update was applied.",
            {"current_version": listing.version},
        )


async def _raise_mutation_failure(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
    expected_version: int,
    *,
    require_editable: bool = False,
) -> None:
    listing = await _owned_listing(session, principal, listing_id)
    _require_version(listing, expected_version)
    if require_editable and ListingStatus(listing.status) not in EDITABLE_STATUSES:
        raise ConflictError(
            "listing_not_editable",
            "This listing can no longer be edited.",
        )
    raise ConflictError(
        "listing_version_conflict",
        "The listing changed before this update was applied.",
        {"current_version": listing.version},
    )
