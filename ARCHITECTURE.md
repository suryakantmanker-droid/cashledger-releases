# ExpenseTrack Pro — Complete Architecture Document

## 1. Folder Structure

```
lib/
├── main.dart                          # App entry point
├── app.dart                           # MaterialApp + Router + Theme
├── firebase_options.dart              # Firebase config (run: flutterfire configure)
│
├── core/
│   ├── constants/
│   │   ├── app_constants.dart         # Collection names, roles, statuses, limits
│   │   └── route_constants.dart       # All route path strings
│   ├── errors/
│   │   ├── failures.dart              # Failure types (dartz Either)
│   │   └── exceptions.dart            # Exception types
│   ├── theme/
│   │   ├── app_theme.dart             # Light + Dark ThemeData
│   │   ├── app_colors.dart            # Color palette
│   │   └── app_text_styles.dart       # Poppins text styles
│   ├── utils/
│   │   ├── app_utils.dart             # formatCurrency, formatDate, initials, IDs
│   │   └── validators.dart            # Form validators (email, phone, amount...)
│   ├── services/
│   │   ├── firebase_service.dart      # Firebase instance Providers
│   │   ├── storage_service.dart       # Firebase Storage upload/delete
│   │   └── notification_service.dart  # FCM + local notifications
│   ├── router/
│   │   └── app_router.dart            # GoRouter with auth redirect + shell routes
│   └── widgets/
│       ├── app_button.dart            # Reusable button (primary/outlined/danger/text)
│       ├── app_text_field.dart        # Labeled text field with validation
│       ├── loading_overlay.dart       # Full-screen loading + shimmer
│       ├── empty_state.dart           # Empty / error state widget
│       └── status_badge.dart          # Pending/Approved/Rejected chip
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/auth_remote_datasource.dart
│   │   │   ├── models/user_model.dart
│   │   │   └── repositories/auth_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/user_entity.dart
│   │   │   ├── repositories/auth_repository.dart
│   │   │   └── usecases/                          (optional — logic is in provider)
│   │   └── presentation/
│   │       ├── providers/auth_provider.dart
│   │       └── screens/
│   │           ├── splash_screen.dart
│   │           ├── login_screen.dart
│   │           └── forgot_password_screen.dart
│   │
│   ├── employees/                     (same Clean Architecture layers)
│   ├── funds/
│   ├── expenses/
│   ├── ledger/
│   ├── dashboard/
│   ├── approval/
│   ├── reports/
│   └── notifications/
```

---

## 2. Clean Architecture

```
┌──────────────────────────────────────┐
│         Presentation Layer           │
│  Screens · Widgets · Providers       │
│        (Riverpod StateNotifier)       │
└──────────────────┬───────────────────┘
                   │ calls
┌──────────────────▼───────────────────┐
│           Domain Layer               │
│  Entities · Repositories (abstract) │
│  Use Cases (optional for simple ops) │
└──────────────────┬───────────────────┘
                   │ implemented by
┌──────────────────▼───────────────────┐
│            Data Layer                │
│  Models · DataSources · Repo Impls   │
│         Firebase SDK calls           │
└──────────────────────────────────────┘
```

---

## 3. State Management — Riverpod

| Provider Type         | Use Case                                           |
|-----------------------|----------------------------------------------------|
| `Provider`            | Dependency injection (FirebaseAuth, Firestore)     |
| `StreamProvider`      | Real-time Firestore streams (employees, expenses)  |
| `FutureProvider`      | One-time async reads (expense by ID)               |
| `StateNotifierProvider` | Mutable state with actions (login, submit expense) |
| `StateProvider`       | Simple mutable state (search query, theme mode)    |

---

## 4. Firestore Collections Design

### `users` collection
```json
{
  "uid": "auto",
  "name": "John Admin",
  "email": "admin@company.com",
  "role": "admin",              // "admin" | "employee"
  "isActive": true,
  "photoUrl": null,
  "fcmToken": "fcm_token_here",
  "createdAt": "Timestamp",
  "lastLoginAt": "Timestamp"
}
```

