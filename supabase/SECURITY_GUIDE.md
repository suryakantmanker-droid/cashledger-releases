# Phase 4 Security Guide — RLS Enablement & Tenant Isolation

## Rollout Order

Run in this exact sequence. Do NOT skip steps.

```
Step 1 — Supabase Dashboard: configure Firebase JWT (JWKS)
Step 2 — Deploy Flutter app update (signInWithIdToken)
Step 3 — Verify JWT works in staging (see Verification section)
Step 4 — Deploy migration 011 (JWT fix + RPC hardening)
Step 5 — Test all financial operations in staging
Step 6 — Deploy migration 012 (enable RLS) to staging
Step 7 — Full regression test in staging (all screens, all roles)
Step 8 — Deploy migrations 011 + 012 to production (in one transaction window)
Step 9 — Deploy migration 013 (audit logging) — can run independently
Step 10 — Monitor error rates for 24h before declaring stable
```

---

## Step 1: Supabase Dashboard Configuration

In Supabase Dashboard → **Authentication** → **Sign In / Up** → **Third Party Auth**:

1. Click **Add provider** → Select **Custom OIDC/JWT**
2. Set:
   - **Issuer URL**: `https://securetoken.google.com/<YOUR_FIREBASE_PROJECT_ID>`
   - **JWKS URL**: `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`
   - **Client ID** (aud claim): `<YOUR_FIREBASE_PROJECT_ID>`
3. Save and note the provider is now active

After this, `supabase.auth.signInWithIdToken(provider: OAuthProvider.custom, idToken: firebaseToken)` will work from Flutter.

---

## JWT Architecture

```
Firebase Auth (email/password login)
  │
  │ FirebaseAuth.signInWithEmailAndPassword()
  ▼
Firebase ID Token (JWT)
  { sub: "FIREBASE_UID", user_id: "FIREBASE_UID", email: "...", ... }
  │
  │ supabase.auth.signInWithIdToken(provider: custom, idToken: firebaseToken)
  ▼
Supabase Session (Supabase JWT)
  {
    sub: "SUPABASE-UUID",               ← NOT the Firebase UID
    user_metadata: {
      sub: "FIREBASE_UID",              ← fn_current_user_uid() reads this
      user_id: "FIREBASE_UID",          ← fallback
      email: "..."
    },
    role: "authenticated"
  }
  │
  │ Every Supabase query now carries this JWT
  ▼
PostgreSQL RLS Policies
  fn_current_user_uid() → "FIREBASE_UID"
  fn_is_member_of(business_id) → true/false
  fn_has_role_or_above(business_id, 'manager') → true/false
```

**Key point**: `auth.uid()` returns the Supabase UUID, not the Firebase UID.
`fn_current_user_uid()` reads `user_metadata.sub` which IS the Firebase UID.
All tables store the Firebase UID — so policies must use `fn_current_user_uid()`.

### Token Refresh
- Firebase tokens expire every 1 hour
- `idTokenChanges()` stream fires on refresh
- `auth_remote_datasource.dart` calls `_ensureSupabaseSession()` before each stream subscription
- Supabase sessions are refreshed automatically if the Supabase token is near expiry

---

## Verification Queries

Run these in the **Supabase SQL Editor** while logged in as a real test user (NOT the service role key). The easiest way: use the Supabase REST API with the user's access token.

### 1. Verify Firebase UID extraction
```sql
SELECT
  fn_current_user_uid()                                     AS firebase_uid,
  auth.jwt() -> 'user_metadata' ->> 'sub'                   AS metadata_sub,
  auth.jwt() -> 'user_metadata' ->> 'user_id'               AS metadata_user_id,
  auth.jwt() ->> 'role'                                     AS jwt_role;
```
Expected: `firebase_uid` = your Firebase UID (non-UUID string), `jwt_role` = 'authenticated'.

### 2. Verify membership check
```sql
SELECT fn_is_member_of('<YOUR_BUSINESS_ID>'::uuid);
-- Expected: true
SELECT fn_is_member_of('00000000-0000-0000-0000-000000000000'::uuid);
-- Expected: false
```

### 3. Verify RLS enforcement on employees table
```sql
-- As user from Business A, try to read Business B's employees
SELECT COUNT(*) FROM employees WHERE business_id = '<BUSINESS_B_ID>'::uuid;
-- Expected: 0 rows (RLS blocks it)
-- Expected: NOT an error — RLS silently returns empty, not an exception
```

