# ATS Backend Architecture & Engineering Guidelines

## Project

**ATS — Aniruddha Telemetry System**

This document is the engineering specification for AI coding agents working on the ATS backend.

The goal is to keep the backend:

- scalable
- reusable
- maintainable
- secure
- multi-tenant safe
- testable
- DRY without over-abstraction
- easy for multiple developers/agents to extend

---

# 1. Technology Stack

## Runtime

- Python 3.13+ target
- FastAPI
- Uvicorn `[standard]`
- Pydantic v2
- pydantic-settings

## Database

- PostgreSQL
- Prefer Psycopg 3 for new implementation:
  - `psycopg[binary,pool]`
- Use transactions explicitly.
- Keep SQL close to the repository/domain that owns it.

## Authentication / Security

- JWT access tokens using PyJWT
- Prefer Argon2 through `pwdlib[argon2]` for new password hashing.
- If bcrypt is retained, explicitly handle bcrypt's 72-byte password limit.
- Never log passwords, JWTs, refresh tokens, token hashes, or sensitive receipt data.

## File Uploads

- `python-multipart`
- Receipt files must be stored in object storage.
- PostgreSQL stores a URL/key/reference, not base64 file content.
- Object storage implementation should be abstracted so S3/R2/MinIO can be swapped.

## Validation

- Pydantic request/response schemas
- `email-validator`

## Development / Testing

- pytest
- httpx
- Ruff for linting and formatting
- uv for dependency/project management
- `uv.lock` must be committed

---

# 2. Current Repository Layout

The backend is isolated from the Flutter application.

Preferred layout:

```text
ats-onework/
├── backend/
│   ├── pyproject.toml
│   ├── uv.lock
│   ├── .env.example
│   ├── README.md
│   │
│   ├── migrations/
│   │   ├── 0001_initial.sql
│   │   ├── 0002_expense_tenant_constraints.sql
│   │   └── ...
│   │
│   ├── scripts/
│   │   ├── seed.py
│   │   ├── create_admin.py
│   │   └── healthcheck.py
│   │
│   ├── app/
│   │   ├── main.py
│   │   │
│   │   ├── core/
│   │   │   ├── config.py
│   │   │   ├── exceptions.py
│   │   │   ├── logging.py
│   │   │   ├── constants.py
│   │   │   └── security/
│   │   │       ├── passwords.py
│   │   │       ├── jwt.py
│   │   │       └── tokens.py
│   │   │
│   │   ├── db/
│   │   │   ├── pool.py
│   │   │   ├── connection.py
│   │   │   ├── transaction.py
│   │   │   └── types.py
│   │   │
│   │   ├── common/
│   │   │   ├── pagination.py
│   │   │   ├── responses.py
│   │   │   ├── permissions.py
│   │   │   └── utils.py
│   │   │
│   │   ├── auth/
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── repository.py
│   │   │   ├── service.py
│   │   │   └── dependencies.py
│   │   │
│   │   ├── users/
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── repository.py
│   │   │   └── service.py
│   │   │
│   │   ├── organizations/
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── repository.py
│   │   │   └── service.py
│   │   │
│   │   ├── expenses/
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── repository.py
│   │   │   ├── service.py
│   │   │   └── dependencies.py
│   │   │
│   │   ├── projects/
│   │   │   ├── router.py
│   │   │   ├── schemas.py
│   │   │   ├── repository.py
│   │   │   └── service.py
│   │   │
│   │   └── api/
│   │       └── v1/
│   │           └── router.py
│   │
│   └── tests/
│       ├── unit/
│       ├── integration/
│       └── conftest.py
```

Use **feature/domain-based organization** as the codebase grows.

Do NOT create large global folders containing dozens of unrelated files such as:

```text
schemas/
repositories/
services/
```

for every domain unless there is a strong reason.

Keep a feature's API, schemas, repository, and service close together.

---

# 3. Architectural Layers

The default dependency direction is:

```text
HTTP Request
    ↓
Router
    ↓
Dependencies / Authorization
    ↓
Service
    ↓
Repository
    ↓
PostgreSQL / Object Storage
```

## Router

Responsibilities:

- HTTP method/path
- request parsing
- response model
- dependency injection
- calling the service
- translating domain results to HTTP responses when necessary

