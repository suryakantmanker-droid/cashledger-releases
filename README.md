# ExpenseTrack Pro (CashLedger)

A professional **multi-business Expense & Employee Money Tracking System** built with Flutter and Supabase. Supports a six-level role hierarchy (owner/admin/manager/accountant/employee/viewer) across multiple businesses, with real-time dashboards, expense approval workflows, fund transfers, employee-site assignment tracking, and a double-entry ledger.

## Features

- **Superadmin**
  - Create and manage businesses, set demo/subscription status
  - Watch specific businesses, reset admin passwords

- **Business Owner / Admin**
  - Manage employees (CRUD), assign departments and physical sites
  - Add/remove additional business admins, change member roles
  - Transfer funds to employees; approve or reject expense submissions
  - View real-time ledger and financial reports; generate PDF reports with charts

- **Employee**
  - Submit expenses with bill photo/file attachments
  - Track personal ledger and fund balance
  - Receive push notifications on approval status and site reassignment

- **Shared**
  - Role-based navigation (GoRouter with auth redirect)
  - Real-time data via Supabase Realtime streams
  - Push notifications via FCM (delivered through a Supabase Edge Function)
  - Light/dark theme support

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.2+ |
| State management | Riverpod v3 (hand-written providers, no codegen) |
| Navigation | GoRouter |
| Auth + Database | Supabase (Postgres, Auth, RLS, RPC functions, Edge Functions) |
| Push notifications | Firebase Messaging (FCM) — messaging only, no Firestore |
| File storage | Cloudinary |
| Local storage | Hive + SharedPreferences |
| Charts | fl_chart, Syncfusion Flutter Charts |
| PDF | pdf + printing |
| Forms | reactive_forms |

## Getting Started

### Prerequisites

- Flutter SDK `>=3.2.0 <4.0.0`
- Supabase CLI (for migrations/Edge Functions): `npm install -g supabase`
- Firebase CLI (messaging config only): `npm install -g firebase-tools`

### Setup

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Supabase

The Supabase URL/anon key are set directly in `lib/main.dart`. Migrations live in `supabase/migrations/*.sql` but are **not** tracked via `supabase db push` — apply a specific file against the linked project with:

```bash
supabase link --project-ref <project-ref>   # one-time per machine
supabase db query --file supabase/migrations/0NN_name.sql --linked
```

Edge Functions (`supabase/functions/*/index.ts`) handle service-role-only operations (creating other users' Auth accounts, admin-triggered email/password changes, sending FCM pushes):

```bash
supabase functions deploy <name>
```

### Firebase (messaging only)

Firebase options are pre-configured in `firebase_options.dart` — used solely for FCM push delivery. Regenerate after changing Firebase config:

```bash
flutterfire configure
```

## Project Structure

```
lib/
├── main.dart              # Entry point — Firebase Messaging, Supabase, Hive init
├── app.dart               # MaterialApp, GoRouter, theme
├── core/                  # Shared infrastructure (theme, router, services, widgets)
├── shared/providers/      # business_context_provider.dart — the multi-business spine
└── features/              # Feature modules
    ├── auth/
    ├── business/           # Multi-business membership & admin management
    ├── superadmin/
    ├── dashboard/
    ├── employees/
    ├── sites/              # Multi-location assignment + history
    ├── departments/
    ├── expenses/
    ├── sales/
    ├── funds/
    ├── ledger/
    ├── approval/
    ├── notifications/
    ├── reports/
    └── profile/
```

## Roles

Six-level hierarchy (`lib/core/constants/permission_matrix.dart`), scoped **per business** — a user's role can differ across businesses they belong to:

| Role | Level | Notes |
|---|---|---|
| `owner` | 50 | The business's real creator; protected from removal |
| `admin` | 40 | Full business management |
| `manager` | 30 | Fund transfers, salary/attendance |
| `accountant` | 20 | Approve expenses, view reports |
| `employee` | 10 | Submit expenses, view own ledger |
| `viewer` | 0 | Read-only |

`AdminShell` (`/admin/...`) is shown for admin+ roles, `EmployeeShell` (`/employee/...`) for everyone else. Role is stored per-business in the `business_members` table (Supabase), not as a single global flag.

## Running Tests

```bash
flutter test
```

## Linting

```bash
flutter analyze
```
