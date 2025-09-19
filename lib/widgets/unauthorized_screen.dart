import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;

class UnauthorizedScreen extends StatelessWidget {
  final String? requiredRole;
  final String? actualRole;
  const UnauthorizedScreen({super.key, this.requiredRole, this.actualRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access Restricted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                'You do not have permission to view this area.',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (requiredRole != null) ...[
                const SizedBox(height: 8),
                Text('Required role: $requiredRole', style: const TextStyle(color: Colors.black54)),
              ],
              if (actualRole != null) ...[
                const SizedBox(height: 4),
                Text('Your role: $actualRole', style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await fa.FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}