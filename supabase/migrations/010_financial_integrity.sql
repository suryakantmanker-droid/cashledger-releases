-- =============================================================================
-- MIGRATION 010 — Financial Integrity & Reversal Function
-- =============================================================================
-- Purpose  : Harden atomic functions with explicit cross-business guards and
--            add a fund-transfer reversal function for corrections.
--
-- When to run: Phase 3 — after 009 is already deployed.
-- Safe     : OR REPLACE — replaces existing functions in place.
-- Rollback : Re-run 009 to restore the previous versions.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Harden transfer_fund — explicit cross-business guard
-- ─────────────────────────────────────────────────────────────────────────────
-- The Phase 1 version used COALESCE(v_current_balance, 0) which silently
-- succeeded even when the employee did NOT belong to the business.
-- This version raises a clear exception when the recipient is not found.

CREATE OR REPLACE FUNCTION public.transfer_fund(
  p_transfer_id   TEXT,
  p_amount        NUMERIC,
  p_given_by      TEXT,
  p_given_by_name TEXT,
  p_given_to      TEXT,
  p_given_to_name TEXT,
  p_purpose       TEXT,
  p_payment_mode  TEXT,
  p_notes         TEXT,
  p_status        TEXT,
  p_transfer_date TIMESTAMPTZ,
  p_business_id   UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fund_id         UUID;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  -- ── Cross-business guard ────────────────────────────────────────────────
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = p_given_to
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Employee % does not belong to business %. Cross-business fund transfers are not permitted.',
      p_given_to, p_business_id
      USING ERRCODE = 'P0001';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Transfer amount must be positive. Got: %', p_amount
      USING ERRCODE = 'P0002';
  END IF;

  v_new_balance := v_current_balance + p_amount;

  -- 1. Insert fund record (business-scoped)
  INSERT INTO public.funds (
    business_id,
    transfer_id, amount, given_by, given_by_name,
    given_to, given_to_name, purpose, payment_mode,
    notes, status, transfer_date, created_at
  ) VALUES (
    p_business_id,
    p_transfer_id, p_amount, p_given_by, p_given_by_name,
    p_given_to, p_given_to_name, p_purpose, p_payment_mode,
    p_notes, p_status, p_transfer_date, v_now
  ) RETURNING id INTO v_fund_id;

  -- 2. Credit employee balance (business-scoped)
  UPDATE public.employees SET
    total_assigned = total_assigned + p_amount,
    balance        = balance + p_amount,
    updated_at     = v_now
  WHERE id          = p_given_to
    AND business_id = p_business_id;

  -- 3. Immutable ledger credit entry (business-scoped)
  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    p_given_to, p_given_to_name, 'credit', p_amount, v_new_balance,
    'Fund received: ' || p_purpose,
    v_fund_id::TEXT, 'fund_transfer', p_transfer_date, v_now
  );

  RETURN v_fund_id;
END;
$$;

COMMENT ON FUNCTION public.transfer_fund IS
  'Atomically transfers funds with cross-business guard. Raises P0001 if recipient not in business.';


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Harden approve_expense — explicit cross-business guard
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.approve_expense(
  p_expense_id        UUID,
  p_approved_by       TEXT,
  p_approved_by_name  TEXT,
  p_business_id       UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount            NUMERIC;
  v_submitted_by      TEXT;
  v_submitted_by_name TEXT;
  v_title             TEXT;
  v_current_balance   NUMERIC;
  v_new_balance       NUMERIC;
  v_now               TIMESTAMPTZ := NOW();
BEGIN
  -- ── Cross-business guard: expense must belong to this business ──────────
  SELECT amount, submitted_by, submitted_by_name, title
  INTO   v_amount, v_submitted_by, v_submitted_by_name, v_title
  FROM   public.expenses
  WHERE  id          = p_expense_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Expense % not found in business %. Cross-business approvals are not permitted.',
      p_expense_id, p_business_id
      USING ERRCODE = 'P0003';
  END IF;

  -- ── Fetch employee balance (employee must also belong to same business) ─
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = v_submitted_by
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Employee % for expense % not found in business %.',
      v_submitted_by, p_expense_id, p_business_id
      USING ERRCODE = 'P0004';
  END IF;

  v_new_balance := v_current_balance - v_amount;

  -- 1. Update expense status
  UPDATE public.expenses SET
    status           = 'approved',
    approved_by      = p_approved_by,
    approved_by_name = p_approved_by_name,
    approved_at      = v_now,
    updated_at       = v_now
  WHERE id          = p_expense_id
    AND business_id = p_business_id;

  -- 2. Deduct from employee balance
  UPDATE public.employees SET
    total_spent = total_spent + v_amount,
    balance     = balance - v_amount,
    updated_at  = v_now
  WHERE id          = v_submitted_by
    AND business_id = p_business_id;

  -- 3. Immutable ledger debit entry (business-scoped)
  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    v_submitted_by, v_submitted_by_name, 'debit', v_amount, v_new_balance,
    'Expense approved: ' || v_title,
    p_expense_id::TEXT, 'expense', v_now, v_now
  );
