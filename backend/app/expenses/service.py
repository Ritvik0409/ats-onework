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
from app.core.exceptions import (
    AuthorizationError,
    ConflictError,
    NotFoundError,
    ValidationError,
)
from app.core.security.tokens import utc_now_naive
from app.db.transaction import transaction
from app.db.types import Conn, Row
from app.expenses.repository import ExpenseRepository
from app.expenses.schemas import ApprovalActionRequest, ExpenseListItem, ExpenseResponse
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import NotificationCreate, NotificationResponse

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
        description: str | None = None,
        receipts: list[tuple[str, str | None]] | None = None,
        created_notifications: list[NotificationResponse] | None = None,
    ) -> ExpenseResponse:
        await self._require_member(conn, employee_id, organization_id)
        await self._require_project_in_org(conn, project_id, organization_id)
        expense_type = await self._require_expense_type_in_org(
            conn, expense_type_id, organization_id
        )
        self._check_expense_type_rules(expense_type, amount, receipts or [])
        async with transaction(conn):
            row = await self._repository.create(
                conn,
                employee_id=employee_id,
                project_id=project_id,
                organization_id=organization_id,
                expense_type_id=expense_type_id,
                amount=amount,
                expense_date=expense_date,
                description=description,
            )
            media_rows: list[Row] = []
            for url, media_description in receipts or []:
                media_rows.append(
                    await self._repository.insert_media(
                        conn,
                        expense_id=row["expense_id"],
                        receipt_url=url,
                        description=media_description,
                    )
                )
            await audit_service.log(
                conn,
                actor_id=employee_id,
                organization_id=organization_id,
                action="expense.submit",
                table_name="expenses",
                record_id=str(row["expense_id"]),
                new_values={"project_id": project_id, "amount": str(amount)},
            )
            await self._notify_admins(
                conn,
                organization_id=organization_id,
                notification=NotificationCreate(
                    employee_id=employee_id,
                    title="Expense submitted",
                    message=f"Expense #{row['expense_id']} is waiting for review.",
                    type="expense.submit",
                    reference_id=str(row["expense_id"]),
                ),
                skip_employee_id=employee_id,
                created_notifications=created_notifications,
            )
        return await self._load_detail(conn, row["expense_id"], organization_id, media_rows)

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

    # -- request-more-info / resubmit -------------------------------------

    async def request_info(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        payload: ApprovalActionRequest,
    ) -> ExpenseResponse:
        """Move a pending expense to ``info_requested`` with the manager's
        question persisted (migration 0003). repeats replace the question."""
        message = (payload.comments or "").strip()
        if not message:
            raise ValidationError("Requesting more info requires a message.")
        await self._require_admin(conn, actor_id, organization_id)
        async with transaction(conn):
            row = await self._repository.get_by_id_for_update(conn, expense_id, organization_id)
            if row is None:
                raise NotFoundError("Expense not found.")
            current = ExpenseStatus(row["status"])
            if ExpenseStatus.INFO_REQUESTED not in EXPENSE_TRANSITIONS[current]:
                raise ConflictError(f"Cannot request more info from an expense in {current.value}.")
            updated = await self._repository.update_status(
                conn,
                expense_id,
                status=ExpenseStatus.INFO_REQUESTED,
                rejection_reason=row["rejection_reason"],
                info_message=message[:500],
                info_requested_at=utc_now_naive(),
            )
            assert updated is not None
            # The question is kept in the approval history, so it survives
            # the employee answering it.
            await self._repository.insert_approval(
                conn,
                expense_id=expense_id,
                actioned_by=actor_id,
                action=ApprovalAction.INFO_REQUESTED.value,
                comments=message,
            )
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=organization_id,
                action="expense.info_requested",
                table_name="expenses",
                record_id=str(expense_id),
                old_values={"status": current.value},
                new_values={
                    "status": ExpenseStatus.INFO_REQUESTED.value,
                    "info_message": message[:500],
                },
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=int(row["employee_id"]),
                    title="Details needed for your expense",
                    message=(f"Expense #{expense_id}: {message[:400]}"),
                    type="expense.info_requested",
                    reference_id=str(expense_id),
                ),
            )
            return await self._load_detail(conn, expense_id, organization_id)

    async def resubmit(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        response: str | None = None,
    ) -> ExpenseResponse:
        """Employee (owner) moves an ``info_requested`` expense back to
        pending once details have been provided; org admins are notified.

        The manager's question and the employee's answer are both kept:
        the question stays on the expense and in the approval history, and
        the answer is stored in ``info_response``.
        """
        await self._require_member(conn, actor_id, organization_id)
        async with transaction(conn):
            row = await self._repository.get_by_id_for_update(conn, expense_id, organization_id)
            if row is None:
                raise NotFoundError("Expense not found.")
            if int(row["employee_id"]) != actor_id:
                raise AuthorizationError("Only the submitting employee can resubmit.")
            current = ExpenseStatus(row["status"])
            if ExpenseStatus.PENDING not in EXPENSE_TRANSITIONS[current]:
                raise ConflictError(f"Cannot resubmit an expense in {current.value}.")
            answer = (response or "").strip() or None
            updated = await self._repository.update_status(
                conn,
                expense_id,
                status=ExpenseStatus.PENDING,
                rejection_reason=row["rejection_reason"],
                info_message=row["info_message"],
                info_requested_at=row["info_requested_at"],
                info_response=answer,
            )
            assert updated is not None
            if answer is not None:
                await self._repository.insert_approval(
                    conn,
                    expense_id=expense_id,
                    actioned_by=actor_id,
                    action=ApprovalAction.INFO_ANSWERED.value,
                    comments=answer,
                )
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=organization_id,
                action="expense.resubmit",
                table_name="expenses",
                record_id=str(expense_id),
                old_values={"status": current.value},
                new_values={
                    "status": ExpenseStatus.PENDING.value,
                    "info_response": answer,
                },
            )
            await self._notify_admins(
                conn,
                organization_id=organization_id,
                notification=NotificationCreate(
                    employee_id=actor_id,
                    title="Expense updated after info request",
                    message=(f"Expense #{expense_id} is back in the pending queue."),
                    type="expense.resubmit",
                    reference_id=str(expense_id),
                ),
            )
            return await self._load_detail(conn, expense_id, organization_id)

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
            # Segregation of duties: nobody approves their own expense.
            if int(row["employee_id"]) == actor_id:
                raise AuthorizationError("You cannot review your own expense.")
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
                info_message=None,
                info_requested_at=None,
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
                organization_id=organization_id,
                action=f"expense.{action.value}",
                table_name="expenses",
                record_id=str(expense_id),
                old_values={"status": current.value},
                new_values={
                    "status": target.value,
                    "rejection_reason": (comments if target == ExpenseStatus.REJECTED else None),
                },
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
            return await self._load_detail(conn, expense_id, organization_id)

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

    async def _load_detail(
        self,
        conn: Conn,
        expense_id: int,
        organization_id: int,
        media_rows: list[Row] | None = None,
    ) -> ExpenseResponse:
        """Read the expense back with its names and receipts.

        Status changes return a bare row from the UPDATE; re-reading gives
        the same complete read model as every other expense response.
        """
        row = await self._repository.get_by_id(conn, expense_id, organization_id)
        if row is None:  # pragma: no cover — the row was just written
            raise NotFoundError("Expense not found.")
        if media_rows is None:
            media_rows = await self._repository.list_media(conn, expense_id)
        return self._to_response(row, media_rows)

    @staticmethod
    def _check_expense_type_rules(
        expense_type: Row,
        amount: Decimal,
        receipts: list[tuple[str, str | None]],
    ) -> None:
        """Enforce the expense type's receipt and amount rules.

        Both columns existed on ``expense_types`` but were never applied,
        so a category that declared "receipt required" accepted an expense
        with no receipt at all.
        """
        requires_receipt = bool(expense_type.get("requires_receipt"))
        if requires_receipt and not receipts:
            raise ValidationError("This expense type requires a receipt.")
        default_limit = expense_type.get("default_limit")
        if default_limit is not None and amount > Decimal(str(default_limit)):
            raise ValidationError(
                f"Amount exceeds the limit of {default_limit} for this expense type."
            )

    async def _notify_admins(
        self,
        conn: Conn,
        *,
        organization_id: int,
        notification: NotificationCreate,
        skip_employee_id: int | None = None,
        created_notifications: list[NotificationResponse] | None = None,
    ) -> None:
        """Fan a notification out to the organization's administrators.

        Rows are appended to ``created_notifications`` so the caller can
        schedule external delivery once the transaction has committed.
        """
        for admin_id in await self._repository.list_admin_ids(conn, organization_id):
            if skip_employee_id is not None and admin_id == skip_employee_id:
                continue
            row = await self._notifications.insert(
                conn, notification.model_copy(update={"employee_id": admin_id})
            )
            if created_notifications is not None:
                created_notifications.append(NotificationResponse.model_validate(row))

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
    ) -> Row:
        expense_type = await self._repository.get_expense_type(conn, expense_type_id)
        if expense_type is None or int(expense_type["organization_id"]) != org_id:
            raise NotFoundError("Expense type not found.")
        return expense_type


service = ExpenseService()
