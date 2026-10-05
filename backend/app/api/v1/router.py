"""Aggregates all domain routers under ``/api/v1`` (arch. doc §20, §49).

Version prefixes are centralized here — never hard-coded per endpoint.
Domain routers (auth, users, organizations, projects, expenses,
reimbursements, notifications) register below as their modules land.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.auth.router import router as auth_router
from app.users.router import router as users_router
from app.organizations.router import router as organizations_router
from app.expenses.router import router as expenses_router
from app.projects.router import router as projects_router
from app.budgets.router import router as budgets_router 
from app.project_requests.router import router as project_requests_router
from app.employee_status.router import router as employee_status_router
from app.expense_types.router import router as expense_types_router
from app.reimbursements.router import router as reimbursements_router


api_v1_router = APIRouter(prefix="/api/v1")
api_v1_router.include_router(auth_router)
api_v1_router.include_router(users_router)
api_v1_router.include_router(organizations_router)
api_v1_router.include_router(expenses_router)
api_v1_router.include_router(projects_router)
api_v1_router.include_router(budgets_router)
api_v1_router.include_router(project_requests_router)
api_v1_router.include_router(employee_status_router)
api_v1_router.include_router(expense_types_router)
api_v1_router.include_router(reimbursements_router)