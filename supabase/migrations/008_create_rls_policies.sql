-- =============================================================================
-- MIGRATION 008 — Create RLS policies (Phase 0: prepared but NOT activated)
-- =============================================================================
-- Purpose : Define all Row Level Security policies.
--
-- ⚠️  CRITICAL — READ BEFORE RUNNING
-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 0 DOES NOT enable RLS on existing tables (employees, expenses, funds,
-- ledger, users). Enabling RLS on those tables right now would BREAK the live
-- Flutter app because auth.uid() is NULL when using the Supabase anon key
-- without a proper Supabase Auth / Firebase JWT session.
--
-- DEPLOYMENT ORDER:
--   Phase 0  → Run this file. Policies are CREATED but RLS is OFF on existing tables.
--               New tables (businesses, business_members) get RLS ON.
--   Phase 1  → Flutter app updated to sign into Supabase via Firebase JWT.
--               Then run enable_rls_existing_tables.sql (provided at end).
--
-- PREREQUISITE for full RLS activation:
--   Either call supabase.auth.signInWithIdToken(idToken: firebaseIdToken) in
--   Flutter, or configure Supabase to trust Firebase JWTs in the Dashboard.
--   Until then auth.uid() is NULL → all is_member_of() checks return false.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Safe    : Policies are dropped + re-created (idempotent).
-- Rollback: See ROLLBACK.sql → section 008
-- Depends : 007_create_helper_functions.sql must have run first
-- =============================================================================

BEGIN;

-- =============================================================================
-- NEW TABLES — Enable RLS immediately (safe: Flutter has no code for these yet)
-- =============================================================================

ALTER TABLE businesses       ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance       ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- EXISTING TABLES — Policies created but RLS NOT enabled yet.
-- Enable only after Firebase JWT is configured (see bottom of this file).
-- =============================================================================
-- ALTER TABLE employees ENABLE ROW LEVEL SECURITY;  -- ← Phase 1
-- ALTER TABLE expenses  ENABLE ROW LEVEL SECURITY;  -- ← Phase 1
-- ALTER TABLE funds     ENABLE ROW LEVEL SECURITY;  -- ← Phase 1
-- ALTER TABLE ledger    ENABLE ROW LEVEL SECURITY;  -- ← Phase 1
-- ALTER TABLE users     ENABLE ROW LEVEL SECURITY;  -- ← Phase 1


-- =============================================================================
-- POLICY: businesses
-- =============================================================================

DROP POLICY IF EXISTS "businesses_select_members"  ON businesses;
DROP POLICY IF EXISTS "businesses_insert_owner"    ON businesses;
DROP POLICY IF EXISTS "businesses_update_owner"    ON businesses;
DROP POLICY IF EXISTS "businesses_delete_never"    ON businesses;

-- Any member of a business can read its row
CREATE POLICY "businesses_select_members" ON businesses
  FOR SELECT
  USING (fn_is_member_of(id));

-- Any authenticated user can create a business (they become the owner)
CREATE POLICY "businesses_insert_owner" ON businesses
  FOR INSERT
  WITH CHECK (
    fn_current_user_uid() IS NOT NULL
    AND owner_uid = fn_current_user_uid()
  );

-- Only the owner can update business settings
CREATE POLICY "businesses_update_owner" ON businesses
  FOR UPDATE
  USING (owner_uid = fn_current_user_uid());

-- Businesses are never deleted (soft-delete via is_active flag)
CREATE POLICY "businesses_delete_never" ON businesses
  FOR DELETE
  USING (false);


-- =============================================================================
-- POLICY: business_members
-- =============================================================================

DROP POLICY IF EXISTS "bm_select_own_business"  ON business_members;
DROP POLICY IF EXISTS "bm_insert_admin"          ON business_members;
DROP POLICY IF EXISTS "bm_update_admin"          ON business_members;
DROP POLICY IF EXISTS "bm_delete_owner"          ON business_members;

-- Members can read the member list of their own business
CREATE POLICY "bm_select_own_business" ON business_members
  FOR SELECT
  USING (fn_is_member_of(business_id));

-- Admin and above can invite/add new members
CREATE POLICY "bm_insert_admin" ON business_members
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'admin'));

-- Admin and above can update member roles / status
-- Owner cannot be demoted except by themselves
CREATE POLICY "bm_update_admin" ON business_members
  FOR UPDATE
  USING (
    fn_has_role_or_above(business_id, 'admin')
    -- Admin cannot modify the owner row unless they ARE the owner
    AND (
      fn_my_role_in(business_id) = 'owner'
      OR role != 'owner'
    )
  );

-- Only owner can remove members; owners cannot be removed
CREATE POLICY "bm_delete_owner" ON business_members
  FOR DELETE
  USING (
    fn_my_role_in(business_id) = 'owner'
    AND role != 'owner'
  );


-- =============================================================================
-- POLICY: expense_categories
-- =============================================================================

