-- =============================================================================
-- Migration 026 — Employee Sites (multi-location) + assignment history
--
-- sites: per-business named locations (name + address), managed like
-- departments but always business-scoped (no global/NULL concept).
--
-- employee_site_assignments: append-only history of which site an employee
-- was at and when. Client never writes to this table directly — all changes
-- go through fn_change_employee_site() so the close-old/open-new pair is
-- atomic and the table stays a clean audit trail.
-- =============================================================================

-- ── sites ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sites (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name        TEXT        NOT NULL,
  address     TEXT        NOT NULL DEFAULT '',
  created_by  TEXT        NOT NULL DEFAULT '',
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT sites_name_business_unique UNIQUE (name, business_id)
);

CREATE INDEX IF NOT EXISTS idx_sites_business ON sites (business_id);

ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sites_select" ON sites;
CREATE POLICY "sites_select" ON sites
  FOR SELECT
  USING (fn_is_member_of(business_id));

DROP POLICY IF EXISTS "sites_insert_admin" ON sites;
CREATE POLICY "sites_insert_admin" ON sites
  FOR INSERT
  WITH CHECK (fn_has_role_or_above(business_id, 'admin'));

DROP POLICY IF EXISTS "sites_update_admin" ON sites;
CREATE POLICY "sites_update_admin" ON sites
  FOR UPDATE
  USING (fn_has_role_or_above(business_id, 'admin'));

DROP POLICY IF EXISTS "sites_superadmin" ON sites;
CREATE POLICY "sites_superadmin" ON sites
  FOR ALL
  USING (fn_is_superadmin())
  WITH CHECK (fn_is_superadmin());

-- ── employee_site_assignments ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.employee_site_assignments (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id TEXT        NOT NULL,
  site_id     UUID        NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
  start_date  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date    TIMESTAMPTZ,
  assigned_by TEXT        NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_site_assignments_employee ON employee_site_assignments (employee_id);

ALTER TABLE public.employee_site_assignments ENABLE ROW LEVEL SECURITY;

-- Read-only for business members. No INSERT/UPDATE/DELETE policy for the
-- client — all writes happen inside fn_change_employee_site (SECURITY DEFINER).
DROP POLICY IF EXISTS "site_assignments_select" ON employee_site_assignments;
CREATE POLICY "site_assignments_select" ON employee_site_assignments
  FOR SELECT
  USING (fn_is_member_of(business_id));

DROP POLICY IF EXISTS "site_assignments_superadmin" ON employee_site_assignments;
CREATE POLICY "site_assignments_superadmin" ON employee_site_assignments
  FOR ALL
  USING (fn_is_superadmin())
  WITH CHECK (fn_is_superadmin());

-- ── fn_change_employee_site ──────────────────────────────────────────────────
-- Atomically closes the employee's current assignment (if any) and opens a
-- new one. Re-checks admin+ server-side regardless of client-side gating.

CREATE OR REPLACE FUNCTION public.fn_change_employee_site(
  p_employee_id TEXT,
  p_business_id UUID,
  p_new_site_id UUID,
  p_assigned_by TEXT
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    TEXT := fn_current_user_uid();
  v_new_id UUID;
  v_result JSON;
BEGIN
  IF v_uid IS NOT NULL AND NOT fn_has_role_or_above(p_business_id, 'admin') THEN
    RAISE EXCEPTION 'Access denied: % cannot change employee sites for business %.',
      v_uid, p_business_id
      USING ERRCODE = 'P0011';
  END IF;

  UPDATE employee_site_assignments
  SET    end_date = NOW()
  WHERE  employee_id = p_employee_id
    AND  business_id = p_business_id
    AND  end_date IS NULL;

  INSERT INTO employee_site_assignments (
    business_id, employee_id, site_id, start_date, end_date, assigned_by
  ) VALUES (
    p_business_id, p_employee_id, p_new_site_id, NOW(), NULL, p_assigned_by
  )
  RETURNING id INTO v_new_id;

  SELECT json_build_object(
    'id', v_new_id,
    'site_id', p_new_site_id,
    'start_date', NOW()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_change_employee_site IS
  'Atomically closes the current site assignment and opens a new one for an employee. Admin+ only.';
