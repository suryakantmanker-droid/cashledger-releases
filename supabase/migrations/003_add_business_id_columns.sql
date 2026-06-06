-- =============================================================================
-- MIGRATION 003 — Add business_id to existing tables
-- =============================================================================
-- Purpose : Extend every existing data table with a business_id column.
--           Also adds supplementary new columns needed for multi-business.
-- Safe    : Each ALTER is guarded by an existence check — fully idempotent.
--
-- CRITICAL SAFETY DESIGN
-- ─────────────────────────────────────────────────────────────────────────────
-- All new columns are added as NULLABLE first.
-- The existing Flutter app inserts rows WITHOUT business_id → they land as NULL.
-- NOT NULL + DEFAULT is added in migration 004 AFTER backfill completes.
-- This means the existing running app is NEVER broken by this migration.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Rollback: See ROLLBACK.sql → section 003
-- Depends : 002_create_new_tables.sql must have run first
-- =============================================================================

BEGIN;

-- ── users ─────────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'users'
      AND column_name  = 'business_id'
  ) THEN
    ALTER TABLE users ADD COLUMN business_id UUID
      REFERENCES businesses(id) ON DELETE SET NULL;
    RAISE NOTICE '[003] Added business_id to users';
  ELSE
    RAISE NOTICE '[003] users.business_id already exists — skipped';
  END IF;
END $$;

-- ── employees ─────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'employees'
      AND column_name  = 'business_id'
  ) THEN
    ALTER TABLE employees ADD COLUMN business_id UUID
      REFERENCES businesses(id) ON DELETE CASCADE;
    RAISE NOTICE '[003] Added business_id to employees';
  ELSE
    RAISE NOTICE '[003] employees.business_id already exists — skipped';
  END IF;
END $$;

-- NOTE: employees.user_id already exists in the original schema (001_initial_schema.sql).
-- employees.id      = Firebase Auth UID (the primary key — same as the Firebase user)
-- employees.user_id = secondary Firebase UID field (currently unused by Flutter models)
--
-- In Phase 1 RLS policies we will use employees.id (the PK) to identify the
-- Firebase user, since that is what the app actually stores and queries.
-- No new column needed here.

-- designation: job title within the business
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'employees'
      AND column_name  = 'designation'
  ) THEN
    ALTER TABLE employees ADD COLUMN designation TEXT;
    RAISE NOTICE '[003] Added designation to employees';
  ELSE
    RAISE NOTICE '[003] employees.designation already exists — skipped';
  END IF;
END $$;

-- salary: base monthly salary
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'employees'
      AND column_name  = 'salary'
  ) THEN
    ALTER TABLE employees ADD COLUMN salary NUMERIC(14,2) NOT NULL DEFAULT 0;
    RAISE NOTICE '[003] Added salary to employees';
  ELSE
    RAISE NOTICE '[003] employees.salary already exists — skipped';
  END IF;
END $$;

-- ── expenses ──────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'business_id'
  ) THEN
    ALTER TABLE expenses ADD COLUMN business_id UUID
      REFERENCES businesses(id) ON DELETE CASCADE;
    RAISE NOTICE '[003] Added business_id to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.business_id already exists — skipped';
  END IF;
END $$;

-- category_id: FK to expense_categories (nullable — keep existing category TEXT for now)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'category_id'
  ) THEN
    ALTER TABLE expenses ADD COLUMN category_id UUID
      REFERENCES expense_categories(id) ON DELETE SET NULL;
    RAISE NOTICE '[003] Added category_id to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.category_id already exists — skipped';
  END IF;
END $$;

-- submitted_at: when the expense was formally submitted (separate from created_at)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'submitted_at'
  ) THEN
    ALTER TABLE expenses ADD COLUMN submitted_at TIMESTAMPTZ;
    RAISE NOTICE '[003] Added submitted_at to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.submitted_at already exists — skipped';
  END IF;
END $$;

-- is_recurring + recurrence fields
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'is_recurring'
  ) THEN
    ALTER TABLE expenses ADD COLUMN is_recurring        BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE expenses ADD COLUMN recurrence_pattern  TEXT
      CHECK (recurrence_pattern IN ('daily','weekly','monthly','yearly'));
    ALTER TABLE expenses ADD COLUMN recurrence_end_date DATE;
    RAISE NOTICE '[003] Added recurring fields to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.is_recurring already exists — skipped';
  END IF;
END $$;

-- edit_history: JSONB array of change snapshots (append-only in app code)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'edit_history'
  ) THEN
    ALTER TABLE expenses ADD COLUMN edit_history JSONB NOT NULL DEFAULT '[]';
    RAISE NOTICE '[003] Added edit_history to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.edit_history already exists — skipped';
  END IF;
END $$;

-- comments: JSONB array of {id, user_uid, user_name, message, created_at}
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'comments'
  ) THEN
    ALTER TABLE expenses ADD COLUMN comments JSONB NOT NULL DEFAULT '[]';
    RAISE NOTICE '[003] Added comments to expenses';
  ELSE
    RAISE NOTICE '[003] expenses.comments already exists — skipped';
  END IF;
END $$;

-- ── funds ─────────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'funds'
      AND column_name  = 'business_id'
  ) THEN
    ALTER TABLE funds ADD COLUMN business_id UUID
      REFERENCES businesses(id) ON DELETE CASCADE;
    RAISE NOTICE '[003] Added business_id to funds';
  ELSE
    RAISE NOTICE '[003] funds.business_id already exists — skipped';
  END IF;
END $$;

-- ── ledger ────────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'ledger'
      AND column_name  = 'business_id'
  ) THEN
    ALTER TABLE ledger ADD COLUMN business_id UUID
      REFERENCES businesses(id) ON DELETE CASCADE;
    RAISE NOTICE '[003] Added business_id to ledger';
  ELSE
    RAISE NOTICE '[003] ledger.business_id already exists — skipped';
  END IF;
END $$;

COMMIT;
