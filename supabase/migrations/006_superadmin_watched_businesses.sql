-- Super-admin business watch list
-- Stores which businesses a super-admin wants to receive notifications for,
-- and optionally until when (NULL = always watch).

CREATE TABLE IF NOT EXISTS public.superadmin_watched_businesses (
    id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    superadmin_uid  TEXT        NOT NULL,
    business_id     TEXT        NOT NULL,
    watch_until     TIMESTAMPTZ NULL,           -- NULL means watch always
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (superadmin_uid, business_id)
);

-- Row-level security
ALTER TABLE public.superadmin_watched_businesses ENABLE ROW LEVEL SECURITY;

-- Super-admin can manage their own watch list
-- Cast auth.uid() to text because superadmin_uid is stored as TEXT (Firebase UID format)
CREATE POLICY "superadmin_manage_own"
    ON public.superadmin_watched_businesses
    FOR ALL
    TO authenticated
    USING  (superadmin_uid = auth.uid()::text)
    WITH CHECK (superadmin_uid = auth.uid()::text);

-- Any authenticated user can READ the watch list
-- (needed so employee's device can check which super-admins to notify)
CREATE POLICY "authenticated_read"
    ON public.superadmin_watched_businesses
    FOR SELECT
    TO authenticated
    USING (true);
