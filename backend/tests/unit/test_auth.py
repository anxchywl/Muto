from __future__ import annotations

import asyncio

import pytest

from app.config import Settings
from app.domain.errors import UnauthorizedError
from app.infrastructure.auth import create_principal_resolver


def settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "APP_ENV": "test",
        "DATABASE_URL": "postgresql+asyncpg://muto:muto@localhost:5432/muto",
        "CURSOR_SECRET": "test-cursor-secret-that-is-at-least-32-bytes",
    }
    values.update(overrides)
    return Settings(**values)


def test_host_authentication_fails_closed_until_configured() -> None:
    resolver = create_principal_resolver(settings())
    with pytest.raises(UnauthorizedError, match="not configured"):
        asyncio.run(resolver.resolve("unverified-host-token"))


def test_development_authentication_returns_a_stable_principal() -> None:
    resolver = create_principal_resolver(
        settings(
            AUTH_ADAPTER="development",
            DEVELOPMENT_AUTH_TOKEN="local-only",
            DEVELOPMENT_ADMIN_AUTH_TOKEN="admin-local-only",
            DEVELOPMENT_AUTH_SUBJECT="student-a",
        )
    )
    first = asyncio.run(resolver.resolve("local-only"))
    second = asyncio.run(resolver.resolve("local-only"))
    assert first == second
    assert first.external_subject == "student-a"
    assert first.is_verified is True


def test_development_authentication_rejects_another_token() -> None:
    resolver = create_principal_resolver(
        settings(
            AUTH_ADAPTER="development",
            DEVELOPMENT_AUTH_TOKEN="local-only",
            DEVELOPMENT_ADMIN_AUTH_TOKEN="admin-local-only",
        )
    )
    with pytest.raises(UnauthorizedError):
        asyncio.run(resolver.resolve("another-token"))


def test_development_admin_is_a_distinct_server_resolved_identity() -> None:
    resolver = create_principal_resolver(
        settings(
            AUTH_ADAPTER="development",
            DEVELOPMENT_AUTH_TOKEN="local-only",
            DEVELOPMENT_ADMIN_AUTH_TOKEN="admin-local-only",
            DEVELOPMENT_ADMIN_AUTH_SUBJECT="operator-a",
        )
    )
    student = asyncio.run(resolver.resolve("local-only"))
    admin = asyncio.run(resolver.resolve("admin-local-only"))
    assert student.is_admin is False
    assert admin.is_admin is True
    assert admin.external_subject == "operator-a"
