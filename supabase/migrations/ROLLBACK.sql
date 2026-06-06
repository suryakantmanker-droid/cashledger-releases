-- =============================================================================
-- ROLLBACK — Undo all Phase 0 migrations
-- =============================================================================
-- Purpose : Complete rollback to pre-migration state.
-- Usage   : Run sections individually in reverse order, or run entire file.
--           Always run on a COPY of production first.
-- Warning : Section 004 rollback removes NOT NULL + DEFAULT constraints,
--           making business_id nullable again. This is safe (app still works).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 008 — Remove RLS policies
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- businesses
DROP POLICY IF EXISTS "businesses_select_members"  ON businesses;
DROP POLICY IF EXISTS "businesses_insert_owner"    ON businesses;
DROP POLICY IF EXISTS "businesses_update_owner"    ON businesses;
DROP POLICY IF EXISTS "businesses_delete_never"    ON businesses;
ALTER TABLE businesses DISABLE ROW LEVEL SECURITY;

-- business_members
DROP POLICY IF EXISTS "bm_select_own_business"  ON business_members;
DROP POLICY IF EXISTS "bm_insert_admin"          ON business_members;
DROP POLICY IF EXISTS "bm_update_admin"          ON business_members;
DROP POLICY IF EXISTS "bm_delete_owner"          ON business_members;
ALTER TABLE business_members DISABLE ROW LEVEL SECURITY;

-- expense_categories
DROP POLICY IF EXISTS "ec_select_members"  ON expense_categories;
DROP POLICY IF EXISTS "ec_insert_admin"    ON expense_categories;
DROP POLICY IF EXISTS "ec_update_admin"    ON expense_categories;
DROP POLICY IF EXISTS "ec_delete_owner"    ON expense_categories;
ALTER TABLE expense_categories DISABLE ROW LEVEL SECURITY;

-- salary_records
DROP POLICY IF EXISTS "sr_select_manager_or_own"  ON salary_records;
DROP POLICY IF EXISTS "sr_insert_manager"          ON salary_records;
DROP POLICY IF EXISTS "sr_update_manager"          ON salary_records;
DROP POLICY IF EXISTS "sr_delete_owner"            ON salary_records;
ALTER TABLE salary_records DISABLE ROW LEVEL SECURITY;

-- attendance
DROP POLICY IF EXISTS "att_select_manager_or_own" ON attendance;
DROP POLICY IF EXISTS "att_insert_manager"         ON attendance;
DROP POLICY IF EXISTS "att_update_manager"         ON attendance;
DROP POLICY IF EXISTS "att_delete_manager"         ON attendance;
ALTER TABLE attendance DISABLE ROW LEVEL SECURITY;

-- existing tables (policies only — RLS was never enabled in Phase 0)
DROP POLICY IF EXISTS "emp_select_members"          ON employees;
DROP POLICY IF EXISTS "emp_insert_admin"             ON employees;
DROP POLICY IF EXISTS "emp_update_admin_or_self"    ON employees;
DROP POLICY IF EXISTS "emp_delete_owner"             ON employees;
DROP POLICY IF EXISTS "exp_select_accountant_or_own" ON expenses;
DROP POLICY IF EXISTS "exp_insert_employee"           ON expenses;
DROP POLICY IF EXISTS "exp_update_accountant_or_own" ON expenses;
DROP POLICY IF EXISTS "exp_delete_own_draft_or_admin" ON expenses;
DROP POLICY IF EXISTS "funds_select_manager_or_own"  ON funds;
DROP POLICY IF EXISTS "funds_insert_manager"          ON funds;
DROP POLICY IF EXISTS "funds_update_manager"          ON funds;
DROP POLICY IF EXISTS "funds_delete_never"            ON funds;
DROP POLICY IF EXISTS "ledger_select_accountant_or_own" ON ledger;
DROP POLICY IF EXISTS "ledger_insert_never_from_app"    ON ledger;
DROP POLICY IF EXISTS "ledger_update_never"             ON ledger;
DROP POLICY IF EXISTS "ledger_delete_never"             ON ledger;
DROP POLICY IF EXISTS "users_select_self_or_admin"  ON users;
DROP POLICY IF EXISTS "users_insert_self"            ON users;
DROP POLICY IF EXISTS "users_update_self_safe"       ON users;
DROP POLICY IF EXISTS "users_delete_never"           ON users;

