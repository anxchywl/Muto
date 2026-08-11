from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, desc, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.schemas import OperationalReportResponse
from app.application.cursors import CursorCodec
from app.config import Settings
from app.domain.errors import ConflictError
from app.infrastructure.db.models import Listing, Report


async def list_reports(
    session: AsyncSession,
    cursor: str | None,
    limit: int | None,
    settings: Settings,
) -> tuple[list[OperationalReportResponse], str | None]:
    page_size = min(limit or settings.default_page_size, settings.maximum_page_size)
    codec = CursorCodec(settings.cursor_secret.get_secret_value())
    payload = codec.decode(cursor) if cursor else None
    if payload is not None and payload.get("f") != "operations:reports":
        raise ConflictError(
            "cursor_filter_mismatch",
            "The cursor does not match this report feed.",
        )
    query = (
        select(Report, Listing)
        .join(Listing, Listing.id == Report.listing_id)
        .order_by(desc(Report.created_at), desc(Report.id))
    )
    if payload:
        moment = datetime.fromisoformat(str(payload["v"]))
        report_id = UUID(str(payload["id"]))
        query = query.where(
            or_(
                Report.created_at < moment,
                and_(Report.created_at == moment, Report.id < report_id),
            )
        )
    rows = list((await session.execute(query.limit(page_size + 1))).all())
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        last = rows[-1][0]
        next_cursor = codec.encode(
            {
                "f": "operations:reports",
                "v": last.created_at.isoformat(),
                "id": str(last.id),
            }
        )
    return (
        [
            OperationalReportResponse(
                id=report.id,
                listing_id=listing.id,
                listing_title=listing.title,
                listing_status=listing.status,
                reason=report.reason,
                note=report.note,
                created_at=report.created_at,
            )
            for report, listing in rows
        ],
        next_cursor,
    )
