import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
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
    final authUser = fa.FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const UnauthorizedScreen(requiredRole: 'Signed-In User', actualRole: 'none');
    }
      final roleAsync = ref.watch(userRoleProvider);
      return roleAsync.when(
        data: (role) {
          debugPrint('[RoleGate] resolved role=$role need=${allow.join(',')}');
          if (role == null) {
            return const UnauthorizedScreen();
          }
          // Only allow roles that are explicitly listed
          if (allow.contains(role)) {
            return builder(context, role);
          }
          return const UnauthorizedScreen();
      },
      loading: () => loading ?? const Center(child: CircularProgressIndicator()),
      error: (e, _) => const UnauthorizedScreen(),
    );
  }
}