"""Project-access endpoints — migration 0002 lifecycle (HTTP only).

Routes:
- ``POST /projects/{project_id}/access-requests`` — employee self-request.
- ``GET  /projects/{project_id}/access-requests`` — admin queue (paged,
  optional ``status`` filter).
- ``GET  /access-requests/mine`` — requester's own requests (paged).
- ``POST /access-requests/{request_id}/approve|reject`` — decision.

Resource-scoped paths 404 cross-tenant probes via the service's
``require_path_member`` / ``require_path_admin`` (§8).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.common.pagination import Page
from app.core.constants import ProjectAccessStatus
from app.core.exceptions import ValidationError
from app.db.connection import get_connection
from app.db.types import Conn
from app.project_requests.schemas import (
    AccessDecisionRequest,
    ProjectAccessListItem,
    ProjectAccessResponse,
)
from app.project_requests.service import service as project_access_service

router = APIRouter(prefix="/access-requests", tags=["project-access"])
projects_router = APIRouter(prefix="/projects", tags=["project-access"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@projects_router.post(
    "/{project_id}/access-requests",
    response_model=ProjectAccessResponse,
    status_code=status.HTTP_201_CREATED,
)
async def request_project_access(
    project_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectAccessResponse:
    return await project_access_service.request_access(
        conn, employee_id=user.employee_id, project_id=project_id
    )


@projects_router.get(
    "/{project_id}/access-requests",
    response_model=Page[ProjectAccessListItem],
)
async def list_project_access_requests(
    project_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    status_filter: Annotated[ProjectAccessStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ProjectAccessListItem]:
    items = await project_access_service.list_for_project(
        conn,
        actor_id=user.employee_id,
        project_id=project_id,
        status=status_filter,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].access_request_id) if items else None
    return Page[ProjectAccessListItem](items=items, next_cursor=next_cursor)


@router.get("", response_model=Page[ProjectAccessListItem])
async def list_org_access_requests(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    status_filter: Annotated[ProjectAccessStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ProjectAccessListItem]:
    """Whole-org admin queue (token-org scope; project filter omitted)."""
    items = await project_access_service.list_org_queue(
        conn,
        actor_id=user.employee_id,
        organization_id=user.organization_id,
        status=status_filter,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].access_request_id) if items else None
    return Page[ProjectAccessListItem](items=items, next_cursor=next_cursor)


@router.get("/mine", response_model=Page[ProjectAccessListItem])
async def list_my_access_requests(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ProjectAccessListItem]:
    items = await project_access_service.list_mine(
        conn,
        employee_id=user.employee_id,
        organization_id=user.organization_id,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].access_request_id) if items else None
    return Page[ProjectAccessListItem](items=items, next_cursor=next_cursor)


@router.post("/{request_id}/approve", response_model=ProjectAccessResponse)
async def approve_access_request(
    request_id: int,
    payload: AccessDecisionRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectAccessResponse:
    return await project_access_service.approve(
        conn, actor_id=user.employee_id, request_id=request_id, payload=payload
    )


@router.post("/{request_id}/reject", response_model=ProjectAccessResponse)
async def reject_access_request(
    request_id: int,
    payload: AccessDecisionRequest,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectAccessResponse:
    return await project_access_service.reject(
        conn, actor_id=user.employee_id, request_id=request_id, payload=payload
    )
