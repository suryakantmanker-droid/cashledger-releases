-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 025 — Backfill business_members.role='owner' for real business owners
--
-- createBusiness() was incorrectly inserting the creator's business_members
-- row with role='admin' instead of 'owner'. This meant the "owner cannot be
-- removed/reverted" protection in removeAdmin/revertToPreviousRole never
-- matched the real owner — they could be (and were) removed like any other
-- admin via the Business Admins panel. Fixed going forward in
-- superadmin_datasource.dart; this backfills existing rows.
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════════

UPDATE business_members bm
SET role = 'owner', updated_at = NOW()
FROM businesses b
WHERE bm.business_id = b.id
  AND bm.user_uid = b.owner_uid
  AND bm.role = 'admin';
