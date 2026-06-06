-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 020 — Fix users INSERT policy for admin-created employees
--
-- Problem:
--   When a business admin creates a new employee, the app:
--     1. Calls the create-auth-user edge function → gets back the employee UID
--     2. Inserts a row into `users` with uid = <employee UID>
--   The current INSERT policy "users_insert_self" only allows:
--     WITH CHECK (uid = fn_current_user_uid())
--   But fn_current_user_uid() returns the ADMIN's UID, not the employee UID,
--   so the insert fails with:
--     AppException: new row violates row-level security for table 'users' (42501)
--
-- Fix:
--   Add a second INSERT policy that allows an admin to insert users rows
--   whose business_id belongs to a business the admin manages.
--   PostgreSQL ORs multiple permissive policies on the same command, so
--   either policy passing is sufficient.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

DROP POLICY IF EXISTS "users_insert_admin" ON users;

-- Admins can insert a users row for a new employee in their business.
-- The self-insert policy ("users_insert_self") remains unchanged for the
-- first-login flow where a user creates their own row.
CREATE POLICY "users_insert_admin" ON users
  FOR INSERT
  WITH CHECK (
    business_id IS NOT NULL
    AND fn_has_role_or_above(business_id, 'admin')
  );

COMMIT;
