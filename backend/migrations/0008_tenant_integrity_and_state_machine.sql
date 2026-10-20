-- =============================================================
-- 0008 — CROSS-TENANT INTEGRITY AND EXPENSE STATE MACHINE
-- =============================================================
-- The application layer already scopes every query to one
-- organization, but the database was not enforcing it. A write that
-- reached past the service layer — a future endpoint, a script, a
-- mistake — could point a reimbursement at another organization's
-- expense, or give a membership a role from a different
-- organization. This migration makes those combinations impossible
-- rather than merely unlikely.
--
-- The mechanism is a composite foreign key: each table gets a unique
-- key on (id, organization_id), and a child table that carries an
-- organization_id can then only reference a parent row of the *same*
-- organization.

-- -- 1. Composite unique keys -------------------------------------------

ALTER TABLE memberships
    ADD CONSTRAINT uq_memberships_org_employee UNIQUE (membership_id, organization_id);

ALTER TABLE roles
    ADD CONSTRAINT uq_roles_org_id UNIQUE (role_id, organization_id);

ALTER TABLE budgets
    ADD CONSTRAINT uq_budgets_org_id UNIQUE (budget_id, organization_id);

ALTER TABLE expenses
    ADD CONSTRAINT uq_expenses_org_id UNIQUE (expense_id, organization_id);

ALTER TABLE expense_types
    ADD CONSTRAINT uq_expense_types_org_id UNIQUE (expense_type_id, organization_id);

ALTER TABLE reimbursements
    ADD CONSTRAINT uq_reimbursements_org_id UNIQUE (reimbursement_id, organization_id);

-- -- 2. A project belongs to an organization ----------------------------
--
-- projects referenced its organization only through its budget, so no
-- constraint could name the organization directly. The column is
-- added here and kept in step with the budget by the trigger below.

ALTER TABLE projects ADD COLUMN organization_id INT;

UPDATE projects p
   SET organization_id = b.organization_id
  FROM budgets b
 WHERE b.budget_id = p.budget_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM projects WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'a project references a missing budget; cannot scope it';
    END IF;
END $$;

ALTER TABLE projects ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE projects
    ADD CONSTRAINT fk_projects_budget_org
    FOREIGN KEY (budget_id, organization_id)
    REFERENCES budgets (budget_id, organization_id);

ALTER TABLE projects
    ADD CONSTRAINT uq_projects_org_id UNIQUE (project_id, organization_id);

CREATE OR REPLACE FUNCTION sync_project_organization() RETURNS TRIGGER AS $$
DECLARE
    budget_org INT;
BEGIN
    SELECT organization_id INTO budget_org FROM budgets WHERE budget_id = NEW.budget_id;
    IF budget_org IS NULL THEN
        RAISE EXCEPTION 'project references a budget that does not exist'
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF NEW.organization_id IS DISTINCT FROM budget_org THEN
        RAISE EXCEPTION 'project organization must match its budget organization'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_project_organization
    BEFORE INSERT OR UPDATE OF budget_id, organization_id ON projects
    FOR EACH ROW EXECUTE FUNCTION sync_project_organization();

-- -- 3. Membership roles -------------------------------------------------

ALTER TABLE membership_roles ADD COLUMN organization_id INT;

UPDATE membership_roles mr
   SET organization_id = m.organization_id
  FROM memberships m
 WHERE m.membership_id = mr.membership_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM membership_roles WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'a membership role references a missing membership';
    END IF;
END $$;

ALTER TABLE membership_roles ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE membership_roles
    ADD CONSTRAINT fk_membership_roles_membership_org
    FOREIGN KEY (membership_id, organization_id)
    REFERENCES memberships (membership_id, organization_id);

ALTER TABLE membership_roles
    ADD CONSTRAINT fk_membership_roles_role_org
    FOREIGN KEY (role_id, organization_id)
    REFERENCES roles (role_id, organization_id);

-- -- 4. Role permissions -------------------------------------------------

ALTER TABLE role_permissions ADD COLUMN organization_id INT;

UPDATE role_permissions rp
   SET organization_id = r.organization_id
  FROM roles r
 WHERE r.role_id = rp.role_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM role_permissions WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'a role permission references a missing role';
    END IF;
END $$;

ALTER TABLE role_permissions ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE role_permissions
    ADD CONSTRAINT fk_role_permissions_role_org
    FOREIGN KEY (role_id, organization_id)
    REFERENCES roles (role_id, organization_id);

-- -- 5. Direct user permissions ------------------------------------------

ALTER TABLE user_permissions ADD COLUMN organization_id INT;

UPDATE user_permissions up
   SET organization_id = m.organization_id
  FROM memberships m
 WHERE m.employee_id = up.employee_id;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM user_permissions up
         WHERE up.organization_id IS NULL
           AND EXISTS (SELECT 1 FROM memberships m WHERE m.employee_id = up.employee_id)
    ) THEN
        RAISE EXCEPTION 'a user permission spans more than one organization';
    END IF;
END $$;

-- A grant for someone with no membership has no organization to belong
-- to; those rows keep a NULL organization and are simply not granted.
ALTER TABLE user_permissions
    ADD CONSTRAINT fk_user_permissions_org
    FOREIGN KEY (organization_id) REFERENCES organizations (organization_id);

-- -- 6. Project members ---------------------------------------------------

ALTER TABLE project_members ADD COLUMN organization_id INT;

UPDATE project_members pm
   SET organization_id = p.organization_id
  FROM projects p
 WHERE p.project_id = pm.project_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM project_members WHERE organization_id IS NULL) THEN
        RAISE EXCEPTION 'a project member references a missing project';
    END IF;
END $$;

ALTER TABLE project_members ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE project_members
    ADD CONSTRAINT fk_project_members_project_org
    FOREIGN KEY (project_id, organization_id)
    REFERENCES projects (project_id, organization_id);

ALTER TABLE project_members
    ADD CONSTRAINT fk_project_members_role_org
    FOREIGN KEY (role_id, organization_id)
    REFERENCES roles (role_id, organization_id);

-- -- 7. A reimbursement may only reference an expense of its own org -----

ALTER TABLE reimbursements
    ADD CONSTRAINT fk_reimbursements_expense_org
    FOREIGN KEY (expense_id, organization_id)
    REFERENCES expenses (expense_id, organization_id);

-- -- 8. The expense state machine is enforced by the database -----------
--
-- The service layer already refuses invalid transitions; this makes the
-- rule hold for every writer, including a direct SQL session.

CREATE OR REPLACE FUNCTION validate_expense_status_transition() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
        (OLD.status = 'pending' AND NEW.status IN ('info_requested', 'approved', 'rejected')) OR
        (OLD.status = 'info_requested' AND NEW.status IN ('pending', 'approved', 'rejected')) OR
        (OLD.status = 'approved' AND NEW.status = 'reimbursed')
    ) THEN
        RAISE EXCEPTION 'invalid expense status transition: % -> %', OLD.status, NEW.status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_expense_status_transition
    BEFORE UPDATE OF status ON expenses
    FOR EACH ROW EXECUTE FUNCTION validate_expense_status_transition();
