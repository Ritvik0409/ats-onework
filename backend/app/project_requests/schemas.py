"""Project-access DTOs — migration 0002 request lifecycle.

Employees request membership on a specific project (``POST
/projects/{id}/access-requests``); admins list and decide (approve =
insert into ``project_members`` with the org's default ``employee``
role). Requested project/rejecter context comes back so the UI can
render the queue without a second round-trip.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.core.constants import ProjectAccessStatus


class AccessDecisionRequest(BaseModel):
    """Body for access-request approve/reject."""

    model_config = ConfigDict(str_strip_whitespace=True)

    comment: str | None = Field(default=None, max_length=255)


class ProjectAccessResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    access_request_id: int
    project_id: int
    employee_id: int
    organization_id: int
    status: ProjectAccessStatus
    decided_by: int | None = None
    decision_comment: str | None = None
    requested_at: datetime
    decided_at: datetime | None = None
    updated_at: datetime
    employee_name: str | None = None
    employee_email: str | None = None
    project_name: str | None = None


class ProjectAccessListItem(ProjectAccessResponse):
    """Cursor-list row — same shape, distinct name per §11 DTO convention."""

    """Cursor-list row — same shape, distinct name per §11 DTO convention."""
