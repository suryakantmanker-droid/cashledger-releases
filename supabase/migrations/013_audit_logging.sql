-- =============================================================================
-- MIGRATION 013 — Security Audit Logging
-- =============================================================================
-- Purpose  : Persistent audit trail for security-relevant events.
--            Records: cross-business access attempts, privilege escalation
--            attempts, financial reversals, and admin role changes.
--
--            Written to by SECURITY DEFINER functions — clients cannot
--            insert, update, or delete audit rows directly.
--
-- Safe     : IF NOT EXISTS + OR REPLACE — fully idempotent.
-- Rollback : See PHASE4_ROLLBACK.sql
-- Depends  : 012_enable_rls_existing_tables.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Audit log table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type   TEXT        NOT NULL,       -- see event type constants below
  severity     TEXT        NOT NULL DEFAULT 'info'
                             CHECK (severity IN ('info', 'warning', 'critical')),
  user_uid     TEXT,                       -- Firebase UID of the actor (NULL = anon)
  business_id  UUID,                       -- Business context (NULL = cross-business)
  table_name   TEXT,                       -- Table involved (NULL = RPC-level)
  operation    TEXT,                       -- SELECT / INSERT / UPDATE / DELETE / RPC
  target_id    TEXT,                       -- Row/entity ID that was targeted
  details      JSONB       NOT NULL DEFAULT '{}',
  ip_address   TEXT,                       -- From request.headers.x-forwarded-for
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.security_audit_log IS
  'Immutable security audit trail. Written by SECURITY DEFINER functions only.';

-- ── Audit log is append-only — enable RLS with strict read policy ─────────────

ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;

-- Admins can read audit logs for their own business
DROP POLICY IF EXISTS "audit_select_admin" ON security_audit_log;
CREATE POLICY "audit_select_admin" ON security_audit_log
  FOR SELECT
  USING (
    business_id IS NOT NULL
    AND fn_has_role_or_above(business_id, 'admin')
  );

-- No direct inserts from clients — only via fn_audit_log() SECURITY DEFINER
DROP POLICY IF EXISTS "audit_insert_never" ON security_audit_log;
CREATE POLICY "audit_insert_never" ON security_audit_log
  FOR INSERT WITH CHECK (false);

-- Immutable
DROP POLICY IF EXISTS "audit_update_never" ON security_audit_log;
CREATE POLICY "audit_update_never" ON security_audit_log
  FOR UPDATE USING (false);

DROP POLICY IF EXISTS "audit_delete_never" ON security_audit_log;
CREATE POLICY "audit_delete_never" ON security_audit_log
  FOR DELETE USING (false);

-- Indexes for audit log queries
CREATE INDEX IF NOT EXISTS idx_audit_business_time
  ON security_audit_log (business_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_user_time
  ON security_audit_log (user_uid, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_severity_time
  ON security_audit_log (severity, created_at DESC)
  WHERE severity IN ('warning', 'critical');


-- =============================================================================
-- 2. fn_audit_log() — SECURITY DEFINER audit writer
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_audit_log(
  p_event_type  TEXT,
  p_severity    TEXT DEFAULT 'info',
  p_business_id UUID DEFAULT NULL,
  p_table_name  TEXT DEFAULT NULL,
  p_operation   TEXT DEFAULT NULL,
  p_target_id   TEXT DEFAULT NULL,
  p_details     JSONB DEFAULT '{}'
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    event_type, severity, user_uid, business_id,
    table_name, operation, target_id, details,
    ip_address, created_at
  ) VALUES (
    p_event_type,
    p_severity,
    fn_current_user_uid(),
    p_business_id,
    p_table_name,
    p_operation,
    p_target_id,
    p_details,
    -- Extract real IP from Supabase request headers (best-effort)
    current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for',
    NOW()
  );
EXCEPTION WHEN OTHERS THEN
  -- Audit logging must never block the main operation
  NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_audit_log IS
  'Inserts an audit log entry. SECURITY DEFINER — clients cannot write audit rows directly.';


-- =============================================================================
-- 3. Audit triggers for high-risk events
-- =============================================================================

-- ── Trigger: business_members role changes ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_audit_member_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.role IS DISTINCT FROM NEW.role THEN
    PERFORM fn_audit_log(
      'member_role_changed',
      'warning',
      NEW.business_id,
      'business_members',
      'UPDATE',
      NEW.user_uid,
      jsonb_build_object(
        'old_role', OLD.role,
        'new_role', NEW.role,
        'changed_by', fn_current_user_uid()
      )
    );
  END IF;

  IF TG_OP = 'DELETE' THEN
    PERFORM fn_audit_log(
      'member_removed',
      'warning',
      OLD.business_id,
      'business_members',
      'DELETE',
      OLD.user_uid,
      jsonb_build_object('role', OLD.role, 'removed_by', fn_current_user_uid())
    );
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS audit_member_role_change ON business_members;
CREATE TRIGGER audit_member_role_change
  AFTER UPDATE OR DELETE ON business_members
  FOR EACH ROW EXECUTE FUNCTION trg_audit_member_role_change();


-- ── Trigger: fund reversals ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_audit_fund_cancelled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'active'
     AND NEW.status = 'cancelled' THEN
    PERFORM fn_audit_log(
      'fund_reversed',
      'warning',
      NEW.business_id,
      'funds',
      'UPDATE',
      NEW.id::TEXT,
      jsonb_build_object(
        'transfer_id', NEW.transfer_id,
        'amount', NEW.amount,
        'reversed_by', fn_current_user_uid()
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_fund_cancelled ON funds;
CREATE TRIGGER audit_fund_cancelled
  AFTER UPDATE ON funds
  FOR EACH ROW EXECUTE FUNCTION trg_audit_fund_cancelled();


-- ── Trigger: expense approval/rejection ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_audit_expense_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status IN ('pending', 'draft')
     AND NEW.status IN ('approved', 'rejected') THEN
    PERFORM fn_audit_log(
      'expense_' || NEW.status,
      'info',
      NEW.business_id,
      'expenses',
      'UPDATE',
      NEW.id::TEXT,
      jsonb_build_object(
        'amount', NEW.amount,
        'submitted_by', NEW.submitted_by,
        'decided_by', fn_current_user_uid()
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_expense_decision ON expenses;
CREATE TRIGGER audit_expense_decision
  AFTER UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION trg_audit_expense_decision();


-- =============================================================================
-- Verification
-- =============================================================================

DO $$
BEGIN
  ASSERT (SELECT COUNT(*) FROM pg_class WHERE relname = 'security_audit_log') = 1,
    'security_audit_log table not created';
  ASSERT (SELECT COUNT(*) FROM pg_proc WHERE proname = 'fn_audit_log') >= 1,
    'fn_audit_log function not created';
  RAISE NOTICE '[013] Audit logging table and triggers created successfully';
  RAISE NOTICE '[013] Audited events: member role changes, fund reversals, expense decisions';
END $$;

COMMIT;
