import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Unified role provider:
/// 1. Refreshes ID token to get latest custom claim.
/// 2. If claim missing, falls back to Firestore users/{uid}.role
/// 3. Normalizes to lowercase.
/// 4. Returns null if still unknown (caller decides fallback UI).
// Throttle token refreshes to avoid spamming network (e.g., many widgets watching role).
class _RoleCache {
  DateTime lastTokenRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  String? lastResolvedRole;
}

final _roleCacheProvider = Provider<_RoleCache>((_) => _RoleCache());

/// Expose raw custom claim (without Firestore fallback) for debugging.
final roleClaimProvider = FutureProvider<String?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final cache = ref.read(_roleCacheProvider);
  final now = DateTime.now();
  // Only force refresh every 15s unless explicitly invalidated.
  final forceRefresh = now.difference(cache.lastTokenRefresh) > const Duration(seconds: 15);
  try {
    final token = await user.getIdTokenResult(forceRefresh);
    if (forceRefresh) cache.lastTokenRefresh = now;
    final claimRole = token.claims?['role'];
    if (claimRole is String && claimRole.trim().isNotEmpty) {
      return claimRole.trim().toLowerCase();
    }
  } catch (_) {}
  return null;
});

/// Firestore user doc role (may lag behind claims briefly if backend updating).
final firestoreUserRoleProvider = FutureProvider<String?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  try {
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!snap.exists) return null;
    final docRole = (snap.data()?['role'] as String?)?.trim().toLowerCase();
    return (docRole != null && docRole.isNotEmpty) ? docRole : null;
  } catch (_) {
    return null;
  }
});

/// Unified role provider (claim preferred, Firestore fallback)
final userRoleProvider = FutureProvider<String?>((ref) async {
  final claim = await ref.watch(roleClaimProvider.future);
  if (claim != null) return claim;
  return await ref.watch(firestoreUserRoleProvider.future);
});

/// Helper to explicitly force a role re-resolution (e.g., after calling setUserRole for self).
void forceRoleReload(WidgetRef ref) {
  ref.invalidate(roleClaimProvider);
  ref.invalidate(firestoreUserRoleProvider);
  ref.invalidate(userRoleProvider);
}

extension RoleChecks on AsyncValue<String?> {
  bool get isAdmin => maybeWhen(data: (r) => r == 'admin', orElse: () => false);
  bool get isEngineer => maybeWhen(data: (r) => r == 'engineer', orElse: () => false);
  bool get isNurse => maybeWhen(data: (r) => r == 'nurse', orElse: () => false); // legacy
  bool get isMedic => maybeWhen(data: (r) => r == 'medic', orElse: () => false);
  bool get canManageKnowledge => isAdmin || isEngineer;
  bool get isKnown => maybeWhen(data: (r) => r != null, orElse: () => false);
}

/// Combined diagnostic provider returning both sources.
class RoleDiagnostics {
  final String? claim;
  final String? firestore;
  const RoleDiagnostics({this.claim, this.firestore});
  bool get mismatch => claim != null && firestore != null && claim != firestore;
  String? get effective => claim ?? firestore;
}

final roleDiagnosticsProvider = FutureProvider<RoleDiagnostics>((ref) async {
  final claim = await ref.watch(roleClaimProvider.future);
  final fs = await ref.watch(firestoreUserRoleProvider.future);
  return RoleDiagnostics(claim: claim, firestore: fs);
});