from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.errors import request_id_of
from app.api.schemas import FavoriteIdsResponse, ListingPageResponse, PageMeta
from app.application.community_service import (
    add_favorite,
    favorite_ids,
    favorite_page,
    remove_favorite,
)
from app.dependencies import CurrentPrincipal, DatabaseSession

router = APIRouter(prefix="/api/v1/favorites", tags=["favorites"])


@router.get("", response_model=ListingPageResponse)
async def page(
    request: Request,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    cursor: Annotated[str | None, Query(max_length=1000)] = None,
    limit: Annotated[int | None, Query(ge=1, le=100)] = None,
) -> ListingPageResponse:
    items, next_cursor = await favorite_page(
        session,
        principal,
        cursor,
        limit,
        request.app.state.settings,
    )
    return ListingPageResponse(
        data=items,
        meta=PageMeta(request_id=request_id_of(request), next_cursor=next_cursor),
    )


@router.get("/ids", response_model=FavoriteIdsResponse)
async def ids(
    request: Request,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> FavoriteIdsResponse:
    return FavoriteIdsResponse(
        data=await favorite_ids(session, principal),
        meta=PageMeta(request_id=request_id_of(request)),
    )


@router.put("/{listing_id}")
async def add(
    request: Request,
    listing_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> dict[str, object]:
    await add_favorite(session, principal, listing_id)
    return {
        "data": {"saved": True},
        "meta": {"request_id": request_id_of(request)},
    }


@router.delete("/{listing_id}")
async def remove(
    request: Request,
    listing_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> dict[str, object]:
    await remove_favorite(session, principal, listing_id)
    return {
        "data": {"saved": False},
        "meta": {"request_id": request_id_of(request)},
    }
