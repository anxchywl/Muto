from __future__ import annotations

import asyncio
import os
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any, Protocol

import boto3  # type: ignore[import-untyped]
from botocore.config import Config  # type: ignore[import-untyped]
from botocore.exceptions import (  # type: ignore[import-untyped]
    BotoCoreError,
    ClientError,
)

from app.config import Settings, StorageAdapter
from app.domain.errors import ServiceUnavailableError


class ImageStorage(Protocol):
    async def probe(self) -> None: ...

    async def write(self, key: str, content: bytes) -> None: ...

    async def read(self, key: str) -> bytes: ...

    async def move(self, source_key: str, destination_key: str) -> None: ...

    async def delete(self, key: str) -> None: ...

    async def list(self, prefix: str) -> list[StoredObject]: ...


@dataclass(frozen=True, slots=True)
class StoredObject:
    key: str
    last_modified: datetime


class UnconfiguredImageStorage:
    async def probe(self) -> None:
        raise _unavailable()

    async def write(self, key: str, content: bytes) -> None:
        raise _unavailable()

    async def read(self, key: str) -> bytes:
        raise _unavailable()

    async def move(self, source_key: str, destination_key: str) -> None:
        raise _unavailable()

    async def delete(self, key: str) -> None:
        raise _unavailable()

    async def list(self, prefix: str) -> list[StoredObject]:
        raise _unavailable()


class LocalImageStorage:
    def __init__(self, root: Path) -> None:
        self._root = root.expanduser().resolve()
        self._root.mkdir(parents=True, exist_ok=True)

    async def probe(self) -> None:
        if not await asyncio.to_thread(self._root.is_dir):
            raise _unavailable()

    def _path(self, key: str) -> Path:
        relative = PurePosixPath(key)
        if relative.is_absolute() or not relative.parts or ".." in relative.parts:
            raise ValueError("invalid storage key")
        resolved = self._root.joinpath(*relative.parts).resolve()
        if not resolved.is_relative_to(self._root):
            raise ValueError("invalid storage key")
        return resolved

    async def write(self, key: str, content: bytes) -> None:
        destination = self._path(key)

        def write_atomic() -> None:
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(dir=destination.parent)
            try:
                with os.fdopen(descriptor, "wb") as temporary:
                    temporary.write(content)
                    temporary.flush()
                    os.fsync(temporary.fileno())
                os.replace(temporary_name, destination)
            finally:
                if os.path.exists(temporary_name):
                    os.unlink(temporary_name)

        await asyncio.to_thread(write_atomic)

    async def read(self, key: str) -> bytes:
        return await asyncio.to_thread(self._path(key).read_bytes)

    async def move(self, source_key: str, destination_key: str) -> None:
        source = self._path(source_key)
        destination = self._path(destination_key)

        def move_atomic() -> None:
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(source, destination)

        await asyncio.to_thread(move_atomic)

    async def delete(self, key: str) -> None:
        path = self._path(key)

        def delete_if_present() -> None:
            try:
                path.unlink()
            except FileNotFoundError:
                return

        await asyncio.to_thread(delete_if_present)

    async def list(self, prefix: str) -> list[StoredObject]:
        root = self._path(prefix)

        def collect() -> list[StoredObject]:
            if not root.exists():
                return []
            return [
                StoredObject(
                    key=path.relative_to(self._root).as_posix(),
                    last_modified=datetime.fromtimestamp(path.stat().st_mtime, tz=UTC),
                )
                for path in root.rglob("*")
                if path.is_file()
            ]

        return await asyncio.to_thread(collect)


