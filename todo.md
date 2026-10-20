# ATS OneWork — current state and what is left

> The backend migration from Firebase to FastAPI and PostgreSQL is
> finished. This file records what the system is now, what is verified,
> and what is genuinely outstanding. The design lives in
> [`ATS_BACKEND_ARCHITECTURE.md`](ATS_BACKEND_ARCHITECTURE.md); the
> original migration plan is kept in [`plan.md`](plan.md) for the record.

---

## What is built

### The API — `backend/`

Strictly layered: **router → service → repository**. Routers parse and
delegate, services hold the rules, repositories own the SQL, and the
database enforces the boundaries that must hold whatever the application
does.

| Domain | What it does |
|---|---|
| `auth` | register, sign in, refresh with rotation and replay detection, sign out, switch organization, change your own password |
| `users` | profiles, the member directory, the working-status log |
| `organizations` | organizations, memberships, roles, budgets, projects, expense types |
| `expenses` | submit, review (approve / reject / request information), resubmit, receipts, reimbursements |
| `reimbursements` | the payout lifecycle, and the receipt of the payment |
| `projects` | projects, their members, access requests |
| `access` | the capability catalogue, an organization's roles and their grants, and who holds what |
| `notifications` | per-user notifications, and the dispatch hook |
| `audit_logs` | the audit trail, scoped to an organization |

### The access model

Three separate things, all in the database:

- a **capability** belongs to an organization;
- a **role** belongs to an organization and grants capabilities;
- a **membership** holds roles, and may hold capabilities of its own.

An employee holds `expense.read_own` and not `expense.read_all`, so
they see their own expenses and nothing else. A manager, finance user,
director or HR user holds `expense.read_all` and sees the organization.
The scope is decided by the server, on every request, so a grant that
is withdrawn applies at once.

A **super administrator** (`users.is_superuser`) administers the
capability catalogue and any organization's access. That is separate
from an organization's `is_admin`, which means "owns this
organization" — a different thing from "reviews expenses".

### The app — `lib/`

Two portals. Which one a person gets, and what they can do inside it,
is decided by the capabilities the server reports for them, not by a
flag in the app.

---

## What is verified

| | |
|---|---|
| **222 tests** | `uv run pytest` — unit, API-contract and integration |
| **66 integration tests** | against a real PostgreSQL, created and dropped for the run |
| **Lint** | `uv run ruff check .` and `uv run ruff format --check .` — clean |
| **Analysis** | `flutter analyze` — clean |

The integration tests cover the things that only a real database shows:
that one organization cannot reach another's roster, that a
cross-organization reimbursement is refused by the database itself,
that an expense's status machine is enforced even by raw SQL, that an
employee sees one expense where an administrator sees two, and that a
grant that is withdrawn takes effect on the next request.

---

## What is outstanding

Ordered by how much it would be worth doing.

### 1. Email verification

`users` has no `email_verified` column, so `/auth/register` creates a
loginable account immediately. Anyone can register with someone else's
address and take it. The fix needs a verification token, a resend
endpoint, an expiry, and a screen in the app.

It is blocked on a decision: **which mail provider**. The repository
has no SMTP or SendGrid configuration, so the choice has not been made.
The flow can be built now with a provider interface whose default
implementation logs the link, and the real sender dropped in later.

### 2. The super administrator's screen for the catalogue

The API for the capability catalogue is complete and tested
(`/system/catalog`), but the app has no screen for it: the access
screen manages an organization's roles, while the platform-level
catalogue is API-only. The same goes for promoting a user to super
administrator — the endpoint exists, the button does not.

### 3. Paging in the app

The API pages by cursor, and `ApiClient.pageCursor` is written and
unused. Every list in the app asks for at most 100 rows and stops
there, so an organization with more than a hundred expenses silently
loses the rest. The fix is a "load more" affordance over the existing
cursor.

### 4. An audit-log screen

`GET /audit-logs` is implemented, tested and tenant-scoped. No screen
in the app calls it, so the audit trail is invisible to the people who
would read it.

### 5. Row-level security in the database

The application scopes every query to one organization, and composite
foreign keys stop a grant pointing at another organization's data. But
the database itself has no row-level security: a connection with the
wrong `organization_id` set would still read across organizations.

This is defence in depth rather than a live hole. It becomes worth
doing if the API ever grows a second consumer of the database.

### 6. A backup and restore routine

Nothing automates a backup of the database or of the uploaded
receipts. The object storage abstraction is in place (§15), so the
uploaded files could be moved to S3 or MinIO without touching the
application, but no routine moves them.

### 7. Deprecating the employee-id sign-in

`POST /auth/login` accepts a bare employee id as well as an email
address, for a flow that no client uses any more. The email path is
the one that should survive.

### 8. Sessions on the client

The access and refresh tokens are kept in `SharedPreferences`, which is
an unencrypted file in the app's sandbox. Android's auto-backup is now
switched off, so they are not copied into a cloud backup, but a device
that is rooted, or an attacker with the app's sandbox, still has them.
`flutter_secure_storage` would keep them in the platform keystore.

### 9. Multi-organization accounts on the client

The API supports a person belonging to several organizations, and
`POST /auth/switch-organization` moves between them. The app signs
into one and stays there. A person with two memberships has to sign
out and back in to use the other.

---

## Things that were deliberately left alone

- **The `categories` and `project_categories` tables** are unused. The
  schema has them; the application does not, and no endpoint exposes
  them. They can be dropped in a migration when there is certainty
  nobody wants them.
- **`EMPLOYEE_ID`-style logins** (see 7 above).
- **Email verification** (see 1 above).
