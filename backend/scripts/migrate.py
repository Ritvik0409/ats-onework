"""ATS database migration runner (CLI over ``app.db.migrations``).

Applies ``migrations/*.sql`` files in lexicographic order, exactly once each.
Applied versions are recorded in the ``schema_migrations`` table, which makes
the runner idempotent and safe to re-run (arch. doc §18).

DSN resolution (first wins):

1. ``--dsn postgresql://...`` CLI flag
2. ``DATABASE_URL`` in the environment / ``backend/.env``
3. composed from ``DB_HOST``/``DB_PORT``/``DB_USER``/``DB_PASSWORD``/``DB_NAME``

Usage (from ``backend/``)::

    uv run python scripts/migrate.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings
from app.db.migrations import apply_migrations, migration_paths


def main() -> int:
    dsn = get_settings().effective_database_url
    names = migration_paths()
    if not names:
        print("No migration files found.", file=sys.stderr)
        return 1

    import psycopg

    with psycopg.connect(dsn) as conn:
        print(f"Target: PostgreSQL on {conn.info.server_version} (db={conn.info.dbname})")
        applied = apply_migrations(conn)

    print("Migrations up to date." if not applied else f"{applied} migration(s) applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
