import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment_model.dart';

class EquipmentRepository {
  final FirebaseFirestore _db;
  EquipmentRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('equipment');

  Stream<List<Equipment>> all() {
    return _col.orderBy('name').snapshots().map((s) => s.docs.map((d) => Equipment.fromMap(d.id, d.data())).toList());
  }

  Stream<Equipment?> byId(String id) {
    return _col.doc(id).snapshots().map((d) => d.exists ? Equipment.fromMap(d.id, d.data()!) : null);
  }

  Future<String> create(Equipment e) async {
    final doc = await _col.add(e.toMap());
    return doc.id;
  }

  Future<void> update(Equipment e) async {
    await _col.doc(e.id).update(e.toMap());
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}

final equipmentRepositoryProvider = Provider<EquipmentRepository>((ref) => EquipmentRepository(FirebaseFirestore.instance));

final equipmentListProvider = StreamProvider<List<Equipment>>((ref) => ref.read(equipmentRepositoryProvider).all());

final equipmentByIdProvider = StreamProvider.family<Equipment?, String>((ref, id) => ref.read(equipmentRepositoryProvider).byId(id));
