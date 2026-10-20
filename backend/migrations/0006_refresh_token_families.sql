-- =============================================================
-- 0006 — REFRESH TOKEN FAMILIES (additive; never edit 0001, §18)
-- =============================================================
-- Refresh tokens are rotated on every use. Rotating by *deleting* the old
-- row made a replayed token indistinguishable from an unknown one, so
-- the server could not tell a stolen token from a client that simply
-- retried after a response was lost in transit.
--
-- Every refresh token now belongs to a family. Rotation keeps the old
-- row and records what replaced it, so a token that comes back after it
-- has already been rotated can be recognised:
--
--   * its replacement is still live  -> the client retried; continue the
--     chain instead of ending the session
--   * its replacement is rotated too  -> the token was replayed; the
--     whole family is revoked
--
-- ``family_id`` is NOT NULL with a random default, so every existing
-- token lands in a family of its own.

ALTER TABLE authentication_tokens
    ADD COLUMN family_id UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE authentication_tokens
    ADD COLUMN replaced_by_token_id INT
        REFERENCES authentication_tokens(token_id) ON DELETE SET NULL;

ALTER TABLE authentication_tokens
    ADD COLUMN revoked_at TIMESTAMP;

-- A token hash must be unique; the rotation below relies on it.
DELETE FROM authentication_tokens a
    USING authentication_tokens b
    WHERE a.token_id > b.token_id
      AND a.token_hash = b.token_hash;

CREATE UNIQUE INDEX uq_authentication_tokens_hash ON authentication_tokens(token_hash);

CREATE INDEX idx_authentication_tokens_family ON authentication_tokens(family_id);
