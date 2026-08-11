from __future__ import annotations

import pytest

from app.commands import cleanup_images


def test_cleanup_command_reports_the_expired_count(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    async def completed() -> int:
        return 3

    monkeypatch.setattr(cleanup_images, "run", completed)
    cleanup_images.main()
    assert capsys.readouterr().out == "expired image uploads: 3\n"
