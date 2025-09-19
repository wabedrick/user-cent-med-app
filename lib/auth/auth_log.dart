import 'package:flutter/foundation.dart';

class AuthLog {
  static void d(String message) => debugPrint('[auth] $message');
  static void role(String message) => debugPrint('[role] $message');
  static void claim(String message) => debugPrint('[claim] $message');
}
