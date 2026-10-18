"""Expense business rules — submit / approve / reject (§35-37, §49 #27-32).

Tenant model (§8): the token's org is the expense org. Project and
expense-type IDs from another org read as 404 (never 403) so callers
cannot probe other tenants. Status transitions follow
``EXPENSE_TRANSITIONS`` (§36) — anything else is 409.

Multi-write workflows (submit = expense + media + audit; approve/reject =
lock + status + approval row + audit + notification) share the
request-scoped connection; ``transaction()`` scopes them explicitly (§7)
so partial writes never survive.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from app.common.audit import service as audit_service
from app.common.tenant import require_path_admin, require_path_member
from app.core.constants import EXPENSE_TRANSITIONS, ApprovalAction, ExpenseStatus
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.db.transaction import transaction
from app.db.types import Conn, Row
from app.expenses.repository import ExpenseRepository
from app.expenses.schemas import ApprovalActionRequest, ExpenseListItem, ExpenseResponse
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import NotificationCreate

_repository = ExpenseRepository()
_notifications = NotificationRepository()


class ExpenseService:
    def __init__(
        self,
        repository: ExpenseRepository | None = None,
        notifications: NotificationRepository | None = None,
    ) -> None:
        self._repository = repository or _repository
        self._notifications = notifications or _notifications

    # -- submit ----------------------------------------------------------

    async def submit(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        project_id: int,
        expense_type_id: int,
        amount: Decimal,
        expense_date: date,
        receipts: list[tuple[str, str | None]] | None = None,
    ) -> ExpenseResponse:
        await self._require_member(conn, employee_id, organization_id)
        await self._require_project_in_org(conn, project_id, organization_id)
        await self._require_expense_type_in_org(conn, expense_type_id, organization_id)
        async with transaction(conn):
            row = await self._repository.create(
                conn,
                employee_id=employee_id,
                project_id=project_id,
                organization_id=organization_id,
                expense_type_id=expense_type_id,
                amount=amount,
                expense_date=expense_date,
            )
            media_rows: list[Row] = []
            for url, description in receipts or []:
                media_rows.append(
                    await self._repository.insert_media(
                        conn, expense_id=row["expense_id"], receipt_url=url, description=description
                    )
                )
            await audit_service.log(
                conn,
                actor_id=employee_id,
                action="expense.submit",
                table_name="expenses",
                record_id=str(row["expense_id"]),
                new_values={"project_id": project_id, "amount": str(amount)},
            )
        return self._to_response(row, media_rows)

    # -- reads -----------------------------------------------------------

    async def get(
        self, conn: Conn, *, employee_id: int, organization_id: int, expense_id: int
    ) -> ExpenseResponse:
        await self._require_member(conn, employee_id, organization_id)
        row = await self._repository.get_by_id(conn, expense_id, organization_id)
        if row is None:
            raise NotFoundError("Expense not found.")
        media = await self._repository.list_media(conn, expense_id)
        return self._to_response(row, media)

    async def list(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        status: ExpenseStatus | None,
        from_date: date | None,
        to_date: date | None,
        limit: int,
        before_id: int | None,
    ) -> list[ExpenseListItem]:
        await self._require_member(conn, employee_id, organization_id)
        rows = await self._repository.list_by_org(
            conn,
            organization_id,
            status=status,
            from_date=from_date,
            to_date=to_date,
            limit=limit,
            before_id=before_id,
        )
        return [ExpenseListItem.model_validate(r) for r in rows]

    async def list_pending(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        limit: int,
        before_id: int | None,
    ) -> list[ExpenseListItem]:
        await self._require_admin(conn, employee_id, organization_id)
        rows = await self._repository.list_pending(
            conn, organization_id, limit=limit, before_id=before_id
        )
        return [ExpenseListItem.model_validate(r) for r in rows]

    # -- approve / reject -------------------------------------------------

    async def approve(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        payload: ApprovalActionRequest,
    ) -> ExpenseResponse:
        return await self._decide(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            expense_id=expense_id,
            action=ApprovalAction.APPROVED,
            comments=payload.comments,
        )

    async def reject(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        payload: ApprovalActionRequest,
    ) -> ExpenseResponse:
        if not (payload.comments or "").strip():
            raise ValidationError("Rejection requires comments.")
        return await self._decide(
            conn,
            actor_id=actor_id,
            organization_id=organization_id,
            expense_id=expense_id,
            action=ApprovalAction.REJECTED,
            comments=payload.comments,
        )

    async def _decide(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        action: ApprovalAction,
        comments: str | None,
    ) -> ExpenseResponse:
        await self._require_admin(conn, actor_id, organization_id)
        async with transaction(conn):
            row = await self._repository.get_by_id_for_update(conn, expense_id, organization_id)
            if row is None:
                raise NotFoundError("Expense not found.")
            current = ExpenseStatus(row["status"])
            target = (
                ExpenseStatus.APPROVED
                if action == ApprovalAction.APPROVED
                else ExpenseStatus.REJECTED
            )
            if target not in EXPENSE_TRANSITIONS[current]:
                raise ConflictError(f"Cannot transition expense from {current.value}.")
            updated = await self._repository.update_status(
                conn,
                expense_id,
                status=target,
                rejection_reason=comments if target == ExpenseStatus.REJECTED else None,
            )
            assert updated is not None
            await self._repository.insert_approval(
                conn,
                expense_id=expense_id,
                actioned_by=actor_id,
                action=action.value,
                comments=comments,
            )
            await audit_service.log(
                conn,
                actor_id=actor_id,
                action=f"expense.{action.value}",
                table_name="expenses",
                record_id=str(expense_id),
                old_values={"status": current.value},
                new_values={"status": target.value},
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=int(row["employee_id"]),
                    title=f"Expense {target.value}",
                    message=f"Expense #{expense_id} was {target.value}.",
                    type=f"expense.{target.value}",
                    reference_id=str(expense_id),
                ),
            )
            media = await self._repository.list_media(conn, expense_id)
            return self._to_response(updated, media)

    # -- helpers ----------------------------------------------------------

    def _to_response(self, row: Row, media_rows: list[Row]) -> ExpenseResponse:
        data = dict(row)
        data["receipts"] = [
            {
                "media_id": m["media_id"],
                "expense_id": m["expense_id"],
                "receipt_url": m["receipt_url"],
                "description": m.get("description"),
                "uploaded_at": m["uploaded_at"],
            }
            for m in media_rows
        ]
        return ExpenseResponse.model_validate(data)

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_project_in_org(self, conn: Conn, project_id: int, org_id: int) -> None:
        actual = await self._repository.get_project_org(conn, project_id)
        if actual is None or actual != org_id:
            raise NotFoundError("Project not found.")

    async def _require_expense_type_in_org(
        self, conn: Conn, expense_type_id: int, org_id: int
    ) -> None:
        actual = await self._repository.get_expense_type_org(conn, expense_type_id)
        if actual is None or actual != org_id:
            raise NotFoundError("Expense type not found.")


service = ExpenseService()
