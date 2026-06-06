-- ============================================================
-- ExpenseTrack Pro — Supabase Schema
--
-- Firebase Auth  → kept for authentication
-- Firebase FCM   → kept for push notifications
-- Firestore      → kept ONLY for 'notifications' collection
-- Everything else → Supabase PostgreSQL (this file)
--
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── Tables ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.users (
  uid          TEXT PRIMARY KEY,
  name         TEXT NOT NULL DEFAULT '',
  email        TEXT NOT NULL DEFAULT '',
  role         TEXT NOT NULL DEFAULT 'employee',
  photo_url    TEXT,
  fcm_token    TEXT,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.employees (
  id                TEXT PRIMARY KEY,    -- same as Firebase UID
  employee_id       TEXT NOT NULL DEFAULT '',
  name              TEXT NOT NULL DEFAULT '',
  email             TEXT NOT NULL DEFAULT '',
  phone             TEXT NOT NULL DEFAULT '',
  department        TEXT NOT NULL DEFAULT '',
  profile_image_url TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  total_assigned    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_spent       NUMERIC(15,2) NOT NULL DEFAULT 0,
  balance           NUMERIC(15,2) NOT NULL DEFAULT 0,
  created_by        TEXT NOT NULL DEFAULT '',
  user_id           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.expenses (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id        TEXT NOT NULL DEFAULT '',
  title             TEXT NOT NULL DEFAULT '',
  amount            NUMERIC(15,2) NOT NULL DEFAULT 0,
  category          TEXT NOT NULL DEFAULT '',
  vendor_name       TEXT,
  description       TEXT,
  expense_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payment_method    TEXT NOT NULL DEFAULT '',
  bill_urls         TEXT[] NOT NULL DEFAULT '{}',
  status            TEXT NOT NULL DEFAULT 'pending',
  submitted_by      TEXT NOT NULL DEFAULT '',
  submitted_by_name TEXT NOT NULL DEFAULT '',
  approved_by       TEXT,
  approved_by_name  TEXT,
  rejection_reason  TEXT,
  approved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.funds (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id   TEXT NOT NULL DEFAULT '',
  amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  given_by      TEXT NOT NULL DEFAULT '',
  given_by_name TEXT NOT NULL DEFAULT '',
  given_to      TEXT NOT NULL DEFAULT '',
  given_to_name TEXT NOT NULL DEFAULT '',
  purpose       TEXT NOT NULL DEFAULT '',
  payment_mode  TEXT NOT NULL DEFAULT '',
  notes         TEXT,
  status        TEXT NOT NULL DEFAULT 'active',
  transfer_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ledger (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    TEXT NOT NULL DEFAULT '',
  employee_name  TEXT NOT NULL DEFAULT '',
  type           TEXT NOT NULL DEFAULT 'credit',   -- 'credit' | 'debit'
  amount         NUMERIC(15,2) NOT NULL DEFAULT 0,
  balance_after  NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks        TEXT NOT NULL DEFAULT '',
  reference_id   TEXT NOT NULL DEFAULT '',
  reference_type TEXT NOT NULL DEFAULT '',
  date           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_employees_user_id   ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS idx_expenses_submitted   ON public.expenses(submitted_by);
CREATE INDEX IF NOT EXISTS idx_expenses_status      ON public.expenses(status);
CREATE INDEX IF NOT EXISTS idx_expenses_created     ON public.expenses(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_funds_given_to       ON public.funds(given_to);
CREATE INDEX IF NOT EXISTS idx_funds_created        ON public.funds(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_employee      ON public.ledger(employee_id);
CREATE INDEX IF NOT EXISTS idx_ledger_created       ON public.ledger(created_at DESC);

-- ── Realtime (required for stream() in supabase_flutter) ─────────────────
-- Enable in Supabase Dashboard → Database → Replication → 0 tables
-- OR run these:

ALTER TABLE public.users     REPLICA IDENTITY FULL;
ALTER TABLE public.employees REPLICA IDENTITY FULL;
ALTER TABLE public.expenses  REPLICA IDENTITY FULL;
ALTER TABLE public.funds     REPLICA IDENTITY FULL;
ALTER TABLE public.ledger    REPLICA IDENTITY FULL;

-- Add tables to the realtime publication so stream() receives INSERT/UPDATE/DELETE events
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.employees;
ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE public.funds;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ledger;

-- ── Disable Row Level Security (allow anon key full access) ──────────────
ALTER TABLE public.users     DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses  DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.funds     DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger    DISABLE ROW LEVEL SECURITY;

-- ── PostgreSQL Function: approve_expense (atomic) ─────────────────────────
-- Atomically: updates expense status + deducts employee balance + creates ledger debit entry

CREATE OR REPLACE FUNCTION public.approve_expense(
  p_expense_id      UUID,
  p_approved_by     TEXT,
  p_approved_by_name TEXT
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_amount          NUMERIC;
  v_submitted_by    TEXT;
  v_submitted_by_name TEXT;
  v_title           TEXT;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  SELECT amount, submitted_by, submitted_by_name, title
  INTO   v_amount, v_submitted_by, v_submitted_by_name, v_title
  FROM   public.expenses
  WHERE  id = p_expense_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Expense not found: %', p_expense_id;
  END IF;

  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id = v_submitted_by;

  v_new_balance := v_current_balance - v_amount;

  -- 1. Update expense
  UPDATE public.expenses SET
    status           = 'approved',
    approved_by      = p_approved_by,
    approved_by_name = p_approved_by_name,
    approved_at      = v_now,
    updated_at       = v_now
  WHERE id = p_expense_id;

  -- 2. Deduct from employee balance
  UPDATE public.employees SET
    total_spent = total_spent + v_amount,
    balance     = balance - v_amount,
    updated_at  = v_now
  WHERE id = v_submitted_by;

  -- 3. Ledger debit entry
  INSERT INTO public.ledger (
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    v_submitted_by, v_submitted_by_name, 'debit', v_amount, v_new_balance,
    'Expense approved: ' || v_title,
    p_expense_id::TEXT, 'expense', v_now, v_now
  );
END;
$$;

-- ── PostgreSQL Function: transfer_fund (atomic) ───────────────────────────
-- Atomically: inserts fund record + credits employee balance + creates ledger credit entry

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
  p_transfer_date TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_fund_id         UUID;
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_now             TIMESTAMPTZ := NOW();
BEGIN
  SELECT balance INTO v_current_balance
  FROM   public.employees
  WHERE  id = p_given_to;

  v_new_balance := v_current_balance + p_amount;

  -- 1. Insert fund record
  INSERT INTO public.funds (
    transfer_id, amount, given_by, given_by_name,
    given_to, given_to_name, purpose, payment_mode,
    notes, status, transfer_date, created_at
  ) VALUES (
    p_transfer_id, p_amount, p_given_by, p_given_by_name,
    p_given_to, p_given_to_name, p_purpose, p_payment_mode,
    p_notes, p_status, p_transfer_date, v_now
  ) RETURNING id INTO v_fund_id;

  -- 2. Credit employee balance
  UPDATE public.employees SET
    total_assigned = total_assigned + p_amount,
    balance        = balance + p_amount,
    updated_at     = v_now
  WHERE id = p_given_to;

  -- 3. Ledger credit entry
  INSERT INTO public.ledger (
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, created_at
  ) VALUES (
    p_given_to, p_given_to_name, 'credit', p_amount, v_new_balance,
    'Fund received: ' || p_purpose,
    v_fund_id::TEXT, 'fund_transfer', p_transfer_date, v_now
  );

  RETURN v_fund_id;
END;
$$;
