from __future__ import annotations

import base64
import hashlib
import hmac
import json
from typing import Any

from app.domain.errors import ValidationError


class CursorCodec:
    def __init__(self, secret: str) -> None:
        self._secret = secret.encode()

    def encode(self, payload: dict[str, Any]) -> str:
        body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        signature = hmac.new(self._secret, body, hashlib.sha256).digest()
        return base64.urlsafe_b64encode(body + signature).decode().rstrip("=")

    def decode(self, cursor: str) -> dict[str, Any]:
        try:
            padded = cursor + "=" * (-len(cursor) % 4)
            raw = base64.urlsafe_b64decode(padded.encode())
            body, signature = raw[:-32], raw[-32:]
            expected = hmac.new(self._secret, body, hashlib.sha256).digest()
            if len(body) == 0 or not hmac.compare_digest(signature, expected):
                raise ValueError
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError
            return payload
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            raise ValidationError(
                "cursor_invalid",
                "The pagination cursor is invalid.",
            ) from exc