Routers must NOT contain:

- complex business logic
- raw SQL
- transaction orchestration
- authorization rules duplicated across endpoints

Keep routers thin.

---

# 4. Service Layer

Services contain business rules and use repositories.

Example:

```python
class ExpenseService:
    # Services are async — psycopg3 runs on the asyncio event loop (§48).
    # conn is provided via dependency injection; the caller owns the transaction.
    async def approve_expense(
        self, conn: AsyncConnection, expense_id: int, actor: CurrentUser
    ) -> ExpenseResponse:
        ...
```

Services are responsible for:

- business rules
- workflow transitions
- authorization checks that depend on business state
- transaction coordination
- calling multiple repositories atomically
- audit operations
- notification orchestration

Example workflow:

```text
approve expense
    ↓
load expense FOR UPDATE
    ↓
verify organization
    ↓
verify permission
    ↓
verify current status
    ↓
change status
    ↓
create reimbursement if required
    ↓
write audit log
    ↓
create notification
    ↓
COMMIT
```

---

# 5. Repository Layer

Repositories own SQL and database access.

Example:

```python
class ExpenseRepository:
    def get_by_id(self, ...):
        ...

    def get_for_update(self, ...):
        ...

    def create(self, ...):
        ...

    def update_status(self, ...):
        ...
```

Repositories must NOT contain large business workflows.

A repository should not decide things like:

```text
"Can this expense be approved?"
```

That is service/business logic.

The repository should execute database operations required by the service.

---

# 6. Avoid Over-Abstracted Generic CRUD

Do NOT build a giant generic repository solely to maximize DRY.

Avoid forcing all domains into:

```python
BaseRepository.create()
BaseRepository.update()
BaseRepository.delete()
```

if the abstraction makes domain queries less readable.

Prefer domain-specific repositories:

```text
ExpenseRepository
ProjectRepository
UserRepository
ReimbursementRepository
```

DRY means removing **real duplication** while keeping domain behavior understandable.

Do not abstract code merely because two functions happen to have similar syntax.

---

# 7. Database Transactions

Transactions are critical for workflows involving multiple writes.

Do NOT let every repository silently call:

```python
conn.commit()
```

A service-level workflow should control the transaction.

Example:

```text
Service
  ↓
BEGIN
  ├── repository update
  ├── repository insert
  ├── audit log
  └── notification
  ↓
COMMIT
```

On failure:

```text
ROLLBACK
```

Transaction boundaries must be intentional.

Particularly protect:

- expense approval
- expense rejection
- reimbursement creation/payment
- role/permission changes
- membership changes
- status changes
- audit + state changes that must remain consistent

---

# 8. Multi-Tenancy Rules

ATS is a multi-tenant system.

Organization boundaries are a first-class security concern.

Every organization-owned operation must consistently verify tenant access.

The application should maintain an authenticated context similar to:

```python
CurrentUser:
    employee_id
    active_organization_id
```

If users can belong to multiple organizations, `active_organization_id` must be explicit.

Do not infer tenant access from a resource ID alone.

Prefer queries like:

```sql
SELECT *
FROM expenses
WHERE expense_id = %(expense_id)s
  AND organization_id = %(organization_id)s;
```

over:

```sql
SELECT *
FROM expenses
WHERE expense_id = %(expense_id)s;
```

when tenant isolation is relevant.

---

# 9. Cross-Tenant Integrity

The database must prevent organization mismatches.

Current expense protection should ensure:

```text
employee
    ↓
organization membership

project
    ↓
organization

expense_type
    ↓
organization

expense
    ↓
organization
```

The following relationships also require tenant consistency:

## Membership roles

Ensure:

```text
membership.organization_id = role.organization_id
```

## Role permissions

Ensure:

```text
role.organization_id = permission.organization_id
```

unless the permission is intentionally global.

## User permissions

Ensure the permission is valid for an organization the user belongs to.

## Project members

Ensure:

```text
employee organization
=
project organization
=
role organization
```

## Reimbursements

Ensure:

```text
expense organization
=
employee organization
=
reimbursement organization
```

Do not rely exclusively on application checks for these invariants.

