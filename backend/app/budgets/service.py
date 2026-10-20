"""Budget business rules (§49 #21): read (member), create + PATCH (admin)."""

from __future__ import annotations

import re
from datetime import date

from app.budgets.repository import BudgetRepository
from app.budgets.schemas import (
    BudgetCreate,
    BudgetListItem,
    BudgetResponse,
    BudgetUpdate,
)
from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.core.exceptions import NotFoundError, ValidationError
from app.db.types import Conn, Row

_repository = BudgetRepository()

_MONTH_RE = re.compile(r"^\d{4}-\d{2}$")


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
            organization_id=organization_id,
            action="budget.create",
            table_name="budgets",
            record_id=str(row["budget_id"]),
            new_values={"amount": str(payload.amount), "organization_id": organization_id},
        )
        return BudgetResponse.model_validate(row)

    async def list_budgets(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        month: str | None,
        limit: int,
        before_id: int | None,
    ) -> list[BudgetListItem]:
        """Member-readable org budgets; ``month`` (YYYY-MM) keeps only
        budgets whose date range overlaps that calendar month."""
        await self._require_member(conn, employee_id, organization_id)
        range_start, range_end = self._month_window(month)
        rows = await self._repository.list_by_org(
            conn,
            organization_id,
            range_start=range_start,
            range_end=range_end,
            limit=limit,
            before_id=before_id,
        )
        return [BudgetListItem.model_validate(r) for r in rows]

    async def update_budget(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        budget_id: int,
        payload: BudgetUpdate,
    ) -> BudgetResponse:
        await self._require_admin(conn, actor_id, organization_id)
        current = await self._repository.get_by_id(conn, budget_id)
        if current is None or int(current["organization_id"]) != organization_id:
            raise NotFoundError("Budget not found.")
        new_start = payload.start_date or current["start_date"]
        new_end = payload.end_date or current["end_date"]
        if new_end <= new_start:
            raise ValidationError("end_date must be after start_date.")
        if payload.amount is None and payload.start_date is None and payload.end_date is None:
            return BudgetResponse.model_validate(current)  # no-op PATCH writes nothing
        row = await self._repository.update(
            conn,
            budget_id,
            amount=payload.amount,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        assert row is not None
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="budget.update",
            table_name="budgets",
            record_id=str(budget_id),
            old_values={"amount": str(current["amount"])},
            new_values={"amount": str(row["amount"])},
        )
        return BudgetResponse.model_validate(row)

    # -- helpers ----------------------------------------------------------

    @staticmethod
    def _month_window(month: str | None) -> tuple[date | None, date | None]:
        if month is None:
            return None, None
        if not _MONTH_RE.match(month):
            raise ValidationError("month must look like YYYY-MM.")
        year, mon = int(month[:4]), int(month[5:7])
        if not 1 <= mon <= 12:
            raise ValidationError("month must look like YYYY-MM.")
        start = date(year, mon, 1)
        end = date(year + (mon == 12), 1 if mon == 12 else mon + 1, 1)
        return start, end

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = BudgetService()
