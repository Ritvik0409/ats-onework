"""Aggregates all domain routers under ``/api/v1`` (arch. doc §20, §49).

Version prefixes are centralized here — never hard-coded per endpoint.
Domain routers (auth, users, organizations, projects, expenses,
reimbursements, notifications) register below as their modules land.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.auth.router import router as auth_router
from app.organizations.router import router as organizations_router
from app.users.router import router as users_router

api_v1_router = APIRouter(prefix="/api/v1")
api_v1_router.include_router(auth_router)
api_v1_router.include_router(users_router)
api_v1_router.include_router(organizations_router)
