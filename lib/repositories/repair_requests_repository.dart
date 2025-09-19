import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/repair_request_model.dart';

class RepairRequestsRepository {
  final FirebaseFirestore _db;
  RepairRequestsRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('repair_requests');

  // Streams
  Stream<List<RepairRequest>> myRequests(String userId) {
    return _col.where('reportedByUserId', isEqualTo: userId).orderBy('timestamp', descending: true).snapshots().map(
      (s) => s.docs.map((d) => RepairRequest.fromMap(d.id, d.data())).toList(),
    );
  }

  Stream<List<RepairRequest>> openUnassigned() {
    return _col.where('status', isEqualTo: 'open').where('assignedEngineerId', isNull: true).orderBy('timestamp', descending: true).snapshots().map(
      (s) => s.docs.map((d) => RepairRequest.fromMap(d.id, d.data())).toList(),
    );
  }

  Stream<List<RepairRequest>> assignedTo(String engineerId) {
    return _col.where('assignedEngineerId', isEqualTo: engineerId).where('status', whereIn: ['open', 'in_progress']).orderBy('timestamp', descending: true).snapshots().map(
      (s) => s.docs.map((d) => RepairRequest.fromMap(d.id, d.data())).toList(),
    );
  }

  // Writes
  Future<String> create({
    required String equipmentId,
    required String reportedByUserId,
    required String description,
  }) async {
    final doc = await _col.add({
      'equipmentId': equipmentId,
      'reportedByUserId': reportedByUserId,
      'description': description,
      'status': 'open',
      'timestamp': FieldValue.serverTimestamp(),
      'assignedEngineerId': null,
    });
    return doc.id;
  }

  Future<void> assignToSelf({required String requestId, required String engineerId}) async {
    await _col.doc(requestId).update({
      'assignedEngineerId': engineerId,
      'status': 'in_progress',
    });
  }

  Future<void> updateStatus({required String requestId, required String status}) async {
    await _col.doc(requestId).update({'status': status});
  }

  Future<void> updateDescription({required String requestId, required String description}) async {
    await _col.doc(requestId).update({'description': description});
  }
}

final repairRequestsRepositoryProvider = Provider<RepairRequestsRepository>((ref) {
  return RepairRequestsRepository(FirebaseFirestore.instance);
});

// Common streams
final myRepairRequestsProvider = StreamProvider.family<List<RepairRequest>, String>((ref, userId) {
  return ref.read(repairRequestsRepositoryProvider).myRequests(userId);
});

final openUnassignedRequestsProvider = StreamProvider<List<RepairRequest>>((ref) {
  return ref.read(repairRequestsRepositoryProvider).openUnassigned();
});

final assignedToMeRequestsProvider = StreamProvider.family<List<RepairRequest>, String>((ref, engineerId) {
  return ref.read(repairRequestsRepositoryProvider).assignedTo(engineerId);
});
