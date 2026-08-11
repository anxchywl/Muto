from __future__ import annotations

import struct
import zlib
from io import BytesIO

import pytest
from PIL import Image, PngImagePlugin

from app.domain.errors import ValidationError
from app.domain.images import MAX_IMAGE_BYTES, validate_upload_metadata
from app.infrastructure.storage.processing import normalize_image


def png_bytes(width: int = 300, height: int = 250) -> bytes:
    output = BytesIO()
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("private-note", "must not survive")
    Image.new("RGB", (width, height), "blue").save(
        output,
        format="PNG",
        pnginfo=metadata,
    )
    return output.getvalue()


def oversized_png_header(width: int = 8_000, height: int = 7_000) -> bytes:
    payload = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + payload
    return (
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", len(payload))
        + chunk
        + struct.pack(">I", zlib.crc32(chunk))
        + b"\x00\x00\x00\x00IEND\xaeB\x60\x82"
    )


def test_valid_image_is_decoded_reencoded_and_stripped_of_metadata() -> None:
    normalized = normalize_image(png_bytes(), "image/png")
    with Image.open(BytesIO(normalized.content)) as decoded:
        assert decoded.size == (300, 250)
        assert "private-note" not in decoded.info
    assert normalized.mime_type == "image/png"
    assert len(normalized.digest) == 64


@pytest.mark.parametrize(
    ("image_format", "mime_type"),
    [("JPEG", "image/jpeg"), ("WEBP", "image/webp")],
)
def test_supported_formats_are_normalized(
    image_format: str,
    mime_type: str,
) -> None:
    output = BytesIO()
    Image.new("RGB", (300, 250), "blue").save(output, format=image_format)
    normalized = normalize_image(output.getvalue(), mime_type)
    assert normalized.mime_type == mime_type


def test_animated_images_are_rejected() -> None:
    output = BytesIO()
    frames = [
        Image.new("RGB", (300, 250), "blue"),
        Image.new("RGB", (300, 250), "red"),
    ]
    frames[0].save(
        output,
        format="WEBP",
        save_all=True,
        append_images=frames[1:],
        duration=100,
    )
    with pytest.raises(ValidationError) as caught:
        normalize_image(output.getvalue(), "image/webp")
    assert caught.value.code == "image_animation_unsupported"


@pytest.mark.parametrize(
    ("content", "declared", "code"),
    [
        (b"not an image", "image/png", "image_content_invalid"),
        (png_bytes(), "image/jpeg", "image_type_mismatch"),
        (png_bytes(100, 100), "image/png", "image_dimensions_too_small"),
        (oversized_png_header(), "image/png", "image_dimensions_too_large"),
        (b"x" * (MAX_IMAGE_BYTES + 1), "image/png", "image_too_large"),
    ],
)
def test_invalid_images_return_stable_validation_codes(
    content: bytes,
    declared: str,
    code: str,
) -> None:
    with pytest.raises(ValidationError) as caught:
        normalize_image(content, declared)
    assert caught.value.code == code


def test_upload_metadata_is_allow_listed_and_bounded() -> None:
    validate_upload_metadata("image/png", 1)
    with pytest.raises(ValidationError) as unsupported:
        validate_upload_metadata("image/gif", 1)
    with pytest.raises(ValidationError) as oversized:
        validate_upload_metadata("image/png", MAX_IMAGE_BYTES + 1)
    assert unsupported.value.code == "image_type_unsupported"
    assert oversized.value.code == "image_size_invalid"
