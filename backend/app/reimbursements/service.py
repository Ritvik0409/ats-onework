"""Reimbursement business rules (§35-37, §49 #33-35).

Triple org-consistency (§9): the reimbursement org is the token org, the
employee and amount derive from the org-scoped expense row — a caller can
never mix an expense from Org B into Org A. Expense ``approved`` →
reimbursement ``pending → processing → paid`` flips the expense to
``reimbursed`` in the same transaction (§36-37).
"""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.permissions import has_permission
from app.common.tenant import require_path_admin, require_path_member
from app.core.constants import (
    REIMBURSEMENT_TRANSITIONS,
    ExpenseStatus,
    ReimbursementStatus,
)
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.db.transaction import transaction
from app.db.types import Conn, Row
from app.notifications.repository import NotificationRepository
from app.notifications.schemas import NotificationCreate
from app.reimbursements.repository import ReimbursementRepository
from app.reimbursements.schemas import (
    ReimbursementCreate,
    ReimbursementListItem,
    ReimbursementResponse,
    ReimbursementTransitionRequest,
)

_repository = ReimbursementRepository()
_notifications = NotificationRepository()


class ReimbursementService:
    def __init__(
        self,
        repository: ReimbursementRepository | None = None,
        notifications: NotificationRepository | None = None,
    ) -> None:
        self._repository = repository or _repository
        self._notifications = notifications or _notifications

    async def create_for_expense(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        expense_id: int,
        payload: ReimbursementCreate,
    ) -> ReimbursementResponse:
        await self._require_admin(conn, actor_id, organization_id)
        async with transaction(conn):
            expense = await self._repository.get_expense(conn, expense_id, organization_id)
            if expense is None:
                raise NotFoundError("Expense not found.")
            if ExpenseStatus(expense["status"]) != ExpenseStatus.APPROVED:
                raise ConflictError("Only approved expenses can be reimbursed.")
            row = await self._repository.create(
                conn,
                expense_id=expense_id,
                employee_id=int(expense["employee_id"]),
                organization_id=organization_id,
                total_amount=expense["amount"],
                payment_reference=payload.payment_reference,
            )
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=organization_id,
                action="reimbursement.create",
                table_name="reimbursements",
                record_id=str(row["reimbursement_id"]),
                new_values={"expense_id": expense_id, "total_amount": str(expense["amount"])},
            )
            return ReimbursementResponse.model_validate(row)

    async def list(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        status: ReimbursementStatus | None,
        limit: int,
        before_id: int | None,
    ) -> list[ReimbursementListItem]:
        await self._require_member(conn, employee_id, organization_id)
        # A caller who holds reimbursement.read_all sees the whole
        # organization; anyone else sees only their own. The scope is
        # decided by the capability, not by the client.
        can_read_all = await has_permission(
            conn,
            employee_id=employee_id,
            organization_id=organization_id,
            api_name="reimbursement.read_all",
        )
        rows = await self._repository.list_by_org(
            conn,
            organization_id,
            status=status,
            limit=limit,
            before_id=before_id,
            employee_id=None if can_read_all else employee_id,
        )
        return [ReimbursementListItem.model_validate(r) for r in rows]

    async def transition(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        reimbursement_id: int,
        payload: ReimbursementTransitionRequest,
    ) -> ReimbursementResponse:
        await self._require_admin(conn, actor_id, organization_id)
        if (
            payload.target_status == ReimbursementStatus.PAID
            and not (payload.payment_reference or "").strip()
        ):
            raise ValidationError("Paid reimbursements require a payment reference.")
        async with transaction(conn):
            current = await self._repository.get_by_id_for_update(
                conn, reimbursement_id, organization_id
            )
            if current is None:
                raise NotFoundError("Reimbursement not found.")
            cur_status = ReimbursementStatus(current["status"])
            if payload.target_status not in REIMBURSEMENT_TRANSITIONS[cur_status]:
                raise ConflictError(f"Cannot transition reimbursement from {cur_status.value}.")
            updated = await self._repository.update_transition(
                conn,
                reimbursement_id,
                status=payload.target_status,
                payment_reference=payload.payment_reference,
            )
            assert updated is not None
            if payload.target_status == ReimbursementStatus.PAID:
                marked = await self._repository.mark_expense_reimbursed(
                    conn, int(current["expense_id"])
                )
                if marked is None:
                    raise ConflictError("Linked expense is no longer approved.")
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=organization_id,
                action=f"reimbursement.{payload.target_status.value}",
                table_name="reimbursements",
                record_id=str(reimbursement_id),
                old_values={"status": cur_status.value},
                new_values={"status": payload.target_status.value},
            )
            await self._notifications.insert(
                conn,
                NotificationCreate(
                    employee_id=int(current["employee_id"]),
                    title=f"Reimbursement {payload.target_status.value}",
                    message=f"Reimbursement #{reimbursement_id} is {payload.target_status.value}.",
                    type=f"reimbursement.{payload.target_status.value}",
                    reference_id=str(reimbursement_id),
                ),
            )
            return ReimbursementResponse.model_validate(updated)

    async def attach_payment_receipt(
        self,
        conn: Conn,
        *,
        actor_id: int,
        organization_id: int,
        reimbursement_id: int,
        payment_receipt_url: str,
    ) -> ReimbursementResponse:
        """Store the receipt that proves a payout was made.

        Only a paid reimbursement can carry one: a receipt for money that
        has not moved yet says nothing.
        """
        await self._require_admin(conn, actor_id, organization_id)
        async with transaction(conn):
            current = await self._repository.get_by_id_for_update(
                conn, reimbursement_id, organization_id
            )
            if current is None:
                raise NotFoundError("Reimbursement not found.")
            if ReimbursementStatus(current["status"]) != ReimbursementStatus.PAID:
                raise ConflictError(
                    "A payment receipt can only be attached to a paid reimbursement."
                )
            updated = await self._repository.set_payment_receipt(
                conn, reimbursement_id, payment_receipt_url=payment_receipt_url
            )
            assert updated is not None
            await audit_service.log(
                conn,
                actor_id=actor_id,
                organization_id=organization_id,
                action="reimbursement.receipt_attached",
                table_name="reimbursements",
                record_id=str(reimbursement_id),
                new_values={"payment_receipt_url": payment_receipt_url},
            )
            return ReimbursementResponse.model_validate(updated)

    async def _require_member(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_member(await self._repository.get_membership(conn, employee_id, org_id))

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = ReimbursementService()
