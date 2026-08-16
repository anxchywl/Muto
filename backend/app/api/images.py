from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Header, Request, Response

from app.api.errors import request_id_of
from app.api.headers import require_idempotency_key
from app.api.schemas import ImageUploadSlotRequest
from app.application.image_service import (
    create_upload_slot,
    finalize_image_upload,
    read_image,
    upload_image_content,
)
from app.dependencies import (
    CurrentPrincipal,
    DatabaseSession,
    ImageStorageDependency,
)

router = APIRouter(prefix="/api/v1", tags=["images"])


@router.post("/image-uploads", status_code=201)
async def create_slot(
    request: Request,
    payload: ImageUploadSlotRequest,
    principal: CurrentPrincipal,
    session: DatabaseSession,
) -> dict[str, object]:
    slot = await create_upload_slot(
        session,
        principal,
        payload,
        request.app.state.settings,
    )
    return {
        "data": slot.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.put("/image-uploads/{upload_id}/content")
async def upload_content(
    request: Request,
    upload_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    storage: ImageStorageDependency,
    response: Response,
) -> dict[str, object]:
    receipt, replayed = await upload_image_content(
        session,
        storage,
        principal,
        upload_id,
        await request.body(),
    )
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": receipt.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.post("/image-uploads/{upload_id}/finalize")
async def finalize(
    request: Request,
    upload_id: UUID,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    storage: ImageStorageDependency,
    response: Response,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    reference, replayed = await finalize_image_upload(
        session,
        storage,
        principal,
        upload_id,
        require_idempotency_key(idempotency_key),
        request.app.state.settings,
    )
    if replayed:
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": reference.model_dump(mode="json"),
        "meta": {"request_id": request_id_of(request)},
    }


@router.get("/images/{image_id}/{version}")
async def image_content(
    image_id: UUID,
    version: str,
    principal: CurrentPrincipal,
    session: DatabaseSession,
    storage: ImageStorageDependency,
) -> Response:
    content, mime_type = await read_image(
        session,
        storage,
        principal,
        image_id,
        version,
    )
    return Response(
        content=content,
        media_type=mime_type,
        headers={
            "Content-Disposition": "inline",
            "Cache-Control": "private, no-store",
        },
    )
