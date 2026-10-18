# ATS Backend

FastAPI + PostgreSQL (psycopg 3) backend for the **ATS — Aniruddha Telemetry System** expense portal.

- Architecture & engineering rules: [`../ATS_BACKEND_ARCHITECTURE.md`](../ATS_BACKEND_ARCHITECTURE.md)
- Migration plan: [`../plan.md`](../plan.md) · Task checklist: [`../todo.md`](../todo.md)
- Stack: FastAPI 0.141 · Uvicorn 0.53 · psycopg 3.3 · Python 3.13 · uv

## Prerequisites

- [uv](https://docs.astral.sh/uv/) ≥ 0.12 (installs/manages Python itself)
- A real PostgreSQL server — local install, remote host, or a container you
  own. No Docker images are required by this repo.

## Setup

```bash
cd backend
uv sync                 # creates .venv from uv.lock (Python 3.13)
cp .env.example .env    # then edit values — generate a JWT_SECRET!
```

Point `.env` at your server with discrete credentials:

```env
DB_HOST=localhost
DB_PORT=5432
DB_USER=ats
DB_PASSWORD=change-me
DB_NAME=ats
```

Create the role + database out-of-band (psql as a superuser):

```sql
CREATE ROLE ats WITH LOGIN PASSWORD 'change-me' CREATEDB;
CREATE DATABASE ats OWNER ats;
```

## Database

```bash
uv run python scripts/migrate.py   # applies migrations/*.sql in order (idempotent)
uv run python scripts/seed.py      # seeds Org A + Org B dev data (idempotent)
```

The DSN is composed from `DB_*` in `.env`; `DATABASE_URL` (or `--dsn` on the
seed script) overrides when set.

## Run

```bash
uv run python scripts/dev.py --reload
```

On Windows **use `scripts/dev.py`, not plain `uvicorn`**: psycopg3 async
cannot run on the Proactor event loop uvicorn otherwise boots there, and the
connection pool would never connect. On Linux/macOS either works.

- Swagger UI: <http://localhost:8000/docs>
- Health: `GET /health` · Readiness: `GET /ready`

## Test & lint

```bash
uv run ruff check .
uv run ruff format --check .
uv run pytest -m "not integration"   # 106 unit + contract tests (no DB needed)
uv run pytest -m integration         # 11 integration tests (needs DB creds in .env)
```

Integration tests auto-provision a throwaway `<DB_NAME>_test` database on
the configured server (create → migrate → run → drop), so they never touch
your development data. `uv run pytest` runs everything.

## Conventions

Read [`../ATS_BACKEND_ARCHITECTURE.md`](../ATS_BACKEND_ARCHITECTURE.md) before writing code —
especially §3 (layering), §42–43 (agent rules), §44 (definition of done), §49 (endpoint contracts).
