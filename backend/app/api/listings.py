from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Query, Request, Response, status

from app.api.errors import request_id_of
from app.api.headers import require_expected_version, require_idempotency_key
from app.api.schemas import (
    IdentityResponse,
    ListingDraftRequest,
    ListingPageResponse,
    ListingQueryParams,
    ListingStatusRequest,
    PageMeta,
)
from app.application.listing_service import (
    browse_listings,
    change_listing_status,
    create_listing,
    get_listing,
    listing_suggestions,
    update_listing,
)
from app.config import Settings
from app.dependencies import CurrentPrincipal, DatabaseSession
from app.domain.listings import ListingStatus

router = APIRouter(prefix="/api/v1", tags=["marketplace"])


def settings_from(request: Request) -> Settings:
    return request.app.state.settings


@router.get("/me")
async def me(request: Request, principal: CurrentPrincipal) -> dict[str, object]:
    return {
        "data": IdentityResponse(
            user_id=principal.user_id,
            display_name=principal.display_name or "Student",
            is_verified=principal.is_verified,
            is_admin=principal.is_admin,
        ).model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.get("/listings", response_model=ListingPageResponse)
async def browse(
    request: Request,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    params: Annotated[ListingQueryParams, Query()],
) -> ListingPageResponse:
    items, next_cursor = await browse_listings(
        session,
        params,
        settings_from(request),
    )
    return ListingPageResponse(
        data=items,
        meta=PageMeta(request_id=request_id_of(request), next_cursor=next_cursor),
    )


@router.get("/listings/suggestions")
async def suggestions(
    request: Request,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    prefix: Annotated[str, Query(max_length=80)],
) -> dict[str, object]:
    return {
        "data": await listing_suggestions(session, prefix),
        "meta": {"request_id": request_id_of(request)},
    }


@router.get("/me/listings", response_model=ListingPageResponse)
async def mine(
    request: Request,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    cursor: str | None = None,
    limit: int | None = None,
    listing_status: Annotated[ListingStatus | None, Query(alias="status")] = None,
) -> ListingPageResponse:
    params = ListingQueryParams(cursor=cursor, limit=limit, status=listing_status)
    items, next_cursor = await browse_listings(
        session,
        params,
        settings_from(request),
        owner_id=principal.user_id,
    )
    return ListingPageResponse(
        data=items,
        meta=PageMeta(request_id=request_id_of(request), next_cursor=next_cursor),
    )


@router.get("/listings/{listing_id}")
async def detail(
    request: Request,
    listing_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
) -> dict[str, object]:
    listing = await get_listing(session, listing_id, principal)
    response.headers["ETag"] = f'"{listing.version}"'
    return {
        "data": listing.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.get("/listings/{listing_id}/images")
async def images(
    request: Request,
    listing_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> dict[str, object]:
    listing = await get_listing(session, listing_id, principal)
    return {
        "data": [image.model_dump(mode="json") for image in listing.images],
        "meta": {"request_id": request_id_of(request)},
    }


@router.post("/listings", status_code=status.HTTP_201_CREATED)
async def create(
    request: Request,
    draft: ListingDraftRequest,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    listing, replayed = await create_listing(
        session,
        principal,
        draft,
        require_idempotency_key(idempotency_key),
        settings_from(request),
    )
    response.headers["ETag"] = f'"{listing.version}"'
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": listing.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.patch("/listings/{listing_id}")
async def update(
    request: Request,
    listing_id: UUID,
    draft: ListingDraftRequest,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
    if_match: Annotated[str | None, Header(alias="If-Match")] = None,
) -> dict[str, object]:
    listing = await update_listing(
        session,
        principal,
        listing_id,
        draft,
        require_expected_version(if_match),
    )
    response.headers["ETag"] = f'"{listing.version}"'
    return {
        "data": listing.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.patch("/listings/{listing_id}/status")
async def status_change(
    request: Request,
    listing_id: UUID,
    payload: ListingStatusRequest,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
    if_match: Annotated[str | None, Header(alias="If-Match")] = None,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    listing, replayed = await change_listing_status(
        session,
        principal,
        listing_id,
        payload.status,
        require_expected_version(if_match),
        require_idempotency_key(idempotency_key),
        settings_from(request),
    )
    response.headers["ETag"] = f'"{listing.version}"'
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": listing.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.delete("/listings/{listing_id}")
async def remove(
    request: Request,
    listing_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
    if_match: Annotated[str | None, Header(alias="If-Match")] = None,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    listing, replayed = await change_listing_status(
        session,
        principal,
        listing_id,
        ListingStatus.removed,
        require_expected_version(if_match),
        require_idempotency_key(idempotency_key),
        settings_from(request),
    )
    response.headers["ETag"] = f'"{listing.version}"'
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": listing.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }
