"""Aggregates all domain routers under ``/api/v1`` (arch. doc §20, §49).

Version prefixes are centralized here — never hard-coded per endpoint.
Domain routers (auth, users, organizations, projects, expenses,
reimbursements, notifications) register below as their modules land.
"""

from __future__ import annotations

from fastapi import APIRouter

api_v1_router = APIRouter(prefix="/api/v1")
