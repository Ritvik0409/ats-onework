from __future__ import annotations
from app.core.exceptions import NotFoundError
from app.db.types import Conn
from app.project_requests.repository import ProjectRequestRepository
from app.project_requests.schemas import ProjectRequestCreate, ProjectRequestApprove

_repository = ProjectRequestRepository()

class ProjectRequestService:
    def __init__(self, repository: ProjectRequestRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create_request(self, conn: Conn, payload: ProjectRequestCreate) -> dict:
        row = await self._repository.create_request(
            conn, email=payload.email, name=payload.name, status=payload.status or "Pending Assignment"
        )
        return dict(row)

    async def list_requests(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_requests(conn)
        return [dict(row) for row in rows]

    async def approve_request(self, conn: Conn, payload: ProjectRequestApprove) -> dict:
        row = await self._repository.update_status(conn, payload.email, "Approved")
        if row is None:
            raise NotFoundError("Project request not found for this email.")
        return dict(row)

service = ProjectRequestService()