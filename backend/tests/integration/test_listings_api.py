from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.schemas import ListingDraftRequest
from app.application.identity import resolve_principal
from app.application.listing_service import create_listing as create_listing_record
from app.application.listing_service import update_listing
from app.config import Settings
from app.domain.auth import AccountStatus, ExternalIdentity, Principal
from app.domain.errors import ConflictError, ForbiddenError
from app.infrastructure.db.models import Listing, User
from app.main import create_app

TOKEN = "integration-development-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def settings(*, subject: str = "student-a", verified: bool = True) -> Settings:
    return Settings(
        APP_ENV="test",
        DATABASE_URL=os.environ["TEST_DATABASE_URL"],
        CURSOR_SECRET="test-cursor-secret-that-is-at-least-32-bytes",
        AUTH_ADAPTER="development",
        DEVELOPMENT_AUTH_TOKEN=TOKEN,
        DEVELOPMENT_ADMIN_AUTH_TOKEN="test-admin-token",
        DEVELOPMENT_AUTH_SUBJECT=subject,
        DEVELOPMENT_AUTH_DISPLAY_NAME=subject.title(),
        DEVELOPMENT_AUTH_VERIFIED=verified,
        DEFAULT_PAGE_SIZE=1,
    )


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


def draft(title: str = "Desk lamp") -> dict[str, object]:
    return {
        "kind": "sale",
        "title": title,
        "description": "Works well",
        "condition": "good",
        "category": "dorm",
        "price_minor_units": 3000,
        "currency": "KZT",
        "images": [],
    }


def create_listing(
    client: TestClient,
    *,
    title: str = "Desk lamp",
    key: str = "listing-create-key-0001",
):
    return client.post(
        "/api/v1/listings",
        headers={**AUTH, "Idempotency-Key": key},
        json=draft(title),
    )


async def suspend_user(user_id: str) -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    async with engine.begin() as connection:
        await connection.execute(
            text("UPDATE users SET account_status = 'suspended' WHERE id = :user_id"),
            {"user_id": user_id},
        )
    await engine.dispose()


@pytest.mark.integration
def test_authentication_and_identity_resolution() -> None:
    with TestClient(create_app(settings())) as client:
        missing = client.get("/api/v1/me")
        first = client.get("/api/v1/me", headers=AUTH)
        second = client.get("/api/v1/me", headers=AUTH)
    assert missing.status_code == 401
    assert missing.json()["error"]["code"] == "authentication_required"
    assert first.status_code == 200
    assert first.json()["data"] == second.json()["data"]


@pytest.mark.integration
def test_create_is_verified_and_idempotent() -> None:
    with TestClient(create_app(settings())) as client:
        first = create_listing(client)
        retry = create_listing(client)
        changed = create_listing(client, title="Different lamp")
    assert first.status_code == 201
    assert first.json()["data"]["status"] == "active"
    assert first.json()["data"]["version"] == 1
    assert retry.status_code == 201
    assert retry.headers["Idempotent-Replayed"] == "true"
    assert retry.json()["data"] == first.json()["data"]
    assert changed.status_code == 409
    assert changed.json()["error"]["code"] == "idempotency_key_reused"


@pytest.mark.integration
def test_expired_idempotency_key_can_be_reused() -> None:
    async def expire_key() -> None:
        engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
        async with engine.begin() as connection:
            await connection.execute(
                text(
                    "UPDATE idempotency_keys "
                    "SET expires_at = :expired_at "
                    "WHERE key = :key"
                ),
                {
                    "expired_at": datetime.now(UTC) - timedelta(seconds=1),
                    "key": "listing-create-key-0001",
                },
            )
        await engine.dispose()

    with TestClient(create_app(settings())) as client:
        first = create_listing(client)
        asyncio.run(expire_key())
        after_expiry = create_listing(client, title="New intent after expiry")
    assert first.status_code == 201
    assert after_expiry.status_code == 201
    assert after_expiry.json()["data"]["id"] != first.json()["data"]["id"]


@pytest.mark.integration
def test_unverified_student_cannot_publish() -> None:
    with TestClient(create_app(settings(verified=False))) as client:
        response = create_listing(client)
    assert response.status_code == 403


