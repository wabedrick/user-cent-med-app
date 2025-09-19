import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to trigger on-demand maintenance reminders (callable) and
/// optionally perform a local client-side daily check to surface due/overdue tasks.
class MaintenanceReminderService {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _notifications;
  final FirebaseAuth _auth;
  MaintenanceReminderService(this._functions, this._firestore, this._notifications, this._auth);

  Future<int> runCallable() async {
    final callable = _functions.httpsCallable('runMaintenanceReminders');
    final result = await callable();
    final data = result.data;
    if (data is Map && data['sent'] is int) return data['sent'] as int;
    return 0;
  }

  /// Local fallback: once per app-day per user.
  Future<int> localDailyScan({DateTime? now}) async {
    final user = _auth.currentUser;
    if (user == null) return 0;
    now ??= DateTime.now();
    // Simple in-memory day guard; for production persist (SharedPreferences)
    _lastRun ??= DateTime.fromMillisecondsSinceEpoch(0);
    if (_lastRun!.day == now.day && _lastRun!.month == now.month && _lastRun!.year == now.year) {
      return 0; // already ran today
    }
    _lastRun = now;
    final snap = await _firestore.collection('maintenance_schedules')
        .where('completed', isEqualTo: false)
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .get();
    int shown = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final assignedTo = data['assignedTo'];
      if (assignedTo == user.uid) {
        shown++;
        await _notifications.show(
          doc.id.hashCode & 0x7FFFFFFF,
          'Maintenance Due',
            'Task for equipment ${data['equipmentId']} is due/overdue.',
          const NotificationDetails(android: AndroidNotificationDetails('maintenance','Maintenance', importance: Importance.defaultImportance)),
        );
      }
    }
    return shown;
  }

  static DateTime? _lastRun;
}

final maintenanceReminderServiceProvider = Provider<MaintenanceReminderService>((ref) {
  return MaintenanceReminderService(
    FirebaseFunctions.instance,
    FirebaseFirestore.instance,
    FlutterLocalNotificationsPlugin(),
    FirebaseAuth.instance,
  );
});
