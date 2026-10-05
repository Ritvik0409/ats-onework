from __future__ import annotations
from app.db.types import Conn
from app.employee_status.repository import EmployeeStatusRepository
from app.employee_status.schemas import EmployeeStatusCreate

_repository = EmployeeStatusRepository()

class EmployeeStatusService:
    def __init__(self, repository: EmployeeStatusRepository | None = None) -> None:
        self._repository = repository or _repository

    async def list_statuses(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_statuses(conn)
        return [dict(row) for row in rows]

    async def update_status(self, conn: Conn, payload: EmployeeStatusCreate) -> dict:
        row = await self._repository.upsert_status(
            conn, email=payload.email, is_active=payload.isActive, updated_by=payload.updatedBy
        )
        return dict(row)

service = EmployeeStatusService()