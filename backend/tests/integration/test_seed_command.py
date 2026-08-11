from __future__ import annotations

import os

import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.commands.seed import SELLER_ID, seed_synthetic_data
from app.infrastructure.db.models import Listing, User, UserIdentity


@pytest.mark.integration
@pytest.mark.asyncio
async def test_synthetic_seed_is_idempotent_and_contains_no_contact_data() -> None:
    engine = create_async_engine(os.environ["TEST_DATABASE_URL"])
    session_maker = async_sessionmaker(engine, expire_on_commit=False)
    async with session_maker() as session:
        await session.execute(delete(Listing).where(Listing.owner_id == SELLER_ID))
        await session.execute(
            delete(UserIdentity).where(
                UserIdentity.provider_issuer == "muto-synthetic-seed"
            )
        )
        await session.execute(delete(User).where(User.id == SELLER_ID))
        await session.commit()
        first = await seed_synthetic_data(session)
        second = await seed_synthetic_data(session)
        count = await session.scalar(select(func.count()).select_from(Listing))
        identity = await session.scalar(
            select(UserIdentity).where(
                UserIdentity.provider_issuer == "muto-synthetic-seed"
            )
        )
    await engine.dispose()
    assert first == 3
    assert second == 0
    assert count == 3
    assert identity is not None
    assert identity.provider_subject == "sample-seller"
