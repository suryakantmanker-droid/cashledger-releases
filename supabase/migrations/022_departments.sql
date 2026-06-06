-- =============================================================================
-- Migration 022 — Employee Departments
--
-- business_id = NULL  → global (created by superadmin, visible to all)
-- business_id = <id>  → business-specific (visible only to that business)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.departments (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  business_id UUID        REFERENCES businesses(id) ON DELETE CASCADE,
  created_by  TEXT        NOT NULL DEFAULT '',
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT departments_name_business_unique UNIQUE (name, business_id)
);

CREATE INDEX IF NOT EXISTS idx_departments_business ON departments (business_id);
CREATE INDEX IF NOT EXISTS idx_departments_global   ON departments (business_id) WHERE business_id IS NULL;

-- Auto-updated_at not needed (no updates expected — just insert/delete)

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read global departments (business_id IS NULL)
-- Members can read their own business departments
DROP POLICY IF EXISTS "dept_select" ON departments;
CREATE POLICY "dept_select" ON departments
  FOR SELECT
  USING (
    business_id IS NULL                                       -- global
    OR fn_is_member_of(business_id)                          -- own business
  );

-- Business admin can insert departments for their business
DROP POLICY IF EXISTS "dept_insert_admin" ON departments;
CREATE POLICY "dept_insert_admin" ON departments
  FOR INSERT
  WITH CHECK (
    business_id IS NOT NULL
    AND fn_has_role_or_above(business_id, 'admin')
  );

-- Business admin can soft-delete (set is_active = false) their own departments
DROP POLICY IF EXISTS "dept_update_admin" ON departments;
CREATE POLICY "dept_update_admin" ON departments
  FOR UPDATE
  USING (
    business_id IS NOT NULL
    AND fn_has_role_or_above(business_id, 'admin')
  );

-- Superadmin can do everything (global + any business)
DROP POLICY IF EXISTS "dept_superadmin" ON departments;
CREATE POLICY "dept_superadmin" ON departments
  FOR ALL
  USING (fn_is_superadmin())
  WITH CHECK (fn_is_superadmin());

-- ── Seed global defaults (business_id = NULL) ─────────────────────────────────

INSERT INTO public.departments (name, business_id, created_by) VALUES
  ('Staff Land',  NULL, 'superadmin'),
  ('Staff Civil', NULL, 'superadmin'),
  ('Sales Man',   NULL, 'superadmin'),
  ('Supervisor',  NULL, 'superadmin')
ON CONFLICT (name, business_id) DO NOTHING;
