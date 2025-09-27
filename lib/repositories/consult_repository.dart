import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/consult_request_model.dart';
import 'dart:async';

class ConsultRepository {
  final _col = FirebaseFirestore.instance.collection('consult_requests');

  Future<void> createConsult({required String question}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final now = DateTime.now();
    await _col.add({
      'userId': uid,
      'question': question.trim(),
      'status': 'open',
      'claimedBy': null,
      'answer': null,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'answeredAt': null,
    });
  }

  Stream<List<ConsultRequest>> userConsults(String uid) {
    // Primary query requires composite index (userId asc, createdAt desc[, __name__ desc])
    final query = _col.where('userId', isEqualTo: uid).orderBy('createdAt', descending: true);
    final controller = StreamController<List<ConsultRequest>>();
    StreamSubscription? sub;
    StreamSubscription? fallbackSub;

    void attachFallback() {
      // Fallback: drop ordering (no composite index required) then sort client-side.
      fallbackSub = _col.where('userId', isEqualTo: uid).snapshots().listen((snap) {
        final list = snap.docs.map(ConsultRequest.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(list);
      }, onError: controller.addError);
    }

    sub = query.snapshots().listen((snap) {
      controller.add(snap.docs.map(ConsultRequest.fromDoc).toList());
    }, onError: (e, st) {
      // If index missing, fallback.
      if (e is FirebaseException && e.code == 'failed-precondition') {
        attachFallback();
      } else {
        controller.addError(e, st);
      }
    });

    controller.onCancel = () async {
      await sub?.cancel();
      await fallbackSub?.cancel();
    };
    return controller.stream;
  }

  // For engineers: open or claimed by self but still active
  Stream<List<ConsultRequest>> openConsults(String engineerId) {
    final query = _col.where('status', whereIn: ['open', 'claimed']).orderBy('createdAt');
    final controller = StreamController<List<ConsultRequest>>();
    StreamSubscription? sub;
    StreamSubscription? fallbackSub;

    void attachFallback() {
      fallbackSub = _col.where('status', whereIn: ['open', 'claimed']).snapshots().listen((snap) {
        final list = snap.docs.map(ConsultRequest.fromDoc).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        controller.add(list);
      }, onError: controller.addError);
    }

    sub = query.snapshots().listen((snap) {
      controller.add(snap.docs.map(ConsultRequest.fromDoc).toList());
    }, onError: (e, st) {
      if (e is FirebaseException && e.code == 'failed-precondition') {
        attachFallback();
      } else {
        controller.addError(e, st);
      }
    });

    controller.onCancel = () async {
      await sub?.cancel();
      await fallbackSub?.cancel();
    };
    return controller.stream;
  }

  Future<void> claim(String consultId, String engineerId) async {
    final ref = _col.doc(consultId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Not found');
      final data = snap.data() as Map<String, dynamic>;
      if (data['status'] != 'open') return; // someone else already claimed
      tx.update(ref, {
        'status': 'claimed',
        'claimedBy': engineerId,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    });
  }

  Future<void> answer(String consultId, String engineerId, String answer) async {
    final ref = _col.doc(consultId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Consult not found');
      final data = snap.data() as Map<String, dynamic>;
      // Only proceed if still claimed & not yet answered, and engineer matches claimer.
      if (data['status'] != 'claimed') {
        throw Exception('Consult no longer in claimed state');
      }
      final claimedBy = data['claimedBy'] as String?;
      if (claimedBy != null && claimedBy != engineerId) {
        throw Exception('Another engineer claimed this consult');
      }
      if (data['answer'] != null) {
        throw Exception('Consult already answered');
      }
      final now = Timestamp.fromDate(DateTime.now());
      tx.update(ref, {
        'status': 'answered',
        'answer': answer.trim(),
        'updatedAt': now,
        'answeredAt': now,
        'claimedBy': claimedBy ?? engineerId,
      });
    });
  }

  Future<void> close(String consultId) async {
    await _col.doc(consultId).update({
      'status': 'closed',
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }
}