Use appropriate PostgreSQL constraints, composite foreign keys, indexes, or triggers where needed.

---

# 10. Authorization

ATS uses organization membership + roles + permissions.

Do not scatter authorization checks across routers.

Create reusable authorization dependencies/services such as:

```text
get_current_user
require_authenticated_user
require_membership
require_permission
require_admin
require_org_access
```

Example conceptual usage:

```python
@router.post("/")
def create_expense(
    user: CurrentUser,
    _: RequirePermission["expense.create"],
):
    ...
```

Authorization should be reusable across endpoints.

Do not make every endpoint manually implement permission logic.

---

# 11. Request / Response Schemas

Do not use a single model everywhere.

Prefer explicit models:

```text
UserCreate
UserUpdate
UserResponse
UserListItem
UserInternal
```

For expenses:

```text
ExpenseCreate
ExpenseUpdate
ExpenseResponse
ExpenseListItem
ExpenseApprovalRequest
ExpenseApprovalResponse
```

Never expose internal fields accidentally.

Examples of fields that should not appear in normal API responses:

```text
password_hash
token_hash
internal security fields
private storage information
```

Map database results to Pydantic response schemas.

Do not blindly return raw database rows.

---

# 12. Authentication

Separate authentication responsibilities.

Recommended:

```text
core/security/
├── passwords.py
├── jwt.py
└── tokens.py
```

Responsibilities:

### passwords.py

- hash password
- verify password
- password policy helpers

### jwt.py

- create access token
- decode/verify JWT
- enforce allowed algorithms
- validate issuer/audience/expiration when configured

### tokens.py

- secure token generation
- token hashing
- token verification
- reset/email verification token helpers

Never trust the JWT `alg` value from a token to decide what algorithms the server accepts.

Always configure allowed algorithms explicitly.

---

# 13. Password Hashing

Preferred new implementation:

```text
pwdlib[argon2]
```

If bcrypt is retained:

- handle bcrypt's 72-byte password limit explicitly
- never store plaintext passwords
- never log passwords
- use a strong cost configuration
- keep password hashing isolated behind `passwords.py`

The rest of the application should call:

```python
hash_password(password)
verify_password(password, password_hash)
```

and should not know the hashing algorithm.

---

# 14. JWT / Token Storage

Store only hashes of server-side authentication tokens where appropriate.

Do NOT store raw reset/verification/refresh tokens in PostgreSQL if a hash-based design is intended.

Tokens should have:

- purpose
- expiration
- creation timestamp
- user association
- hashed value

Expired tokens should have a cleanup strategy.

Do not log tokens.

---

# 15. Object Storage

Receipt images must NOT be stored as base64 in PostgreSQL.

Use:

```text
FastAPI
   ↓
ObjectStorage abstraction
   ↓
S3 / Cloudflare R2 / MinIO
   ↓
URL/key stored in PostgreSQL
```

Create an interface/abstraction:

```python
class ObjectStorage:
    def upload(...)
    def delete(...)
    def generate_url(...)
```

Possible implementations:

```text
S3Storage
R2Storage
MinioStorage
```

The expense service must depend on the abstraction, not a specific provider.

---

# 16. PostgreSQL ID Strategy

For the new schema use PostgreSQL identity columns:

```sql
GENERATED ALWAYS AS IDENTITY
```

instead of introducing new `SERIAL` columns.

Keep IDs as integer/bigint according to expected scale.

Use `BIGINT` for high-growth tables if the expected volume warrants it.

---

# 17. PostgreSQL Indexing

Do not create indexes blindly.

Create indexes around:

- foreign keys used in joins
- common organization filters
- status filters used frequently
- timestamps used for sorting/filtering
- unique lookup fields
- common composite query patterns

Token lookup:

```sql
CREATE INDEX idx_auth_tokens_hash
ON authentication_tokens(token_hash);
```

Prefer the normal B-tree index unless real benchmarking demonstrates a reason to use a hash index.

Every index should have a reason tied to an actual query/workload.

---

# 18. Migrations

Do not treat a single:

```text
db/schema.sql
```

as the long-term production migration mechanism.

Use versioned migrations:

