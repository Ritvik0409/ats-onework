"""Expense persistence — raw parameterized SQL only (arch. doc §5, §32).

Every read carries ``WHERE organization_id = %s`` (§8) so cross-tenant IDs
are undiscoverable — the service turns empty results into 404 (§49).
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from app.core.constants import ExpenseStatus
from app.db.types import Conn, Row

_EXPENSE_COLUMNS = (
    "expense_id, employee_id, project_id, organization_id, expense_type_id, "
    "amount, status, rejection_reason, expense_date, submission_date, updated_at, "
    "info_message, info_requested_at"
)

_MEDIA_COLUMNS = "media_id, expense_id, receipt_url, description, uploaded_at"


class ExpenseRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def get_project_org(self, conn: Conn, project_id: int) -> int | None:
        """Resolve a project's org via budgets — mirrors the DB trigger (§9)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT b.organization_id AS organization_id"
                " FROM projects p JOIN budgets b ON b.budget_id = p.budget_id"
                " WHERE p.project_id = %s",
                (project_id,),
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def get_expense_type_org(self, conn: Conn, expense_type_id: int) -> int | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT organization_id FROM expense_types WHERE expense_type_id = %s",
                (expense_type_id,),
            )
            row = await cur.fetchone()
            return None if row is None else int(row["organization_id"])

    async def create(
        self,
        conn: Conn,
        *,
        employee_id: int,
        project_id: int,
        organization_id: int,
        expense_type_id: int,
        amount: Decimal,
        expense_date: date,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expenses"
                " (employee_id, project_id, organization_id, expense_type_id, amount, expense_date)"
                " VALUES (%s, %s, %s, %s, %s, %s) RETURNING " + _EXPENSE_COLUMNS,
                (
                    employee_id,
                    project_id,
                    organization_id,
                    expense_type_id,
                    str(amount),
                    expense_date,
                ),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id(self, conn: Conn, expense_id: int, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _EXPENSE_COLUMNS + " FROM expenses"
                " WHERE expense_id = %s AND organization_id = %s",
                (expense_id, organization_id),
            )
            return await cur.fetchone()

    async def get_by_id_for_update(
        self, conn: Conn, expense_id: int, organization_id: int
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _EXPENSE_COLUMNS + " FROM expenses"
                " WHERE expense_id = %s AND organization_id = %s FOR UPDATE",
                (expense_id, organization_id),
            )
            return await cur.fetchone()

    async def update_status(
        self,
        conn: Conn,
        expense_id: int,
        *,
        status: ExpenseStatus,
        rejection_reason: str | None,
        info_message: str | None,
        info_requested_at: datetime | None,
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE expenses SET status = %s, rejection_reason = %s,"
                " info_message = %s, info_requested_at = %s"
                " WHERE expense_id = %s RETURNING " + _EXPENSE_COLUMNS,
                (status.value, rejection_reason, info_message, info_requested_at, expense_id),
            )
            return await cur.fetchone()

    async def list_admin_ids(self, conn: Conn, organization_id: int) -> list[int]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT employee_id FROM memberships WHERE organization_id = %s AND is_admin",
                (organization_id,),
            )
            return [int(row["employee_id"]) for row in await cur.fetchall()]

    async def insert_approval(
        self,
        conn: Conn,
        *,
        expense_id: int,
        actioned_by: int,
        action: str,
        comments: str | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expense_approvals (expense_id, actioned_by, action, comments)"
                " VALUES (%s, %s, %s, %s)"
                " RETURNING approval_id, expense_id, actioned_by, action, comments, actioned_at",
                (expense_id, actioned_by, action, comments),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def insert_media(
        self, conn: Conn, *, expense_id: int, receipt_url: str, description: str | None
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expense_media (expense_id, receipt_url, description)"
                " VALUES (%s, %s, %s) RETURNING " + _MEDIA_COLUMNS,
                (expense_id, receipt_url, description),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_media(self, conn: Conn, expense_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _MEDIA_COLUMNS + " FROM expense_media"
                " WHERE expense_id = %s ORDER BY media_id ASC",
                (expense_id,),
            )
            return list(await cur.fetchall())

    async def list_by_org(
        self,
        conn: Conn,
        organization_id: int,
        *,
        status: ExpenseStatus | None,
        from_date: date | None,
        to_date: date | None,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _EXPENSE_COLUMNS + " FROM expenses"
                " WHERE organization_id = %s"
                " AND (%s::text IS NULL OR status = %s::text)"
                " AND (%s::date IS NULL OR expense_date >= %s::date)"
                " AND (%s::date IS NULL OR expense_date <= %s::date)"
                " AND (%s::int IS NULL OR expense_id < %s::int)"
                " ORDER BY expense_id DESC LIMIT %s::int",
                (
                    organization_id,
                    None if status is None else status.value,
                    None if status is None else status.value,
                    from_date,
                    from_date,
                    to_date,
                    to_date,
                    before_id,
                    before_id,
                    limit,
                ),
            )
            return list(await cur.fetchall())

    async def list_pending(
        self, conn: Conn, organization_id: int, *, limit: int, before_id: int | None
    ) -> list[Row]:
        return await self.list_by_org(
            conn,
            organization_id,
            status=ExpenseStatus.PENDING,
            from_date=None,
            to_date=None,
            limit=limit,
            before_id=before_id,
        )
