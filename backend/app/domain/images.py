from __future__ import annotations

from dataclasses import dataclass

from app.domain.errors import ValidationError

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MIN_IMAGE_DIMENSION = 200
MAX_IMAGE_PIXELS = 50_000_000
MAX_LISTING_IMAGES = 6
ALLOWED_IMAGE_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


@dataclass(frozen=True, slots=True)
class ValidatedImage:
    content: bytes
    mime_type: str
    width: int
    height: int
    digest: str
    extension: str


def validate_upload_metadata(mime_type: str, byte_length: int) -> None:
    if mime_type not in ALLOWED_IMAGE_MIME_TYPES:
        raise ValidationError(
            "image_type_unsupported",
            "The image type is not supported.",
        )
    if byte_length < 1 or byte_length > MAX_IMAGE_BYTES:
        raise ValidationError(
            "image_size_invalid",
            "The image size is outside the allowed range.",
        )