```text
migrations/
├── 0001_initial.sql
├── 0002_add_expense_constraints.sql
├── 0003_add_reimbursement_rules.sql
├── 0004_add_indexes.sql
└── ...
```

Never edit an already-applied production migration destructively.

Add a new migration instead.

The database schema and migration history must remain reproducible.

---

# 19. Seed Data

Seed data should be deterministic and safe to rerun where practical.

Separate:

```text
schema/migrations
```

from:

```text
development/test seed data
```

Do not put production secrets into seed files.

Never hard-code real passwords or credentials.

---

# 20. API Versioning

Use:

```text
/api/v1/...
```

Keep API versioning centralized:

```text
app/api/v1/router.py
```

Example:

```text
/api/v1/auth
/api/v1/users
/api/v1/organizations
/api/v1/projects
/api/v1/expenses
/api/v1/reimbursements
/api/v1/notifications
```

Do not hard-code version prefixes independently in every endpoint.

---

# 21. Pagination

Create shared pagination infrastructure.

Example:

```python
class PaginationParams(BaseModel):
    page_size: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None
```

For high-volume resources prefer cursor/keyset pagination where appropriate.

Important candidates:

- expenses
- audit logs
- notifications
- approvals

Avoid very large `OFFSET` pagination for high-volume tables.

---

# 22. Error Handling

Create common application exceptions:

```text
AppException
├── AuthenticationError
├── AuthorizationError
├── NotFoundError
├── ConflictError
├── ValidationError
└── DatabaseError
```

Map errors consistently:

```text
401 Authentication
403 Authorization
404 Not Found
409 Conflict
422 Validation
500 Unexpected Internal Error
```

Never expose raw SQL/database errors to API clients.

Do not expose stack traces in production responses.

---

# 23. Logging

Use structured logging.

Useful fields:

```text
request_id
employee_id
organization_id
endpoint
method
status_code
duration_ms
error_type
```

Never log:

```text
password
password_hash
JWT
refresh token
reset token
token_hash
private receipt data
```

Add request correlation IDs so errors can be traced across logs.

---

# 24. Main Application

Keep `main.py` small.

Preferred concept:

```python
def create_app() -> FastAPI:
    app = FastAPI(...)

    register_middleware(app)
    register_exception_handlers(app)
    register_routers(app)

    return app


app = create_app()
```

Avoid putting business logic in `main.py`.

---

# 25. Dependency Injection

Use FastAPI dependency injection for:

- database connections
- current user
- organization context
- authorization
- pagination
- services where appropriate

Avoid creating database connections directly in route handlers.

Prefer:

```text
request
  ↓
dependency
  ↓
connection/service
  ↓
router
```

---

# 26. Testing Strategy

Use three main categories.

## Unit tests

Test isolated logic:

```text
test_security.py
test_expense_service.py
test_permission_service.py
test_pagination.py
```

Mock external dependencies where appropriate.

## Integration tests

Run against a real PostgreSQL database.

Test:

- SQL
- constraints
- triggers
- transactions
- repository behavior
- tenant isolation

## API tests

Test:

- authentication
- authorization
- validation
- HTTP behavior
- response contracts

Do not rely only on mocked database tests.

---

# 27. Multi-Tenant Security Tests

These are mandatory.

Create at least two organizations:

```text
Org A
Org B
```

and users:

```text
User A → Org A
User B → Org B
```

Test that User A cannot:

```text
read Org B expenses
modify Org B expenses
approve Org B expenses
read Org B projects
modify Org B projects
assign Org B roles
modify Org B reimbursements
access Org B notifications
```

Also test cross-tenant write attempts directly against repository/service/database behavior.

---

# 28. Database Tests

Because ATS relies heavily on PostgreSQL constraints, integration tests must verify:

- foreign keys
- unique constraints
- partial unique indexes
- check constraints
- tenant consistency
- triggers
- transaction rollback
- concurrent update behavior where relevant

Do not assume application validation replaces database validation.

---

# 29. Testing Fixtures

Keep reusable fixtures in:

```text
tests/conftest.py
```

Useful fixtures:

```text
postgres_db
db_connection
test_client
user
organization
membership
admin_user
expense
project
auth_token
```

Fixtures should be composable and minimal.

Avoid one gigantic fixture that creates the entire application state unless the test genuinely needs it.

