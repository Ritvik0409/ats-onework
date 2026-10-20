"""Project DTOs (§49 #22-24 + member management).

``budget_amount`` and ``member_count`` are computed aggregates — the
budget row owns the amount; members live in the join table.
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class ProjectCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    budget_id: int = Field(gt=0)
    name: str = Field(min_length=1, max_length=150)
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None


class ProjectUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = None
    is_active: bool | None = None
    start_date: date | None = None
    end_date: date | None = None


class ProjectResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    project_id: int
    budget_id: int
    name: str
    description: str | None = None
    is_active: bool
    start_date: date | None = None
    end_date: date | None = None
    created_at: datetime
    updated_at: datetime
    budget_amount: Decimal
    member_count: int
    #: Ids of the employees assigned to the project. A client needs these
    #: to know which projects the signed-in employee can act in.
    assigned_employee_ids: list[int] = Field(default_factory=list)


class ProjectListItem(ProjectResponse):
    """Cursor-list row — same shape, distinct name per §11."""


class ProjectMemberAdd(BaseModel):
    """Body for ``POST /projects/{id}/members`` — role defaults to the
    organization's ``employee`` role when omitted."""

    model_config = ConfigDict(str_strip_whitespace=True)

    employee_id: int = Field(gt=0)
    role_id: int | None = Field(default=None, gt=0)


class ProjectMemberListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    project_member_id: int
    project_id: int
    employee_id: int
    employee_name: str
    employee_email: str
    role_id: int
    role_name: str
