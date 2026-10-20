"""Auth persistence — raw SQL only (arch. doc §5, §32).

Owns ``users`` credential reads/writes and the ``authentication_tokens``
refresh-token lifecycle (hashed, expiry-checked, §14). No business rules
here — status gates, rotation, and membership resolution live in the
service. Never called from routers.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from app.core.constants import TokenPurpose
from app.db.types import Conn, Row


class AuthRepository:
    async def get_user_by_email(self, conn: Conn, email: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT employee_id, name, email, password_hash, account_status,
                       is_superuser, last_login_at, created_at, updated_at
                FROM users
                WHERE email = %s
                """,
                (email.lower(),),
            )
            return await cur.fetchone()

    async def get_user_by_id(self, conn: Conn, employee_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT employee_id, name, email, password_hash, account_status,
                       is_superuser, last_login_at, created_at, updated_at
                FROM users
                WHERE employee_id = %s
                """,
                (employee_id,),
            )
            return await cur.fetchone()

    async def create_user(
        self,
        conn: Conn,
        *,
        name: str,
        email: str,
        password_hash: str,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO users (name, email, password_hash)
                VALUES (%s, %s, %s)
                RETURNING employee_id, name, email, account_status,
                          is_superuser, last_login_at, created_at, updated_at
                """,
                (name, email.lower(), password_hash),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row

    async def update_password_hash(self, conn: Conn, employee_id: int, password_hash: str) -> None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE users SET password_hash = %s WHERE employee_id = %s",
                (password_hash, employee_id),
            )

    async def update_last_login(self, conn: Conn, employee_id: int, at: datetime) -> None:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE users SET last_login_at = %s WHERE employee_id = %s",
                (at, employee_id),
            )

    async def list_memberships(self, conn: Conn, employee_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT m.organization_id, m.is_admin, o.name, o.slug
                FROM memberships AS m
                JOIN organizations AS o
                  ON o.organization_id = m.organization_id
                WHERE m.employee_id = %s
                ORDER BY m.organization_id ASC
                """,
                (employee_id,),
            )
            return list(await cur.fetchall())

    async def get_membership(
        self, conn: Conn, employee_id: int, organization_id: int
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT membership_id, employee_id, organization_id, is_admin
                FROM memberships
                WHERE employee_id = %s AND organization_id = %s
                """,
                (employee_id, organization_id),
            )
            return await cur.fetchone()

    async def organization_exists(self, conn: Conn, organization_id: int) -> bool:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT 1 FROM organizations WHERE organization_id = %s",
                (organization_id,),
            )
            return await cur.fetchone() is not None

    async def insert_token(
        self,
        conn: Conn,
        *,
        employee_id: int,
        token_hash: str,
        purpose: TokenPurpose,
        expires_at: datetime,
        family_id: uuid.UUID | None = None,
    ) -> Row:
        """Insert a token. A new family is started unless one is given."""
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO authentication_tokens
                    (employee_id, token_hash, purpose, expires_at, family_id)
                VALUES (%s, %s, %s, %s, COALESCE(%s::uuid, gen_random_uuid()))
                RETURNING token_id, employee_id, token_hash, purpose,
                          expires_at, created_at, family_id
                """,
                (
                    employee_id,
                    token_hash,
                    purpose.value,
                    expires_at,
                    family_id,
                ),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row

    async def get_token(self, conn: Conn, token_hash: str, purpose: TokenPurpose) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT token_id, employee_id, token_hash, purpose,
                       expires_at, created_at, family_id,
                       replaced_by_token_id, revoked_at
                FROM authentication_tokens
                WHERE token_hash = %s AND purpose = %s
                """,
                (token_hash, purpose.value),
            )
            return await cur.fetchone()

    async def get_token_by_id(self, conn: Conn, token_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT token_id, employee_id, token_hash, purpose,
                       expires_at, created_at, family_id,
                       replaced_by_token_id, revoked_at
                FROM authentication_tokens
                WHERE token_id = %s
                """,
                (token_id,),
            )
            return await cur.fetchone()

    async def mark_rotated(self, conn: Conn, token_id: int, *, replaced_by_token_id: int) -> None:
        """Record that a token has been replaced by another one.

        The row is kept rather than deleted: keeping it is what makes a
        replayed token recognisable as a replay. Only the replacement is
        recorded -- ``revoked_at`` stays empty, because a rotated token
        is not a revoked one: a client that retries after a lost
        response must still be able to continue the chain.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE authentication_tokens SET replaced_by_token_id = %s WHERE token_id = %s",
                (replaced_by_token_id, token_id),
            )

    async def revoke_family(self, conn: Conn, family_id: uuid.UUID) -> int:
        """Revoke every token of a family — the response to a replay."""
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE authentication_tokens"
                " SET revoked_at = CURRENT_TIMESTAMP"
                " WHERE family_id = %s AND revoked_at IS NULL",
                (family_id,),
            )
            return cur.rowcount

    async def revoke_refresh_tokens_for_employee(self, conn: Conn, *, employee_id: int) -> int:
        """Revoke every refresh token of a user (used when switching org)."""
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE authentication_tokens"
                " SET revoked_at = CURRENT_TIMESTAMP"
                " WHERE employee_id = %s AND purpose = %s AND revoked_at IS NULL",
                (employee_id, TokenPurpose.REFRESH.value),
            )
            return cur.rowcount

    async def delete_token(self, conn: Conn, token_hash: str) -> int:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM authentication_tokens WHERE token_hash = %s",
                (token_hash,),
            )
            return cur.rowcount

    async def delete_token_for_employee(
        self, conn: Conn, *, employee_id: int, token_hash: str
    ) -> int:
        """Owner-scoped revoke — a caller can never revoke another user's token."""
        async with conn.cursor() as cur:
            await cur.execute(
                """
                DELETE FROM authentication_tokens
                WHERE token_hash = %s AND employee_id = %s
                """,
                (token_hash, employee_id),
            )
            return cur.rowcount

    async def delete_expired_tokens(self, conn: Conn) -> int:
        """Cleanup helper for expired rows (§14) — run from a cron/scheduler."""
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM authentication_tokens WHERE expires_at <= CURRENT_TIMESTAMP",
            )
            return cur.rowcount
