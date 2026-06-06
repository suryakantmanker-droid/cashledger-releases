# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**expense_tracker** — A Flutter expense & employee money tracking app with admin/employee dual-role system, Firebase backend, and real-time Firestore data. Firebase project: `cashledger-9e954`.

## Commands

```bash
# Run the app
flutter run

# Build
flutter build apk
flutter build ios

# Run tests
flutter test
flutter test test/widget_test.dart   # single test file

# Code generation (required after editing Riverpod @riverpod annotations or Hive models)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch          # watch mode during development

# Linting
flutter analyze

# Firebase deployment
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions

# Regenerate Firebase options (after changing Firebase config)
flutterfire configure
```

## Architecture

**Clean Architecture** with feature-based organization:

```
lib/
├── main.dart              # Firebase + Supabase + Hive init, background FCM handler
├── app.dart               # MaterialApp, GoRouter, theme, ProviderScope
├── core/                  # Shared infrastructure
│   ├── constants/         # App-wide constants and route path strings
│   ├── errors/            # Failure types (dartz Either) and custom exceptions
│   ├── theme/             # Light/dark themes, colors, typography
│   ├── utils/             # Formatting helpers, validators
│   ├── services/          # Firebase, Supabase, notifications, storage service classes
│   ├── router/            # GoRouter with auth-based redirect logic
│   └── widgets/           # Reusable AppButton, AppTextField, loading overlays, etc.
└── features/              # Domain-based feature modules
    ├── auth/              # Login, signup, forgot password, auth provider, UserEntity
    ├── dashboard/         # Admin & employee dashboards with stats and charts
    ├── employees/         # Employee CRUD (admin only)
    ├── expenses/          # Expense submission, list, detail, approval
    ├── funds/             # Fund transfer and history (admin)
    ├── ledger/            # Double-entry ledger, immutable entries
    ├── approval/          # Expense approval workflow screen
    ├── notifications/     # Notification list and models
    └── reports/           # Analytics and PDF report generation
```

Each feature typically contains: screen(s), a Riverpod provider, and models.

## State Management

**Riverpod v3 (dev)** with code generation:

- `@riverpod` annotation → run `build_runner` to generate `.g.dart` files
- `StreamProvider` for real-time Firestore streams (employees, expenses, ledger)
- `StateNotifierProvider` for mutable state (auth, form submissions)
- `FutureProvider.family` for single-document fetches
- `ref.watch` in widget `build`, `ref.read` in callbacks/event handlers

## Navigation

**GoRouter v17** configured in `core/router/app_router.dart`:

- `/` → SplashScreen (2 sec) → redirects based on auth state
- `/login`, `/forgot-password` → unauthenticated routes
- `AdminShell` (`/admin/...`) — persistent shell for admin users
- `EmployeeShell` (`/employee/...`) — persistent shell for employee users
- Auth redirect: unauthenticated → `/login`; authenticated on `/login` → role-based dashboard
- `_RouterRefreshNotifier` listens to both stream and notifier auth state to trigger re-evaluation

Route path constants live in `core/constants/route_constants.dart`.

## Data Layer

**Two backends:**
- **Firebase/Firestore** — auth (`firebase_auth`), real-time data, push notifications (FCM)
- **Supabase** — PostgreSQL for supplementary data

**Firestore collections:** `users`, `employees`, `funds`, `expenses`, `ledger`, `notifications`, `settings`, `user_tokens`

**Error handling:** `dartz` `Either<Failure, T>` returned from repository methods. `Failure` subtypes defined in `core/errors/failures.dart`. Data sources throw custom exceptions (`core/errors/exceptions.dart`).

## Key Patterns

- **Forms:** `reactive_forms` package with validators from `core/utils/validators.dart`; use `AppTextField` widget for consistent styling
- **Images:** compressed via `flutter_image_compress` before upload; displayed with `cached_network_image` + shimmer placeholder
- **PDF:** generated with `pdf` package, viewed with `flutter_pdfview`; download via `dio`
- **Local storage:** `hive_flutter` for non-Firestore local state; `shared_preferences` for simple key-value
- **Responsive layout:** `flutter_screenutil` for sizing — always initialize before use

## Firebase Cloud Functions

`functions/index.js` (Node.js 20) — `sendPushOnNotification` triggers on new notification documents, reads FCM token from `user_tokens/{userId}`, and sends push with unread badge count.

## Code Generation Files

Files ending in `.g.dart` are auto-generated — never edit them manually. Re-run `build_runner` after modifying:
- Any class annotated with `@riverpod`
- Any Hive model annotated with `@HiveType`/`@HiveField`
