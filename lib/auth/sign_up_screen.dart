import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:google_fonts/google_fonts.dart'; // no longer used
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profession_role_mapper.dart';
// (Optional) If Google sign-in is desired, add google_sign_in dependency in pubspec.
// import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';

import '../main.dart' show ensureUserDoc, TokenRefresher, RoleRouter; // reuse existing helper and router
import 'sign_in_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  String? selectedCountry;
  String? selectedProfession; // user-chosen profession label
  bool loading = false;
  bool showPassword = false;
  bool rememberEmail = true;
  String? emailError;
  String? passwordError;
  String? firstNameError;
  String? lastNameError;
  String? professionError;
  String? countryError;
  String? error;
  String? status;

  @override
  void initState() { super.initState(); _restoreEmail(); }

  Future<void> _restoreEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('last_email');
      if (saved != null) setState(() => emailCtrl.text = saved);
      rememberEmail = prefs.getBool('remember_email') ?? true;
    } catch (_) {}
  }

  Future<void> _persistEmail() async { try { final prefs = await SharedPreferences.getInstance(); if (rememberEmail && emailCtrl.text.trim().isNotEmpty) { await prefs.setString('last_email', emailCtrl.text.trim()); } else { await prefs.remove('last_email'); } await prefs.setBool('remember_email', rememberEmail); } catch (_) {} }

  void _validateFields({bool live = false}) {
    final email = emailCtrl.text.trim();
    final pwd = passCtrl.text;
    final first = firstNameCtrl.text.trim();
    final last = lastNameCtrl.text.trim();
    String? eErr; String? pErr;
    String? fErr; String? lErr; String? profErr; String? cErr;
    if (email.isEmpty) { eErr = 'Required'; } else if (!email.contains('@')) { eErr = 'Invalid email'; }
    if (pwd.isEmpty) { pErr = 'Required'; } else if (pwd.length < 6) { pErr = 'Min 6 chars'; }
    if (first.isEmpty) fErr = 'Required';
    if (last.isEmpty) lErr = 'Required';
    if (selectedProfession == null) profErr = 'Select one';
    if (selectedCountry == null) cErr = 'Select country';
    if (live) { setState(() { emailError = eErr; passwordError = pErr; }); } else { emailError = eErr; passwordError = pErr; }
    if (live) {
      setState(() {
        firstNameError = fErr; lastNameError = lErr; professionError = profErr; countryError = cErr;
      });
    } else {
      firstNameError = fErr; lastNameError = lErr; professionError = profErr; countryError = cErr;
    }
  }

  Future<void> _createAccount() async {
    _validateFields(live: true);
    if (emailError != null || passwordError != null) return;
    setState(() { loading = true; error = null; status = 'Creating account'; });
    try {
      final dynamic connRaw = await Connectivity().checkConnectivity();
      // connectivity_plus v7 may return a List<ConnectivityResult>; earlier versions return a single ConnectivityResult.
      bool isOffline;
      if (connRaw is List<ConnectivityResult>) {
        isOffline = connRaw.isEmpty || connRaw.every((r) => r == ConnectivityResult.none);
      } else if (connRaw is ConnectivityResult) {
        isOffline = connRaw == ConnectivityResult.none;
      } else {
        // Fallback: assume online if we cannot determine
        isOffline = false;
      }
      if (isOffline) {
        throw Exception('No internet connection');
      }
      final email = emailCtrl.text.trim();
      final pwd = passCtrl.text;
      final cred = await fa.FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
      if (cred.user != null) {
        status = 'Provisioning profile';
        await ensureUserDoc(cred.user!);
        // Merge extended profile fields
        try {
          final role = mapProfessionToRole(selectedProfession);
          // Ensure user still present (no await needed)
          final _ = fa.FirebaseAuth.instance.currentUser;
          await _upsertProfile(cred.user!.uid, role: role);
        } catch (_) {}
        // Refresh token after provisioning to pick up any server-side defaults
        // or soon-to-be assigned claims by an admin.
        try { await cred.user!.getIdToken(true); } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const TokenRefresher(child: RoleRouter())),
          );
        }
      }
      if (rememberEmail) unawaited(_persistEmail());
    } on fa.FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? 'Auth error (${e.code})');
    } on PlatformException catch (e) {
      setState(() => error = e.message ?? 'Platform error: ${e.code}');
    } catch (e) {
      final msg = e.toString();
      setState(() => error = msg.contains('unavailable') ? 'Service temporarily unavailable. Try again soon.' : msg);
    } finally {
      if (mounted) setState(() { loading = false; status = null; });
    }
  }

  Future<void> _upsertProfile(String uid, {required String role}) async {
    try {
      final db = FirebaseFirestore.instance;
      final ref = db.collection('users').doc(uid);
      await ref.set({
        'firstName': firstNameCtrl.text.trim(),
        'lastName': lastNameCtrl.text.trim(),
        'country': selectedCountry,
        'profession': selectedProfession,
        'role': role, // may differ from initial default
        'displayName': '${firstNameCtrl.text.trim()} ${lastNameCtrl.text.trim()}',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Non-fatal; profile enrichment can be retried in settings later.
    }
  }

  // Placeholder for future Google Sign-In integration.
  Future<void> _signInWithGoogle() async {
    if (loading) return;
    setState(() { loading = true; error = null; status = 'Connecting to Google'; });
    try {
      // TODO: Implement google_sign_in + Firebase auth linking.
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() { error = 'Google sign-in not yet implemented'; });
    } catch (e) {
      setState(() { error = e.toString(); });
    } finally {
      if (mounted) setState(() { loading = false; status = null; });
    }
  }

  void _goToSignIn() {
    if (loading) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        actions: [
          TextButton(
            onPressed: loading ? null : _goToSignIn,
            child: const Text('Have account?', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: emailCtrl,
                    onChanged: (_) => _validateFields(live: true),
                    decoration: InputDecoration(labelText: 'Email', errorText: emailError, prefixIcon: const Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: firstNameCtrl,
                        onChanged: (_) => _validateFields(live: true),
                        decoration: InputDecoration(labelText: 'First Name', errorText: firstNameError, prefixIcon: const Icon(Icons.badge_outlined)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lastNameCtrl,
                        onChanged: (_) => _validateFields(live: true),
                        decoration: InputDecoration(labelText: 'Last Name', errorText: lastNameError, prefixIcon: const Icon(Icons.badge)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _CountryDropdown(
                    value: selectedCountry,
                    onChanged: (v) => setState(() { selectedCountry = v; _validateFields(live: true); }),
                    errorText: countryError,
                  ),
                  const SizedBox(height: 8),
                  _ProfessionDropdown(
                    value: selectedProfession,
                    onChanged: (v) => setState(() { selectedProfession = v; _validateFields(live: true); }),
                    errorText: professionError,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passCtrl,
                    onChanged: (_) => _validateFields(live: true),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: passwordError,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => showPassword = !showPassword),
                      ),
                    ),
                    obscureText: !showPassword,
                  ),
                  const SizedBox(height: 12),
                  if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                  if (loading && status != null) ...[
                    const SizedBox(height: 8),
                    Row(children: const [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Expanded(child: Text('Please wait...')),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(children: [
                        Checkbox(
                          value: rememberEmail,
                          onChanged: loading ? null : (v) => setState(() { rememberEmail = v ?? true; _persistEmail(); }),
                        ),
                        const Text('Remember email'),
                      ]),
                      const Spacer(),
                      ElevatedButton(onPressed: loading ? null : _createAccount, child: Text(loading ? '...' : 'Create Account')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(children: const [Expanded(child: Divider()), SizedBox(width: 8), Text('OR'), SizedBox(width: 8), Expanded(child: Divider())]),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: loading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 1),
                  ),
                  SizedBox(height: bottomInset > 0 ? bottomInset : 0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lightweight country dropdown (static list subset for brevity).
class _CountryDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;
  const _CountryDropdown({required this.value, required this.onChanged, this.errorText});
  static const _countries = <String>[
    'United States','Canada','United Kingdom','Germany','France','Kenya','Nigeria','South Africa','India','Brazil','Japan','Australia'
  ];
  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: 'Country', errorText: errorText, prefixIcon: const Icon(Icons.public)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
            value: value,
            hint: const Text('Select country'),
            items: _countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ProfessionDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;
  const _ProfessionDropdown({required this.value, required this.onChanged, this.errorText});
  static const _professions = <String>[
    'Biomedical Engineer',
    'Doctor',
    'Nurse',
    'Clinical Officer',
    'Technician',
  ];
  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: 'Profession', errorText: errorText, prefixIcon: const Icon(Icons.work_outline)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: const Text('Select profession'),
          items: _professions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
