from __future__ import annotations

import asyncio
import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.api.schemas import ReportRequest
from app.application.community_service import submit_report
from app.config import Settings
from app.domain.auth import AccountStatus, Principal
from app.domain.errors import RateLimitedError
from app.infrastructure.db.models import Favorite, IdempotencyKey, Listing, Report, User
from app.main import create_app

TOKEN = "integration-development-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def settings(*, subject: str = "student-a") -> Settings:
    return Settings(
        APP_ENV="test",
        DATABASE_URL=os.environ["TEST_DATABASE_URL"],
        CURSOR_SECRET="test-cursor-secret-that-is-at-least-32-bytes",
        AUTH_ADAPTER="development",
        DEVELOPMENT_AUTH_TOKEN=TOKEN,
        DEVELOPMENT_ADMIN_AUTH_TOKEN="test-admin-token",
        DEVELOPMENT_AUTH_SUBJECT=subject,
        DEVELOPMENT_AUTH_DISPLAY_NAME=subject.title(),
        DEVELOPMENT_AUTH_VERIFIED=True,
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


def draft(title: str) -> dict[str, object]:
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


def publish(client: TestClient, title: str, key: str) -> dict[str, object]:
    response = client.post(
        "/api/v1/listings",
        headers={**AUTH, "Idempotency-Key": key},
        json=draft(title),
    )
    assert response.status_code == 201
    return response.json()["data"]


async def suspend_user(user_id: str) -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    async with engine.begin() as connection:
        await connection.execute(
            text("UPDATE users SET account_status = 'suspended' WHERE id = :user_id"),
            {"user_id": user_id},
        )
    await engine.dispose()


@pytest.mark.integration
def test_favorites_are_idempotent_paginated_and_account_isolated() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        first = publish(seller, "First favorite", "listing-create-key-0001")
        second = publish(seller, "Second favorite", "listing-create-key-0002")

    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        assert (
            buyer.put(f"/api/v1/favorites/{first['id']}", headers=AUTH).status_code
            == 200
        )
        assert (
            buyer.put(f"/api/v1/favorites/{first['id']}", headers=AUTH).status_code
            == 200
        )
        assert (
            buyer.put(f"/api/v1/favorites/{second['id']}", headers=AUTH).status_code
            == 200
        )
        saved = buyer.get("/api/v1/favorites/ids", headers=AUTH)
        page_one = buyer.get("/api/v1/favorites?limit=1", headers=AUTH)
        page_two = buyer.get(
            "/api/v1/favorites",
            headers=AUTH,
            params={"limit": 1, "cursor": page_one.json()["meta"]["next_cursor"]},
        )
        assert (
            buyer.delete(f"/api/v1/favorites/{first['id']}", headers=AUTH).status_code
            == 200
        )
        assert (
            buyer.delete(f"/api/v1/favorites/{first['id']}", headers=AUTH).status_code
            == 200
        )

    assert saved.status_code == 200
    assert set(saved.json()["data"]) == {first["id"], second["id"]}
    assert len(page_one.json()["data"]) == 1
    assert len(page_two.json()["data"]) == 1
    assert page_one.json()["data"][0]["contact"] is None

    with TestClient(create_app(settings(subject="other-buyer"))) as other:
        assert other.get("/api/v1/favorites/ids", headers=AUTH).json()["data"] == []


@pytest.mark.integration
def test_unavailable_favorites_leave_the_feed_but_keep_toggle_state() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Soon sold", "listing-create-key-0001")
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        buyer.put(f"/api/v1/favorites/{listing['id']}", headers=AUTH)
    with TestClient(create_app(settings(subject="seller"))) as seller:
        sold = seller.patch(
            f"/api/v1/listings/{listing['id']}/status",
            headers={
                **AUTH,
                "If-Match": '"1"',
                "Idempotency-Key": "listing-status-key-0001",
            },
            json={"status": "sold"},
        )
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        page = buyer.get("/api/v1/favorites", headers=AUTH)
        saved = buyer.get("/api/v1/favorites/ids", headers=AUTH)
    assert sold.status_code == 200
    assert page.json()["data"] == []
    assert saved.json()["data"] == [listing["id"]]


@pytest.mark.integration
def test_suspended_seller_listing_leaves_favorites_feed() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Suspended favorite", "listing-create-key-0001")
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        buyer.put(f"/api/v1/favorites/{listing['id']}", headers=AUTH)

    asyncio.run(suspend_user(str(listing["seller_id"])))

    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        page = buyer.get("/api/v1/favorites", headers=AUTH)
        saved = buyer.get("/api/v1/favorites/ids", headers=AUTH)

    assert page.status_code == 200
    assert page.json()["data"] == []
    assert saved.json()["data"] == [listing["id"]]


@pytest.mark.integration
def test_seller_profile_and_listings_expose_only_public_marketplace_data() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        active = publish(seller, "Still active", "listing-create-key-0001")
        sold = publish(seller, "Already sold", "listing-create-key-0002")
        seller_id = active["seller_id"]
        seller.patch(
            f"/api/v1/listings/{sold['id']}/status",
            headers={
                **AUTH,
                "If-Match": '"1"',
                "Idempotency-Key": "listing-status-key-0001",
            },
            json={"status": "sold"},
        )

    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        buyer_id = buyer.get("/api/v1/me", headers=AUTH).json()["data"]["user_id"]
        profile = buyer.get(f"/api/v1/sellers/{seller_id}", headers=AUTH)
        listings = buyer.get(f"/api/v1/sellers/{seller_id}/listings", headers=AUTH)
        unknown = buyer.get(f"/api/v1/sellers/{buyer_id}", headers=AUTH)
    assert profile.status_code == 200
    assert profile.json()["data"]["active_listing_count"] == 1
    assert profile.json()["data"]["is_verified"] is True
    assert "email" not in profile.json()["data"]
    assert [item["id"] for item in listings.json()["data"]] == [active["id"]]
    assert listings.json()["data"][0]["contact"] is None
    assert unknown.status_code == 404


@pytest.mark.integration
def test_seller_cursor_cannot_be_reused_in_the_main_feed() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        first = publish(seller, "Seller page one", "listing-create-key-0001")
        publish(seller, "Seller page two", "listing-create-key-0002")
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        seller_page = buyer.get(
            f"/api/v1/sellers/{first['seller_id']}/listings?limit=1",
            headers=AUTH,
        )
        mismatch = buyer.get(
            "/api/v1/listings",
            headers=AUTH,
            params={"cursor": seller_page.json()["meta"]["next_cursor"]},
        )
    assert seller_page.status_code == 200
    assert mismatch.status_code == 409


@pytest.mark.integration
def test_suspended_seller_content_is_not_publicly_enumerable() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Suspended seller item", "listing-create-key-0001")
    asyncio.run(suspend_user(str(listing["seller_id"])))

    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        feed = buyer.get("/api/v1/listings", headers=AUTH)
        detail = buyer.get(f"/api/v1/listings/{listing['id']}", headers=AUTH)
        profile = buyer.get(
            f"/api/v1/sellers/{listing['seller_id']}",
            headers=AUTH,
        )
        favorite = buyer.put(f"/api/v1/favorites/{listing['id']}", headers=AUTH)
        report = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
            json={"listing_id": listing["id"], "reason": "misleading"},
        )

    assert feed.json()["data"] == []
    assert detail.status_code == 404
    assert profile.status_code == 404
    assert favorite.status_code == 404
    assert report.status_code == 404


