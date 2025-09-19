import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../auth/role_service.dart';
import '../auth/claim_sync_manager.dart';
import '../auth/auth_log.dart';
// (Legacy role provider import no longer needed here)
import '../widgets/role_gate.dart';
import '../dashboard/admin_dashboard.dart';
import '../dashboard/engineer_dashboard.dart';
import '../dashboard/nurse_dashboard.dart';
import 'sign_in_screen.dart';
import '../widgets/error_utils.dart';

/// UnifiedAuthGate centralizes:
///  - Firebase initialization error (optional external provider hook)
///  - Auth state (signed out / loading / error)
///  - Role resolution with claim-backed admin enforcement
///  - Retry + claim sync loop with bounded backoff
///  - Final routing into appropriate dashboard widget
class UnifiedAuthGate extends ConsumerStatefulWidget {
  const UnifiedAuthGate({super.key});
  @override
  ConsumerState<UnifiedAuthGate> createState() => _UnifiedAuthGateState();
}

class _UnifiedAuthGateState extends ConsumerState<UnifiedAuthGate> {
  final _roleService = RoleService();
  AsyncValue<fa.User?> _auth = const AsyncValue.loading();
  AsyncValue<String?> _role = const AsyncValue.loading();
  StreamSubscription<fa.User?>? _authSub;
  int _roleAttempts = 0;
  Timer? _roleTimer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _listenAuth();
  }

  void _listenAuth() {
    _authSub = fa.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_disposed) return;
      AuthLog.d('auth state changed uid=${user?.uid}');
      setState(() => _auth = AsyncValue.data(user));
      if (user != null) {
        _resolveRole(initial: true);
      } else {
        _roleAttempts = 0;
        setState(() => _role = const AsyncValue.loading());
      }
    }, onError: (e, st) {
      if (_disposed) return;
      AuthLog.d('auth stream error: $e');
      setState(() => _auth = AsyncValue.error(e, st));
    });
  }

  Future<void> _resolveRole({bool forceClaim = false, bool initial = false}) async {
    if (_disposed) return;
    setState(() => _role = const AsyncValue.loading());
    try {
      final resolved = await _roleService.resolveRole(forceClaimRefresh: forceClaim);
      AuthLog.role('resolved role candidate=$resolved attempts=$_roleAttempts');
      if (resolved == 'admin') {
        final claim = await _roleService.fetchClaimRole();
        if (claim != 'admin') {
          AuthLog.claim('admin Firestore role detected but claim=$claim; triggering sync');
          ClaimSyncManager().ensureClaimPresent();
          if (_roleAttempts < 6) {
            _roleAttempts++;
            _roleTimer?.cancel();
            final delay = Duration(milliseconds: 250 * _roleAttempts);
            _roleTimer = Timer(delay, () => _resolveRole(forceClaim: true));
          }
          setState(() => _role = const AsyncValue.loading());
          return;
        }
      }
      _roleAttempts = 0;
      setState(() => _role = AsyncValue.data(resolved));
    } catch (e, st) {
      AuthLog.role('role resolution error: $e');
      setState(() => _role = AsyncValue.error(e, st));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _roleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _auth.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
  error: (e, _) => Scaffold(body: FriendlyErrorView(error: e, title: 'Couldn’t sign you in', onRetry: () => _listenAuth())),
      data: (user) {
        if (user == null) return const SignInScreen();
        return _role.when(
          loading: () => const _RoleLoading(),
          error: (e, _) => Scaffold(body: FriendlyErrorView(error: e, title: 'Couldn’t determine your access', onRetry: () => _resolveRole(forceClaim: true))),
          data: (role) {
            if (role == null) {
              return _StalledRole(onRetry: () => _resolveRole(forceClaim: true));
            }
            switch (role) {
              case 'admin':
                return RoleGate(allow: const ['admin'], builder: (_, __) => const AdminDashboardScreen());
              case 'engineer':
                return RoleGate(allow: const ['engineer','admin'], builder: (_, __) => const EngineerDashboardScreen());
              case 'nurse': // legacy
              case 'medic':
                return RoleGate(allow: const ['nurse','medic','admin'], builder: (_, __) => const NurseDashboardScreen());
              default:
                return _StalledRole(onRetry: () => _resolveRole(forceClaim: true));
            }
          },
        );
      },
    );
  }
}

class _RoleLoading extends StatelessWidget {
  const _RoleLoading();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _StalledRole extends StatelessWidget {
  final VoidCallback onRetry;
  const _StalledRole({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text('Resolving your access role… If this takes too long you can retry or sign out.' , textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ElevatedButton(onPressed: () async { try { await fa.FirebaseAuth.instance.signOut(); } catch (_) {} }, child: const Text('Sign Out')),
            ]),
          ],
        ),
      ),
    );
  }
}

// (unused _ErrorScaffold removed; FriendlyErrorView is used instead)
