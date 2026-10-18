"""Aggregates all domain routers under ``/api/v1`` (arch. doc §20, §49).

Version prefixes are centralized here — never hard-coded per endpoint.
Domain routers (auth, users, organizations, projects, expenses,
reimbursements, notifications) register below as their modules land.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.audit_logs.router import router as audit_logs_router
from app.auth.router import router as auth_router
from app.budgets.router import router as budgets_router
from app.expense_types.router import router as expense_types_router
from app.expenses.router import approvals_router as approvals_router
from app.expenses.router import router as expenses_router
from app.notifications.router import router as notifications_router
from app.organizations.router import router as organizations_router
from app.project_requests.router import projects_router as project_access_projects_router
from app.project_requests.router import router as project_access_router
from app.projects.router import org_router as org_projects_router
from app.projects.router import router as projects_router
from app.reimbursements.router import expense_router as expense_reimbursement_router
from app.reimbursements.router import router as reimbursements_router
from app.users.router import router as users_router

api_v1_router = APIRouter(prefix="/api/v1")
api_v1_router.include_router(auth_router)
api_v1_router.include_router(users_router)
api_v1_router.include_router(organizations_router)
api_v1_router.include_router(expenses_router)
api_v1_router.include_router(approvals_router)
api_v1_router.include_router(projects_router)
api_v1_router.include_router(org_projects_router)
api_v1_router.include_router(budgets_router)
api_v1_router.include_router(project_access_router)
api_v1_router.include_router(project_access_projects_router)
api_v1_router.include_router(expense_types_router)
api_v1_router.include_router(reimbursements_router)
api_v1_router.include_router(expense_reimbursement_router)
api_v1_router.include_router(notifications_router)
api_v1_router.include_router(audit_logs_router)
