"""Project DTOs (§49 #22-24)."""

from __future__ import annotations

from datetime import date, datetime

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


class ProjectListItem(ProjectResponse):
    """Cursor-list row — same shape, distinct name per §11."""