### 4. Verify ledger is write-blocked from client
```sql
INSERT INTO ledger (business_id, employee_id, employee_name, type, amount, balance_after, remarks, reference_id, reference_type)
VALUES ('<BID>'::uuid, 'uid', 'name', 'credit', 100, 100, 'test', 'ref', 'test');
-- Expected: ERROR — RLS policy "ledger_insert_never_from_app" blocks this
```

### 5. Verify RPC role enforcement
```sql
-- As an employee (role = 'employee'), try to call transfer_fund
SELECT transfer_fund(
  'TRF-TEST', 100, 'given_by', 'By Name', 'given_to', 'To Name',
  'test', 'Cash', NULL, 'active', NOW(),
  '<YOUR_BUSINESS_ID>'::uuid
);
-- Expected: ERROR P0008 — Insufficient privileges: manager role required
```

---

## Security Audit Checklist

### Pre-deployment
- [ ] `fn_current_user_uid()` returns Firebase UID (not NULL) for logged-in user
- [ ] `fn_is_member_of(<business_id>)` returns true for own business, false for other
- [ ] `fn_has_role_or_above(<business_id>, 'manager')` correct for all roles
- [ ] Flutter app calls `signInWithIdToken()` on every login and token refresh
- [ ] Supabase Dashboard JWKS URL configured for Firebase project

### Post-deployment (within 1h of going live)
- [ ] All dashboard screens load for admin users
- [ ] All dashboard screens load for employee users
- [ ] Fund transfer completes successfully (manager/admin user)
- [ ] Expense submission completes successfully (employee user)
- [ ] Expense approval completes successfully (accountant/manager/admin user)
- [ ] Notification screen loads for both admin and employee
- [ ] Business switcher changes data correctly (no data from previous business visible)
- [ ] Ledger screen shows correct entries
- [ ] No P0003/P0004/P0008 errors in Supabase logs for legitimate operations
- [ ] Error rate on Supabase functions < pre-deployment baseline

---

## Attack Simulation Checklist

### Cross-Business Read Attack
```
Attacker: User from Business A with valid JWT
Target: Business B data

Test 1 — Direct REST query:
  GET /rest/v1/employees?business_id=eq.<BIZ_B_ID>
  Expected: [] (empty — RLS blocks all B's rows)

Test 2 — Supabase JS SDK:
  supabase.from('expenses').select().eq('business_id', BIZ_B_ID)
  Expected: [] (same RLS enforcement via PostgREST)

Test 3 — RPC with cross-business ID:
  supabase.rpc('fn_get_dashboard_stats', { p_business_id: BIZ_B_ID })
  Expected: Error P0011 — "not a member of business"
```

### Privilege Escalation Attack
```
Attacker: Employee user (role = 'employee')
Target: Approve own expense or transfer funds

Test 4 — Direct approve_expense RPC:
  supabase.rpc('approve_expense', { p_expense_id: ..., p_business_id: ... })
  Expected: Error P0008 — "accountant role required"

Test 5 — Direct transfer_fund RPC:
  supabase.rpc('transfer_fund', { ..., p_business_id: ... })
  Expected: Error P0008 — "manager role required"

Test 6 — Direct ledger INSERT:
  supabase.from('ledger').insert({ ... })
  Expected: Error — RLS "ledger_insert_never_from_app" blocks it

Test 7 — Forged business_id in expense insert:
  supabase.from('expenses').insert({ business_id: BIZ_B_ID, submitted_by: OWN_UID, ... })
  Expected: Error — RLS "exp_insert_employee" requires fn_has_role_or_above(business_id, 'employee')
  Since user is not a member of BIZ_B, fn_has_role_or_above returns false → blocked
```

### Forged Identity Attack
```
Attacker: Has anon key, no JWT, knows a valid business_id + employee_id

Test 8 — Anon key + direct REST:
  GET /rest/v1/employees with apikey=anon_key (no Authorization header)
  Expected: [] — RLS returns no rows (fn_current_user_uid() = NULL → fn_is_member_of() = false)
  NOTE: After Phase 5 (anon access revoked), this would return 403.

Test 9 — Anon key + RPC:
  POST /rest/v1/rpc/transfer_fund with apikey=anon_key
  Expected: fn_assert_caller_role skips (UID = NULL), but cross-business guard still fires.
  Risk: anon key CAN call RPCs until Phase 5 revokes anon access to functions.
  Mitigation: Cross-business guard prevents wrong-business transfers.
  Remaining gap: Anon caller KNOWING valid IDs for same business could call RPCs.
  Phase 5 fix: Revoke EXECUTE on all RPCs from anon role.

Test 10 — JWT with wrong role claim:
  Craft a JWT claiming role='admin' but user is actually 'employee' in DB
  Expected: JWT is validated by Supabase signature verification — forged JWTs are rejected.
  Role in JWT is NOT used for Supabase RLS — fn_my_role_in() queries business_members table.
```

