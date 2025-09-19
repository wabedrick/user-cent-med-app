import 'package:cloud_functions/cloud_functions.dart';
import 'assistant_models.dart';

class AssistantRepository {
  final FirebaseFunctions _functions;
  AssistantRepository({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<String> chat({required List<AssistantMessage> messages, String? systemPrompt, String model = 'gpt-4o-mini', double temperature = 0.2}) async {
    final callable = _functions.httpsCallable('aiAssistantChat');
    final res = await callable.call({
      'messages': messages.map((m) => m.toJson()).toList(),
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      'model': model,
      'temperature': temperature,
    });
    final data = res.data as Map<dynamic, dynamic>;
    final status = data['status'] as String?;
    if (status == 'ok' || status == 'no-key') {
      return (data['reply'] as String?) ?? '';
    }
    throw Exception('Assistant error: $status');
  }
}
