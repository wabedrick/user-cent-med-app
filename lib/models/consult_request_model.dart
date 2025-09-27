import 'package:cloud_firestore/cloud_firestore.dart';

class ConsultRequest {
  final String id;
  final String userId;          // requester user
  final String question;        // original question
  final String status;          // open | claimed | answered | closed
  final String? claimedBy;      // engineer user id who claimed
  final String? answer;         // short answer / resolution summary
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? answeredAt;

  ConsultRequest({
    required this.id,
    required this.userId,
    required this.question,
    required this.status,
    required this.claimedBy,
    required this.answer,
    required this.createdAt,
    required this.updatedAt,
    required this.answeredAt,
  });

  factory ConsultRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ConsultRequest(
      id: doc.id,
      userId: d['userId'] as String,
      question: d['question'] as String,
      status: d['status'] as String? ?? 'open',
      claimedBy: d['claimedBy'] as String?,
      answer: d['answer'] as String?,
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      updatedAt: (d['updatedAt'] as Timestamp).toDate(),
      answeredAt: d['answeredAt'] != null ? (d['answeredAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'question': question,
        'status': status,
        'claimedBy': claimedBy,
        'answer': answer,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        if (answeredAt != null) 'answeredAt': Timestamp.fromDate(answeredAt!),
      };

  ConsultRequest copyWith({
    String? status,
    String? claimedBy,
    String? answer,
    DateTime? updatedAt,
    DateTime? answeredAt,
  }) => ConsultRequest(
        id: id,
        userId: userId,
        question: question,
        status: status ?? this.status,
        claimedBy: claimedBy ?? this.claimedBy,
        answer: answer ?? this.answer,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        answeredAt: answeredAt ?? this.answeredAt,
      );
}
