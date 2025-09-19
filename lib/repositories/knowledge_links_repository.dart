import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/knowledge_link_model.dart';

class KnowledgeLinksRepository {
  final FirebaseFirestore _db;
  KnowledgeLinksRepository(this._db);
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('knowledge_links');

  Stream<List<KnowledgeLink>> all() {
    return _col.orderBy('createdAt', descending: true).snapshots().map(
      (s) => s.docs.map((d) => KnowledgeLink.fromMap(d.id, d.data())).toList(),
    );
  }

  Future<void> create({
    required String title,
    required String url,
    required String type,
    String? equipmentId,
    required String createdBy,
  }) async {
    await _col.add({
      'title': title,
      'titleLower': title.toLowerCase(),
      'url': url,
      'type': type,
      'equipmentId': equipmentId,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}

final knowledgeLinksRepositoryProvider = Provider<KnowledgeLinksRepository>((ref) => KnowledgeLinksRepository(FirebaseFirestore.instance));
final knowledgeLinksProvider = StreamProvider<List<KnowledgeLink>>((ref) => ref.read(knowledgeLinksRepositoryProvider).all());

// Firestore server-side prefix search (simple) when query >=2.
final knowledgeLinksSearchProvider = FutureProvider.family<List<KnowledgeLink>, String>((ref, query) async {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.length < 2) {
    return ref.watch(knowledgeLinksProvider).maybeWhen(data: (d) => d, orElse: () => []);
  }
  final col = FirebaseFirestore.instance.collection('knowledge_links');
  // NOTE: Requires composite index for orderBy titleLower if adding filters; currently simple range.
  final end = trimmed.substring(0, trimmed.length - 1) + String.fromCharCode(trimmed.codeUnitAt(trimmed.length - 1) + 1);
  final snap = await col
      .where('titleLower', isGreaterThanOrEqualTo: trimmed)
      .where('titleLower', isLessThan: end)
      .orderBy('titleLower')
      .limit(50)
      .get();
  return snap.docs.map((d) => KnowledgeLink.fromMap(d.id, d.data())).toList();
});
