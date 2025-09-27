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

## Consult Requests Security
The `consult_requests` collection enables a user-to-engineer Q&A workflow.

Allowed transitions (client-side):
1. User creates doc with: `userId`, `question`, `status='open'`, timestamps; no `claimedBy` or `answer`.
2. Engineer/Admin claims: `status: 'claimed'`, sets `claimedBy`, `updatedAt`.
3. Claimer answers: `status: 'answered'`, sets `answer`, `answeredAt`, `updatedAt`.
4. Owner OR engineer/admin closes: `status: 'closed'`, updates `updatedAt`.

Read access:
- Owner: can read their own consults.
- Engineers/Admins: can read all consults to view open/claimed/answered items.

Write validation (firestore.rules):
- Strict key whitelists per transition to prevent privilege escalation.
- Question length <= 2000 chars; answer length <= 10000 chars.
- Only claimer can answer; only engineer/admin can claim.
- No deletes (audit retention).

Deployment Reminder:
After modifying `firestore.rules`, deploy:
```bash
firebase deploy --only firestore:rules
```

Troubleshooting PERMISSION_DENIED on consults:
1. Confirm rules deployed (timestamp in console updates).
2. Re-login after assigning a role; custom claims require new ID token.
3. Ensure creation payload matches required keys & `status='open'`.
4. For claim/answer, verify current document `status` matches expected pre-state.

### Engineer Notifications & Concurrency Hardening

Notifications:
- A Cloud Function trigger `onConsultRequestCreate` sends an FCM push (`type=consult_new`) to all engineers & admins (tokens stored in `users.fcmToken`).
- Client `MessagingService` listens for notification taps (foreground/background/terminated) and routes engineers directly to the Consults view, storing a pending `consultId` in a provider for contextual focus (future highlight logic can consume this).

Answer Transaction Integrity:
- Repository `answer()` function now executes inside a Firestore transaction verifying:
	- Doc still exists
	- `status == 'claimed'`
	- `claimedBy` is either null or matches current engineer
	- `answer` is still null (single-write invariant)
	- It then atomically sets `status='answered'`, `answer`, `answeredAt`, `updatedAt` & (if needed) `claimedBy`.

Rule Hardening (added guards):
- Claim transition asserts original `answer` null and prevents injecting `answer` early.
- Answer transition asserts previous `answer == null`.
- Close transition asserts `answer` & `claimedBy` remain unchanged.

Operational Notes:
- If an engineer opens two devices and answers simultaneously, the first transaction wins; the second receives a local exception (client shows failure). Rules reject any second answer attempt because `resource.data.answer` is no longer null.
- If FCM tokens become invalid, they can be refreshed by signing in again; stale tokens are simply skipped (Firebase Admin SDK returns errors that we currently ignore silently—future improvement: prune invalid tokens).

Future Considerations:
- Add explicit highlighting of the pending consult after navigation.
- Implement pagination for large open consult backlogs.
- Introduce secondary notification when an answer is posted (notify the original user).
