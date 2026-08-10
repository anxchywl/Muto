from __future__ import annotations

from hmac import compare_digest

from app.config import AuthAdapter, Settings
from app.domain.auth import (
    AccountStatus,
    ExternalIdentity,
    TokenIdentityResolver,
)
from app.domain.errors import UnauthorizedError


class UnavailableHostPrincipalResolver:
    async def resolve(self, token: str) -> ExternalIdentity:
        raise UnauthorizedError("The host authentication adapter is not configured.")


class DevelopmentPrincipalResolver:
    def __init__(self, settings: Settings) -> None:
        configured = settings.development_auth_token
        if configured is None:
            raise ValueError("development authentication token is missing")
        self._token = configured.get_secret_value()
        self._subject = settings.development_auth_subject
        self._display_name = settings.development_auth_display_name
        self._verified = settings.development_auth_verified
        admin_token = settings.development_admin_auth_token
        if admin_token is None:
            raise ValueError("development admin authentication token is missing")
        self._admin_token = admin_token.get_secret_value()
        self._admin_subject = settings.development_admin_auth_subject
        self._admin_display_name = settings.development_admin_auth_display_name

    async def resolve(self, token: str) -> ExternalIdentity:
        is_user = bool(token) and compare_digest(token, self._token)
        is_admin = bool(token) and compare_digest(token, self._admin_token)
        if not is_user and not is_admin:
            raise UnauthorizedError("The development authentication token is invalid.")
        return ExternalIdentity(
            external_issuer="muto-development",
            external_subject=self._admin_subject if is_admin else self._subject,
            is_verified=True if is_admin else self._verified,
            account_status=AccountStatus.active,
            display_name=self._admin_display_name if is_admin else self._display_name,
            is_admin=is_admin,
        )


def create_principal_resolver(settings: Settings) -> TokenIdentityResolver:
    if settings.auth_adapter == AuthAdapter.development:
        return DevelopmentPrincipalResolver(settings)
    return UnavailableHostPrincipalResolver()
