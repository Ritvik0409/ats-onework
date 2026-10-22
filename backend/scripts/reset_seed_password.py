"""Reset the seeded accounts' password so the live API can be exercised.

Local development helper — it rewrites the password of the seeded
accounts only, and prints what it did. The account list comes from the
seeder, so a new persona is covered automatically.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg
from pwdlib import PasswordHash

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings
from scripts.seed import USERS

EMAILS = tuple(email for email, *_rest in USERS)


def main() -> int:
    settings = get_settings()
    if settings.app_env == "production":
        print("[reset] refusing to run against a production database")
        return 1
    password = os.environ.get("SEED_PASSWORD") or "DevPass!2026"
    hasher = PasswordHash.recommended()
    hashed = hasher.hash(password)

    with (
        psycopg.connect(
            host=settings.db_host,
            port=settings.db_port,
            user=settings.db_user,
            password=settings.db_password,
            dbname=settings.db_name,
        ) as conn,
        conn.cursor() as cur,
    ):
        cur.execute(
            "UPDATE users SET password_hash = %s WHERE email = ANY(%s)",
            (hashed, list(EMAILS)),
        )
        print(f"[reset] {cur.rowcount} accounts now use the test password")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
