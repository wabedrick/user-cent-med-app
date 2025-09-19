import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'package:cloud_functions/cloud_functions.dart';

class UserRepository {
  final FirebaseFirestore _db;
  UserRepository(this._db);
  DocumentReference<Map<String, dynamic>> doc(String uid) => _db.collection('users').doc(uid);
  Stream<AppUser?> byId(String uid) => doc(uid).snapshots().map((d) => d.exists ? AppUser.fromMap(d.id, d.data()!) : null);

  /// Stream all users (capped) ordered by email for admin listing
  Stream<List<AppUser>> allUsers({int limit = 500}) {
    return _db
        .collection('users')
        .orderBy('email')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList());
  }

  /// Update role directly in Firestore (admin only per rules) AND optionally invoke Cloud Function
  /// to sync custom claims. If the callable fails we still keep the Firestore change.
  Future<void> updateUserRole({required String uid, required String newRole, bool callFunction = true}) async {
    if (callFunction) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('setUserRole');
        await callable.call(<String, dynamic>{'targetUid': uid, 'newRole': newRole});
        return; // Function handles Firestore + claims + audit log
      } catch (_) {
        // Fallback to direct Firestore update if function fails
      }
    }
    // Direct Firestore update (claims will lag until next admin-triggered claim sync)
    final ref = doc(uid);
    await ref.update({'role': newRole});
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(FirebaseFirestore.instance));

final userByIdProvider = StreamProvider.family<AppUser?, String>((ref, uid) => ref.read(userRepositoryProvider).byId(uid));
final usersListProvider = StreamProvider<List<AppUser>>((ref) => ref.read(userRepositoryProvider).allUsers());
