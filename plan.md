# ATS Backend Migration Plan — Firebase → FastAPI + PostgreSQL (psycopg3)

> ATS — Aniruddha Telemetry System · OneWork Expense Portal
> Status: **Approved** · Created: 2026-09-17
>
> **Authoritative spec:** [`ATS_BACKEND_ARCHITECTURE.md`](ATS_BACKEND_ARCHITECTURE.md) — this file records the migration plan; the architecture doc governs implementation (§2 layout, §49 endpoint contracts, §51 ADRs). Where they differ, the architecture doc wins.

---

## 1. Context

The repository currently contains a **Flutter mobile app** (`ats_onework`) that uses
Firebase (Firestore, Auth, Storage) for its Employee/Management expense portals.

This plan builds a **new production-grade REST backend** that replaces Firebase:

- **Framework:** FastAPI (async, end-to-end)
- **Database:** PostgreSQL — versioned raw-SQL migrations (`migrations/0001_initial.sql`, derived verbatim from `schema.sql`; no ORM, no Alembic — simple ordered migration runner)
- **Driver:** **psycopg3** (`psycopg[binary,pool]`) — the official successor of psycopg2, chosen for native `AsyncConnectionPool` support so DB calls never block the event loop
- **Package manager:** **uv** (replaces pip/pip-tools/virtualenv)
- **Placement:** `backend/` folder inside this repo (Flutter app stays untouched in `lib/`)

The Flutter app will later consume this API instead of Firebase (out of scope for backend v1).

## 2. Tech Stack & Verified Versions (checked on PyPI — 2026-09-17)

### Runtime dependencies

| Package | Version | Purpose |
|---|---|---|
| `fastapi` | 0.141.1 | Web framework |
| `uvicorn[standard]` | 0.53.0 | ASGI server (uvloop + httptools) |
| `psycopg[binary,pool]` | 3.3.5 | PostgreSQL driver + `AsyncConnectionPool` |
| `pydantic` | 2.13.5 | Request/response validation |
| `pydantic-settings` | 2.15.0 | Env-based configuration (`.env`) |
| `PyJWT` | 2.14.0 | JWT access tokens |
| `pwdlib[argon2]` | 0.3.1 | Password hashing — Argon2id via argon2-cffi 25.1.0 |
| `python-multipart` | 0.0.32 | Receipt image uploads |
| `email-validator` | 2.3.0 | Email validation in Pydantic |

### Dev dependencies

| Package | Version | Purpose |
|---|---|---|
| `pytest` | 9.1.1 | Test framework |
| `httpx` | 0.28.1 | FastAPI `TestClient` / async API tests |
| `ruff` | 0.16.8 | Linter + formatter (replaces flake8/black/isort) |

### Tooling

- **uv** ≥ 0.12.15 (standalone installer)
- **Python 3.13** (target runtime — fully supported by every package above)
- **PostgreSQL 17** via Docker Compose (local development)

### Rejected alternatives (and why)

| Rejected | Reason |
|---|---|
| `psycopg2-binary` 2.9.13 | Maintained but feature-frozen; sync-only; user approved psycopg3 upgrade |
| SQLAlchemy + Alembic | User wants raw SQL + `schema.sql` as single source of truth |
| `python-jose` | Unmaintained, known CVEs → **PyJWT** |
| `passlib` | Unmaintained; **breaks on Python 3.13** → `pwdlib[argon2]` |
| `bcrypt` (direct) | 72-byte truncation history; Argon2id preferred by OWASP → `pwdlib[argon2]` |

---

## 3. Architecture

### 3.1 Layering rule (strict, enforced)

```
Router (api/)  →  Service (services/)  →  Repository (repositories/)
```

- **Routers** — HTTP concerns only: parse request, status codes, response models. No business logic.
- **Services** — business rules, transaction orchestration, cross-domain events
  (e.g., expense approved → create notification via `services/notifications`).
- **Repositories** — raw parameterized SQL only; map rows → Pydantic domain schemas.
  Never called directly from routers.

### 3.2 Dependency Injection & transactions

- All DB access flows through FastAPI `Depends()`:
  - `get_connection` — yields a connection from `AsyncConnectionPool` inside
    `async with pool.connection()` → **auto COMMIT on success, auto ROLLBACK on exception**.
- Services and repositories receive the connection; nothing imports the pool directly.
- The pool is created in `lifespan` with `open=False` then explicitly opened
  (psycopg3 best practice — constructor-open is deprecated).

### 3.3 Authentication design (matches `authentication_tokens` table)

- **Access token:** JWT (PyJWT, HS256), short expiry (~30 min), carries
  `employee_id`, `organization_id`, `is_admin`.
- **Refresh token:** opaque random token, stored **SHA-256 hashed** in
  `authentication_tokens` (purpose `refresh`), rotated on every refresh
  (old token invalidated, new one issued).
- Passwords hashed with **bcrypt** into `users.password_hash`.
- All endpoints tenant-scoped by `organization_id` — enforced in services,
  backed by the DB's cross-tenant validation trigger.

### 3.4 Constants ↔ schema sync

`app/core/constants.py` holds `StrEnum`s mirroring every CHECK constraint:
expense status, account status, reimbursement status, token purpose,
employee status, expense action. Pydantic models validate against these enums;
SQL literals come from the same source (DRY).

### 3.5 Error handling

- Global exception handlers produce one JSON error envelope:
  `{ "error": { "code", "message", "details" } }`.
- psycopg3 exceptions mapped: `UniqueViolation` → 409,
  `CheckViolation` → 422, `ForeignKeyViolation` → 400. SQL internals never leak.

### 3.6 Notifications & background work

