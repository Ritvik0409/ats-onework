# ATS Backend Migration — TODO Checklist

> Companion to `plan.md`. Work top-to-bottom; each phase gates the next.
> All commands run with **uv** from `backend/`.

---

## Phase 0 — Tooling & Environment

- [x] Install uv: **0.12.15** verified (latest)
- [x] Verify Python 3.13 available: **3.13.14** installed via uv
- [x] Create `backend/` directory layout (14 packages with `__init__.py`)
- [x] `docker-compose.yml` — Postgres 16 (volume, healthcheck, port 5432)
- [x] Update root `.gitignore`: `backend/.venv/`, `.env`, `__pycache__/`, `backend/uploads/`, `.ruff_cache/`, `.pytest_cache/`
- [x] `backend/migrations/0001_initial.sql` = `schema.sql` verbatim (verified byte-identical via `fc /b`)
- [x] `backend/scripts/migrate.py` (ordered SQL runner, dollar-quote-aware splitter, `schema_migrations` tracking) + `seed.py` (Org A + Org B, Argon2id-hashed dev passwords, idempotent) — syntax-checked on 3.13; runtime verification happens in Phase 3 once deps are installed

## Phase 1 — Project Scaffolding (uv)

- [x] `pyproject.toml` — project metadata, `requires-python = ">=3.13"` (+ `.python-version` pinned to 3.13)
- [x] Runtime deps (pinned): `fastapi==0.141.1`, `uvicorn[standard]==0.53.0`,
      `psycopg[binary,pool]==3.3.5`, `pydantic==2.13.5`, `pydantic-settings==2.15.0`,
      `PyJWT==2.14.0`, `pwdlib[argon2]==0.3.1` (Argon2id), `python-multipart==0.0.32`, `email-validator==2.3.0`
- [x] Dev deps (`[dependency-groups] dev`): `pytest==9.1.1`, `httpx==0.28.1`, `ruff==0.16.8`
- [x] Ruff config (line-length 100, target py313, `E,F,I,B,UP,SIM,ARG,RUF` — §30)
- [x] Pytest config (`testpaths=tests`, `-q`, `integration` marker)
- [x] `uv lock` (44 packages resolved) + `uv sync` (42 installed) on **CPython 3.13.14**; `uv.lock` created — commit it
- [x] Functional smoke test: Argon2id hash/verify, JWT round-trip, `AsyncConnectionPool` import, Pydantic v2 model + BaseSettings — all green
- [x] `.env.example` (DATABASE_URL, DB_POOL_*, JWT_SECRET/ALGORITHM/EXPIRE, CORS_ORIGINS, S3_* placeholders — §40)
- [x] `backend/README.md` (prereqs, setup, migrate, seed, run, test, conventions)

## Phase 2 — Core Infrastructure

- [x] `app/core/config.py` — pydantic-settings, cached `get_settings()`
      (DATABASE_URL, JWT_SECRET, JWT_ALGORITHM, JWT_*_EXPIRE, CORS_ORIGINS,
      S3_* placeholders, ENVIRONMENT, LOG_LEVEL — §40)
- [x] `app/core/constants.py` — StrEnums mirroring every CHECK constraint
      (ExpenseStatus [incl. `reimbursed` per schema], AccountStatus
      [`users.status`], ReimbursementStatus, TokenPurpose,
      EmployeeStatus [service-layer lifecycle], ApprovalAction) + status
      transition maps incl. `failed → processing` retry (§36)
- [x] `app/core/exceptions.py` — AppException tree (AuthenticationError,
      AuthorizationError, NotFoundError, ConflictError, ValidationError,
      TransientError→503) + global handlers → error envelope (§22);
      `to_app_exception` psycopg3 mapping incl. constraint-specific 409s (§50)
- [x] `app/core/security/passwords.py` — pwdlib[argon2]; async
      `hash_password`/`verify_password`/`verify_and_update_password`
      via `asyncio.to_thread` (argon2 verify true/false §48)
- [x] `app/core/security/jwt.py` — PyJWT, explicit alg allow-list (HS256),
      claims `sub`/`org`/`admin`/`exp`/`iat` (ADR-001, §51) —
      verified round-trip `sub=7, org=3, admin=True`
- [x] `app/core/security/tokens.py` — `secrets.token_urlsafe` generation,
      SHA-256 hashing (64-hex), expiry checks, expired-token cleanup helper
      (§14) — verified hash length + refresh expiry
- [x] `app/core/logging.py` — structured logging (request_id, employee_id,
      organization_id, duration_ms) + request-ID middleware; never-log list
      (§23) — verified (no `redact` helper in this codebase; exclusion is by
      review per module docstring — follow-up: consider a `redact()` helper)
- [x] `app/db/pool.py` — `AsyncConnectionPool` (min/max from settings,
      `row_factory=dict_row`, `open=False` → opened in lifespan, closed on
      shutdown) — verified pool settings (min=2, max=10 from `.env.example`
      defaults)
- [x] `app/db/connection.py` — verified: yields from `pool.connection()`
      (commit on clean exit, rollback on exception); `transaction()` helper in
      `transaction.py` scopes multi-write workflows explicitly
- [x] `app/db/transaction.py` + `app/db/types.py` (`Conn = AsyncConnection[dict]`,
      `Row = dict`; dict_row decision documented)
- [x] `app/common/` — `pagination.py` (cursor + offset, `Page[T]` — verified
      success models returned directly — no data envelope), `permissions.py`
      (verified: `RequirePermission` factory, admin-bypass until Phase 4.3
      AuthorizationService), `utils.py` (verified: `utc_now`, `slugify`)
