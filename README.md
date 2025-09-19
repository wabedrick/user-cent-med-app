# User-Centered Medical Equipment App

MVP built with Flutter + Firebase (Auth, Firestore). Includes role-based access (engineer, nurse, admin).

## Firestore Rules: Publish & Verify

Use either Console or CLI to ensure rules are active on your Firebase project.

### Option A: Firebase Console (fastest)
1. Open Firebase Console → Firestore Database → Rules
2. Paste the contents of `firestore.rules`
3. Click Publish
4. (Optional) Use "Rules Playground" to test reads/writes with a specific uid/claim

### Option B: Firebase CLI
1. Install CLI (once):
	```powershell
	npm install -g firebase-tools
	```
2. Login and select your project:
	```powershell
	firebase login
	firebase use <your-project-id>
	```
3. Deploy rules from the repo root:
	```powershell
	firebase deploy --only firestore:rules
	```

Verify that:
- `users/{uid}`: a user can create/read/update their own doc; delete is denied.
- Admin claim (`request.auth.token.role == 'admin'`) can read users and `audit_logs`.

## Managing Roles without Cloud Functions

We provide a local script (no Blaze required) to set roles via Admin SDK.
See `OFFLINE_ROLE_MANAGEMENT.md` for full instructions. Common commands:

```powershell
# Promote by email
npm run roles:set-email -- --email "alice@example.com" --role admin

# List users and roles
npm run roles:list

# View recent audit logs
npm run roles:audit
```

After changing roles, sign out and sign in again in the app (or tap "Refresh token").

## App Auth Notes

- On sign-in/sign-up, the app refreshes the ID token and ensures your user doc exists.
- If reads are denied before your doc exists, the app attempts a self-create (per rules).
- Admin dashboard disables in-app role changes unless Cloud Functions are deployed.

## Running the App

From project root:
```powershell
flutter pub get
flutter run
```

Optional flags:
```powershell
# Force app to open on Sign In
flutter run --dart-define=FORCE_SIGNOUT=true

# Default role for new users (engineer|nurse|admin)
flutter run --dart-define=DEFAULT_ROLE=engineer
```
