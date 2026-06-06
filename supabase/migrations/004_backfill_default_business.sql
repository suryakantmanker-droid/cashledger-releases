-- =============================================================================
-- MIGRATION 004 — Backfill default business and apply NOT NULL constraints
-- =============================================================================
-- Purpose : 1. Creates ONE default business for all existing data.
--           2. Assigns every existing row to that default business.
--           3. Adds NOT NULL + DEFAULT constraints so the existing Flutter
--              app can continue inserting without specifying business_id.
--           4. Seeds default expense categories.
--
-- IMPORTANT — The DEFAULT constraint in step 3 is the backward-compat bridge:
--   The running Flutter app does NOT send business_id in its INSERT statements.
--   The DEFAULT ensures those rows go into the default business automatically,
--   keeping the app fully functional until Phase 1 (Flutter migration).
--   After Phase 1 you MUST remove the DEFAULT — it becomes a security gap.
--
-- Default Business UUID: 11111111-1111-1111-1111-111111111111
--   (Fixed, well-known UUID — easy to identify in queries and logs)
--
-- Safe    : All operations guarded by WHERE NOT EXISTS / IS NULL checks.
-- Rollback: See ROLLBACK.sql → section 004
-- Depends : 003_add_business_id_columns.sql must have run first
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1 — Create the default business
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO businesses (
  id,
  name,
  slug,
  owner_uid,
  plan,
  max_employees,
  is_active,
  settings,
  created_at,
  updated_at
)
SELECT
  '11111111-1111-1111-1111-111111111111'::UUID,
  'Default Business',
  'default-business',
  -- Pick the first admin user as owner; fall back to 'system' if no admin exists
  COALESCE(
    (SELECT uid FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1),
    'system'
  ),
  'pro',
  9999,            -- no employee cap on the default business
  true,
  jsonb_build_object(
    'currency',               'INR',
    'timezone',               'Asia/Kolkata',
    'fiscal_year_start_month', 4,
    'migrated',               true
  ),
  NOW(),
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM businesses
  WHERE id = '11111111-1111-1111-1111-111111111111'::UUID
);

-- Step 1 complete — default business created (or already existed)

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2 — Create business_members for every existing user
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO business_members (
  business_id,
  user_uid,
  role,
  is_active,
  joined_at,
  created_at,
  updated_at
)
SELECT
  '11111111-1111-1111-1111-111111111111'::UUID,
  u.uid,
  -- Map old two-role system to new six-role hierarchy
  CASE u.role
    WHEN 'admin'    THEN 'admin'
    WHEN 'employee' THEN 'employee'
    ELSE                 'viewer'     -- unknown roles become viewer (safe default)
  END,
  COALESCE(u.is_active, true),
  COALESCE(u.created_at, NOW()),
  NOW(),
  NOW()
FROM users u
WHERE u.uid IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM business_members bm
    WHERE bm.business_id = '11111111-1111-1111-1111-111111111111'::UUID
      AND bm.user_uid    = u.uid
  );

-- Step 2 complete — business_members created for all existing users

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3 — Backfill business_id = default on all existing rows
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE employees
SET    business_id = '11111111-1111-1111-1111-111111111111'::UUID
WHERE  business_id IS NULL;

-- Step 3a — backfilled employees

UPDATE expenses
SET    business_id = '11111111-1111-1111-1111-111111111111'::UUID
WHERE  business_id IS NULL;

-- Step 3b — backfilled expenses

UPDATE funds
SET    business_id = '11111111-1111-1111-1111-111111111111'::UUID
WHERE  business_id IS NULL;

-- Step 3c — backfilled funds

UPDATE ledger
SET    business_id = '11111111-1111-1111-1111-111111111111'::UUID
WHERE  business_id IS NULL;

-- Step 3d — backfilled ledger

UPDATE users
SET    business_id = '11111111-1111-1111-1111-111111111111'::UUID
WHERE  business_id IS NULL;

-- Step 3e — backfilled users

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4 — Verify zero NULL rows before applying NOT NULL constraint
--          If any row is still NULL, raise an exception and abort.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT  COUNT(*) INTO null_count FROM employees WHERE business_id IS NULL;
  IF null_count > 0 THEN
    RAISE EXCEPTION '[004] ABORT: % employees rows still have NULL business_id', null_count;
  END IF;

  SELECT  COUNT(*) INTO null_count FROM expenses WHERE business_id IS NULL;
  IF null_count > 0 THEN
    RAISE EXCEPTION '[004] ABORT: % expenses rows still have NULL business_id', null_count;
  END IF;

  SELECT  COUNT(*) INTO null_count FROM funds WHERE business_id IS NULL;
  IF null_count > 0 THEN
    RAISE EXCEPTION '[004] ABORT: % funds rows still have NULL business_id', null_count;
  END IF;

  SELECT  COUNT(*) INTO null_count FROM ledger WHERE business_id IS NULL;
  IF null_count > 0 THEN
    RAISE EXCEPTION '[004] ABORT: % ledger rows still have NULL business_id', null_count;
  END IF;

  RAISE NOTICE '[004] Step 4 — all rows verified, no NULLs remaining';
END
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5 — Apply NOT NULL + DEFAULT to existing tables
--
-- DEFAULT = the default business UUID. This is the backward-compat bridge:
-- the existing Flutter app's INSERT statements (which omit business_id) will
-- automatically target the default business until Phase 1 is deployed.
--
-- ⚠️  REMOVE THESE DEFAULTS after Phase 1 Flutter deployment using:
--     ALTER TABLE employees ALTER COLUMN business_id DROP DEFAULT;
--     (etc. for other tables)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE employees
  ALTER COLUMN business_id SET NOT NULL,
  ALTER COLUMN business_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::UUID;

ALTER TABLE expenses
  ALTER COLUMN business_id SET NOT NULL,
  ALTER COLUMN business_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::UUID;

ALTER TABLE funds
  ALTER COLUMN business_id SET NOT NULL,
  ALTER COLUMN business_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::UUID;

ALTER TABLE ledger
  ALTER COLUMN business_id SET NOT NULL,
  ALTER COLUMN business_id SET DEFAULT '11111111-1111-1111-1111-111111111111'::UUID;

-- users.business_id stays nullable — a user may exist before joining a business.

-- Step 5 — NOT NULL + DEFAULT constraints applied to all tables

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6 — Seed default expense categories for the default business
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO expense_categories (business_id, name, sort_order)
VALUES
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Travel',          1),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Food & Beverage', 2),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Office Supplies', 3),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Utilities',       4),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Rent',            5),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Vendor Payment',  6),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Maintenance',     7),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Marketing',       8),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Salaries',        9),
  ('11111111-1111-1111-1111-111111111111'::UUID, 'Miscellaneous',   10)
ON CONFLICT (business_id, name) DO NOTHING;

-- Step 6 complete — default expense categories seeded

COMMIT;
