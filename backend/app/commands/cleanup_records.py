from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete

from app.config import get_settings
from app.infrastructure.db import Database
from app.infrastructure.db.models import IdempotencyKey, ImageUpload, Report


async def run() -> tuple[int, int, int]:
    settings = get_settings()
    database = Database(settings.database_url)
    now = datetime.now(UTC)
    try:
        async with database.session_maker() as session:
            idempotency = await session.execute(
                delete(IdempotencyKey).where(IdempotencyKey.expires_at <= now)
            )
            uploads = await session.execute(
                delete(ImageUpload).where(
                    ImageUpload.state == "expired",
                    ImageUpload.updated_at
                    <= now - timedelta(days=settings.expired_upload_retention_days),
                )
            )
            reports = await session.execute(
                delete(Report).where(
                    Report.created_at
                    <= now - timedelta(days=settings.report_retention_days)
                )
            )
            await session.commit()
            return (
                _affected(idempotency),
                _affected(uploads),
                _affected(reports),
            )
    finally:
        await database.close()


def main() -> None:
    idempotency, uploads, reports = asyncio.run(run())
    print(
        "deleted records: "
        f"idempotency={idempotency} uploads={uploads} reports={reports}"
    )


def _affected(result: object) -> int:
    value = getattr(result, "rowcount", 0)
    return value if isinstance(value, int) else 0


if __name__ == "__main__":
    main()
