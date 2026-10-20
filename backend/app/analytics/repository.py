"""Analytics persistence — tenant-scoped aggregate SQL (§5, §8).

Every query is parameterized and every organization read carries
``organization_id`` explicitly, so a dashboard can never leak another
tenant's totals. Status semantics match the budget module: **spend** is
``approved`` + ``reimbursed``; pending and rejected amounts are reported
separately rather than folded into spend.
"""

from __future__ import annotations

from datetime import date

from app.db.types import Conn, Row


def _expense_scope(employee_id: int | None) -> tuple[str, tuple[object, ...]]:
    """Optional owner filter appended to expense reads.

    The fragment is a fixed literal chosen here — never user input — so
    composing it into the statement cannot inject SQL.
    """
    if employee_id is None:
        return "", ()
    return " AND e.employee_id = %s", (employee_id,)


_SPEND_FILTER = "e.status IN ('approved', 'reimbursed')"


class AnalyticsRepository:
    async def get_membership(self, conn: Conn, employee_id: int, org_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id, employee_id, organization_id, is_admin"
                " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, org_id),
            )
            return await cur.fetchone()

    async def summary(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
        employee_id: int | None = None,
    ) -> Row:
        scope, scope_args = _expense_scope(employee_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT"
                f" COALESCE(SUM(e.amount) FILTER (WHERE {_SPEND_FILTER}), 0) AS total_spend,"
                " COUNT(*) FILTER (WHERE e.status = 'pending') AS pending_count,"
                " COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'pending'), 0) AS pending_amount,"
                " COUNT(*) FILTER (WHERE e.status = 'info_requested') AS info_requested_count,"
                " COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'info_requested'), 0)"
                "   AS info_requested_amount,"
                " COUNT(*) FILTER (WHERE e.status = 'approved') AS approved_count,"
                " COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'approved'), 0)"
                "   AS approved_amount,"
                " COUNT(*) FILTER (WHERE e.status = 'rejected') AS rejected_count,"
                " COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'rejected'), 0)"
                "   AS rejected_amount,"
                " COUNT(*) FILTER (WHERE e.status = 'reimbursed') AS reimbursed_count,"
                " COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'reimbursed'), 0)"
                "   AS reimbursed_amount,"
                " COUNT(*) AS total_claims,"
                " AVG(EXTRACT(EPOCH FROM GREATEST(a.decided_at - e.submission_date,"
                "     interval '0')) / 86400.0)"
                "   FILTER (WHERE a.decided_at IS NOT NULL) AS avg_approval_days"
                " FROM expenses e"
                " LEFT JOIN LATERAL ("
                "   SELECT MIN(ap.actioned_at) AS decided_at"
                "     FROM expense_approvals ap"
                "    WHERE ap.expense_id = e.expense_id"
                "      AND ap.organization_id = e.organization_id"
                "      AND ap.action IN ('approved', 'rejected')"
                " ) a ON TRUE"
                " WHERE e.organization_id = %s"
                + scope
                + " AND e.expense_date >= %s AND e.expense_date <= %s",
                (organization_id, *scope_args, from_date, to_date),
            )
            row = await cur.fetchone()
        return row or {}

    async def budget_allocated(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT COALESCE(SUM(amount), 0) AS budget FROM budgets"
                " WHERE organization_id = %s AND start_date <= %s AND end_date >= %s",
                (organization_id, to_date, from_date),
            )
            row = await cur.fetchone()
        return row or {}

    async def monthly(
        self,
        conn: Conn,
        *,
        organization_id: int,
        month_start: date,
        month_end: date,
        employee_id: int | None = None,
    ) -> list[Row]:
        """One row per calendar month, zero-filled by ``generate_series``."""
        scope, scope_args = _expense_scope(employee_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "WITH months AS ("
                "  SELECT generate_series(%s::date, %s::date, interval '1 month')::date"
                "    AS month_start"
                ")"
                " SELECT to_char(m.month_start, 'YYYY-MM') AS month,"
                "        to_char(m.month_start, 'Mon') AS label,"
                "        COALESCE(s.spend, 0) AS spend,"
                "        COALESCE(b.budget, 0) AS budget,"
                "        COALESCE(s.pending_count, 0) AS pending_count,"
                "        COALESCE(s.pending_amount, 0) AS pending_amount,"
                "        COALESCE(s.approved_count, 0) AS approved_count,"
                "        COALESCE(s.approved_amount, 0) AS approved_amount,"
                "        COALESCE(s.rejected_count, 0) AS rejected_count,"
                "        COALESCE(s.rejected_amount, 0) AS rejected_amount"
                "   FROM months m"
                "   LEFT JOIN LATERAL ("
                "     SELECT"
                f"       COALESCE(SUM(e.amount) FILTER (WHERE {_SPEND_FILTER}), 0) AS spend,"
                "       COUNT(*) FILTER (WHERE e.status = 'pending') AS pending_count,"
                "       COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'pending'), 0)"
                "         AS pending_amount,"
                "       COUNT(*) FILTER (WHERE e.status = 'approved') AS approved_count,"
                "       COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'approved'), 0)"
                "         AS approved_amount,"
                "       COUNT(*) FILTER (WHERE e.status = 'rejected') AS rejected_count,"
                "       COALESCE(SUM(e.amount) FILTER (WHERE e.status = 'rejected'), 0)"
                "         AS rejected_amount"
                "       FROM expenses e"
                "      WHERE e.organization_id = %s"
                + scope
                + "        AND e.expense_date >= m.month_start"
                "        AND e.expense_date < (m.month_start + interval '1 month')::date"
                "   ) s ON TRUE"
                "   LEFT JOIN LATERAL ("
                "     SELECT COALESCE(SUM(bd.amount), 0) AS budget"
                "       FROM budgets bd"
                "      WHERE bd.organization_id = %s"
                "        AND bd.start_date < (m.month_start + interval '1 month')::date"
                "        AND bd.end_date >= m.month_start"
                "   ) b ON TRUE"
                "  ORDER BY m.month_start",
                (
                    month_start,
                    month_end,
                    organization_id,
                    *scope_args,
                    organization_id,
                ),
            )
            return list(await cur.fetchall())

    async def categories(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
        employee_id: int | None = None,
        limit: int = 8,
    ) -> list[Row]:
        scope, scope_args = _expense_scope(employee_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT t.name AS name,"
                "       COALESCE(SUM(e.amount), 0) AS amount,"
                "       COUNT(*) AS count"
                "  FROM expenses e"
                "  JOIN expense_types t ON t.expense_type_id = e.expense_type_id"
                " WHERE e.organization_id = %s" + scope + f"   AND {_SPEND_FILTER}"
                "   AND e.expense_date >= %s AND e.expense_date <= %s"
                " GROUP BY t.name"
                " ORDER BY amount DESC, name ASC"
                " LIMIT %s::int",
                (organization_id, *scope_args, from_date, to_date, limit),
            )
            return list(await cur.fetchall())

    async def projects(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
        limit: int = 8,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT p.project_id,"
                "       p.name,"
                "       COALESCE(SUM(e.amount) FILTER"
                f"         (WHERE {_SPEND_FILTER}), 0) AS amount,"
                "       COUNT(e.expense_id) FILTER"
                f"         (WHERE {_SPEND_FILTER}) AS count,"
                "       b.amount AS budget"
                "  FROM projects p"
                "  JOIN budgets b ON b.budget_id = p.budget_id"
                "  LEFT JOIN expenses e"
                "    ON e.project_id = p.project_id"
                "   AND e.organization_id = b.organization_id"
                "   AND e.expense_date >= %s AND e.expense_date <= %s"
                " WHERE b.organization_id = %s"
                " GROUP BY p.project_id, p.name, b.amount"
                " ORDER BY amount DESC, p.name ASC"
                " LIMIT %s::int",
                (from_date, to_date, organization_id, limit),
            )
            return list(await cur.fetchall())

    async def aging(self, conn: Conn, *, organization_id: int) -> list[Row]:
        """Age of everything still waiting for a decision, org-wide.

        This deliberately ignores the chart window: an item waiting today
        is urgent regardless of which period the dashboard is showing.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT bucket, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount"
                "  FROM ("
                "    SELECT CASE"
                "             WHEN CURRENT_DATE - e.expense_date <= 2 THEN '0-2 days'"
                "             WHEN CURRENT_DATE - e.expense_date <= 7 THEN '3-7 days'"
                "             WHEN CURRENT_DATE - e.expense_date <= 14 THEN '8-14 days'"
                "             ELSE '15+ days'"
                "           END AS bucket,"
                "           e.amount"
                "      FROM expenses e"
                "     WHERE e.organization_id = %s"
                "       AND e.status IN ('pending', 'info_requested')"
                "  ) waiting"
                " GROUP BY bucket",
                (organization_id,),
            )
            return list(await cur.fetchall())

    async def top_spenders(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
        limit: int = 5,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT u.employee_id, u.name,"
                "       COALESCE(SUM(e.amount), 0) AS amount,"
                "       COUNT(*) AS count"
                "  FROM expenses e"
                "  JOIN users u ON u.employee_id = e.employee_id"
                " WHERE e.organization_id = %s"
                f"   AND {_SPEND_FILTER}"
                "   AND e.expense_date >= %s AND e.expense_date <= %s"
                " GROUP BY u.employee_id, u.name"
                " ORDER BY amount DESC, u.name ASC"
                " LIMIT %s::int",
                (organization_id, from_date, to_date, limit),
            )
            return list(await cur.fetchall())

    async def reimbursements(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT status, COUNT(*) AS count,"
                "       COALESCE(SUM(total_amount), 0) AS amount,"
                "       AVG(EXTRACT(EPOCH FROM (paid_at - created_at)) / 86400.0)"
                "         FILTER (WHERE status = 'paid' AND paid_at IS NOT NULL)"
                "         AS avg_payment_days"
                "  FROM reimbursements"
                " WHERE organization_id = %s"
                "   AND created_at::date >= %s AND created_at::date <= %s"
                " GROUP BY status",
                (organization_id, from_date, to_date),
            )
            return list(await cur.fetchall())

    async def status_breakdown(
        self,
        conn: Conn,
        *,
        organization_id: int,
        from_date: date,
        to_date: date,
        employee_id: int | None = None,
    ) -> list[Row]:
        scope, scope_args = _expense_scope(employee_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT status, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount"
                "  FROM expenses e"
                " WHERE e.organization_id = %s"
                + scope
                + "   AND e.expense_date >= %s AND e.expense_date <= %s"
                " GROUP BY status",
                (organization_id, *scope_args, from_date, to_date),
            )
            return list(await cur.fetchall())
