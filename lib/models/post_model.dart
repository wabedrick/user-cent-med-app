import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorHandle; // persisted stable handle (may be absent on legacy docs)
  final String? authorAvatarUrl;
  final String? title; // optional label/name for the post
  final String caption;
  final List<String> imageUrls; // zero or more images
  final String kind; // 'image' | 'video' | 'manual' (default 'image')
  final String? videoUrl; // when kind == 'video'
  final String? fileUrl; // when kind == 'manual' (pdf)
  final String? fileName; // display name for manual/video
  final String? equipmentId;
  final String? equipmentName;
  final Timestamp createdAt;
  final int likeCount;
  final List<String> likedBy; // small, sampled list for quick UI; source-of-truth is likeCount

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.authorAvatarUrl,
    required this.title,
    required this.caption,
    required this.imageUrls,
    required this.kind,
    required this.videoUrl,
    required this.fileUrl,
    required this.fileName,
    required this.equipmentId,
    required this.equipmentName,
    required this.createdAt,
    required this.likeCount,
    required this.likedBy,
  });

  bool likedByUser(String uid) => likedBy.contains(uid);

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Post(
      id: doc.id,
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Unknown',
      authorHandle: d['authorHandle'] as String?,
      authorAvatarUrl: d['authorAvatarUrl'] as String?,
      title: d['title'] as String?,
      caption: d['caption'] as String? ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? const <String>[],
      kind: (d['kind'] as String?)?.toLowerCase() ?? 'image',
      videoUrl: d['videoUrl'] as String?,
      fileUrl: d['fileUrl'] as String?,
      fileName: d['fileName'] as String?,
      equipmentId: d['equipmentId'] as String?,
      equipmentName: d['equipmentName'] as String?,
      createdAt: d['createdAt'] is Timestamp ? d['createdAt'] as Timestamp : Timestamp.now(),
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      likedBy: (d['likedBy'] as List?)?.cast<String>() ?? const <String>[],
    );
  }

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
    'authorHandle': authorHandle,
        'authorAvatarUrl': authorAvatarUrl,
        'caption': caption,
        'imageUrls': imageUrls,
        'kind': kind,
        'videoUrl': videoUrl,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'createdAt': createdAt,
        'likeCount': likeCount,
        'likedBy': likedBy,
      };
}