class S3ImageStorage:
    def __init__(
        self,
        *,
        endpoint_url: str,
        region: str,
        bucket: str,
        access_key_id: str,
        secret_access_key: str,
        force_path_style: bool,
        client: object | None = None,
    ) -> None:
        self._bucket = bucket
        self._client = client or boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            region_name=region,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path" if force_path_style else "virtual"},
                retries={"mode": "standard", "max_attempts": 3},
                connect_timeout=5,
                read_timeout=15,
            ),
        )

    async def probe(self) -> None:
        await self._call("head_bucket", Bucket=self._bucket)

    async def write(self, key: str, content: bytes) -> None:
        safe_key = _validated_key(key)
        await self._call(
            "put_object",
            Bucket=self._bucket,
            Key=safe_key,
            Body=content,
            ContentLength=len(content),
            ContentType="application/octet-stream",
        )

    async def read(self, key: str) -> bytes:
        response: Any = await self._call(
            "get_object",
            Bucket=self._bucket,
            Key=_validated_key(key),
        )
        body = response["Body"]
        return await asyncio.to_thread(body.read)

    async def move(self, source_key: str, destination_key: str) -> None:
        source = _validated_key(source_key)
        destination = _validated_key(destination_key)
        await self._call(
            "copy_object",
            Bucket=self._bucket,
            Key=destination,
            CopySource={"Bucket": self._bucket, "Key": source},
            MetadataDirective="COPY",
        )
        await self._call("delete_object", Bucket=self._bucket, Key=source)

    async def delete(self, key: str) -> None:
        await self._call(
            "delete_object",
            Bucket=self._bucket,
            Key=_validated_key(key),
        )

    async def list(self, prefix: str) -> list[StoredObject]:
        safe_prefix = _validated_key(prefix).rstrip("/") + "/"
        continuation: str | None = None
        objects: list[StoredObject] = []
        while True:
            arguments: dict[str, object] = {
                "Bucket": self._bucket,
                "Prefix": safe_prefix,
                "MaxKeys": 1_000,
            }
            if continuation is not None:
                arguments["ContinuationToken"] = continuation
            response: Any = await self._call("list_objects_v2", **arguments)
            for item in response.get("Contents", []):
                key = item.get("Key")
                modified = item.get("LastModified")
                if isinstance(key, str) and isinstance(modified, datetime):
                    objects.append(
                        StoredObject(key=key, last_modified=modified.astimezone(UTC))
                    )
            if not response.get("IsTruncated"):
                break
            continuation = response.get("NextContinuationToken")
            if not isinstance(continuation, str):
                raise _unavailable()
        return objects

    async def _call(self, method: str, **kwargs: object) -> object:
        try:
            operation = getattr(self._client, method)
            return await asyncio.to_thread(operation, **kwargs)
        except (BotoCoreError, ClientError) as error:
            if isinstance(error, ClientError) and method == "get_object":
                code = str(error.response.get("Error", {}).get("Code", ""))
                if code in {"NoSuchKey", "404", "NotFound"}:
                    raise FileNotFoundError from error
            raise _unavailable() from error


def create_image_storage(settings: Settings) -> ImageStorage:
    if settings.storage_adapter == StorageAdapter.local:
        if settings.image_storage_root is None:
            raise RuntimeError("local image storage has no root")
        return LocalImageStorage(settings.image_storage_root)
    if settings.storage_adapter == StorageAdapter.s3:
        if (
            settings.s3_endpoint_url is None
            or settings.s3_bucket is None
            or settings.s3_access_key_id is None
            or settings.s3_secret_access_key is None
        ):
            raise RuntimeError("S3 image storage is incomplete")
        return S3ImageStorage(
            endpoint_url=settings.s3_endpoint_url,
            region=settings.s3_region,
            bucket=settings.s3_bucket,
            access_key_id=settings.s3_access_key_id.get_secret_value(),
            secret_access_key=settings.s3_secret_access_key.get_secret_value(),
            force_path_style=settings.s3_force_path_style,
        )
    return UnconfiguredImageStorage()


def _validated_key(key: str) -> str:
    relative = PurePosixPath(key)
    if (
        relative.is_absolute()
        or not relative.parts
        or ".." in relative.parts
        or any(part in {"", "."} for part in relative.parts)
    ):
        raise ValueError("invalid storage key")
    normalized = relative.as_posix()
    if normalized != key or len(normalized) > 512:
        raise ValueError("invalid storage key")
    return normalized


def _unavailable() -> ServiceUnavailableError:
    return ServiceUnavailableError(
        "image_storage_unavailable",
        "Image storage is not configured.",
    )
