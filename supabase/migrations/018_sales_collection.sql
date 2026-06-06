-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 018: Sale Collection
-- Employees can log sale proceeds (scrap, surplus items, etc.) which are
-- instantly credited to their wallet — no admin approval required.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Table ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sales (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id         TEXT          NOT NULL,
  employee_id     TEXT          NOT NULL,
  employee_name   TEXT          NOT NULL,
  amount          NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  item_description TEXT         NOT NULL,
  buyer_name      TEXT,
  notes           TEXT,
  proof_urls      TEXT[]        NOT NULL DEFAULT '{}',
  sale_date       TIMESTAMPTZ   NOT NULL,
  business_id     UUID          NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS sales_business_id_idx    ON sales(business_id);
CREATE INDEX IF NOT EXISTS sales_employee_id_idx    ON sales(employee_id);
CREATE INDEX IF NOT EXISTS sales_sale_date_idx      ON sales(sale_date DESC);

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;

-- Admins see all sales in their business
CREATE POLICY "Admins can view all sales" ON sales
  FOR SELECT USING (
    business_id IN (
      SELECT business_id FROM business_members
      WHERE user_uid = auth.uid()::TEXT
        AND role IN ('admin','owner','manager','accountant','viewer')
    )
  );

-- Employees can only see their own sales
CREATE POLICY "Employees can view own sales" ON sales
  FOR SELECT USING (
    employee_id = auth.uid()::TEXT
  );

-- Employees can insert their own sales
CREATE POLICY "Employees can insert own sales" ON sales
  FOR INSERT WITH CHECK (
    employee_id = auth.uid()::TEXT AND
    business_id IN (
      SELECT business_id FROM business_members
      WHERE user_uid = auth.uid()::TEXT
    )
  );

-- ── Atomic RPC: log_sale_collection ──────────────────────────────────────────
-- Inserts the sale record, credits employee balance, and writes a ledger entry
-- in a single atomic transaction.
CREATE OR REPLACE FUNCTION log_sale_collection(
  p_sale_id         TEXT,
  p_amount          NUMERIC,
  p_employee_id     TEXT,
  p_employee_name   TEXT,
  p_item_description TEXT,
  p_buyer_name      TEXT,
  p_notes           TEXT,
  p_proof_urls      TEXT[],
  p_sale_date       TIMESTAMPTZ,
  p_business_id     UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale_uuid    UUID;
  v_new_balance  NUMERIC(15,2);
BEGIN
  -- 1. Insert sale record
  INSERT INTO sales (
    sale_id, employee_id, employee_name, amount,
    item_description, buyer_name, notes, proof_urls,
    sale_date, business_id
  ) VALUES (
    p_sale_id, p_employee_id, p_employee_name, p_amount,
    p_item_description, p_buyer_name, p_notes, COALESCE(p_proof_urls, '{}'),
    p_sale_date, p_business_id
  )
  RETURNING id INTO v_sale_uuid;

  -- 2. Credit employee balance
  UPDATE employees
  SET
    balance        = balance + p_amount,
    total_assigned = total_assigned + p_amount,
    updated_at     = NOW()
  WHERE id = p_employee_id AND business_id = p_business_id
  RETURNING balance INTO v_new_balance;

  IF v_new_balance IS NULL THEN
    RAISE EXCEPTION 'Employee % not found in business %', p_employee_id, p_business_id;
  END IF;

  -- 3. Write ledger CREDIT entry
  INSERT INTO ledger (
    employee_id, employee_name, type, amount, balance_after,
    remarks, reference_id, reference_type, date, business_id, created_at
  ) VALUES (
    p_employee_id, p_employee_name,
    'credit', p_amount, v_new_balance,
    'Sale collection: ' || p_item_description,
    v_sale_uuid::TEXT, 'sale_collection',
    p_sale_date, p_business_id, NOW()
  );

  RETURN v_sale_uuid;
END;
$$;