### `employees` collection (doc ID = Firebase Auth UID)
```json
{
  "userId": "firebase_auth_uid",
  "employeeId": "EMP1234567",
  "name": "Raj Kumar",
  "email": "raj@company.com",
  "phone": "9876543210",
  "department": "Sales",
  "profileImageUrl": "https://...",
  "isActive": true,
  "totalAssigned": 50000.0,
  "totalSpent": 32000.0,
  "balance": 18000.0,
  "createdBy": "admin_uid",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

### `funds` collection
```json
{
  "transferId": "TXN1234567",
  "amount": 10000.0,
  "givenBy": "admin_uid",
  "givenByName": "John Admin",
  "givenTo": "employee_uid",
  "givenToName": "Raj Kumar",
  "purpose": "Site visit expenses",
  "paymentMode": "Cash",
  "notes": "For 3 days",
  "status": "active",
  "transferDate": "Timestamp",
  "createdAt": "Timestamp"
}
```

### `expenses` collection
```json
{
  "expenseId": "EXP1234567",
  "title": "Hotel Booking",
  "amount": 3500.0,
  "category": "Travel",
  "vendorName": "Treebo Hotels",
  "description": "2 nights in Mumbai",
  "expenseDate": "Timestamp",
  "paymentMethod": "UPI",
  "billUrls": ["https://storage.googleapis.com/..."],
  "status": "pending",
  "submittedBy": "employee_uid",
  "submittedByName": "Raj Kumar",
  "approvedBy": null,
  "approvedByName": null,
  "rejectionReason": null,
  "approvedAt": null,
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

### `ledger` collection
```json
{
  "employeeId": "employee_uid",
  "employeeName": "Raj Kumar",
  "type": "credit",              // "credit" | "debit"
  "amount": 10000.0,
  "balanceAfter": 18000.0,
  "remarks": "Fund received: Site visit expenses",
  "referenceId": "fund_doc_id",
  "referenceType": "fund_transfer",  // "fund_transfer" | "expense"
  "date": "Timestamp",
  "createdAt": "Timestamp"
}
```

### `notifications` collection
```json
{
  "userId": "target_uid",
  "title": "Expense Approved",
  "body": "Your expense 'Hotel Booking' was approved.",
  "type": "expense_approved",
  "data": { "expenseId": "..." },
  "isRead": false,
  "createdAt": "Timestamp"
}
```

---

## 5. Ledger Balance Logic

```
CREDIT entry   →  When Admin transfers funds to employee
                  balanceAfter = currentBalance + fundAmount
                  employees.balance += amount
                  employees.totalAssigned += amount

DEBIT entry    →  When expense is APPROVED by admin
                  balanceAfter = currentBalance - expenseAmount
                  employees.balance -= amount
                  employees.totalSpent += amount

Atomic write   →  Both ledger entry + employee update use Firestore batch.commit()
                  to guarantee consistency even on network failure.
```

---

## 6. Approval Workflow (Atomic Firestore Batch)

```
Employee submits expense
    │
    ▼
expense.status = "pending"
    │
    ▼
Admin sees it in ApprovalListScreen
    │
    ├── APPROVE ──►  batch.update(expense, status=approved)
    │                batch.update(employee, balance-=amount, totalSpent+=amount)
    │                batch.set(ledger, type=debit, balanceAfter=...)
    │                → notify employee: "Expense Approved"
    │
    └── REJECT  ──►  expense.status = "rejected"
                     expense.rejectionReason = "reason"
                     → notify employee: "Expense Rejected: reason"
```

---

## 7. Authentication Flow

```
App Launch
    │
    ▼
SplashScreen (2s)
    │
    ▼
authStateChanges stream
    │
    ├── null     →  LoginScreen
    │
    ├── admin    →  AdminDashboard (GoRouter redirect)
    │
    └── employee →  EmployeeDashboard (GoRouter redirect)


Login Flow:
  1. Validate email + password
  2. FirebaseAuth.signInWithEmailAndPassword()
  3. Fetch /users/{uid} from Firestore
  4. Check isActive flag (deactivated user is signed out)
  5. Update lastLoginAt timestamp
  6. Save FCM token
  7. Navigate by role
```

---

## 8. File Upload Strategy

```dart
// Image upload with compression
1. Pick image (ImagePicker)
2. Compress with FlutterImageCompress (85% quality, max 1024px)
3. Upload to Firebase Storage: bill_images/{expenseId}/{uuid}.jpg
4. Track progress with UploadTask.snapshotEvents
5. Get downloadURL on completion
6. Store URL in expense.billUrls array

// PDF upload
1. Pick PDF (FilePicker)
2. Upload to: bill_pdfs/{expenseId}/{uuid}.pdf
3. Same progress tracking
```

---

## 9. Offline Strategy

Firestore has built-in offline persistence enabled:
```dart
db.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

- All reads/streams work offline from the local cache
- Writes are queued and synced when online
- Hive is used for non-Firestore local state (draft expenses, user preferences)

---

## 10. Navigation Architecture

```
GoRouter (v14)
│
├── /                   → SplashScreen
├── /login              → LoginScreen
├── /forgot-password    → ForgotPasswordScreen
│
├── AdminShell (NavigationBar: Dashboard, Employees, Approvals, Ledger, Reports)
│   ├── /admin/dashboard
│   ├── /admin/employees         ← EmployeeListScreen
│   ├── /admin/employees/add     ← AddEmployeeScreen
│   ├── /admin/employees/:id     ← EmployeeDetailScreen
│   ├── /admin/funds/transfer    ← FundTransferScreen
│   ├── /admin/funds/history     ← FundHistoryScreen
│   ├── /admin/approvals         ← ApprovalListScreen
│   ├── /admin/expenses/:id      ← ExpenseDetailScreen
│   ├── /admin/ledger            ← LedgerScreen
│   └── /admin/reports           ← ReportsScreen
│
└── EmployeeShell (NavigationBar: Dashboard, Expenses, Ledger)
    ├── /employee/dashboard
    ├── /employee/expenses        ← ExpenseListScreen
    ├── /employee/expenses/add    ← AddExpenseScreen (FAB)
    ├── /employee/expenses/:id    ← ExpenseDetailScreen
    └── /employee/ledger          ← LedgerScreen
```

**Auth redirect:** GoRouter redirect function watches `currentUserProvider` (Stream).
- Unauthenticated → always redirect to `/login`
- Authenticated on `/login` → redirect by role

---

## 11. Performance Optimizations

1. **Firestore reads:** Use `StreamProvider` with `.limit(20)` pagination
2. **Images:** Compress before upload (5MB → ~300KB), use `cached_network_image`
3. **Queries:** All compound queries have composite indexes in `firestore.indexes.json`
4. **State:** `ref.watch` only in build methods; use `ref.read` in callbacks
5. **Rebuilds:** Use `select()` to listen to specific fields: `ref.watch(provider.select((s) => s.isLoading))`
6. **Riverpod:** Feature providers are `family` providers — only creates streams for active data

---

## 12. Firebase Cost Optimization

| Strategy                    | How                                                     |
|-----------------------------|---------------------------------------------------------|
| Minimize reads              | Use streams (charged per doc read, not per update)      |
| Pagination                  | `.limit(20)` on all list queries                        |
| Shallow queries             | Never fetch subcollections unless needed                |
| Batch writes                | Use batch for multi-document atomic writes              |
| Image compression           | Compress images before Storage upload                   |
| FCM (free)                  | Use FCM topics instead of targeting individual tokens   |
| Firestore cache             | Offline persistence reduces re-reads dramatically       |
| Avoid `getDocuments()` loops| Never loop fetch — use `whereIn` or `arrayContains`    |

---

## 13. Security Best Practices

1. **Role enforcement** is in Firestore Security Rules — never trust client-side role checks alone
2. **Employee cannot modify status** — rules block writing `status`, `approvedBy`, `rejectionReason`
3. **Ledger is immutable** — `update: if false` in rules
4. **Users never hard-deleted** — soft delete with `isActive: false`
5. **FCM token** stored per-user, refreshed on every login
6. **File size limits** enforced in Storage Rules (5MB images, 10MB PDFs)
7. **Isactive check** on login — deactivated accounts are signed out immediately
8. **No API keys** in code — use `firebase_options.dart` (excluded from public repos via `.gitignore`)

---

## 14. Development Roadmap

### Phase 1 — Foundation (Week 1-2)
- [ ] Flutter project setup + Firebase project creation
- [ ] Run `flutterfire configure` to generate `firebase_options.dart`
- [ ] Authentication (Login, Logout, Forgot Password)
- [ ] Admin Employee CRUD
- [ ] Fund Transfer
- [ ] Basic Ledger

### Phase 2 — Core Features (Week 3-4)
- [ ] Expense submission (employee)
- [ ] Bill upload (image + PDF)
- [ ] Approval workflow (admin approve/reject)
- [ ] Expense detail screen
- [ ] Employee dashboard

### Phase 3 — Analytics & Reports (Week 5)
- [ ] Admin dashboard with charts
- [ ] Monthly reports
- [ ] Category-wise breakdown
- [ ] Employee-wise summary

### Phase 4 — Notifications & Polish (Week 6)
- [ ] FCM notifications
- [ ] Local notifications
- [ ] Low balance alert
- [ ] UI refinements + dark mode testing
- [ ] Error handling + offline indicators

### Phase 5 — Production Hardening (Week 7-8)
- [ ] Deploy Firestore security rules
- [ ] Deploy storage rules
- [ ] Deploy Firestore indexes
- [ ] Performance testing
- [ ] App signing (Android keystore, iOS provisioning)
- [ ] Play Store / App Store submission

### Phase 6 — Future Features
- [ ] PDF export (pdf package)
- [ ] Excel export
- [ ] OCR bill scanning (Google ML Kit)
- [ ] GPS tracking of expenses
- [ ] Multi-branch support (add `branchId` to all documents)
- [ ] WhatsApp notifications (Twilio/WATI API)
- [ ] Web admin panel (Flutter Web or React)
- [ ] GST report generation

---

## 15. Setup Instructions

```bash
# 1. Install Flutter & create project
flutter create --org com.yourcompany expense_tracker
# Copy lib/ folder into the new project

# 2. Install Firebase CLI
npm install -g firebase-tools
firebase login

# 3. Configure Firebase
flutterfire configure
# → Creates firebase_options.dart automatically

# 4. Install dependencies
flutter pub get

# 5. Run code generation (for Riverpod annotations)
flutter pub run build_runner build --delete-conflicting-outputs

# 6. Deploy Firestore rules
firebase deploy --only firestore:rules

# 7. Deploy Storage rules
firebase deploy --only storage

# 8. Deploy Firestore indexes
firebase deploy --only firestore:indexes

# 9. Create first admin user
# In Firebase Console → Authentication → Add user
# Then in Firestore → users collection → add doc with uid:
# { name, email, role: "admin", isActive: true, createdAt }

# 10. Run the app
flutter run
```

---

## 16. Android Setup Required

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>

<!-- Inside <application> tag: -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="expense_tracker_channel"/>
```

Set `minSdkVersion 21` in `android/app/build.gradle`.

---

## 17. iOS Setup Required

Add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access for capturing bill photos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access for selecting bill images</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Saving bill images</string>
```
