from __future__ import annotations

import asyncio
import os
import struct
import zlib
from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.application.image_service import (
    expire_orphaned_uploads,
    finalize_image_upload,
)
from app.application.storage_reconciliation import delete_untracked_storage_objects
from app.config import Settings
from app.domain.auth import AccountStatus, Principal
from app.domain.images import MAX_IMAGE_BYTES
from app.infrastructure.db.models import ImageUpload, ListingImage, User
from app.infrastructure.storage.files import LocalImageStorage
from app.main import create_app

TOKEN = "integration-development-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def settings(
    storage_root: Path,
    *,
    subject: str = "student-a",
    **overrides: object,
) -> Settings:
    values: dict[str, object] = dict(
        APP_ENV="test",
        DATABASE_URL=os.environ["TEST_DATABASE_URL"],
        CURSOR_SECRET="test-cursor-secret-that-is-at-least-32-bytes",
        AUTH_ADAPTER="development",
        DEVELOPMENT_AUTH_TOKEN=TOKEN,
        DEVELOPMENT_ADMIN_AUTH_TOKEN="test-admin-token",
        DEVELOPMENT_AUTH_SUBJECT=subject,
        DEVELOPMENT_AUTH_DISPLAY_NAME=subject.title(),
        DEVELOPMENT_AUTH_VERIFIED=True,
        STORAGE_ADAPTER="local",
        IMAGE_STORAGE_ROOT=storage_root,
    )
    values.update(overrides)
    return Settings(**values)


async def clean_database() -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    async with engine.begin() as connection:
        await connection.execute(
            text(
                "TRUNCATE listing_images, image_uploads, reports, favorites, "
                "idempotency_keys, listings, user_identities, users CASCADE"
            )
        )
    await engine.dispose()


@pytest.fixture(autouse=True)
def clean_tables() -> None:
    asyncio.run(clean_database())


def image_bytes(
    *,
    image_format: str = "PNG",
    width: int = 300,
    height: int = 250,
) -> bytes:
    output = BytesIO()
    Image.new("RGB", (width, height), "blue").save(output, format=image_format)
    return output.getvalue()