@pytest.mark.integration
def test_browse_uses_stable_validated_cursors_and_filters() -> None:
    with TestClient(create_app(settings())) as client:
        create_listing(client, title="Alpha lamp", key="listing-create-key-0001")
        create_listing(client, title="Beta lamp", key="listing-create-key-0002")
        first = client.get("/api/v1/listings?limit=1", headers=AUTH)
        cursor = first.json()["meta"]["next_cursor"]
        second = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={"limit": 1, "cursor": cursor},
        )
        malformed = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={"cursor": "bad-cursor"},
        )
        mismatch = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={"cursor": cursor, "category": "electronics"},
        )
        searched = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={"q": "alpha"},
        )
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["data"][0]["id"] != second.json()["data"][0]["id"]
    assert malformed.status_code == 422
    assert malformed.json()["error"]["code"] == "cursor_invalid"
    assert mismatch.status_code == 409
    assert searched.json()["data"][0]["title"] == "Alpha lamp"


@pytest.mark.integration
def test_suggestions_hide_suspended_sellers() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = create_listing(seller, title="Distinctive telescope").json()["data"]
    asyncio.run(suspend_user(listing["seller_id"]))

    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        response = buyer.get(
            "/api/v1/listings/suggestions",
            headers=AUTH,
            params={"prefix": "Distinctive"},
        )

    assert response.status_code == 200
    assert response.json()["data"] == []


@pytest.mark.integration
def test_browse_applies_structured_filters_and_price_ordering() -> None:
    expensive = draft("Expensive chair")
    expensive.update(
        category="furniture",
        condition="worn",
        price_minor_units=5000,
    )
    giveaway = draft("Free chair")
    giveaway.update(
        kind="giveaway",
        category="furniture",
        condition="worn",
        price_minor_units=None,
        currency=None,
    )
    with TestClient(create_app(settings())) as client:
        create_listing(client, title="Cheap lamp", key="listing-create-key-0001")
        client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0002"},
            json=expensive,
        )
        client.post(
            "/api/v1/listings",
            headers={**AUTH, "Idempotency-Key": "listing-create-key-0003"},
            json=giveaway,
        )
        ordered = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={
                "currency": "KZT",
                "sort": "price_ascending",
                "limit": 10,
            },
        )
        filtered = client.get(
            "/api/v1/listings",
            headers=AUTH,
            params={
                "category": "furniture",
                "kind": "sale",
                "condition": "worn",
                "currency": "KZT",
                "min_minor_units": 4000,
                "max_minor_units": 6000,
                "limit": 10,
            },
        )
    assert [item["title"] for item in ordered.json()["data"]] == [
        "Cheap lamp",
        "Expensive chair",
    ]
    assert [item["title"] for item in filtered.json()["data"]] == ["Expensive chair"]


@pytest.mark.integration
def test_ownership_versions_and_lifecycle_are_authoritative() -> None:
    with TestClient(create_app(settings())) as owner:
        created = create_listing(owner).json()["data"]
        listing_id = created["id"]
        updated = owner.patch(
            f"/api/v1/listings/{listing_id}",
            headers={**AUTH, "If-Match": '"1"'},
            json=draft("Updated lamp"),
        )
        stale = owner.patch(
            f"/api/v1/listings/{listing_id}",
            headers={**AUTH, "If-Match": '"1"'},
            json=draft("Stale lamp"),
        )
        sold = owner.patch(
            f"/api/v1/listings/{listing_id}/status",
            headers={
                **AUTH,
                "If-Match": '"2"',
                "Idempotency-Key": "listing-status-key-0001",
            },
            json={"status": "sold"},
        )
        sold_retry = owner.patch(
            f"/api/v1/listings/{listing_id}/status",
            headers={
                **AUTH,
                "If-Match": '"2"',
                "Idempotency-Key": "listing-status-key-0001",
            },
            json={"status": "sold"},
        )
        sold_edit = owner.patch(
            f"/api/v1/listings/{listing_id}",
            headers={**AUTH, "If-Match": '"3"'},
            json=draft("Cannot edit"),
        )
    with TestClient(create_app(settings(subject="student-b"))) as stranger:
        strangers_mine = stranger.get("/api/v1/me/listings", headers=AUTH)
        forbidden = stranger.patch(
            f"/api/v1/listings/{listing_id}/status",
            headers={
                **AUTH,
                "If-Match": '"3"',
                "Idempotency-Key": "listing-status-key-0002",
            },
            json={"status": "active"},
        )
    assert updated.status_code == 200
    assert updated.json()["data"]["version"] == 2
    assert stale.status_code == 409
    assert stale.json()["error"]["details"]["current_version"] == 2
    assert sold.status_code == 200
    assert sold_retry.headers["Idempotent-Replayed"] == "true"
    assert sold_edit.status_code == 409
    assert strangers_mine.json()["data"] == []
    assert forbidden.status_code == 403


