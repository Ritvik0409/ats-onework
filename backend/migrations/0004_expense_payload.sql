-- =============================================================
-- 0004 — EXPENSE PAYLOAD AND RECEIPT SAFETY (additive; never edit 0001, §18)
-- =============================================================
-- Expenses carry what the submitter actually typed, and the columns the
-- API already accepted are wide enough to hold it:
--
--   * description  — the text an employee types was accepted by the client
--                    and then dropped: neither the request schema nor the
--                    table had a place for it.
--   * rejection_reason — the API accepted 2000-character rejection
--                    comments while the column held 255, so a long
--                    rejection died with an unmapped database error
--                    (HTTP 500) instead of a validation error.
--   * info_response — the employee's answer to an information request.

ALTER TABLE expenses ADD COLUMN description TEXT;

ALTER TABLE expenses ALTER COLUMN rejection_reason TYPE VARCHAR(2000);

ALTER TABLE expenses ADD COLUMN info_response TEXT;

-- The information-request round trip is part of the approval history.
ALTER TABLE expense_approvals DROP CONSTRAINT expense_approvals_action_check;
ALTER TABLE expense_approvals ADD CONSTRAINT expense_approvals_action_check
    CHECK (action IN ('approved', 'rejected', 'info_requested', 'info_answered'));
