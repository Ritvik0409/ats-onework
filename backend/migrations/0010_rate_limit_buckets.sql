-- =============================================================
-- 0010 — RATE LIMIT BUCKETS (additive; never edit 0001, §18)
-- =============================================================
-- The sign-in endpoints were open: any number of attempts, from
-- anywhere. Two problems follow from that.
--
--   * A password can be guessed without limit.
--   * Verifying a password is deliberately expensive (Argon2id, tens of
--     milliseconds of CPU). An open endpoint is therefore also a way to
--     make the server spend all its time hashing.
--
-- The counters live in the database so every worker of a multi-process
-- deployment shares them -- a counter in memory would be reset by
-- every restart and would not see the attempts landing on another
-- worker.
--
-- One row per key, holding the hits in the current window. A key is
-- the caller's address, or their email address, or both.

CREATE TABLE rate_limit_buckets (
    bucket_key   VARCHAR(200)    PRIMARY KEY,
    window_start TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hits         INT             NOT NULL DEFAULT 0
);

CREATE INDEX idx_rate_limit_buckets_window ON rate_limit_buckets(window_start);
