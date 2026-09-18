"""Organization endpoints — HTTP concerns only (§49 #13-20).

Auth levels: collection routes need any authenticated user; path-scoped
routes authenticate and let the service enforce membership (404) vs admin
(403) against the **path** organization — see the service docstring.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.api.v1.deps import CurrentUser, get_current_user
from app.db.connection import get_connection
from app.db.types import Conn
from app.organizations.schemas import (
    MembershipCreate,
    MembershipResponse,
    OrganizationCreate,
    OrganizationResponse,
    OrganizationUpdate,
    RoleCreate,
    RoleResponse,
)
from app.organizations.service import service as organization_service

router = APIRouter(prefix="/organizations", tags=["organizations"])


@router.post("", response_model=OrganizationResponse, status_code=status.HTTP_201_CREATED)
async def create_organization(
    payload: OrganizationCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> OrganizationResponse:
    return await organization_service.create_organization(
        conn, actor_id=user.employee_id, payload=payload
    )


@router.get("", response_model=list[OrganizationResponse])
async def list_organizations(
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[OrganizationResponse]:
    return await organization_service.list_own(conn, user.employee_id)


@router.get("/{organization_id}", response_model=OrganizationResponse)
async def get_organization(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> OrganizationResponse:
    return await organization_service.get_organization(
        conn, employee_id=user.employee_id, organization_id=organization_id
    )


@router.patch("/{organization_id}", response_model=OrganizationResponse)
async def update_organization(
    organization_id: int,
    payload: OrganizationUpdate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> OrganizationResponse:
    return await organization_service.update_organization(
        conn,
        employee_id=user.employee_id,
        organization_id=organization_id,
        payload=payload,
    )


@router.post(
    "/{organization_id}/members",
    response_model=MembershipResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_member(
    organization_id: int,
    payload: MembershipCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> MembershipResponse:
    return await organization_service.add_member(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        payload=payload,
    )


@router.delete(
    "/{organization_id}/members/{employee_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def remove_member(
    organization_id: int,
    employee_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> Response:
    await organization_service.remove_member(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        employee_id=employee_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{organization_id}/roles", response_model=list[RoleResponse])
async def list_roles(
    organization_id: int,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> list[RoleResponse]:
    return await organization_service.list_roles(
        conn, employee_id=user.employee_id, organization_id=organization_id
    )


@router.post(
    "/{organization_id}/roles",
    response_model=RoleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_role(
    organization_id: int,
    payload: RoleCreate,
    user: Annotated[CurrentUser, Depends(get_current_user)],
    conn: Annotated[Conn, Depends(get_connection)],
) -> RoleResponse:
    return await organization_service.create_role(
        conn,
        actor_id=user.employee_id,
        organization_id=organization_id,
        payload=payload,
    )
