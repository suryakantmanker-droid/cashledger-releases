# ExpenseTrack Pro

A professional **Expense & Employee Money Tracking System** built with Flutter and Firebase. Supports dual roles — Admin and Employee — with real-time dashboards, expense approval workflows, fund transfers, and a double-entry ledger.

## Features

- **Admin**
  - Manage employees (CRUD)
  - Transfer funds to employees
  - Approve or reject expense submissions
  - View real-time ledger and financial reports
  - Generate PDF reports with charts

- **Employee**
  - Submit expenses with bill photo/file attachments
  - Track personal ledger and fund balance
  - Receive push notifications on approval status

- **Shared**
  - Role-based navigation (GoRouter with auth redirect)
  - Real-time data via Firestore streams
  - Push notifications via FCM
  - Light/dark theme support

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.2+ |
| State management | Riverpod v3 |
| Navigation | GoRouter v17 |
| Auth | Firebase Auth |
| Database | Cloud Firestore + Supabase |
| Push notifications | Firebase Messaging (FCM) |
| Local storage | Hive + SharedPreferences |
| Charts | fl_chart, Syncfusion Flutter Charts |
| PDF | pdf + printing |
| Forms | reactive_forms |

## Getting Started

### Prerequisites

- Flutter SDK `>=3.2.0 <4.0.0`
- Firebase CLI (`npm install -g firebase-tools`)
- An active Firebase project (default: `cashledger-9e954`)

### Setup

```bash
# Install dependencies
flutter pub get

# Run code generation (Riverpod + Hive adapters)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

### Firebase

Firebase options are pre-configured in `firebase_options.dart`. To regenerate after changing Firebase config:

```bash
flutterfire configure
```

Deploy Firestore rules, indexes, and Cloud Functions:

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions
```

## Project Structure

```
lib/
├── main.dart              # Entry point — Firebase, Supabase, Hive init
├── app.dart               # MaterialApp, GoRouter, theme
├── core/                  # Shared infrastructure (theme, router, services, widgets)
└── features/              # Feature modules
    ├── auth/
    ├── dashboard/
    ├── employees/
    ├── expenses/
    ├── funds/
    ├── ledger/
    ├── approval/
    ├── notifications/
    └── reports/
```

## User Roles

| Role | Default Route | Capabilities |
|---|---|---|
| `admin` | `/admin/dashboard` | Full access |
| `employee` | `/employee/dashboard` | Own expenses & ledger only |

Role is stored in the `users` Firestore collection and determines the navigation shell on login.

## Running Tests

```bash
flutter test
```

## Linting

```bash
flutter analyze
```
=======
# cashledger-releases
