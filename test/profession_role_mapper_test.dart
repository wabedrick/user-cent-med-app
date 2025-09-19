import 'package:flutter_test/flutter_test.dart';
import 'package:user_cent_med_app/auth/profession_role_mapper.dart';

void main() {
  group('mapProfessionToRole', () {
    test('engineer terms -> engineer', () {
      expect(mapProfessionToRole('Biomedical Engineer'), 'engineer');
      expect(mapProfessionToRole('engineer'), 'engineer');
    });
    test('clinical terms -> medic', () {
      expect(mapProfessionToRole('Doctor'), 'medic');
      expect(mapProfessionToRole('Nurse'), 'medic');
      expect(mapProfessionToRole('Clinical Officer'), 'medic');
      expect(mapProfessionToRole('Medic'), 'medic');
    });
    test('fallback -> engineer', () {
      expect(mapProfessionToRole('Technician'), 'engineer');
      expect(mapProfessionToRole(null), 'engineer');
    });
  });
}
