"""Organization persistence — raw SQL only (arch. doc §5, §32).

Owns ``organizations``, ``memberships`` (plus the admin head-count used by
the last-admin guard), and org-scoped ``roles``. Every nested query carries
``WHERE organization_id = %s`` (§8) — the service turns empty results into
404s so cross-tenant IDs stay undiscoverable.
"""

from __future__ import annotations

from app.db.types import Conn, Row

_ORG_COLUMNS = (
    "organization_id, name, slug, description, is_system, is_active, created_at, updated_at"
)

_MEMBERSHIP_COLUMNS = "membership_id, employee_id, organization_id, is_admin, joined_at, updated_at"

_ROLE_COLUMNS = "role_id, name, organization_id, description, is_active, created_at, updated_at"


class OrganizationRepository:
    # -- organizations ---------------------------------------------------

    async def create_organization(
        self, conn: Conn, *, name: str, slug: str, description: str | None
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO organizations (name, slug, description)"
                " VALUES (%s, %s, %s) RETURNING " + _ORG_COLUMNS,
                (name, slug, description),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row

    async def get_organization(self, conn: Conn, organization_id: int) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT " + _ORG_COLUMNS + " FROM organizations WHERE organization_id = %s",
                (organization_id,),
            )
            return await cur.fetchone()

    async def list_organizations_for_employee(self, conn: Conn, employee_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT o.organization_id, o.name, o.slug, o.description,"
                " o.is_system, o.is_active, o.created_at, o.updated_at"
                " FROM organizations AS o"
                " JOIN memberships AS m ON m.organization_id = o.organization_id"
                " WHERE m.employee_id = %s ORDER BY o.organization_id ASC",
                (employee_id,),
            )
            return list(await cur.fetchall())

    async def update_organization(
        self,
        conn: Conn,
        organization_id: int,
        *,
        name: str | None = None,
        slug: str | None = None,
        description: str | None = None,
        is_active: bool | None = None,
    ) -> Row | None:
        assignments: list[str] = []
        params: list[object] = []
        if name is not None:
            assignments.append("name = %s")
            params.append(name)
        if slug is not None:
            assignments.append("slug = %s")
            params.append(slug)
        if description is not None:
            assignments.append("description = %s")
            params.append(description)
        if is_active is not None:
            assignments.append("is_active = %s")
            params.append(is_active)
        if not assignments:
            return await self.get_organization(conn, organization_id)
        params.append(organization_id)
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE organizations SET "
                + ", ".join(assignments)
                + " WHERE organization_id = %s RETURNING "
                + _ORG_COLUMNS,
                tuple(params),
            )
            return await cur.fetchone()

    # -- memberships ------------------------------------------------------

    async def get_membership(
        self, conn: Conn, employee_id: int, organization_id: int
    ) -> Row | None:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _MEMBERSHIP_COLUMNS
                + " FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, organization_id),
            )
            return await cur.fetchone()

    async def add_membership(
        self, conn: Conn, *, employee_id: int, organization_id: int, is_admin: bool
    ) -> Row:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO memberships (employee_id, organization_id, is_admin)"
                " VALUES (%s, %s, %s) RETURNING " + _MEMBERSHIP_COLUMNS,
                (employee_id, organization_id, is_admin),
            )
            row = await cur.fetchone()
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row

    async def remove_membership(self, conn: Conn, *, employee_id: int, organization_id: int) -> int:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM memberships WHERE employee_id = %s AND organization_id = %s",
                (employee_id, organization_id),
            )
            return cur.rowcount

    async def count_admins(self, conn: Conn, organization_id: int) -> int:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT COUNT(*) AS admin_count FROM memberships"
                " WHERE organization_id = %s AND is_admin",
                (organization_id,),
            )
            row = await cur.fetchone()
            assert row is not None
            return int(row["admin_count"])

    async def lock_admin_memberships(self, conn: Conn, organization_id: int) -> list[Row]:
        """Lock every admin membership row (``FOR UPDATE``) and return them.

        Callers hold the locks until the request-scoped transaction commits
        or rolls back (§7) — this is what makes the last-admin guard in
        ``remove_member`` safe under concurrency. Aggregates cannot take
        ``FOR UPDATE`` directly, so the rows are locked first and counted
        in Python.
        """
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT membership_id FROM memberships"
                " WHERE organization_id = %s AND is_admin FOR UPDATE",
                (organization_id,),
            )
            return list(await cur.fetchall())

    async def user_exists(self, conn: Conn, employee_id: int) -> bool:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT 1 FROM users WHERE employee_id = %s",
                (employee_id,),
            )
            return await cur.fetchone() is not None

    # -- roles (org-scoped) -------------------------------------------------

    async def list_roles(self, conn: Conn, organization_id: int) -> list[Row]:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT "
                + _ROLE_COLUMNS
                + " FROM roles WHERE organization_id = %s ORDER BY name ASC",
                (organization_id,),
            )
            return list(await cur.fetchall())

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
            assert row is not None  # INSERT ... RETURNING always yields a row
            return row
