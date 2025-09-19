import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/maintenance_schedule_model.dart';

class MaintenanceRepository {
  final FirebaseFirestore _db;
  MaintenanceRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('maintenance_schedules');

  Stream<List<MaintenanceSchedule>> allUpcoming() {
    final now = DateTime.now();
    return _col
        .where('dueDate', isGreaterThanOrEqualTo: now)
        .orderBy('dueDate')
        .snapshots()
        .map((s) => s.docs.map((d) => MaintenanceSchedule.fromMap(d.id, d.data())).toList());
  }

  Stream<List<MaintenanceSchedule>> assignedTo(String uid) {
    return _col
        .where('assignedTo', isEqualTo: uid)
        .where('completed', isEqualTo: false)
        .orderBy('dueDate')
        .snapshots()
        .map((s) => s.docs.map((d) => MaintenanceSchedule.fromMap(d.id, d.data())).toList());
  }

  Future<String> create(MaintenanceSchedule s) async {
    final doc = await _col.add(s.toMap());
    return doc.id;
  }

  Future<void> update(MaintenanceSchedule s) async {
    await _col.doc(s.id).update(s.toMap());
  }

  Future<void> markCompleted(String id, {bool value = true}) async {
    await _col.doc(id).update({'completed': value});
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) => MaintenanceRepository(FirebaseFirestore.instance));

final upcomingMaintenanceProvider = StreamProvider<List<MaintenanceSchedule>>((ref) => ref.read(maintenanceRepositoryProvider).allUpcoming());
final myMaintenanceProvider = StreamProvider.family<List<MaintenanceSchedule>, String>((ref, uid) => ref.read(maintenanceRepositoryProvider).assignedTo(uid));
