-- =============================================================
-- 0005 — AUDIT TENANCY (additive; never edit 0001, §18)
-- =============================================================
-- Audit rows now record the organization the change happened in.
--
-- The read endpoint used to derive the tenant from the actor's
-- membership, which meant a person who belongs to two organizations
-- exposed their actions in one of them to the administrators of the
-- other, and rows whose actor had been deleted (``actor_id IS NULL``)
-- were visible to every organization's administrators.
--
-- Legacy rows are backfilled only where the actor has exactly one
-- membership; an actor with several organizations is ambiguous, so
-- those rows keep a NULL organization and stay out of every tenant's
-- view rather than being shown to the wrong one.

ALTER TABLE audit_logs
    ADD COLUMN organization_id INT
        REFERENCES organizations(organization_id) ON DELETE CASCADE;

UPDATE audit_logs l
   SET organization_id = m.organization_id
  FROM memberships m
 WHERE l.actor_id = m.employee_id
   AND l.organization_id IS NULL
   AND NOT EXISTS (
       SELECT 1 FROM memberships m2
        WHERE m2.employee_id = l.actor_id
          AND m2.organization_id <> m.organization_id
   );

CREATE INDEX idx_audit_logs_org ON audit_logs(organization_id, log_id DESC);
