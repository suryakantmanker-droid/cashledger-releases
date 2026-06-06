-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 017 — Add phone + address fields to users, employees, businesses
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── users table ───────────────────────────────────────────────────────────────
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone    TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS address  TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS city     TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS district TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS state    TEXT DEFAULT '';

-- ── employees table ───────────────────────────────────────────────────────────
ALTER TABLE employees ADD COLUMN IF NOT EXISTS address  TEXT DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS city     TEXT DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS district TEXT DEFAULT '';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS state    TEXT DEFAULT '';

-- ── businesses table ──────────────────────────────────────────────────────────
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS address  TEXT DEFAULT '';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS city     TEXT DEFAULT '';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS district TEXT DEFAULT '';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS state    TEXT DEFAULT '';

COMMIT;
