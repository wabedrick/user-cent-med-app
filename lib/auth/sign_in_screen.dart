import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../main.dart' show ensureUserDoc, TokenRefresher, RoleRouter; // reuse existing helper and router
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  bool showPassword = false;
  bool rememberEmail = true;
  String? emailError;
  String? passwordError;
  String? error;
  String? status;

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  Future<void> _restoreEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('last_email');
      if (saved != null) {
        setState(() => emailCtrl.text = saved);
      }
      rememberEmail = prefs.getBool('remember_email') ?? true;
    } catch (_) {}
  }

  Future<void> _persistEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rememberEmail && emailCtrl.text.trim().isNotEmpty) {
        await prefs.setString('last_email', emailCtrl.text.trim());
      } else {
        await prefs.remove('last_email');
      }
      await prefs.setBool('remember_email', rememberEmail);
    } catch (_) {}
  }

  void _validateFields({bool live = false}) {
    final email = emailCtrl.text.trim();
    final pwd = passCtrl.text;
    String? eErr;
    String? pErr;
    if (email.isEmpty) {
      eErr = 'Required';
    } else if (!email.contains('@')) {
      eErr = 'Invalid email';
    }
    if (pwd.isEmpty) {
      pErr = 'Required';
    } else if (pwd.length < 6) {
      pErr = 'Min 6 chars';
    }
    if (live) {
      setState(() { emailError = eErr; passwordError = pErr; });
    } else {
      emailError = eErr; passwordError = pErr;
    }
  }

  Future<void> _signIn() async {
    _validateFields(live: true);
    if (emailError != null || passwordError != null) return;
    setState(() { loading = true; error = null; status = 'Signing in…'; });
    try {
      await fa.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user != null) {
        await ensureUserDoc(user);
        // Proactively refresh token so custom claims apply immediately.
        try { await user.getIdToken(true); } catch (_) {}
        if (mounted) {
          // Explicitly route into the authenticated area to avoid any UI ambiguity.
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
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() { loading = false; status = null; });
    }
  }

  Future<void> _resetPassword() async {
    setState(() { loading = true; error = null; });
    try {
      await fa.FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent')));
      }
    } on fa.FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? 'Auth error (${e.code})');
    } on PlatformException catch (e) {
      setState(() => error = e.message ?? 'Platform error: ${e.code}');
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _goToSignUp() {
    if (loading) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In'),
        actions: [
          TextButton(
            onPressed: loading ? null : _goToSignUp,
            child: const Text('New user?', style: TextStyle(color: Colors.white)),
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
                      ElevatedButton(onPressed: loading ? null : _signIn, child: Text(loading ? '...' : 'Sign In')),
                      TextButton(onPressed: loading ? null : _resetPassword, child: const Text('Forgot password?')),
                    ],
                  ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          const Text("Don't have an account?"),
                          TextButton(
                            onPressed: loading ? null : _goToSignUp,
                            child: const Text('Create one'),
                          ),
                        ],
                      ),
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
