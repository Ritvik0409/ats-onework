"""Canonical user DTOs — the single place user shapes are defined
(arch. doc §11).

``UserResponse`` is imported by the auth module so registration/login
responses can never drift from the user read model. ``password_hash`` (and
any other internal column) must never appear on any model here — the
field-exposure test in ``tests/`` guards this (§49 #8-12).
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.core.constants import AccountStatus, EmployeeStatus


class UserResponse(BaseModel):
    """Public user shape — §49 #3/#8. No sensitive fields, ever."""

    model_config = ConfigDict(from_attributes=True)

    employee_id: int
    name: str
    email: str
    account_status: AccountStatus
    is_superuser: bool
    last_login_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class UserListItem(BaseModel):
    """Compact row for the admin list endpoint — §49 #9."""

    model_config = ConfigDict(from_attributes=True)

    employee_id: int
    name: str
    email: str
    account_status: AccountStatus


class UserUpdate(BaseModel):
    """Admin-only patch body — §49 #10. All fields optional."""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str | None = Field(default=None, min_length=1, max_length=100)
    account_status: AccountStatus | None = None
    is_superuser: bool | None = None


class EmployeeStatusCreate(BaseModel):
    """Body for appending a status-log row — §49 #12."""

    model_config = ConfigDict(str_strip_whitespace=True)

    status: EmployeeStatus


class EmployeeStatusResponse(BaseModel):
    """One status-log row — §49 #11/#12."""

    model_config = ConfigDict(from_attributes=True)

    status_id: int
    employee_id: int
    status: EmployeeStatus
    started_at: datetime
    ended_at: datetime | None = None
    updated_by: int | None = None
