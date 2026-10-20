"""Project business rules (§49 #22-24). Tenant scope resolves via budgets (§9)."""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.db.transaction import transaction
from app.db.types import Conn, Row
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import NotificationCreate
from app.projects.repository import ProjectRepository
from app.projects.schemas import (
    ProjectCreate,
    ProjectListItem,
    ProjectMemberAdd,
    ProjectMemberListItem,
    ProjectResponse,
    ProjectUpdate,
)

_repository = ProjectRepository()
_notifications = NotificationRepository()


class ProjectService:
    def __init__(
        self,
        repository: ProjectRepository | None = None,
        notifications: NotificationRepository | None = None,
    ) -> None:
        self._repository = repository or _repository
        self._notifications = notifications or _notifications

    async def create_project(
        self, conn: Conn, *, actor_id: int, organization_id: int, payload: ProjectCreate
    ) -> ProjectResponse:
        await self._require_admin(conn, actor_id, organization_id)
        budget_org = await self._repository.get_budget_org(conn, payload.budget_id)
        if budget_org is None or budget_org != organization_id:
            raise NotFoundError("Budget not found.")
        self._check_dates(payload.start_date, payload.end_date)
        row = await self._repository.create(
            conn,
            budget_id=payload.budget_id,
            organization_id=organization_id,
            name=payload.name,
            description=payload.description,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="project.create",
            table_name="projects",
            record_id=str(row["project_id"]),
            new_values={"name": payload.name, "budget_id": payload.budget_id},
        )
        return ProjectResponse.model_validate(row)

    async def list_projects(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        limit: int,
        before_id: int | None,
    ) -> list[ProjectListItem]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_by_org(
            conn, organization_id, limit=limit, before_id=before_id
        )
        return [ProjectListItem.model_validate(r) for r in rows]

    async def update_project(
        self, conn: Conn, *, actor_id: int, project_id: int, payload: ProjectUpdate
    ) -> ProjectResponse:
        org_id = await self._repository.get_project_org(conn, project_id)
        if org_id is None:
            raise NotFoundError("Project not found.")
        await self._require_admin(conn, actor_id, org_id)
        current = await self._repository.get_by_id(conn, project_id, org_id)
        if current is None:
            raise NotFoundError("Project not found.")
        start = payload.start_date if payload.start_date is not None else current["start_date"]
        end = payload.end_date if payload.end_date is not None else current["end_date"]
        self._check_dates(start, end)
        if not payload.model_dump(exclude_unset=True):
            return ProjectResponse.model_validate(current)
        row = await self._repository.update(
            conn,
            project_id,
            org_id,
            name=payload.name,
            description=payload.description,
            is_active=payload.is_active,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        if row is None:
            raise NotFoundError("Project not found.")
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=org_id,
            action="project.update",
            table_name="projects",
            record_id=str(project_id),
            old_values={"name": current["name"], "is_active": current["is_active"]},
            new_values={"name": row["name"], "is_active": row["is_active"]},
        )
        return ProjectResponse.model_validate(row)

    @staticmethod
    def _check_dates(start: object, end: object) -> None:
        if start is not None and end is not None and end <= start:  # type: ignore[operator]
            raise ValidationError("end_date must be after start_date.")

    # -- project members (§49 nice-to-have → real) -------------------------

    async def _resolve_org(self, conn: Conn, project_id: int) -> int:
        org_id = await self._repository.get_project_org(conn, project_id)
        if org_id is None:
            raise NotFoundError("Project not found.")
        return org_id

    async def list_members(
        self,
        conn: Conn,
        *,
        employee_id: int,
        project_id: int,
        limit: int,
        before_id: int | None,
    ) -> list[ProjectMemberListItem]:
        org_id = await self._resolve_org(conn, project_id)
        await self._require_member(conn, employee_id, org_id)
        rows = await self._repository.list_members(
            conn,
            project_id,
            organization_id=org_id,
            before_id=before_id,
            limit=limit,
        )
        return [ProjectMemberListItem.model_validate(r) for r in rows]

    async def add_member(
        self,
        conn: Conn,
        *,
        actor_id: int,
        project_id: int,
        payload: ProjectMemberAdd,
    ) -> ProjectMemberListItem:
        org_id = await self._resolve_org(conn, project_id)
        await self._require_admin(conn, actor_id, org_id)
        membership = await self._repository.get_employee_membership(
            conn, payload.employee_id, org_id
        )
        if membership is None:
            raise NotFoundError("Employee is not a member of this organization.")
        role_id = payload.role_id
        if role_id is None:
            role = await self._repository.get_default_role_id(conn, org_id)
            if role is None:
                raise ConflictError(
                    "Default role 'employee' is not configured for this organization."
                )
            role_id = int(role["role_id"])
        else:
            role = await self._repository.get_role(conn, role_id, org_id)
            if role is None or int(role["organization_id"]) != org_id:
                raise NotFoundError("Role not found.")
        async with transaction(conn):
            existing = await self._repository.is_project_member(
                conn, project_id, payload.employee_id
            )
            if existing:
                raise ConflictError("Employee is already a member of this project.")
            row = await self._repository.insert_member(
                conn,
                project_id=project_id,
                organization_id=org_id,
                employee_id=payload.employee_id,
                role_id=role_id,
            )
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=org_id,
                action="project_member.add",
                table_name="project_members",
                record_id=str(row["project_member_id"]),
                new_values={"project_id": project_id, "employee_id": payload.employee_id},
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=payload.employee_id,
                    title="Added to a project",
                    message=(f"You now have access to project #{project_id}."),
                    type="project.member.added",
                    reference_id=str(project_id),
                ),
            )
            return ProjectMemberListItem.model_validate(row)

    async def remove_member(
        self, conn: Conn, *, actor_id: int, project_id: int, target_employee_id: int
    ) -> None:
        org_id = await self._resolve_org(conn, project_id)
        await self._require_admin(conn, actor_id, org_id)
        async with transaction(conn):
            row = await self._repository.delete_member(conn, project_id, target_employee_id)
            if row is None:
                raise NotFoundError("Employee is not a member of this project.")
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=org_id,
                action="project_member.remove",
                table_name="project_members",
                record_id=str(row["project_member_id"]),
                old_values={
                    "project_id": project_id,
                    "employee_id": target_employee_id,
                },
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=target_employee_id,
                    title="Removed from a project",
                    message=(f"Your access to project #{project_id} was revoked."),
                    type="project.member.removed",
                    reference_id=str(project_id),
                ),
            )

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = ProjectService()
