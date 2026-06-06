# Multi-Business SaaS Architecture — ExpenseTrack Pro

> Generated for the existing Flutter + Firebase + Supabase codebase at D:\Flutter-radhe
> Current state: single-tenant (no businessId anywhere), roles: admin | employee only

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Database Schema — Supabase (PostgreSQL)](#2-database-schema--supabase-postgresql)
3. [Firestore Structure (Notifications)](#3-firestore-structure)
4. [Supabase Row Level Security (RLS)](#4-supabase-rls-policies)
5. [Updated Firestore Security Rules](#5-updated-firestore-security-rules)
6. [Flutter Folder Structure](#6-flutter-folder-structure)
7. [Role & Permission System](#7-role--permission-system)
8. [Auth Flow — Post Login](#8-auth-flow--post-login)
9. [Active Business Provider (Critical)](#9-active-business-provider)
10. [Repository Pattern](#10-repository-pattern)
11. [Key Models & Entities](#11-key-models--entities)
12. [Provider Structure](#12-provider-structure)
13. [Optimized Query Patterns](#13-optimized-query-patterns)
14. [Offline Sync Architecture](#14-offline-sync-architecture)
15. [Migration Strategy](#15-migration-strategy)
16. [What Can Break](#16-what-can-break)
17. [Production Best Practices](#17-production-best-practices)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SAAS PLATFORM                           │
├───────────────────┬─────────────────────┬───────────────────────┤
│   Business A      │    Business B        │    Business C         │
│   ─────────────   │   ─────────────      │   ─────────────       │
│   owner: U1       │   owner: U5          │   owner: U9           │
│   admin: U2       │   admin: U6          │   employees: U10-U15  │
│   employees: U3,4 │   employees: U7,U8   │                       │
├───────────────────┴─────────────────────┴───────────────────────┤
│              COMPLETE DATA ISOLATION via businessId             │
│              Supabase RLS enforces at database level            │
└─────────────────────────────────────────────────────────────────┘

Flutter App
├── Firebase Auth          (identity only)
├── Supabase PostgreSQL    (all business data + RLS)
├── Firestore             (real-time notifications — scoped to businessId)
├── Cloudinary            (file storage)
├── FCM                   (push notifications)
└── Hive                  (offline cache + sync queue)
```

**Key design decisions:**
- Supabase is the single source of truth for all business data
- RLS at the database level — app-side businessId filters are a UX convenience, not a security boundary
- Firestore is used ONLY for real-time notifications, nested under `businesses/{businessId}/`
- A user can belong to multiple businesses (business_members table)
- Active business is persisted in Hive and restored on app launch

---

## 2. Database Schema — Supabase (PostgreSQL)

### 2.1 businesses

```sql
CREATE TABLE businesses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  slug          TEXT UNIQUE NOT NULL,             -- URL-friendly, e.g. "acme-corp"
  logo_url      TEXT,
  owner_id      UUID NOT NULL REFERENCES auth.users(id),
  plan          TEXT NOT NULL DEFAULT 'free'
                  CHECK (plan IN ('free', 'starter', 'pro', 'enterprise')),
  max_employees INTEGER NOT NULL DEFAULT 10,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  settings      JSONB NOT NULL DEFAULT '{}',      -- timezone, currency, fiscal year start
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_businesses_owner ON businesses(owner_id);
```

### 2.2 user_profiles

```sql
-- Global profile (not per-business). One row per Firebase Auth user.
CREATE TABLE user_profiles (
  id          UUID PRIMARY KEY,                   -- matches Firebase Auth UID
  name        TEXT NOT NULL,
  email       TEXT NOT NULL UNIQUE,
  phone       TEXT,
  photo_url   TEXT,
  fcm_token   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 2.3 business_members (replaces old `users` role field)

```sql
CREATE TABLE business_members (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id),
  role         TEXT NOT NULL
                 CHECK (role IN ('owner','admin','manager','accountant','employee','viewer')),
  is_active    BOOLEAN NOT NULL DEFAULT true,
  invited_by   UUID REFERENCES auth.users(id),
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, user_id)
);

CREATE INDEX idx_members_user    ON business_members(user_id);
CREATE INDEX idx_members_business ON business_members(business_id);
```

### 2.4 employees

```sql
CREATE TABLE employees (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id       UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id           UUID REFERENCES auth.users(id),    -- null until they register
  employee_code     TEXT NOT NULL,
  name              TEXT NOT NULL,
  email             TEXT NOT NULL,
  phone             TEXT,
  department        TEXT,
  designation       TEXT,
  profile_image_url TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  -- financial snapshot (updated via triggers/functions)
  salary            NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_assigned    NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_spent       NUMERIC(14,2) NOT NULL DEFAULT 0,
  balance           NUMERIC(14,2) NOT NULL DEFAULT 0,
  -- metadata
  created_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, email),
  UNIQUE(business_id, employee_code)
);

CREATE INDEX idx_employees_business ON employees(business_id);
CREATE INDEX idx_employees_user     ON employees(user_id);
```

### 2.5 expenses

```sql
CREATE TABLE expenses (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id      UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  expense_code     TEXT NOT NULL,
  title            TEXT NOT NULL,
  amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  category_id      UUID REFERENCES expense_categories(id),
  category_name    TEXT NOT NULL,                -- denormalized for reports
  vendor_name      TEXT,
  description      TEXT,
  expense_date     DATE NOT NULL,
  payment_method   TEXT NOT NULL,
  bill_urls        TEXT[] NOT NULL DEFAULT '{}',
  status           TEXT NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','pending','approved','rejected','cancelled')),
  -- submission
  submitted_by      UUID NOT NULL REFERENCES auth.users(id),
  submitted_by_name TEXT NOT NULL,
  submitted_at      TIMESTAMPTZ,
  -- approval
  approved_by       UUID REFERENCES auth.users(id),
  approved_by_name  TEXT,
  approved_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  -- recurring
  is_recurring         BOOLEAN NOT NULL DEFAULT false,
  recurrence_pattern   TEXT CHECK (recurrence_pattern IN ('daily','weekly','monthly','yearly')),
  recurrence_end_date  DATE,
  parent_expense_id    UUID REFERENCES expenses(id),   -- for generated recurring copies
  -- audit trail (append-only JSONB arrays)
  edit_history   JSONB NOT NULL DEFAULT '[]',
  comments       JSONB NOT NULL DEFAULT '[]',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, expense_code)
);

CREATE INDEX idx_expenses_business   ON expenses(business_id);
CREATE INDEX idx_expenses_submitted  ON expenses(business_id, submitted_by);
CREATE INDEX idx_expenses_status     ON expenses(business_id, status);
CREATE INDEX idx_expenses_date       ON expenses(business_id, expense_date DESC);
CREATE INDEX idx_expenses_category   ON expenses(business_id, category_name);
```

### 2.6 funds

```sql
CREATE TABLE funds (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id     UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  transfer_code   TEXT NOT NULL,
  amount          NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  given_by        UUID NOT NULL REFERENCES auth.users(id),
  given_by_name   TEXT NOT NULL,
  given_to        UUID NOT NULL REFERENCES auth.users(id),
  given_to_name   TEXT NOT NULL,
  given_to_employee_id UUID REFERENCES employees(id),
  purpose         TEXT NOT NULL,
  payment_mode    TEXT NOT NULL,
  notes           TEXT,
  status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','completed','cancelled')),
  transfer_date   DATE NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, transfer_code)
);

CREATE INDEX idx_funds_business  ON funds(business_id);
CREATE INDEX idx_funds_given_to  ON funds(business_id, given_to);
```

### 2.7 ledger

```sql
-- Immutable. Never UPDATE or DELETE.
CREATE TABLE ledger (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id      UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id      UUID NOT NULL REFERENCES employees(id),
  employee_name    TEXT NOT NULL,
  type             TEXT NOT NULL CHECK (type IN ('credit','debit')),
  amount           NUMERIC(14,2) NOT NULL,
  balance_after    NUMERIC(14,2) NOT NULL,
  remarks          TEXT,
  reference_id     UUID,
  reference_type   TEXT CHECK (reference_type IN (
                     'fund_transfer','expense','salary','advance','deduction')),
  date             DATE NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ledger_business  ON ledger(business_id);
CREATE INDEX idx_ledger_employee  ON ledger(business_id, employee_id);
CREATE INDEX idx_ledger_date      ON ledger(business_id, date DESC);
```

### 2.8 expense_categories (customizable per business)

```sql
CREATE TABLE expense_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  icon        TEXT,
  color       TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, name)
);
```

### 2.9 salary_records

```sql
CREATE TABLE salary_records (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id),
  month       SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
  year        SMALLINT NOT NULL,
  base_salary NUMERIC(14,2) NOT NULL,
  advances    NUMERIC(14,2) NOT NULL DEFAULT 0,
  deductions  NUMERIC(14,2) NOT NULL DEFAULT 0,
  net_salary  NUMERIC(14,2) NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid')),
  paid_at     TIMESTAMPTZ,
  paid_by     UUID REFERENCES auth.users(id),
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, employee_id, month, year)
);

CREATE INDEX idx_salary_business  ON salary_records(business_id);
CREATE INDEX idx_salary_employee  ON salary_records(business_id, employee_id);
```

### 2.10 attendance

```sql
CREATE TABLE attendance (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id),
  date        DATE NOT NULL,
  status      TEXT NOT NULL
                CHECK (status IN ('present','absent','half_day','holiday','leave')),
  check_in    TIMESTAMPTZ,
  check_out   TIMESTAMPTZ,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(business_id, employee_id, date)
);

CREATE INDEX idx_attendance_business  ON attendance(business_id);
CREATE INDEX idx_attendance_employee  ON attendance(business_id, employee_id);
```

### 2.11 sync_queue (offline support)

```sql
-- Used by the Flutter app to track pending offline mutations
CREATE TABLE sync_queue (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id  UUID NOT NULL REFERENCES businesses(id),
  user_id      UUID NOT NULL REFERENCES auth.users(id),
  operation    TEXT NOT NULL CHECK (operation IN ('insert','update','delete')),
  table_name   TEXT NOT NULL,
  payload      JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  synced_at    TIMESTAMPTZ
);
```

---

## 3. Firestore Structure

Firestore is used ONLY for real-time notifications. All other data lives in Supabase.

```
businesses/
  {businessId}/
    notifications/
      {notificationId}
        userId        : string   (Firebase Auth UID)
        title         : string
        body          : string
        type          : string   ('expense_approved' | 'expense_rejected' |
                                  'fund_transferred' | 'low_balance' |
                                  'salary_paid' | 'pending_approval')
        data          : map      (referenceId, referenceType, etc.)
        isRead        : boolean
        createdAt     : timestamp

    settings/
      {docId}
        ...business notification settings
```

**Why nested under businesses/{businessId}?**
- Security rules can check `businessId` from the path — no data field needed
- Queries are scoped to one business automatically
- Easy to delete all business data if a business is removed

---

## 4. Supabase RLS Policies

### 4.1 Helper SQL Functions

```sql
-- Returns the businessId the current request belongs to (set via app header or JWT claim)
-- Best approach: embed businessId in Supabase JWT custom claims
CREATE OR REPLACE FUNCTION current_business_id()
RETURNS UUID AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'business_id', '')::UUID;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Check if current user is a member of the given business
CREATE OR REPLACE FUNCTION is_member_of(bid UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members
    WHERE business_id = bid
      AND user_id = auth.uid()
      AND is_active = true
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Get current user's role in the active business
CREATE OR REPLACE FUNCTION my_role_in(bid UUID)
RETURNS TEXT AS $$
  SELECT role FROM business_members
  WHERE business_id = bid
    AND user_id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Role hierarchy check
CREATE OR REPLACE FUNCTION has_role_or_above(bid UUID, min_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  role_order TEXT[] := ARRAY['viewer','employee','accountant','manager','admin','owner'];
  user_role TEXT := my_role_in(bid);
BEGIN
  RETURN array_position(role_order, user_role) >=
         array_position(role_order, min_role);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
```

### 4.2 businesses RLS

```sql
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_read_own_business" ON businesses
  FOR SELECT USING (is_member_of(id));

CREATE POLICY "owner_can_update_business" ON businesses
  FOR UPDATE USING (owner_id = auth.uid());

CREATE POLICY "authenticated_can_create_business" ON businesses
  FOR INSERT WITH CHECK (owner_id = auth.uid() AND auth.uid() IS NOT NULL);
```

### 4.3 employees RLS

```sql
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- All members can read employees of their business
CREATE POLICY "members_read_employees" ON employees
  FOR SELECT USING (is_member_of(business_id));

-- Admin and above can insert/update
CREATE POLICY "admins_manage_employees" ON employees
  FOR INSERT WITH CHECK (
    is_member_of(business_id) AND has_role_or_above(business_id, 'admin')
  );

CREATE POLICY "admins_update_employees" ON employees
  FOR UPDATE USING (
    is_member_of(business_id) AND (
      has_role_or_above(business_id, 'admin')
      OR user_id = auth.uid()   -- employee can update own safe fields
    )
  );

CREATE POLICY "owner_delete_employee" ON employees
  FOR DELETE USING (has_role_or_above(business_id, 'owner'));
```

### 4.4 expenses RLS

```sql
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

-- Read: member of business. Employees see only own; managers+ see all.
CREATE POLICY "expenses_select" ON expenses
  FOR SELECT USING (
    is_member_of(business_id) AND (
      submitted_by = auth.uid()
      OR has_role_or_above(business_id, 'accountant')
    )
  );

-- Insert: any active member (not viewer)
CREATE POLICY "expenses_insert" ON expenses
  FOR INSERT WITH CHECK (
    is_member_of(business_id)
    AND has_role_or_above(business_id, 'employee')
    AND submitted_by = auth.uid()
  );

-- Update: own draft/pending, or accountant+ for approval
CREATE POLICY "expenses_update" ON expenses
  FOR UPDATE USING (
    is_member_of(business_id) AND (
      (submitted_by = auth.uid() AND status IN ('draft','pending'))
      OR has_role_or_above(business_id, 'accountant')
    )
  );

-- Delete: only drafts by submitter or admin+
CREATE POLICY "expenses_delete" ON expenses
  FOR DELETE USING (
    is_member_of(business_id) AND (
      (submitted_by = auth.uid() AND status = 'draft')
      OR has_role_or_above(business_id, 'admin')
    )
  );
```

### 4.5 ledger RLS

```sql
ALTER TABLE ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ledger_select" ON ledger
  FOR SELECT USING (
    is_member_of(business_id) AND (
      employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid())
      OR has_role_or_above(business_id, 'accountant')
    )
  );

-- Insert only via server functions / Edge Functions (service role key)
-- App users never insert directly
CREATE POLICY "ledger_insert" ON ledger
  FOR INSERT WITH CHECK (false);  -- blocked at app level; use service role in Edge Functions

-- No updates or deletes — immutable
CREATE POLICY "ledger_no_update" ON ledger FOR UPDATE USING (false);
CREATE POLICY "ledger_no_delete" ON ledger FOR DELETE USING (false);
```

### 4.6 funds RLS

```sql
ALTER TABLE funds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "funds_select" ON funds
  FOR SELECT USING (
    is_member_of(business_id) AND (
      given_to = auth.uid()
      OR has_role_or_above(business_id, 'accountant')
    )
  );

CREATE POLICY "funds_insert" ON funds
  FOR INSERT WITH CHECK (
    is_member_of(business_id) AND has_role_or_above(business_id, 'manager')
  );

CREATE POLICY "funds_update" ON funds
  FOR UPDATE USING (
    is_member_of(business_id) AND has_role_or_above(business_id, 'manager')
  );

CREATE POLICY "funds_no_delete" ON funds FOR DELETE USING (false);
```

---

## 5. Updated Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuth() {
      return request.auth != null;
    }

    // Check Supabase JWT custom claim (set during login via Edge Function)
    function claimedBusiness(businessId) {
      return isAuth() &&
        request.auth.token.get('business_id', '') == businessId;
    }

    function claimedRole() {
      return request.auth.token.get('role', 'viewer');
    }

    function isAdminLike() {
      return claimedRole() in ['owner', 'admin', 'manager', 'accountant'];
    }

    match /businesses/{businessId} {

      // Notifications — scoped to the business path
      match /notifications/{notifId} {
        allow read: if isAuth() &&
          claimedBusiness(businessId) &&
          resource.data.userId == request.auth.uid;

        allow create: if isAuth() && claimedBusiness(businessId);

        allow update: if isAuth() &&
          claimedBusiness(businessId) &&
          resource.data.userId == request.auth.uid &&
          request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isRead']);

        allow delete: if isAuth() &&
          claimedBusiness(businessId) &&
          isAdminLike();
      }

      match /settings/{docId} {
        allow read:  if isAuth() && claimedBusiness(businessId);
        allow write: if isAuth() && claimedBusiness(businessId) &&
          claimedRole() in ['owner', 'admin'];
      }
    }

    // Deny everything else
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## 6. Flutter Folder Structure

```
lib/
├── main.dart
├── app.dart
│
├── core/
│   ├── constants/
│   │   ├── app_constants.dart          (extend with new roles, statuses)
│   │   ├── route_constants.dart
│   │   ├── supabase_tables.dart        (NEW — all table name constants)
│   │   └── permission_matrix.dart      (NEW — role → permission map)
│   │
│   ├── di/                             (NEW)
│   │   └── providers.dart              (top-level Riverpod providers for services)
│   │
│   ├── errors/
│   │   ├── failures.dart               (add BusinessFailure, PermissionFailure)
│   │   └── exceptions.dart
│   │
│   ├── extensions/                     (NEW)
│   │   ├── string_ext.dart
│   │   ├── datetime_ext.dart
│   │   └── role_ext.dart               (UserRole extension methods)
│   │
│   ├── guards/                         (NEW)
│   │   ├── role_guard.dart
│   │   └── business_guard.dart
│   │
│   ├── network/
│   │   └── network_info.dart
│   │
│   ├── router/
│   │   ├── app_router.dart             (extend with business routes)
│   │   └── router_notifier.dart
│   │
│   ├── services/
│   │   ├── firebase_service.dart
│   │   ├── supabase_service.dart
│   │   ├── storage_service.dart
│   │   ├── notification_service.dart   (update Firestore path to nested)
│   │   ├── sync_service.dart           (NEW — offline queue processor)
│   │   └── hive_service.dart           (NEW — wraps all Hive box operations)
│   │
│   ├── theme/
│   ├── utils/
│   └── widgets/
│
├── features/
│   │
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── auth_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   └── user_model.dart         (add businessId, role fields)
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── user_entity.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── login_usecase.dart
│   │   │       ├── logout_usecase.dart
│   │   │       └── get_current_user_usecase.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       ├── widgets/
│   │       └── providers/
│   │           └── auth_provider.dart
│   │
│   ├── business/                           (NEW — core feature)
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── business_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   ├── business_model.dart
│   │   │   │   └── business_member_model.dart
│   │   │   └── repositories/
│   │   │       └── business_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── business_entity.dart
│   │   │   │   └── business_member_entity.dart
│   │   │   ├── repositories/
│   │   │   │   └── business_repository.dart
│   │   │   └── usecases/
│   │   │       ├── create_business_usecase.dart
│   │   │       ├── get_user_businesses_usecase.dart
│   │   │       ├── switch_business_usecase.dart
│   │   │       ├── invite_member_usecase.dart
│   │   │       └── update_member_role_usecase.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── create_business_screen.dart
│   │       │   ├── business_selector_screen.dart
│   │       │   └── business_settings_screen.dart
│   │       ├── widgets/
│   │       │   └── business_switcher_widget.dart
│   │       └── providers/
│   │           └── business_provider.dart
│   │
│   ├── dashboard/
│   │   ├── data/ domain/ presentation/     (update all queries to include businessId)
│   │
│   ├── employees/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── employee_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   └── employee_model.dart     (add businessId, designation, salary)
│   │   │   └── repositories/
│   │   │       └── employee_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── employee_entity.dart
│   │   │   ├── repositories/
│   │   │   │   └── employee_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_employees_usecase.dart
│   │   │       ├── add_employee_usecase.dart
│   │   │       ├── update_employee_usecase.dart
│   │   │       └── deactivate_employee_usecase.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       ├── widgets/
│   │       └── providers/
│   │
│   ├── expenses/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── expense_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   └── expense_model.dart      (add businessId, categoryId, editHistory, comments)
│   │   │   └── repositories/
│   │   │       └── expense_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── expense_entity.dart
│   │   │   │   ├── expense_comment_entity.dart  (NEW)
│   │   │   │   └── edit_history_entity.dart     (NEW)
│   │   │   ├── repositories/
│   │   │   │   └── expense_repository.dart
│   │   │   └── usecases/
│   │   │       ├── submit_expense_usecase.dart
│   │   │       ├── approve_expense_usecase.dart
│   │   │       ├── reject_expense_usecase.dart
│   │   │       ├── add_comment_usecase.dart     (NEW)
│   │   │       └── get_expenses_usecase.dart
│   │   └── presentation/
│   │       ├── screens/
│   │       ├── widgets/
│   │       └── providers/
│   │
│   ├── funds/
│   ├── ledger/
│   ├── approval/
│   ├── notifications/
│   ├── reports/
│   │
│   ├── salary/                             (NEW)
│   │   ├── data/ domain/ presentation/
│   │
│   ├── attendance/                         (NEW)
│   │   ├── data/ domain/ presentation/
│   │
│   └── settings/                           (NEW)
│       ├── data/ domain/ presentation/
│
└── shared/
    ├── models/
    ├── providers/
    │   ├── active_business_provider.dart   (NEW — critical)
    │   ├── permissions_provider.dart       (NEW)
    │   └── current_user_role_provider.dart (NEW)
    └── widgets/
        ├── role_guard_widget.dart          (NEW)
        └── business_aware_widget.dart      (NEW)
```

---

## 7. Role & Permission System

### UserRole enum

```dart
// core/constants/permission_matrix.dart

enum UserRole {
  owner,
  admin,
  manager,
  accountant,
  employee,
  viewer;

  static UserRole fromString(String value) =>
      UserRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => UserRole.viewer,
      );

  // Hierarchy index (higher = more privileged)
  int get level => switch (this) {
    UserRole.owner       => 5,
    UserRole.admin       => 4,
    UserRole.manager     => 3,
    UserRole.accountant  => 2,
    UserRole.employee    => 1,
    UserRole.viewer      => 0,
  };

  bool isAtLeast(UserRole other) => level >= other.level;
}

// Permission matrix
extension UserRolePermissions on UserRole {
  bool get canApproveExpenses  => isAtLeast(UserRole.accountant);
  bool get canTransferFunds    => isAtLeast(UserRole.manager);
  bool get canManageEmployees  => isAtLeast(UserRole.admin);
  bool get canViewAllExpenses  => isAtLeast(UserRole.accountant);
  bool get canViewReports      => isAtLeast(UserRole.accountant);
  bool get canManageSalary     => isAtLeast(UserRole.manager);
  bool get canInviteMembers    => isAtLeast(UserRole.admin);
  bool get canManageBusiness   => this == UserRole.owner;
  bool get canSubmitExpenses   => isAtLeast(UserRole.employee);
  bool get canViewOwnData      => isAtLeast(UserRole.employee);
  bool get isAdminLike         => isAtLeast(UserRole.admin);
}
```

### Route Guard Widget

```dart
// shared/widgets/role_guard_widget.dart

class RoleGuard extends ConsumerWidget {
  final UserRole minimumRole;
  final Widget child;
  final Widget? fallback;

  const RoleGuard({
    required this.minimumRole,
    required this.child,
    this.fallback,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);
    if (role.isAtLeast(minimumRole)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
```

### Router Role Guard

```dart
// core/guards/role_guard.dart

String? roleGuard(WidgetRef ref, UserRole required) {
  final role = ref.read(currentUserRoleProvider);
  if (!role.isAtLeast(required)) return Routes.unauthorized;
  return null;
}
```

---

## 8. Auth Flow — Post Login

```dart
// Sequence after Firebase Auth returns a user:
//
// 1. Fetch user_profiles row from Supabase (create if first login)
// 2. Fetch business_members rows for this user_id
// 3. If no memberships → navigate to /create-business
// 4. Restore last active businessId from Hive
// 5. Load that business's member record → get role
// 6. Inject (businessId, role) into Supabase JWT via Edge Function OR store in provider
// 7. Navigate to role-appropriate shell

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepo;
  final BusinessRepository _businessRepo;
  final HiveService _hive;
  final Ref _ref;

  Future<void> handlePostLogin(User firebaseUser) async {
    state = state.copyWith(isLoading: true);

    // Step 1: upsert user profile
    final profile = await _authRepo.upsertProfile(firebaseUser);

    // Step 2: fetch all business memberships
    final memberships = await _businessRepo.getMembershipsForUser(firebaseUser.uid);

    if (memberships.isEmpty) {
      state = state.copyWith(isLoading: false, needsBusinessSetup: true);
      return;
    }

    // Step 3: restore or default active business
    final savedId = _hive.getActiveBusinessId();
    final activeMembership = memberships.firstWhere(
      (m) => m.businessId == savedId,
      orElse: () => memberships.first,
    );

    // Step 4: store in providers
    _ref.read(activeBusinessProvider.notifier).set(activeMembership);

    // Step 5: update Supabase session with businessId claim (via Edge Function)
    await _authRepo.refreshSessionWithBusiness(activeMembership.businessId);

    state = state.copyWith(
      isLoading: false,
      user: profile,
      activeMembership: activeMembership,
    );
  }
}
```

---

## 9. Active Business Provider

This is the **single most critical piece** of the multi-business architecture.
Every repository and every query reads `activeBusinessId` from this provider.

```dart
// shared/providers/active_business_provider.dart

@Riverpod(keepAlive: true)
class ActiveBusiness extends _$ActiveBusiness {
  @override
  BusinessMemberEntity? build() => null;

  void set(BusinessMemberEntity membership) {
    state = membership;
    ref.read(hiveServiceProvider).saveActiveBusinessId(membership.businessId);
  }

  Future<void> switchTo(String businessId) async {
    final memberships = await ref.read(userMembershipsProvider.future);
    final target = memberships.firstWhere((m) => m.businessId == businessId);
    set(target);

    // Invalidate all business-scoped providers
    ref.invalidate(employeesProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(fundsProvider);
    ref.invalidate(ledgerProvider);
    ref.invalidate(dashboardStatsProvider);
  }

  void clear() {
    state = null;
    ref.read(hiveServiceProvider).clearActiveBusinessId();
  }
}

// Convenient accessor used everywhere
@Riverpod(keepAlive: true)
String activeBusinessId(ActiveBusinessIdRef ref) {
  final membership = ref.watch(activeBusinessProvider);
  if (membership == null) throw Exception('No active business');
  return membership.businessId;
}

@Riverpod(keepAlive: true)
UserRole currentUserRole(CurrentUserRoleRef ref) {
  final membership = ref.watch(activeBusinessProvider);
  return UserRole.fromString(membership?.role ?? 'viewer');
}
```

---

## 10. Repository Pattern

### Abstract Repository (Domain Layer)

```dart
// features/expenses/domain/repositories/expense_repository.dart

abstract class ExpenseRepository {
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    required String businessId,
    String? status,
    String? submittedBy,
    DateTimeRange? dateRange,
    int page = 0,
  });

  Future<Either<Failure, ExpenseEntity>> getExpenseById(String id);

  Future<Either<Failure, String>> createExpense(ExpenseEntity expense);

  Future<Either<Failure, void>> updateExpense(ExpenseEntity expense);

  Future<Either<Failure, void>> approveExpense({
    required String expenseId,
    required String approvedBy,
    required String approvedByName,
  });

  Future<Either<Failure, void>> rejectExpense({
    required String expenseId,
    required String rejectionReason,
    required String rejectedBy,
  });

  Future<Either<Failure, void>> addComment({
    required String expenseId,
    required ExpenseComment comment,
  });
}
```

### Repository Implementation (Data Layer)

```dart
// features/expenses/data/repositories/expense_repository_impl.dart

class ExpenseRepositoryImpl implements ExpenseRepository {
  final SupabaseClient _supabase;
  final HiveService _hive;
  final NetworkInfo _network;

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    required String businessId,
    String? status,
    String? submittedBy,
    DateTimeRange? dateRange,
    int page = 0,
  }) async {
    try {
      // Try network first
      if (await _network.isConnected) {
        var query = _supabase
          .from(SupabaseTables.expenses)
          .select()
          .eq('business_id', businessId)  // RLS also enforces this
          .order('created_at', ascending: false)
          .range(page * 20, (page + 1) * 20 - 1);

        if (status != null) query = query.eq('status', status);
        if (submittedBy != null) query = query.eq('submitted_by', submittedBy);
        if (dateRange != null) {
          query = query
            .gte('expense_date', dateRange.start.toIso8601String())
            .lte('expense_date', dateRange.end.toIso8601String());
        }

        final data = await query;
        final expenses = data.map(ExpenseModel.fromJson).toList();

        // Cache to Hive for offline use
        await _hive.cacheExpenses(businessId, expenses);
        return Right(expenses);
      }

      // Fallback to Hive cache
      final cached = _hive.getExpenses(businessId);
      return Right(cached);
    } on PostgrestException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
```

### Use Case

```dart
// features/expenses/domain/usecases/get_expenses_usecase.dart

class GetExpensesUseCase {
  final ExpenseRepository _repo;
  GetExpensesUseCase(this._repo);

  Future<Either<Failure, List<ExpenseEntity>>> call(GetExpensesParams params) {
    return _repo.getExpenses(
      businessId: params.businessId,
      status: params.status,
      submittedBy: params.submittedBy,
      dateRange: params.dateRange,
      page: params.page,
    );
  }
}

class GetExpensesParams extends Equatable {
  final String businessId;
  final String? status;
  final String? submittedBy;
  final DateTimeRange? dateRange;
  final int page;

  const GetExpensesParams({
    required this.businessId,
    this.status,
    this.submittedBy,
    this.dateRange,
    this.page = 0,
  });

  @override
  List<Object?> get props => [businessId, status, submittedBy, dateRange, page];
}
```

---

## 11. Key Models & Entities

### BusinessEntity

```dart
// features/business/domain/entities/business_entity.dart

class BusinessEntity extends Equatable {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String ownerId;
  final String plan;
  final int maxEmployees;
  final bool isActive;
  final Map<String, dynamic> settings;
  final DateTime createdAt;

  const BusinessEntity({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.plan,
    required this.maxEmployees,
    required this.isActive,
    required this.settings,
    required this.createdAt,
    this.logoUrl,
  });

  String get currency => settings['currency'] as String? ?? 'INR';
  String get timezone => settings['timezone'] as String? ?? 'Asia/Kolkata';

  @override
  List<Object?> get props => [id, name, slug];
}
```

### BusinessMemberEntity

```dart
class BusinessMemberEntity extends Equatable {
  final String id;
  final String businessId;
  final String userId;
  final String role;           // owner | admin | manager | accountant | employee | viewer
  final bool isActive;
  final DateTime joinedAt;
  // Joined fields (loaded with business info)
  final String? businessName;
  final String? businessLogoUrl;

  UserRole get userRole => UserRole.fromString(role);

  @override
  List<Object?> get props => [id, businessId, userId, role];
}
```

### Updated ExpenseEntity

```dart
class ExpenseEntity extends Equatable {
  final String id;
  final String businessId;        // NEW
  final String expenseCode;
  final String title;
  final double amount;
  final String? categoryId;       // NEW
  final String categoryName;
  final String? vendorName;
  final String? description;
  final DateTime expenseDate;
  final String paymentMethod;
  final List<String> billUrls;
  final String status;
  final String submittedBy;
  final String submittedByName;
  final DateTime? submittedAt;
  final String? approvedBy;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final bool isRecurring;         // NEW
  final String? recurrencePattern; // NEW
  final List<ExpenseComment> comments;    // NEW
  final List<EditHistoryEntry> editHistory; // NEW
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ExpenseComment extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String message;
  final DateTime createdAt;
}

class EditHistoryEntry extends Equatable {
  final String userId;
  final String userName;
  final Map<String, dynamic> changes;  // field → {from, to}
  final DateTime editedAt;
}
```

### Updated EmployeeEntity

```dart
class EmployeeEntity extends Equatable {
  final String id;
  final String businessId;        // NEW
  final String? userId;
  final String employeeCode;
  final String name;
  final String email;
  final String? phone;
  final String? department;
  final String? designation;      // NEW
  final String? profileImageUrl;
  final bool isActive;
  final double salary;            // NEW
  final double totalAssigned;
  final double totalSpent;
  final double balance;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
}
```

---

## 12. Provider Structure

```dart
// shared/providers/active_business_provider.dart  — see Section 9

// features/expenses/presentation/providers/expense_provider.dart

@riverpod
Future<List<ExpenseEntity>> expenses(
  ExpensesRef ref, {
  String? status,
  DateTimeRange? dateRange,
}) async {
  final businessId = ref.watch(activeBusinessIdProvider);
  final role = ref.watch(currentUserRoleProvider);
  final currentUser = ref.watch(currentUserProvider).valueOrNull;

  final useCase = ref.read(getExpensesUseCaseProvider);
  final result = await useCase(GetExpensesParams(
    businessId: businessId,
    status: status,
    // Employees see only their own; managers+ see all
    submittedBy: role.canViewAllExpenses ? null : currentUser?.uid,
    dateRange: dateRange,
  ));

  return result.fold(
    (failure) => throw Exception(failure.message),
    (expenses) => expenses,
  );
}

@riverpod
class ExpenseNotifier extends _$ExpenseNotifier {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> submitExpense(ExpenseEntity expense) async {
    state = const AsyncValue.loading();
    final businessId = ref.read(activeBusinessIdProvider);
    final useCase = ref.read(submitExpenseUseCaseProvider);

    final result = await useCase(expense.copyWith(businessId: businessId));
    state = result.fold(
      (f) => AsyncValue.error(f.message, StackTrace.current),
      (_) {
        ref.invalidate(expensesProvider);
        return const AsyncValue.data(null);
      },
    );
  }
}
```

---

## 13. Optimized Query Patterns

### Always include businessId — belt AND suspenders

```dart
// Even though RLS enforces isolation, always include business_id in queries.
// This makes queries use the index and avoids accidental data leaks if RLS
// is misconfigured during development.

// CORRECT
_supabase
  .from('expenses')
  .select()
  .eq('business_id', businessId)   // ← always explicit
  .eq('status', 'pending')
  .order('created_at', ascending: false)
  .range(0, 19);

// WRONG — relies solely on RLS, no index, slow on large tables
_supabase.from('expenses').select().eq('status', 'pending');
```

### Dashboard aggregate query (single call)

```dart
// Use a Supabase RPC (PostgreSQL function) for complex dashboard stats
// to avoid N+1 queries.

// Create this in Supabase:
// CREATE OR REPLACE FUNCTION get_dashboard_stats(bid UUID)
// RETURNS JSON AS $$ ... $$ LANGUAGE sql SECURITY DEFINER;

final stats = await _supabase.rpc('get_dashboard_stats', params: {
  'bid': businessId,
});
```

### Paginated expense list

```dart
Future<List<ExpenseModel>> getExpensesPage({
  required String businessId,
  required int page,
  int pageSize = 20,
  String? status,
}) async {
  final from = page * pageSize;
  final to = from + pageSize - 1;

  var q = _supabase
    .from('expenses')
    .select('id, expense_code, title, amount, category_name, status, '
            'expense_date, submitted_by_name, created_at')  // select only needed columns
    .eq('business_id', businessId)
    .order('expense_date', ascending: false)
    .range(from, to);

  if (status != null) q = q.eq('status', status);

  final data = await q;
  return data.map(ExpenseModel.fromJson).toList();
}
```

### Realtime subscription (business-scoped)

```dart
// For the approvals screen — real-time updates when expenses change status
final channel = _supabase.channel('expenses:$businessId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'expenses',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'business_id',
      value: businessId,
    ),
    callback: (payload) => ref.invalidate(expensesProvider),
  )
  .subscribe();
```

---

## 14. Offline Sync Architecture

```dart
// core/services/hive_service.dart

class HiveService {
  static const _activeBusinessBox = 'active_business';
  static const _expenseDraftBox   = 'draft_expenses';
  static const _syncQueueBox      = 'sync_queue';
  static const _expenseCacheBox   = 'expense_cache';

  // Active business
  String? getActiveBusinessId() =>
    Hive.box(_activeBusinessBox).get('id') as String?;

  void saveActiveBusinessId(String id) =>
    Hive.box(_activeBusinessBox).put('id', id);

  // Offline drafts — stored keyed by local UUID
  Future<void> saveDraftExpense(Map<String, dynamic> draft) async {
    final box = Hive.box(_expenseDraftBox);
    await box.put(draft['local_id'], draft);
  }

  List<Map<String, dynamic>> getPendingDrafts() {
    return Hive.box<Map>(_expenseDraftBox)
      .values
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  }

  // Sync queue
  Future<void> enqueue(SyncOperation op) async {
    await Hive.box(_syncQueueBox).add(op.toJson());
  }

  List<SyncOperation> getQueue() {
    return Hive.box<Map>(_syncQueueBox)
      .values
      .map((e) => SyncOperation.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  }
}

// core/services/sync_service.dart

class SyncService {
  final HiveService _hive;
  final SupabaseClient _supabase;
  final NetworkInfo _network;

  // Call on app resume or connectivity restore
  Future<void> processQueue(String businessId) async {
    if (!await _network.isConnected) return;

    final queue = _hive.getQueue()
      .where((op) => op.businessId == businessId)
      .toList();

    for (final op in queue) {
      try {
        await _executeOperation(op);
        await _hive.dequeue(op.id);
      } catch (e) {
        // Leave in queue for next attempt; log error
      }
    }
  }

  Future<void> _executeOperation(SyncOperation op) async {
    switch (op.operation) {
      case 'insert':
        await _supabase.from(op.table).insert(op.payload);
      case 'update':
        await _supabase.from(op.table).update(op.payload).eq('id', op.payload['id']);
      case 'delete':
        await _supabase.from(op.table).delete().eq('id', op.payload['id']);
    }
  }
}
```

---

## 15. Migration Strategy

### Phase 0 — Preparation (Days 1–3)

**Goal:** Set up the new schema alongside the old one without breaking anything.

1. Create new Supabase tables: `businesses`, `business_members`, `expense_categories`, `salary_records`, `attendance`
2. Add `business_id` column (nullable) to all existing tables: `employees`, `expenses`, `funds`, `ledger`
3. Create a default business row for existing data:
   ```sql
   INSERT INTO businesses (id, name, slug, owner_id, plan)
   VALUES ('00000000-0000-0000-0000-000000000001', 'Default Business', 'default', '<your-admin-uid>', 'pro');
   ```
4. Backfill `business_id` on all existing rows:
   ```sql
   UPDATE employees SET business_id = '00000000-0000-0000-0000-000000000001';
   UPDATE expenses   SET business_id = '00000000-0000-0000-0000-000000000001';
   UPDATE funds      SET business_id = '00000000-0000-0000-0000-000000000001';
   UPDATE ledger     SET business_id = '00000000-0000-0000-0000-000000000001';
   ```
5. Make `business_id` NOT NULL after backfill
6. Create `business_members` rows for all existing users:
   ```sql
   INSERT INTO business_members (business_id, user_id, role)
   SELECT '00000000-...', uid, role FROM user_profiles;
   ```
7. Create all RLS functions (`is_member_of`, `my_role_in`, `has_role_or_above`)
8. Enable RLS on all tables but do NOT add policies yet (add next phase)
9. Write all database indexes

### Phase 1 — Flutter: Business + Auth Layer (Week 1)

**Goal:** App reads active business; all queries now include businessId. No UI change yet.

**Order:**
1. `core/services/hive_service.dart` — wrap Hive operations cleanly
2. `shared/providers/active_business_provider.dart` — the critical provider
3. `features/business/` — full Clean Architecture feature (entity → repo → usecase → provider)
4. Update `AuthNotifier.handlePostLogin` to fetch memberships and set active business
5. Update `app_router.dart` — add `/create-business` route; redirect new users there
6. Add `activeBusinessId` parameter to ALL existing datasource methods (but don't enable RLS policies yet)
7. Add RLS policies — enable business isolation

**Test:** Log in with existing user → lands on existing dashboard → all data still works.

### Phase 2 — Role System (Week 2)

**Goal:** Replace hardcoded `role == 'admin'` checks with the permission matrix.

**Order:**
1. `UserRole` enum + extensions in `core/constants/permission_matrix.dart`
2. `currentUserRoleProvider` in shared providers
3. `RoleGuard` widget
4. Replace every `user.role == 'admin'` check in screens/providers
5. Update GoRouter redirect logic to use `UserRole` and `canViewReports`, etc.
6. Add `manager`, `accountant`, `viewer` to existing role dropdowns in employee add/edit

**Test:** Create a viewer account → confirm they cannot see approval buttons, fund transfer, etc.

### Phase 3 — Feature Migration (Weeks 3–4)

Migrate each feature to full Clean Architecture. **Order matters** — start with the least interdependent:

1. **notifications** — update Firestore path to `businesses/{businessId}/notifications/`
2. **employees** — add `designation`, `salary` fields; update all providers
3. **funds** — no model changes needed; just businessId + RLS
4. **ledger** — no model changes needed; just businessId + RLS
5. **expenses** — add `categoryId`, `comments`, `editHistory`, recurring fields
6. **approval** — update to use `canApproveExpenses` permission
7. **dashboard** — add new analytics (use Supabase RPC for aggregate queries)
8. **reports** — add PDF + Excel export, monthly/category/employee breakdowns

### Phase 4 — New Features (Weeks 5–7)

1. `salary/` feature — salary records, pay runs
2. `attendance/` feature — daily check-in, monthly summary
3. Business switcher UI (header drawer with business list)
4. `business_settings_screen.dart` — manage categories, plan, members

### Phase 5 — Offline & Polish (Week 8)

1. `sync_service.dart` + queue processing
2. Hive caching for expenses, employees
3. Connectivity listener to trigger sync on reconnect
4. Push notification improvements (low balance, salary alerts)
5. Performance: pagination everywhere, select only needed columns

---

## 16. What Can Break

| Risk | Severity | Mitigation |
|------|----------|------------|
| Existing Firestore security rules don't check businessId | HIGH | Update rules in Phase 1 before enabling RLS |
| `notifications` Firestore path change — old notifications lost | MEDIUM | Run a migration script to move old docs under `businesses/{id}/` |
| `currentUserProvider` returns a user with no active business | HIGH | Add `needsBusinessSetup` state; route guard blocks all screens until business is set |
| Supabase RLS policy errors during migration | HIGH | Enable RLS policies one table at a time; test with service role key first |
| `hive_service.dart` added — old Hive box names still valid | LOW | Keep same box name constants; just wrap in a service |
| `UserRole` enum — old `'admin'` / `'employee'` strings still used in Supabase | MEDIUM | `UserRole.fromString` handles unknown values gracefully (returns `viewer`) |
| Employee feature: `employeeId` was Firebase Auth UID — now it's a UUID | HIGH | Keep `user_id` field; `id` becomes the internal UUID; update all references |
| Providers invalidated on business switch — in-flight requests fail | MEDIUM | `ref.invalidate` after switch; show loading state while providers rebuild |
| Notification FCM topics are global (`admin_notifications`) — cross-business leak | HIGH | Move to per-business topics: `admin_{businessId}` |

---

## 17. Production Best Practices

### Never trust the app for businessId

```dart
// RLS is your security boundary. App-side businessId is for UX and performance.
// Always verify with Supabase functions that the user is actually a member.
```

### JWT custom claims for Firestore rules

```javascript
// Supabase Edge Function: called after login to embed businessId + role
// into the Firebase custom token
import { createCustomToken } from 'firebase-admin/auth';

export const refreshBusinessClaims = async (req) => {
  const { userId, businessId } = req.body;
  const { data: member } = await supabase
    .from('business_members')
    .select('role')
    .eq('user_id', userId)
    .eq('business_id', businessId)
    .single();

  const token = await createCustomToken(userId, {
    business_id: businessId,
    role: member.role,
  });
  return { token };
};
```

### FCM topics must be per-business

```dart
// notification_service.dart

Future<void> subscribeToBusinessTopics(String businessId, UserRole role) async {
  await FirebaseMessaging.instance.subscribeToTopic('business_$businessId');
  if (role.isAdminLike) {
    await FirebaseMessaging.instance.subscribeToTopic('admin_$businessId');
  }
}

Future<void> unsubscribeFromBusinessTopics(String businessId) async {
  await FirebaseMessaging.instance.unsubscribeFromTopic('business_$businessId');
  await FirebaseMessaging.instance.unsubscribeFromTopic('admin_$businessId');
}
```

### Always paginate — never load all records

```dart
// Dangerous — will OOM on large businesses
_supabase.from('expenses').select().eq('business_id', businessId);

// Correct
_supabase.from('expenses').select().eq('business_id', businessId)
  .range(page * pageSize, (page + 1) * pageSize - 1);
```

### Expense code generation (business-scoped, collision-free)

```sql
-- PostgreSQL sequence per business using a function
CREATE OR REPLACE FUNCTION next_expense_code(bid UUID)
RETURNS TEXT AS $$
DECLARE seq_val INT;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(expense_code FROM 4) AS INT)), 0) + 1
  INTO seq_val
  FROM expenses WHERE business_id = bid;
  RETURN 'EXP' || LPAD(seq_val::TEXT, 5, '0');
END;
$$ LANGUAGE plpgsql;
```

### Supabase table name constants

```dart
// core/constants/supabase_tables.dart

abstract class SupabaseTables {
  static const businesses      = 'businesses';
  static const businessMembers = 'business_members';
  static const userProfiles    = 'user_profiles';
  static const employees       = 'employees';
  static const expenses        = 'expenses';
  static const funds           = 'funds';
  static const ledger          = 'ledger';
  static const notifications   = 'notifications';
  static const salaryRecords   = 'salary_records';
  static const attendance      = 'attendance';
  static const expenseCategories = 'expense_categories';
}
```

### Hive boxes — multi-business safe

```dart
// Prefix cache keys with businessId to avoid stale data when switching
String _expenseKey(String businessId) => 'expenses_$businessId';
String _employeeKey(String businessId) => 'employees_$businessId';
```

### Dashboard stats — single RPC call

```sql
-- Supabase RPC: get_dashboard_stats
CREATE OR REPLACE FUNCTION get_dashboard_stats(bid UUID)
RETURNS JSON AS $$
SELECT json_build_object(
  'total_employees',   (SELECT COUNT(*) FROM employees WHERE business_id = bid AND is_active),
  'total_expenses',    (SELECT COUNT(*) FROM expenses  WHERE business_id = bid),
  'pending_approvals', (SELECT COUNT(*) FROM expenses  WHERE business_id = bid AND status = 'pending'),
  'total_spent',       (SELECT COALESCE(SUM(amount),0) FROM expenses WHERE business_id = bid AND status = 'approved'),
  'monthly_spent',     (SELECT COALESCE(SUM(amount),0) FROM expenses WHERE business_id = bid
                         AND status = 'approved'
                         AND DATE_TRUNC('month', expense_date) = DATE_TRUNC('month', NOW())),
  'top_categories',    (SELECT json_agg(t) FROM (
                          SELECT category_name, SUM(amount) AS total
                          FROM expenses WHERE business_id = bid AND status = 'approved'
                          GROUP BY category_name ORDER BY total DESC LIMIT 5
                        ) t)
);
$$ LANGUAGE sql SECURITY DEFINER;
```

---

## Implementation Priority Summary

```
Week 1  │ DB schema migration, HiveService, activeBusinessProvider, auth flow
Week 2  │ UserRole enum, permissions, route guards, RLS policies enabled
Week 3  │ employees + expenses migration (businessId + new fields)
Week 4  │ funds + ledger + notifications migration (Firestore path)
Week 5  │ new dashboard stats (RPC), reports (PDF/Excel)
Week 6  │ salary + attendance features
Week 7  │ business switcher UI, business settings screen
Week 8  │ offline sync, performance tuning, production hardening
```
