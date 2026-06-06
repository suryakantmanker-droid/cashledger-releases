-- =============================================================================
-- MIGRATION 002 — Create new multi-business tables
-- =============================================================================
-- Purpose : Add the five brand-new tables that form the multi-tenancy layer.
--           No existing tables are modified here.
-- Safe    : All CREATE statements use IF NOT EXISTS — fully idempotent.
-- Impact  : Creates new tables only. Existing app code is unaffected.
-- Rollback: See ROLLBACK.sql → section 002
-- Depends : 001_create_role_enum.sql must have run first
-- =============================================================================
--
-- NOTE ON AUTH STRATEGY
-- ─────────────────────
-- This app uses Firebase Auth (not Supabase Auth). Therefore:
--   • All "user ID" columns are TEXT (Firebase UID), not UUID.
--   • They do NOT reference auth.users because Firebase UIDs are not Supabase
--     auth UUIDs. There is no FK enforcement for user identity at the DB level.
--   • RLS referencing auth.uid() requires Firebase JWT configured in Supabase.
--     See README.md → "Firebase JWT Setup" before enabling RLS.
-- =============================================================================

BEGIN;

-- ── businesses ────────────────────────────────────────────────────────────────
-- Root tenant table. Every other table cascades from here.
-- Each row is a completely isolated business silo.

CREATE TABLE IF NOT EXISTS businesses (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT          NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  slug            TEXT          NOT NULL CHECK (slug ~ '^[a-z0-9-]+$'),
  logo_url        TEXT,
  owner_uid       TEXT          NOT NULL,   -- Firebase Auth UID
  plan            TEXT          NOT NULL DEFAULT 'free'
                                  CHECK (plan IN ('free','starter','pro','enterprise')),
  max_employees   INTEGER       NOT NULL DEFAULT 10 CHECK (max_employees > 0),
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  -- JSONB settings bag: currency, timezone, fiscal_year_start_month, etc.
  settings        JSONB         NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT businesses_slug_unique UNIQUE (slug)
);

COMMENT ON TABLE  businesses              IS 'Root tenant. Every data table FKs to this.';
COMMENT ON COLUMN businesses.owner_uid   IS 'Firebase Auth UID of the owner. Not an FK.';
COMMENT ON COLUMN businesses.slug        IS 'URL-safe identifier, lowercase letters/numbers/hyphens only.';
COMMENT ON COLUMN businesses.settings    IS 'JSON bag: {currency, timezone, fiscal_year_start_month}.';

-- ── business_members ─────────────────────────────────────────────────────────
-- Maps Firebase users to businesses with a role.
-- A single Firebase user can belong to multiple businesses.

CREATE TABLE IF NOT EXISTS business_members (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID          NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_uid      TEXT          NOT NULL,   -- Firebase Auth UID
  role          TEXT          NOT NULL
                                CHECK (role IN ('owner','admin','manager','accountant','employee','viewer')),
  is_active     BOOLEAN       NOT NULL DEFAULT true,
  invited_by    TEXT,                     -- Firebase Auth UID of the inviter (NULL for first owner)
  joined_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT business_members_user_unique UNIQUE (business_id, user_uid)
);

COMMENT ON TABLE  business_members           IS 'User ↔ Business membership with role. One user can be in N businesses.';
COMMENT ON COLUMN business_members.user_uid  IS 'Firebase Auth UID. No FK to auth.users (Firebase, not Supabase Auth).';
COMMENT ON COLUMN business_members.role      IS 'Hierarchy: owner > admin > manager > accountant > employee > viewer';

-- ── expense_categories ───────────────────────────────────────────────────────
-- Each business can define its own custom expense category list.

CREATE TABLE IF NOT EXISTS expense_categories (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID          NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name          TEXT          NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  icon          TEXT,
  color         TEXT          CHECK (color ~ '^#[0-9A-Fa-f]{6}$' OR color IS NULL),
  is_active     BOOLEAN       NOT NULL DEFAULT true,
  sort_order    INTEGER       NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT expense_categories_name_unique UNIQUE (business_id, name)
);

COMMENT ON TABLE expense_categories IS 'Per-business expense categories. Defaults seeded in migration 004.';

-- ── salary_records ────────────────────────────────────────────────────────────
-- Monthly pay records per employee per business.

CREATE TABLE IF NOT EXISTS salary_records (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID          NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id   TEXT          NOT NULL,   -- references employees.id (TEXT PK)
  month         SMALLINT      NOT NULL CHECK (month BETWEEN 1 AND 12),
  year          SMALLINT      NOT NULL CHECK (year >= 2020),
  base_salary   NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (base_salary >= 0),
  advances      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (advances >= 0),
  deductions    NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (deductions >= 0),
  net_salary    NUMERIC(14,2) NOT NULL DEFAULT 0,  -- computed: base - advances - deductions
  status        TEXT          NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','paid','cancelled')),
  paid_at       TIMESTAMPTZ,
  paid_by_uid   TEXT,                    -- Firebase Auth UID of admin who processed payment
  notes         TEXT,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT salary_records_unique UNIQUE (business_id, employee_id, month, year)
);

COMMENT ON TABLE salary_records IS 'Monthly salary computation and payment tracking per employee.';

-- ── attendance ────────────────────────────────────────────────────────────────
-- Daily attendance log per employee per business.

CREATE TABLE IF NOT EXISTS attendance (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   UUID          NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id   TEXT          NOT NULL,   -- references employees.id
  date          DATE          NOT NULL,
  status        TEXT          NOT NULL
                                CHECK (status IN (
                                  'present','absent','half_day',
                                  'holiday','leave','work_from_home'
                                )),
  check_in      TIMESTAMPTZ,
  check_out     TIMESTAMPTZ,
  notes         TEXT,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT attendance_employee_date_unique UNIQUE (business_id, employee_id, date)
);

COMMENT ON TABLE attendance IS 'Daily attendance record. One row per employee per day per business.';

COMMIT;
