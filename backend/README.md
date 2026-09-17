# ATS Backend

FastAPI + PostgreSQL (psycopg 3) backend for the **ATS — Aniruddha Telemetry System** expense portal.

- Architecture & engineering rules: [`../ATS_BACKEND_ARCHITECTURE.md`](../ATS_BACKEND_ARCHITECTURE.md)
- Migration plan: [`../plan.md`](../plan.md) · Task checklist: [`../todo.md`](../todo.md)
- Stack: FastAPI 0.141 · Uvicorn 0.53 · psycopg 3.3 · Python 3.13 · uv

## Prerequisites

- [uv](https://docs.astral.sh/uv/) ≥ 0.12 (installs/manages Python itself)
- Docker (for the local PostgreSQL 16)

## Setup

```bash
cd backend
uv sync                 # creates .venv from uv.lock (Python 3.13)
cp .env.example .env    # then edit values — generate a JWT_SECRET!
docker compose up -d    # start PostgreSQL 16
```

## Database

```bash
uv run python scripts/migrate.py   # applies migrations/*.sql in order (idempotent)
uv run python scripts/seed.py      # seeds Org A + Org B dev data (idempotent)
```

Default local DSN: `postgresql://ats:ats_dev_password@localhost:5432/ats`
(override with `DATABASE_URL` or `--dsn`).

## Run

```bash
uv run uvicorn app.main:app --reload
```

- Swagger UI: <http://localhost:8000/docs>
- Health: `GET /health` · Readiness: `GET /ready`

## Test & lint

```bash
uv run ruff check .
uv run ruff format --check .
uv run pytest                     # unit + api (skips DB integration unless DB is up)
uv run pytest -m integration      # full integration suite (needs Postgres running)
```

## Conventions

Read [`../ATS_BACKEND_ARCHITECTURE.md`](../ATS_BACKEND_ARCHITECTURE.md) before writing code —
especially §3 (layering), §42–43 (agent rules), §44 (definition of done), §49 (endpoint contracts).
