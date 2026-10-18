"""Expense service behavior with in-memory doubles — no database.

Covers the info-request lifecycle added by migration 0003 + §49 #33:
request-info (admin, message required), resubmit (owner-only, notifies
admins), and the transition guards (409) around both.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.core.constants import ExpenseStatus
from app.core.exceptions import (
    AuthorizationError,
    ConflictError,
    ValidationError,
)
from app.expenses import service as expense_service_module
from app.expenses.schemas import ApprovalActionRequest
from app.expenses.service import ExpenseService
from app.notifications.schemas import NotificationCreate


class _AuditStub:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    async def log(self, _conn: Any, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        return {"log_id": len(self.calls)}


class _NotificationsStub:
    def __init__(self) -> None:
        self.sent: list[NotificationCreate] = []

    async def insert(self, _conn: Any, payload: NotificationCreate) -> dict[str, Any]:
        self.sent.append(payload)
        return {"notification_id": len(self.sent)}


class _RepositoryStub:
    """Stores expense rows as mutable dicts — mirrors update_status."""

    def __init__(self) -> None:
        self.expenses: dict[int, dict[str, Any]] = {}
        self.memberships: dict[tuple[int, int], dict[str, Any]] = {}
        self.admin_ids: list[int] = []

    # -- service surface ---------------------------------------------------

    async def get_membership(
        self, _conn: Any, employee_id: int, org_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, org_id))

    async def list_admin_ids(self, _conn: Any, _organization_id: int) -> list[int]:
        return list(self.admin_ids)

    async def get_by_id_for_update(
        self, _conn: Any, expense_id: int, _organization_id: int
    ) -> dict[str, Any] | None:
        return self.expenses.get(expense_id)

    async def update_status(
        self,
        _conn: Any,
        expense_id: int,
        *,
        status: ExpenseStatus,
        rejection_reason: str | None,
        info_message: str | None,
        info_requested_at: Any,
    ) -> dict[str, Any] | None:
        row = self.expenses.get(expense_id)
        if row is None:
            return None
        row["status"] = status.value
        row["rejection_reason"] = rejection_reason
        row["info_message"] = info_message
        row["info_requested_at"] = info_requested_at
        return dict(row)

    async def list_media(self, _conn: Any, expense_id: int) -> list[dict[str, Any]]:  # noqa: ARG002
        return []

    async def insert_approval(
        self,
        _conn: Any,
        *,
        expense_id: int,
        actioned_by: int,
        action: str,
        comments: str | None,
    ) -> dict[str, Any]:
        return {
            "approval_id": len(self.expenses) + 100,
            "expense_id": expense_id,
            "actioned_by": actioned_by,
            "action": action,
            "comments": comments,
            "actioned_at": None,
        }


def _expense(
    expense_id: int,
    employee_id: int = 5,
    organization_id: int = 10,
    status: str = ExpenseStatus.PENDING.value,
) -> dict[str, Any]:
    return {
        "expense_id": expense_id,
        "employee_id": employee_id,
        "project_id": 100,
        "organization_id": organization_id,
        "expense_type_id": 3,
        "amount": "1200.50",
        "status": status,
        "rejection_reason": None,
        "expense_date": "2026-10-01",
        "submission_date": "2026-10-02T09:00:00",
        "updated_at": "2026-10-02T09:00:00",
        "info_message": None,
        "info_requested_at": None,
    }


class _FakeTransaction:
    async def __aenter__(self) -> None:
        return None

    async def __aexit__(self, *exc: Any) -> None:
        return None


class _Conn:
    def transaction(self) -> _FakeTransaction:
        return _FakeTransaction()


@pytest.fixture
def deps() -> tuple[_RepositoryStub, _NotificationsStub, _AuditStub]:
    repo = _RepositoryStub()
    repo.memberships[(1, 10)] = {"membership_id": 1, "is_admin": True, "employee_id": 1}
    repo.memberships[(2, 10)] = {"membership_id": 2, "is_admin": False, "employee_id": 2}
    repo.memberships[(5, 10)] = {"membership_id": 5, "is_admin": False, "employee_id": 5}
    repo.admin_ids = [1]
    repo.expenses[7] = _expense(7)
    repo.expenses[8] = _expense(8, status=ExpenseStatus.INFO_REQUESTED.value, employee_id=5)
    repo.expenses[9] = _expense(9, status=ExpenseStatus.APPROVED.value, employee_id=5)
    return repo, _NotificationsStub(), _AuditStub()


def _service(repo: _RepositoryStub, notifications: _NotificationsStub) -> ExpenseService:
    return ExpenseService(repository=repo, notifications=notifications)  # type: ignore[arg-type]


def _patch_audit(monkeypatch: pytest.MonkeyPatch, audit: _AuditStub) -> None:
    monkeypatch.setattr(expense_service_module, "audit_service", audit)


# -- request-info ----------------------------------------------------------


async def test_request_info_happy_path(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo, notifications, audit = deps
    _patch_audit(monkeypatch, audit)
    response = await _service(repo, notifications).request_info(
        _Conn(),
        actor_id=1,
        organization_id=10,
        expense_id=7,
        payload=ApprovalActionRequest(comments="Attach itemized receipt"),
    )
    assert response.status == ExpenseStatus.INFO_REQUESTED
    assert response.info_message == "Attach itemized receipt"
    assert repo.expenses[7]["info_message"] == "Attach itemized receipt"
    assert repo.expenses[7]["info_requested_at"] is not None
    # Exactly one notification, addressed to the submitting employee.
    assert [n.employee_id for n in notifications.sent] == [5]
    assert "Expense #7" in notifications.sent[0].message
    assert audit.calls[-1]["action"] == "expense.info_requested"


async def test_request_info_requires_message(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo, notifications, audit = deps
    _patch_audit(monkeypatch, audit)
    with pytest.raises(ValidationError):
        await _service(repo, notifications).request_info(
            _Conn(),
            actor_id=1,
            organization_id=10,
            expense_id=7,
            payload=ApprovalActionRequest(comments="   "),
        )
    assert repo.expenses[7]["status"] == ExpenseStatus.PENDING.value
    assert notifications.sent == []
    assert audit.calls == []


async def test_request_info_on_decided_expense_409(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Approved and reimbursed expenses are decided — no info requests."""
    repo, notifications, audit = deps
    _patch_audit(monkeypatch, audit)
    with pytest.raises(ConflictError):
        await _service(repo, notifications).request_info(
            _Conn(),
            actor_id=1,
            organization_id=10,
            expense_id=9,
            payload=ApprovalActionRequest(comments="Why?"),
        )
    assert repo.expenses[9]["status"] == ExpenseStatus.APPROVED.value


