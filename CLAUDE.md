# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**expense_tracker** (CashLedger) — A Flutter expense & employee money tracking app with a multi-tenant, multi-business architecture: **superadmin / business-owner / admin / manager / accountant / employee** role hierarchy, real-time Supabase Postgres data, and FCM push notifications.

**Backend reality (important — differs from what package names alone would suggest):**
- **Supabase** is the primary backend: Postgres database, Auth, Row-Level Security, Postgres RPC functions, Edge Functions, and Realtime streams. Project ref `lfvmkuqesvjodqrzzpaj` (URL/anon key in `lib/main.dart`).
- **Firebase** is used *only* for push notification delivery (`firebase_messaging`) plus a legacy `firebase_options.dart`/`functions/` Cloud Functions setup. There is **no Cloud Firestore usage anywhere in `lib/`** — `functions/index.js` (`sendPushOnNotification`, Firestore-triggered) and `firestore.rules`/`firestore.indexes.json` are leftovers from an earlier architecture and aren't invoked by current code. The live notification path is: `NotificationService.sendNotificationToUser()` → inserts into the Supabase `notifications` table → invokes the `send-notification` Supabase Edge Function → FCM push (token stored in `users.fcm_token`).

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

# Linting
flutter analyze

# Code generation — NOT currently needed: there are no @riverpod or @HiveType
# annotations anywhere in lib/ despite riverpod_generator/hive_generator being
# dev dependencies. All providers are hand-written StateNotifier/FutureProvider;
# Hive is used for plain key-value storage. Only run this if you add a new
# @riverpod/@HiveType annotation:
dart run build_runner build --delete-conflicting-outputs

# Regenerate Firebase options (after changing Firebase messaging config)
flutterfire configure
```

### Supabase — migrations & functions

Migrations in `supabase/migrations/*.sql` are **numbered but not tracked via `supabase db push`/migration history** — this project applies them manually (see migration file headers: "Run this in: Supabase Dashboard → SQL Editor"). The CLI pattern used throughout this repo's history:

```bash
supabase link --project-ref lfvmkuqesvjodqrzzpaj   # one-time per machine
supabase db query --file supabase/migrations/0NN_name.sql --linked
supabase db query "SELECT ..." --linked            # ad-hoc checks/backfills
```

Do **not** run `supabase db push` blind — since remote migration history isn't tracked, it may try to replay the entire migration directory against production. Verify schema state with a targeted `supabase db query` first, and confirm with the user before applying anything to the live DB.

Edge Functions (`supabase/functions/*/index.ts`, Deno) run with the `service_role` key server-side for operations the client's own JWT can't perform (creating *other* users' Auth accounts, changing another user's email/password, bypassing RLS):
- `create-auth-user` — creates a Supabase Auth account + `users` row (employee-add and admin-invite flows)
- `update-user-email` / `update-user-password` — admin-triggered credential changes for other users
- `send-notification` — sends the actual FCM push for a `notifications` row

Deploy with `supabase functions deploy <name>` (requires `supabase link` first); also confirm with the user first, since this pushes to the live project.

## Architecture

**Clean Architecture**, feature-based. Each feature under `lib/features/<name>/` typically has `data/{datasources,models,repositories}`, `domain/{entities,repositories}`, `presentation/{screens,providers,widgets}`. Repositories return `dartz` `Either<Failure, T>`; datasources throw `ServerException`/`FirestoreException` (legacy exception name — not Firestore-specific) caught and converted at the repository layer.

Feature modules: `auth`, `business` (multi-business membership/admin management), `superadmin`, `dashboard`, `employees`, `sites` (multi-location assignment + history), `departments`, `expenses`, `sales`, `funds`, `ledger`, `approval`, `notifications`, `reports`, `profile`.

### Multi-business architecture — the spine

Every business-scoped repository/provider/screen reads from `lib/shared/providers/business_context_provider.dart` and **never** receives a `businessId` through the widget tree:

- `businessContextProvider` (`StateNotifierProvider`, global/keepAlive) — holds the user's loaded `BusinessMembershipEntity` list and the currently active one. Bootstrap sequence and business-switch behavior are documented in the file's header comment.
- `activeBusinessIdProvider` — the active business's UUID; repositories must only be called once this is non-null.
- `currentUserRoleProvider` — the caller's `UserRole` *in the active business* (not a global role).
- `userMembershipsProvider` — all businesses the user belongs to (business switcher).
- Superadmins get a synthetic `UserRole.owner` membership per business (`getAllBusinessesAsSuperadmin`) rather than a real `business_members` row, unless `ensureSuperadminMembership()` has granted them a real one for direct support access — that grant does **not** count toward `AppConstants.maxBusinessAdmins` and is filtered out of `getBusinessAdmins()`.

### Role hierarchy (`lib/core/constants/permission_matrix.dart`)

Six-level hierarchy, **not** a flat admin/employee flag: `owner(50) > admin(40) > manager(30) > accountant(20) > employee(10) > viewer(0)`. All permission checks go through `UserRole.isAtLeast()` or the `UserRolePermissions` extension getters (`canApproveExpenses`, `canManageEmployees`, `canManageRoles`, `canManageBusiness` [owner-only], etc.) — never compare role strings directly.

**Legacy field gotcha:** `users.role` (a string column, `AppConstants.roleAdmin`/`roleEmployee`) is a *separate*, older two-tier flag still read in several screens via `UserEntity.isAdmin`/`isEmployee` (splash/login post-auth routing, ledger scope, profile, expense-detail admin actions). It's kept in sync automatically by `BusinessRemoteDataSourceImpl._syncLegacyUserRole()` whenever `business_members.role` changes (`addMember`/`updateMemberRole`) — owner/admin collapse to legacy `'admin'`, everything else collapses to `'employee'`. If you add a new place that mutates a business role, route it through `BusinessRepository.addMember`/`updateMemberRole` rather than writing `business_members` directly, so this stays in sync.

A business's true creator/owner **must** get `business_members.role = 'owner'`, not `'admin'` — only `'owner'` is protected from removal in `removeAdmin`/`revertToPreviousRole`. `superadmin_datasource.dart#createBusiness()` is the only place that should mint an owner row.

