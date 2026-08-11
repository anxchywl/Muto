from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.infrastructure.db.models import ImageUpload
from app.infrastructure.storage import ImageStorage


async def delete_untracked_storage_objects(
    session: AsyncSession,
    storage: ImageStorage,
    *,
    grace_hours: int,
    now: datetime | None = None,
    batch_size: int = 100,
) -> int:
    tracked = set(
        await session.scalars(
            select(ImageUpload.storage_key).where(ImageUpload.storage_key.is_not(None))
        )
    )
    cutoff = (now or datetime.now(UTC)) - timedelta(hours=grace_hours)
    candidates = []
    for prefix in ("staged", "images"):
        for stored in await storage.list(prefix):
            if stored.key not in tracked and stored.last_modified <= cutoff:
                candidates.append(stored)
    candidates.sort(key=lambda item: (item.last_modified, item.key))
    for stored in candidates[:batch_size]:
        await storage.delete(stored.key)
    return min(len(candidates), batch_size)
