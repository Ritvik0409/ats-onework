# 🏢 ATS OneWork

The expense portal for **Aniruddha Telemetry System**. A Flutter app
with two portals — one for employees, one for management — over a
FastAPI and PostgreSQL backend.

The backend replaced an earlier Firebase implementation. The layering,
the endpoint contracts and the reasoning behind them live in
[`ATS_BACKEND_ARCHITECTURE.md`](ATS_BACKEND_ARCHITECTURE.md); what is
built and what is still to do is in [`todo.md`](todo.md).

## ✨ What it does

### 👤 Employee portal
- **Dashboard** — the state of your own expenses.
- **Submit an expense** — amount, date, project, category, a
  description and the receipt; the file's type is checked from its
  bytes, not from what the client says it is.
- **Your requests** — every submission with its status, and a way to
  answer a reviewer who has asked for more information.
- **Your projects** — the projects you are a member of.

### 👔 Management portal
- **Review queue** — the expenses waiting for a decision, with approve,
  reject and request-information.
- **Payouts** — move a reimbursement through its lifecycle and attach
  the receipt of the payment.
- **Projects and budgets** — projects, their members, and the budget
  each one draws on.
- **People** — the member directory and each person's working status.
- **Access** — the roles of the organization, what each role grants,
  and who holds what.

The portals show different things because the **server** decides, not
the app: an employee sees only their own expenses, and a manager sees
the whole organization. See the access model in the architecture doc,
§10.1.

## 🛠️ How it is built

| | |
|---|---|
| **App** | Flutter (Dart) — `lib/` |
| **API** | FastAPI, async end to end — `backend/app/` |
| **Database** | PostgreSQL 16, raw SQL, no ORM — `backend/migrations/` |
| **Auth** | JWT access tokens, opaque refresh tokens with rotation and replay detection |
| **Passwords** | Argon2id |
| **Authorization** | organization membership, roles and capabilities, all in the database |

The backend is layered strictly: **router → service → repository**.
Routers parse and delegate; services hold the rules; repositories own
the SQL. Nothing else.

## ▶️ Running it

### The API

```bash
cd backend
cp .env.example .env          # then set JWT_SECRET and the database password
uv sync
uv run python scripts/migrate.py
uv run python scripts/seed.py  # optional: two organizations with sample accounts
uv run uvicorn app.main:app --reload
```

The interactive documentation is at `http://localhost:8000/docs` — it is
not served in production.

### The app

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's alias for the host machine. On a
physical device, pass the machine's address on the network instead. The
base URL can also be set at build time:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

## ✅ Checks

```bash
cd backend
uv run ruff check .
uv run ruff format --check .
uv run pytest                    # 222 tests
```

The integration tests need a PostgreSQL they may create and drop; they
skip themselves when no database is configured.

```bash
flutter analyze
flutter test
```
