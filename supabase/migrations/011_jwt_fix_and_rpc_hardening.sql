-- =============================================================================
-- MIGRATION 011 — JWT Helper Fix + RPC Role Enforcement
-- =============================================================================
-- Purpose  : Two critical security fixes before RLS can be activated safely:
--
--   1. Fix fn_current_user_uid() — the original version used auth.uid()::TEXT
--      which fails for Firebase UIDs (non-UUID strings). The correct approach
--      extracts the Firebase UID from the JWT user_metadata, which is where
--      Supabase stores the Firebase JWT claims after signInWithIdToken().
--
--   2. Add caller role validation to all financial RPCs — since SECURITY
--      DEFINER bypasses RLS, the RPCs must self-enforce role hierarchy.
--      Without this, any user with the anon key + knowledge of IDs could
--      call transfer_fund or approve_expense for any business.
--
-- PREREQUISITE (must happen BEFORE running this migration):
--   Flutter app must call supabase.auth.signInWithIdToken() after Firebase
--   login. Otherwise fn_current_user_uid() returns NULL for all users and
--   the role checks become no-ops. See auth_remote_datasource.dart changes.
--
-- SUPABASE DASHBOARD SETUP (one-time):
--   Auth → Settings → External OAuth Providers → Add custom JWT provider
--   JWKS URL: https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com
--   JWT Issuer: https://securetoken.google.com/<YOUR_FIREBASE_PROJECT_ID>
--   Alternatively, use: Dashboard → Auth → Third Party Auth → Firebase
--
-- Safe     : OR REPLACE — idempotent.
-- Rollback : See PHASE4_ROLLBACK.sql
-- Depends  : 007_create_helper_functions.sql, 009_update_atomic_functions_phase1.sql,
--            010_financial_integrity.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Fix fn_current_user_uid() for Firebase JWT
-- =============================================================================
-- Firebase Auth JWT claims structure:
--   { "sub": "FIREBASE_UID", "user_id": "FIREBASE_UID", "email": "...", ... }
--
-- After supabase.auth.signInWithIdToken(idToken: firebaseToken):
--   Supabase creates an auth.users row with a Supabase UUID.
--   The original Firebase JWT claims are preserved in user_metadata.
--   The Supabase JWT's user_metadata contains: { "sub": "FIREBASE_UID", ... }
--
-- auth.uid() returns the SUPABASE UUID — NOT the Firebase UID.
-- Firebase UID is in (auth.jwt() -> 'user_metadata') ->> 'sub'.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_current_user_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    -- PRIMARY: Firebase UID after signInWithIdToken (stored in user_metadata).
    -- Firebase puts the UID in both 'sub' and 'user_id' claims.
    (auth.jwt() -> 'user_metadata') ->> 'sub',
    (auth.jwt() -> 'user_metadata') ->> 'user_id',
    -- FALLBACK: Direct Firebase JWT via JWKS (sub IS the Firebase UID in this mode).
    -- Only used if Supabase is configured to accept Firebase JWTs directly.
    NULLIF(auth.jwt() ->> 'sub', '')
  );
$$;

COMMENT ON FUNCTION public.fn_current_user_uid IS
  'Returns the Firebase UID from the current JWT. Reads user_metadata.sub after '
  'signInWithIdToken, falls back to raw sub claim for direct JWKS mode. NULL if no session.';


-- =============================================================================
-- 2. fn_assert_caller_role() — raise exception if caller lacks minimum role
-- =============================================================================
-- Used inside SECURITY DEFINER RPCs to enforce role hierarchy before
-- any financial operation is allowed. Only enforces when the caller has
-- a valid JWT (i.e., is an authenticated user, not anon key).

CREATE OR REPLACE FUNCTION public.fn_assert_caller_role(
  p_business_id UUID,
  p_min_role    TEXT
)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  TEXT := fn_current_user_uid();
  v_role TEXT;
BEGIN
  -- Skip enforcement if caller has no JWT identity (anon key / pre-auth transition).
  -- After the Flutter app is updated to use signInWithIdToken, all callers will
  -- have a UID and this guard will always be enforced.
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  v_role := fn_my_role_in(p_business_id);

  IF fn_role_level(v_role) < fn_role_level(p_min_role) THEN
    RAISE EXCEPTION
      'Insufficient privileges for business %. Required: %, actual: %.',
      p_business_id, p_min_role, COALESCE(v_role, 'no membership')
      USING ERRCODE = 'P0008';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.fn_assert_caller_role IS
  'Raises P0008 if the calling user''s role is below p_min_role in the given business. '
  'No-op when caller has no JWT (anon key transition safety).';


