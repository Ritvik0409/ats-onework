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
    "amount, status, rejection_reason, description, expense_date, submission_date, "
    "updated_at, info_message, info_requested_at, info_response"
)

# The list/detail shapes carry the names a client would otherwise have to
# resolve with three extra round-trips (and would get wrong, since the
# expense only stores the ids). Joined here so the read model is complete.
_EXPENSE_JOINED_COLUMNS = (
    "e.expense_id, e.employee_id, e.project_id, e.organization_id, e.expense_type_id, "
    "e.amount, e.status, e.rejection_reason, e.description, e.expense_date, "
    "e.submission_date, e.updated_at, e.info_message, e.info_requested_at, e.info_response, "
    "u.name AS employee_name, u.email AS employee_email, "
    "p.name AS project_name, t.name AS expense_type_name"
)

_EXPENSE_JOINS = (
    " FROM expenses e"
    " JOIN users u ON u.employee_id = e.employee_id"
    " JOIN projects p ON p.project_id = e.project_id"
    " JOIN expense_types t ON t.expense_type_id = e.expense_type_id"
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

    async def get_expense_type(self, conn: Conn, expense_type_id: int) -> Row | None:
        """The expense type's rules — organization, receipt and limit."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT expense_type_id, name, organization_id, requires_receipt, default_limit"
                " FROM expense_types WHERE expense_type_id = %s",
                (expense_type_id,),
            )
            return await cur.fetchone()

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
        description: str | None = None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO expenses"
                " (employee_id, project_id, organization_id, expense_type_id, amount,"
                " expense_date, description)"
                " VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING " + _EXPENSE_COLUMNS,
                (
                    employee_id,
                    project_id,
                    organization_id,
                    expense_type_id,
                    str(amount),
                    expense_date,
                    description,
                ),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def get_by_id(self, conn: Conn, expense_id: int, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _EXPENSE_JOINED_COLUMNS
                + _EXPENSE_JOINS
                + " WHERE e.expense_id = %s AND e.organization_id = %s",
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
        info_response: str | None = None,
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE expenses SET status = %s, rejection_reason = %s,"
                " info_message = %s, info_requested_at = %s, info_response = %s"
                " WHERE expense_id = %s RETURNING " + _EXPENSE_COLUMNS,
                (
                    status.value,
                    rejection_reason,
                    info_message,
                    info_requested_at,
                    info_response,
                    expense_id,
                ),
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
        employee_id: int | None = None,
    ) -> list[Row]:
        """List expenses, newest first.

        ``employee_id`` narrows the list to one submitter — the scope an
        employee without ``expense.read_all`` is given.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _EXPENSE_JOINED_COLUMNS
                + _EXPENSE_JOINS
                + " WHERE e.organization_id = %s"
                " AND (%s::text IS NULL OR e.status = %s::text)"
                " AND (%s::date IS NULL OR e.expense_date >= %s::date)"
                " AND (%s::date IS NULL OR e.expense_date <= %s::date)"
                " AND (%s::int IS NULL OR e.expense_id < %s::int)"
                " AND (%s::int IS NULL OR e.employee_id = %s::int)"
                " ORDER BY e.expense_id DESC LIMIT %s::int",
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
                    employee_id,
                    employee_id,
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
