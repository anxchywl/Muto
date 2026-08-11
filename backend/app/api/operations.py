from __future__ import annotations

from fastapi import APIRouter, Query, Request

from app.api.errors import request_id_of
from app.api.schemas import OperationalReportPage, PageMeta
from app.application.report_operations import list_reports
from app.config import Settings
from app.dependencies import CurrentAdmin, DatabaseSession

router = APIRouter(prefix="/api/v1/operations", tags=["operations"])


@router.get("/reports", response_model=OperationalReportPage)
async def reports(
    request: Request,
    principal: CurrentAdmin,
    session: DatabaseSession,
    cursor: str | None = None,
    limit: int | None = Query(default=None, ge=1, le=100),
) -> OperationalReportPage:
    settings: Settings = request.app.state.settings
    items, next_cursor = await list_reports(session, cursor, limit, settings)
    return OperationalReportPage(
        data=items,
        meta=PageMeta(request_id=request_id_of(request), next_cursor=next_cursor),
    )
