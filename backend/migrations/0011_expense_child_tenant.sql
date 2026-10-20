-- =============================================================
-- 0011 — ORGANIZATION ON THE EXPENSE CHILD TABLES
-- =============================================================
-- `expense_media` and `expense_approvals` hung off an expense without
-- carrying an organization of their own, so a query that reached them
-- directly could not scope itself by tenant -- it had to trust that
-- the expense id it was given had already been checked.
--
-- They now carry the organization, the same way every other
-- organization-owned table does, so a query can always say which
-- organization it is reading. The rows are backfilled from their
-- expense, whose organization never changes.

ALTER TABLE expense_media
    ADD COLUMN organization_id INT REFERENCES organizations(organization_id) ON DELETE CASCADE;

ALTER TABLE expense_approvals
    ADD COLUMN organization_id INT REFERENCES organizations(organization_id) ON DELETE CASCADE;

UPDATE expense_media m
   SET organization_id = e.organization_id
  FROM expenses e
 WHERE e.expense_id = m.expense_id;

UPDATE expense_approvals a
   SET organization_id = e.organization_id
  FROM expenses e
 WHERE e.expense_id = a.expense_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM expense_media WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'a receipt references a missing expense; cannot scope it';
    END IF;
    IF EXISTS (SELECT 1 FROM expense_approvals WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'an approval references a missing expense; cannot scope it';
    END IF;
END $$;

ALTER TABLE expense_media ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE expense_approvals ALTER COLUMN organization_id SET NOT NULL;

CREATE INDEX idx_expense_media_org ON expense_media(organization_id);
CREATE INDEX idx_expense_approvals_org ON expense_approvals(organization_id);
