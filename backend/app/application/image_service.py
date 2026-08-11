from __future__ import annotations

import hashlib
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.schemas import (
    ImageReference,
    ImageUploadReceipt,
    ImageUploadSlotRequest,
    ImageUploadSlotResponse,
)
from app.config import Settings, StorageAdapter
from app.domain.auth import Principal
from app.domain.errors import (
    ConflictError,
    ForbiddenError,
    ImageUploadExpiredError,
    ImageUploadRateLimitedError,
    NotFoundError,
    ServiceUnavailableError,
    ValidationError,
)
from app.domain.images import validate_upload_metadata
from app.domain.listings import ListingStatus
from app.infrastructure.db.models import (
    IdempotencyKey,
    ImageUpload,
    Listing,
    ListingImage,
    User,
)
from app.infrastructure.storage import ImageStorage
from app.infrastructure.storage.processing import normalize_image

EXTENSIONS = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


async def create_upload_slot(
    session: AsyncSession,
    principal: Principal,
    payload: ImageUploadSlotRequest,
    settings: Settings,
) -> ImageUploadSlotResponse:
    if settings.storage_adapter == StorageAdapter.unconfigured:
        raise ServiceUnavailableError(
            "image_storage_unavailable",
            "Image storage is not configured.",
        )
    validate_upload_metadata(payload.mime_type, payload.byte_length)
    lock_scope = f"image-slot:{principal.user_id}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(lock_scope, 0)))
    )
    now = datetime.now(UTC)
    window_start = now - timedelta(seconds=settings.image_upload_window_seconds)
    count, oldest = (
        await session.execute(
            select(func.count(), func.min(ImageUpload.created_at)).where(
                ImageUpload.owner_id == principal.user_id,
                ImageUpload.created_at > window_start,
            )
        )
    ).one()
    if count >= settings.image_upload_burst_limit:
        retry_after = settings.image_upload_window_seconds
        if oldest is not None:
            retry_after = max(1, int((oldest - window_start).total_seconds()) + 1)
        raise ImageUploadRateLimitedError(retry_after)
    upload = ImageUpload(
        owner_id=principal.user_id,
        declared_mime_type=payload.mime_type,
        declared_byte_length=payload.byte_length,
        expires_at=now + timedelta(minutes=settings.image_upload_ttl_minutes),
    )
    session.add(upload)
    await session.commit()
    return ImageUploadSlotResponse(
        upload_id=upload.id,
        upload_target=f"/api/v1/image-uploads/{upload.id}/content",
        expires_at=upload.expires_at,
    )


async def upload_image_content(
    session: AsyncSession,
    storage: ImageStorage,
    principal: Principal,
    upload_id: UUID,
    content: bytes,
) -> tuple[ImageUploadReceipt, bool]:
    await _lock_upload(session, principal, upload_id)
    upload = await _owned_upload(session, principal, upload_id)
    await _require_not_expired(session, storage, upload)
    if len(content) != upload.declared_byte_length:
        raise ValidationError(
            "image_size_mismatch",
            "The uploaded byte count does not match the requested slot.",
        )
    normalized = normalize_image(content, upload.declared_mime_type)
    if upload.state != "pending":
        if upload.content_digest == normalized.digest:
            return _receipt(upload), True
        raise ConflictError(
            "image_upload_already_used",
            "This upload slot already contains different content.",
        )
    storage_key = f"staged/{upload.id}.{normalized.extension}"
    await storage.write(storage_key, normalized.content)
    upload.state = "uploaded"
    upload.detected_mime_type = normalized.mime_type
    upload.byte_size = len(normalized.content)
    upload.width = normalized.width
    upload.height = normalized.height
    upload.content_digest = normalized.digest
    upload.version = normalized.digest
    upload.storage_key = storage_key
    try:
        await session.commit()
    except SQLAlchemyError:
        await storage.delete(storage_key)
        raise
    return _receipt(upload), False


