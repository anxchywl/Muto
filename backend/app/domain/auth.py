from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol
from uuid import UUID


class AccountStatus(StrEnum):
    active = "active"
    suspended = "suspended"


@dataclass(frozen=True, slots=True)
class ExternalIdentity:
    external_issuer: str
    external_subject: str
    is_verified: bool
    account_status: AccountStatus
    display_name: str | None = None
    telegram_username: str | None = None
    email: str | None = None
    phone: str | None = None
    is_admin: bool = False


@dataclass(frozen=True, slots=True)
class Principal:
    user_id: UUID
    is_verified: bool
    account_status: AccountStatus
    display_name: str | None = None
    telegram_username: str | None = None
    email: str | None = None
    phone: str | None = None
    is_admin: bool = False


class TokenIdentityResolver(Protocol):
    async def resolve(self, token: str) -> ExternalIdentity: ...
