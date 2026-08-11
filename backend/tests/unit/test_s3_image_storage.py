from __future__ import annotations

import io
from datetime import UTC, datetime

import pytest
from botocore.exceptions import ClientError

from app.domain.errors import ServiceUnavailableError
from app.infrastructure.storage.files import S3ImageStorage


class FakeS3Client:
    def __init__(self) -> None:
        self.objects: dict[tuple[str, str], bytes] = {}

    def head_bucket(self, **values: object) -> dict[str, object]:
        assert values["Bucket"] == "private-images"
        return {}

    def put_object(self, **values: object) -> dict[str, object]:
        key = (str(values["Bucket"]), str(values["Key"]))
        self.objects[key] = bytes(values["Body"])
        return {}

    def get_object(self, **values: object) -> dict[str, object]:
        key = (str(values["Bucket"]), str(values["Key"]))
        return {"Body": io.BytesIO(self.objects[key])}

    def copy_object(self, **values: object) -> dict[str, object]:
        source = values["CopySource"]
        assert isinstance(source, dict)
        source_key = (str(source["Bucket"]), str(source["Key"]))
        target_key = (str(values["Bucket"]), str(values["Key"]))
        self.objects[target_key] = self.objects[source_key]
        return {}

    def delete_object(self, **values: object) -> dict[str, object]:
        self.objects.pop((str(values["Bucket"]), str(values["Key"])), None)
        return {}

    def list_objects_v2(self, **values: object) -> dict[str, object]:
        prefix = str(values["Prefix"])
        return {
            "Contents": [
                {"Key": key, "LastModified": datetime(2026, 1, 1, tzinfo=UTC)}
                for bucket, key in self.objects
                if bucket == values["Bucket"] and key.startswith(prefix)
            ],
            "IsTruncated": False,
        }


def storage(client: object) -> S3ImageStorage:
    return S3ImageStorage(
        endpoint_url="https://storage.example.test",
        region="test",
        bucket="private-images",
        access_key_id="access",
        secret_access_key="secret",
        force_path_style=True,
        client=client,
    )


@pytest.mark.asyncio
async def test_s3_storage_writes_reads_moves_and_deletes_private_objects() -> None:
    client = FakeS3Client()
    adapter = storage(client)

    await adapter.probe()
    await adapter.write("staged/one.webp", b"safe-image")
    assert await adapter.read("staged/one.webp") == b"safe-image"

    await adapter.move("staged/one.webp", "images/one.webp")
    assert ("private-images", "staged/one.webp") not in client.objects
    assert await adapter.read("images/one.webp") == b"safe-image"
    assert [item.key for item in await adapter.list("images")] == ["images/one.webp"]

    await adapter.delete("images/one.webp")
    assert client.objects == {}


@pytest.mark.asyncio
@pytest.mark.parametrize("key", ["../secret", "/absolute", "a/./b", "a//b"])
async def test_s3_storage_rejects_client_controlled_keys(key: str) -> None:
    with pytest.raises(ValueError, match="invalid storage key"):
        await storage(FakeS3Client()).write(key, b"content")


class FailingS3Client(FakeS3Client):
    def put_object(self, **values: object) -> dict[str, object]:
        raise ClientError(
            {"Error": {"Code": "AccessDenied", "Message": "denied"}},
            "PutObject",
        )


class MissingS3Client(FakeS3Client):
    def get_object(self, **values: object) -> dict[str, object]:
        raise ClientError(
            {"Error": {"Code": "NoSuchKey", "Message": "missing"}},
            "GetObject",
        )


@pytest.mark.asyncio
async def test_s3_storage_hides_provider_errors() -> None:
    with pytest.raises(ServiceUnavailableError) as raised:
        await storage(FailingS3Client()).write("staged/one.webp", b"content")
    assert raised.value.code == "image_storage_unavailable"
    assert "denied" not in raised.value.message


@pytest.mark.asyncio
async def test_s3_storage_maps_missing_objects_without_leaking_provider_errors() -> (
    None
):
    with pytest.raises(FileNotFoundError):
        await storage(MissingS3Client()).read("images/missing.webp")