---

# 30. Code Quality

Use Ruff.

Recommended categories include:

```toml
[tool.ruff.lint]
select = [
    "E",
    "F",
    "I",
    "B",
    "UP",
    "SIM",
    "ARG",
    "RUF",
]
```

Run:

```bash
ruff check .
ruff format .
```

CI should fail on lint/format violations.

---

# 31. Type Hints

Use type hints consistently.

Prefer:

```python
def get_expense(
    expense_id: int,
    organization_id: int,
) -> Expense | None:
    ...
```

instead of untyped functions.

Use explicit return types for services and repositories.

Avoid `Any` unless genuinely necessary.

---

# 32. SQL Rules

Prefer parameterized SQL.

Correct:

```python
cursor.execute(
    """
    SELECT *
    FROM expenses
    WHERE expense_id = %s
    """,
    (expense_id,),
)
```

Never construct SQL using string interpolation:

```python
# DO NOT DO THIS
query = f"SELECT * FROM expenses WHERE expense_id = {expense_id}"
```

Keep SQL readable.

Use named helper methods for complex queries.

---

# 33. Repository SQL Style

Repository methods should make their intent obvious.

Prefer:

```text
get_by_id
get_by_id_for_update
get_by_email
list_by_organization
create
update
delete
update_status
```

rather than a huge generic method whose behavior changes based on many flags.

Explicit code is preferable to magical abstractions.

---

# 34. Avoid Circular Dependencies

Recommended dependency direction:

```text
router
  ↓
service
  ↓
repository
  ↓
db
```

Not:

```text
repository → service
service → router
schema → repository
```

Keep modules independent.

---

# 35. Domain Service Boundaries

Examples:

## ExpenseService

Owns:

- expense creation rules
- approval
- rejection
- reimbursement initiation
- expense state transitions

## ReimbursementService

Owns:

- reimbursement lifecycle
- payment state
- payment reference
- paid timestamp

## MembershipService

Owns:

- joining/leaving organization
- admin changes
- role assignment

## AuthorizationService

Owns:

- permission evaluation
- role/permission resolution

Avoid putting all business logic into one giant `UserService` or `AppService`.

---

# 36. State Machines / Status Rules

Status fields are business state machines.

Examples:

```text
Expense:
pending → approved
pending → rejected
approved → reimbursed
```

```text
Reimbursement:
pending → processing
processing → paid
processing → failed
```

Do not allow arbitrary status transitions.

Put transition rules inside services and enforce important invariants in PostgreSQL where practical.

---

# 37. Audit Logging

Important mutations should create audit entries.

Examples:

- user status change
- role assignment
- permission changes
- expense approval
- expense rejection
- reimbursement payment
- organization administration changes

Audit entries should capture enough information to answer:

```text
who
did what
to which record
when
before
after
```

Do not store secrets in `old_values` or `new_values`.

---

# 38. Notification Design

Notifications should be generated by services/workflows, not directly from every route.

Example:

```text
ExpenseService
    ↓
approve expense
    ↓
NotificationService
    ↓
create notification
```

This keeps notification behavior reusable.

---

# 39. External Providers

Any external service should be behind an interface.

Examples:

```text
ObjectStorage
EmailSender
PaymentProvider
NotificationSender
```

The business logic should depend on the interface.

This makes tests easier and future provider changes cheaper.

---

# 40. Configuration

Use `pydantic-settings`.

Keep secrets in environment variables.

Example categories:

```text
APP_ENV
DATABASE_URL
JWT_SECRET
JWT_ALGORITHM
JWT_ACCESS_TOKEN_EXPIRE_MINUTES
S3_ENDPOINT
S3_BUCKET
S3_ACCESS_KEY
S3_SECRET_KEY
```

Use `.env.example` as a template only.

Never commit real credentials.

---

# 41. Environment Separation

Support at least:

```text
development
test
production
```

Never run tests against production databases.

Never use production credentials in local development.

---

# 42. AI Agent Rules

When modifying this repository, the AI agent MUST:

