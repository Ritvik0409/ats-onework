"""Shared audit-log write helper — one DRY entry point (arch. doc §37).

Domain services record important mutations (status changes, role
assignments, payments, admin changes) through ``AuditService.log`` from
inside their workflow transaction, so the audit row commits or rolls back
atomically with the business change. Repositories never write audit rows
directly; routers never call this helper — only services do.

The schema's ``audit_logs`` table carries no ``organization_id`` column, so
tenant scoping for the read endpoint (Phase 4.7) is derived via the actor's
membership; the service-level invariant ``actor_id``/``organization_id``
pair is still passed through for future-proofing.
"""

from __future__ import annotations

from typing import Any

from app.db.types import Conn, Row


class AuditService:
    async def log(
        self,
        conn: Conn,
        *,
        actor_id: int | None,
        action: str,
        table_name: str,
        record_id: str,
        old_values: dict[str, Any] | None = None,
        new_values: dict[str, Any] | None = None,
    ) -> Row:
        """Insert one audit row; returns the inserted row as a dict."""
        import json

        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO audit_logs
                    (actor_id, action, table_name, record_id, old_values, new_values)
                VALUES (%s, %s, %s, %s, %s::jsonb, %s::jsonb)
                RETURNING log_id, actor_id, action, table_name, record_id,
                          old_values, new_values, created_at
                """,
                (
                    actor_id,
                    action,
                    table_name,
                    record_id,
                    json.dumps(old_values) if old_values is not None else None,
                    json.dumps(new_values) if new_values is not None else None,
                ),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row


service = AuditService()
