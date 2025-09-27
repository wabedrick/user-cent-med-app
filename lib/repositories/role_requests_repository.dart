import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleRequestsRepository {
  final FirebaseFirestore _db;
  RoleRequestsRepository(this._db);

  /// Submits a role request for the given [uid].
  /// Uses the document id as the uid to prevent duplicates.
  Future<void> submitEngineerRequest({
    required String uid,
    String? email,
    String? displayName,
  }) async {
    final docRef = _db.collection('role_requests').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists) {
        final data = snap.data();
        final status = (data?['status'] as String?)?.toLowerCase();
        if (status == 'pending') {
          throw StateError('Request already pending');
        }
      }
      tx.set(docRef, {
        'uid': uid,
        'requestedRole': 'engineer',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
      }, SetOptions(merge: true));
    });
  }

  /// Watches the current user's role request document (null if none exists)
  Stream<Map<String, dynamic>?> watchMyRequest(String uid) {
    return _db.collection('role_requests').doc(uid).snapshots().map((snap) => snap.data());
  }

  /// Stream all pending role requests (requestedRole='engineer' currently)
  Stream<List<Map<String, dynamic>>> watchPending({int limit = 100}) {
    return _db
        .collection('role_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return {
                ...data,
                'id': d.id,
              };
            }).toList());
  }

  Future<void> markApproved({required String uid, required String adminUid}) async {
    final ref = _db.collection('role_requests').doc(uid);
    await ref.set({
      'status': 'approved',
      'approvedBy': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markDenied({required String uid, required String adminUid, String? reason}) async {
    final ref = _db.collection('role_requests').doc(uid);
    await ref.set({
      'status': 'denied',
      'deniedBy': adminUid,
      if (reason != null) 'reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final roleRequestsRepositoryProvider = Provider<RoleRequestsRepository>((ref) {
  return RoleRequestsRepository(FirebaseFirestore.instance);
});

final roleRequestByUidProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, uid) {
  return ref.read(roleRequestsRepositoryProvider).watchMyRequest(uid);
});

final pendingRoleRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(roleRequestsRepositoryProvider).watchPending();
});