RAISE NOTICE '[ROLLBACK 008] All RLS policies removed';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 007 — Drop helper functions
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
DROP FUNCTION IF EXISTS fn_get_dashboard_stats(UUID);
DROP FUNCTION IF EXISTS fn_next_fund_code(UUID);
DROP FUNCTION IF EXISTS fn_next_expense_code(UUID);
DROP FUNCTION IF EXISTS fn_has_role_or_above(UUID, TEXT);
DROP FUNCTION IF EXISTS fn_role_level(TEXT);
DROP FUNCTION IF EXISTS fn_my_role_in(UUID);
DROP FUNCTION IF EXISTS fn_is_member_of(UUID);
DROP FUNCTION IF EXISTS fn_current_user_uid();
RAISE NOTICE '[ROLLBACK 007] Helper functions dropped';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 006 — Drop triggers
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
DROP TRIGGER IF EXISTS trg_businesses_updated_at     ON businesses;
DROP TRIGGER IF EXISTS trg_business_members_updated_at ON business_members;
DROP TRIGGER IF EXISTS trg_employees_updated_at      ON employees;
DROP TRIGGER IF EXISTS trg_expenses_updated_at       ON expenses;
DROP TRIGGER IF EXISTS trg_salary_records_updated_at ON salary_records;
DROP TRIGGER IF EXISTS trg_attendance_updated_at     ON attendance;
DROP TRIGGER IF EXISTS trg_users_updated_at          ON users;
DROP FUNCTION IF EXISTS fn_set_updated_at();
RAISE NOTICE '[ROLLBACK 006] Triggers and trigger function dropped';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 005 — Drop indexes
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
DROP INDEX IF EXISTS idx_businesses_owner_uid;
DROP INDEX IF EXISTS idx_businesses_is_active;
DROP INDEX IF EXISTS idx_business_members_user_uid;
DROP INDEX IF EXISTS idx_business_members_business_id;
DROP INDEX IF EXISTS idx_business_members_business_user;
DROP INDEX IF EXISTS idx_employees_business_active;
DROP INDEX IF EXISTS idx_employees_business_user_uid;
DROP INDEX IF EXISTS idx_employees_business_department;
DROP INDEX IF EXISTS idx_expenses_business_date;
DROP INDEX IF EXISTS idx_expenses_business_status;
DROP INDEX IF EXISTS idx_expenses_business_submitted_by;
DROP INDEX IF EXISTS idx_expenses_business_category;
DROP INDEX IF EXISTS idx_expenses_business_date_status;
DROP INDEX IF EXISTS idx_funds_business_date;
DROP INDEX IF EXISTS idx_funds_business_given_to;
DROP INDEX IF EXISTS idx_ledger_business_date;
DROP INDEX IF EXISTS idx_ledger_business_employee;
DROP INDEX IF EXISTS idx_ledger_reference;
DROP INDEX IF EXISTS idx_expense_categories_business;
DROP INDEX IF EXISTS idx_salary_records_business_year_month;
DROP INDEX IF EXISTS idx_salary_records_business_employee;
DROP INDEX IF EXISTS idx_attendance_business_date;
DROP INDEX IF EXISTS idx_attendance_business_employee_date;
RAISE NOTICE '[ROLLBACK 005] All migration indexes dropped';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 004 — Remove NOT NULL constraints, DEFAULT, and backfilled data
-- NOTE: This does NOT delete the backfilled data — it only makes columns
--       nullable again. The default business and backfilled rows remain.
--       Remove them manually if needed.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
ALTER TABLE employees ALTER COLUMN business_id DROP NOT NULL;
ALTER TABLE employees ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE expenses  ALTER COLUMN business_id DROP NOT NULL;
ALTER TABLE expenses  ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE funds     ALTER COLUMN business_id DROP NOT NULL;
ALTER TABLE funds     ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE ledger    ALTER COLUMN business_id DROP NOT NULL;
ALTER TABLE ledger    ALTER COLUMN business_id DROP DEFAULT;
RAISE NOTICE '[ROLLBACK 004] NOT NULL + DEFAULT removed from existing tables';
-- To also delete backfill data (destructive — only if you want a full undo):
-- DELETE FROM business_members WHERE business_id = '11111111-1111-1111-1111-111111111111';
-- DELETE FROM expense_categories WHERE business_id = '11111111-1111-1111-1111-111111111111';
-- DELETE FROM businesses WHERE id = '11111111-1111-1111-1111-111111111111';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 003 — Drop columns added to existing tables
-- WARNING: This DESTROYS all data in those columns. Verify backfill not needed.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
ALTER TABLE users     DROP COLUMN IF EXISTS business_id;
ALTER TABLE employees DROP COLUMN IF EXISTS business_id;
ALTER TABLE employees DROP COLUMN IF EXISTS user_uid;
ALTER TABLE employees DROP COLUMN IF EXISTS designation;
ALTER TABLE employees DROP COLUMN IF EXISTS salary;
ALTER TABLE expenses  DROP COLUMN IF EXISTS business_id;
ALTER TABLE expenses  DROP COLUMN IF EXISTS category_id;
ALTER TABLE expenses  DROP COLUMN IF EXISTS submitted_at;
ALTER TABLE expenses  DROP COLUMN IF EXISTS is_recurring;
ALTER TABLE expenses  DROP COLUMN IF EXISTS recurrence_pattern;
ALTER TABLE expenses  DROP COLUMN IF EXISTS recurrence_end_date;
ALTER TABLE expenses  DROP COLUMN IF EXISTS edit_history;
ALTER TABLE expenses  DROP COLUMN IF EXISTS comments;
ALTER TABLE funds     DROP COLUMN IF EXISTS business_id;
ALTER TABLE ledger    DROP COLUMN IF EXISTS business_id;
RAISE NOTICE '[ROLLBACK 003] All new columns removed from existing tables';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 002 — Drop new tables (CASCADE removes FKs and policies)
-- WARNING: Destroys all data in these tables.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
DROP TABLE IF EXISTS attendance         CASCADE;
DROP TABLE IF EXISTS salary_records     CASCADE;
DROP TABLE IF EXISTS expense_categories CASCADE;
DROP TABLE IF EXISTS business_members   CASCADE;
DROP TABLE IF EXISTS businesses         CASCADE;
RAISE NOTICE '[ROLLBACK 002] New tables dropped';
COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK 001 — Drop role enum
-- Only safe if no column references this type.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;
DROP TYPE IF EXISTS user_role CASCADE;
RAISE NOTICE '[ROLLBACK 001] user_role enum dropped';
COMMIT;
