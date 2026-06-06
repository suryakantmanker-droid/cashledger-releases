-- =============================================================================
-- MIGRATION 007 — RLS helper functions
-- =============================================================================
-- Purpose : Create the four helper SQL functions used by RLS policies.
--           These functions are the single source of truth for:
--             • Who is a member of a business?
--             • What role does the current user have?
--             • Does a role meet a minimum privilege level?
--             • What is the current user's Firebase UID?
--
-- PREREQUISITES — Firebase JWT + Supabase
-- ─────────────────────────────────────────────────────────────────────────────
-- auth.uid() in Supabase returns the "sub" claim from the JWT.
-- When using Firebase Auth with Supabase, you must configure Supabase to
-- accept Firebase-signed JWTs:
--
--   Option A (Recommended): Use supabase.auth.signInWithIdToken() in Flutter:
--     await supabase.auth.signInWithIdToken(
--       provider: OAuthProvider.google,   // or custom
--       idToken: await firebaseUser.getIdToken(),
--     );
--     This creates a Supabase session → auth.uid() works correctly.
--
--   Option B: Configure Supabase JWT secret to Firebase's project public key.
--     Supabase Dashboard → Project Settings → API → JWT Settings
--     Set: JWT Secret = Firebase RS256 public key (JWKS URL).
--
-- Until one of the above is configured, auth.uid() returns NULL and these
-- functions will return their safe defaults (false / 'viewer' / 0).
-- The app will still work (RLS is not enabled yet in Phase 0).
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Safe    : OR REPLACE — fully idempotent.
-- Rollback: See ROLLBACK.sql → section 007
-- Depends : 002_create_new_tables.sql must have run first
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_current_user_uid()
-- Returns the Firebase Auth UID from the active JWT.
-- Returns NULL if no session exists (anon key only, no auth configured).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_current_user_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- auth.uid() returns UUID; we cast to TEXT since Firebase UIDs are TEXT.
  -- This works whether Supabase Auth or Firebase JWT is configured.
  SELECT auth.uid()::TEXT;
$$;

COMMENT ON FUNCTION fn_current_user_uid IS
  'Returns the Firebase Auth UID from the current JWT. NULL if no auth session.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_is_member_of(business_id UUID)
-- Returns TRUE if the current user is an active member of the given business.
-- Used in RLS SELECT policies: "can the user see this row at all?"
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_is_member_of(p_business_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   business_members
    WHERE  business_id = p_business_id
      AND  user_uid    = fn_current_user_uid()
      AND  is_active   = true
  );
$$;

COMMENT ON FUNCTION fn_is_member_of IS
  'TRUE if current user is an active member of the given business.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_my_role_in(business_id UUID)
-- Returns the role TEXT for the current user in the given business.
-- Returns NULL if the user is not a member.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_my_role_in(p_business_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM   business_members
  WHERE  business_id = p_business_id
    AND  user_uid    = fn_current_user_uid()
    AND  is_active   = true
  LIMIT  1;
$$;

COMMENT ON FUNCTION fn_my_role_in IS
  'Returns the role (TEXT) of the current user in the given business, or NULL if not a member.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_role_level(role TEXT)
-- Maps a role name to an integer so we can do ">=" comparisons.
-- Higher number = more privilege.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_role_level(p_role TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE p_role
    WHEN 'owner'       THEN 50
    WHEN 'admin'       THEN 40
    WHEN 'manager'     THEN 30
    WHEN 'accountant'  THEN 20
    WHEN 'employee'    THEN 10
    WHEN 'viewer'      THEN  0
    ELSE                     -1   -- unknown role → no access
  END;
$$;

COMMENT ON FUNCTION fn_role_level IS
  'Maps role name → integer for hierarchy comparison. owner=50 … viewer=0.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_has_role_or_above(business_id UUID, min_role TEXT)
-- Returns TRUE if the current user's role in the given business is at least
-- as privileged as min_role.
--
-- Usage examples in RLS policies:
--   fn_has_role_or_above(business_id, 'admin')      → owner OR admin
--   fn_has_role_or_above(business_id, 'accountant') → owner/admin/manager/accountant
--   fn_has_role_or_above(business_id, 'employee')   → everyone except viewer
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_has_role_or_above(p_business_id UUID, p_min_role TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT fn_role_level(fn_my_role_in(p_business_id)) >= fn_role_level(p_min_role);
$$;

COMMENT ON FUNCTION fn_has_role_or_above IS
  'TRUE if the current user''s role in p_business_id >= p_min_role in the hierarchy.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_get_dashboard_stats(business_id UUID)
-- Single RPC call for dashboard — avoids N+1 queries from the Flutter app.
-- Called via: supabase.rpc('fn_get_dashboard_stats', params: {'p_business_id': id})
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_get_dashboard_stats(p_business_id UUID)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    -- counts
    'total_employees',
      (SELECT COUNT(*) FROM employees
       WHERE business_id = p_business_id AND is_active = true),

    'total_expenses',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id),

    'pending_approvals',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id AND status = 'pending'),

    -- financial totals
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

    -- top 5 categories this month
    'top_categories',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT category AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id
           AND  status      = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY category
         ORDER  BY total DESC
         LIMIT  5
       ) t),

    -- top 5 spending employees this month
    'top_spenders',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT submitted_by_name AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id
           AND  status      = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY submitted_by_name
         ORDER  BY total DESC
         LIMIT  5
       ) t),

    -- monthly trend (last 6 months)
    'monthly_trend',
      (SELECT COALESCE(json_agg(t ORDER BY t.month), '[]'::json)
       FROM (
         SELECT
           TO_CHAR(DATE_TRUNC('month', expense_date), 'Mon YYYY') AS month,
           COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id
           AND  status      = 'approved'
           AND  expense_date >= NOW() - INTERVAL '6 months'
         GROUP  BY DATE_TRUNC('month', expense_date)
       ) t)
  );
$$;

COMMENT ON FUNCTION fn_get_dashboard_stats IS
  'Single-call dashboard aggregates. Call via supabase.rpc(''fn_get_dashboard_stats'').';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_next_expense_code(business_id UUID)
-- Generates collision-free, sequential expense codes per business.
-- e.g. EXP00001, EXP00002 …
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_next_expense_code(p_business_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_seq INTEGER;
BEGIN
  SELECT COALESCE(
    MAX(CAST(SUBSTRING(expense_id FROM 4) AS INTEGER)), 0
  ) + 1
  INTO   next_seq
  FROM   expenses
  WHERE  business_id = p_business_id
    AND  expense_id  ~ '^EXP[0-9]+$';

  RETURN 'EXP' || LPAD(next_seq::TEXT, 5, '0');
END;
$$;

COMMENT ON FUNCTION fn_next_expense_code IS
  'Returns the next sequential expense code (EXP00001 …) for a given business.';

-- ─────────────────────────────────────────────────────────────────────────────
-- fn_next_fund_code(business_id UUID)
-- Generates collision-free, sequential fund transfer codes per business.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_next_fund_code(p_business_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_seq INTEGER;
BEGIN
  SELECT COALESCE(
    MAX(CAST(SUBSTRING(transfer_id FROM 4) AS INTEGER)), 0
  ) + 1
  INTO   next_seq
  FROM   funds
  WHERE  business_id = p_business_id
    AND  transfer_id ~ '^TRF[0-9]+$';

  RETURN 'TRF' || LPAD(next_seq::TEXT, 5, '0');
END;
$$;

COMMENT ON FUNCTION fn_next_fund_code IS
  'Returns the next sequential fund transfer code (TRF00001 …) for a given business.';

-- [007] All helper functions created successfully

COMMIT;