1. Read the relevant domain files before changing them.
2. Preserve existing architecture unless there is a clear reason to refactor.
3. Avoid unnecessary abstractions.
4. Follow the Router → Service → Repository → DB boundary.
5. Keep tenant isolation in every organization-sensitive operation.
6. Prefer database constraints for invariant enforcement.
7. Use parameterized SQL only.
8. Use transactions for multi-step state changes.
9. Add/update tests for behavior changes.
10. Run Ruff after Python changes.
11. Run relevant tests after changes.
12. Do not silently change database semantics.
13. Do not modify migrations that may already have been applied; add a new migration.
14. Do not expose secrets or sensitive fields through API schemas/logs.
15. Do not bypass authorization to make a feature work.
16. Keep changes focused and minimal.
17. Reuse existing utilities before creating duplicates.
18. Do not create generic abstractions without at least two real use cases.
19. Keep database queries tenant-aware.
20. Document architectural decisions when introducing a new pattern.

---

# 43. AI Agent Decision Rules

Before writing new code:

```text
1. Is there already a helper/service/repository for this?
      ↓ yes → reuse it
      ↓ no

2. Is this domain-specific?
      ↓ yes → put it in the domain module
      ↓ no

3. Is it shared infrastructure?
      ↓ yes → put it in core/common/db
      ↓ no

4. Does it contain business rules?
      ↓ yes → service
      ↓ no

5. Does it execute SQL?
      ↓ yes → repository
      ↓ no

6. Is it HTTP-specific?
      ↓ yes → router
```

---

# 44. Definition of Done

A backend feature is not complete until:

- [ ] Request schema exists
- [ ] Response schema exists
- [ ] Authorization is implemented
- [ ] Tenant isolation is verified
- [ ] Service contains business rules
- [ ] Repository contains SQL
- [ ] Transactions are correct
- [ ] Database constraints are correct
- [ ] Migration exists if schema changes
- [ ] Unit tests exist where useful
- [ ] Integration tests cover DB behavior
- [ ] API tests cover important endpoints
- [ ] Error handling is consistent
- [ ] Logging does not leak sensitive information
- [ ] Ruff passes
- [ ] Relevant pytest tests pass
- [ ] API documentation remains accurate

---

# 45. Priority Improvements for the Current ATS Backend

Implement these in roughly this order:

## P0 — Security / Integrity

1. Complete cross-tenant database integrity.
2. Add tenant-aware repository queries.
3. Centralize authorization.
4. Verify JWT algorithm/configuration.
5. Protect sensitive fields and logs.
6. Ensure transaction correctness for approval/reimbursement workflows.

## P1 — Architecture

1. Move toward feature/domain-based modules.
2. Separate password/JWT/token security modules.
3. Introduce explicit transaction handling.
4. Introduce domain-specific repositories.
5. Introduce reusable authorization dependencies/services.
6. Add object-storage abstraction.

## P2 — Database

1. Use versioned migrations.
2. Review indexes based on actual queries.
3. Add missing organization consistency constraints.
4. Review reimbursement consistency.
5. Keep ERD synchronized with the actual schema.

## P3 — Testing

1. Unit tests for services/security.
2. PostgreSQL integration tests.
3. Multi-tenant isolation tests.
4. Approval/reimbursement workflow tests.
5. Transaction rollback tests.
6. API contract tests.

## P4 — Operational Quality

1. Structured logging.
2. Request IDs.
3. Health checks.
4. Metrics/observability.
5. CI checks for Ruff + pytest.
6. Deployment configuration.

---

# 46. Important Design Principle

Do NOT optimize for "most abstract architecture".

Optimize for:

```text
Correctness
   ↓
Security
   ↓
Maintainability
   ↓
Testability
   ↓
Performance
   ↓
Abstraction
```

Good DRY:

```text
shared pagination
shared authorization
shared transaction infrastructure
shared object-storage interface
shared error handling
shared security helpers
```

Bad DRY:

```text
one generic repository for every table
one generic service for every domain
one mega-schema for every API response
one mega-dependency file
one mega-utils.py
```

The code should remain obvious to a developer who did not write the original feature.

---

# 47. Target Architecture Summary

