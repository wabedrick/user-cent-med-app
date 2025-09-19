import 'auth_log.dart';

/// Pure role resolution logic: prefers custom claim role, falls back to Firestore role.
/// Accepts injected async fetch functions so it can be unit tested without Firebase.
typedef ClaimFetcher = Future<String?> Function({bool force});
typedef FirestoreRoleFetcher = Future<String?> Function();

class RoleResolver {
  final ClaimFetcher _claimFetcher;
  final FirestoreRoleFetcher _firestoreFetcher;
  const RoleResolver({required ClaimFetcher claimFetcher, required FirestoreRoleFetcher firestoreFetcher})
      : _claimFetcher = claimFetcher,
        _firestoreFetcher = firestoreFetcher;

  Future<String?> resolve({bool forceClaimRefresh = false}) async {
    final claim = await _claimFetcher(force: forceClaimRefresh);
    if (claim != null) {
      AuthLog.role('resolver: using claim role=$claim');
      return claim;
    }
    AuthLog.role('resolver: claim missing; falling back to Firestore');
    return await _firestoreFetcher();
  }
}
