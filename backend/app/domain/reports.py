from __future__ import annotations

from enum import StrEnum

from app.domain.errors import ValidationError


class ReportReason(StrEnum):
    prohibited = "prohibited"
    misleading = "misleading"
    offensive = "offensive"
    other = "other"


def validate_report(reason: ReportReason, note: str | None) -> None:
    if reason == ReportReason.other and note is None:
        raise ValidationError(
            "report_note_required",
            "A note is required for this report reason.",
        )
