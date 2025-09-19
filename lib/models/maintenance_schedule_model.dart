class MaintenanceSchedule {
  final String id;
  final String equipmentId;
  final DateTime dueDate;
  final String assignedTo;
  final bool completed;

  MaintenanceSchedule({
    required this.id,
    required this.equipmentId,
    required this.dueDate,
    required this.assignedTo,
    required this.completed,
  });

  factory MaintenanceSchedule.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      try {
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
    return MaintenanceSchedule(
      id: id,
      equipmentId: data['equipmentId'] ?? '',
      dueDate: parseDate(data['dueDate']),
      assignedTo: data['assignedTo'] ?? '',
      completed: data['completed'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'dueDate': dueDate,
      'assignedTo': assignedTo,
      'completed': completed,
    };
  }
}
