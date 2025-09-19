class AssistantMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const AssistantMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => { 'role': role, 'content': content };
}
