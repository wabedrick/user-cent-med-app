## Authentication & Authorization Architecture

This document describes the production-ready auth & role model implemented on 2025‑09‑18.

### Goals
1. Deterministic, claim-backed authorization (no privilege via stale Firestore state).
2. Fast role resolution with graceful handling while custom claims propagate.
3. Centralized retry & claim sync logic to eliminate scattered permission-denied workarounds.
4. Extensible, testable abstractions (repositories/services separated from widgets/providers).

### Core Components
| Component | File | Responsibility |
|-----------|------|----------------|
| `AuthRepository` | `lib/auth/auth_repository.dart` | Sign in/out, sign up, ensure user profile doc exists safely. |
| `RoleService` | `lib/auth/role_service.dart` | Fetch role from custom claim (preferred) and Firestore as fallback. |
| `ClaimSyncManager` | `lib/auth/claim_sync_manager.dart` | Attempts to reconcile missing custom claims (forced token refresh + optional callable). |
| `RoleRouter` | `lib/main.dart` | Directs user to appropriate dashboard; requires claim=='admin' for admin access. |
| `RoleGate` | `lib/widgets/role_gate.dart` | Widget-level allow-list gating for subtrees. |
| Permission retry helper | `lib/auth/permission_denied_retry.dart` | Wraps mutations to retry once after claim sync. |

### Role Resolution Rules
1. Custom claim `role` (lowercased) is authoritative.
2. Firestore `users/{uid}.role` is ONLY a fallback for non-admin roles while waiting for claims.
3. Admin dashboard requires the claim itself to equal `admin` (Firestore-only admin is treated as pending).

### Claim Propagation Flow
```
Sign In / Role Change
    ↓ (Cloud Function sets custom claim & updates Firestore)
Client Token Refresh (forced) → Claim available? → YES → proceed
                                    ↓ NO
                             ClaimSyncManager.ensureClaimPresent()
                                    ↓ (refresh + optional callable selfSyncRoleClaim)
                             Re-poll RoleRouter (exponential backoff ≤5 attempts)
```

### Handling permission-denied
Use `runWithPermissionRetry` for write operations likely to fail if the claim has just been granted.
Provide a callback that triggers `ClaimSyncManager().ensureClaimPresent()` then retries once.

### Future Enhancements (Backlog)
* Integrate a periodic background claim freshness check on app resume every N minutes.
* Replace legacy Riverpod role providers with a single `roleControllerProvider` backed by `RoleService`.
* Add unit tests using mocks for `RoleService` & claim sync flows (see TODO list).

### Operational Notes
* Deploy Cloud Functions (`setUserRole`, `selfSyncRoleClaim`) before expecting automatic claim healing.
* For first bootstrap, run `bootstrapFirstAdmin` or an offline script to assign the initial admin.
* Never grant admin by editing Firestore directly; use the callable to ensure claim + audit log.

---
Document last updated: 2025‑09‑18