from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.config import AuthAdapter, Settings


def settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "APP_ENV": "test",
        "DATABASE_URL": "postgresql+asyncpg://muto:muto@localhost:5432/muto",
        "CURSOR_SECRET": "test-cursor-secret-that-is-at-least-32-bytes",
    }
    values.update(overrides)
    return Settings(**values)


def test_secure_defaults_use_host_authentication() -> None:
    configured = settings()
    assert configured.auth_adapter == AuthAdapter.host
    assert configured.api_docs_enabled is False
    assert configured.cors_allowed_origins == []


def test_development_authentication_is_rejected_in_production() -> None:
    with pytest.raises(ValidationError, match="cannot run in production"):
        settings(
            APP_ENV="production",
            AUTH_ADAPTER="development",
            DEVELOPMENT_AUTH_TOKEN="local-only",
            DEVELOPMENT_ADMIN_AUTH_TOKEN="admin-local-only",
        )


def test_development_authentication_requires_a_token() -> None:
    with pytest.raises(ValidationError, match="DEVELOPMENT_AUTH_TOKEN"):
        settings(AUTH_ADAPTER="development")


def test_development_authentication_requires_distinct_admin_token() -> None:
    with pytest.raises(ValidationError, match="DEVELOPMENT_ADMIN_AUTH_TOKEN"):
        settings(AUTH_ADAPTER="development", DEVELOPMENT_AUTH_TOKEN="local-only")
    with pytest.raises(ValidationError, match="must differ"):
        settings(
            AUTH_ADAPTER="development",
            DEVELOPMENT_AUTH_TOKEN="same-token",
            DEVELOPMENT_ADMIN_AUTH_TOKEN="same-token",
        )


def test_production_rejects_api_documentation() -> None:
    with pytest.raises(ValidationError, match="documentation"):
        settings(APP_ENV="production", API_DOCS_ENABLED=True)


def test_cors_origins_are_explicit_and_never_wildcarded() -> None:
    configured = settings(CORS_ALLOWED_ORIGINS="https://one.test, https://two.test")
    assert configured.cors_allowed_origins == [
        "https://one.test",
        "https://two.test",
    ]
    with pytest.raises(ValidationError, match="wildcard"):
        settings(CORS_ALLOWED_ORIGINS="*")
    with pytest.raises(ValidationError, match="without paths"):
        settings(CORS_ALLOWED_ORIGINS="https://student:secret@one.test/path")


def test_local_image_storage_is_development_only_and_requires_a_root() -> None:
    with pytest.raises(ValidationError, match="IMAGE_STORAGE_ROOT"):
        settings(STORAGE_ADAPTER="local")
    with pytest.raises(ValidationError, match="cannot run in production"):
        settings(
            APP_ENV="production",
            STORAGE_ADAPTER="local",
            IMAGE_STORAGE_ROOT="test-images",
        )


def test_production_s3_storage_requires_complete_https_configuration() -> None:
    with pytest.raises(ValidationError, match="missing S3 settings"):
        settings(APP_ENV="production", STORAGE_ADAPTER="s3")
    with pytest.raises(ValidationError, match="must use HTTPS"):
        settings(
            APP_ENV="production",
            STORAGE_ADAPTER="s3",
            S3_ENDPOINT_URL="http://storage.test",
            S3_BUCKET="private-images",
            S3_ACCESS_KEY_ID="access",
            S3_SECRET_ACCESS_KEY="secret",
        )
