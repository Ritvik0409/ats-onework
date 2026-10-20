"""Expense-type business rules (§49 #25-26)."""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.db.types import Conn, Row
from app.expense_types.repository import ExpenseTypeRepository
from app.expense_types.schemas import ExpenseTypeCreate, ExpenseTypeResponse

_repository = ExpenseTypeRepository()


class ExpenseTypeService:
    def __init__(self, repository: ExpenseTypeRepository | None = None) -> None:
        self._repository = repository or _repository

    async def create_type(
        self, conn: Conn, *, actor_id: int, organization_id: int, payload: ExpenseTypeCreate
    ) -> ExpenseTypeResponse:
        await self._require_admin(conn, actor_id, organization_id)
        row = await self._repository.create(
            conn,
            organization_id=organization_id,
            name=payload.name,
            description=payload.description,
            requires_receipt=payload.requires_receipt,
            default_limit=payload.default_limit,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            action="expense_type.create",
            table_name="expense_types",
            record_id=str(row["expense_type_id"]),
            new_values={"name": payload.name, "organization_id": organization_id},
        )
        return ExpenseTypeResponse.model_validate(row)

    async def list_types(
        self, conn: Conn, *, employee_id: int, organization_id: int
    ) -> list[ExpenseTypeResponse]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_by_org(conn, organization_id)
        return [ExpenseTypeResponse.model_validate(r) for r in rows]

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = ExpenseTypeService()
