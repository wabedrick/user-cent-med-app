import 'package:flutter_test/flutter_test.dart';
import 'package:user_cent_med_app/auth/role_resolver.dart';

void main() {
  group('RoleResolver', () {
    test('prefers claim when present', () async {
      final resolver = RoleResolver(
        claimFetcher: ({bool force = false}) async => 'admin',
        firestoreFetcher: () async => 'engineer',
      );
      expect(await resolver.resolve(), 'admin');
    });

    test('falls back to Firestore when claim null', () async {
      final resolver = RoleResolver(
        claimFetcher: ({bool force = false}) async => null,
        firestoreFetcher: () async => 'medic',
      );
      expect(await resolver.resolve(), 'medic');
    });

    test('returns null when neither source has role', () async {
      final resolver = RoleResolver(
        claimFetcher: ({bool force = false}) async => null,
        firestoreFetcher: () async => null,
      );
      expect(await resolver.resolve(), isNull);
    });
  });
}