-- =============================================================================
-- 3. Harden transfer_fund — require caller role >= 'manager'
-- =============================================================================

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
  -- ── Role check ──────────────────────────────────────────────────────────
  PERFORM fn_assert_caller_role(p_business_id, 'manager');

  -- ── Cross-business guard ─────────────────────────────────────────────────
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = p_given_to
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Employee % does not belong to business %. Cross-business fund transfers are not permitted.',
      p_given_to, p_business_id
      USING ERRCODE = 'P0001';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive. Got: %', p_amount
      USING ERRCODE = 'P0002';
  END IF;

  v_new_balance := v_current_balance + p_amount;

  INSERT INTO public.funds (
    business_id,
    transfer_id, amount, given_by, given_by_name,
    given_to, given_to_name, purpose, payment_mode,
    notes, status, transfer_date, created_at
  ) VALUES (
    p_business_id,
    p_transfer_id, p_amount, p_given_by, p_given_by_name,
    p_given_to, p_given_to_name, p_purpose, p_payment_mode,
    p_notes, p_status, p_transfer_date, v_now
  ) RETURNING id INTO v_fund_id;

  UPDATE public.employees SET
    total_assigned = total_assigned + p_amount,
    balance        = balance + p_amount,
    updated_at     = v_now
  WHERE id          = p_given_to
    AND business_id = p_business_id;

  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    p_given_to, p_given_to_name, 'credit', p_amount, v_new_balance,
    'Fund received: ' || p_purpose,
    v_fund_id::TEXT, 'fund_transfer', p_transfer_date, v_now
  );

  RETURN v_fund_id;
END;
$$;

COMMENT ON FUNCTION public.transfer_fund IS
  'Atomically transfers funds. Requires manager+ role. '
  'Cross-business guard (P0001), positive amount (P0002), role check (P0008).';


-- =============================================================================
-- 4. Harden approve_expense — require caller role >= 'accountant'
-- =============================================================================

CREATE OR REPLACE FUNCTION public.approve_expense(
  p_expense_id        UUID,
  p_approved_by       TEXT,
  p_approved_by_name  TEXT,
  p_business_id       UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount            NUMERIC;
  v_submitted_by      TEXT;
  v_submitted_by_name TEXT;
  v_title             TEXT;
  v_current_balance   NUMERIC;
  v_new_balance       NUMERIC;
  v_now               TIMESTAMPTZ := NOW();
BEGIN
  -- ── Role check ──────────────────────────────────────────────────────────
  PERFORM fn_assert_caller_role(p_business_id, 'accountant');

  -- ── Cross-business guard: expense must belong to this business ──────────
  SELECT amount, submitted_by, submitted_by_name, title
  INTO   v_amount, v_submitted_by, v_submitted_by_name, v_title
  FROM   public.expenses
  WHERE  id          = p_expense_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Expense % not found in business %. Cross-business approvals are not permitted.',
      p_expense_id, p_business_id
      USING ERRCODE = 'P0003';
  END IF;

  -- ── Cross-business guard: employee must belong to same business ─────────
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = v_submitted_by
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Employee % for expense % not found in business %.',
      v_submitted_by, p_expense_id, p_business_id
      USING ERRCODE = 'P0004';
  END IF;

  v_new_balance := v_current_balance - v_amount;

  UPDATE public.expenses SET
    status           = 'approved',
    approved_by      = p_approved_by,
    approved_by_name = p_approved_by_name,
    approved_at      = v_now,
    updated_at       = v_now
  WHERE id          = p_expense_id
    AND business_id = p_business_id;

  UPDATE public.employees SET
    total_spent = total_spent + v_amount,
    balance     = balance - v_amount,
    updated_at  = v_now
  WHERE id          = v_submitted_by
    AND business_id = p_business_id;

  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    v_submitted_by, v_submitted_by_name, 'debit', v_amount, v_new_balance,
    'Expense approved: ' || v_title,
    p_expense_id::TEXT, 'expense', v_now, v_now
  );
END;
$$;

COMMENT ON FUNCTION public.approve_expense IS
  'Atomically approves an expense. Requires accountant+ role. '
  'Cross-business guards P0003/P0004, role check P0008.';


-- =============================================================================
-- 5. Harden reverse_fund_transfer — require caller role >= 'admin'
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reverse_fund_transfer(
  p_fund_id      UUID,
  p_reversed_by  TEXT,
  p_reason       TEXT,
  p_business_id  UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount          NUMERIC;
  v_employee_id     TEXT;
  v_employee_name   TEXT;
  v_transfer_id     TEXT;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_reversal_id     UUID;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  -- ── Role check ──────────────────────────────────────────────────────────
  PERFORM fn_assert_caller_role(p_business_id, 'admin');

  SELECT amount, given_to, given_to_name, transfer_id
  INTO   v_amount, v_employee_id, v_employee_name, v_transfer_id
  FROM   public.funds
  WHERE  id          = p_fund_id
    AND  business_id = p_business_id
    AND  status      = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Fund transfer % not found or already cancelled in business %.',
      p_fund_id, p_business_id
      USING ERRCODE = 'P0005';
  END IF;

  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = v_employee_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % not found in business %.', v_employee_id, p_business_id
      USING ERRCODE = 'P0006';
  END IF;

  IF v_current_balance < v_amount THEN
    RAISE EXCEPTION
      'Insufficient balance to reverse transfer. Balance: %, Reversal amount: %.',
      v_current_balance, v_amount
      USING ERRCODE = 'P0007';
  END IF;

  v_new_balance := v_current_balance - v_amount;

  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    v_employee_id, v_employee_name, 'debit', v_amount, v_new_balance,
    'REVERSAL of fund ' || v_transfer_id || ': ' || p_reason,
    p_fund_id::TEXT, 'fund_reversal', v_now, v_now
  ) RETURNING id INTO v_reversal_id;

  UPDATE public.employees SET
    total_assigned = total_assigned - v_amount,
    balance        = balance - v_amount,
    updated_at     = v_now
  WHERE id          = v_employee_id
    AND business_id = p_business_id;

  UPDATE public.funds SET
    status = 'cancelled',
    notes  = COALESCE(notes, '') || ' | REVERSED: ' || p_reason || ' by ' || p_reversed_by
  WHERE id          = p_fund_id
    AND business_id = p_business_id;

  RETURN v_reversal_id;