### Denial of Service via RLS
```
Test 11 — Enumerate business IDs:
  Attacker makes 10,000 fn_get_dashboard_stats calls with random UUIDs
  Mitigation: Supabase rate limiting + P0011 exception (short-circuit) + connection pooling
  Monitoring: Alert on high P0011 error rate
```

---

## Phase 5 Hardening (Post-Phase-4 Roadmap)

```
1. Revoke anon key access to all financial RPCs:
   REVOKE EXECUTE ON FUNCTION transfer_fund FROM anon;
   REVOKE EXECUTE ON FUNCTION approve_expense FROM anon;
   REVOKE EXECUTE ON FUNCTION reverse_fund_transfer FROM anon;

2. Revoke anon key SELECT on all tables:
   REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM anon;
   (All queries require 'authenticated' role)

3. Move notification creation to Supabase Edge Function:
   Validate caller's business membership server-side before writing Firestore.

4. Enable Supabase Audit Logs in Dashboard:
   Settings → Audit Logs → Enable for data-modifying operations.

5. Add rate limiting to financial RPCs:
   Use pg_sleep + rate limit table to prevent bulk transfer attacks.

6. JWT expiry hardening:
   Reduce Firebase token lifetime to 30 minutes for admin users.
   Implement forced re-auth for financial operations.
```

---

## Production Monitoring Checklist

### Metrics to watch (first 48h after Phase 4)
- [ ] Supabase error rate (PostgREST 4xx/5xx) — should not exceed pre-deploy baseline
- [ ] RLS policy evaluation time (pg_stat_user_tables `seq_scan` count should decrease)
- [ ] P0008 errors in logs — expected 0 from legitimate app operations
- [ ] P0011 errors in logs — expected 0 from legitimate app operations
- [ ] Firebase token refresh failures (would break Supabase session refresh)
- [ ] `security_audit_log` `warning` events — investigate any unexpected entries

### Alert thresholds
```
CRITICAL: Any P0001 (cross-business transfer attempt)
WARNING:  >5 P0008 errors/minute (privilege escalation attempts)
WARNING:  >10 P0011 errors/minute (cross-business read attempts)
INFO:     security_audit_log entries with severity = 'critical'
```

### Useful queries for on-call
```sql
-- Recent security events
SELECT event_type, severity, user_uid, details, created_at
FROM   security_audit_log
WHERE  created_at > NOW() - INTERVAL '1 hour'
ORDER  BY created_at DESC;

-- Check if RLS is enabled on all tables
SELECT relname, relrowsecurity
FROM   pg_class
WHERE  relname IN ('employees','expenses','funds','ledger','users')
ORDER  BY relname;

-- Check fn_current_user_uid is working for a specific user
-- (run in Supabase SQL editor with the user's JWT in the Authorization header)
SELECT fn_current_user_uid(), fn_is_member_of('<bid>'::uuid), fn_my_role_in('<bid>'::uuid);
```

---

## Rollback Decision Tree

```
Incident detected
  │
  ├─ App screens return empty data (no errors)
  │    Cause: fn_current_user_uid() returns NULL (JWT not working)
  │    Fix:   Verify Supabase JWKS URL is correct. Check Flutter is calling signInWithIdToken.
  │    Emergency: Disable RLS on affected tables (PHASE4_ROLLBACK.sql Stage 1)
  │
  ├─ Users get P0008 errors on legitimate operations
  │    Cause: fn_assert_caller_role() fails for an expected role
  │    Fix:   Verify business_members table has correct role values
  │    Emergency: Remove role check from specific RPC (PHASE4_ROLLBACK.sql Stage 2)
  │
  ├─ Cannot create new user rows (first login fails)
  │    Cause: users RLS blocks insert — fn_current_user_uid() NULL at insert time
  │    Fix:   Ensure signInWithIdToken is called BEFORE _createUser
  │    Emergency: Disable RLS on users table only
  │
  └─ Performance degradation (queries slower)
       Cause: RLS policy function calls per-row (fn_is_member_of overhead)
       Fix:   Check idx_business_members_business_user index is being used
       Monitor: EXPLAIN ANALYZE on slow queries
```