def oversized_png_header() -> bytes:
    payload = struct.pack(">IIBBBBB", 8_000, 7_000, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + payload
    return (
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", len(payload))
        + chunk
        + struct.pack(">I", zlib.crc32(chunk))
        + b"\x00\x00\x00\x00IEND\xaeB\x60\x82"
    )


def create_slot(
    client: TestClient, content: bytes, mime_type: str = "image/png"
) -> dict[str, object]:
    response = client.post(
        "/api/v1/image-uploads",
        headers=AUTH,
        json={"mime_type": mime_type, "byte_length": len(content)},
    )
    assert response.status_code == 201
    return response.json()["data"]


def stage_image(
    client: TestClient,
    content: bytes,
    *,
    mime_type: str = "image/png",
    key: str = "image-finalize-key-0001",
) -> tuple[dict[str, object], dict[str, object]]:
    slot = create_slot(client, content, mime_type)
    uploaded = client.put(str(slot["upload_target"]), headers=AUTH, content=content)
    assert uploaded.status_code == 200
    finalized = client.post(
        f"/api/v1/image-uploads/{slot['upload_id']}/finalize",
        headers={**AUTH, "Idempotency-Key": key},
    )
    assert finalized.status_code == 200
    return slot, finalized.json()["data"]


def listing_draft(images: list[dict[str, object]]) -> dict[str, object]:
    return {
        "kind": "sale",
        "title": "Listing with image",
        "description": "Works well",
        "condition": "good",
        "category": "dorm",
        "price_minor_units": 3000,
        "currency": "KZT",
        "images": images,
    }


@pytest.mark.integration
def test_image_flow_reencodes_finalizes_redeems_and_controls_access(
    tmp_path: Path,
) -> None:
    content = image_bytes()
    with TestClient(create_app(settings(tmp_path, subject="seller"))) as seller:
        slot = create_slot(seller, content)
        uploaded = seller.put(str(slot["upload_target"]), headers=AUTH, content=content)
        upload_retry = seller.put(
            str(slot["upload_target"]), headers=AUTH, content=content
        )
        finalized = seller.post(
            f"/api/v1/image-uploads/{slot['upload_id']}/finalize",
            headers={**AUTH, "Idempotency-Key": "image-finalize-key-0001"},
        )
        finalize_retry = seller.post(
            f"/api/v1/image-uploads/{slot['upload_id']}/finalize",
            headers={**AUTH, "Idempotency-Key": "image-finalize-key-0001"},
        )
        reference = finalized.json()["data"]
        owner_preview = seller.get(
            f"/api/v1/images/{reference['id']}/{reference['version']}",
            headers=AUTH,
        )
        created = seller.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0001"},
            json=listing_draft([reference]),
        )
    assert uploaded.status_code == 200
    assert uploaded.json()["data"]["width"] == 300
    assert upload_retry.headers["Idempotent-Replayed"] == "true"
    assert finalize_retry.headers["Idempotent-Replayed"] == "true"
    assert owner_preview.status_code == 200
    assert owner_preview.headers["Content-Type"] == "image/png"
    assert created.status_code == 201
    assert created.json()["data"]["images"] == [reference]

    listing_id = created.json()["data"]["id"]
    with TestClient(create_app(settings(tmp_path, subject="buyer"))) as buyer:
        detail = buyer.get(f"/api/v1/listings/{listing_id}", headers=AUTH)
        image_list = buyer.get(f"/api/v1/listings/{listing_id}/images", headers=AUTH)
        public_image = buyer.get(
            f"/api/v1/images/{reference['id']}/{reference['version']}",
            headers=AUTH,
        )
    assert detail.json()["data"]["images"] == [reference]
    assert image_list.json()["data"] == [reference]
    assert public_image.status_code == 200
    assert public_image.headers["Cache-Control"] == (
        "private, max-age=31536000, immutable"
    )


@pytest.mark.integration
def test_upload_slots_are_rate_limited_per_account(tmp_path: Path) -> None:
    configured = settings(tmp_path, IMAGE_UPLOAD_BURST_LIMIT=1)
    content = image_bytes()
    with TestClient(create_app(configured)) as client:
        first = client.post(
            "/api/v1/image-uploads",
            headers=AUTH,
            json={"mime_type": "image/png", "byte_length": len(content)},
        )
        limited = client.post(
            "/api/v1/image-uploads",
            headers=AUTH,
            json={"mime_type": "image/png", "byte_length": len(content)},
        )
    assert first.status_code == 201
    assert limited.status_code == 429
    assert limited.json()["error"]["code"] == "image_upload_rate_limited"
    assert int(limited.headers["Retry-After"]) > 0


@pytest.mark.integration
def test_storage_reconciliation_deletes_only_old_untracked_objects(
    tmp_path: Path,
) -> None:
    old = tmp_path / "images" / "orphan" / "old.png"
    recent = tmp_path / "images" / "orphan" / "recent.png"
    old.parent.mkdir(parents=True)
    old.write_bytes(b"old")
    recent.write_bytes(b"recent")
    moment = datetime.now(UTC)
    old_time = (moment - timedelta(hours=25)).timestamp()
    os.utime(old, (old_time, old_time))

    async def reconcile() -> int:
        engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
        session_maker = async_sessionmaker(engine, expire_on_commit=False)
        async with session_maker() as session:
            deleted = await delete_untracked_storage_objects(
                session,
                LocalImageStorage(tmp_path),
                grace_hours=24,
                now=moment,
            )
        await engine.dispose()
        return deleted

    assert asyncio.run(reconcile()) == 1
    assert not old.exists()
    assert recent.exists()