END;
$$;

COMMENT ON FUNCTION public.reverse_fund_transfer IS
  'Immutable reversal of a fund transfer. Requires admin+ role. '
  'Original records preserved for audit trail. Role check P0008.';


-- =============================================================================
-- 6. Harden fn_get_dashboard_stats — require business membership
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_dashboard_stats(p_business_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
  v_uid    TEXT := fn_current_user_uid();
BEGIN
  -- Enforce membership check when caller has a JWT (not anon key)
  IF v_uid IS NOT NULL AND NOT fn_is_member_of(p_business_id) THEN
    RAISE EXCEPTION
      'Access denied: % is not a member of business %.',
      v_uid, p_business_id
      USING ERRCODE = 'P0011';
  END IF;

  SELECT json_build_object(
    'total_employees',
      (SELECT COUNT(*) FROM employees
       WHERE business_id = p_business_id AND is_active = true),
    'total_expenses',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id),
    'pending_approvals',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id AND status = 'pending'),
    'total_approved_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id AND status = 'approved'),
    'this_month_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id
         AND status = 'approved'
         AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())),
    'last_month_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id
         AND status = 'approved'
         AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW() - INTERVAL '1 month')),
    'top_categories',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT category AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY category ORDER BY total DESC LIMIT 5
       ) t),
    'top_spenders',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT submitted_by_name AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY submitted_by_name ORDER BY total DESC LIMIT 5
       ) t),
    'monthly_trend',
      (SELECT COALESCE(json_agg(t ORDER BY t.month), '[]'::json)
       FROM (
         SELECT
           TO_CHAR(DATE_TRUNC('month', expense_date), 'Mon YYYY') AS month,
           COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  expense_date >= NOW() - INTERVAL '6 months'
         GROUP  BY DATE_TRUNC('month', expense_date)
       ) t)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_get_dashboard_stats IS
  'Dashboard aggregates for a business. Membership-enforced when JWT is present.';


-- =============================================================================
-- 7. Add get_employee_balance — also needs membership check
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_employee_balance(
  p_employee_id TEXT,
  p_business_id UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance NUMERIC;
  v_uid     TEXT := fn_current_user_uid();
BEGIN
  -- Members can read balances; employees can only read their own
  IF v_uid IS NOT NULL THEN
    IF NOT fn_is_member_of(p_business_id) THEN
      RAISE EXCEPTION 'Access denied to business %.', p_business_id
        USING ERRCODE = 'P0011';
    END IF;
    -- Employees can only read their own balance
    IF fn_role_level(fn_my_role_in(p_business_id)) < fn_role_level('manager')
       AND p_employee_id != v_uid THEN
      RAISE EXCEPTION 'Employees may only read their own balance.'
        USING ERRCODE = 'P0012';
    END IF;
  END IF;

  SELECT balance INTO v_balance
  FROM   public.employees
  WHERE  id          = p_employee_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN RETURN 0; END IF;
  RETURN COALESCE(v_balance, 0);
END;
$$;

COMMENT ON FUNCTION public.get_employee_balance IS
  'Returns employee balance. Membership-enforced; employees can only read own balance.';


-- =============================================================================
-- Verification
-- =============================================================================

DO $$
BEGIN
  ASSERT (SELECT COUNT(*) FROM pg_proc WHERE proname = 'fn_current_user_uid') >= 1,
    'fn_current_user_uid not found';
  ASSERT (SELECT COUNT(*) FROM pg_proc WHERE proname = 'fn_assert_caller_role') >= 1,
    'fn_assert_caller_role not found';
  RAISE NOTICE '[011] JWT fix + RPC hardening applied successfully';
  RAISE NOTICE '[011] fn_current_user_uid now reads user_metadata.sub for Firebase UID';
  RAISE NOTICE '[011] transfer_fund requires manager+, approve_expense requires accountant+';
  RAISE NOTICE '[011] reverse_fund_transfer requires admin+, fn_get_dashboard_stats requires membership';
END $$;

COMMIT;
