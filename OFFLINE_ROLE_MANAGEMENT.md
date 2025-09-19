# Offline Role Management (No Blaze Plan Needed)

This guide lets you manage user roles (admin / engineer / nurse) locally without deploying Cloud Functions or upgrading to the Blaze plan.

## Overview
You will run a local Node.js script using a Firebase service account. It sets custom claims (role) and updates the Firestore `users` collection plus an `audit_logs` entry, matching the production design.

## Prerequisites
1. Node.js 18+ installed.
2. A Firebase project already initialized (you have this).
3. A user has signed up via the app (so you can promote them).
4. Service account key JSON (NOT committed to git).

## Get Service Account Key
1. Go to Firebase Console > Project Settings > Service Accounts.
2. Click "Generate new private key". Confirm download.
3. Save the file as `serviceAccountKey.json` at the project root (`user-cent-med-app/`).
   - Alternatively store it elsewhere and set env var:
     - Windows PowerShell: `$env:GOOGLE_APPLICATION_CREDENTIALS='C:/full/path/key.json'`

## Install Dependencies
```pwsh
npm install
```
(Uses root `package.json` we added with `firebase-admin` dependency.)

## First Admin Bootstrap
Promote an existing user (who already signed up) to admin:
```pwsh
npm run roles:bootstrap -- --email youremail@example.com
```
This will:
- Set custom claim role=admin
- Ensure a `users/{uid}` doc exists with role=admin
- Write an `audit_logs` record

After this, have the user sign out and sign back in (or wait ~1 minute) so the ID token refreshes and the claim becomes active in the app.

## Set Role by UID
If you know the UID:
```pwsh
npm run roles:set -- --uid SOME_UID --role engineer
```
Roles allowed: `admin`, `engineer`, `nurse`.

## Set Role by Email
```pwsh
npm run roles:set-email -- --email nurse1@example.com --role engineer
```

## List Users (Optionally Filter Role)
```pwsh
npm run roles:list
npm run roles:list -- --role engineer
npm run roles:list -- --limit 50
```

## View Audit Logs
```pwsh
npm run roles:audit
npm run roles:audit -- --limit 100
```
Shows recent `audit_logs` documents with role changes and bootstrap events.

## App Behavior
The Flutter app already prefers custom claims for role resolution. Once you assign a role via this script and the user refreshes their ID token (sign out/in or wait), the correct dashboard loads.

## Token Refresh Tips
- Fastest: Add a temporary button in app to `FirebaseAuth.instance.currentUser?.getIdToken(true)` (optional dev helper) OR just sign out/in.
- Automatic refresh occurs roughly hourly if user stays signed in.

## Security Notes
- Never commit `serviceAccountKey.json`.
- Consider adding it to `.gitignore` (if not already):
  ```
  serviceAccountKey.json
  ```
- Restrict file access (filesystem permissions) if on a shared machine.

## Migration to Cloud Functions Later
When you upgrade to Blaze and deploy functions:
1. Remove local bootstrap usage (or keep for emergency—just secure the key).
2. Admin UI can keep using callable `setUserRole` without changes.
3. The audit log format is consistent.

## Troubleshooting
| Problem | Cause | Fix |
|---------|-------|-----|
| Error: Missing credentials | No key file or env var | Place `serviceAccountKey.json` or set `GOOGLE_APPLICATION_CREDENTIALS` |
| User shows old role | ID token cached | Sign out/in or force token refresh |
| Role not in table | User never signed in | Have user sign in once (creates Auth record) |
| Permission denied in app after role change | Token stale | Refresh token as above |

## Example Workflow (Fresh Project)
```pwsh
# 1. User signs up via app with youremail@example.com
# 2. You bootstrap admin
npm run roles:bootstrap -- --email youremail@example.com
# 3. Sign out/in in the app -> See Admin Dashboard
# 4. Create another test account in the app
# 5. Promote that account to engineer by email
npm run roles:set-email -- --email engineer1@example.com --role engineer
# 6. List all users
npm run roles:list
# 7. View audit logs
npm run roles:audit
```

## Accepted Roles
- admin
- engineer
- nurse

Anything else is rejected.

## Extending Script (Optional)
You can add more commands (e.g., delete-role, sync-docs) inside `scripts/role_manager.js` following existing patterns.

---
Maintains production parity for RBAC logic while avoiding Blaze plan until you're ready.