@pytest.mark.integration
def test_removing_a_listing_releases_its_images_for_cleanup(tmp_path: Path) -> None:
    content = image_bytes()
    with TestClient(create_app(settings(tmp_path, subject="seller"))) as seller:
        _, reference = stage_image(seller, content)
        created = seller.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0001"},
            json=listing_draft([reference]),
        )
        removed = seller.delete(
            f"/api/v1/listings/{created.json()['data']['id']}",
            headers={
                **AUTH,
                "If-Match": '"1"',
                "Idempotency-Key": "listing-remove-key-0001",
            },
        )

    async def inspect_and_cleanup() -> tuple[str, int, int]:
        engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
        session_maker = async_sessionmaker(engine, expire_on_commit=False)
        storage = LocalImageStorage(tmp_path)
        async with session_maker() as session:
            upload = await session.get(ImageUpload, UUID(str(reference["id"])))
            assert upload is not None
            state = upload.state
            associations = len(list(await session.scalars(select(ListingImage.id))))
            expired = await expire_orphaned_uploads(session, storage)
        await engine.dispose()
        return state, associations, expired

    assert removed.status_code == 200
    assert asyncio.run(inspect_and_cleanup()) == ("finalized", 0, 1)
    with TestClient(create_app(settings(tmp_path, subject="seller"))) as seller:
        unavailable = seller.get(
            f"/api/v1/images/{reference['id']}/{reference['version']}",
            headers=AUTH,
        )
    assert unavailable.status_code == 404


@pytest.mark.integration
def test_unredeemed_image_is_private_and_finalization_requires_ownership(
    tmp_path: Path,
) -> None:
    content = image_bytes()
    with TestClient(create_app(settings(tmp_path, subject="seller"))) as seller:
        slot = create_slot(seller, content)
        seller.put(str(slot["upload_target"]), headers=AUTH, content=content)
        finalized = seller.post(
            f"/api/v1/image-uploads/{slot['upload_id']}/finalize",
            headers={**AUTH, "Idempotency-Key": "image-finalize-key-0001"},
        ).json()["data"]
    with TestClient(create_app(settings(tmp_path, subject="buyer"))) as buyer:
        unauthorized_upload = buyer.put(
            str(slot["upload_target"]), headers=AUTH, content=content
        )
        unauthorized_finalize = buyer.post(
            f"/api/v1/image-uploads/{slot['upload_id']}/finalize",
            headers={**AUTH, "Idempotency-Key": "image-finalize-key-0002"},
        )
        private_image = buyer.get(
            f"/api/v1/images/{finalized['id']}/{finalized['version']}",
            headers=AUTH,
        )
        forged_listing = buyer.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0001"},
            json=listing_draft([finalized]),
        )
    assert unauthorized_upload.status_code == 403
    assert unauthorized_finalize.status_code == 403
    assert private_image.status_code == 404
    assert forged_listing.status_code == 403


@pytest.mark.integration
@pytest.mark.parametrize(
    ("content", "mime_type", "code"),
    [
        (b"not an image", "image/png", "image_content_invalid"),
        (image_bytes(image_format="JPEG"), "image/png", "image_type_mismatch"),
        (image_bytes(width=100, height=100), "image/png", "image_dimensions_too_small"),
        (oversized_png_header(), "image/png", "image_dimensions_too_large"),
    ],
)
def test_invalid_image_content_is_rejected(
    tmp_path: Path,
    content: bytes,
    mime_type: str,
    code: str,
) -> None:
    with TestClient(create_app(settings(tmp_path))) as client:
        slot = create_slot(client, content, mime_type)
        response = client.put(str(slot["upload_target"]), headers=AUTH, content=content)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == code


@pytest.mark.integration
def test_oversized_upload_is_stopped_by_the_request_limit(tmp_path: Path) -> None:
    with TestClient(create_app(settings(tmp_path))) as client:
        response = client.put(
            "/api/v1/image-uploads/00000000-0000-0000-0000-000000000001/content",
            headers=AUTH,
            content=b"x" * (MAX_IMAGE_BYTES + 1),
        )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_body_too_large"


