from __future__ import annotations

import pytest

from app.application.cursors import CursorCodec
from app.domain.errors import ValidationError


def test_cursor_round_trips_opaque_payload() -> None:
    codec = CursorCodec("test-cursor-secret-that-is-at-least-32-bytes")
    encoded = codec.encode({"f": "filters", "v": "value", "id": "identifier"})
    assert "filters" not in encoded
    assert codec.decode(encoded) == {
        "f": "filters",
        "v": "value",
        "id": "identifier",
    }


def test_cursor_rejects_tampering_and_malformed_input() -> None:
    codec = CursorCodec("test-cursor-secret-that-is-at-least-32-bytes")
    encoded = codec.encode({"f": "filters"})
    with pytest.raises(ValidationError):
        codec.decode(encoded[:-1] + ("A" if encoded[-1] != "A" else "B"))
    with pytest.raises(ValidationError):
        codec.decode("not-a-valid-cursor")
