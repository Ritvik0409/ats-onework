"""Audit-log read rules (§49 #39, admin only)."""

from __future__ import annotations

from app.audit_logs.repository import AuditLogRepository
from app.audit_logs.schemas import AuditLogListItem
from app.common.tenant import require_path_admin
from app.db.types import Conn, Row

_repository = AuditLogRepository()


class AuditLogService:
    def __init__(self, repository: AuditLogRepository | None = None) -> None:
        self._repository = repository or _repository

    async def list(
        self,
        conn: Conn,
        *,
        employee_id: int,
        organization_id: int,
        table_name: str | None,
        actor_id: int | None,
        limit: int,
        before_id: int | None,
    ) -> list[AuditLogListItem]:
        await self._require_admin(conn, employee_id, organization_id)
        rows = await self._repository.list_for_org(
            conn,
            organization_id,
            table_name=table_name,
            actor_id=actor_id,
            limit=limit,
            before_id=before_id,
        )
        return [AuditLogListItem.model_validate(r) for r in rows]

    async def _require_admin(self, conn: Conn, employee_id: int, org_id: int) -> Row:
        return require_path_admin(await self._repository.get_membership(conn, employee_id, org_id))


service = AuditLogService()
