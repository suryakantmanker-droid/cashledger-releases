-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 016 — Add phone column to businesses table
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS phone TEXT DEFAULT '';