@pytest.mark.integration
def test_hidden_and_removed_visibility_is_deliberate() -> None:
    with TestClient(create_app(settings())) as owner:
        listing_id = create_listing(owner).json()["data"]["id"]
        hidden = owner.patch(
            f"/api/v1/listings/{listing_id}/status",
            headers={
                **AUTH,
                "If-Match": '"1"',
                "Idempotency-Key": "listing-status-key-0001",
            },
            json={"status": "hidden"},
        )
        owner_detail = owner.get(f"/api/v1/listings/{listing_id}", headers=AUTH)
    with TestClient(create_app(settings(subject="student-b"))) as stranger:
        hidden_detail = stranger.get(f"/api/v1/listings/{listing_id}", headers=AUTH)
    with TestClient(create_app(settings())) as owner:
        removed = owner.delete(
            f"/api/v1/listings/{listing_id}",
            headers={
                **AUTH,
                "If-Match": '"2"',
                "Idempotency-Key": "listing-remove-key-0001",
            },
        )
        gone = owner.get(f"/api/v1/listings/{listing_id}", headers=AUTH)
    assert hidden.status_code == 200
    assert owner_detail.status_code == 200
    assert hidden_detail.status_code == 404
    assert removed.status_code == 200
    assert gone.status_code == 410


async def concurrent_principal(database_url: str) -> Principal:
    engine = create_async_engine(database_url)
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        user = User(display_name="Concurrent Student", is_verified=True)
        session.add(user)
        await session.commit()
    await engine.dispose()
    return Principal(
        user_id=user.id,
        display_name=user.display_name,
        is_verified=True,
        account_status=AccountStatus.active,
    )


@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_identical_creation_creates_one_listing() -> None:
    database_url = os.environ["TEST_DATABASE_URL"]
    principal = await concurrent_principal(database_url)
    engine = create_async_engine(database_url)
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    payload = ListingDraftRequest.model_validate(draft())

    async def submit() -> tuple[object, bool]:
        async with session_maker() as session:
            return await create_listing_record(
                session,
                principal,
                payload,
                "concurrent-create-key-0001",
                settings(),
            )

    first, second = await asyncio.gather(submit(), submit())
    await engine.dispose()
    assert first[0].id == second[0].id
    assert sorted([first[1], second[1]]) == [False, True]


@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_edits_do_not_silently_overwrite() -> None:
    database_url = os.environ["TEST_DATABASE_URL"]
    principal = await concurrent_principal(database_url)
    engine = create_async_engine(database_url)
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        listing, _ = await create_listing_record(
            session,
            principal,
            ListingDraftRequest.model_validate(draft()),
            "concurrent-create-key-0001",
            settings(),
        )

    async def edit(title: str) -> object:
        async with session_maker() as session:
            try:
                return await update_listing(
                    session,
                    principal,
                    listing.id,
                    ListingDraftRequest.model_validate(draft(title)),
                    1,
                )
            except ConflictError as error:
                return error

    results = await asyncio.gather(edit("First edit"), edit("Second edit"))
    await engine.dispose()
    assert sum(not isinstance(result, ConflictError) for result in results) == 1
    conflicts = [result for result in results if isinstance(result, ConflictError)]
    assert len(conflicts) == 1
    assert conflicts[0].code == "listing_version_conflict"


@pytest.mark.integration
@pytest.mark.asyncio
async def test_database_rejects_invalid_listing_invariants() -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        user = User(id=uuid4(), display_name="Constraint Student", is_verified=True)
        session.add(user)
        await session.flush()
        session.add(
            Listing(
                owner_id=user.id,
                title="Invalid sale",
                description="Missing its required price",
                category="dorm",
                kind="sale",
                condition="good",
                price_minor_units=None,
                currency=None,
            )
        )
        with pytest.raises(IntegrityError):
            await session.commit()
    await engine.dispose()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_identity_mapping_is_stable_and_concurrency_safe() -> None:
    database_url = os.environ["TEST_DATABASE_URL"]
    engine = create_async_engine(database_url)
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    identity = ExternalIdentity(
        external_issuer="integration-host",
        external_subject="stable-student-subject",
        display_name="Stable Student",
        is_verified=True,
        account_status=AccountStatus.active,
    )

    async def resolve() -> Principal:
        async with session_maker() as session:
            return await resolve_principal(session, identity)

    first, second = await asyncio.gather(resolve(), resolve())
    assert first.user_id == second.user_id

    suspended = ExternalIdentity(
        external_issuer=identity.external_issuer,
        external_subject=identity.external_subject,
        display_name=identity.display_name,
        is_verified=identity.is_verified,
        account_status=AccountStatus.suspended,
    )
    async with session_maker() as session:
        with pytest.raises(ForbiddenError):
            await resolve_principal(session, suspended)
    await engine.dispose()
