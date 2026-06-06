-- =============================================================================
-- MIGRATION 005 — Create performance indexes
-- =============================================================================
-- Purpose : Add composite indexes on every table so that business-scoped
--           queries use index scans instead of sequential scans.
--           Every hot query path in the Flutter app is covered here.
-- Safe    : IF NOT EXISTS on every CREATE INDEX — fully idempotent.
-- Impact  : Index creation may take a few seconds on large tables.
--           Uses CONCURRENTLY where possible for zero-downtime creation.
-- Note    : CONCURRENTLY cannot run inside a transaction block.
--           Run each statement individually if table has live traffic.
-- Rollback: See ROLLBACK.sql → section 005
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- businesses
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_businesses_owner_uid
  ON businesses (owner_uid);

CREATE INDEX IF NOT EXISTS idx_businesses_is_active
  ON businesses (is_active)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- business_members
-- ─────────────────────────────────────────────────────────────────────────────

-- Most critical index: "give me all businesses for this user"
CREATE INDEX IF NOT EXISTS idx_business_members_user_uid
  ON business_members (user_uid)
  WHERE is_active = true;

-- "give me all members of this business"
CREATE INDEX IF NOT EXISTS idx_business_members_business_id
  ON business_members (business_id)
  WHERE is_active = true;

-- Role lookup within a business (used by RLS helper functions)
CREATE INDEX IF NOT EXISTS idx_business_members_business_user
  ON business_members (business_id, user_uid)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- employees
-- ─────────────────────────────────────────────────────────────────────────────

-- Primary query: all active employees in a business
CREATE INDEX IF NOT EXISTS idx_employees_business_active
  ON employees (business_id, is_active);

-- Link Firebase user → their employee record within a business
CREATE INDEX IF NOT EXISTS idx_employees_business_user_id
  ON employees (business_id, user_id);

-- Department filtering
CREATE INDEX IF NOT EXISTS idx_employees_business_department
  ON employees (business_id, department);

-- ─────────────────────────────────────────────────────────────────────────────
-- expenses
-- ─────────────────────────────────────────────────────────────────────────────

-- Most common query: all expenses for a business, newest first
CREATE INDEX IF NOT EXISTS idx_expenses_business_date
  ON expenses (business_id, expense_date DESC);

-- Approval queue: pending expenses for a business
CREATE INDEX IF NOT EXISTS idx_expenses_business_status
  ON expenses (business_id, status)
  WHERE status IN ('pending','draft');

-- Employee sees only their own expenses
CREATE INDEX IF NOT EXISTS idx_expenses_business_submitted_by
  ON expenses (business_id, submitted_by);

-- Category analytics
CREATE INDEX IF NOT EXISTS idx_expenses_business_category
  ON expenses (business_id, category);

-- Dashboard: monthly totals (date range scans)
CREATE INDEX IF NOT EXISTS idx_expenses_business_date_status
  ON expenses (business_id, expense_date DESC, status);

-- ─────────────────────────────────────────────────────────────────────────────
-- funds
-- ─────────────────────────────────────────────────────────────────────────────

-- All fund transfers for a business
CREATE INDEX IF NOT EXISTS idx_funds_business_date
  ON funds (business_id, transfer_date DESC);

-- Employee sees transfers sent to them
CREATE INDEX IF NOT EXISTS idx_funds_business_given_to
  ON funds (business_id, given_to);

-- ─────────────────────────────────────────────────────────────────────────────
-- ledger
-- ─────────────────────────────────────────────────────────────────────────────

-- Full ledger for a business
CREATE INDEX IF NOT EXISTS idx_ledger_business_date
  ON ledger (business_id, date DESC);

-- Employee's own ledger entries
CREATE INDEX IF NOT EXISTS idx_ledger_business_employee
  ON ledger (business_id, employee_id, date DESC);

-- Reference lookup (fund_transfer or expense link)
CREATE INDEX IF NOT EXISTS idx_ledger_reference
  ON ledger (business_id, reference_id, reference_type);

-- ─────────────────────────────────────────────────────────────────────────────
-- expense_categories
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_expense_categories_business
  ON expense_categories (business_id, sort_order)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────────────────
-- salary_records
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_salary_records_business_year_month
  ON salary_records (business_id, year DESC, month DESC);

CREATE INDEX IF NOT EXISTS idx_salary_records_business_employee
  ON salary_records (business_id, employee_id, year DESC, month DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- attendance
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_attendance_business_date
  ON attendance (business_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_attendance_business_employee_date
  ON attendance (business_id, employee_id, date DESC);
