import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/role_provider.dart' show userRoleProvider; // legacy unified role provider (will be phased out)
import 'auth/role_service.dart';
import 'auth/claim_sync_manager.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'theme.dart';
import 'dashboard/nurse_dashboard.dart';
import 'dashboard/engineer_dashboard.dart';
import 'dashboard/admin_dashboard.dart';
import 'widgets/role_gate.dart';
// sign_in_screen imported indirectly via UnifiedAuthGate
import 'auth/unified_auth_gate.dart';
import 'equipment/equipment_list_page.dart';
import 'features/maintenance/maintenance_list_page.dart';
import 'features/knowledge/knowledge_center_page.dart';
import 'features/assistant/assistant_chat_screen.dart';
import 'widgets/error_utils.dart';
// Add localization + messaging service imports
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/messaging_service.dart';

// Configurable default role via --dart-define=DEFAULT_ROLE=engineer|nurse|admin
const String _envDefaultRole = String.fromEnvironment('DEFAULT_ROLE');
final String kDefaultRole = (_envDefaultRole == 'engineer' || _envDefaultRole == 'nurse' || _envDefaultRole == 'admin')
    ? _envDefaultRole
    : 'engineer';
bool get kDefaultRoleIsValid => kDefaultRole == 'engineer' || kDefaultRole == 'nurse' || kDefaultRole == 'admin';
// For self-provisioning user docs, never write 'admin' to satisfy rules; clamp to non-admin.
String get kSafeSelfCreateRole => (kDefaultRole == 'admin') ? 'engineer' : (kDefaultRoleIsValid ? kDefaultRole : 'engineer');

// Dev flag to force sign-out at launch so app opens on Sign In screen
const String _envForceSignOut = String.fromEnvironment('FORCE_SIGNOUT');
bool get kForceSignOutOnLaunch => _envForceSignOut == 'true' || _envForceSignOut == '1' || _envForceSignOut.toLowerCase() == 'yes';

// Firebase init error provider placeholder (can be overridden in runApp)
final firebaseInitErrorProvider = Provider<String?>((_) => null);

// Auth state stream provider
final authStateProvider = StreamProvider<fa.User?>((ref) {
  return fa.FirebaseAuth.instance.authStateChanges().map((u) {
    debugPrint('[auth] user=${u?.uid}');
    // Register FCM token on sign-in
    if (u != null) {
      MessagingService.ensureRegistered(u);
    }
    return u;
  });
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? initError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Initialize local notifications
    await MessagingService.initLocalNotifications();
    if (kForceSignOutOnLaunch) {
      try {
        await fa.FirebaseAuth.instance.signOut();
        debugPrint('[auth] Forced sign-out on launch (FORCE_SIGNOUT)');
      } catch (_) {}
    }
  } catch (e) {
    initError = e.toString();
  }
  runApp(ProviderScope(
    overrides: [firebaseInitErrorProvider.overrideWithValue(initError)],
    child: const App(),
  ));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Med Equip Manager',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Add basic localization support
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
      ],
  home: const UnifiedAuthGate(),
      routes: {
        '/equipment': (_) => const EquipmentListPage(),
        '/maintenance': (_) => const MaintenanceListPage(),
        '/knowledge': (_) => const KnowledgeCenterPage(),
        '/assistant': (_) => const AssistantChatScreen(),
      },
    );
  }
}

// Legacy AuthGate removed; functionality consolidated into UnifiedAuthGate.

/// Ensures we proactively refresh the ID token upon entering the authenticated
/// area and when app lifecycle resumes, so newly granted custom claims (e.g.,
/// admin) take effect without confusing permission_denied errors.
class TokenRefresher extends StatefulWidget {
  final Widget child;
  const TokenRefresher({super.key, required this.child});
  @override
  State<TokenRefresher> createState() => _TokenRefresherState();
}

