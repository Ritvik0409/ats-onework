"""Rate limiting for the sign-in endpoints (arch. doc §40, §48).

The counters live in the database, so every worker of a multi-process
deployment shares them. A counter in memory would be reset by every
restart and would not see the attempts landing on another worker.

The limit that matters is the one on the address: the one on an email
address is a second line of defence, and a generous one. A person who
fat-fingers their password a few times should not be locked out of
their own account by a colleague's guessing.

Verifying a password is deliberately expensive (Argon2id, tens of
milliseconds of CPU), so an unlimited sign-in endpoint is also a way to
make the server spend all its time hashing. These limits bound that.

All clock arithmetic here lives on the IST axis: the connection pool
pins every session's ``TimeZone`` to ``Settings.db_timezone``, so
``CURRENT_TIMESTAMP`` written into the buckets and the comparisons
against it are consistent with :func:`ist_now_naive` — no UTC-side
assumption, no session-zone drift.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.core.exceptions import RateLimitExceeded
from app.core.security.tokens import ist_now_naive
from app.db.types import Conn


@dataclass(frozen=True, slots=True)
class Limit:
    """One limit: how many attempts, over how long a window."""

    count: int
    window_seconds: int


#: Sign-in. Thirty attempts a minute from one address is generous for
#: a person -- and for an office sharing one address -- while still
#: bounding what an unauthenticated caller can make the server hash.
LOGIN_PER_ADDRESS = Limit(count=30, window_seconds=60)
#: The same address may not try many different accounts.
LOGIN_PER_ADDRESS_ACCOUNTS = Limit(count=50, window_seconds=300)
#: One account may not be guessed at from many addresses. This is the
#: limit that actually protects a password.
LOGIN_PER_ACCOUNT = Limit(count=15, window_seconds=900)
#: Registration is cheap to call and expensive to abuse.
REGISTER_PER_ADDRESS = Limit(count=20, window_seconds=3600)
#: A client refreshing its access token is normal, and a mobile client
#: on a flaky connection may do it often.
REFRESH_PER_ADDRESS = Limit(count=120, window_seconds=60)


async def hit(conn: Conn, *, key: str, limit: Limit) -> None:
    """Count one attempt against ``key`` and refuse when it is over.

    A fixed window: the counter resets once the window has passed. The
    counter row is only touched when the limit is actually reached, so
    the common case is a single read.
    """
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT hits, window_start
              FROM rate_limit_buckets
             WHERE bucket_key = %s
               AND window_start > CURRENT_TIMESTAMP - (%s::int * INTERVAL '1 second')
            """,
            (key, limit.window_seconds),
        )
        row = await cur.fetchone()

    if row is not None and int(row["hits"]) >= limit.count:
        elapsed = await _elapsed(conn, key)
        retry_after = max(1, int(limit.window_seconds - elapsed))
        raise RateLimitExceeded(retry_after)

    async with conn.cursor() as cur:
        await cur.execute(
            """
            INSERT INTO rate_limit_buckets (bucket_key, window_start, hits)
            VALUES (%s, CURRENT_TIMESTAMP, 1)
            ON CONFLICT (bucket_key) DO UPDATE
               SET hits = CASE
                             WHEN rate_limit_buckets.window_start
                                  <= CURRENT_TIMESTAMP
                                     - (%s::int * INTERVAL '1 second')
                             THEN 1
                             ELSE rate_limit_buckets.hits + 1
                         END,
                   window_start = CASE
                                     WHEN rate_limit_buckets.window_start
                                          <= CURRENT_TIMESTAMP
                                             - (%s::int * INTERVAL '1 second')
                                     THEN CURRENT_TIMESTAMP
                                     ELSE rate_limit_buckets.window_start
                                 END
            """,
            (key, limit.window_seconds, limit.window_seconds),
        )
    # The counter has to outlive the request it counted. A failed
    # sign-in ends the request with a rollback, which would take the
    # count with it — and the attempts that matter are the ones that
    # failed. It is committed here, before the request does anything
    # else, so nothing else is caught up in it.
    await conn.commit()


async def _elapsed(conn: Conn, key: str) -> float:
    """Seconds since the bucket's window opened, 0 when there is no bucket.

    The subtraction is the Python mirror of what the SQL comparisons in
    :func:`hit` already rely on: the session's ``TimeZone`` is pinned to
    ``Settings.db_timezone``, and :func:`ist_now_naive` reads the same
    clock, so a naive stored value and a naive now() subtract cleanly.
    """
    async with conn.cursor() as cur:
        await cur.execute(
            "SELECT window_start FROM rate_limit_buckets WHERE bucket_key = %s", (key,)
        )
        row = await cur.fetchone()
    if row is None:
        return 0.0
    return max(0.0, (ist_now_naive() - row["window_start"]).total_seconds())


async def clear(conn: Conn, *, key: str) -> None:
    """Forget the attempts against a key — used after a successful sign-in."""
    async with conn.cursor() as cur:
        await cur.execute("DELETE FROM rate_limit_buckets WHERE bucket_key = %s", (key,))
    await conn.commit()


async def purge_stale(conn: Conn, *, older_than_seconds: int = 3600) -> int:
    """Drop the counters that are no longer counting anything."""
    async with conn.cursor() as cur:
        await cur.execute(
            "DELETE FROM rate_limit_buckets"
            " WHERE window_start <= CURRENT_TIMESTAMP - (%s::int * INTERVAL '1 second')",
            (older_than_seconds,),
        )
        return cur.rowcount