- `app/services/notifications/` isolates dispatch (DB record now; email/push later
  via the same interface). Routers schedule dispatch with `BackgroundTasks`.

### 3.7 File storage

- Receipt uploads → local disk under `uploads/` behind an `ObjectStorage`
  interface (§15); URLs stored in `expense_media.receipt_url`. S3/MinIO/R2
  implementations can replace it without touching domain code. Served via
  `StaticFiles` in dev.

---

## 4. Folder Structure

```
backend/
├── pyproject.toml            # uv project: deps, ruff, pytest config
├── uv.lock                   # locked versions (committed)
├── .env.example
├── README.md
├── docker-compose.yml        # Postgres 17 local dev
├── migrations/
│   ├── 0001_initial.sql      # = schema.sql verbatim (baseline, never edited)
│   └── 0002_...sql           # additive changes only (arch. doc §18)
├── scripts/
│   ├── migrate.py            # ordered SQL migration runner (no Alembic)
│   └── seed.py               # deterministic dev/test seed (Org A + Org B)
├── app/
│   ├── __init__.py
│   ├── main.py               # create_app() factory + lifespan (pool, §24)
│   ├── core/
│   │   ├── config.py         # pydantic-settings (JWT_*, S3_* keys, §40)
│   │   ├── constants.py      # StrEnums mirroring CHECKs + transition maps (§36)
│   │   ├── exceptions.py     # AppException tree + handlers (§22, §50)
│   │   ├── logging.py        # structured logs + request-ID middleware (§23)
│   │   └── security/         # split per §12
│   │       ├── passwords.py  # pwdlib/Argon2id, asyncio.to_thread (§48)
│   │       ├── jwt.py        # PyJWT, explicit alg allow-list
│   │       └── tokens.py     # refresh/reset generation + SHA-256 hashing
│   ├── db/
│   │   ├── pool.py           # AsyncConnectionPool lifecycle, dict_row
│   │   ├── connection.py     # get_connection dependency (commit/rollback)
│   │   ├── transaction.py    # explicit transaction helpers (§7)
│   │   └── types.py          # row factories, type aliases
│   ├── common/
│   │   ├── pagination.py     # cursor (keyset) + offset params, Page[T] (§21)
│   │   ├── responses.py      # error envelope
│   │   ├── permissions.py    # require_permission / RequirePermission (§10)
│   │   └── utils.py
│   ├── api/
│   │   └── v1/
│   │       ├── router.py     # aggregates domain routers (§20)
│   │       └── deps.py       # get_current_user, require_membership/admin
│   ├── auth/                 # feature modules (§2 layout) — each contains
│   │   ├── router.py         #   HTTP concerns only
│   │   ├── schemas.py        #   Create/Update/Response/ListItem models
│   │   ├── repository.py     #   raw parameterized SQL
│   │   ├── service.py        #   business rules + transactions
│   │   └── dependencies.py
│   ├── users/                # router, schemas, repository, service
│   ├── organizations/        # + memberships + roles
│   ├── projects/             # projects, budgets, expense types
│   ├── expenses/             # expenses + media + approvals
│   ├── reimbursements/
│   └── notifications/
└── tests/
    ├── unit/                 # services, security, pagination (§26)
    ├── integration/          # real PostgreSQL: SQL, constraints, triggers
    ├── api/                  # httpx contract tests (vs §49 table)
    └── conftest.py           # postgres_db, user, organization, auth_token (§29)
```

## 5. API Surface (v1, prefix `/api/v1`)

| Domain | Endpoints |
|---|---|
| Health | `GET /health` (liveness), `GET /ready` (DB `SELECT 1`) |
| Auth | `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout` |
| Users | `GET /users/me`, `GET /users`, `PATCH /users/{id}`, status management |
| Organizations | CRUD + memberships (`POST /orgs/{id}/members`), roles |
| Projects | CRUD (org-scoped), budgets, expense types |
| Expenses | `POST /expenses` (multipart w/ receipts), `GET /expenses` (filters, pagination), detail |
| Approvals | `GET /approvals/pending`, `POST /expenses/{id}/approve`, `POST /expenses/{id}/reject` |
| Reimbursements | lifecycle `pending → processing → paid/failed` (enforces `paid_at` rule) |
| Notifications | list, mark read |

List endpoints use **cursor/keyset pagination** for high-volume tables (expenses, audit logs, notifications, approvals) and `limit`/`offset` for small admin reference lists — shared via `common/pagination.py` and `deps.py`. Full contracts: architecture doc §49.

---

## 6. Quality Gates

1. **Ruff** — `ruff check` + `ruff format` clean, config in `pyproject.toml`.
2. **pytest** — auth flow (register/login/refresh/rotation/logout),
   tenant isolation (cross-org access → 403/404), expense approval workflow,
   reimbursement paid_at rule, error envelope shape.
3. **Manual verification** — `docker compose up -d`, apply `schema.sql`,
   `uv run uvicorn app.main:app --reload`, exercise Swagger UI (`/docs`).

## 7. Best Practices Enforced

- **DRY** — base repository, shared deps, single error envelope, `constants.py`.
- **Security** — parameterized SQL only, Argon2id via pwdlib, hashed refresh tokens,
  tenant checks on every query, secrets only via env vars, CORS allow-list.
- **Layering** — strict router → service → repository; services never import HTTP types.
- **Typing** — full type hints; Pydantic v2 at every I/O boundary.

## 8. Explicitly Out of Scope (v1 / future work)

- Alembic (versioned raw-SQL migrations + runner adopted instead; §18)
- Rate limiting, CI pipeline, email/SMS providers, S3 storage
- Flutter app migration off Firebase



