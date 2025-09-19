import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    } catch (_) {
      // Best effort only
    }
  }
}
