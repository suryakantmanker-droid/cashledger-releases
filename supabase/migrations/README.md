# Phase 0 — Database Migration Guide

Multi-business schema migration for ExpenseTrack Pro.  
**Goal:** Lay the database foundation without breaking the live Flutter app.

---

## Files in this folder

| File | Purpose | When |
|------|---------|------|
| `001_initial_schema.sql` | **EXISTING** original schema (users, employees, expenses, funds, ledger + atomic functions) | Already ran |
| `001_create_role_enum.sql` | Creates `user_role` PostgreSQL enum | Phase 0 |
| `002_create_new_tables.sql` | New tables: businesses, business_members, expense_categories, salary_records, attendance | Phase 0 |
| `003_add_business_id_columns.sql` | Adds `business_id` (nullable) + supplementary columns to existing tables | Phase 0 |
| `004_backfill_default_business.sql` | Creates default business, assigns all rows, applies NOT NULL + DEFAULT | Phase 0 |
| `005_create_indexes.sql` | All performance indexes for business-scoped queries | Phase 0 |
| `006_create_updated_at_triggers.sql` | Auto-update `updated_at` triggers | Phase 0 |
| `007_create_helper_functions.sql` | RLS functions: `fn_is_member_of`, `fn_my_role_in`, `fn_has_role_or_above`, `fn_get_dashboard_stats`, etc. | Phase 0 |
| `008_create_rls_policies.sql` | RLS policies (enabled on new tables; PREPARED but not enabled on existing tables) | Phase 0 |
| `009_update_atomic_functions_phase1.sql` | Updates `approve_expense` + `transfer_fund` to accept `business_id` param | **Phase 1 only** |
| `ROLLBACK.sql` | Complete undo script (run sections in reverse order) | Emergency |
| `VERIFY.sql` | Post-migration verification queries (V1–V15) | After each step |

---

## Existing Schema Note

`001_initial_schema.sql` already ran (it was the original setup). It defines:
- Tables: `users`, `employees`, `expenses`, `funds`, `ledger`
- `employees.id TEXT` = Firebase Auth UID (the primary key **is** the Firebase UID)
- `employees.user_id TEXT` = secondary field (currently unused by Flutter models)
- Two atomic PostgreSQL functions: `approve_expense()` and `transfer_fund()`
- RLS explicitly **disabled** on all tables (`DISABLE ROW LEVEL SECURITY`)

The Phase 0 migrations extend this schema safely.

## Deployment Order

Run **one file at a time** in this exact order. Verify with `VERIFY.sql` between each step.

**Phase 0 (run now):**
```
001_create_role_enum  →  002_create_new_tables  →  003_add_business_id_columns
→  004_backfill_default_business  →  005_create_indexes
→  006_create_updated_at_triggers  →  007_create_helper_functions
→  008_create_rls_policies
```

**Phase 1 (run later, after Flutter update):**
```
009_update_atomic_functions_phase1
→  enable_rls_existing_tables (inline SQL in README)
→  remove DEFAULT from existing tables (inline SQL in README)
```

### Where to run

**Option A — Supabase Dashboard SQL Editor** (recommended for initial migration)
- Paste each file content → Run
- Check the output messages for `[00x]` NOTICE logs

**Option B — Supabase CLI**
```bash
supabase db push          # if using Supabase CLI migrations
# OR
psql $DATABASE_URL -f supabase/migrations/001_create_role_enum.sql
psql $DATABASE_URL -f supabase/migrations/002_create_new_tables.sql
# ... etc
```

---

## Safety Design

The migration is designed so the **live Flutter app keeps working at every step**:

| Migration | App impact |
|-----------|-----------|
| 001 | None — creates a new TYPE only |
| 002 | None — creates new tables the app doesn't use |
| 003 | None — adds nullable columns; existing SELECT/INSERT unaffected |
| 004 | None — backfills data; adds DEFAULT so existing INSERTs still work |
| 005 | None — indexes don't change data |
| 006 | None — triggers only affect UPDATE, no breaking change |
| 007 | None — creates functions; app doesn't call them yet |
| 008 | None — policies created; RLS NOT enabled on existing tables |

