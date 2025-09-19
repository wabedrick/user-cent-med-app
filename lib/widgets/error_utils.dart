import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Maps technical errors to short, user-friendly messages.
String friendlyMessageFor(Object error) {
  final msg = error.toString();
  // Auth-specific
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'permission-denied':
      case 'permission_denied':
        return 'You don’t have permission to do that.';
      case 'network-request-failed':
        return 'You’re offline. Please check your internet connection.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'We couldn’t find your account.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Something went wrong with sign-in. Please try again.';
    }
  }
  // Firestore/Functions
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You don’t have permission to do that.';
      case 'not-found':
        return 'This item could not be found.';
      case 'already-exists':
        return 'That already exists.';
      case 'cancelled':
        return 'The request was cancelled.';
      case 'deadline-exceeded':
      case 'unavailable':
      case 'aborted':
        return 'The service is temporarily unavailable. Please try again.';
      default:
        // Continue to generic mapping
        break;
    }
  }
  // Timeouts and connectivity
  if (error is TimeoutException || msg.toLowerCase().contains('timeout')) {
    return 'This is taking longer than expected. Please try again.';
  }
  if (msg.toLowerCase().contains('network') || msg.toLowerCase().contains('failed host lookup')) {
    return 'You’re offline. Please check your internet connection.';
  }
  // Permission-denied text fallback
  if (msg.toLowerCase().contains('permission-denied')) {
    return 'You don’t have permission to do that.';
  }
  return 'Something went wrong. Please try again.';
}

/// Shows a SnackBar with a friendly error, optionally with a fallback message.
void showFriendlyError(BuildContext context, Object error, {String? fallback}) {
  final text = fallback ?? friendlyMessageFor(error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text)),
  );
}

/// A compact error view suitable for AsyncValue.error or general failures.
class FriendlyErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final String? title;
  const FriendlyErrorView({super.key, required this.error, this.onRetry, this.title});

  @override
  Widget build(BuildContext context) {
    final msg = friendlyMessageFor(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
            ],
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
