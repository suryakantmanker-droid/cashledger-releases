-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 023 — Track previous_role on business_members
--
-- Lets "Remove Admin" offer a "Revert to previous role" option instead of
-- only a full removal, by remembering the role a member held right before
-- being promoted to owner/admin. Cleared automatically once reverted.
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE business_members ADD COLUMN IF NOT EXISTS previous_role TEXT DEFAULT NULL;