DROP POLICY IF EXISTS "ec_select_members"  ON expense_categories;
DROP POLICY IF EXISTS "ec_insert_admin"    ON expense_categories;
DROP POLICY IF EXISTS "ec_update_admin"    ON expense_categories;
DROP POLICY IF EXISTS "ec_delete_owner"    ON expense_categories;

CREATE POLICY "ec_select_members" ON expense_categories
  FOR SELECT
  USING (fn_is_member_of(business_id));

CREATE POLICY "ec_insert_admin" ON expense_categories
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'admin'));

CREATE POLICY "ec_update_admin" ON expense_categories
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'admin'));

CREATE POLICY "ec_delete_owner" ON expense_categories
  FOR DELETE
  USING (fn_has_role_or_above(business_id, 'owner'));


-- =============================================================================
-- POLICY: salary_records
-- =============================================================================

DROP POLICY IF EXISTS "sr_select_manager_or_own"  ON salary_records;
DROP POLICY IF EXISTS "sr_insert_manager"          ON salary_records;
DROP POLICY IF EXISTS "sr_update_manager"          ON salary_records;
DROP POLICY IF EXISTS "sr_delete_owner"            ON salary_records;

-- Managers+ see all salary records; employees see only their own.
-- salary_records.employee_id references employees.id which IS the Firebase UID.
CREATE POLICY "sr_select_manager_or_own" ON salary_records
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'manager')
      OR employee_id = fn_current_user_uid()   -- employees.id = Firebase UID
    )
  );

CREATE POLICY "sr_insert_manager" ON salary_records
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'manager'));

CREATE POLICY "sr_update_manager" ON salary_records
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'manager'));

CREATE POLICY "sr_delete_owner" ON salary_records
  FOR DELETE
  USING (fn_has_role_or_above(business_id, 'owner'));


-- =============================================================================
-- POLICY: attendance
-- =============================================================================

DROP POLICY IF EXISTS "att_select_manager_or_own" ON attendance;
DROP POLICY IF EXISTS "att_insert_manager"         ON attendance;
DROP POLICY IF EXISTS "att_update_manager"         ON attendance;
DROP POLICY IF EXISTS "att_delete_manager"         ON attendance;

CREATE POLICY "att_select_manager_or_own" ON attendance
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'manager')
      OR employee_id = fn_current_user_uid()   -- employees.id = Firebase UID
    )
  );

CREATE POLICY "att_insert_manager" ON attendance
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'manager'));

CREATE POLICY "att_update_manager" ON attendance
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'manager'));

CREATE POLICY "att_delete_manager" ON attendance
  FOR DELETE
  USING (fn_has_role_or_above(business_id, 'manager'));


-- =============================================================================
-- POLICY: employees  (created but RLS NOT yet enabled — Phase 1)
-- =============================================================================

DROP POLICY IF EXISTS "emp_select_members"         ON employees;
DROP POLICY IF EXISTS "emp_insert_admin"            ON employees;
DROP POLICY IF EXISTS "emp_update_admin_or_self"   ON employees;
DROP POLICY IF EXISTS "emp_delete_owner"            ON employees;

-- All business members can read the employee directory
CREATE POLICY "emp_select_members" ON employees
  FOR SELECT
  USING (fn_is_member_of(business_id));

-- Admin and above can add employees
CREATE POLICY "emp_insert_admin" ON employees
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'admin'));

-- Admin+ can update any employee; employee can update their own safe fields.
-- NOTE: employees.id IS the Firebase Auth UID (set in original schema 001).
CREATE POLICY "emp_update_admin_or_self" ON employees
  FOR UPDATE
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'admin')
      OR id = fn_current_user_uid()    -- id column = Firebase UID (PK)
    )
  );

-- Only owner can deactivate / remove employees
CREATE POLICY "emp_delete_owner" ON employees
  FOR DELETE
  USING (fn_has_role_or_above(business_id, 'owner'));


-- =============================================================================
-- POLICY: expenses  (created but RLS NOT yet enabled — Phase 1)
-- =============================================================================

DROP POLICY IF EXISTS "exp_select_accountant_or_own" ON expenses;
DROP POLICY IF EXISTS "exp_insert_employee"           ON expenses;
DROP POLICY IF EXISTS "exp_update_accountant_or_own" ON expenses;
DROP POLICY IF EXISTS "exp_delete_own_draft_or_admin" ON expenses;

-- Accountants+ see all expenses; employees see only their own
CREATE POLICY "exp_select_accountant_or_own" ON expenses
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'accountant')
      OR submitted_by = fn_current_user_uid()
    )
  );

-- Any active member (employee and above) can create expenses
CREATE POLICY "exp_insert_employee" ON expenses
  FOR INSERT
  WITH CHECK (
    fn_has_role_or_above(business_id, 'employee')
    AND submitted_by = fn_current_user_uid()
  );