### Role-change side effects are centralized

`BusinessRemoteDataSourceImpl.updateMemberRole()` is the single place that: updates `business_members.role`, tracks `previous_role` (for the "revert to previous role" UI), syncs the legacy `users.role`, and activates/deactivates the matching `employees` row when crossing the admin-like boundary. Don't duplicate this logic in callers (`EmployeeNotifier.changeRole`, `BusinessAdminsActionsNotifier.switchToAdmin`) — they just call `updateMemberRole` and react to the result.

## Navigation

**GoRouter**, configured in `lib/core/router/app_router.dart`, with three persistent shells gated by role:
- `AdminShell` (`/admin/...`) — `currentUserRoleProvider.isAdminLike` (admin+)
- `EmployeeShell` (`/employee/...`) — everyone else
- Superadmin routes (`/superadmin/...`) — `user.isSuperadmin`

The top-level `redirect` callback is the authoritative router for auth/business-loading state and for routing away from auth screens once business context settles — it correctly uses `currentUserRoleProvider`. Screens that navigate manually right after an auth event (`login_screen.dart`, `splash_screen.dart`) still use the **legacy** `user.isAdmin` flag for their one-shot post-auth redirect, which is why keeping that legacy field in sync (above) matters.

`RouteConstants` (`lib/core/constants/route_constants.dart`) holds every route path string — add new routes there, not as raw string literals.

## Key Patterns

- **Dropdown-with-inline-create**: `DepartmentDropdown` (`lib/features/departments/`) and `SiteDropdown` (`lib/features/sites/`) both implement "pick from a business-scoped list, or type a new value to create it inline" via a bottom sheet. Follow this pattern for any future "managed list" field rather than a plain `DropdownButtonFormField`.
- **Append-only history**: `employee_site_assignments` is intentionally not directly writable by the client (no INSERT/UPDATE RLS policy) — all writes go through the `fn_change_employee_site` Postgres RPC (`SECURITY DEFINER`, re-checks role server-side) so the close-old/open-new pair is atomic and the table stays a clean audit trail. Use this approach for any other "track changes over time" requirement instead of ad-hoc UPDATE-then-INSERT from Flutter.
- **Forms:** `reactive_forms` package; `AppTextField`/`AppButton` (`lib/core/widgets/`) for consistent styling.
- **Images:** compressed via `flutter_image_compress` before upload; uploaded to **Cloudinary** (unsigned preset, see `lib/core/services/storage_service.dart`) — not Firebase Storage or Supabase Storage; displayed with `cached_network_image`.
- **PDF:** generated with `pdf` package, viewed with `flutter_pdfview`; download via `dio`.
- **Local storage:** `hive_flutter` for local state (active business id, cached memberships, notification mode); `shared_preferences` for simple key-value.
- **Responsive layout:** `flutter_screenutil` — already initialized in `app.dart`.

## Error Handling

`dartz` `Either<Failure, T>` returned from repository methods. `Failure` subtypes in `lib/core/errors/failures.dart`. Data sources throw custom exceptions (`lib/core/errors/exceptions.dart`) caught and converted to `Failure`s at the repository layer.
