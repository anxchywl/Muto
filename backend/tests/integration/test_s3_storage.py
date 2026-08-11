from __future__ import annotations

import os
from uuid import uuid4

import boto3  # type: ignore[import-untyped]
import pytest

from app.infrastructure.storage.files import S3ImageStorage


@pytest.mark.integration
@pytest.mark.asyncio
async def test_real_s3_compatible_storage_round_trip() -> None:
    endpoint = os.environ.get("TEST_S3_ENDPOINT")
    if endpoint is None:
        pytest.skip("TEST_S3_ENDPOINT is not configured")
    access_key = os.environ["TEST_S3_ACCESS_KEY_ID"]
    secret_key = os.environ["TEST_S3_SECRET_ACCESS_KEY"]
    bucket = f"muto-test-{uuid4()}"
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name="us-east-1",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )
    client.create_bucket(Bucket=bucket)
    storage = S3ImageStorage(
        endpoint_url=endpoint,
        region="us-east-1",
        bucket=bucket,
        access_key_id=access_key,
        secret_access_key=secret_key,
        force_path_style=True,
    )
    try:
        await storage.probe()
        await storage.write("staged/image.webp", b"normalized")
        assert await storage.read("staged/image.webp") == b"normalized"
        await storage.move("staged/image.webp", "images/image/v1.webp")
        assert [item.key for item in await storage.list("images")] == [
            "images/image/v1.webp"
        ]
        await storage.delete("images/image/v1.webp")
        assert await storage.list("images") == []
    finally:
        client.delete_bucket(Bucket=bucket)
