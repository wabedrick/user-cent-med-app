import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'auth_log.dart';
import 'role_resolver.dart';

/// Lightweight cached access to role sources (custom claim & Firestore user doc).
/// Separation from providers makes it easier to unit test without Riverpod.
class RoleService {
  final fa.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  RoleService({fa.FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? fa.FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  DateTime _lastForce = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String?> fetchClaimRole({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    if (force) {
      final now = DateTime.now();
      if (now.difference(_lastForce) < const Duration(seconds: 5)) force = false; // throttle
    }
    try {
      final token = await user.getIdTokenResult(force);
      if (force) _lastForce = DateTime.now();
      final claimRole = token.claims?['role'];
      if (claimRole is String && claimRole.trim().isNotEmpty) {
        final r = claimRole.trim().toLowerCase();
        AuthLog.claim('fetched claim=$r force=$force');
        return r;
      }
    } catch (e) {
      AuthLog.claim('claim fetch error: $e');
    }
    return null;
  }

  Future<String?> fetchFirestoreRole() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final snap = await _db.collection('users').doc(user.uid).get();
      if (!snap.exists) return null;
      final role = (snap.data()?['role'] as String?)?.trim().toLowerCase();
      if (role != null) AuthLog.role('firestore role=$role');
      return role?.isNotEmpty == true ? role : null;
    } catch (e) {
      AuthLog.role('firestore role error: $e');
      return null;
    }
  }

  /// Unified effective role (claim preferred) with optional forced claim refresh.
  Future<String?> resolveRole({bool forceClaimRefresh = false}) async {
    final resolver = RoleResolver(
      claimFetcher: ({bool force = false}) => fetchClaimRole(force: force),
      firestoreFetcher: () => fetchFirestoreRole(),
    );
    return resolver.resolve(forceClaimRefresh: forceClaimRefresh);
  }
}
