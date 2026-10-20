-- =============================================================
-- 0007 — PAYMENT RECEIPTS (additive; never edit 0001, §18)
-- =============================================================
-- The "mark as paid" flow collects a payment receipt image, but there
-- was nowhere to put it: the file was read into memory and then
-- discarded, while the UI reported that it had been attached.
--
-- The reimbursement now carries the URL of its payment receipt, the
-- same way an expense carries its receipt URLs.

ALTER TABLE reimbursements ADD COLUMN payment_receipt_url TEXT;
