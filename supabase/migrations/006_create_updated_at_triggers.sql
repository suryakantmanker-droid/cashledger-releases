-- =============================================================================
-- MIGRATION 006 — Auto-update updated_at triggers
-- =============================================================================
-- Purpose : Every table with an updated_at column gets a trigger that
--           automatically stamps the column on every UPDATE.
-- Safe    : OR REPLACE on functions; DROP IF EXISTS + CREATE on triggers.
-- Impact  : Negligible overhead per UPDATE (native PL/pgSQL).
-- Rollback: See ROLLBACK.sql → section 006
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared trigger function (one function, reused by all tables)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_set_updated_at IS
  'Shared trigger function: stamps updated_at = NOW() on every row UPDATE.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper macro: creates the trigger on a given table.
-- Called once per table below.
-- ─────────────────────────────────────────────────────────────────────────────

-- businesses
DROP TRIGGER IF EXISTS trg_businesses_updated_at ON businesses;
CREATE TRIGGER trg_businesses_updated_at
  BEFORE UPDATE ON businesses
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- business_members
DROP TRIGGER IF EXISTS trg_business_members_updated_at ON business_members;
CREATE TRIGGER trg_business_members_updated_at
  BEFORE UPDATE ON business_members
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- employees
DROP TRIGGER IF EXISTS trg_employees_updated_at ON employees;
CREATE TRIGGER trg_employees_updated_at
  BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- expenses
DROP TRIGGER IF EXISTS trg_expenses_updated_at ON expenses;
CREATE TRIGGER trg_expenses_updated_at
  BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- salary_records
DROP TRIGGER IF EXISTS trg_salary_records_updated_at ON salary_records;
CREATE TRIGGER trg_salary_records_updated_at
  BEFORE UPDATE ON salary_records
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- attendance
DROP TRIGGER IF EXISTS trg_attendance_updated_at ON attendance;
CREATE TRIGGER trg_attendance_updated_at
  BEFORE UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- NOTE: ledger and funds have NO updated_at — they are append-only by design.
-- users.updated_at: if this column exists in your schema, add trigger here.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'users'
      AND column_name  = 'updated_at'
  ) THEN
    EXECUTE '
      DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
      CREATE TRIGGER trg_users_updated_at
        BEFORE UPDATE ON users
        FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
    ';
    RAISE NOTICE '[006] Created updated_at trigger on users';
  END IF;
END $$;

-- [006] All updated_at triggers installed successfully

COMMIT;
