-- =============================================================================
-- MIGRATION 001 — Create user_role enum
-- =============================================================================
-- Purpose : Define the role hierarchy as a native PostgreSQL enum so that
--           the database itself enforces valid role values.
-- Safe    : Guarded by DO block — idempotent, re-runnable.
-- Impact  : Creates a new TYPE only. No existing tables touched.
-- Rollback: DROP TYPE user_role;   (only safe if no column uses it yet)
-- =============================================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'user_role'
  ) THEN
    -- Ordered from least to most privileged.
    -- This ordering is NOT used for comparison directly; the helper function
    -- role_level() in migration 007 maps each value to an integer for that.
    CREATE TYPE user_role AS ENUM (
      'viewer',
      'employee',
      'accountant',
      'manager',
      'admin',
      'owner'
    );
    RAISE NOTICE '[001] Created user_role enum type.';
  ELSE
    RAISE NOTICE '[001] user_role enum already exists — skipped.';
  END IF;
END
$$;

COMMIT;