END;
$$;

COMMENT ON FUNCTION public.approve_expense IS
  'Atomically approves an expense with cross-business guard. Raises P0003/P0004 on cross-business attempt.';


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Reversal function — immutable double-entry correction
-- ─────────────────────────────────────────────────────────────────────────────
-- Ledger entries are NEVER updated or deleted.
-- Corrections use a reversal entry that creates an equal-and-opposite record.
--
-- This function:
--   1. Validates the original fund transfer belongs to the business
--   2. Creates an equal DEBIT ledger entry (reversal of the original CREDIT)
--   3. Deducts from employee balance and total_assigned
--   4. Marks the original fund record as 'cancelled'
--   5. Returns the reversal ledger entry ID
--
-- The original fund row and ledger entry are preserved for audit trail.

CREATE OR REPLACE FUNCTION public.reverse_fund_transfer(
  p_fund_id      UUID,
  p_reversed_by  TEXT,
  p_reason       TEXT,
  p_business_id  UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount          NUMERIC;
  v_employee_id     TEXT;
  v_employee_name   TEXT;
  v_transfer_id     TEXT;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_reversal_id     UUID;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  -- Fetch original fund transfer (must belong to same business)
  SELECT amount, given_to, given_to_name, transfer_id
  INTO   v_amount, v_employee_id, v_employee_name, v_transfer_id
  FROM   public.funds
  WHERE  id          = p_fund_id
    AND  business_id = p_business_id
    AND  status      = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Fund transfer % not found or already cancelled in business %.',
      p_fund_id, p_business_id
      USING ERRCODE = 'P0005';
  END IF;

  -- Current employee balance
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = v_employee_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee % not found in business %.', v_employee_id, p_business_id
      USING ERRCODE = 'P0006';
  END IF;

  IF v_current_balance < v_amount THEN
    RAISE EXCEPTION
      'Insufficient balance to reverse transfer. Balance: %, Reversal amount: %.',
      v_current_balance, v_amount
      USING ERRCODE = 'P0007';
  END IF;

  v_new_balance := v_current_balance - v_amount;

  -- 1. Immutable reversal DEBIT entry (equal-and-opposite to original credit)
  INSERT INTO public.ledger (
    business_id,
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_business_id,
    v_employee_id, v_employee_name, 'debit', v_amount, v_new_balance,
    'REVERSAL of fund ' || v_transfer_id || ': ' || p_reason,
    p_fund_id::TEXT, 'fund_reversal', v_now, v_now
  ) RETURNING id INTO v_reversal_id;

  -- 2. Adjust employee balance
  UPDATE public.employees SET
    total_assigned = total_assigned - v_amount,
    balance        = balance - v_amount,
    updated_at     = v_now
  WHERE id          = v_employee_id
    AND business_id = p_business_id;

  -- 3. Mark fund as cancelled (original row preserved for audit)
  UPDATE public.funds SET
    status     = 'cancelled',
    notes      = COALESCE(notes, '') || ' | REVERSED: ' || p_reason || ' by ' || p_reversed_by
  WHERE id          = p_fund_id
    AND business_id = p_business_id;

  RETURN v_reversal_id;
END;
$$;

COMMENT ON FUNCTION public.reverse_fund_transfer IS
  'Creates an immutable reversal ledger entry for a fund transfer. Original records preserved.';


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Helper: get_employee_balance — single-RPC balance check
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_employee_balance(
  p_employee_id TEXT,
  p_business_id UUID DEFAULT '11111111-1111-1111-1111-111111111111'::UUID
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance NUMERIC;
BEGIN
  SELECT balance INTO v_balance
  FROM   public.employees
  WHERE  id          = p_employee_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN RETURN 0; END IF;
  RETURN COALESCE(v_balance, 0);
END;
$$;

COMMENT ON FUNCTION public.get_employee_balance IS
  'Returns the current balance for an employee within a specific business. Returns 0 if not found.';


-- ─────────────────────────────────────────────────────────────────────────────
-- Verification
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  ASSERT (SELECT COUNT(*) FROM pg_proc WHERE proname = 'reverse_fund_transfer') = 1,
    'reverse_fund_transfer function not created';
  ASSERT (SELECT COUNT(*) FROM pg_proc WHERE proname = 'get_employee_balance') = 1,
    'get_employee_balance function not created';
  RAISE NOTICE 'Migration 010: All functions verified OK';
END $$;
