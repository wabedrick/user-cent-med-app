import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../navigation/app_navigator.dart';

class MessagingService {
  static final _fln = FlutterLocalNotificationsPlugin();

  static Future<void> initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const init = InitializationSettings(android: android, iOS: ios);
    await _fln.initialize(init);
  }

  static Future<void> ensureRegistered(fa.User user) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'fcmToken': token}, SetOptions(merge: true));
      }
      FirebaseMessaging.onMessage.listen((m) async {
        final notif = m.notification;
        if (notif != null) {
          const android = AndroidNotificationDetails('default', 'General');
          const ios = DarwinNotificationDetails();
          const details = NotificationDetails(android: android, iOS: ios);
          await _fln.show(notif.hashCode, notif.title, notif.body, details);
        }
      });

      // Background / terminated tap handling (when app opened from notification)
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final data = m.data;
        final type = data['type'];
        if (type == 'consult_new') {
          final consultId = data['consultId'];
          if (consultId != null) {
            _setPendingConsult(consultId);
          }
        } else if (type == 'consult_answered') {
          final consultId = data['consultId'];
          if (consultId != null) {
            _setPendingConsult(consultId);
          }
        }
      });

      // If app was launched from terminated via notification
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final data = initialMessage.data;
        final t = data['type'];
        if ((t == 'consult_new' || t == 'consult_answered') && data['consultId'] != null) {
          _setPendingConsult(data['consultId']!);
        }
      }
    } catch (_) {
      // Best effort only
    }
  }

  static void _setPendingConsult(String consultId) {
    try {
      final container = ProviderScope.containerOf(appNavigatorKey.currentContext!, listen: false);
  container.read(pendingConsultNavigationProvider.notifier).set(consultId);
      // Navigate to root (RoleRouter decides engineer screen) if we have a navigator
      appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    } catch (e) {
      // swallow
    }
  }
}