```text
                    Flutter Client
                          │
                          ▼
                     FastAPI API
                          │
                    ┌─────┴─────┐
                    │           │
                 Router   Dependencies
                    │           │
                    └─────┬─────┘
                          ▼
                      Services
                          │
          ┌───────────────┼────────────────┐
          ▼               ▼                ▼
    Repositories   Authorization     Object Storage
          │
          ▼
      PostgreSQL
          │
      ┌───┴───────────┐
      ▼               ▼
 Constraints          RLS
```

The goal is to make each layer have one clear responsibility while keeping the system easy to test and extend.

---

# 48. Async Execution Rules

Psycopg 3 connections are asyncio-native. Therefore:

- All routers, services, and repositories are `async def`.
- Never perform blocking I/O inside async functions (no `requests`, no `time.sleep`, no sync DB drivers).
- Argon2 hashing is CPU-bound (~50–100 ms). Wrap password hash/verify in `asyncio.to_thread(...)` inside `passwords.py` so the event loop stays responsive:

```python
async def hash_password(password: str) -> str:
    return await asyncio.to_thread(_hasher.hash, password)
```

- FastAPI `BackgroundTasks` runs after the response completes; use it for notification dispatch and similar non-critical side effects.
- Examples elsewhere in this document show synchronous signatures for readability; every real implementation must be async as described here.

# 49. Endpoint Contract Table (v1)

Conventions:

