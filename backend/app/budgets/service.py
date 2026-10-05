from __future__ import annotations
from app.core.exceptions import NotFoundError
from app.db.types import Conn
from app.budgets.repository import BudgetRepository
from app.budgets.schemas import BudgetCreate

_repository = BudgetRepository()

class BudgetService:
    def __init__(self, repository: BudgetRepository | None = None) -> None:
        self._repository = repository or _repository

    async def get_budget(self, conn: Conn, month: str) -> dict:
        row = await self._repository.get_by_month(conn, month)
        if row is None:
            return {"month": month, "amount": 0.0}
        return dict(row)

    async def set_budget(self, conn: Conn, payload: BudgetCreate) -> dict:
        row = await self._repository.upsert_budget(
            conn,
            month=payload.month,
            amount=payload.amount,
            set_by_email=payload.setByEmail,
            set_by_name=payload.setByName,
        )
        return dict(row)

service = BudgetService()