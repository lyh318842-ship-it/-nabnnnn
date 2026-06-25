import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:digl/features/medical_profile/models/doctor_recommendation_model.dart';
import 'package:digl/features/medical_profile/services/advanced_diagnosis_service.dart';
import 'package:digl/features/medical_profile/services/doctor_matching_service.dart';
import '../models/ai_chat_conversation.dart';
import '../models/ai_chat_message.dart';
import '../models/medical_intake.dart';
import '../services/medical_ai_api_service.dart';

class MedicalAiRepository {
  final MedicalAiApiService apiService;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  MedicalAiRepository({required this.apiService, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? get _conversationsRef {
    final uid = auth.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) return null;
    return firestore.collection('users').doc(uid).collection('medical_ai_conversations');
  }

  String get _localConversationsKey => 'medical_ai_conversations_${auth.currentUser?.uid ?? 'guest'}';
  String _localMessagesKey(String conversationId) => 'medical_ai_messages_${auth.currentUser?.uid ?? 'guest'}_$conversationId';

  Future<AiChatConversation> createConversation({bool localOnly = false}) async {
    final now = DateTime.now();
    final conversation = AiChatConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'محادثة جديدة',
      createdAt: now,
      updatedAt: now,
    );
    await _saveConversationLocal(conversation);
    final ref = _conversationsRef;
    if (!localOnly && ref != null) {
      await ref.doc(conversation.id).set(conversation.toMap());
    }
    return conversation;
  }

  Future<List<AiChatConversation>> loadConversations() async {
    final ref = _conversationsRef;
    if (ref != null) {
      try {
        final snapshot = await ref.orderBy('updatedAt', descending: true).limit(50).get();
        final remote = snapshot.docs.map((doc) => AiChatConversation.fromMap(doc.id, doc.data())).toList();
        if (remote.isNotEmpty) return remote;
      } catch (e) {
        // Falls back to the local cache when Firestore is temporarily unavailable.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_localConversationsKey) ?? <String>[]).map((raw) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiChatConversation.fromMap(map['id'].toString(), map);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<AiChatMessage>> loadMessages(String conversationId) async {
    final ref = _conversationsRef;
    if (ref != null && conversationId.trim().isNotEmpty) {
      try {
        final snapshot = await ref.doc(conversationId).collection('messages').orderBy('createdAt').limitToLast(200).get();
        final remote = snapshot.docs.map((doc) => AiChatMessage.fromMap(doc.id, doc.data())).toList();
        if (remote.isNotEmpty) return remote;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_localMessagesKey(conversationId)) ?? <String>[]).map((raw) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiChatMessage.fromMap(map['id'].toString(), map);
    }).toList();
  }

  Future<void> saveMessage(String conversationId, AiChatMessage message) async {
    await _saveMessageLocal(conversationId, message);
    final title = message.isUser ? _titleFromMessage(message.content) : null;
    final now = DateTime.now();
    final ref = _conversationsRef;
    if (ref != null && conversationId.trim().isNotEmpty) {
      final conversationRef = ref.doc(conversationId);
      await conversationRef.set({
        if (title != null) 'title': title,
        'updatedAt': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await conversationRef.collection('messages').doc(message.id).set(message.toMap());
    }
    await _touchLocalConversation(conversationId, title, now);
  }

  Future<void> clearMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localMessagesKey(conversationId));
    final ref = _conversationsRef;
    if (ref == null || conversationId.trim().isEmpty) return;
    final snapshot = await ref.doc(conversationId).collection('messages').limit(200).get();
    final batch = firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> deleteMessage(String conversationId, AiChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_localMessagesKey(conversationId)) ?? <String>[];
    await prefs.setStringList(_localMessagesKey(conversationId), current.where((raw) {
      try { return (jsonDecode(raw) as Map<String, dynamic>)['id']?.toString() != message.id; } catch (_) { return true; }
    }).toList());
    final ref = _conversationsRef;
    if (ref != null && conversationId.trim().isNotEmpty) {
      await ref.doc(conversationId).collection('messages').doc(message.id).delete();
    }
  }

  Future<String> sendMessage(MedicalIntake intake, List<AiChatMessage> history, String message, {String? attachmentPath, String? attachmentType}) => apiService.sendMedicalMessage(intake: intake, history: history, message: message, attachmentPath: attachmentPath, attachmentType: attachmentType);

  Future<List<DoctorRecommendation>> recommendDoctors(MedicalIntake intake) async {
    final specialty = _specialtyForProblem(intake.problem);
    return DoctorMatchingService.findMatchingDoctors(recommendedSpecialties: [SpecialtyRecommendation(name: specialty, description: 'مطابقة أولية من الذكاء الاصطناعي', matchPercentage: 80)], symptoms: intake.symptoms, returnCount: 1);
  }

  Future<void> _saveConversationLocal(AiChatConversation conversation) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_localConversationsKey) ?? <String>[];
    list.removeWhere((raw) { try { return (jsonDecode(raw) as Map<String, dynamic>)['id'] == conversation.id; } catch (_) { return false; } });
    list.insert(0, jsonEncode({'id': conversation.id, ...conversation.toMap(firestore: false)}));
    await prefs.setStringList(_localConversationsKey, list.take(50).toList());
  }

  Future<void> _saveMessageLocal(String conversationId, AiChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_localMessagesKey(conversationId)) ?? <String>[];
    current.add(jsonEncode({'id': message.id, ...message.toMap(firestore: false)}));
    await prefs.setStringList(_localMessagesKey(conversationId), current.length > 200 ? current.sublist(current.length - 200) : current);
  }

  Future<void> _touchLocalConversation(String conversationId, String? title, DateTime updatedAt) async {
    final existing = (await loadConversations()).firstWhere(
      (item) => item.id == conversationId,
      orElse: () => AiChatConversation(id: conversationId, title: title ?? 'محادثة جديدة', createdAt: updatedAt, updatedAt: updatedAt),
    );
    await _saveConversationLocal(AiChatConversation(id: conversationId, title: title ?? existing.title, createdAt: existing.createdAt, updatedAt: updatedAt));
  }

  String _titleFromMessage(String message) {
    final clean = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'محادثة جديدة';
    return clean.length <= 42 ? clean : '${clean.substring(0, 42)}...';
  }

  String _specialtyForProblem(String problem) {
    final text = problem.toLowerCase();
    if (text.contains('قلب') || text.contains('صدر')) return 'قلب';
    if (text.contains('جلد') || text.contains('حساسية')) return 'جلدية';
    if (text.contains('طفل')) return 'أطفال';
    if (text.contains('أسنان') || text.contains('سن')) return 'أسنان';
    if (text.contains('معدة') || text.contains('بطن')) return 'باطنية';
    return 'طب عام';
  }
}
