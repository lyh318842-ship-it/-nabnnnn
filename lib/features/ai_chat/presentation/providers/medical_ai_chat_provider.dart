import 'package:digl/features/ai_chat/data/services/medical_ai_error_handler.dart';
import 'package:digl/features/ai_chat/presentation/pages/medical_ai_chat_screen.dart';
import 'package:flutter/material.dart';
import '../../data/models/ai_chat_conversation.dart';
import '../../data/models/ai_chat_message.dart';
import '../../data/models/medical_intake.dart';
import '../../data/repositories/medical_ai_repository.dart';

class MedicalAiChatProvider extends ChangeNotifier {
  final MedicalAiRepository repository;
  MedicalAiChatProvider(this.repository);

  final List<AiChatConversation> conversations = [];
  final List<AiChatMessage> messages = [];
  bool isLoading = false;
  bool isLoadingConversations = false;
  String? error;
  String? activeConversationId;

  MedicalIntake get _defaultIntake => const MedicalIntake(
        problem: 'محادثة طبية عامة بدون نموذج سياق افتتاحي',
        symptomStart: 'غير محدد',
        age: 0,
        gender: 'غير محدد',
        duration: '',
        severity: 'غير محددة',
      );

  Future<void> loadConversations() async {
    isLoadingConversations = true;
    error = null;
    notifyListeners();
    try {
      conversations
        ..clear()
        ..addAll(await repository.loadConversations());
      if (conversations.isEmpty) {
        await createNewConversation();
      } else {
        await openConversation(conversations.first.id);
      }
    } catch (e) {
      error = MedicalAiErrorHandler.friendlyMessage(e);
      await createNewConversation(localOnly: true);
    } finally {
      isLoadingConversations = false;
      notifyListeners();
    }
  }

  Future<void> createNewConversation({bool localOnly = false}) async {
    final conversation = await repository.createConversation(localOnly: localOnly);
    conversations.removeWhere((item) => item.id == conversation.id);
    conversations.insert(0, conversation);
    activeConversationId = conversation.id;
    messages.clear();
    error = null;
    notifyListeners();
  }

  Future<void> openConversation(String id) async {
    activeConversationId = id;
    messages
      ..clear()
      ..addAll(await repository.loadMessages(id));
    error = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> clearMessages() async {
    final id = activeConversationId;
    if (id == null) return;
    messages.clear();
    error = null;
    await repository.clearMessages(id);
    notifyListeners();
  }

  Future<void> send(String content) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    if (activeConversationId == null) await createNewConversation();
    await _addUser(clean);
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final reply = await repository.sendMessage(_defaultIntake, messages, clean);
      await _addBot(reply);
    } catch (e) {
      error = MedicalAiErrorHandler.friendlyMessage(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendAttachment(String path, String type, {String? description}) async {
    final cleanDescription = description?.trim() ?? '';
    final label = type == 'image'
        ? 'تم رفع صورة للتحليل.${cleanDescription.isEmpty ? '' : '\nوصف المستخدم للصورة: $cleanDescription'}'
        : 'تم رفع ملف للمراجعة${cleanDescription.isEmpty ? '' : ': $cleanDescription'}';
    await _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: label, isUser: true, createdAt: DateTime.now(), attachmentPath: path, attachmentType: type));
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final reply = await repository.sendMessage(_defaultIntake, messages, label, attachmentPath: path, attachmentType: type);
      await _addBot(reply);
    } catch (e) {
      error = MedicalAiErrorHandler.friendlyMessage(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MedicalAiChatScreen(), settings: const RouteSettings(name: '/medical_ai_chat')));

  static Widget floatingButton(BuildContext context) => FloatingActionButton.extended(
        heroTag: 'global_ai_chat_fab',
        elevation: 0,
        highlightElevation: 0,
        onPressed: () => open(context),
        icon: const Icon(Icons.smart_toy_rounded),
        label: const Text('مساعدك الشخصي'),
      );

  Future<void> deleteMessage(AiChatMessage message) async {
    final id = activeConversationId;
    messages.removeWhere((item) => item.id == message.id);
    notifyListeners();
    if (id != null) await repository.deleteMessage(id, message);
  }

  Future<void> resend(AiChatMessage message) async {
    if (!message.isUser || message.content.trim().isEmpty || isLoading) return;
    await send(message.content);
  }

  Future<void> _addUser(String content) => _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: content, isUser: true, createdAt: DateTime.now()));
  Future<void> _addBot(String content) => _add(AiChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), content: content, isUser: false, createdAt: DateTime.now()));

  Future<void> _add(AiChatMessage msg) async {
    final id = activeConversationId;
    if (id == null) return;
    messages.add(msg);
    notifyListeners();
    await repository.saveMessage(id, msg);
    conversations
      ..clear()
      ..addAll(await repository.loadConversations());
    notifyListeners();
  }
}
