"""Expense-type persistence — raw SQL only (§5). All queries org-scoped (§8)."""

from __future__ import annotations

from decimal import Decimal

from app.db.types import Conn, Row

_TYPE_COLUMNS = (
    "expense_type_id, name, organization_id, description, is_active, "
    "requires_receipt, default_limit, created_at, updated_at"
)


class ExpenseTypeRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def create(
        self,
        conn: Conn,
        *,
        organization_id: int,
        name: str,
        description: str | None,
        requires_receipt: bool,
        default_limit: Decimal | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expense_types (name, organization_id, description,"
                " requires_receipt, default_limit)"
                " VALUES (%s, %s, %s, %s, %s) RETURNING " + _TYPE_COLUMNS,
                (
                    name,
                    organization_id,
                    description,
                    requires_receipt,
                    str(default_limit) if default_limit is not None else None,
                ),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_by_org(self, conn: Conn, organization_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _TYPE_COLUMNS + " FROM expense_types"
                " WHERE organization_id = %s ORDER BY name ASC",
                (organization_id,),
            )
            return list(await cur.fetchall())
