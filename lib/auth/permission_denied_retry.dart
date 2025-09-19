import 'dart:async';

typedef AsyncOperation<T> = Future<T> Function();

/// Wraps Firestore / Storage operations to attempt a single claim refresh if a
/// permission-denied error occurs due to a likely missing custom claim.
Future<T> runWithPermissionRetry<T>(AsyncOperation<T> op, {Future<bool> Function()? onPermissionDenied}) async {
  try {
    return await op();
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('permission-denied')) {
      if (onPermissionDenied != null) {
        final recovered = await onPermissionDenied();
        if (recovered) {
          // one retry only
          return await op();
        }
      }
    }
    rethrow;
  }
}
