import 'package:wakelock_plus/wakelock_plus.dart';

/// A tiny helper to keep the screen on while any player is active.
/// Reference counted to support multiple players.
class WakelockHelper {
  static int _count = 0;

  static Future<void> acquire() async {
    _count++;
    if (_count == 1) {
      try { await WakelockPlus.enable(); } catch (_) {}
    }
  }

  static Future<void> release() async {
    if (_count > 0) _count--;
    if (_count == 0) {
      try { await WakelockPlus.disable(); } catch (_) {}
    }
  }
}
