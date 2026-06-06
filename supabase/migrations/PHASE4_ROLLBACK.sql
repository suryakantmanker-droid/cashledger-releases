-- =============================================================================
-- PHASE 4 ROLLBACK — Emergency RLS Disable + Function Restoration
-- =============================================================================
-- Purpose  : Instantly disables RLS on all tables if a live incident is
--            discovered after Phase 4 deployment. This restores the pre-Phase-4
--            behaviour where the app can read/write data with the anon key.
--
-- ⚠️  USE ONLY IN GENUINE EMERGENCIES ⚠️
-- Running this in production means tenant isolation is DISABLED.
-- Engage the security team immediately if this is executed.
--
-- ROLLBACK STRATEGY — Staged:
--   Stage 1 (seconds): Disable RLS         → data accessible again
--   Stage 2 (minutes): Restore old RPCs    → remove role checks
--   Stage 3 (hours):   Investigate + fix   → re-deploy Phase 4 correctly
--
-- =============================================================================

-- =============================================================================
-- STAGE 1 — Disable RLS (run first, instant effect)
-- =============================================================================

-- Uncomment and run ONLY the tables that are causing issues.
-- DO NOT run all at once unless absolutely necessary.

-- ALTER TABLE public.employees DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.expenses  DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.funds     DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.ledger    DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.users     DISABLE ROW LEVEL SECURITY;

-- To disable ALL at once (emergency only):
-- BEGIN;
-- ALTER TABLE public.employees DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.expenses  DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.funds     DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.ledger    DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.users     DISABLE ROW LEVEL SECURITY;
-- COMMIT;


-- =============================================================================
-- STAGE 2 — Restore fn_current_user_uid() to pre-011 version
-- =============================================================================
-- Run this if the JWT fix (011) caused authentication issues.

/*
CREATE OR REPLACE FUNCTION public.fn_current_user_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid()::TEXT;
$$;
*/


-- =============================================================================
-- STAGE 2 — Remove role checks from RPCs (restore 010 versions)
-- =============================================================================
-- Run this if the role enforcement in 011 blocked legitimate operations.
-- This restores the cross-business guards from 010 but removes role checks.

/*
-- Restore transfer_fund without role check (migration 010 version):
CREATE OR REPLACE FUNCTION public.transfer_fund(
  p_transfer_id   TEXT,
  p_amount        NUMERIC,
  p_given_by      TEXT,
  p_given_by_name TEXT,
  p_given_to      TEXT,
  p_given_to_name TEXT,
  p_purpose       TEXT,
  p_payment_mode  TEXT,
  p_notes         TEXT,
  p_status        TEXT,
  p_transfer_date TIMESTAMPTZ,
  p_business_id   UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fund_id         UUID;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id = p_given_to AND business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % does not belong to business %. Cross-business fund transfers are not permitted.',
      p_given_to, p_business_id USING ERRCODE = 'P0001';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive. Got: %', p_amount USING ERRCODE = 'P0002';
  END IF;

  v_new_balance := v_current_balance + p_amount;

  INSERT INTO public.funds (
    business_id, transfer_id, amount, given_by, given_by_name,
    given_to, given_to_name, purpose, payment_mode,
    notes, status, transfer_date, created_at
  ) VALUES (
    p_business_id, p_transfer_id, p_amount, p_given_by, p_given_by_name,
    p_given_to, p_given_to_name, p_purpose, p_payment_mode,
    p_notes, p_status, p_transfer_date, v_now
  ) RETURNING id INTO v_fund_id;

  UPDATE public.employees SET
    total_assigned = total_assigned + p_amount,
    balance        = balance + p_amount,
    updated_at     = v_now
  WHERE id = p_given_to AND business_id = p_business_id;

  INSERT INTO public.ledger (
    business_id, employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id, p_given_to, p_given_to_name, 'credit', p_amount, v_new_balance,
    'Fund received: ' || p_purpose, v_fund_id::TEXT, 'fund_transfer', p_transfer_date, v_now
  );

  RETURN v_fund_id;
END;
$$;
*/


-- =============================================================================
-- STAGE 3 — Remove audit logging (if 013 is the issue)
-- =============================================================================

/*
DROP TRIGGER IF EXISTS audit_member_role_change ON business_members;
DROP TRIGGER IF EXISTS audit_fund_cancelled ON funds;
DROP TRIGGER IF EXISTS audit_expense_decision ON expenses;
DROP FUNCTION IF EXISTS trg_audit_member_role_change();
DROP FUNCTION IF EXISTS trg_audit_fund_cancelled();
DROP FUNCTION IF EXISTS trg_audit_expense_decision();
DROP FUNCTION IF EXISTS fn_audit_log(TEXT, TEXT, UUID, TEXT, TEXT, TEXT, JSONB);
-- Keep the table (don't lose audit history): DROP TABLE security_audit_log;
*/


-- =============================================================================
-- VERIFICATION — Check which tables have RLS enabled
-- =============================================================================

SELECT
  relname                                         AS table_name,
  CASE WHEN relrowsecurity THEN '✓ ON' ELSE '✗ OFF' END AS rls_status
FROM pg_class
WHERE relname IN (
  'businesses','business_members','employees','expenses',
  'funds','ledger','users','expense_categories',
  'salary_records','attendance','security_audit_log'
)
ORDER BY relname;


-- =============================================================================
-- MONITORING — Find recent access denials
-- =============================================================================

-- Check for recent policy violations logged in audit log:
-- SELECT event_type, severity, user_uid, business_id, details, created_at
-- FROM   security_audit_log
-- WHERE  severity IN ('warning','critical')
-- ORDER  BY created_at DESC
-- LIMIT  50;

-- Check pg_stat_activity for blocked queries:
-- SELECT pid, usename, state, wait_event_type, wait_event, query
-- FROM   pg_stat_activity
-- WHERE  state != 'idle'
-- ORDER  BY query_start;
