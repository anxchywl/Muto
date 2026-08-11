from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.errors import request_id_of
from app.api.schemas import ListingPageResponse, PageMeta
from app.application.community_service import seller_listings, seller_profile
from app.dependencies import CurrentPrincipal, DatabaseSession

router = APIRouter(prefix="/api/v1/sellers", tags=["sellers"])


@router.get("/{seller_id}")
async def profile(
    request: Request,
    seller_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> dict[str, object]:
    resolved = await seller_profile(session, seller_id)
    return {
        "data": resolved.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.get("/{seller_id}/listings", response_model=ListingPageResponse)
async def listings(
    request: Request,
    seller_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    cursor: Annotated[str | None, Query(max_length=1000)] = None,
    limit: Annotated[int | None, Query(ge=1, le=100)] = None,
) -> ListingPageResponse:
    items, next_cursor = await seller_listings(
        session,
        seller_id,
        cursor,
        limit,
        request.app.state.settings,
    )
    return ListingPageResponse(
        data=items,
        meta=PageMeta(request_id=request_id_of(request), next_cursor=next_cursor),
    )
