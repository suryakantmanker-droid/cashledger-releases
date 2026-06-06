-- =============================================================================
-- VERIFY — Post-migration verification queries
-- =============================================================================
-- Purpose : Run these queries after each migration to confirm success.
--           All queries are read-only (SELECT only). Safe to run anytime.
-- Usage   : Run in Supabase SQL Editor or psql.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- V1 — Verify new tables exist
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns c
   WHERE c.table_schema = t.table_schema
     AND c.table_name   = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_name IN (
    'businesses','business_members','expense_categories',
    'salary_records','attendance'
  )
ORDER BY table_name;
-- Expected: 5 rows

-- ─────────────────────────────────────────────────────────────────────────────
-- V2 — Verify business_id columns exist on existing tables
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  table_name,
  column_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name  = 'business_id'
  AND table_name  IN ('users','employees','expenses','funds','ledger')
ORDER BY table_name;
-- Expected: 5 rows
-- Expected is_nullable: YES for users, NO for employees/expenses/funds/ledger
-- Expected column_default: NOT NULL for employees/expenses/funds/ledger
--   (should show '11111111-1111-1111-1111-111111111111'::uuid)

-- ─────────────────────────────────────────────────────────────────────────────
-- V3 — Verify default business was created
-- ─────────────────────────────────────────────────────────────────────────────
SELECT id, name, slug, owner_uid, plan, is_active, created_at
FROM businesses
WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;
-- Expected: exactly 1 row

-- ─────────────────────────────────────────────────────────────────────────────
-- V4 — Verify all existing users have a business_members row
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  u.uid,
  u.role AS old_role,
  bm.role AS new_role,
  bm.is_active
FROM users u
LEFT JOIN business_members bm
  ON bm.user_uid    = u.uid
  AND bm.business_id = '11111111-1111-1111-1111-111111111111'::UUID
ORDER BY u.created_at;
-- Expected: every user has a matching bm row (no NULLs in new_role column)

-- ─────────────────────────────────────────────────────────────────────────────
-- V5 — Verify zero NULL business_id rows in existing tables
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 'employees' AS tbl, COUNT(*) AS null_business_id FROM employees WHERE business_id IS NULL
UNION ALL
SELECT 'expenses',         COUNT(*) FROM expenses  WHERE business_id IS NULL
UNION ALL
SELECT 'funds',            COUNT(*) FROM funds     WHERE business_id IS NULL
UNION ALL
SELECT 'ledger',           COUNT(*) FROM ledger    WHERE business_id IS NULL;
-- Expected: all counts = 0

-- ─────────────────────────────────────────────────────────────────────────────
-- V6 — Verify row counts match (nothing lost during backfill)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'employees' AS tbl,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE business_id = '11111111-1111-1111-1111-111111111111') AS in_default
FROM employees
UNION ALL
SELECT 'expenses', COUNT(*),
  COUNT(*) FILTER (WHERE business_id = '11111111-1111-1111-1111-111111111111')
FROM expenses
UNION ALL
SELECT 'funds', COUNT(*),
  COUNT(*) FILTER (WHERE business_id = '11111111-1111-1111-1111-111111111111')
FROM funds
UNION ALL
SELECT 'ledger', COUNT(*),
  COUNT(*) FILTER (WHERE business_id = '11111111-1111-1111-1111-111111111111')
FROM ledger;
-- Expected: total = in_default for all rows (100% assigned)

-- ─────────────────────────────────────────────────────────────────────────────
-- V7 — Verify all indexes exist
-- ─────────────────────────────────────────────────────────────────────────────
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
-- Expected: 23+ indexes

-- ─────────────────────────────────────────────────────────────────────────────
-- V8 — Verify triggers exist
-- ─────────────────────────────────────────────────────────────────────────────
SELECT trigger_name, event_object_table, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name LIKE 'trg_%'
ORDER BY event_object_table;
-- Expected: 6-7 triggers (businesses, business_members, employees, expenses,
--           salary_records, attendance, optionally users)

-- ─────────────────────────────────────────────────────────────────────────────
-- V9 — Verify helper functions exist
-- ─────────────────────────────────────────────────────────────────────────────
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE 'fn_%'
ORDER BY routine_name;
-- Expected: fn_current_user_uid, fn_get_dashboard_stats, fn_has_role_or_above,
--           fn_is_member_of, fn_my_role_in, fn_next_expense_code,
--           fn_next_fund_code, fn_role_level, fn_set_updated_at

-- ─────────────────────────────────────────────────────────────────────────────
-- V10 — Verify RLS status on all tables
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  relname AS table_name,
  relrowsecurity AS rls_enabled,
  relforcerowsecurity AS rls_forced
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relkind = 'r'
  AND relname IN (
    'businesses','business_members','expense_categories',
    'salary_records','attendance',
    'employees','expenses','funds','ledger','users'
  )
ORDER BY relname;
-- Expected after Phase 0:
--   businesses, business_members, expense_categories,
--   salary_records, attendance → rls_enabled = true
--   employees, expenses, funds, ledger, users → rls_enabled = false

-- ─────────────────────────────────────────────────────────────────────────────
-- V11 — Verify expense categories seeded
-- ─────────────────────────────────────────────────────────────────────────────
SELECT name, sort_order
FROM expense_categories
WHERE business_id = '11111111-1111-1111-1111-111111111111'::UUID
ORDER BY sort_order;
-- Expected: 10 rows (Travel, Food & Beverage, … Miscellaneous)

-- ─────────────────────────────────────────────────────────────────────────────
-- V12 — Test helper functions (will return false/viewer until JWT configured)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  fn_current_user_uid()                                          AS current_uid,
  fn_is_member_of('11111111-1111-1111-1111-111111111111'::UUID)  AS is_member,
  fn_my_role_in('11111111-1111-1111-1111-111111111111'::UUID)    AS my_role,
  fn_role_level('admin')                                         AS admin_level,
  fn_role_level('employee')                                      AS employee_level,
  fn_role_level('owner')                                         AS owner_level;
-- Expected now: NULL, false, NULL, 40, 10, 50
-- Expected after Firebase JWT: uid filled in, membership checked correctly

-- ─────────────────────────────────────────────────────────────────────────────
-- V13 — Test dashboard stats function
-- ─────────────────────────────────────────────────────────────────────────────
SELECT fn_get_dashboard_stats('11111111-1111-1111-1111-111111111111'::UUID);
-- Expected: JSON object with total_employees, total_expenses, etc.

-- ─────────────────────────────────────────────────────────────────────────────
-- V14 — Verify new columns on expenses table
-- ─────────────────────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'expenses'
  AND column_name IN (
    'business_id','category_id','submitted_at',
    'is_recurring','recurrence_pattern','recurrence_end_date',
    'edit_history','comments'
  )
ORDER BY column_name;
-- Expected: 8 rows

-- ─────────────────────────────────────────────────────────────────────────────
-- V15 — Verify new columns on employees table
-- ─────────────────────────────────────────────────────────────────────────────
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'employees'
  AND column_name IN ('business_id','user_uid','designation','salary')
ORDER BY column_name;
-- Expected: 4 rows
