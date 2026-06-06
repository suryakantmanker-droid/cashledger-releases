-- =============================================================================
-- MIGRATION 009 — Update atomic functions for multi-business
-- =============================================================================
-- Purpose : Update approve_expense() and transfer_fund() to include business_id
--           in all their INSERT and UPDATE operations.
--
-- ⚠️  WHEN TO RUN — Phase 1 ONLY
-- ─────────────────────────────────────────────────────────────────────────────
-- DO NOT run this in Phase 0.
-- Run this in Phase 1, AFTER migration 004 has removed the DEFAULT on
-- ledger.business_id (once the Flutter app always supplies business_id).
--
-- Until Phase 1: the DEFAULT '11111111-...' on ledger.business_id ensures
-- the Phase 0 versions of these functions still insert correctly.
--
-- Safe    : OR REPLACE — replaces the existing functions in place.
-- Rollback: Re-run the original functions from 001_initial_schema.sql
-- Depends : 004_backfill_default_business.sql must have run first
-- =============================================================================

-- Drop old 3-arg signatures from 001_initial_schema.sql before replacing
DROP FUNCTION IF EXISTS public.approve_expense(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.transfer_fund(TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ);

-- ─────────────────────────────────────────────────────────────────────────────
-- approve_expense — Updated for multi-business
-- Adds p_business_id parameter so ledger entry is stamped with the correct business.
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
  -- Fetch expense details (scoped to business for safety)
  SELECT amount, submitted_by, submitted_by_name, title
  INTO   v_amount, v_submitted_by, v_submitted_by_name, v_title
  FROM   public.expenses
  WHERE  id          = p_expense_id
    AND  business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Expense % not found in business %', p_expense_id, p_business_id;
  END IF;

  -- Fetch employee balance (scoped to business)
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = v_submitted_by
    AND  business_id = p_business_id;

  v_new_balance := COALESCE(v_current_balance, 0) - v_amount;

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

COMMENT ON FUNCTION public.approve_expense(UUID, TEXT, TEXT, UUID) IS
  'Atomically approves an expense: updates status, deducts employee balance, creates ledger entry. Business-scoped.';

-- ─────────────────────────────────────────────────────────────────────────────
-- transfer_fund — Updated for multi-business
-- Adds p_business_id parameter so all rows are stamped with the correct business.
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- Fetch employee balance (scoped to business)
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id          = p_given_to
    AND  business_id = p_business_id;

  v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

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

  -- 2. Credit employee balance (scoped to business)
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

COMMENT ON FUNCTION public.transfer_fund(TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) IS
  'Atomically transfers funds: inserts fund record, credits employee balance, creates ledger entry. Business-scoped.';
