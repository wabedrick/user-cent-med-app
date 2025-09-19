import 'package:flutter_test/flutter_test.dart';
import 'package:user_cent_med_app/features/assistant/assistant_models.dart';

void main() {
  test('AssistantMessage toJson shapes correctly', () {
    const m = AssistantMessage(role: 'user', content: 'Hello');
    final j = m.toJson();
    expect(j['role'], 'user');
    expect(j['content'], 'Hello');
  });
}
