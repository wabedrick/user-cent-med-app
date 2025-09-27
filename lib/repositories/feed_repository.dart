import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post_model.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) => FeedRepository(FirebaseFirestore.instance));

class FeedRepository {
  final FirebaseFirestore _db;
  FeedRepository(this._db);

  // Stream latest posts, newest first. Supports simple pagination via lastDocument.
  Stream<List<Post>> watchLatest({DocumentSnapshot<Map<String, dynamic>>? startAfter, int limit = 10}) {
    Query<Map<String, dynamic>> q = _db.collection('posts').orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q.snapshots().map((snap) => snap.docs.map((d) => Post.fromDoc(d)).toList());
  }

  Future<List<Post>> fetchLatestOnce({DocumentSnapshot<Map<String, dynamic>>? startAfter, int limit = 10}) async {
    Query<Map<String, dynamic>> q = _db.collection('posts').orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.get();
    return snap.docs.map((d) => Post.fromDoc(d)).toList();
  }

  /// Fetch a single page of posts with accompanying last document for pagination.
  Future<({List<Post> posts, DocumentSnapshot<Map<String, dynamic>>? last})> fetchPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 10,
  }) async {
    Query<Map<String, dynamic>> q = _db.collection('posts').orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.get();
    final posts = snap.docs.map((d) => Post.fromDoc(d)).toList();
    final last = snap.docs.isEmpty ? null : snap.docs.last;
    return (posts: posts, last: last);
  }

  Future<void> toggleLike({required String postId, required String userId}) async {
    final doc = _db.collection('posts').doc(postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final likedBy = (data['likedBy'] as List?)?.cast<String>() ?? <String>[];
      int likeCount = (data['likeCount'] as num?)?.toInt() ?? 0;
      if (likedBy.contains(userId)) {
        likedBy.remove(userId);
        likeCount = likeCount > 0 ? likeCount - 1 : 0;
      } else {
        likedBy.add(userId);
        likeCount = likeCount + 1;
      }
      tx.update(doc, {
        'likedBy': likedBy,
        'likeCount': likeCount,
      });
    });
  }

  Future<void> createImagePost({
    required String authorId,
    required String authorName,
    required String authorHandle,
    String? authorAvatarUrl,
    String? title,
    required String caption,
    required List<String> imageUrls,
    String? equipmentId,
    String? equipmentName,
  }) async {
    await _db.collection('posts').add({
      'authorId': authorId,
      'authorName': authorName,
      'authorHandle': authorHandle,
      'authorAvatarUrl': authorAvatarUrl,
      'title': title,
      'caption': caption,
      'imageUrls': imageUrls,
      'kind': 'image',
      'equipmentId': equipmentId,
      'equipmentName': equipmentName,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'likedBy': <String>[],
    });
  }

  Future<void> createVideoPost({
    required String authorId,
    required String authorName,
    required String authorHandle,
    String? authorAvatarUrl,
    required String title,
    required String caption,
    required String videoUrl,
    String? fileName,
    String? equipmentId,
    String? equipmentName,
  }) async {
    await _db.collection('posts').add({
      'authorId': authorId,
      'authorName': authorName,
      'authorHandle': authorHandle,
      'authorAvatarUrl': authorAvatarUrl,
      'title': title,
      'caption': caption,
      'imageUrls': <String>[],
      'videoUrl': videoUrl,
      'fileName': fileName,
      'kind': 'video',
      'equipmentId': equipmentId,
      'equipmentName': equipmentName,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'likedBy': <String>[],
    });
  }

  Future<void> createManualPost({
    required String authorId,
    required String authorName,
    required String authorHandle,
    String? authorAvatarUrl,
    String? title,
    required String caption,
    required String fileUrl,
    String? fileName,
    String? equipmentId,
    String? equipmentName,
  }) async {
    await _db.collection('posts').add({
      'authorId': authorId,
      'authorName': authorName,
      'authorHandle': authorHandle,
      'authorAvatarUrl': authorAvatarUrl,
      'title': title,
      'caption': caption,
      'imageUrls': <String>[],
      'fileUrl': fileUrl,
      'fileName': fileName,
      'kind': 'manual',
      'equipmentId': equipmentId,
      'equipmentName': equipmentName,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'likedBy': <String>[],
    });
  }
}

// Simple feed provider that streams latest posts
final feedStreamProvider = StreamProvider.autoDispose<List<Post>>((ref) {
  return ref.read(feedRepositoryProvider).watchLatest(limit: 20);
});

/// Lightweight head stream (very small limit) used only to detect if new posts
/// have arrived while user scrolls older paginated list. We keep this tiny to
/// minimize snapshot bandwidth.
final feedHeadStreamProvider = StreamProvider.autoDispose<List<Post>>((ref) {
  return ref.read(feedRepositoryProvider).watchLatest(limit: 5);
});
