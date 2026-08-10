from __future__ import annotations

from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class AppEnvironment(StrEnum):
    development = "development"
    test = "test"
    production = "production"


class AuthAdapter(StrEnum):
    host = "host"
    development = "development"


class StorageAdapter(StrEnum):
    unconfigured = "unconfigured"
    local = "local"
    s3 = "s3"


class Settings(BaseSettings):
    environment: AppEnvironment = Field(
        default=AppEnvironment.production,
        alias="APP_ENV",
    )
    database_url: str = Field(alias="DATABASE_URL")
    cursor_secret: SecretStr = Field(alias="CURSOR_SECRET", min_length=32)
    auth_adapter: AuthAdapter = Field(default=AuthAdapter.host, alias="AUTH_ADAPTER")
    development_auth_token: SecretStr | None = Field(
        default=None,
        alias="DEVELOPMENT_AUTH_TOKEN",
    )
    development_auth_subject: str = Field(
        default="student-a",
        alias="DEVELOPMENT_AUTH_SUBJECT",
        min_length=1,
        max_length=255,
    )
    development_auth_display_name: str = Field(
        default="Development Student",
        alias="DEVELOPMENT_AUTH_DISPLAY_NAME",
        min_length=1,
        max_length=255,
    )
    development_auth_verified: bool = Field(
        default=True,
        alias="DEVELOPMENT_AUTH_VERIFIED",
    )
    development_admin_auth_token: SecretStr | None = Field(
        default=None,
        alias="DEVELOPMENT_ADMIN_AUTH_TOKEN",
    )
    development_admin_auth_subject: str = Field(
        default="operator-a",
        alias="DEVELOPMENT_ADMIN_AUTH_SUBJECT",
        min_length=1,
        max_length=255,
    )
    development_admin_auth_display_name: str = Field(
        default="Development Operator",
        alias="DEVELOPMENT_ADMIN_AUTH_DISPLAY_NAME",
        min_length=1,
        max_length=255,
    )
    cors_allowed_origins: Annotated[list[str], NoDecode] = Field(
        default_factory=list,
        alias="CORS_ALLOWED_ORIGINS",
    )
    api_docs_enabled: bool = Field(default=False, alias="API_DOCS_ENABLED")
    request_body_max_bytes: int = Field(
        default=150_000,
        alias="REQUEST_BODY_MAX_BYTES",
        ge=1_024,
        le=10 * 1_024 * 1_024,
    )
    default_page_size: int = Field(default=8, alias="DEFAULT_PAGE_SIZE", ge=1, le=50)
    maximum_page_size: int = Field(default=50, alias="MAXIMUM_PAGE_SIZE", ge=1, le=100)
    idempotency_ttl_hours: int = Field(
        default=24,
        alias="IDEMPOTENCY_TTL_HOURS",
        ge=1,
        le=168,
    )
    report_burst_limit: int = Field(
        default=5,
        alias="REPORT_BURST_LIMIT",
        ge=1,
        le=20,
    )
    report_window_seconds: int = Field(
        default=600,
        alias="REPORT_WINDOW_SECONDS",
        ge=60,
        le=86_400,
    )
    storage_adapter: StorageAdapter = Field(
        default=StorageAdapter.unconfigured,
        alias="STORAGE_ADAPTER",
    )
    image_storage_root: Path | None = Field(
        default=None,
        alias="IMAGE_STORAGE_ROOT",
    )
    s3_endpoint_url: str | None = Field(default=None, alias="S3_ENDPOINT_URL")
    s3_region: str = Field(default="us-east-1", alias="S3_REGION", min_length=1)
    s3_bucket: str | None = Field(default=None, alias="S3_BUCKET")
    s3_access_key_id: SecretStr | None = Field(default=None, alias="S3_ACCESS_KEY_ID")
    s3_secret_access_key: SecretStr | None = Field(
        default=None,
        alias="S3_SECRET_ACCESS_KEY",
    )
    s3_force_path_style: bool = Field(default=False, alias="S3_FORCE_PATH_STYLE")
    image_upload_ttl_minutes: int = Field(
        default=60,
        alias="IMAGE_UPLOAD_TTL_MINUTES",
        ge=5,
        le=1_440,
    )
    image_upload_burst_limit: int = Field(
        default=30,
        alias="IMAGE_UPLOAD_BURST_LIMIT",
        ge=1,
        le=200,
    )
    image_upload_window_seconds: int = Field(
        default=3_600,
        alias="IMAGE_UPLOAD_WINDOW_SECONDS",
        ge=60,
        le=86_400,
    )
    expired_upload_retention_days: int = Field(
        default=30,
        alias="EXPIRED_UPLOAD_RETENTION_DAYS",
        ge=1,
        le=365,
    )
    report_retention_days: int = Field(
        default=365,
        alias="REPORT_RETENTION_DAYS",
        ge=30,
        le=2_555,
    )
    storage_orphan_grace_hours: int = Field(
        default=24,
        alias="STORAGE_ORPHAN_GRACE_HOURS",
        ge=1,
        le=168,
    )

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def parse_origins(cls, value: object) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(origin).strip() for origin in value if str(origin).strip()]
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        raise ValueError("CORS_ALLOWED_ORIGINS must be a comma-separated list")

    @model_validator(mode="after")
    def guard_development_features(self) -> Settings:
        if self.auth_adapter == AuthAdapter.development:
            if self.environment == AppEnvironment.production:
                raise ValueError("development authentication cannot run in production")
            if self.development_auth_token is None:
                raise ValueError(
                    "DEVELOPMENT_AUTH_TOKEN is required for development authentication"
                )
            if self.development_admin_auth_token is None:
                raise ValueError(
                    "DEVELOPMENT_ADMIN_AUTH_TOKEN is required for "
                    "development authentication"
                )
            if compare_secrets(
                self.development_auth_token,
                self.development_admin_auth_token,
            ):
                raise ValueError("development user and admin tokens must differ")
        if self.environment == AppEnvironment.production and self.api_docs_enabled:
            raise ValueError("API documentation cannot be enabled in production")
        if self.storage_adapter == StorageAdapter.local:
            if self.environment == AppEnvironment.production:
                raise ValueError("local image storage cannot run in production")
            if self.image_storage_root is None:
                raise ValueError(
                    "IMAGE_STORAGE_ROOT is required for local image storage"
                )
        if self.storage_adapter == StorageAdapter.s3:
            required = {
                "S3_ENDPOINT_URL": self.s3_endpoint_url,
                "S3_BUCKET": self.s3_bucket,
                "S3_ACCESS_KEY_ID": self.s3_access_key_id,
                "S3_SECRET_ACCESS_KEY": self.s3_secret_access_key,
            }
            missing = [name for name, value in required.items() if value is None]
            if missing:
                raise ValueError(f"missing S3 settings: {', '.join(missing)}")
            endpoint = urlsplit(self.s3_endpoint_url or "")
            if (
                endpoint.scheme != "https"
                and self.environment == AppEnvironment.production
            ):
                raise ValueError("S3_ENDPOINT_URL must use HTTPS in production")
        if "*" in self.cors_allowed_origins:
            raise ValueError("wildcard CORS origins are not allowed")
        for origin in self.cors_allowed_origins:
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.netloc
                or parsed.username is not None
                or parsed.password is not None
                or parsed.path
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError("CORS origins must be HTTP origins without paths")
        if self.default_page_size > self.maximum_page_size:
            raise ValueError("DEFAULT_PAGE_SIZE cannot exceed MAXIMUM_PAGE_SIZE")
        return self

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )


@lru_cache
def get_settings() -> Settings:
    return Settings.model_validate({})


def compare_secrets(left: SecretStr, right: SecretStr) -> bool:
    return left.get_secret_value() == right.get_secret_value()
