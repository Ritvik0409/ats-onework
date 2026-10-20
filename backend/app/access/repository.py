"""Access persistence — the role and capability tables (arch. doc §5, §10).

Owns ``permissions``, ``roles``, ``membership_roles``,
``role_permissions`` and ``user_permissions``, plus the platform's
``access_catalog``.

Every query is organization-scoped: a grant can only ever point at a
capability of the same organization, which the schema enforces with
composite foreign keys.
"""

from __future__ import annotations

from app.db.types import Conn, Row

_PERMISSION_COLUMNS = (
    "permission_id, api_name, organization_id, is_global, description, created_at, updated_at"
)
_ROLE_COLUMNS = "role_id, name, organization_id, description, is_active, created_at, updated_at"


class AccessRepository:
    # -- capabilities (per organization) -----------------------------------

    async def list_permissions(self, conn: Conn, organization_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _PERMISSION_COLUMNS + " FROM permissions"
                " WHERE organization_id = %s ORDER BY api_name ASC",
                (organization_id,),
            )
            return list(await cur.fetchall())

    async def get_permission(self, conn: Conn, organization_id: int, api_name: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _PERMISSION_COLUMNS + " FROM permissions"
                " WHERE organization_id = %s AND api_name = %s",
                (organization_id, api_name),
            )
            return await cur.fetchone()

    async def create_permission(
        self,
        conn: Conn,
        *,
        organization_id: int,
        api_name: str,
        description: str | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO permissions (api_name, organization_id, is_global, description)"
                " VALUES (%s, %s, %s, %s) RETURNING " + _PERMISSION_COLUMNS,
                (api_name, organization_id, True, description),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    # -- roles (per organization) ------------------------------------------

    async def list_roles(self, conn: Conn, organization_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _ROLE_COLUMNS + " FROM roles"
                " WHERE organization_id = %s ORDER BY name ASC",
                (organization_id,),
            )
            return list(await cur.fetchall())

    async def get_role(self, conn: Conn, organization_id: int, role_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _ROLE_COLUMNS + " FROM roles"
                " WHERE organization_id = %s AND role_id = %s",
                (organization_id, role_id),
            )
            return await cur.fetchone()

    async def get_role_by_name(self, conn: Conn, organization_id: int, name: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _ROLE_COLUMNS + " FROM roles WHERE organization_id = %s AND name = %s",
                (organization_id, name),
            )
            return await cur.fetchone()

    async def create_role(
        self,
        conn: Conn,
        *,
        organization_id: int,
        name: str,
        description: str | None,
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO roles (name, organization_id, description)"
                " VALUES (%s, %s, %s) RETURNING " + _ROLE_COLUMNS,
                (name, organization_id, description),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    # -- role grants -------------------------------------------------------

    async def list_role_grants(self, conn: Conn, organization_id: int, role_id: int) -> list[str]:
        """The capability names a role grants."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT p.api_name FROM role_permissions rp"
                " JOIN permissions p ON p.permission_id = rp.permission_id"
                " WHERE rp.organization_id = %s AND rp.role_id = %s"
                " ORDER BY p.api_name ASC",
                (organization_id, role_id),
            )
            rows = await cur.fetchall()
        return [row["api_name"] for row in rows]

    async def replace_role_grants(
        self, conn: Conn, organization_id: int, role_id: int, api_names: list[str]
    ) -> None:
        """Set the role's grants to exactly ``api_names``."""
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM role_permissions WHERE organization_id = %s AND role_id = %s",
                (organization_id, role_id),
            )
            if not api_names:
                return
            await cur.execute(
                "INSERT INTO role_permissions (role_id, organization_id, permission_id)"
                " SELECT %s, %s, p.permission_id FROM permissions p"
                " WHERE p.organization_id = %s AND p.api_name = ANY(%s::text[])"
                " ON CONFLICT DO NOTHING",
                (role_id, organization_id, organization_id, api_names),
            )

    # -- membership roles --------------------------------------------------

    async def list_member_roles(
        self, conn: Conn, organization_id: int, employee_id: int
    ) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT r.role_id, r.name, r.organization_id, r.description,"
                " r.is_active, r.created_at, r.updated_at"
                " FROM roles r"
                " JOIN membership_roles mr ON mr.role_id = r.role_id"
                " JOIN memberships m ON m.membership_id = mr.membership_id"
                " WHERE m.organization_id = %s AND m.employee_id = %s"
                " ORDER BY r.name ASC",
                (organization_id, employee_id),
            )
            return list(await cur.fetchall())

    async def replace_member_roles(
        self, conn: Conn, organization_id: int, employee_id: int, role_ids: list[int]
    ) -> None:
        """Set the member's roles to exactly ``role_ids``."""
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM membership_roles WHERE organization_id = %s"
                " AND membership_id IN (SELECT membership_id FROM memberships"
                "                         WHERE organization_id = %s AND employee_id = %s)",
                (organization_id, organization_id, employee_id),
            )
            if not role_ids:
                return
            await cur.execute(
                "INSERT INTO membership_roles (membership_id, role_id, organization_id)"
                " SELECT m.membership_id, r.role_id, m.organization_id"
                "   FROM memberships m"
                "   JOIN roles r ON r.role_id = ANY(%s::int[])"
                "  WHERE m.organization_id = %s AND m.employee_id = %s"
                "    AND r.organization_id = m.organization_id"
                " ON CONFLICT DO NOTHING",
                (role_ids, organization_id, employee_id),
            )

    async def add_member_role(
        self, conn: Conn, organization_id: int, membership_id: int, role_id: int
    ) -> None:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO membership_roles (membership_id, role_id, organization_id)"
                " VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                (membership_id, role_id, organization_id),
            )

    # -- direct grants -----------------------------------------------------

    async def list_user_grants(
        self, conn: Conn, organization_id: int, employee_id: int
    ) -> list[str]:
        """The capability names granted to a person directly."""
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT p.api_name FROM user_permissions up"
                " JOIN permissions p ON p.permission_id = up.permission_id"
                " WHERE up.organization_id = %s AND up.employee_id = %s"
                " ORDER BY p.api_name ASC",
                (organization_id, employee_id),
            )
            rows = await cur.fetchall()
        return [row["api_name"] for row in rows]

    async def replace_user_grants(
        self, conn: Conn, organization_id: int, employee_id: int, api_names: list[str]
    ) -> None:
        """Set the person's direct grants to exactly ``api_names``."""
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM user_permissions WHERE organization_id = %s AND employee_id = %s",
                (organization_id, employee_id),
            )
            if not api_names:
                return
            await cur.execute(
                "INSERT INTO user_permissions (employee_id, permission_id, organization_id)"
                " SELECT %s, p.permission_id, %s FROM permissions p"
                " WHERE p.organization_id = %s AND p.api_name = ANY(%s::text[])"
                " ON CONFLICT DO NOTHING",
                (employee_id, organization_id, organization_id, api_names),
            )

    # -- the platform catalogue --------------------------------------------

    async def list_catalog(self, conn: Conn) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT catalog_id, kind, name, description, grants, created_at, updated_at"
                " FROM access_catalog ORDER BY kind ASC, name ASC"
            )
            return list(await cur.fetchall())

    async def get_catalog_entry(self, conn: Conn, kind: str, name: str) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT catalog_id, kind, name, description, grants, created_at, updated_at"
                " FROM access_catalog WHERE kind = %s AND name = %s",
                (kind, name),
            )
            return await cur.fetchone()

    async def create_catalog_entry(
        self,
        conn: Conn,
        *,
        kind: str,
        name: str,
        description: str | None,
        grants: list[str],
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO access_catalog (kind, name, description, grants)"
                " VALUES (%s, %s, %s, %s::text[])"
                " RETURNING catalog_id, kind, name, description, grants, created_at, updated_at",
                (kind, name, description, grants),
            )
            row = await cur.fetchone()
            assert row is not None
            return row

    async def update_catalog_entry(
        self,
        conn: Conn,
        *,
        kind: str,
        name: str,
        description: str | None,
        grants: list[str] | None,
    ) -> Row | None:
        assignments: list[str] = []
        params: list[object] = []
        if description is not None:
            assignments.append("description = %s")
            params.append(description)
        if grants is not None:
            assignments.append("grants = %s::text[]")
            params.append(grants)
        if not assignments:
            return await self.get_catalog_entry(conn, kind, name)
        params.extend((kind, name))
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE access_catalog SET "
                + ", ".join(assignments)
                + " WHERE kind = %s AND name = %s"
                " RETURNING catalog_id, kind, name, description, grants, created_at, updated_at",
                tuple(params),
            )
            return await cur.fetchone()

    async def delete_catalog_entry(self, conn: Conn, kind: str, name: str) -> int:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM access_catalog WHERE kind = %s AND name = %s",
                (kind, name),
            )
            return cur.rowcount

    # -- installation ------------------------------------------------------

    async def install_catalog_for_org(self, conn: Conn, organization_id: int) -> tuple[int, int]:
        """Install the current catalogue into an organization.

        Returns the number of capabilities and roles installed. Both
        install functions are idempotent and never undo an
        administrator's work: a capability that already exists is left
        alone, and a role that already grants something keeps exactly
        what it has.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT ats_install_permissions(%s) AS installed_permissions",
                (organization_id,),
            )
            row = await cur.fetchone()
            permissions = int(row["installed_permissions"]) if row else 0
            await cur.execute(
                "SELECT ats_install_roles(%s) AS installed_roles",
                (organization_id,),
            )
            row = await cur.fetchone()
            roles = int(row["installed_roles"]) if row else 0
        return permissions, roles
