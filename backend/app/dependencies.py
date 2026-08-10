from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends, Header, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.identity import resolve_principal
from app.domain.auth import Principal, TokenIdentityResolver
from app.domain.errors import ForbiddenError, UnauthorizedError
from app.infrastructure.db.session import Database
from app.infrastructure.storage import ImageStorage


def database_from(request: Request) -> Database:
    return request.app.state.database


async def get_session(
    database: Annotated[Database, Depends(database_from)],
) -> AsyncIterator[AsyncSession]:
    async with database.session_maker() as session:
        yield session


def principal_resolver_from(request: Request) -> TokenIdentityResolver:
    return request.app.state.principal_resolver


def image_storage_from(request: Request) -> ImageStorage:
    return request.app.state.image_storage


async def require_principal(
    resolver: Annotated[TokenIdentityResolver, Depends(principal_resolver_from)],
    session: Annotated[AsyncSession, Depends(get_session)],
    authorization: Annotated[str | None, Header()] = None,
) -> Principal:
    if authorization is None or not authorization.startswith("Bearer "):
        raise UnauthorizedError()
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise UnauthorizedError()
    identity = await resolver.resolve(token)
    return await resolve_principal(session, identity)


async def require_admin(
    principal: Annotated[Principal, Depends(require_principal)],
) -> Principal:
    if not principal.is_admin:
        raise ForbiddenError("Operator access is required.")
    return principal


DatabaseSession = Annotated[AsyncSession, Depends(get_session)]
CurrentPrincipal = Annotated[Principal, Depends(require_principal)]
CurrentAdmin = Annotated[Principal, Depends(require_admin)]
ImageStorageDependency = Annotated[ImageStorage, Depends(image_storage_from)]