@pytest.mark.integration
def test_reports_are_private_idempotent_and_reject_self_reporting() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Report target", "listing-create-key-0001")
        own = seller.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
            json={"listing_id": listing["id"], "reason": "misleading"},
        )
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        first = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
            json={
                "listing_id": listing["id"],
                "reason": "misleading",
                "note": "  not what it says  ",
            },
        )
        retry = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
            json={
                "listing_id": listing["id"],
                "reason": "misleading",
                "note": "not what it says",
            },
        )
        changed = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
            json={"listing_id": listing["id"], "reason": "offensive"},
        )
        repeated_listing = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0002"},
            json={"listing_id": listing["id"], "reason": "offensive"},
        )
    assert own.status_code == 403
    assert first.status_code == 202
    assert first.json()["data"] == {"accepted": True}
    assert "reporter" not in first.text
    assert retry.headers["Idempotent-Replayed"] == "true"
    assert changed.status_code == 409
    assert repeated_listing.status_code == 202

    async def stored_reports() -> tuple[int, str | None]:
        engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
        session_maker = async_sessionmaker(engine, expire_on_commit=False)
        async with session_maker() as session:
            count = await session.scalar(select(func.count()).select_from(Report))
            note = await session.scalar(select(Report.note))
        await engine.dispose()
        return count or 0, note

    assert asyncio.run(stored_reports()) == (1, "not what it says")


@pytest.mark.integration
def test_only_admin_can_read_report_operations_without_reporter_identity() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Operations target", "listing-create-key-0001")
        second_listing = publish(
            seller, "Second operations target", "listing-create-key-0002"
        )
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        assert (
            buyer.post(
                "/api/v1/reports",
                headers={**AUTH, "Idempotency-Key": "report-request-key-0001"},
                json={
                    "listing_id": listing["id"],
                    "reason": "misleading",
                    "note": "Incorrect description",
                },
            ).status_code
            == 202
        )
        assert (
            buyer.post(
                "/api/v1/reports",
                headers={**AUTH, "Idempotency-Key": "report-request-key-0002"},
                json={"listing_id": second_listing["id"], "reason": "offensive"},
            ).status_code
            == 202
        )
        denied = buyer.get("/api/v1/operations/reports", headers=AUTH)
        allowed = buyer.get(
            "/api/v1/operations/reports",
            headers={"Authorization": "Bearer test-admin-token"},
            params={"limit": 1},
        )
        next_page = buyer.get(
            "/api/v1/operations/reports",
            headers={"Authorization": "Bearer test-admin-token"},
            params={"limit": 1, "cursor": allowed.json()["meta"]["next_cursor"]},
        )

    assert denied.status_code == 403
    assert allowed.status_code == 200
    assert len(allowed.json()["data"]) == 1
    assert len(next_page.json()["data"]) == 1
    assert {
        allowed.json()["data"][0]["listing_id"],
        next_page.json()["data"][0]["listing_id"],
    } == {listing["id"], second_listing["id"]}
    assert "reporter" not in allowed.text
    assert "reporter" not in next_page.text


