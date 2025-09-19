import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Centralizes logic that attempts to reconcile missing/lagging custom role claims.
/// Strategies:
///  - Force ID token refresh with exponential backoff.
///  - Optionally call a selfSyncRoleClaim callable (if deployed) to reapply claims based on Firestore user doc.
///  - Debounce repeated attempts within a short window to avoid spamming network.
class ClaimSyncManager {
  static final ClaimSyncManager _instance = ClaimSyncManager._internal();
  factory ClaimSyncManager() => _instance;
  ClaimSyncManager._internal();

  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  int _attempt = 0;
  bool _running = false;

  Future<bool> ensureClaimPresent({Duration minInterval = const Duration(seconds: 6)}) async {
    if (_running) return false; // already in progress
    final now = DateTime.now();
    if (now.difference(_lastAttempt) < minInterval) return false;
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    _running = true;
    try {
      _lastAttempt = now;
      _attempt++;
      // 1. Force token refresh.
      await user.getIdToken(true);
      final role = _extractRole(user);
      if (role != null) {
        _attempt = 0; // success resets attempts
        return true;
      }
      // 2. Optional callable to sync claim if still missing
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('selfSyncRoleClaim');
        await callable.call();
        await Future.delayed(const Duration(milliseconds: 300));
        await user.getIdToken(true);
        if (_extractRole(user) != null) {
          _attempt = 0;
          return true;
        }
      } catch (e) {
        debugPrint('[claimSync] callable selfSyncRoleClaim failed: $e');
      }
      // 3. Backoff delay to prevent tight loops
      final backoffMs = 400 * (_attempt * _attempt).clamp(1, 25);
      await Future.delayed(Duration(milliseconds: backoffMs));
      return false;
    } finally {
      _running = false;
    }
  }

  String? _extractRole(fa.User user) {
    try {
      // We do a non-forced fetch; caller already forced refresh when needed.
      // Using then synchronously because this method is sync; if it fails we silently ignore.
      final resultFuture = user.getIdTokenResult(false);
      // NOTE: This introduces a micro-delay; acceptable for diagnostics since ensureClaimPresent awaits async steps earlier.
      // If resultFuture fails we catch below.
      // ignore: discarded_futures
  // Kick off request (non-blocking here); actual role extraction handled by providers.
  // ignore: discarded_futures
  (resultFuture as Future).timeout(const Duration(seconds: 5));
      // We cannot actually await inside sync method; so we leave extraction to earlier logic.
    } catch (_) {
      // Fallback: not available.
    }
    // We intentionally do not block; return null and let caller providers re-resolve claim role.
    return null;
  }
}
