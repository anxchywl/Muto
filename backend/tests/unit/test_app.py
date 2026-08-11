from __future__ import annotations

from collections.abc import Iterator

from fastapi import APIRouter, Request
from fastapi.testclient import TestClient

from app.config import Settings
from app.domain.errors import AppError
from app.main import create_app


def build_client(*, body_limit: int = 150_000) -> TestClient:
    settings = Settings(
        APP_ENV="test",
        DATABASE_URL="postgresql+asyncpg://muto:muto@localhost:5432/muto",
        CURSOR_SECRET="test-cursor-secret-that-is-at-least-32-bytes",
        REQUEST_BODY_MAX_BYTES=body_limit,
    )
    application = create_app(settings)
    test_router = APIRouter()

    @test_router.get("/api/v1/failure")
    async def failure() -> None:
        raise AppError(status_code=409, code="test_conflict", message="Conflict.")

    @test_router.post("/api/v1/body")
    async def body(request: Request) -> dict[str, int]:
        return {"size": len(await request.body())}

    @test_router.get("/api/v1/unexpected")
    async def unexpected() -> None:
        raise RuntimeError("private internal detail")

    application.include_router(test_router)
    return TestClient(application, raise_server_exceptions=False)


def test_liveness_returns_request_id_and_security_headers() -> None:
    with build_client() as client:
        response = client.get("/health/live", headers={"X-Request-ID": "test-123"})
    assert response.status_code == 200
    assert response.json() == {
        "data": {"status": "ok"},
        "meta": {"request_id": "test-123"},
    }
    assert response.headers["X-Request-ID"] == "test-123"
    assert response.headers["X-Content-Type-Options"] == "nosniff"


def test_invalid_request_id_is_replaced() -> None:
    with build_client() as client:
        response = client.get("/health/live", headers={"X-Request-ID": "bad id"})
    request_id = response.headers["X-Request-ID"]
    assert request_id != "bad id"
    assert response.json()["meta"]["request_id"] == request_id


def test_application_errors_have_the_stable_shape() -> None:
    with build_client() as client:
        response = client.get("/api/v1/failure")
    assert response.status_code == 409
    error = response.json()["error"]
    assert error["code"] == "test_conflict"
    assert error["message"] == "Conflict."
    assert error["request_id"] == response.headers["X-Request-ID"]
    assert response.headers["Cache-Control"] == "private, no-store"


def test_missing_routes_do_not_expose_framework_details() -> None:
    with build_client() as client:
        response = client.get("/missing")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "resource_not_found"
    assert "detail" not in response.json()


def test_unexpected_errors_do_not_expose_internal_details() -> None:
    with build_client() as client:
        response = client.get("/api/v1/unexpected")
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert "private internal detail" not in response.text
    assert response.json()["error"]["request_id"] == response.headers["X-Request-ID"]


def test_request_body_limit_uses_actual_bytes() -> None:
    with build_client(body_limit=1_024) as client:
        response = client.post(
            "/api/v1/body",
            content=b"x" * 1_025,
            headers={"Content-Type": "application/octet-stream"},
        )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_body_too_large"


def test_request_body_limit_stops_a_chunked_body() -> None:
    def chunks() -> Iterator[bytes]:
        yield b"x" * 700
        yield b"y" * 700

    with build_client(body_limit=1_024) as client:
        response = client.post(
            "/api/v1/body",
            content=chunks(),
            headers={"Content-Type": "application/octet-stream"},
        )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "request_body_too_large"