async def finalize_image_upload(
    session: AsyncSession,
    storage: ImageStorage,
    principal: Principal,
    upload_id: UUID,
    idempotency_key: str,
    settings: Settings,
) -> tuple[ImageReference, bool]:
    lock_scope = f"image-finalize:{principal.user_id}:{upload_id}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(lock_scope, 0)))
    )
    fingerprint = hashlib.sha256(str(upload_id).encode()).hexdigest()
    now = datetime.now(UTC)
    existing = await session.scalar(
        select(IdempotencyKey).where(
            IdempotencyKey.user_id == principal.user_id,
            IdempotencyKey.operation == "image.finalize",
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
            return ImageReference.model_validate(existing.response_body), True
        await session.delete(existing)
        await session.flush()
    upload = await _owned_upload(session, principal, upload_id)
    await _require_not_expired(session, storage, upload)
    if upload.state == "pending":
        raise ConflictError(
            "image_upload_incomplete",
            "Upload the image content before finalizing it.",
        )
    if upload.version is None or upload.storage_key is None:
        raise RuntimeError("uploaded image has incomplete metadata")
    reference = ImageReference(id=upload.id, version=upload.version)
    moved_from: str | None = None
    moved_to: str | None = None
    if upload.state == "uploaded":
        extension = EXTENSIONS.get(upload.detected_mime_type or "")
        if extension is None:
            raise RuntimeError("uploaded image has unsupported metadata")
        destination = f"images/{upload.id}/{upload.version}.{extension}"
        moved_from = upload.storage_key
        moved_to = destination
        await storage.move(upload.storage_key, destination)
        upload.storage_key = destination
        upload.state = "finalized"
        upload.finalized_at = now
    session.add(
        IdempotencyKey(
            user_id=principal.user_id,
            operation="image.finalize",
            key=idempotency_key,
            request_fingerprint=fingerprint,
            response_status=200,
            response_body=reference.model_dump(mode="json"),
            expires_at=now + timedelta(hours=settings.idempotency_ttl_hours),
        )
    )
    try:
        await session.commit()
    except SQLAlchemyError:
        if moved_from is not None and moved_to is not None:
            await storage.move(moved_to, moved_from)
        raise
    return reference, False


async def image_references_by_listing(
    session: AsyncSession,
    listing_ids: list[UUID],
) -> dict[UUID, list[ImageReference]]:
    if not listing_ids:
        return {}
    rows = (
        await session.execute(
            select(ListingImage.listing_id, ImageUpload.id, ImageUpload.version)
            .join(ImageUpload, ImageUpload.id == ListingImage.image_upload_id)
            .where(ListingImage.listing_id.in_(listing_ids))
            .order_by(ListingImage.listing_id, ListingImage.position)
        )
    ).all()
    result: dict[UUID, list[ImageReference]] = {}
    for listing_id, image_id, version in rows:
        if version is None:
            continue
        result.setdefault(listing_id, []).append(
            ImageReference(id=image_id, version=version)
        )
    return result


async def redeem_listing_images(
    session: AsyncSession,
    principal: Principal,
    listing_id: UUID,
    references: list[ImageReference],
) -> None:
    image_ids = [reference.id for reference in references]
    if len(set(image_ids)) != len(image_ids):
        raise ValidationError(
            "listing_images_duplicated",
            "A listing cannot contain the same image more than once.",
        )
    uploads: dict[UUID, ImageUpload] = {}
    if image_ids:
        locked = await session.scalars(
            select(ImageUpload)
            .where(ImageUpload.id.in_(sorted(image_ids)))
            .with_for_update()
        )
        uploads = {upload.id: upload for upload in locked}
    now = datetime.now(UTC)
    previous_image_ids = set(
        await session.scalars(
            select(ListingImage.image_upload_id).where(
                ListingImage.listing_id == listing_id
            )
        )
    )
    for reference in references:
        upload = uploads.get(reference.id)
        if upload is None or upload.version != reference.version:
            raise ValidationError(
                "image_reference_invalid",
                "An image reference is invalid.",
            )
        if upload.owner_id != principal.user_id:
            raise ForbiddenError("An image belongs to another account.")
        if upload.state == "expired" or (
            upload.state != "redeemed" and upload.expires_at <= now
        ):
            raise ImageUploadExpiredError()
        if upload.state == "redeemed" and upload.redeemed_listing_id != listing_id:
            raise ConflictError(
                "image_reference_redeemed",
                "An image reference was already used by another listing.",
            )
        if upload.state not in {"finalized", "redeemed"}:
            raise ConflictError(
                "image_upload_incomplete",
                "An image must be finalized before use.",
            )
    await session.execute(
        delete(ListingImage).where(ListingImage.listing_id == listing_id)
    )
    detached_ids = previous_image_ids - set(image_ids)
    if detached_ids:
        detached_uploads = await session.scalars(
            select(ImageUpload)
            .where(ImageUpload.id.in_(detached_ids))
            .with_for_update()
        )
        for upload in detached_uploads:
            upload.state = "finalized"
            upload.redeemed_listing_id = None
            upload.expires_at = now
    for position, reference in enumerate(references):
        upload = uploads[reference.id]
        upload.state = "redeemed"
        upload.redeemed_listing_id = listing_id
        session.add(
            ListingImage(
                listing_id=listing_id,
                image_upload_id=reference.id,
                position=position,
            )
        )
    await session.flush()


async def release_listing_images(
    session: AsyncSession,
    listing_id: UUID,
) -> None:
    upload_ids = list(
        await session.scalars(
            select(ListingImage.image_upload_id).where(
                ListingImage.listing_id == listing_id
            )
        )
    )
    if not upload_ids:
        return
    uploads = await session.scalars(
        select(ImageUpload).where(ImageUpload.id.in_(upload_ids)).with_for_update()
    )
    now = datetime.now(UTC)
    for upload in uploads:
        upload.state = "finalized"
        upload.redeemed_listing_id = None
        upload.expires_at = now
    await session.execute(
        delete(ListingImage).where(ListingImage.listing_id == listing_id)
    )
    await session.flush()


async def read_image(
    session: AsyncSession,
    storage: ImageStorage,
    principal: Principal,
    image_id: UUID,
    version: str,
) -> tuple[bytes, str]:
    upload = await session.get(ImageUpload, image_id)
    if upload is None or upload.version != version or upload.storage_key is None:
        raise NotFoundError("image_not_found", "The image was not found.")
    if upload.state == "finalized":
        if upload.owner_id != principal.user_id:
            raise NotFoundError("image_not_found", "The image was not found.")
        await _require_not_expired(session, storage, upload)
    elif upload.state == "redeemed":
        if upload.redeemed_listing_id is None:
            raise RuntimeError("redeemed image has no listing")
        listing = await session.get(Listing, upload.redeemed_listing_id)
        if listing is None:
            raise NotFoundError("image_not_found", "The image was not found.")
        seller_status = await session.scalar(
            select(User.account_status).where(User.id == listing.owner_id)
        )
        if seller_status != "active":
            raise NotFoundError("image_not_found", "The image was not found.")
        association = await session.scalar(
            select(ListingImage.id).where(
                ListingImage.listing_id == listing.id,
                ListingImage.image_upload_id == upload.id,
            )
        )
        if association is None:
            raise NotFoundError("image_not_found", "The image was not found.")
        if listing.status == ListingStatus.removed.value:
            raise NotFoundError("image_not_found", "The image was not found.")
        if (
            listing.status == ListingStatus.hidden.value
            and listing.owner_id != principal.user_id
        ):
            raise NotFoundError("image_not_found", "The image was not found.")
    else:
        raise NotFoundError("image_not_found", "The image was not found.")
    try:
        content = await storage.read(upload.storage_key)
    except FileNotFoundError as exc:
        raise NotFoundError("image_not_found", "The image was not found.") from exc
    if upload.detected_mime_type is None:
        raise RuntimeError("stored image has no content type")
    return content, upload.detected_mime_type


async def expire_orphaned_uploads(
    session: AsyncSession,
    storage: ImageStorage,
    *,
    now: datetime | None = None,
    batch_size: int = 100,
) -> int:
    moment = now or datetime.now(UTC)
    uploads = list(
        await session.scalars(
            select(ImageUpload)
            .where(
                ImageUpload.state.in_(["pending", "uploaded", "finalized"]),
                ImageUpload.expires_at <= moment,
            )
            .order_by(ImageUpload.expires_at)
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        )
    )
    for upload in uploads:
        if upload.storage_key:
            await storage.delete(upload.storage_key)
        upload.state = "expired"
    await session.commit()
    return len(uploads)


async def _lock_upload(
    session: AsyncSession,
    principal: Principal,
    upload_id: UUID,
) -> None:
    scope = f"image-upload:{principal.user_id}:{upload_id}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(scope, 0)))
    )


async def _owned_upload(
    session: AsyncSession,
    principal: Principal,
    upload_id: UUID,
) -> ImageUpload:
    upload = await session.get(ImageUpload, upload_id)
    if upload is None:
        raise NotFoundError("image_upload_not_found", "The upload was not found.")
    if upload.owner_id != principal.user_id:
        raise ForbiddenError("The upload belongs to another account.")
    return upload


async def _require_not_expired(
    session: AsyncSession,
    storage: ImageStorage,
    upload: ImageUpload,
) -> None:
    if upload.state == "redeemed":
        return
    if upload.state == "expired" or upload.expires_at <= datetime.now(UTC):
        if upload.storage_key:
            await storage.delete(upload.storage_key)
        upload.state = "expired"
        await session.commit()
        raise ImageUploadExpiredError()


def _receipt(upload: ImageUpload) -> ImageUploadReceipt:
    if (
        upload.detected_mime_type is None
        or upload.byte_size is None
        or upload.width is None
        or upload.height is None
    ):
        raise RuntimeError("uploaded image has incomplete metadata")
    return ImageUploadReceipt(
        upload_id=upload.id,
        mime_type=upload.detected_mime_type,
        byte_size=upload.byte_size,
        width=upload.width,
        height=upload.height,
    )
