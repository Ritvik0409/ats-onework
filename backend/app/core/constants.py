"""System-wide constants (arch. doc: constants ↔ schema sync).

``StrEnum`` values mirror the PostgreSQL ``CHECK`` constraints exactly —
Pydantic models validate against these enums and SQL literals come from the
same source, so the two can never drift (single source of truth).
"""

from __future__ import annotations

from enum import StrEnum


class AccountStatus(StrEnum):
    """users.account_status CHECK constraint."""

    ACTIVE = "active"
    SUSPENDED = "suspended"
    LOCKED = "locked"
    INACTIVE = "inactive"


class EmployeeStatus(StrEnum):
    """employee_status.status CHECK constraint (temporal lifecycle log)."""

    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"
    ON_LEAVE = "on_leave"


class TokenPurpose(StrEnum):
    """authentication_tokens.purpose CHECK constraint."""

    LOGIN = "login"
    RESET_PASSWORD = "reset_password"
    REFRESH = "refresh"
    VERIFY_EMAIL = "verify_email"


class ExpenseStatus(StrEnum):
    """expenses.status CHECK constraint."""

    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    REIMBURSED = "reimbursed"


class ApprovalAction(StrEnum):
    """expense_approvals.action CHECK constraint."""

    APPROVED = "approved"
    REJECTED = "rejected"


class ReimbursementStatus(StrEnum):
    """reimbursements.status CHECK constraint."""

    PENDING = "pending"
    PROCESSING = "processing"
    PAID = "paid"
    FAILED = "failed"


# Status transition maps (§36) — arbitrary transitions are forbidden; services
# consult these before persisting any status change.
EXPENSE_TRANSITIONS: dict[ExpenseStatus, set[ExpenseStatus]] = {
    ExpenseStatus.PENDING: {ExpenseStatus.APPROVED, ExpenseStatus.REJECTED},
    ExpenseStatus.APPROVED: {ExpenseStatus.REIMBURSED},
    ExpenseStatus.REJECTED: set(),
    ExpenseStatus.REIMBURSED: set(),
}

REIMBURSEMENT_TRANSITIONS: dict[ReimbursementStatus, set[ReimbursementStatus]] = {
    ReimbursementStatus.PENDING: {ReimbursementStatus.PROCESSING},
    ReimbursementStatus.PROCESSING: {ReimbursementStatus.PAID, ReimbursementStatus.FAILED},
    ReimbursementStatus.PAID: set(),
    # Failed payouts may be retried by moving them back to processing.
    ReimbursementStatus.FAILED: {ReimbursementStatus.PROCESSING},
}

# Pagination bounds (§21)
DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100
