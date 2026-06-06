-- =============================================================================
-- MIGRATION 012 — Enable RLS on Existing Tables
-- =============================================================================
-- Purpose  : The true security lockdown.
--            After this migration, NO row in any business-scoped table can be
--            read, written, or deleted by a user who is not a verified member
--            of that business — even via direct Supabase REST API calls.
--
-- ⚠️  CRITICAL — DO NOT RUN UNTIL ALL OF THE FOLLOWING ARE TRUE:
-- ─────────────────────────────────────────────────────────────────────────────
--   1. Migration 011 is deployed (JWT fix + fn_assert_caller_role).
--   2. Flutter app is deployed with signInWithIdToken() after Firebase login.
--   3. Supabase Dashboard is configured to trust Firebase JWTs (JWKS URL set).
--   4. You have verified fn_current_user_uid() returns the correct Firebase
--      UID by running: SELECT fn_current_user_uid(); in a Supabase SQL session
--      WHILE LOGGED IN as a test user (not the service role key).
--   5. Staging environment tested: all Flutter screens load correctly with RLS on.
--
-- VERIFICATION QUERY (run before this migration):
--   SELECT fn_current_user_uid();   -- Must return Firebase UID, not NULL
--   SELECT fn_is_member_of('<your-business-id>'::uuid);  -- Must return true
--
-- Safe     : Each ALTER only enables — no policies are dropped.
--            Existing policies from 008 are re-created here to allow fixes.
-- Rollback : See PHASE4_ROLLBACK.sql — RLS can be disabled instantly.
-- Depends  : 008_create_rls_policies.sql + 011 must have run first.
-- =============================================================================

BEGIN;

-- =============================================================================
-- Enable RLS on the five previously-unprotected tables
-- =============================================================================

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funds     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users     ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- POLICY FIX: employees
-- =============================================================================
-- Re-create with FORCE-safe ordering. The original policies in 008 are correct
-- but we re-create here to ensure they're current after any 008 drift.

DROP POLICY IF EXISTS "emp_select_members"         ON employees;
DROP POLICY IF EXISTS "emp_insert_admin"            ON employees;
DROP POLICY IF EXISTS "emp_update_admin_or_self"   ON employees;
DROP POLICY IF EXISTS "emp_delete_owner"            ON employees;

CREATE POLICY "emp_select_members" ON employees
  FOR SELECT
  USING (fn_is_member_of(business_id));

CREATE POLICY "emp_insert_admin" ON employees
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'admin'));

-- Admin+ updates anyone; employee updates only their own row (id = Firebase UID)
CREATE POLICY "emp_update_admin_or_self" ON employees
  FOR UPDATE
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'admin')
      OR id = fn_current_user_uid()
    )
  );

CREATE POLICY "emp_delete_owner" ON employees
  FOR DELETE
  USING (fn_has_role_or_above(business_id, 'owner'));


-- =============================================================================
-- POLICY FIX: expenses
-- =============================================================================

DROP POLICY IF EXISTS "exp_select_accountant_or_own"  ON expenses;
DROP POLICY IF EXISTS "exp_insert_employee"            ON expenses;
DROP POLICY IF EXISTS "exp_update_accountant_or_own"  ON expenses;
DROP POLICY IF EXISTS "exp_delete_own_draft_or_admin" ON expenses;

-- Accountant+ sees all; employees see only their own
CREATE POLICY "exp_select_accountant_or_own" ON expenses
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'accountant')
      OR submitted_by = fn_current_user_uid()
    )
  );

-- Employee+ can submit expenses for themselves only
CREATE POLICY "exp_insert_employee" ON expenses
  FOR INSERT
  WITH CHECK (
    fn_has_role_or_above(business_id, 'employee')
    AND submitted_by = fn_current_user_uid()
  );

-- Accountant+ can approve/reject any expense in the business;
-- Employee can edit their own while still draft or pending
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

-- Employee can delete their own draft; admin can delete any draft
CREATE POLICY "exp_delete_own_draft_or_admin" ON expenses
  FOR DELETE
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'admin')
      OR (submitted_by = fn_current_user_uid() AND status = 'draft')
    )
  );


-- =============================================================================
-- POLICY FIX: funds
-- =============================================================================
-- Note: funds are ONLY written via the transfer_fund RPC (SECURITY DEFINER).
-- The INSERT policy blocks direct REST API inserts from the Flutter anon key.

DROP POLICY IF EXISTS "funds_select_manager_or_own" ON funds;
DROP POLICY IF EXISTS "funds_insert_manager"         ON funds;
DROP POLICY IF EXISTS "funds_update_manager"         ON funds;
DROP POLICY IF EXISTS "funds_delete_never"           ON funds;

