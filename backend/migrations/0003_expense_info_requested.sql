-- =============================================================
-- 0003 — EXPENSE INFO-REQUESTED STATUS (additive; never edit 0001, §18)
-- =============================================================
-- Managers previously could only approve or reject; borderline expense
-- submissions had no honest state. This adds:
--   pending -> info_requested  (manager asks the employee for details)
--   info_requested -> pending  (employee resubmits after answering)
--   info_requested -> approved | rejected (decision after an answer)
--
-- The manager's question is preserved in the new ``info_message``
-- column so the employee sees *what* is being asked — it is NOT
-- ``rejection_reason``, which keeps its approved/rejected semantics.

ALTER TABLE expenses DROP CONSTRAINT expenses_status_check;

ALTER TABLE expenses ADD CONSTRAINT expenses_status_check
    CHECK (status IN (
        'pending', 'info_requested', 'approved', 'rejected', 'reimbursed'
    ));

ALTER TABLE expenses
    ADD COLUMN info_message    VARCHAR(500),
    ADD COLUMN info_requested_at TIMESTAMP;
