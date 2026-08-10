from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.auth import AccountStatus, ExternalIdentity, Principal
from app.domain.errors import ForbiddenError
from app.infrastructure.db.models import User, UserIdentity


async def resolve_principal(
    session: AsyncSession,
    identity: ExternalIdentity,
) -> Principal:
    lock_key = f"identity:{identity.external_issuer}:{identity.external_subject}"
    await session.execute(
        select(func.pg_advisory_xact_lock(func.hashtextextended(lock_key, 0)))
    )
    mapped = await session.scalar(
        select(UserIdentity).where(
            UserIdentity.provider_issuer == identity.external_issuer,
            UserIdentity.provider_subject == identity.external_subject,
        )
    )
    if mapped is None:
        resolved_user = User(
            display_name=identity.display_name,
            is_verified=identity.is_verified,
            account_status=identity.account_status.value,
            telegram_username=identity.telegram_username,
            email=identity.email,
            phone=identity.phone,
        )
        session.add(resolved_user)
        await session.flush()
        session.add(
            UserIdentity(
                user_id=resolved_user.id,
                provider_issuer=identity.external_issuer,
                provider_subject=identity.external_subject,
            )
        )
    else:
        existing_user = await session.get(User, mapped.user_id)
        if existing_user is None:
            raise RuntimeError("identity mapping has no user")
        resolved_user = existing_user
        resolved_user.display_name = identity.display_name
        resolved_user.is_verified = identity.is_verified
        resolved_user.account_status = identity.account_status.value
        resolved_user.telegram_username = identity.telegram_username
        resolved_user.email = identity.email
        resolved_user.phone = identity.phone
    await session.commit()
    if resolved_user.account_status != AccountStatus.active.value:
        raise ForbiddenError("This account is suspended.")
    return Principal(
        user_id=resolved_user.id,
        is_verified=resolved_user.is_verified,
        account_status=AccountStatus(resolved_user.account_status),
        display_name=resolved_user.display_name,
        telegram_username=resolved_user.telegram_username,
        email=resolved_user.email,
        phone=resolved_user.phone,
        is_admin=identity.is_admin,
    )
