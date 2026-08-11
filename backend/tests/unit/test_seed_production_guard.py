from __future__ import annotations

import pytest

from app.commands import seed
from app.config import Settings


@pytest.mark.asyncio
async def test_seed_command_is_blocked_in_production(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    production = Settings(
        APP_ENV="production",
        DATABASE_URL="postgresql+asyncpg://muto:muto@localhost:5432/muto",
        CURSOR_SECRET="test-cursor-secret-that-is-at-least-32-bytes",
    )
    monkeypatch.setattr(seed, "get_settings", lambda: production)

    with pytest.raises(RuntimeError, match="disabled in production"):
        await seed.run()
