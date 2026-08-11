from __future__ import annotations

from pathlib import Path

import pytest

from app.domain.errors import ServiceUnavailableError
from app.infrastructure.storage.files import (
    LocalImageStorage,
    UnconfiguredImageStorage,
)


@pytest.mark.asyncio
async def test_local_storage_writes_moves_reads_and_deletes(tmp_path: Path) -> None:
    storage = LocalImageStorage(tmp_path)
    await storage.write("staged/image.png", b"content")
    assert await storage.read("staged/image.png") == b"content"
    await storage.move("staged/image.png", "images/image/v1.png")
    assert await storage.read("images/image/v1.png") == b"content"
    assert [item.key for item in await storage.list("images")] == [
        "images/image/v1.png"
    ]
    await storage.delete("images/image/v1.png")
    with pytest.raises(FileNotFoundError):
        await storage.read("images/image/v1.png")


@pytest.mark.asyncio
async def test_local_storage_rejects_path_traversal(tmp_path: Path) -> None:
    storage = LocalImageStorage(tmp_path)
    with pytest.raises(ValueError):
        await storage.write("../outside", b"content")


@pytest.mark.asyncio
async def test_unconfigured_storage_fails_closed() -> None:
    storage = UnconfiguredImageStorage()
    operations = [
        storage.write("key", b"content"),
        storage.read("key"),
        storage.move("source", "destination"),
        storage.delete("key"),
        storage.list("images"),
    ]
    for operation in operations:
        with pytest.raises(ServiceUnavailableError):
            await operation