@pytest.mark.integration
def test_report_validation_and_rate_limit_have_structured_errors() -> None:
    with TestClient(create_app(settings(subject="seller"))) as seller:
        listing = publish(seller, "Rate target", "listing-create-key-0001")
    with TestClient(create_app(settings(subject="buyer"))) as buyer:
        invalid = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0000"},
            json={"listing_id": listing["id"], "reason": "other"},
        )
        accepted = [
            buyer.post(
                "/api/v1/reports",
                headers={
                    **AUTH,
                    "Idempotency-Key": f"report-request-key-{index:04d}",
                },
                json={"listing_id": listing["id"], "reason": "misleading"},
            )
            for index in range(1, 6)
        ]
        limited = buyer.post(
            "/api/v1/reports",
            headers={**AUTH, "Idempotency-Key": "report-request-key-0006"},
            json={"listing_id": listing["id"], "reason": "misleading"},
        )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "report_note_required"
    assert all(response.status_code == 202 for response in accepted)
    assert limited.status_code == 429
    assert limited.json()["error"]["code"] == "report_rate_limited"
    assert int(limited.headers["Retry-After"]) > 0


async def report_fixture() -> tuple[
    AsyncEngine,
    async_sessionmaker[AsyncSession],
    Principal,
    ReportRequest,
]:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        reporter = User(display_name="Reporter", is_verified=True)
        owner = User(display_name="Owner", is_verified=True)
        session.add_all([reporter, owner])
        await session.flush()
        listing = Listing(
            owner_id=owner.id,
            title="Concurrent report target",
            description="Description",
            category="dorm",
            kind="sale",
            condition="good",
            price_minor_units=3000,
            currency="KZT",
        )
        session.add(listing)
        await session.commit()
    principal = Principal(
        user_id=reporter.id,
        display_name=reporter.display_name,
        is_verified=True,
        account_status=AccountStatus.active,
    )
    payload = ReportRequest(
        listing_id=listing.id,
        reason="misleading",
    )
    return engine, session_maker, principal, payload


@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_report_retry_is_recorded_once() -> None:
    engine, session_maker, principal, payload = await report_fixture()

    async def submit() -> tuple[dict[str, bool], bool]:
        async with session_maker() as session:
            return await submit_report(
                session,
                principal,
                payload,
                "concurrent-report-key-0001",
                settings(),
            )

    first, second = await asyncio.gather(submit(), submit())
    async with session_maker() as session:
        reports = await session.scalar(select(func.count()).select_from(Report))
        keys = await session.scalar(
            select(func.count())
            .select_from(IdempotencyKey)
            .where(IdempotencyKey.operation == "report.submit")
        )
    await engine.dispose()
    assert sorted([first[1], second[1]]) == [False, True]
    assert reports == 1
    assert keys == 1


@pytest.mark.integration
@pytest.mark.asyncio
async def test_database_enforces_unique_favorites() -> None:
    engine, session_maker, principal, payload = await report_fixture()
    async with session_maker() as session:
        session.add_all(
            [
                Favorite(user_id=principal.user_id, listing_id=payload.listing_id),
                Favorite(user_id=principal.user_id, listing_id=payload.listing_id),
            ]
        )
        with pytest.raises(IntegrityError):
            await session.commit()
    await engine.dispose()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_database_enforces_report_reason_invariants() -> None:
    engine, session_maker, principal, payload = await report_fixture()
    async with session_maker() as session:
        session.add(
            Report(
                reporter_id=principal.user_id,
                listing_id=payload.listing_id,
                reason="other",
                note=None,
            )
        )
        with pytest.raises(IntegrityError):
            await session.commit()
    await engine.dispose()


@pytest.mark.integration
@pytest.mark.asyncio
async def test_concurrent_reports_cannot_bypass_the_rate_limit() -> None:
    engine, session_maker, principal, payload = await report_fixture()

    async def submit(index: int) -> object:
        async with session_maker() as session:
            try:
                return await submit_report(
                    session,
                    principal,
                    payload,
                    f"concurrent-report-key-{index:04d}",
                    settings(),
                )
            except RateLimitedError as error:
                return error

    results = await asyncio.gather(*(submit(index) for index in range(6)))
    await engine.dispose()
    assert sum(isinstance(result, RateLimitedError) for result in results) == 1
    assert sum(not isinstance(result, RateLimitedError) for result in results) == 5
