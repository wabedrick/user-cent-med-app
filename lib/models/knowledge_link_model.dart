class KnowledgeLink {
  final String id;
  final String title;
  final String url;
  final String type; // 'video' | 'pdf'
  final String? equipmentId;
  final String createdBy;
  final DateTime createdAt;
  final List<String> tags;


  KnowledgeLink({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    required this.createdBy,
    required this.createdAt,
    this.equipmentId,
    this.tags = const [],
  });

  factory KnowledgeLink.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      try { final d = (v as dynamic).toDate(); if (d is DateTime) return d; } catch (_) {}
      if (v is String) { try { return DateTime.parse(v); } catch (_) {} }
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }
    List<String> parseTags(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).cast<String>().toList();
      }
      return const [];
    }
    return KnowledgeLink(
      id: id,
      title: (data['title'] ?? '').toString(),
      url: (data['url'] ?? '').toString(),
      type: (data['type'] ?? '').toString(),
      equipmentId: (data['equipmentId'] as String?),
      createdBy: (data['createdBy'] ?? '').toString(),
      createdAt: parseDate(data['createdAt']),
      tags: parseTags(data['tags']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'url': url,
        'type': type,
        'equipmentId': equipmentId,
        'createdBy': createdBy,
        'createdAt': createdAt,
        'tags': tags,
      };
}
