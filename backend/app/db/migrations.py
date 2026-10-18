"""Migration runner core (§18) — one implementation, three entry points.

- ``scripts/migrate.py``  → CLI (`uv run python scripts/migrate.py`)
- ``tests`` (conftest)    → throws a fresh schema into the throwaway DB
- anything else that needs "apply the.sql files exactly once"

Applied versions are recorded in ``schema_migrations`` — idempotent and
safe to re-run against any database.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING

import psycopg

if TYPE_CHECKING:
    from collections.abc import Callable

BACKEND_DIR = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = BACKEND_DIR / "migrations"

MIGRATION_PATTERN = re.compile(r"^\d{4}_[a-z0-9_]+\.sql$")

HISTORY_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


def migration_files() -> list[Path]:
    return sorted(p for p in MIGRATIONS_DIR.glob("*.sql") if MIGRATION_PATTERN.match(p.name))


def split_sql_statements(sql: str) -> list[str]:
    """Split a SQL script into individual statements.

    Semicolon-aware but dollar-quote and comment aware, so PL/pgSQL function
    bodies ($$ ... $$) and string literals are never split apart.
    """
    statements: list[str] = []
    buf: list[str] = []
    i = 0
    n = len(sql)
    while i < n:
        ch = sql[i]

        # Line comment: skip to end of line.
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j == -1 else j
            continue

        # Block comment: skip past the closing '*/'.
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue

        # Single-quoted string literal (respect '' escaping).
        if ch == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            buf.append(sql[i : j + 1])
            i = j + 1
            continue

        # Dollar-quoted block ($$ or $tag$ ... $$).
        if ch == "$":
            m = re.match(r"\$[A-Za-z_]*\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i + len(tag))
                end = n if j == -1 else j + len(tag)
                buf.append(sql[i:end])
                i = end
                continue

        # Statement separator.
        if ch == ";":
            statements.append("".join(buf))
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    statements.append("".join(buf))
    return [s.strip() for s in statements if s.strip()]


def applied_versions(conn: psycopg.Connection) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT version FROM schema_migrations ORDER BY version")
        return {row[0] for row in cur.fetchall()}


def migration_paths() -> list[str]:
    if not MIGRATIONS_DIR.is_dir():
        return []
    return [p.name for p in migration_files()]


def apply_migrations(
    conn: psycopg.Connection,
    *,
    log: Callable[[str], None] = print,
) -> int:
    """Apply every pending ``migrations/*.sql``. Returns files applied."""
    files = migration_files()
    if not files:
        raise RuntimeError(f"No migration files found in {MIGRATIONS_DIR}")

    conn.execute(HISTORY_TABLE_SQL)
    applied = applied_versions(conn)

    count = 0
    for path in files:
        if path.name in applied:
            log(f"= {path.name} (already applied)")
            continue

        sql = path.read_text(encoding="utf-8")
        statements = split_sql_statements(sql)
        try:
            with conn.transaction():
                for stmt in statements:
                    conn.execute(stmt)
                conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)",
                    (path.name,),
                )
        except psycopg.Error as exc:
            log(f"! {path.name} FAILED: {exc}")
            raise
        log(f"+ {path.name} applied ({len(statements)} statements)")
        count += 1

    return count
