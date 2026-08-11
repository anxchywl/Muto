from __future__ import annotations

import asyncio

from app.application.image_service import expire_orphaned_uploads
from app.config import get_settings
from app.infrastructure.db import Database
from app.infrastructure.storage import create_image_storage


async def run() -> int:
    settings = get_settings()
    database = Database(settings.database_url)
    storage = create_image_storage(settings)
    try:
        async with database.session_maker() as session:
            return await expire_orphaned_uploads(session, storage)
    finally:
        await database.close()


def main() -> None:
    expired = asyncio.run(run())
    print(f"expired image uploads: {expired}")


if __name__ == "__main__":
    main()