class _TokenRefresherState extends State<TokenRefresher> with WidgetsBindingObserver {
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick off a refresh shortly after build to avoid blocking UI.
    scheduleMicrotask(_refreshTokenIfNeeded);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTokenIfNeeded();
    }
  }

  Future<void> _refreshTokenIfNeeded() async {
    final now = DateTime.now();
    if (now.difference(_lastRefresh) < const Duration(seconds: 20)) return;
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.getIdToken(true);
      _lastRefresh = DateTime.now();
      debugPrint('[auth] ID token refreshed');
    } catch (e) {
      debugPrint('[auth] token refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ensure user document exists with default role when first seen
Future<void> ensureUserDoc(fa.User user) async {
  // Make sure we use a fresh token to reduce permission_denied due to stale claims
  try { await user.getIdToken(true); } catch (_) {}
  final users = FirebaseFirestore.instance.collection('users');
  final doc = users.doc(user.uid);
  int attempt = 0;
  while (true) {
    attempt++;
    try {
      final snap = await doc.get().timeout(const Duration(seconds: 6), onTimeout: () => throw TimeoutException('get user doc timeout'));
      if (!snap.exists) {
        await doc
            .set({
              'email': user.email,
              'displayName': user.displayName,
              'emailLower': (user.email ?? '').toLowerCase(),
              'role': kSafeSelfCreateRole,
              'createdAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 6), onTimeout: () => throw TimeoutException('create user doc timeout'));
      }
      return;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Rules deny reads/writes (likely not published yet). Skip creation and proceed.
        debugPrint('ensureUserDoc: permission-denied reading user doc; skipping self-create');
        return;
      }
      if (e.code == 'unavailable' && attempt < 4) {
        final backoff = Duration(milliseconds: 300 * attempt * attempt);
        debugPrint('ensureUserDoc unavailable attempt=$attempt backoff=${backoff.inMilliseconds}');
        await Future.delayed(backoff);
        continue;
      }
      rethrow;
    } on TimeoutException {
      if (attempt < 4) {
        final backoff = Duration(milliseconds: 300 * attempt * attempt);
        debugPrint('ensureUserDoc timeout attempt=$attempt backoff=${backoff.inMilliseconds}');
        await Future.delayed(backoff);
        continue;
      }
      rethrow;
    }
  }
}
// (Removed duplicate userRoleProvider – now sourced from providers/role_provider.dart)

// Debug role override using ChangeNotifier so UI rebuilds when value changes.
class RoleOverrideNotifier extends ValueNotifier<String?> {
  RoleOverrideNotifier() : super(null);
  String? get role => value;
  void setRole(String? r) => value = r;
  void clear() => value = null;
}

final debugRoleOverrideProvider = Provider<RoleOverrideNotifier>((ref) => RoleOverrideNotifier());

class RoleRouter extends ConsumerStatefulWidget {
  const RoleRouter({super.key});
  @override
  ConsumerState<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends ConsumerState<RoleRouter> {
  final _service = RoleService();
  AsyncValue<String?> _role = const AsyncValue.loading();
  Timer? _pollTimer;
  int _pollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolve({bool forceClaim = false}) async {
    setState(() => _role = const AsyncValue.loading());
    try {
      final override = ref.read(debugRoleOverrideProvider).role;
      if (override != null) {
        setState(() => _role = AsyncValue.data(override));
        return;
      }
      final resolved = await _service.resolveRole(forceClaimRefresh: forceClaim);
      // Enforce claim presence for admin: if Firestore says admin but claim not yet set, treat as loading.
      if (resolved == 'admin') {
        final claim = await _service.fetchClaimRole();
        if (claim != 'admin') {
          // Trigger claim sync manager attempt (non-blocking)
            ClaimSyncManager().ensureClaimPresent();
          // schedule a short re-poll with backoff (max 5 attempts)
          if (_pollAttempts < 5) {
            _pollAttempts++;
            _pollTimer?.cancel();
            _pollTimer = Timer(Duration(milliseconds: 300 * _pollAttempts), () => _resolve(forceClaim: true));
          }
          setState(() => _role = const AsyncValue.loading());
          return;
        }
      }
      setState(() => _role = AsyncValue.data(resolved));
    } catch (e, st) {
      setState(() => _role = AsyncValue.error(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _role.when(
      data: (role) {
        if (role == null) return const _RoleLoadingFallback();
        switch (role) {
          case 'admin':
            return RoleGate(allow: const ['admin'], builder: (_, __) => const AdminDashboardScreen());
          case 'engineer':
            return RoleGate(allow: const ['engineer','admin'], builder: (_, __) => const EngineerDashboardScreen());
          case 'nurse': // legacy
          case 'medic':
            return RoleGate(allow: const ['nurse','medic','admin'], builder: (_, __) => const NurseDashboardScreen());
          default:
            return const _RoleLoadingFallback();
        }
      },
      loading: () => const _RoleLoadingFallback(),
      error: (e, _) => Scaffold(body: FriendlyErrorView(error: e, title: 'Couldn’t determine your access', onRetry: () => _resolve(forceClaim: true))),
    );
  }
}

class _RoleLoadingFallback extends StatefulWidget {
  const _RoleLoadingFallback();
  @override
  State<_RoleLoadingFallback> createState() => _RoleLoadingFallbackState();
}

class _RoleLoadingFallbackState extends State<_RoleLoadingFallback> {
  static const total = 8; // seconds
  int remaining = total;
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        return;
      }
      setState(() => remaining--);
      if (remaining <= 0) {
        timer.cancel();
        // Instead of auto-fallback to a role dashboard (risk of privilege confusion),
        // stay on a deterministic safe screen instructing user to retry.
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            if (remaining > 0) Text('Loading role… $remaining s'),
            if (remaining <= 0) ...[
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'Unable to resolve your role. Please retry. If this persists, sign out and sign back in.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => ref.invalidate(userRoleProvider),
                child: const Text('Retry role fetch'),
              ),
            ),
            TextButton(
              onPressed: () async { try { await fa.FirebaseAuth.instance.signOut(); } catch (_) {} },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

// (Removed inline dashboards; nurse implementation moved to dashboard/nurse_dashboard.dart. Admin/Engineer placeholders reuse nurse screen for now.)
