-- ══════════════════════════════════════════════════════════════════════════════
-- MIGRATION 015 — Fresh Start: Supabase Native Auth
--
-- Run this in: Supabase Dashboard → SQL Editor
--
-- What this does:
--   1. Enables RLS on ALL tables (was Phase 1 — now safe since Supabase Auth)
--   2. Creates the notifications table (moved from Firestore)
--   3. Enables Realtime on notifications
--   4. Creates the first superadmin user row (run AFTER creating auth user)
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── STEP 1: Enable RLS on all remaining tables ────────────────────────────────
-- These were deferred (Phase 1) because Firebase JWT wasn't configured.
-- Now that Supabase Auth is used natively, auth.uid() works correctly.

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses  ENABLE ROW LEVEL SECURITY;
ALTER TABLE funds     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE users     ENABLE ROW LEVEL SECURITY;

-- ── STEP 2: Notifications table ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notifications (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     TEXT        NOT NULL,
  business_id TEXT        DEFAULT '',
  title       TEXT        NOT NULL,
  body        TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'general',
  data        JSONB       DEFAULT '{}',
  is_read     BOOLEAN     DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_user       ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notif_business   ON notifications (business_id);
CREATE INDEX IF NOT EXISTS idx_notif_created_at ON notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_unread     ON notifications (user_id, is_read)
  WHERE is_read = FALSE;

-- ── STEP 3: RLS on notifications ──────────────────────────────────────────────

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notif_select_own"  ON notifications;
DROP POLICY IF EXISTS "notif_insert_auth" ON notifications;
DROP POLICY IF EXISTS "notif_update_own"  ON notifications;

CREATE POLICY "notif_select_own" ON notifications
  FOR SELECT USING (user_id = auth.uid()::TEXT);

CREATE POLICY "notif_insert_auth" ON notifications
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "notif_update_own" ON notifications
  FOR UPDATE USING (user_id = auth.uid()::TEXT);

-- ── STEP 4: Enable Supabase Realtime on notifications ────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
END $$;

COMMIT;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 5: Create superadmin user row
--
-- Run this SEPARATELY after:
--   a) Go to Supabase Dashboard → Authentication → Users
--   b) Click "Add user" → enter your email + password → Create
--   c) Copy the UUID shown for that user
--   d) Paste it below replacing 'PASTE-YOUR-UUID-HERE'
-- ══════════════════════════════════════════════════════════════════════════════

-- INSERT INTO users (
--   uid, name, email, role, is_active, is_superadmin, created_at
-- ) VALUES (
--   'PASTE-YOUR-UUID-HERE',      -- UUID from Supabase Auth
--   'Super Admin',               -- your name
--   'your@email.com',            -- your email
--   'admin',
--   true,
--   true,
--   NOW()
-- )
-- ON CONFLICT (uid) DO UPDATE SET is_superadmin = true;
