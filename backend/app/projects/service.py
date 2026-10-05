from __future__ import annotations
from app.core.exceptions import NotFoundError
from app.db.types import Conn
from app.projects.repository import ProjectRepository
from app.projects.schemas import ProjectCreate, ProjectUpdate

_repository = ProjectRepository()

class ProjectService:
    def __init__(self, repository: ProjectRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create_project(self, conn: Conn, payload: ProjectCreate) -> dict:
        row = await self._repository.create_project(
            conn, name=payload.name, budget=payload.budget, is_active=payload.isActive
        )
        return dict(row)

    async def list_projects(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_projects(conn)
        return [dict(row) for row in rows]

    async def update_project(self, conn: Conn, project_id: str, payload: ProjectUpdate) -> dict:
        row = await self._repository.update_project(
            conn, project_id, budget=payload.budget, is_active=payload.isActive
        )
        if row is None:
            raise NotFoundError("Project not found.")
        return dict(row)

service = ProjectService()