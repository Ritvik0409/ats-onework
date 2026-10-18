"""Budget business rules (§49 #21)."""

from __future__ import annotations

from app.budgets.repository import BudgetRepository
from app.budgets.schemas import BudgetCreate, BudgetResponse
from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin
from app.core.exceptions import ValidationError
from app.db.types import Conn, Row

_repository = BudgetRepository()


class BudgetService:
    def __init__(self, repository: BudgetRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create_budget(
        self, conn: Conn, *, actor_id: int, organization_id: int, payload: BudgetCreate
    ) -> BudgetResponse:
        await self._require_admin(conn, actor_id, organization_id)
        if payload.end_date <= payload.start_date:
            raise ValidationError("end_date must be after start_date.")
        row = await self._repository.create(
            conn,
            amount=payload.amount,
            employee_id=actor_id,
            organization_id=organization_id,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="budget.create",
            table_name="budgets",
            record_id=str(row["budget_id"]),
            new_values={"amount": str(payload.amount), "organization_id": organization_id},
        )
        return BudgetResponse.model_validate(row)

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = BudgetService()
