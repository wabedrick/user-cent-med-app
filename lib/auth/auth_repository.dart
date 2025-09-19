import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Contract for sign-in / sign-up / sign-out plus user document provisioning.
/// Keeps Firebase interaction logic in one place so UI stays declarative.
class AuthRepository {
  final fa.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  AuthRepository({fa.FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? fa.FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  Stream<fa.User?> authState() => _auth.authStateChanges();

  fa.User? get currentUser => _auth.currentUser;

  Future<fa.UserCredential> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _postAuthProvision(cred.user);
    return cred;
  }

  Future<fa.UserCredential> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await _postAuthProvision(cred.user, creating: true);
    return cred;
  }

  Future<void> signOut() => _auth.signOut();

  /// Ensure user profile exists; safe against racing concurrent clients.
  Future<void> _postAuthProvision(fa.User? user, {bool creating = false}) async {
    if (user == null) return;
    // Always force refresh so any server-side custom claims assigned shortly after sign-in are picked up.
    try { await user.getIdToken(true); } catch (_) {}
    final doc = _db.collection('users').doc(user.uid);
    try {
      final snap = await doc.get();
      if (!snap.exists) {
        // Do not set admin by default; keep minimal fields.
        await doc.set({
          'email': user.email,
          'emailLower': (user.email ?? '').toLowerCase(),
          'role': 'engineer', // safe default
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Intentionally swallow permission-denied to avoid blocking UI; rules may restrict self-provision.
    }
  }
}
