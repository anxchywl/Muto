from __future__ import annotations

import pytest

from app.commands import reconcile_storage


def test_reconcile_storage_reports_deleted_objects(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    async def completed() -> int:
        return 3

    monkeypatch.setattr(reconcile_storage, "run", completed)
    reconcile_storage.main()
    assert capsys.readouterr().out == "deleted untracked storage objects: 3\n"
