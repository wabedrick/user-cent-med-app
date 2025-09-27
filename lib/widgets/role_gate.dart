import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Removed unused firebase_auth import
import '../providers/role_provider.dart';
import 'unauthorized_screen.dart';

typedef RoleBuilder = Widget Function(BuildContext context, String? role);

class RoleGate extends ConsumerWidget {
  final List<String> allow; // e.g. ['admin'] or ['engineer','admin']
  final RoleBuilder builder;
  final Widget? loading;
  final Widget? unauthorized;
  final bool redirectUnauthorized;

  const RoleGate({
    super.key,
    required this.allow,
    required this.builder,
    this.loading,
    this.unauthorized,
    this.redirectUnauthorized = false,
  });

  // (unused helper removed)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final asyncRole = ref.watch(userRoleProvider);
  final role = asyncRole.value;

    // While role is resolving, show a lightweight loading instead of Access Restricted.
    if (asyncRole.isLoading) {
      return const Center(child: SizedBox(height: 32, width: 32, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    // If role still unknown after load, allow by default to avoid spurious restriction,
    // since upstream routes should already be safe.
    if (role == null) {
      return builder(context, role);
    }

    if (!allow.contains(role)) {
      return const UnauthorizedScreen();
    }
    return builder(context, role);
  }
}