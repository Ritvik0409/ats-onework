from __future__ import annotations
from app.core.exceptions import NotFoundError
from app.db.types import Conn
from app.reimbursements.repository import ReimbursementRepository
from app.reimbursements.schemas import ReimbursementCreate, ReimbursementUpdate

_repository = ReimbursementRepository()

class ReimbursementService:
    def __init__(self, repository: ReimbursementRepository | None = None) -> None:
        self._repository = repository or _repository

    async def list_reimbursements(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_all(conn)
        return [dict(row) for row in rows]

    async def create_reimbursement(self, conn: Conn, payload: ReimbursementCreate) -> dict:
        row = await self._repository.create(
            conn, expense_id=payload.expenseId, amount=payload.amount, employee_email=payload.employeeEmail
        )
        return dict(row)

    async def update_reimbursement(self, conn: Conn, reimbursement_id: str, payload: ReimbursementUpdate) -> dict:
        row = await self._repository.update(conn, reimbursement_id, status=payload.status or "Processed")
        if row is None:
            raise NotFoundError("Reimbursement not found.")
        return dict(row)

service = ReimbursementService()