-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 019 — Fix fn_current_user_uid() for Supabase Native Auth
--
-- Problem:
--   Migration 011 rewrote fn_current_user_uid() for Firebase JWT mode,
--   making it extract the UID from user_metadata.sub / user_metadata.user_id.
--   After migration 015 switched to Supabase Native Auth, user_metadata no
--   longer contains 'sub' or 'user_id', so the function falls through to
--   NULLIF(auth.jwt() ->> 'sub', '').  If the JWT's sub claim is absent or
--   the Realtime/REST context strips it, the function returns NULL.
--   NULL breaks every RLS policy that calls fn_current_user_uid(), causing:
--     "new row violates row-level security policy for table 'expenses'"
--
-- Fix:
--   Put auth.uid()::TEXT FIRST in the COALESCE chain.  In Supabase Native
--   Auth, auth.uid() is always populated from the session JWT and returns
--   the correct Supabase user UUID.  The Firebase fallback paths are kept
--   for any deployment that still bridges Firebase JWTs.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_current_user_uid()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    -- 1. Supabase Native Auth — always correct, always populated in REST & Realtime
    auth.uid()::TEXT,

    -- 2. Firebase JWT via signInWithIdToken — UID stored in user_metadata.sub
    (auth.jwt() -> 'user_metadata') ->> 'sub',
    (auth.jwt() -> 'user_metadata') ->> 'user_id',

    -- 3. Direct Firebase JWKS mode — sub IS the Firebase UID
    NULLIF(auth.jwt() ->> 'sub', '')
  );
$$;

COMMENT ON FUNCTION public.fn_current_user_uid IS
  'Returns the current user UID. Prioritises auth.uid() (Supabase Native Auth), '
  'then falls back to Firebase UID paths for signInWithIdToken / JWKS mode.';

-- ── Recreate expenses INSERT policy to use the fixed helper ──────────────────
-- (The old policy body is identical; recreating it forces Postgres to
--  re-evaluate the function binding and clears any cached plan.)

DROP POLICY IF EXISTS "exp_insert_employee" ON expenses;

CREATE POLICY "exp_insert_employee" ON expenses
  FOR INSERT
  WITH CHECK (
    fn_has_role_or_above(business_id, 'employee')
    AND submitted_by = fn_current_user_uid()
  );

COMMIT;
