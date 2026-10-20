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
    """expenses.status CHECK constraint (0001 + migration 0003)."""

    PENDING = "pending"
    INFO_REQUESTED = "info_requested"
    APPROVED = "approved"
    REJECTED = "rejected"
    REIMBURSED = "reimbursed"


class ApprovalAction(StrEnum):
    """expense_approvals.action CHECK constraint (migration 0004)."""

    APPROVED = "approved"
    REJECTED = "rejected"
    INFO_REQUESTED = "info_requested"
    INFO_ANSWERED = "info_answered"


class ReimbursementStatus(StrEnum):
    """reimbursements.status CHECK constraint."""

    PENDING = "pending"
    PROCESSING = "processing"
    PAID = "paid"
    FAILED = "failed"


# Status transition maps (§36) — arbitrary transitions are forbidden; services
# consult these before persisting any status change.
EXPENSE_TRANSITIONS: dict[ExpenseStatus, set[ExpenseStatus]] = {
    ExpenseStatus.PENDING: {
        ExpenseStatus.INFO_REQUESTED,
        ExpenseStatus.APPROVED,
        ExpenseStatus.REJECTED,
    },
    # An answered info request goes back to the review queue, or the
    # manager can still decide directly without waiting for a resubmit.
    ExpenseStatus.INFO_REQUESTED: {
        ExpenseStatus.PENDING,
        ExpenseStatus.APPROVED,
        ExpenseStatus.REJECTED,
    },
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


class ProjectAccessStatus(StrEnum):
    """project_access_requests.status CHECK constraint (migration 0002)."""

    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


PROJECT_ACCESS_TRANSITIONS: dict[ProjectAccessStatus, set[ProjectAccessStatus]] = {
    ProjectAccessStatus.PENDING: {ProjectAccessStatus.APPROVED, ProjectAccessStatus.REJECTED},
    ProjectAccessStatus.APPROVED: set(),
    ProjectAccessStatus.REJECTED: set(),
}

# Pagination bounds (§21)
DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100
