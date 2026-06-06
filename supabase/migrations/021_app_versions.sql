-- =============================================================================
-- Migration 021 — App Versions (Force Update Support)
--
-- Stores the latest app version info per platform.
-- The Flutter app reads this on every launch and compares with its own version.
-- If current < min_version  → force update (cannot skip)
-- If current < latest_version → optional update (can skip)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.app_versions (
  id             SERIAL        PRIMARY KEY,
  platform       TEXT          NOT NULL DEFAULT 'android',  -- 'android' | 'ios'
  latest_version TEXT          NOT NULL,                    -- e.g. '1.2.0'
  min_version    TEXT          NOT NULL,                    -- below this = force update
  apk_url        TEXT,                                      -- Supabase Storage public URL
  release_notes  TEXT          DEFAULT '',                  -- "What's new" text
  force_update   BOOLEAN       NOT NULL DEFAULT false,      -- true = always force regardless of version
  is_active      BOOLEAN       NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT app_versions_platform_key UNIQUE (platform)
);

-- Auto-update updated_at on row change
CREATE OR REPLACE TRIGGER app_versions_updated_at
  BEFORE UPDATE ON public.app_versions
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- RLS: public read (no auth needed — app checks version before login)
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_versions_read_public" ON public.app_versions;
CREATE POLICY "app_versions_read_public" ON public.app_versions
  FOR SELECT USING (true);

-- Only service role / superadmin can write
DROP POLICY IF EXISTS "app_versions_write_superadmin" ON public.app_versions;
CREATE POLICY "app_versions_write_superadmin" ON public.app_versions
  FOR ALL USING (fn_is_superadmin()) WITH CHECK (fn_is_superadmin());

-- Seed initial row for Android
-- Update latest_version and apk_url every time you release a new APK
INSERT INTO public.app_versions (platform, latest_version, min_version, apk_url, release_notes, force_update)
VALUES (
  'android',
  '1.0.0',       -- latest_version  → change this on every release
  '1.0.0',       -- min_version     → set lower to allow old versions
  '',            -- apk_url         → paste Supabase Storage public URL here
  'Initial release.',
  false
)
ON CONFLICT (platform) DO NOTHING;