@pytest.mark.integration
def test_removing_an_image_from_a_listing_revokes_its_url(tmp_path: Path) -> None:
    with TestClient(create_app(settings(tmp_path))) as client:
        _, reference = stage_image(client, image_bytes())
        created = client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0001"},
            json=listing_draft([reference]),
        ).json()["data"]
        updated = client.patch(
            f"/api/v1/listings/{created['id']}",
            headers={**AUTH, "If-Match": '"1"'},
            json=listing_draft([]),
        )
        removed_image = client.get(
            f"/api/v1/images/{reference['id']}/{reference['version']}",
            headers=AUTH,
        )
    assert updated.status_code == 200
    assert updated.json()["data"]["images"] == []
    assert removed_image.status_code == 410


@pytest.mark.integration
def test_image_reference_is_single_use_and_listing_images_are_bounded(
    tmp_path: Path,
) -> None:
    with TestClient(create_app(settings(tmp_path))) as client:
        _, reference = stage_image(client, image_bytes())
        first = client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0001"},
            json=listing_draft([reference]),
        )
        reused = client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0002"},
            json=listing_draft([reference]),
        )
        duplicated = client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0003"},
            json=listing_draft([reference, reference]),
        )
        too_many = client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0004"},
            json=listing_draft([reference] * 7),
        )
    assert first.status_code == 201
    assert reused.status_code == 409
    assert reused.json()["error"]["code"] == "image_reference_redeemed"
    assert duplicated.status_code == 422
    assert duplicated.json()["error"]["code"] == "listing_images_duplicated"
    assert too_many.status_code == 422


@pytest.mark.integration
@pytest.mark.asyncio
async def test_expired_unredeemed_upload_is_deleted(tmp_path: Path) -> None:
    content = image_bytes()
    with TestClient(create_app(settings(tmp_path))) as client:
        slot, _ = stage_image(client, content)

    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        upload = await session.get(ImageUpload, UUID(str(slot["upload_id"])))
        assert upload is not None
        storage_key = upload.storage_key
        upload.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await session.commit()
    storage = LocalImageStorage(tmp_path)
    async with session_maker() as session:
        expired = await expire_orphaned_uploads(session, storage)
    async with session_maker() as session:
        upload = await session.get(ImageUpload, UUID(str(slot["upload_id"])))
        assert upload is not None
        assert upload.state == "expired"
    await engine.dispose()
    assert expired == 1
    assert storage_key is not None
    with pytest.raises(FileNotFoundError):
        await storage.read(storage_key)


@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_finalization_moves_content_once(tmp_path: Path) -> None:
    content = image_bytes()
    with TestClient(create_app(settings(tmp_path))) as client:
        identity = client.get("/api/v1/me", headers=AUTH).json()["data"]
        slot = create_slot(client, content)
        client.put(str(slot["upload_target"]), headers=AUTH, content=content)

    principal = Principal(
        user_id=UUID(identity["user_id"]),
        display_name=identity["display_name"],
        is_verified=True,
        account_status=AccountStatus.active,
    )
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    storage = LocalImageStorage(tmp_path)

    async def finalize() -> tuple[object, bool]:
        async with session_maker() as session:
            return await finalize_image_upload(
                session,
                storage,
                principal,
                UUID(str(slot["upload_id"])),
                "concurrent-image-finalize-key",
                settings(tmp_path),
            )

    first, second = await asyncio.gather(finalize(), finalize())
    await engine.dispose()
    assert first[0] == second[0]
    assert sorted([first[1], second[1]]) == [False, True]


@pytest.mark.integration
@pytest.mark.asyncio
async def test_database_rejects_completed_upload_without_metadata() -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        user = User(display_name="Image owner", is_verified=True)
        session.add(user)
        await session.flush()
        session.add(
            ImageUpload(
                owner_id=user.id,
                state="uploaded",
                declared_mime_type="image/png",
                declared_byte_length=100,
                expires_at=datetime.now(UTC) + timedelta(hours=1),
            )
        )
        with pytest.raises(IntegrityError):
            await session.commit()
    await engine.dispose()
