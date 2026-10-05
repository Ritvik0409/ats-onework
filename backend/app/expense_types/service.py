from __future__ import annotations
from app.db.types import Conn
from app.expense_types.repository import ExpenseTypeRepository
from app.expense_types.schemas import ExpenseTypeCreate

_repository = ExpenseTypeRepository()

class ExpenseTypeService:
    def __init__(self, repository: ExpenseTypeRepository | None = None) -> None:
        self._repository = repository or _repository

    async def list_types(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_types(conn)
        return [dict(row) for row in rows]

    async def create_type(self, conn: Conn, payload: ExpenseTypeCreate) -> dict:
        row = await self._repository.create_type(conn, name=payload.name)
        return dict(row)

service = ExpenseTypeService()