import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation/app_navigator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/role_provider.dart' show userRoleProvider; // legacy unified role provider (will be phased out)
import 'auth/role_service.dart';
import 'auth/claim_sync_manager.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
// media_kit global initialization (required for some platforms to ensure backends are ready)
import 'package:media_kit/media_kit.dart';
import 'theme.dart';
import 'dashboard/user_dashboard.dart';
import 'dashboard/engineer_dashboard.dart';
import 'dashboard/admin_dashboard.dart';
// sign_in_screen imported indirectly via UnifiedAuthGate
import 'auth/unified_auth_gate.dart';
import 'equipment/equipment_list_page.dart';
import 'features/maintenance/maintenance_list_page.dart';
import 'features/knowledge/knowledge_center_page.dart';
import 'features/assistant/assistant_chat_screen.dart';
import 'widgets/error_utils.dart';
import 'features/video/mini_video_overlay.dart';
// Add localization + messaging service imports
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/messaging_service.dart';
// (removed duplicate imports for app_navigator & riverpod)

// Default role for newly registered users should be 'user'.
// Avoid deriving from environment to prevent accidental elevation.
const String kSafeSelfCreateRole = 'user';

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
  // Ensure media_kit is initialized (idempotent). This can help avoid backend load races
  // when we attempt a software decode fallback very early in app lifetime.
  try { MediaKit.ensureInitialized(); } catch (e) { debugPrint('[media_kit] init warning: $e'); }
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
      navigatorKey: appNavigatorKey,
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
      builder: (context, child) {
        // Provide a global Overlay so mini-player and tooltips/menus can use it
        return Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (ctx) => Stack(
                children: [
                  if (child != null) child,
                  const MiniVideoOverlay(),
                ],
              ),
            ),
          ],
        );
      },
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
        // Derive base from last word of displayName or email local part.
        String base = '';
        final dn = user.displayName?.trim();
        if (dn != null && dn.isNotEmpty) {
          final parts = dn.split(RegExp(r'\s+'));
            base = parts.isNotEmpty ? parts.last : dn;
        }
        if (base.isEmpty) {
          final email = user.email ?? '';
          base = email.contains('@') ? email.split('@').first : email;
        }
        base = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '').toLowerCase();
        if (base.length < 3) base = 'user';
        // Check for collisions; append short number if needed.
        String candidate = base;
        int suffix = 1;
        while (true) {
          final q = await users.where('username', isEqualTo: candidate).limit(1).get();
          if (q.docs.isEmpty) break;
          suffix++;
          candidate = '$base$suffix';
          if (suffix > 9999) { // safety cap
            candidate = base + DateTime.now().millisecondsSinceEpoch.toString().substring(9);
            break;
          }
        }
        await doc
            .set({
              'email': user.email,
              'displayName': user.displayName,
              'emailLower': (user.email ?? '').toLowerCase(),
              'role': kSafeSelfCreateRole,
              'username': candidate,
              'createdAt': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 6), onTimeout: () => throw TimeoutException('create user doc timeout'));
      } else {
        // Backfill username if missing (legacy accounts)
        final data = snap.data();
        if (data != null && (data['username'] == null || (data['username'] as String).trim().isEmpty)) {
          String base = '';
          final ln = (data['lastName'] as String?)?.trim();
          if (ln != null && ln.isNotEmpty) base = ln;
          if (base.isEmpty) {
            final dn = (data['displayName'] as String?)?.trim();
            if (dn != null && dn.isNotEmpty) {
              final parts = dn.split(RegExp(r'\s+'));
              base = parts.isNotEmpty ? parts.last : dn;
            }
          }
          if (base.isEmpty) {
            final email = user.email ?? '';
            base = email.contains('@') ? email.split('@').first : email;
          }
          base = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '').toLowerCase();
          if (base.length < 3) base = 'user';
          String candidate = base;
          int suffix = 1;
          while (true) {
            final q = await users.where('username', isEqualTo: candidate).limit(1).get();
            if (q.docs.isEmpty) break;
            suffix++;
            candidate = '$base$suffix';
            if (suffix > 9999) { candidate = base + DateTime.now().millisecondsSinceEpoch.toString().substring(9); break; }
          }
          await doc.update({'username': candidate});
        }
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

// Holds a consultId that should be focused after navigation (e.g., from notification tap)
// Implemented as a NotifierProvider instead of StateProvider to avoid analyzer symbol issues.
class PendingConsultNavigation extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
  void clear() => state = null;
}
final pendingConsultNavigationProvider = NotifierProvider<PendingConsultNavigation, String?>(PendingConsultNavigation.new);

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
    // If there is a pending consult navigation request and user is engineer/admin, ensure we route to engineer screen.
  final pendingConsult = ref.watch(pendingConsultNavigationProvider);
    return _role.when(
      data: (role) {
        if (role == null) return const _RoleLoadingFallback();
        switch (role) {
          case 'admin':
            return const AdminDashboardScreen();
          case 'engineer':
            return EngineerDashboardScreen(pendingConsultId: pendingConsult);
          case 'nurse': // legacy
          case 'medic':
            return const UserDashboardScreen();
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
