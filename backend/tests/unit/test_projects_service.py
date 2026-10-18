"""Project service behavior with in-memory doubles — no database.

Covers the new member-management surface (§49 #22-24): admin-only add
with default/explicit role resolution, org-member validation, duplicate
409, 404-scoping across orgs, and the notification on add/remove.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.core.exceptions import AuthorizationError, ConflictError, NotFoundError
from app.notifications.schemas import NotificationCreate
from app.projects import service as project_service_module
from app.projects.schemas import ProjectMemberAdd
from app.projects.service import ProjectService


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
    def __init__(self) -> None:
        self.project_orgs: dict[int, int] = {}  # project_id -> org (via budget)
        self.memberships: dict[tuple[int, int], dict[str, Any]] = {}
        self.members: dict[tuple[int, int], dict[str, Any]] = {}  # (project, employee)
        self.roles: dict[int, dict[str, Any]] = {}
        self.known_users: set[int] = set()
        self._next_member_id = 1

    # -- scoping -----------------------------------------------------------

    async def get_project_org(self, _conn: Any, project_id: int) -> int | None:
        return self.project_orgs.get(project_id)

    async def get_membership(
        self, _conn: Any, employee_id: int, org_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, org_id))

    async def get_employee_membership(
        self, _conn: Any, employee_id: int, organization_id: int
    ) -> dict[str, Any] | None:
        return self.memberships.get((employee_id, organization_id))

    # -- roles -------------------------------------------------------------

    async def get_default_role_id(self, _conn: Any, organization_id: int) -> dict[str, Any] | None:
        for row in self.roles.values():
            if row["organization_id"] == organization_id and row["name"] == "employee":
                return dict(row)
        return None

    async def get_role(self, _conn: Any, role_id: int) -> dict[str, Any] | None:
        row = self.roles.get(role_id)
        return dict(row) if row else None

    # -- members -----------------------------------------------------------

    async def list_members(
        self, _conn: Any, project_id: int, *, before_id: int | None, limit: int
    ) -> list[dict[str, Any]]:
        rows = [
            dict(row)
            for (pid, _eid), row in sorted(self.members.items())
            if pid == project_id and (before_id is None or row["project_member_id"] < before_id)
        ]
        return rows[:limit]

    async def is_project_member(self, _conn: Any, project_id: int, employee_id: int) -> bool:
        return (project_id, employee_id) in self.members

    async def insert_member(
        self, _conn: Any, *, project_id: int, employee_id: int, role_id: int
    ) -> dict[str, Any]:
        member_id = self._next_member_id
        self._next_member_id += 1
        role = self.roles[role_id]
        row = {
            "project_member_id": member_id,
            "project_id": project_id,
            "employee_id": employee_id,
            "role_id": role_id,
            "role_name": role["name"],
            "employee_name": f"User {employee_id}",
            "employee_email": f"user{employee_id}@example.com",
        }
        self.members[(project_id, employee_id)] = row
        return dict(row)

    async def delete_member(self, _conn: Any, project_id: int, employee_id: int) -> dict[str, Any]:
        row = self.members.pop((project_id, employee_id), None)
        return dict(row) if row else None


class _FakeTransaction:
    async def __aenter__(self) -> None:
        return None

    async def __aexit__(self, *exc: Any) -> None:
        return None


class _Conn:
    def transaction(self) -> _FakeTransaction:
        return _FakeTransaction()


@pytest.fixture
def deps() -> _RepositoryStub:
    repo = _RepositoryStub()
    repo.project_orgs[100] = 10
    repo.memberships[(1, 10)] = {"membership_id": 1, "is_admin": True, "employee_id": 1}
    repo.memberships[(2, 10)] = {"membership_id": 2, "is_admin": False, "employee_id": 2}
    repo.memberships[(5, 10)] = {"membership_id": 5, "is_admin": False, "employee_id": 5}
    repo.known_users = {1, 2, 5}
    repo.roles[11] = {"role_id": 11, "organization_id": 10, "name": "employee"}
    repo.roles[12] = {"role_id": 12, "organization_id": 10, "name": "lead"}
    repo.roles[13] = {"role_id": 13, "organization_id": 20, "name": "employee"}
    return repo


def _service(repo: _RepositoryStub, monkeypatch: pytest.MonkeyPatch) -> ProjectService:
    monkeypatch.setattr(project_service_module, "audit_service", _AuditStub())
    return ProjectService(repository=repo)  # type: ignore[arg-type]


async def test_add_member_default_role_and_notification(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    response = await _service(repo, monkeypatch).add_member(
        _Conn(),
        actor_id=1,
        project_id=100,
        payload=ProjectMemberAdd(employee_id=5),
    )
    assert response.employee_id == 5
    assert response.role_name == "employee"  # default role resolved
    assert (100, 5) in repo.members
    assert [n.type for n in notifications.sent] == ["project.member.added"]
    assert notifications.sent[0].employee_id == 5


async def test_add_member_duplicate_409(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    svc = _service(repo, monkeypatch)
    await svc.add_member(
        _Conn(), actor_id=1, project_id=100, payload=ProjectMemberAdd(employee_id=5)
    )
    with pytest.raises(ConflictError):
        await svc.add_member(
            _Conn(), actor_id=1, project_id=100, payload=ProjectMemberAdd(employee_id=5)
        )
    assert len(notifications.sent) == 1


async def test_add_member_not_in_org_404(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    with pytest.raises(NotFoundError):
        await _service(repo, monkeypatch).add_member(
            _Conn(), actor_id=1, project_id=100, payload=ProjectMemberAdd(employee_id=999)
        )
    assert notifications.sent == []


async def test_add_member_explicit_foreign_role_404(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    """role_id 13 belongs to org 20 — must read as 404, not be attached."""
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    with pytest.raises(NotFoundError):
        await _service(repo, monkeypatch).add_member(
            _Conn(),
            actor_id=1,
            project_id=100,
            payload=ProjectMemberAdd(employee_id=5, role_id=13),
        )


async def test_add_member_non_admin_403(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    with pytest.raises(AuthorizationError) as exc:
        await _service(repo, monkeypatch).add_member(
            _Conn(), actor_id=2, project_id=100, payload=ProjectMemberAdd(employee_id=5)
        )
    assert exc.value.status_code == 403


async def test_remove_member_notify_and_audit(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    svc = _service(repo, monkeypatch)
    await svc.add_member(
        _Conn(), actor_id=1, project_id=100, payload=ProjectMemberAdd(employee_id=5)
    )
    notifications.sent.clear()
    await svc.remove_member(_Conn(), actor_id=1, project_id=100, target_employee_id=5)
    assert (100, 5) not in repo.members
    assert [(n.type, n.employee_id) for n in notifications.sent] == [("project.member.removed", 5)]


async def test_remove_unknown_member_404(
    deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    with pytest.raises(NotFoundError):
        await _service(repo, monkeypatch).remove_member(
            _Conn(), actor_id=1, project_id=100, target_employee_id=5
        )


async def test_list_members_scoped(deps: _RepositoryStub, monkeypatch: pytest.MonkeyPatch) -> None:
    repo, notifications = deps, _NotificationsStub()
    monkeypatch.setattr(project_service_module, "_notifications", notifications)
    svc = _service(repo, monkeypatch)
    await svc.add_member(
        _Conn(), actor_id=1, project_id=100, payload=ProjectMemberAdd(employee_id=5)
    )
    items = await svc.list_members(_Conn(), employee_id=2, project_id=100, limit=10, before_id=None)
    assert [m.employee_id for m in items] == [5]
    with pytest.raises(NotFoundError):  # org the caller doesn't belong to
        repo.project_orgs[300] = 20
        await svc.list_members(_Conn(), employee_id=2, project_id=300, limit=10, before_id=None)
