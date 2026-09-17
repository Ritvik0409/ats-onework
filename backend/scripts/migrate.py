"""ATS database migration runner.

Applies ``migrations/*.sql`` files in lexicographic order, exactly once each.
Applied versions are recorded in the ``schema_migrations`` table, which makes
the runner idempotent and safe to re-run (arch. doc §18).

Usage (from ``backend/``)::

    DATABASE_URL=postgresql://... uv run python scripts/migrate.py
    uv run python scripts/migrate.py --dsn postgresql://ats:ats_dev_password@localhost:5432/ats
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import psycopg

BACKEND_DIR = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = BACKEND_DIR / "migrations"

DEFAULT_DSN = "postgresql://ats:ats_dev_password@localhost:5432/ats"

MIGRATION_PATTERN = re.compile(r"^\d{4}_[a-z0-9_]+\.sql$")
HISTORY_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


def build_dsn(cli_dsn: str | None) -> str:
    return cli_dsn or os.environ.get("DATABASE_URL") or DEFAULT_DSN


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

        # Dollar-quoted block ($$ or $tag$ ... $$ or $tag$).
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
        cur.execute(
            "SELECT version FROM schema_migrations ORDER BY version",
        )
        return {row[0] for row in cur.fetchall()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dsn", default=None, help="PostgreSQL DSN")
    args = parser.parse_args()

    migration_files = sorted(
        p for p in MIGRATIONS_DIR.glob("*.sql") if MIGRATION_PATTERN.match(p.name)
    )
    if not migration_files:
        print(f"No migration files found in {MIGRATIONS_DIR}", file=sys.stderr)
        return 1

    with psycopg.connect(build_dsn(args.dsn)) as conn:
        conn.execute(HISTORY_TABLE_SQL)
        conn.commit()
        applied = applied_versions(conn)

        for path in migration_files:
            if path.name in applied:
                print(f"= {path.name} (already applied)")
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
                print(f"! {path.name} FAILED: {exc}", file=sys.stderr)
                return 1
            print(f"+ {path.name} applied ({len(statements)} statements)")

    print("Migrations up to date.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