async def test_request_info_non_admin_forbidden(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
) -> None:
    repo, notifications, _ = deps
    with pytest.raises(AuthorizationError) as exc:
        await _service(repo, notifications).request_info(
            _Conn(),
            actor_id=2,
            organization_id=10,
            expense_id=7,
            payload=ApprovalActionRequest(comments="Why?"),
        )
    assert exc.value.status_code == 403


# -- resubmit --------------------------------------------------------------


async def test_resubmit_happy_path_notifies_admins(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repo, notifications, audit = deps
    _patch_audit(monkeypatch, audit)
    repo.expenses[8]["info_message"] = "Where is the invoice?"
    response = await _service(repo, notifications).resubmit(
        _Conn(), actor_id=5, organization_id=10, expense_id=8
    )
    assert response.status == ExpenseStatus.PENDING
    assert response.info_message is None
    assert repo.expenses[8]["info_message"] is None
    assert [n.type for n in notifications.sent] == ["expense.resubmit"]
    assert [n.employee_id for n in notifications.sent] == [1]


async def test_resubmit_owner_only(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
) -> None:
    repo, notifications, _ = deps
    with pytest.raises(AuthorizationError):
        await _service(repo, notifications).resubmit(
            _Conn(), actor_id=2, organization_id=10, expense_id=8
        )
    assert repo.expenses[8]["status"] == ExpenseStatus.INFO_REQUESTED.value
    assert notifications.sent == []


async def test_resubmit_pending_expense_409(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
) -> None:
    repo, notifications, _ = deps
    with pytest.raises(ConflictError):
        await _service(repo, notifications).resubmit(
            _Conn(), actor_id=5, organization_id=10, expense_id=7
        )


# -- decided expenses still reachable through transitions -------------------


async def test_approve_after_info_request(
    deps: tuple[_RepositoryStub, _NotificationsStub, _AuditStub],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Managers can decide directly without waiting for a resubmit."""
    repo, notifications, audit = deps
    _patch_audit(monkeypatch, audit)
    response = await _service(repo, notifications).approve(
        _Conn(),
        actor_id=1,
        organization_id=10,
        expense_id=8,
        payload=ApprovalActionRequest(comments=None),
    )
    assert response.status == ExpenseStatus.APPROVED
    assert repo.expenses[8]["status"] == ExpenseStatus.APPROVED.value