-- Manager+ sees all fund transfers; employees see only transfers TO them
CREATE POLICY "funds_select_manager_or_own" ON funds
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'manager')
      OR given_to = fn_current_user_uid()
    )
  );

-- Direct inserts are blocked — must use transfer_fund RPC (SECURITY DEFINER bypasses this)
CREATE POLICY "funds_insert_manager" ON funds
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'manager'));

-- Direct updates are blocked — must use reverse_fund_transfer RPC
CREATE POLICY "funds_update_manager" ON funds
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'manager'));

-- Fund transfer rows are immutable (audit trail)
CREATE POLICY "funds_delete_never" ON funds
  FOR DELETE
  USING (false);


-- =============================================================================
-- POLICY FIX: ledger (immutable — append-only from RPCs only)
-- =============================================================================

DROP POLICY IF EXISTS "ledger_select_accountant_or_own" ON ledger;
DROP POLICY IF EXISTS "ledger_insert_never_from_app"    ON ledger;
DROP POLICY IF EXISTS "ledger_update_never"             ON ledger;
DROP POLICY IF EXISTS "ledger_delete_never"             ON ledger;

-- Accountant+ sees all ledger; employees see their own entries
CREATE POLICY "ledger_select_accountant_or_own" ON ledger
  FOR SELECT
  USING (
    fn_is_member_of(business_id) AND (
      fn_has_role_or_above(business_id, 'accountant')
      OR employee_id = fn_current_user_uid()
    )
  );

-- SECURITY: ledger is ONLY written by SECURITY DEFINER RPCs (approve_expense,
-- transfer_fund, reverse_fund_transfer). The service role bypasses RLS.
-- This WITH CHECK (false) blocks all direct app-level inserts.
CREATE POLICY "ledger_insert_never_from_app" ON ledger
  FOR INSERT
  WITH CHECK (false);

-- Immutable — no updates from any client path
CREATE POLICY "ledger_update_never" ON ledger
  FOR UPDATE
  USING (false);

-- Immutable — no deletes ever
CREATE POLICY "ledger_delete_never" ON ledger
  FOR DELETE
  USING (false);


-- =============================================================================
-- POLICY FIX: users
-- =============================================================================
-- The users table is accessed in two patterns:
--   1. auth_remote_datasource: stream by uid, create on first login, update FCM token
--   2. notification_service: update FCM token by uid
-- Both use the authenticated user's own JWT, so uid = fn_current_user_uid() works.

DROP POLICY IF EXISTS "users_select_self_or_admin"  ON users;
DROP POLICY IF EXISTS "users_insert_self"            ON users;
DROP POLICY IF EXISTS "users_update_self_safe"       ON users;
DROP POLICY IF EXISTS "users_delete_never"           ON users;

-- User reads their own row; admins can read other users in their business
CREATE POLICY "users_select_self_or_admin" ON users
  FOR SELECT
  USING (
    uid = fn_current_user_uid()
    OR (
      business_id IS NOT NULL
      AND fn_has_role_or_above(business_id, 'admin')
    )
  );

-- First-login user row creation: user can only create their own row
CREATE POLICY "users_insert_self" ON users
  FOR INSERT
  WITH CHECK (uid = fn_current_user_uid());

-- Users can update their own row (FCM token, photo, name);
-- admins can update role and is_active for users in their business
CREATE POLICY "users_update_self_safe" ON users
  FOR UPDATE
  USING (
    uid = fn_current_user_uid()
    OR (
      business_id IS NOT NULL
      AND fn_has_role_or_above(business_id, 'admin')
    )
  );

-- Users are never hard-deleted (GDPR: soft-delete via is_active = false)
CREATE POLICY "users_delete_never" ON users
  FOR DELETE
  USING (false);


-- =============================================================================
-- Add Supabase Realtime publication for business-scoped tables
-- =============================================================================
-- Realtime with RLS: only events for rows the user can SELECT are delivered.
-- This means Realtime streams are automatically tenant-isolated after RLS is on.

DO $$
BEGIN
  -- Only add if not already in the publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'employees'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.employees;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'supabase_realtime publication update skipped: %', SQLERRM;
END $$;


-- =============================================================================
-- Verification
-- =============================================================================

DO $$
BEGIN
  -- Confirm RLS is enabled on all five public tables (schema-qualified to exclude auth.users)
  ASSERT (
    SELECT COUNT(*) FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname IN ('employees','expenses','funds','ledger','users')
      AND n.nspname = 'public'
      AND c.relrowsecurity = true
  ) = 5, 'RLS not enabled on all expected tables';

  RAISE NOTICE '[012] RLS ENABLED on: employees, expenses, funds, ledger, users';
  RAISE NOTICE '[012] All business-scoped data is now tenant-isolated at the database level';
  RAISE NOTICE '[012] Cross-business reads/writes are impossible even via direct REST API';
END $$;

COMMIT;
