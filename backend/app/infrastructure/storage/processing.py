from __future__ import annotations

import hashlib
import warnings
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from app.domain.errors import ValidationError
from app.domain.images import (
    ALLOWED_IMAGE_MIME_TYPES,
    MAX_IMAGE_BYTES,
    MAX_IMAGE_PIXELS,
    MIN_IMAGE_DIMENSION,
    ValidatedImage,
)

FORMAT_DETAILS = {
    "JPEG": ("image/jpeg", "jpg"),
    "PNG": ("image/png", "png"),
    "WEBP": ("image/webp", "webp"),
}
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS


def normalize_image(content: bytes, declared_mime_type: str) -> ValidatedImage:
    if len(content) > MAX_IMAGE_BYTES:
        raise ValidationError("image_too_large", "The image exceeds 5 MB.")
    if declared_mime_type not in ALLOWED_IMAGE_MIME_TYPES:
        raise ValidationError(
            "image_type_unsupported", "The image type is not supported."
        )
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(content)) as source:
                details = FORMAT_DETAILS.get(source.format or "")
                if details is None:
                    raise ValidationError(
                        "image_type_unsupported", "The image type is not supported."
                    )
                detected_mime_type, extension = details
                if detected_mime_type != declared_mime_type:
                    raise ValidationError(
                        "image_type_mismatch",
                        "The image content does not match its declared type.",
                    )
                if getattr(source, "is_animated", False):
                    raise ValidationError(
                        "image_animation_unsupported",
                        "Animated images are not supported.",
                    )
                width, height = source.size
                if width < MIN_IMAGE_DIMENSION or height < MIN_IMAGE_DIMENSION:
                    raise ValidationError(
                        "image_dimensions_too_small",
                        "The image dimensions are too small.",
                    )
                if width * height > MAX_IMAGE_PIXELS:
                    raise ValidationError(
                        "image_dimensions_too_large",
                        "The image has too many pixels.",
                    )
                source.load()
                normalized = ImageOps.exif_transpose(source)
                width, height = normalized.size
                output = BytesIO()
                if detected_mime_type == "image/jpeg":
                    normalized.convert("RGB").save(
                        output,
                        format="JPEG",
                        quality=88,
                        optimize=True,
                    )
                elif detected_mime_type == "image/png":
                    mode = "RGBA" if "A" in normalized.getbands() else "RGB"
                    normalized.convert(mode).save(output, format="PNG", optimize=True)
                else:
                    mode = "RGBA" if "A" in normalized.getbands() else "RGB"
                    normalized.convert(mode).save(
                        output,
                        format="WEBP",
                        quality=88,
                        method=6,
                    )
    except ValidationError:
        raise
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise ValidationError(
            "image_dimensions_too_large",
            "The image has too many pixels.",
        ) from exc
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ValidationError(
            "image_content_invalid",
            "The uploaded file is not a valid image.",
        ) from exc
    normalized_content = output.getvalue()
    if len(normalized_content) > MAX_IMAGE_BYTES:
        raise ValidationError(
            "image_too_large",
            "The normalized image exceeds 5 MB.",
        )
    return ValidatedImage(
        content=normalized_content,
        mime_type=detected_mime_type,
        width=width,
        height=height,
        digest=hashlib.sha256(normalized_content).hexdigest(),
        extension=extension,
    )
