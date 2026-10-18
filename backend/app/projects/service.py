"""Project business rules (§49 #22-24). Tenant scope resolves via budgets (§9)."""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.core.exceptions import NotFoundError, ValidationError
from app.db.types import Conn, Row
from app.projects.repository import ProjectRepository
from app.projects.schemas import ProjectCreate, ProjectListItem, ProjectResponse, ProjectUpdate

_repository = ProjectRepository()


class ProjectService:
    def __init__(self, repository: ProjectRepository | None = None) -> None:
        self._repository = repository or _repository

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
            name=payload.name,
            description=payload.description,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
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
        current = await self._repository.get_by_id(conn, project_id)
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

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = ProjectService()