- [x] `app/main.py` — verified: `create_app()` factory, CORS middleware,
      `/health`, `/ready` (§24) — verified factory constructs; health router
      exposes both routes (app-level list shows `_IncludedRouter` because
      FastAPI expands `include_router` at startup/request time)
- [x] Phase 2 quality gates — `ruff check .`: All checks passed;
      `ruff format --check .`: 37 files already formatted;
      `pytest`: no tests ran (expected — tests land in Phase 3);
      `create_app()` factory constructs (verified); exception mapping
      (`to_app_exception`: UniqueViolation→409, FK→400, Check→422),
      Argon2id hash/verify, JWT create/decode, tokens, pagination cursor
      round-trip — all verified live
- [ ] Boot check (Phase 3 DB needed): `uvicorn app.main:app` boots;
      `/health`→200; `/ready` pings DB after `migrate`+`seed`

## Phase 3 — Shared Plumbing & Fixtures (before any domain module)

- [x] `app/api/v1/deps.py` — `require_membership` (DB-backed auth context
      rebuild; 401 no-membership) + `require_admin`; `RequirePermission`
      factory in `app/common/permissions.py` (§10)
- [ ] Verify `scripts/migrate.py`: fresh DB → `0001_initial.sql` applies cleanly;
      `scripts/seed.py` seeds Org A + Org B users (deterministic, no secrets)
- [x] `app/common/object_storage.py` — `ObjectStorage` interface + local-disk
      dev implementation (S3/MinIO swap later, §15)
- [x] `app/common/audit.py` — `AuditService.log` DRY helper (§37)
- [x] `app/notifications/` feature module — DB-backed notification creation
      (`schemas`/`repository`/`service`) + `BackgroundTasks` dispatch hook
      (`dispatch.py`, §38)
- [x] `tests/conftest.py` fixtures FIRST (§29): `db_connection`, `seeded_orgs`
      `test_client`, `admin_token`/`member_token`/`other_org_admin_token`
      (Org A/B tenant-isolation layout), `truncate_all` helper —
      integration fixtures skip cleanly when `TEST_DATABASE_URL` is unset
- [x] Phase 3 quality gates — `ruff check .`: All checks passed;
      `ruff format --check .`: 44 files already formatted;
      `pytest -m "not integration"`: no tests ran (expected — first DB tests
      land in Phase 4); all Phase 3 modules import cleanly
- [ ] Docker/Postgres pending (daemon unreachable from this shell —
      `docker ps` fails on `dockerDesktopLinuxEngine` pipe): start Docker
      Desktop, then `docker compose up -d --wait`, `migrate.py`, `seed.py`,
      `uvicorn app.main:app` boot + `/health`→200 + `/ready` DB ping

## Phase 4 — Feature Modules (each: router + schemas + repository + service)

> Order matters: **auth is the reference implementation** — everything else
> copies its shape. Every endpoint is implemented row-by-row against the
> **§49 contract table** in `ATS_BACKEND_ARCHITECTURE.md` (method, path, auth,
> request model, success code, error codes). All code is async (§48).

### 4.1 auth/ (reference module)
- [x] `schemas.py`: UserCreate, LoginRequest, TokenPair, RefreshRequest,
      OrganizationSwitchRequest, UserResponse
- [x] `repository.py`: user lookup by email, insert, token insert/revoke
      (hashed, expiry-checked), update `last_login_at`
- [x] `service.py`: register (Argon2id), login (verify + issue pair + org list),
      refresh (rotation — old token invalidated), logout (revoke),
      switch-organization (ADR-001: server-side membership re-validation)
- [x] `router.py`: `POST /auth/register|login|refresh|logout|switch-organization`
- [x] Tests: happy path, wrong password → 401, suspended/locked → 403,
      expired/unknown refresh → 401, rotation invalidates old token,
      switch to non-member org → 403
      (verified: `tests/unit/test_auth_service.py` + `tests/api/test_phase43_contract.py`
      + `tests/integration/test_phase43_tenant_isolation.py`; `ruff check` clean)

### 4.2 users/
- [x] `schemas.py`: UserResponse (never exposes password_hash), UserListItem,
      UserUpdate, EmployeeStatusCreate/Response
- [x] Endpoints (§49 #8–12): `GET /users/me`, `GET /users` (admin),
      `PATCH /users/{id}` (admin), employee-status log GET/POST
      (single-active constraint → 409 on conflict)
- [x] Tests: field-exposure audit (no sensitive fields), non-admin → 403,
      active-status conflict → 409
      (verified: `tests/unit/test_users_organizations_service.py` + contract tests;
      admin gate is router-level `require_admin`, existence/409 are service-level)

### 4.3 organizations/ (+ memberships + roles)
- [x] Create org (creator becomes admin member), list own, get (member),
      patch (admin) — §49 #13–20
- [x] Members: add/remove with admin guard + last-admin guard → 409;
      roles CRUD (org-scoped, `UNIQUE(name, organization_id)` → 409)
- [x] Tenant scoping: `WHERE organization_id = %s` in every query (§8)
      (path-org membership enforced in service: non-member → 404, member-non-admin → 403)
- [x] Tests: cross-org access → 404, non-admin → 403, duplicate slug → 409
      (verified: unit + contract + integration tests; `ruff check` /
      `ruff format --check` clean; `pytest -m "not integration"`: 59 passed;
      `-m integration` deselected — needs live Postgres + `TEST_DATABASE_URL`)

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

