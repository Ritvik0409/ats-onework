"""Shared pagination (arch. doc §21).

- ``CursorParams``/``Page`` — cursor (keyset) pagination for high-volume
  tables: expenses, audit logs, notifications, approvals.
- ``OffsetParams`` — limit/offset for small admin reference lists only.

The cursor encodes the keyset position (e.g. ``created_at`` + ``id``) as
opaque base64url JSON; repositories translate it into ``WHERE`` predicates.
"""

from __future__ import annotations

import base64
import json

from pydantic import BaseModel, Field

from app.core.constants import DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE


class Page[T: BaseModel](BaseModel):
    """Standard list response envelope (§49)."""

    items: list[T]
    next_cursor: str | None = None


class CursorParams(BaseModel):
    limit: int = Field(default=DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE)
    cursor: str | None = Field(default=None, description="Opaque cursor from next_cursor")


class OffsetParams(BaseModel):
    limit: int = Field(default=DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE)
    offset: int = Field(default=0, ge=0)


def encode_cursor(**key_values: object) -> str:
    """Encode a keyset position into an opaque cursor string."""
    raw = json.dumps(key_values, separators=(",", ":"), default=str).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii")


def decode_cursor(cursor: str) -> dict:
    """Decode an opaque cursor back into its keyset values.

    Raises ``ValueError`` on malformed cursors — endpoints translate that
    into a 422 ValidationError.
    """
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii"))
        data = json.loads(raw)
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        msg = "Invalid pagination cursor."
        raise ValueError(msg) from exc
    if not isinstance(data, dict):
        msg = "Invalid pagination cursor."
        raise ValueError(msg)
    return data
