from __future__ import annotations

import os

import pytest
from sqlalchemy import inspect
from sqlalchemy.ext.asyncio import create_async_engine


@pytest.mark.integration
@pytest.mark.asyncio
async def test_initial_migration_creates_identity_tables() -> None:
    database_url = os.environ["TEST_DATABASE_URL"]
    engine = create_async_engine(database_url)
    async with engine.connect() as connection:
        table_names = await connection.run_sync(
            lambda sync_connection: inspect(sync_connection).get_table_names()
        )
    await engine.dispose()
    assert "users" in table_names
    assert "user_identities" in table_names
    assert "listings" in table_names
    assert "idempotency_keys" in table_names
    assert "favorites" in table_names
    assert "reports" in table_names
    assert "image_uploads" in table_names
    assert "listing_images" in table_names