-- Accountants+ can approve/reject; employees can edit their own draft/pending
CREATE POLICY "exp_update_accountant_or_own" ON expenses
  FOR UPDATE
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'accountant')
      OR (
        submitted_by = fn_current_user_uid()
        AND status IN ('draft', 'pending')
      )
    )
  );

-- Employees can delete their own drafts; admins can delete anything in draft
CREATE POLICY "exp_delete_own_draft_or_admin" ON expenses
  FOR DELETE
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'admin')
      OR (submitted_by = fn_current_user_uid() AND status = 'draft')
    )
  );


-- =============================================================================
-- POLICY: funds  (created but RLS NOT yet enabled — Phase 1)
-- =============================================================================

DROP POLICY IF EXISTS "funds_select_manager_or_own" ON funds;
DROP POLICY IF EXISTS "funds_insert_manager"         ON funds;
DROP POLICY IF EXISTS "funds_update_manager"         ON funds;
DROP POLICY IF EXISTS "funds_delete_never"           ON funds;

-- Managers+ see all transfers; employees see only transfers TO them
CREATE POLICY "funds_select_manager_or_own" ON funds
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'manager')
      OR given_to = fn_current_user_uid()
    )
  );

CREATE POLICY "funds_insert_manager" ON funds
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'manager'));

CREATE POLICY "funds_update_manager" ON funds
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'manager'));

-- Fund transfers are never deleted (audit trail)
CREATE POLICY "funds_delete_never" ON funds
  FOR DELETE
  USING (false);


-- =============================================================================
-- POLICY: ledger  (created but RLS NOT yet enabled — Phase 1)
-- =============================================================================

DROP POLICY IF EXISTS "ledger_select_accountant_or_own" ON ledger;
DROP POLICY IF EXISTS "ledger_insert_never_from_app"    ON ledger;
DROP POLICY IF EXISTS "ledger_update_never"             ON ledger;
DROP POLICY IF EXISTS "ledger_delete_never"             ON ledger;

-- Accountants+ see all ledger; employees see their own.
-- ledger.employee_id references employees.id which IS the Firebase UID.
CREATE POLICY "ledger_select_accountant_or_own" ON ledger
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'accountant')
      OR employee_id = fn_current_user_uid()   -- employees.id = Firebase UID
    )
  );

-- Ledger is ONLY written by server-side Edge Functions using service role key.
-- The Flutter app never inserts directly.
CREATE POLICY "ledger_insert_never_from_app" ON ledger
  FOR INSERT
  WITH CHECK (false);  -- service role bypasses RLS; anon/user role is blocked

-- Ledger is immutable — no updates ever
CREATE POLICY "ledger_update_never" ON ledger
  FOR UPDATE
  USING (false);

-- Ledger is immutable — no deletes ever
CREATE POLICY "ledger_delete_never" ON ledger
  FOR DELETE
  USING (false);


-- =============================================================================
-- POLICY: users  (created but RLS NOT yet enabled — Phase 1)
-- =============================================================================

DROP POLICY IF EXISTS "users_select_self_or_admin"  ON users;
DROP POLICY IF EXISTS "users_insert_self"            ON users;
DROP POLICY IF EXISTS "users_update_self_safe"       ON users;
DROP POLICY IF EXISTS "users_delete_never"           ON users;

-- Users can read their own row; admins can read all users in their business
CREATE POLICY "users_select_self_or_admin" ON users
  FOR SELECT
  USING (
    uid = fn_current_user_uid()
    OR (
      business_id IS NOT NULL
      AND fn_has_role_or_above(business_id, 'admin')
    )
  );

-- A user can create their own profile (first-login flow)
CREATE POLICY "users_insert_self" ON users
  FOR INSERT
  WITH CHECK (uid = fn_current_user_uid());

-- Users update their own safe fields; admins can update role/is_active
CREATE POLICY "users_update_self_safe" ON users
  FOR UPDATE
  USING (
    uid = fn_current_user_uid()
    OR (
      business_id IS NOT NULL
      AND fn_has_role_or_above(business_id, 'admin')
    )
  );

-- Users are never hard-deleted
CREATE POLICY "users_delete_never" ON users
  FOR DELETE
  USING (false);


-- [008] All RLS policies created
-- [008] RLS is ENABLED on: businesses, business_members, expense_categories, salary_records, attendance
-- [008] RLS is NOT YET enabled on: employees, expenses, funds, ledger, users

COMMIT;

-- =============================================================================
-- PHASE 1 SCRIPT — Run this SEPARATELY after Firebase JWT is configured
-- =============================================================================
-- DO NOT run this block now. Save as a separate migration for Phase 1.
--
-- -- enable_rls_existing_tables.sql
-- BEGIN;
-- ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE expenses  ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE funds     ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE ledger    ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE users     ENABLE ROW LEVEL SECURITY;
-- COMMIT;
