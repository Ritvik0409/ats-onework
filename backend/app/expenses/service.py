from __future__ import annotations
from app.core.exceptions import NotFoundError
from app.db.types import Conn
from app.expenses.repository import ExpenseRepository
from app.expenses.schemas import ExpenseCreate, ExpenseUpdate

_repository = ExpenseRepository()

class ExpenseService:
    def __init__(self, repository: ExpenseRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create_expense(self, conn: Conn, payload: ExpenseCreate) -> dict:
        row = await self._repository.create_expense(
            conn,
            employee_id=payload.employeeId,
            employee_name=payload.employeeName,
            email=payload.email,
            type=payload.type,
            amount=payload.amount,
            date=payload.date,
            description=payload.description,
            status=payload.status or "Pending Verification",
            receipt_base64=payload.receiptBase64,
            project_name=payload.projectName,
            uploader_role=payload.uploaderRole or "employee"
        )
        return dict(row)

    async def list_expenses(self, conn: Conn) -> list[dict]:
        rows = await self._repository.list_expenses(conn)
        return [dict(row) for row in rows]

    async def update_expense(self, conn: Conn, expense_id: str, payload: ExpenseUpdate) -> dict:
        row = await self._repository.update_expense_status(
            conn,
            expense_id,
            status=payload.status,
            rejection_reason=payload.rejectionReason,
            processed_by=payload.processedBy,
            transaction_id=payload.transactionId,
            payment_receipt_url=payload.paymentReceiptUrl
        )
        if row is None:
            raise NotFoundError("Expense not found.")
        return dict(row)

service = ExpenseService()