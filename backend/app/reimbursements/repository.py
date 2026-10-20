"""Reimbursement persistence — raw SQL only (§5). All reads org-scoped (§8)."""

from __future__ import annotations

from decimal import Decimal

from app.core.constants import ReimbursementStatus
from app.db.types import Conn, Row

_REIMB_COLUMNS = (
    "reimbursement_id, expense_id, employee_id, organization_id, total_amount, "
    "payment_reference, payment_receipt_url, status, paid_at, created_at, updated_at"
)


class ReimbursementRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def get_expense(self, conn: Conn, expense_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT expense_id, employee_id, organization_id, amount, status"
                " FROM expenses WHERE expense_id = %s AND organization_id = %s",
                (expense_id, org_id),
            )
            return await cur.fetchone()

    async def get_by_id(self, conn: Conn, reimbursement_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _REIMB_COLUMNS + " FROM reimbursements"
                " WHERE reimbursement_id = %s AND organization_id = %s",
                (reimbursement_id, org_id),
            )
            return await cur.fetchone()

    async def get_by_id_for_update(
        self, conn: Conn, reimbursement_id: int, org_id: int
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _REIMB_COLUMNS + " FROM reimbursements"
                " WHERE reimbursement_id = %s AND organization_id = %s FOR UPDATE",
                (reimbursement_id, org_id),
            )
            return await cur.fetchone()

    async def create(
        self,
        conn: Conn,
        *,
        expense_id: int,
        employee_id: int,
        organization_id: int,
        total_amount: Decimal,
        payment_reference: str | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO reimbursements"
                " (expense_id, employee_id, organization_id, total_amount, payment_reference)"
                " VALUES (%s, %s, %s, %s, %s) RETURNING " + _REIMB_COLUMNS,
                (expense_id, employee_id, organization_id, str(total_amount), payment_reference),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def list_by_org(
        self,
        conn: Conn,
        organization_id: int,
        *,
        status: ReimbursementStatus | None,
        limit: int,
        before_id: int | None,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _REIMB_COLUMNS + " FROM reimbursements"
                " WHERE organization_id = %s"
                " AND (%s::text IS NULL OR status = %s::text)"
                " AND (%s::int IS NULL OR reimbursement_id < %s::int)"
                " ORDER BY reimbursement_id DESC LIMIT %s::int",
                (
                    organization_id,
                    None if status is None else status.value,
                    None if status is None else status.value,
                    before_id,
                    before_id,
                    limit,
                ),
            )
            return list(await cur.fetchall())

    async def update_transition(
        self,
        conn: Conn,
        reimbursement_id: int,
        *,
        status: ReimbursementStatus,
        payment_reference: str | None,
    ) -> Row | None:
        async with conn.cursor() as cur:
            if status == ReimbursementStatus.PAID:
                await cur.execute(
                    "UPDATE reimbursements SET status = %s, payment_reference = %s,"
                    " paid_at = NOW(), updated_at = NOW()"
                    " WHERE reimbursement_id = %s RETURNING " + _REIMB_COLUMNS,
                    (status.value, payment_reference, reimbursement_id),
                )
            else:
                await cur.execute(
                    "UPDATE reimbursements SET status = %s,"
                    " payment_reference = COALESCE(%s, payment_reference),"
                    " updated_at = NOW() WHERE reimbursement_id = %s RETURNING " + _REIMB_COLUMNS,
                    (status.value, payment_reference, reimbursement_id),
                )
            return await cur.fetchone()

    async def set_payment_receipt(
        self, conn: Conn, reimbursement_id: int, *, payment_receipt_url: str
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE reimbursements SET payment_receipt_url = %s, updated_at = NOW()"
                " WHERE reimbursement_id = %s RETURNING " + _REIMB_COLUMNS,
                (payment_receipt_url, reimbursement_id),
            )
            return await cur.fetchone()

    async def mark_expense_reimbursed(self, conn: Conn, expense_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE expenses SET status = 'reimbursed'"
                " WHERE expense_id = %s AND status = 'approved'"
                " RETURNING expense_id, status",
                (expense_id,),
            )
            return await cur.fetchone()
