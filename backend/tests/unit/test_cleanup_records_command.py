from __future__ import annotations

import pytest

from app.commands import cleanup_records


def test_cleanup_records_reports_each_retention_class(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    async def completed() -> tuple[int, int, int]:
        return 4, 3, 2

    monkeypatch.setattr(cleanup_records, "run", completed)
    cleanup_records.main()
    assert capsys.readouterr().out == (
        "deleted records: idempotency=4 uploads=3 reports=2\n"
    )
