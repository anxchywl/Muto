from __future__ import annotations

import asyncio

from app.application.storage_reconciliation import delete_untracked_storage_objects
from app.config import get_settings
from app.infrastructure.db import Database
from app.infrastructure.storage import create_image_storage


async def run() -> int:
    settings = get_settings()
    database = Database(settings.database_url)
    storage = create_image_storage(settings)
    try:
        async with database.session_maker() as session:
            return await delete_untracked_storage_objects(
                session,
                storage,
                grace_hours=settings.storage_orphan_grace_hours,
            )
    finally:
        await database.close()


def main() -> None:
    deleted = asyncio.run(run())
    print(f"deleted untracked storage objects: {deleted}")


if __name__ == "__main__":
    main()
