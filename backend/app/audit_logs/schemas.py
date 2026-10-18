"""Audit-log read DTOs (§49 #39). Secrets never land in old/new values (§37)."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


class AuditLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    log_id: int
    actor_id: int | None = None
    action: str
    table_name: str
    record_id: str
    old_values: dict[str, Any] | None = None
    new_values: dict[str, Any] | None = None
    created_at: datetime


class AuditLogListItem(AuditLogResponse):
    """Cursor-list row — same shape, distinct name per §11."""
