"""Project endpoints — HTTP only (§49 #22-24)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.common.pagination import Page
from app.db.connection import get_connection
from app.db.types import Conn
from app.projects.schemas import (
    ProjectCreate,
    ProjectListItem,
    ProjectMemberAdd,
    ProjectMemberListItem,
    ProjectResponse,
    ProjectUpdate,
)
from app.projects.service import service as project_service

router = APIRouter(prefix="/projects", tags=["projects"])
org_router = APIRouter(prefix="/organizations", tags=["projects"])


def _parse_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        value = int(cursor)
    except (TypeError, ValueError) as exc:
        from app.core.exceptions import ValidationError

        raise ValidationError("Invalid pagination cursor.") from exc
    return value if value > 0 else None


@org_router.post(
    "/{organization_id}/projects",
    response_model=ProjectResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_project(
    organization_id: int,
    payload: ProjectCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectResponse:
    return await project_service.create_project(
        conn, actor_id=user.employee_id, organization_id=organization_id, payload=payload
    )


@org_router.get("/{organization_id}/projects", response_model=Page[ProjectListItem])
async def list_projects(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ProjectListItem]:
    items = await project_service.list_projects(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].project_id) if items else None
    return Page[ProjectListItem](items=items, next_cursor=next_cursor)


@router.patch("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: int,
    payload: ProjectUpdate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectResponse:
    return await project_service.update_project(
        conn, actor_id=user.employee_id, project_id=project_id, payload=payload
    )


@router.get("/{project_id}/members", response_model=Page[ProjectMemberListItem])
async def list_project_members(
    project_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    cursor: Annotated[str | None, Query()] = None,
) -> Page[ProjectMemberListItem]:
    items = await project_service.list_members(
        conn,
        employee_id=user.employee_id,
        project_id=project_id,
        limit=limit,
        before_id=_parse_cursor(cursor),
    )
    next_cursor = str(items[-1].project_member_id) if items else None
    return Page[ProjectMemberListItem](items=items, next_cursor=next_cursor)


@router.post(
    "/{project_id}/members",
    response_model=ProjectMemberListItem,
    status_code=status.HTTP_201_CREATED,
)
async def add_project_member(
    project_id: int,
    payload: ProjectMemberAdd,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> ProjectMemberListItem:
    return await project_service.add_member(
        conn, actor_id=user.employee_id, project_id=project_id, payload=payload
    )


@router.delete("/{project_id}/members/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_project_member(
    project_id: int,
    employee_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    await project_service.remove_member(
        conn, actor_id=user.employee_id, project_id=project_id, target_employee_id=employee_id
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
