# ATS Backend Migration — TODO Checklist

> Companion to `plan.md`. Work top-to-bottom; each phase gates the next.
> All commands run with **uv** from `backend/`.

---

## Phase 0 — Tooling & Environment

- [ ] Install uv (≥ 0.12.15): `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
- [ ] Verify Python 3.13 available: `uv python install 3.13`
- [ ] Create `backend/` directory layout
- [ ] `docker-compose.yml` — Postgres 17 (volume, healthcheck, port 5432)
- [ ] Update root `.gitignore`: `.venv/`, `.env`, `__pycache__/`, `uploads/`, `.ruff_cache/`, `.pytest_cache/`
- [ ] `backend/migrations/0001_initial.sql` = `schema.sql` verbatim (baseline — never edited afterwards; §18)
- [ ] `backend/scripts/migrate.py` (ordered SQL runner) + `seed.py` (Org A + Org B)

## Phase 1 — Project Scaffolding (uv)

- [ ] `pyproject.toml` — project metadata, `requires-python = ">=3.13"`
- [ ] Runtime deps (pinned): `fastapi==0.141.1`, `uvicorn[standard]==0.53.0`,
      `psycopg[binary,pool]==3.3.5`, `pydantic==2.13.5`, `pydantic-settings==2.15.0`,
      `PyJWT==2.14.0`, `pwdlib[argon2]==0.3.1` (Argon2id), `python-multipart==0.0.32`, `email-validator==2.3.0`
- [ ] Dev deps: `pytest==9.1.1`, `httpx==0.28.1`, `ruff==0.16.8`
- [ ] Ruff config (line-length 100, target py313, lint + format)
- [ ] Pytest config (`testpaths`, markers)
- [ ] `uv lock` + `uv sync`; commit `uv.lock`
- [ ] `.env.example` (DATABASE_URL, JWT_SECRET, ACCESS_TOKEN_EXPIRE_MINUTES,
      REFRESH_TOKEN_EXPIRE_DAYS, CORS_ORIGINS, ENVIRONMENT, LOG_LEVEL)
- [ ] `backend/README.md` (setup, run, test instructions)

## Phase 2 — Core Infrastructure

- [ ] `app/core/config.py` — pydantic-settings, cached `get_settings()`
      (DATABASE_URL, JWT_SECRET, JWT_ALGORITHM, JWT_*_EXPIRE, CORS_ORIGINS,
      S3_* placeholders, ENVIRONMENT, LOG_LEVEL — §40)
- [ ] `app/core/constants.py` — StrEnums mirroring every CHECK constraint
      (ExpenseStatus, AccountStatus, ReimbursementStatus, TokenPurpose,
      EmployeeStatus, ApprovalAction) + status transition maps (§36)
- [ ] `app/core/exceptions.py` — AppException tree (AuthenticationError,
      AuthorizationError, NotFoundError, ConflictError, ValidationError) +
      global handlers → error envelope (§22); psycopg3 exception mapping (§50)
- [ ] `app/core/security/passwords.py` — pwdlib[argon2]; async
      `hash_password`/`verify_password` via `asyncio.to_thread` (§48)
- [ ] `app/core/security/jwt.py` — PyJWT, explicit alg allow-list (HS256),
      claims `sub`/`org`/`admin`/`exp`/`iat` (ADR-001, §51)
- [ ] `app/core/security/tokens.py` — `secrets.token_urlsafe` generation,
      SHA-256 hashing, expiry checks, expired-token cleanup helper (§14)
- [ ] `app/core/logging.py` — structured logging (request_id, employee_id,
      organization_id, duration_ms) + request-ID middleware; never-log list (§23)
- [ ] `app/db/pool.py` — `AsyncConnectionPool` (min/max from settings,
      `row_factory=dict_row`, `open=False` → opened in lifespan, closed on shutdown)
- [ ] `app/db/connection.py` — `get_connection` dependency (auto commit/rollback)
- [ ] `app/db/transaction.py` + `app/db/types.py`
- [ ] `app/common/` — `pagination.py` (cursor + offset, `Page[T]`), `responses.py`
      (error envelope), `permissions.py`, `utils.py`
- [ ] `app/main.py` — `create_app()` factory, middleware, exception handlers,
      `/health`, `/ready` (§24)
- [ ] Verify: `uv run uvicorn app.main:app --reload` boots; `/ready` pings DB

## Phase 3 — Shared Plumbing & Fixtures (before any domain module)

- [ ] `app/api/v1/deps.py` — `get_current_user` (CurrentUser: employee_id,
      organization_id, is_admin), `require_membership`, `require_admin`,
      `require_permission` / `RequirePermission[...]` (§10)
- [ ] Verify `scripts/migrate.py`: fresh DB → `0001_initial.sql` applies cleanly;
      `scripts/seed.py` seeds Org A + Org B users (deterministic, no secrets)
- [ ] `app/common/object_storage.py` — `ObjectStorage` interface + local-disk
      dev implementation (S3/MinIO swap later, §15)
- [ ] `app/notifications/` feature module — DB-backed notification creation +
      `BackgroundTasks` dispatch hook (§38)
- [ ] `tests/conftest.py` fixtures FIRST (§29): `postgres_db`, `db_connection`,
      `test_client`, `user`, `admin_user`, `organization`, `membership`,
      `expense`, `project`, `auth_token` — composable, minimal

## Phase 4 — Feature Modules (each: router + schemas + repository + service)

> Order matters: **auth is the reference implementation** — everything else
> copies its shape. Every endpoint is implemented row-by-row against the
> **§49 contract table** in `ATS_BACKEND_ARCHITECTURE.md` (method, path, auth,
> request model, success code, error codes). All code is async (§48).

### 4.1 auth/ (reference module)
- [ ] `schemas.py`: UserCreate, LoginRequest, TokenPair, RefreshRequest,
      OrganizationSwitchRequest, UserResponse
- [ ] `repository.py`: user lookup by email, insert, token insert/revoke
      (hashed, expiry-checked), update `last_login_at`
- [ ] `service.py`: register (Argon2id), login (verify + issue pair + org list),
      refresh (rotation — old token invalidated), logout (revoke),
      switch-organization (ADR-001: server-side membership re-validation)
- [ ] `router.py`: `POST /auth/register|login|refresh|logout|switch-organization`
- [ ] Tests: happy path, wrong password → 401, suspended/locked → 403,
      expired/unknown refresh → 401, rotation invalidates old token,
      switch to non-member org → 403

### 4.2 users/
- [ ] `schemas.py`: UserResponse (never exposes password_hash), UserListItem,
      UserUpdate, EmployeeStatusCreate/Response
- [ ] Endpoints (§49 #8–12): `GET /users/me`, `GET /users` (admin),
      `PATCH /users/{id}` (admin), employee-status log GET/POST
      (single-active constraint → 409 on conflict)
- [ ] Tests: field-exposure audit (no sensitive fields), non-admin → 403,
      active-status conflict → 409

### 4.3 organizations/ (+ memberships + roles)
- [ ] Create org (creator becomes admin member), list own, get (member),
      patch (admin) — §49 #13–20
- [ ] Members: add/remove with admin guard + last-admin guard → 409;
      roles CRUD (org-scoped, `UNIQUE(name, organization_id)` → 409)
- [ ] Tenant scoping: `WHERE organization_id = %s` in every query (§8)
- [ ] Tests: cross-org access → 404, non-admin → 403, duplicate slug → 409

### 4.4 projects/ (projects, budgets, expense types)
- [ ] Schemas + CRUD for budgets/projects/expense types (admin), member list
- [ ] Cross-tenant write attempts rejected in service + DB constraint backstop (§9)
- [ ] Tests: cross-tenant access → 404, uniqueness → 409

### 4.5 expenses/ (expenses + media + approvals)
- [ ] `schemas.py`: ExpenseCreate, ExpenseResponse, ExpenseListItem,
      ApprovalActionRequest, MediaResponse
- [ ] Submit (§49 #27): validate project/expense-type org consistency
      (mirrors DB trigger, §9), store receipts via `ObjectStorage`,
      insert expense + media rows in ONE transaction, notify (BackgroundTasks)
- [ ] Approve/reject (§49 #31–32): `FOR UPDATE` lock, transition map (§36),
      approval row, audit log, notification — one service transaction (§7)
- [ ] Router: `POST /expenses` (multipart), `GET /expenses` (cursor pagination +
      status/date filters), `GET /expenses/{id}`, `GET /approvals/pending`,
      `POST /expenses/{id}/approve|reject`
- [ ] Tests: submit 201 with files, cross-tenant ids → 404/422, approve flow →
      status change + notification + audit row, reject without comments → 422,
      double-action → 409, non-admin → 403

### 4.6 reimbursements/
- [ ] Lifecycle `pending → processing → paid/failed` via transition map;
      `paid` requires `payment_reference` and sets `paid_at` (service +
      DB CHECK `chk_paid_at` backstop) — §49 #33–35
- [ ] `POST /expenses/{id}/reimbursement` (UNIQUE expense_id → 409),
      `POST /reimbursements/{id}/transition`, `GET /reimbursements`
- [ ] Triple org-consistency enforced (expense = employee = reimbursement org, §9)
- [ ] Tests: invalid transition → 409, paid without reference → 422,
      cross-tenant → 404

### 4.7 notifications/ + audit logs (read side)
- [ ] `GET /notifications` (cursor-paginated), `POST /notifications/{id}/read`
      (owner), `POST /notifications/read-all`, `GET /audit-logs` (admin)

## Phase 5 — Quality Gates (Definition of Done, arch. doc §44)

- [ ] **Mandatory tenant-isolation suite (§27)**: Org A vs Org B — read, modify,
      approve, assign roles, reimbursements, notifications across all endpoints
- [ ] **DB integration tests (§28)**: FKs, unique, partial unique, CHECKs,
      triggers, transaction rollback, concurrent update behavior
- [ ] **API contract tests** vs §49 table (status codes + response models)
- [ ] Unit tests for services/security/pagination (§26)
- [ ] `uv run ruff check .` + `uv run ruff format --check .` — clean
- [ ] `uv run pytest` — full suite green
- [ ] No sensitive data in logs (§23 never-log list audit)
- [ ] Manual E2E: `docker compose up -d` → `scripts/migrate.py` → `seed.py`
      → boot server → Swagger walk-through: register → login → submit expense
      → approve → reimburse

## Phase 6 — Wrap-up

- [ ] Update root `README.md` with backend section (architecture pointer →
      `ATS_BACKEND_ARCHITECTURE.md`)
- [ ] Architecture doc updated if any new pattern was introduced (§42.20)
- [ ] Final review: no secrets in code, `uv.lock` committed, `.env` ignored
- [ ] PR-ready summary

