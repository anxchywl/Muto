from __future__ import annotations

import pytest

from app.domain.errors import ValidationError
from app.domain.reports import ReportReason, validate_report


def test_other_report_reason_requires_a_note() -> None:
    with pytest.raises(ValidationError):
        validate_report(ReportReason.other, None)
    validate_report(ReportReason.other, "Additional context")


def test_fixed_report_reasons_do_not_require_a_note() -> None:
    for reason in (
        ReportReason.prohibited,
        ReportReason.misleading,
        ReportReason.offensive,
    ):
        validate_report(reason, None)