- All paths are prefixed with `/api/v1` (centralized in `app/api/v1/router.py`).
- Auth levels: `public`, `user` (authenticated), `member` (active membership in the token's organization), `admin` (`is_admin` membership in that organization).
- Cross-tenant resource access returns **404** (never reveal existence of another organization's resources); permission failures on same-org resources return **403**.
- List endpoints return `Page[T] = { items: T[], next_cursor: str | null }` using cursor/keyset pagination (§21); small admin reference lists may accept `limit`/`offset`.
- All error responses use the shared error envelope (§22).

| # | Method | Path | Auth | Request | Success | Errors |
|----|--------|------|------|---------|---------|--------|
| 1 | GET | /health | public | — | 200 | — |
| 2 | GET | /ready | public | — | 200 / 503 | — |
| 3 | POST | /auth/register | public | UserCreate | 201 UserResponse | 409 (email exists), 422 |
| 4 | POST | /auth/login | public | LoginRequest | 200 TokenPair (+ org list) | 401, 403 (suspended/locked), 422 |
| 5 | POST | /auth/refresh | public | RefreshRequest | 200 TokenPair | 401 (expired/unknown/revoked) |
| 6 | POST | /auth/logout | user | — | 204 | 401 |
| 7 | POST | /auth/switch-organization | user | OrganizationSwitchRequest | 200 TokenPair | 403 (not a member), 404 |
| 8 | GET | /users/me | user | — | 200 UserResponse | 401 |
| 9 | GET | /users | admin | query filters | 200 Page[UserListItem] | 403 |
| 10 | PATCH | /users/{employee_id} | admin | UserUpdate | 200 UserResponse | 403, 404 |
| 11 | GET | /users/{employee_id}/statuses | admin | — | 200 list[EmployeeStatusResponse] | 403, 404 |
| 12 | POST | /users/{employee_id}/statuses | admin | EmployeeStatusCreate | 201 EmployeeStatusResponse | 403, 404, 409 (active exists), 422 |
| 13 | POST | /organizations | user | OrganizationCreate | 201 OrganizationResponse (creator becomes admin member) | 409 (slug), 422 |
| 14 | GET | /organizations | user | — | 200 list of own memberships/orgs | 401 |
| 15 | GET | /organizations/{organization_id} | member | — | 200 OrganizationResponse | 404 |
| 16 | PATCH | /organizations/{organization_id} | admin | OrganizationUpdate | 200 OrganizationResponse | 403, 404 |
| 17 | POST | /organizations/{id}/members | admin | MembershipCreate | 201 MembershipResponse | 403, 404, 409 |
| 18 | DELETE | /organizations/{id}/members/{employee_id} | admin | — | 204 | 403, 404, 409 (last admin) |
| 19 | GET | /organizations/{id}/roles | member | — | 200 list[RoleResponse] | 404 |
| 20 | POST | /organizations/{id}/roles | admin | RoleCreate | 201 RoleResponse | 403, 409, 422 |
| 21 | POST | /organizations/{id}/budgets | admin | BudgetCreate | 201 BudgetResponse | 403, 404, 422 |
| 22 | POST | /organizations/{id}/projects | admin | ProjectCreate | 201 ProjectResponse | 403, 404, 409 |
| 23 | GET | /organizations/{id}/projects | member | filters | 200 Page[ProjectListItem] | 404 |
| 24 | PATCH | /projects/{project_id} | admin | ProjectUpdate | 200 ProjectResponse | 403, 404 |
| 25 | POST | /organizations/{id}/expense-types | admin | ExpenseTypeCreate | 201 ExpenseTypeResponse | 403, 404, 409 |
| 26 | GET | /organizations/{id}/expense-types | member | — | 200 list[ExpenseTypeResponse] | 404 |
| 27 | POST | /expenses | member | multipart: ExpenseCreate + receipt files | 201 ExpenseResponse | 403, 404 (project/type not in org), 422 |
| 28 | GET | /expenses | member | status / from / to filters | 200 Page[ExpenseListItem] | 404 |
| 29 | GET | /expenses/{expense_id} | member | — | 200 ExpenseResponse | 404 |
| 30 | GET | /approvals/pending | admin | — | 200 Page[ExpenseListItem] | 403 |
| 31 | POST | /expenses/{id}/approve | admin | ApprovalActionRequest | 200 ExpenseResponse | 403, 404, 409 (not pending), 422 |
| 32 | POST | /expenses/{id}/reject | admin | ApprovalActionRequest (comments required) | 200 ExpenseResponse | 403, 404, 409, 422 (missing comments) |
| 33 | POST | /expenses/{id}/reimbursement | admin | ReimbursementCreate | 201 ReimbursementResponse | 403, 404, 409 (UNIQUE expense_id), 422 |
| 34 | GET | /reimbursements | member | status filter | 200 Page[ReimbursementListItem] | 404 |
| 35 | POST | /reimbursements/{id}/transition | admin | ReimbursementTransitionRequest | 200 ReimbursementResponse | 403, 404, 409 (invalid transition), 422 (paid without reference) |
| 36 | GET | /notifications | user | — | 200 Page[NotificationResponse] | 401 |
| 37 | POST | /notifications/{id}/read | user (owner) | — | 204 | 403, 404 |
| 38 | POST | /notifications/read-all | user | — | 204 | 401 |
| 39 | GET | /audit-logs | admin | filters | 200 Page[AuditLogResponse] | 403 |

# 50. psycopg3 Exception Mapping

Handled centrally in exception handlers (§22) — never per-repository:

| psycopg exception | AppException | HTTP |
|---|---|---|
| `UniqueViolation` (23505) | ConflictError | 409 |
| `ForeignKeyViolation` (23503) | ValidationError ("referenced record does not exist or is in use") | 400 |
| `CheckViolation` (23514) | ValidationError | 422 |
| `NotNullViolation` (23502) | ValidationError | 422 |
| `ExclusionViolation` (23P01) | ConflictError | 409 |
| `LockNotAvailable`, `QueryCanceled` (statement_timeout) | TransientError | 503 (logged; retriable) |
| anything else | InternalError | 500 (full detail logged with `request_id`, never returned) |

Constraint names are stable identifiers — map specific violations (e.g., `users_email_key`) to precise error codes/messages where a better client experience is warranted. Raw PostgreSQL messages must never reach API clients.

---

# 51. ADR-001: Multi-Organization Context (`active_organization_id`)

**Decision:** the JWT access token carries `sub` (employee_id), `org` (active organization_id), `admin` (is_admin for that organization), plus `exp`/`iat`.

- **Login** resolves the user's memberships; if exactly one active membership exists, that organization becomes active. The token response also includes the organization list (ADR: token remains stateless; no server session).
- **Switch:** `POST /auth/switch-organization` re-issues a token after server-side membership validation. Membership is never trusted from the client.
- **Every request:** `get_current_user` decodes the JWT and builds `CurrentUser(employee_id, organization_id, is_admin)`, which feeds §8's tenant rules.
- **Rationale:** stateless, auditable (each token is org-scoped), and satisfies §8's requirement that `active_organization_id` be explicit rather than inferred.



