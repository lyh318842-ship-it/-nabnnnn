import 'package:cloud_firestore/cloud_firestore.dart';

class AiChatConversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiChatConversation.fromMap(String id, Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    }

    return AiChatConversation(
      id: id,
      title: (map['title'] ?? 'محادثة جديدة').toString(),
      createdAt: readDate(map['createdAt']),
      updatedAt: readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool firestore = true}) => {
        'title': title,
        'createdAt': firestore ? Timestamp.fromDate(createdAt) : createdAt.toIso8601String(),
        'updatedAt': firestore ? Timestamp.fromDate(updatedAt) : updatedAt.toIso8601String(),
      };
}
