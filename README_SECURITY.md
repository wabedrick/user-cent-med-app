# Firestore Security & Roles

## Overview
This app uses a `users/{uid}` document to store each user's role (engineer, nurse, admin). Role-based decisions (UI + security rules) depend on that document existing.

## Rules File
See `firestore.rules` for current enforced logic:
- Users: can create their own doc, read/update only their own, no deletes.
- Equipment: any signed-in user can read; only engineer/admin can create/update; only admin can delete.
- All other paths: denied.

### Admin Enhancements
If the signed-in user's role is `admin`, they may read/update any user document to adjust roles. Regular users remain restricted to their own document.

## Deploying Rules
```bash
firebase deploy --only firestore:rules
```
Or via console: Firestore -> Rules -> paste -> Publish.

## Creating User Docs
On first sign-in the app auto-creates the user document with the default role (engineer unless overridden with `--dart-define=DEFAULT_ROLE=`). If a permission error occurs:
1. Confirm the rules are deployed.
2. Ensure you signed in so `request.auth` is non-null.
3. Check that no prior rule blocks `/users/{uid}` creation.

## Changing Roles Safely
1. Open Firestore console.
2. Go to `users` collection.
3. Edit the `role` field (`engineer`, `nurse`, or `admin`).
4. Sign out & sign back in in the app.

## Troubleshooting Permission Denied
- `permission-denied` while reading role: rules not updated or missing user doc.
- Verify path: `users/<auth.uid>`.
- If doc exists but still denied, confirm lowercase field: `role`.

## Next Hardening Steps
- Add audit log collection (append-only) for role changes.
- Enforce role changes only by admin via Cloud Function.
- Add Firestore composite indexes as features expand.
