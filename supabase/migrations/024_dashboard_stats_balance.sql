-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 024 — Add total_assigned/net_balance to fn_get_dashboard_stats
--
-- The admin dashboard's "Total Assigned" and "Net Balance" cards were
-- hardcoded to 0 on the Flutter side because this RPC never returned them
-- (see dashboard_stats.dart comments: "Phase 3: funds not yet migrated").
-- This adds the missing business-wide sums from the employees table.
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_get_dashboard_stats(p_business_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
  v_uid    TEXT := fn_current_user_uid();
BEGIN
  -- Enforce membership check when caller has a JWT (not anon key)
  IF v_uid IS NOT NULL AND NOT fn_is_member_of(p_business_id) THEN
    RAISE EXCEPTION
      'Access denied: % is not a member of business %.',
      v_uid, p_business_id
      USING ERRCODE = 'P0011';
  END IF;

  SELECT json_build_object(
    'total_employees',
      (SELECT COUNT(*) FROM employees
       WHERE business_id = p_business_id AND is_active = true),
    'total_expenses',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id),
    'pending_approvals',
      (SELECT COUNT(*) FROM expenses
       WHERE business_id = p_business_id AND status = 'pending'),
    'total_approved_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id AND status = 'approved'),
    'total_assigned',
      (SELECT COALESCE(SUM(total_assigned), 0) FROM employees
       WHERE business_id = p_business_id AND is_active = true),
    'net_balance',
      (SELECT COALESCE(SUM(balance), 0) FROM employees
       WHERE business_id = p_business_id AND is_active = true),
    'this_month_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id
         AND status = 'approved'
         AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())),
    'last_month_amount',
      (SELECT COALESCE(SUM(amount), 0) FROM expenses
       WHERE business_id = p_business_id
         AND status = 'approved'
         AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW() - INTERVAL '1 month')),
    'top_categories',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT category AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY category ORDER BY total DESC LIMIT 5
       ) t),
    'top_spenders',
      (SELECT COALESCE(json_agg(t), '[]'::json)
       FROM (
         SELECT submitted_by_name AS name, COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())
         GROUP  BY submitted_by_name ORDER BY total DESC LIMIT 5
       ) t),
    'monthly_trend',
      (SELECT COALESCE(json_agg(t ORDER BY t.month), '[]'::json)
       FROM (
         SELECT
           TO_CHAR(DATE_TRUNC('month', expense_date), 'Mon YYYY') AS month,
           COALESCE(SUM(amount), 0) AS total
         FROM   expenses
         WHERE  business_id = p_business_id AND status = 'approved'
           AND  expense_date >= NOW() - INTERVAL '6 months'
         GROUP  BY DATE_TRUNC('month', expense_date)
       ) t)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_get_dashboard_stats IS
  'Dashboard aggregates for a business. Membership-enforced when JWT is present. Adds total_assigned/net_balance (024).';
