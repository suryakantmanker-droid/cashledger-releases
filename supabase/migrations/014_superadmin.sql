-- =============================================================================
-- MIGRATION 014 — Superadmin Support
-- =============================================================================
-- Purpose  : Adds a superadmin flag to the users table.
--            A superadmin bypasses all business membership checks and has
--            read/write access to every business in the system.
--
-- Safe     : IF NOT EXISTS / OR REPLACE — fully idempotent.
-- Rollback : ALTER TABLE users DROP COLUMN IF EXISTS is_superadmin;
--            DROP FUNCTION IF EXISTS fn_is_superadmin();
-- =============================================================================

BEGIN;

-- ── 1. Add is_superadmin column ───────────────────────────────────────────────

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_superadmin BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.is_superadmin IS
  'TRUE = platform superadmin. Bypasses all business membership checks. Set manually by DB admin only.';

-- Partial index: fast lookup for the (rare) superadmin check
CREATE INDEX IF NOT EXISTS idx_users_is_superadmin
  ON public.users (uid)
  WHERE is_superadmin = true;

-- ── 2. Helper function: fn_is_superadmin() ────────────────────────────────────
-- Used by RLS policies to grant superadmin full access on all tables.

CREATE OR REPLACE FUNCTION public.fn_is_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_superadmin FROM public.users
     WHERE uid = COALESCE(
       -- Firebase UID embedded in Supabase JWT by the custom token flow
       (auth.jwt() -> 'user_metadata' ->> 'sub'),
       (auth.jwt() -> 'user_metadata' ->> 'user_id'),
       (auth.jwt() ->> 'sub')
     )
    ),
    false
  );
$$;

COMMENT ON FUNCTION public.fn_is_superadmin IS
  'Returns TRUE if the current JWT user has the superadmin flag set. Used in RLS policies.';

-- ── 3. RLS policy addendums — superadmin bypasses all tenant isolation ─────────
-- Wrapped in DO blocks so the migration is safe even if earlier migrations
-- (002–013) have not yet been run. Policies are created only when the table exists.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='businesses') THEN
    DROP POLICY IF EXISTS "businesses_select_superadmin" ON businesses;
    CREATE POLICY "businesses_select_superadmin" ON businesses
      FOR SELECT USING (fn_is_superadmin());

    DROP POLICY IF EXISTS "businesses_all_superadmin" ON businesses;
    CREATE POLICY "businesses_all_superadmin" ON businesses
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='business_members') THEN
    DROP POLICY IF EXISTS "biz_members_superadmin" ON business_members;
    CREATE POLICY "biz_members_superadmin" ON business_members
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='users') THEN
    DROP POLICY IF EXISTS "users_superadmin" ON users;
    CREATE POLICY "users_superadmin" ON users
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='employees') THEN
    DROP POLICY IF EXISTS "employees_superadmin" ON employees;
    CREATE POLICY "employees_superadmin" ON employees
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='expenses') THEN
    DROP POLICY IF EXISTS "expenses_superadmin" ON expenses;
    CREATE POLICY "expenses_superadmin" ON expenses
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='funds') THEN
    DROP POLICY IF EXISTS "funds_superadmin" ON funds;
    CREATE POLICY "funds_superadmin" ON funds
      FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='ledger') THEN
    DROP POLICY IF EXISTS "ledger_superadmin" ON ledger;
    CREATE POLICY "ledger_superadmin" ON ledger
      FOR SELECT USING (fn_is_superadmin());
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='security_audit_log') THEN
    DROP POLICY IF EXISTS "audit_select_superadmin" ON security_audit_log;
    CREATE POLICY "audit_select_superadmin" ON security_audit_log
      FOR SELECT USING (fn_is_superadmin());
  END IF;
END $$;


-- ── 4. Set superadmin for the platform owner ─────────────────────────────────
-- IMPORTANT: Replace with the actual superadmin email before running.
-- Run this section AFTER confirming the user exists in the users table
-- (they must have logged in at least once so Firebase created their UID).

-- Example (uncomment and edit):
-- UPDATE public.users SET is_superadmin = true WHERE email = 'admin@cashledger.com';


-- ── Verification ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  ASSERT (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_name = 'users' AND column_name = 'is_superadmin'
  ) = 1, 'is_superadmin column not found on users table';

  ASSERT (
    SELECT COUNT(*) FROM pg_proc WHERE proname = 'fn_is_superadmin'
  ) >= 1, 'fn_is_superadmin function not created';

  RAISE NOTICE '[014] Superadmin migration complete';
  RAISE NOTICE '[014] Remember to run: UPDATE users SET is_superadmin = true WHERE email = ''your@email.com'';';
END $$;

COMMIT;
