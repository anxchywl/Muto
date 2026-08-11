from __future__ import annotations

from uuid import uuid4

from app.api.schemas import ReportRequest


def test_report_note_is_normalized_before_its_length_is_checked() -> None:
    request = ReportRequest(
        listing_id=uuid4(),
        reason="misleading",
        note=f"context{' ' * 600}",
    )
    assert request.note == "context"
