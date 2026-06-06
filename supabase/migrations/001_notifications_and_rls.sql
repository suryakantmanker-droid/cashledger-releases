-- ══════════════════════════════════════════════════════════════════════════
-- Migration: Move notifications from Firestore to Supabase
--            + Update RLS from Firebase JWT → Supabase Auth
--
-- Run this in: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. Notifications table ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     TEXT        NOT NULL,          -- matches users.uid (Supabase auth UUID)
  business_id TEXT        DEFAULT '',
  title       TEXT        NOT NULL,
  body        TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'general',
  data        JSONB       DEFAULT '{}',
  is_read     BOOLEAN     DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_id    ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_business   ON notifications (business_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread     ON notifications (user_id, is_read) WHERE is_read = FALSE;

-- ── 2. RLS on notifications ───────────────────────────────────────────────
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications"   ON notifications;
DROP POLICY IF EXISTS "Service role can insert"            ON notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON notifications;

-- Users can only read their own notifications
CREATE POLICY "Users can view own notifications" ON notifications
  FOR SELECT USING (user_id = auth.uid()::TEXT);

-- Any authenticated user can insert (admin sending to employee, etc.)
-- The service-role Edge Function bypasses RLS entirely
CREATE POLICY "Authenticated can insert notifications" ON notifications
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Users can mark their own notifications as read
CREATE POLICY "Users can update own notifications" ON notifications
  FOR UPDATE USING (user_id = auth.uid()::TEXT);

-- ── 3. Enable Supabase Realtime on notifications ──────────────────────────
-- Run this once to allow .stream() subscriptions in Flutter
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ── 4. RLS: update users table to use Supabase auth.uid() ─────────────────
-- If your users table RLS still references fn_current_user_uid() (Firebase),
-- drop that function and recreate policies with standard auth.uid().
--
-- IMPORTANT: Replace the policy names below with your actual policy names.
-- Check existing policies with:
--   SELECT policyname FROM pg_policies WHERE tablename = 'users';

-- Example — adjust policy names to match yours:
-- DROP POLICY IF EXISTS "Users can read own data"   ON users;
-- DROP POLICY IF EXISTS "Users can update own data" ON users;
-- DROP FUNCTION IF EXISTS fn_current_user_uid() CASCADE;
--
-- CREATE POLICY "Users can read own data" ON users
--   FOR SELECT USING (uid = auth.uid()::TEXT);
--
-- CREATE POLICY "Users can update own data" ON users
--   FOR UPDATE USING (uid = auth.uid()::TEXT);

-- ── 5. Verify ─────────────────────────────────────────────────────────────
-- After running, test with:
--   SELECT * FROM notifications LIMIT 5;
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'notifications';
