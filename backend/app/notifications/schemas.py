"""Notifications owned by a user — typed rows (arch. doc §38).

Creation is service-driven: domain services call ``NotificationService.create``
(or the module-level convenience) inside their own workflow transaction; the
*read* endpoints (list / mark-read / read-all, §49 #36-38) land in Phase 4.7.
No HTTP lives here; dispatch to push/email providers goes through
``BackgroundTasks`` at the router layer (§38).
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class NotificationCreate(BaseModel):
    """Inputs a service supplies when raising a notification."""

    model_config = ConfigDict(str_strip_whitespace=True)

    employee_id: int = Field(gt=0)
    title: str = Field(min_length=1, max_length=150)
    message: str = Field(min_length=1)
    type: str = Field(min_length=1, max_length=50)
    reference_id: str | None = Field(default=None, max_length=50)


class NotificationResponse(BaseModel):
    """API shape of a notification row — §49 #36."""

    model_config = ConfigDict(from_attributes=True)

    notification_id: int
    employee_id: int
    title: str
    message: str
    type: str
    reference_id: str | None = None
    is_read: bool
    created_at: datetime


class NotificationListItem(NotificationResponse):
    """Cursor-list row — same shape, distinct name per §11 DTO convention."""
