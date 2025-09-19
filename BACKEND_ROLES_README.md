# Backend Role Management

## Overview
Roles are enforced via Firebase Authentication custom claims and mirrored in Firestore `users/{uid}` documents. The Flutter app first checks the custom claim; if absent it falls back to Firestore.

## Cloud Functions
- `setUserRole` (callable): Admin-only. Updates Firestore role, sets custom claim, writes audit log.
- `bootstrapFirstAdmin` (callable): One-time elevation using an environment secret.

### Deploy
From repo root:
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

Set env for bootstrap secret:
```bash
firebase functions:config:set bootstrap.secret="YOUR_LONG_RANDOM_SECRET"
```
(Alternatively use standard env var in hosting platform; adjust code if needed.)

### Bootstrapping First Admin
1. Sign up a user.
2. Call `bootstrapFirstAdmin` with the secret (temporary client script or curl via emulator).
3. Re-authenticate (getIdToken) to pull new custom claim.

### Changing Roles
The admin dashboard now calls `setUserRole` instead of writing directly. After change:
- Custom claim updated.
- Firestore doc updated.
- Audit entry stored in `audit_logs` (type: `role_change`).

### Firestore Rules
Rules use `request.auth.token.role` for authorization, reducing reads.

## Audit Log Structure
Collection: `audit_logs`
```
{
  type: 'role_change' | 'bootstrap_admin',
  targetUid: string,
  newRole?: string,
  changedBy?: string,
  ts: serverTimestamp()
}
```

### Next Hardening Ideas
- Add rate limiting (functions runWith limits or check last change time).
- Require multi-step verification for admin role assignments.
- Email notifications on role changes.
- Periodic script to verify Firestore role and custom claim consistency.