---

## Default Business

All existing data is migrated to a single "Default Business":

- **UUID:** `11111111-1111-1111-1111-111111111111`
- **Name:** Default Business
- **Plan:** pro
- **Owner:** First admin user in the `users` table

After Phase 1 (Flutter migration), you can rename this business to match your real business name via Supabase Dashboard or the new Business Settings screen.

---

## Firebase JWT Setup (Required Before Phase 1 RLS)

The RLS policies use `auth.uid()` to identify users. Since this app uses **Firebase Auth** (not Supabase Auth), you must configure Supabase to accept Firebase JWTs:

### Option A — signInWithIdToken (Recommended)

In Flutter, after Firebase login:

```dart
final firebaseUser = FirebaseAuth.instance.currentUser!;
final idToken = await firebaseUser.getIdToken();

await Supabase.instance.client.auth.signInWithIdToken(
  provider: OAuthProvider.google,  // or use custom provider
  idToken: idToken,
);
```

This creates a Supabase session linked to the Firebase UID.

### Option B — Firebase JWT Secret in Supabase Dashboard

1. Go to: Supabase Dashboard → Project Settings → API → JWT Settings
2. Set `JWT Secret` to your Firebase project's JWT verification key
3. Set `Issuer` to: `https://securetoken.google.com/YOUR_FIREBASE_PROJECT_ID`

---

## After Phase 0 — Enable RLS on Existing Tables (Phase 1)

Once Firebase JWT is configured and the Flutter app is updated, enable RLS on existing tables:

```sql
-- Run this in Phase 1 ONLY — NOT now
BEGIN;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses  ENABLE ROW LEVEL SECURITY;
ALTER TABLE funds     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE users     ENABLE ROW LEVEL SECURITY;
COMMIT;
```

---

## Remove Backward-Compat DEFAULT (After Phase 1 Flutter Deployment)

The `DEFAULT '11111111-...'` on existing tables is a temporary bridge for the live app.
After the Flutter app is fully migrated (Phase 1), remove these defaults:

```sql
-- Run AFTER Flutter Phase 1 is deployed and stable
BEGIN;
ALTER TABLE employees ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE expenses  ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE funds     ALTER COLUMN business_id DROP DEFAULT;
ALTER TABLE ledger    ALTER COLUMN business_id DROP DEFAULT;
COMMIT;
```

---

## Role Mapping

| Old role (app) | New role (multi-business) |
|---------------|--------------------------|
| `admin` | `admin` |
| `employee` | `employee` |
| anything else | `viewer` |

New roles available for assignment in Phase 1+:

| Role | Level | Can approve expenses | Can transfer funds | Can manage employees |
|------|-------|---------------------|-------------------|---------------------|
| owner | 50 | ✓ | ✓ | ✓ |
| admin | 40 | ✓ | ✓ | ✓ |
| manager | 30 | ✓ | ✓ | ✗ |
| accountant | 20 | ✓ | ✗ | ✗ |
| employee | 10 | ✗ | ✗ | ✗ |
| viewer | 0 | ✗ | ✗ | ✗ |

---

## Rollback

If anything goes wrong, run `ROLLBACK.sql` **one section at a time**, in reverse order (start from ROLLBACK 008 downward to 001). Each section is labelled with its migration number.

**Never run the full ROLLBACK.sql in one shot on production** — read each section first.

---

## Verification

After all 8 migrations, run `VERIFY.sql` in its entirety. All 15 checks should pass.

Key checks:
- V5: All NULL counts = 0 (no orphan rows)
- V6: `total = in_default` for all tables (100% backfilled)
- V10: RLS enabled only on new tables
- V12: `fn_role_level('admin') = 40`, `fn_role_level('owner') = 50`
