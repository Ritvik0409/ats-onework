"""User business rules — profile reads, admin updates, status log
(arch. doc §35; contracts §49 #8-12).

Authorization split (§10): the router enforces the admin gate via
``require_admin``; the service enforces existence (404) and the
single-active status invariant (409). Tenant note — users are global rows;
organization scoping for the *read* surface is derived from the caller's
membership, and admin membership is the gate for list/update/status writes.
"""

from __future__ import annotations

from app.common.audit import service as audit_service
from app.common.pagination import Page, decode_cursor, encode_cursor
from app.core.constants import AccountStatus
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.db.types import Conn
from app.users.repository import UserRepository
from app.users.schemas import (
    EmployeeStatusCreate,
    EmployeeStatusResponse,
    UserListItem,
    UserResponse,
    UserUpdate,
)

_repository = UserRepository()


class UserService:
    def __init__(self, repository: UserRepository | None = None) -> None:
        self._repository = repository or _repository

    async def get_me(self, conn: Conn, employee_id: int) -> UserResponse:
        row = await self._repository.get_by_id(conn, employee_id)
        if row is None:
            raise NotFoundError("User not found.")
        return UserResponse.model_validate(row)

    async def list_users(
        self,
        conn: Conn,
        *,
        limit: int,
        cursor: str | None,
        search: str | None = None,
        account_status: AccountStatus | None = None,
    ) -> Page[UserListItem]:
        after_id: int | None = None
        if cursor is not None:
            try:
                after_id = int(decode_cursor(cursor).get("after_id", 0)) or None
            except (TypeError, ValueError) as exc:
                # TypeError: crafted cursor with a non-numeric after_id
                # (e.g. {"after_id": null}) — still a 422, never a 500.
                raise ValidationError("Invalid pagination cursor.") from exc
        rows = await self._repository.list_users(
            conn,
            limit=limit,
            after_id=after_id,
            search=search,
            account_status=account_status,
        )
        next_cursor: str | None = None
        if len(rows) > limit:
            rows = rows[:limit]
            next_cursor = encode_cursor(after_id=rows[-1]["employee_id"])
        return Page(
            items=[UserListItem.model_validate(row) for row in rows],
            next_cursor=next_cursor,
        )

    async def update_user(
        self,
        conn: Conn,
        *,
        actor_id: int,
        employee_id: int,
        payload: UserUpdate,
    ) -> UserResponse:
        current = await self._repository.get_by_id(conn, employee_id)
        if current is None:
            raise NotFoundError("User not found.")
        if not payload.model_dump(exclude_unset=True):
            # No-op PATCH — return current state without writing a
            # misleading audit row claiming something changed.
            return UserResponse.model_validate(current)
        row = await self._repository.update_user(
            conn,
            employee_id,
            name=payload.name,
            account_status=payload.account_status,
            is_superuser=payload.is_superuser,
        )
        if row is None:  # pragma: no cover — guarded above; race safety
            raise NotFoundError("User not found.")
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="user.update",
            table_name="users",
            record_id=str(employee_id),
            old_values={
                "name": current["name"],
                "account_status": current["account_status"],
                "is_superuser": current["is_superuser"],
            },
            new_values={
                "name": row["name"],
                "account_status": row["account_status"],
                "is_superuser": row["is_superuser"],
            },
        )
        return UserResponse.model_validate(row)

    async def list_statuses(self, conn: Conn, employee_id: int) -> list[EmployeeStatusResponse]:
        if await self._repository.get_by_id(conn, employee_id) is None:
            raise NotFoundError("User not found.")
        rows = await self._repository.list_statuses(conn, employee_id)
        return [EmployeeStatusResponse.model_validate(row) for row in rows]

    async def create_status(
        self,
        conn: Conn,
        *,
        actor_id: int,
        employee_id: int,
        payload: EmployeeStatusCreate,
    ) -> EmployeeStatusResponse:
        if await self._repository.get_by_id(conn, employee_id) is None:
            raise NotFoundError("User not found.")
        active = await self._repository.get_active_status(conn, employee_id)
        if active is not None:
            raise ConflictError(
                "This user already has an active status entry. End it before opening a new one."
            )
        row = await self._repository.create_status(
            conn,
            employee_id=employee_id,
            status=payload.status,
            updated_by=actor_id,
        )
        await audit_service.log(
            conn,
            actor_id=actor_id,
            action="user.status.create",
            table_name="employee_status",
            record_id=str(row["status_id"]),
            new_values={
                "employee_id": employee_id,
                "status": row["status"],
            },
        )
        return EmployeeStatusResponse.model_validate(row)


service = UserService()
