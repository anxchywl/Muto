from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Header, Request, Response, status

from app.api.errors import request_id_of
from app.api.headers import require_idempotency_key
from app.api.schemas import ReportRequest
from app.application.community_service import submit_report
from app.dependencies import CurrentPrincipal, DatabaseSession

router = APIRouter(prefix="/api/v1/reports", tags=["reports"])


@router.post("", status_code=status.HTTP_202_ACCEPTED)
async def submit(
    request: Request,
    payload: ReportRequest,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    response: Response,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    result, replayed = await submit_report(
        session,
        principal,
        payload,
        require_idempotency_key(idempotency_key),
        request.app.state.settings,
    )
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": result,
        "meta": {"request_id": request_id_of(request)},
    }
