class RepairRequest {
  final String id;
  final String equipmentId;
  final String reportedByUserId;
  final String description;
  final String status;
  final DateTime timestamp;
  final String? assignedEngineerId;

  RepairRequest({
    required this.id,
    required this.equipmentId,
    required this.reportedByUserId,
    required this.description,
    required this.status,
    required this.timestamp,
    this.assignedEngineerId,
  });

  factory RepairRequest.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      try {
        // Firestore Timestamp has toDate(); dynamic call avoids import.
        final d = (v as dynamic).toDate();
        if (d is DateTime) return d;
      } catch (_) {}
      if (v is String) {
        try { return DateTime.parse(v); } catch (_) {}
      }
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
      return DateTime.now();
    }
    return RepairRequest(
      id: id,
      equipmentId: data['equipmentId'] ?? '',
      reportedByUserId: data['reportedByUserId'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? '',
      timestamp: parseDate(data['timestamp']),
      assignedEngineerId: data['assignedEngineerId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'reportedByUserId': reportedByUserId,
      'description': description,
      'status': status,
      'timestamp': timestamp,
      'assignedEngineerId': assignedEngineerId,
    };
  }
}
