from __future__ import annotations

import os

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://muto:muto@localhost:54321/muto",
)
os.environ.setdefault("CURSOR_SECRET", "test-cursor-secret-that-is-at-least-32-bytes")
