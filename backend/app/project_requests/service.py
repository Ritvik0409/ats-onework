"""Project-access-request business rules (migration 0002).

Tenant model (§8): everything resolves through the project's org read
from its budget — a caller probing another org's project sees 404
(never 403) via ``require_path_member`` / ``require_path_admin``.

Lifecycle: ``pending -> approved | rejected`` per
``PROJECT_ACCESS_TRANSITIONS`` — anything else is 409. Approval grants
``project_members`` with the org's default ``employee`` role; decisions
are terminal and re-request inserts a new row (migration 0002 partial
unique). All multi-writes run in one transaction with audit + notifications.
"""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.core.constants import PROJECT_ACCESS_TRANSITIONS, ProjectAccessStatus
from app.core.exceptions import ConflictError, NotFoundError
from app.db.transaction import transaction
from app.db.types import Conn, Row
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import NotificationCreate
from app.project_requests.repository import ProjectAccessRepository
from app.project_requests.schemas import (
    AccessDecisionRequest,
    ProjectAccessListItem,
    ProjectAccessResponse,
)

_repository = ProjectAccessRepository()
_notifications = NotificationRepository()


class ProjectAccessService:
    def __init__(
        self,
        repository: ProjectAccessRepository | None = None,
        notifications: NotificationRepository | None = None,
    ) -> None:
        self._repository = repository or _repository
        self._notifications = notifications or _notifications

    # -- request ------------------------------------------------------------

    async def request_access(
        self, conn: Conn, *, employee_id: int, project_id: int
    ) -> ProjectAccessResponse:
        org_id = await self._repository.get_project_org(conn, project_id)
        if org_id is None:
            raise NotFoundError("Project not found.")
        require_path_member(await self._repository.get_membership(conn, employee_id, org_id))
        async with transaction(conn):
            if await self._repository.is_project_member(conn, project_id, employee_id):
                raise ConflictError("Already a member of this project.")
            if await self._repository.find_pending(conn, project_id, employee_id) is not None:
                raise ConflictError("A pending access request already exists for this project.")
            row = await self._repository.create(
                conn, employee_id=employee_id, project_id=project_id, organization_id=org_id
            )
            await audit_service.log(
                conn,
                actor_id=employee_id,
                organization_id=org_id,
                action="project_access.request",
                table_name="project_access_requests",
                record_id=str(row["access_request_id"]),
                new_values={"project_id": project_id, "organization_id": org_id},
            )
        return ProjectAccessResponse.model_validate(row)

    # -- reads --------------------------------------------------------------

    async def list_for_project(
        self,
        conn: Conn,
        *,
        actor_id: int,
        project_id: int,
        status: ProjectAccessStatus | None,
        limit: int,
        before_id: int | None,
    ) -> list[ProjectAccessListItem]:
        org_id = await self._repository.get_project_org(conn, project_id)
        if org_id is None:
            raise NotFoundError("Project not found.")
        require_path_admin(await self._repository.get_membership(conn, actor_id, org_id))
        rows = await self._repository.list_by_project(
            conn,
            org_id,
            project_id=project_id,
            status=status,
            limit=limit,
            before_id=before_id,
        )
        return [ProjectAccessListItem.model_validate(r) for r in rows]

    async def list_org_queue(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        status: ProjectAccessStatus | None,
        limit: int,
        before_id: int | None,
    ) -> list[ProjectAccessListItem]:
        """Whole-org admin queue (GET /access-requests, token-org scope)."""
        require_path_admin(await self._repository.get_membership(conn, actor_id, organization_id))
        rows = await self._repository.list_by_project(
            conn,
            organization_id,
            project_id=None,
            status=status,
            limit=limit,
            before_id=before_id,
        )
        return [ProjectAccessListItem.model_validate(r) for r in rows]

    async def list_mine(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        limit: int,
        before_id: int | None,
    ) -> list[ProjectAccessListItem]:
        require_path_member(
            await self._repository.get_membership(conn, employee_id, organization_id)
        )
        rows = await self._repository.list_by_employee(
            conn,
            employee_id=employee_id,
            organization_id=organization_id,
            limit=limit,
            before_id=before_id,
        )
        return [ProjectAccessListItem.model_validate(r) for r in rows]

    # -- decide -------------------------------------------------------------

    async def approve(
        self,
        conn: Conn,
        *,
        actor_id: int,
        request_id: int,
        payload: AccessDecisionRequest,
    ) -> ProjectAccessResponse:
        return await self._decide(
            conn,
            actor_id=actor_id,
            request_id=request_id,
            status=ProjectAccessStatus.APPROVED,
            payload=payload,
        )

    async def reject(
        self,
        conn: Conn,
        *,
        actor_id: int,
        request_id: int,
        payload: AccessDecisionRequest,
    ) -> ProjectAccessResponse:
        return await self._decide(
            conn,
            actor_id=actor_id,
            request_id=request_id,
            status=ProjectAccessStatus.REJECTED,
            payload=payload,
        )

    async def _decide(
        self,
        conn: Conn,
        *,
        actor_id: int,
        request_id: int,
        status: ProjectAccessStatus,
        payload: AccessDecisionRequest,
    ) -> ProjectAccessResponse:
        org_id = await self._repository.get_request_org(conn, request_id)
        if org_id is None:
            raise NotFoundError("Access request not found.")
        require_path_admin(await self._repository.get_membership(conn, actor_id, org_id))
        comment = (payload.comment or "").strip() or None
        async with transaction(conn):
            row = await self._repository.get_by_id_for_update(conn, request_id, org_id)
            if row is None:
                raise NotFoundError("Access request not found.")
            current = ProjectAccessStatus(row["status"])
            if status not in PROJECT_ACCESS_TRANSITIONS[current]:
                raise ConflictError(f"Cannot transition access request from {current.value}.")
            if status == ProjectAccessStatus.APPROVED:
                await self._grant_membership(conn, request_row=row, organization_id=org_id)
            updated = await self._repository.update_status(
                conn,
                request_id=request_id,
                status=status,
                decided_by=actor_id,
                decision_comment=comment,
            )
            assert updated is not None
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=org_id,
                action=f"project_access.{status.value}",
                table_name="project_access_requests",
                record_id=str(request_id),
                old_values={"status": current.value},
                new_values={"status": status.value},
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=int(row["employee_id"]),
                    title=f"Project access {status.value}",
                    message=(
                        f"Your access request for project #{int(row['project_id'])} "
                        f"was {status.value}."
                    ),
                    type=f"project_access.{status.value}",
                    reference_id=str(request_id),
                ),
            )
        return ProjectAccessResponse.model_validate(updated)

    # -- helpers ------------------------------------------------------------

    async def _grant_membership(
        self, conn: Conn, *, request_row: Row, organization_id: int
    ) -> None:
        project_id = int(request_row["project_id"])
        employee_id = int(request_row["employee_id"])
        if await self._repository.is_project_member(conn, project_id, employee_id):
            return  # added manually meanwhile — the grant is already satisfied
        role = await self._repository.get_default_role_id(conn, organization_id)
        if role is None:
            raise ConflictError("Default role 'employee' is not configured for this organization.")
        await self._repository.insert_member(
            conn,
            project_id=project_id,
            organization_id=organization_id,
            employee_id=employee_id,
            role_id=int(role["role_id"]),
        )


service = ProjectAccessService()
