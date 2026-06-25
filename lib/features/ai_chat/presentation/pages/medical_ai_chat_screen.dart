import 'dart:io';
import 'dart:math' as math;

import 'package:digl/services/user_role_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/ai_chat_message.dart';
import '../../data/repositories/medical_ai_repository.dart';
import '../../data/services/medical_ai_api_service.dart';
import '../providers/medical_ai_chat_provider.dart';

class MedicalAiChatScreen extends StatefulWidget {
  const MedicalAiChatScreen({super.key});

  @override
  State<MedicalAiChatScreen> createState() => _MedicalAiChatScreenState();
}

class _MedicalAiChatScreenState extends State<MedicalAiChatScreen> {
  final _message = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocus = FocusNode();

  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();

  }

  @override
  void dispose() {
    _message.dispose();
    _scrollController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  Future<void> _startNewChat(BuildContext providerContext) async {
    await providerContext.read<MedicalAiChatProvider>().createNewConversation();
    if (!mounted) return;
    _message.clear();
    setState(() => _selectedImagePath = null);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendMessage(MedicalAiChatProvider provider) async {
    final text = _message.text.trim();
    if (provider.isLoading) return;
    if (text.isEmpty && _selectedImagePath == null) return;
    final selectedImage = _selectedImagePath;
    _message.clear();
    setState(() => _selectedImagePath = null);
    _scrollToBottom();
    if (selectedImage != null) {
      await provider.sendAttachment(selectedImage, 'image', description: text.isEmpty ? 'يرجى تحليل الصورة المرفقة.' : text);
    } else {
      await provider.send(text);
    }
    _scrollToBottom();
    _messageFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MedicalAiChatProvider(
        MedicalAiRepository(apiService: MedicalAiApiService()),
      )..loadConversations(),
      child: FutureBuilder<bool>(
        future: UserRoleService.isPatient(),
        builder: (context, roleSnapshot) {
          if (roleSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (roleSnapshot.data != true) {
            return Scaffold(
              appBar: AppBar(title: const Text('مساعد نبض AI')),
              body: const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('المساعد الذكي متاح لحسابات المرضى فقط.', textAlign: TextAlign.center),
                  ),
                ),
              ),
            );
          }
          return Consumer<MedicalAiChatProvider>(
            builder: (context, provider, _) => Scaffold(
              resizeToAvoidBottomInset: true,
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('مساعد نبض AI'),
                actions: [
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'المحادثات السابقة',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.history_rounded),
                    ),
                  ),
                  IconButton(
                    tooltip: 'محادثة جديدة',
                    onPressed: provider.isLoading ? null : () => _startNewChat(context),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              drawer: _ConversationsDrawer(provider: provider),
              body: SafeArea(child: _buildChat(context, provider)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChat(BuildContext context, MedicalAiChatProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    _scrollToBottom();
    final itemCount = provider.messages.length + (provider.isLoading ? 1 : 0);
    return Column(
      children: [
        if (provider.error != null)
          MaterialBanner(
            content: Text(provider.error!),
            actions: [TextButton(onPressed: provider.clearError, child: const Text('حسناً'))],
          ),
        Expanded(
          child: provider.messages.isEmpty && !provider.isLoading
              ? _EmptyChat(colorScheme: colorScheme)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  itemCount: itemCount,
                  itemBuilder: (context, i) {
                    if (i == provider.messages.length) return const _TypingIndicator();
                    return _MessageBubble(
                      message: provider.messages[i],
                      onDelete: () => _confirmDeleteMessage(context, provider, provider.messages[i]),
                      onResend: provider.messages[i].isUser ? () => provider.resend(provider.messages[i]) : null,
                    );
                  },
                ),
        ),
        _Composer(
          controller: _message,
          focusNode: _messageFocus,
          isLoading: provider.isLoading,
          selectedImagePath: _selectedImagePath,
          onRemoveImage: () => setState(() => _selectedImagePath = null),
          onSend: () => _sendMessage(provider),
          onImage: () async {
            if (provider.isLoading) return;
            final x = await ImagePicker().pickImage(source: ImageSource.gallery);
            if (x != null) {
              setState(() => _selectedImagePath = x.path);
              _messageFocus.requestFocus();
            }
          },
          onFile: () async {
            if (provider.isLoading) return;
            final f = await FilePicker.platform.pickFiles();
            final path = f?.files.single.path;
            if (path != null) {
              final lowerPath = path.toLowerCase();
              final isImage = lowerPath.endsWith('.jpg') ||
                  lowerPath.endsWith('.jpeg') ||
                  lowerPath.endsWith('.png') ||
                  lowerPath.endsWith('.webp') ||
                  lowerPath.endsWith('.heic') ||
                  lowerPath.endsWith('.heif');
              if (isImage) {
                setState(() => _selectedImagePath = path);
                _messageFocus.requestFocus();
              } else {
                await provider.sendAttachment(path, 'file', description: _message.text);
              }
              _scrollToBottom();
            }
          },
        ),
      ],
    );
  }

  Future<void> _confirmDeleteMessage(BuildContext context, MedicalAiChatProvider provider, AiChatMessage message) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.delete_outline_rounded, size: 42, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('حذف الرسالة؟', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('سيتم حذف هذه الرسالة من واجهة المحادثة وسجل المحادثة المحفوظ.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.delete_rounded), label: const Text('حذف الرسالة')),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await provider.deleteMessage(message);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الرسالة')));
    }
  }
}



class _ConversationsDrawer extends StatelessWidget {
  const _ConversationsDrawer({required this.provider});

  final MedicalAiChatProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('محادثة جديدة'),
              onTap: () async {
                Navigator.pop(context);
                await provider.createNewConversation();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: provider.isLoadingConversations
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: provider.conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = provider.conversations[index];
                        final selected = conversation.id == provider.activeConversationId;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: colorScheme.primaryContainer.withOpacity(.45),
                          leading: Icon(selected ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded),
                          title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${conversation.updatedAt.year}/${conversation.updatedAt.month}/${conversation.updatedAt.day}',
                            textDirection: TextDirection.ltr,
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            await provider.openConversation(conversation.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onDelete, this.onResend});

  final AiChatMessage message;
  final VoidCallback onDelete;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final background = isUser ? colorScheme.primary : colorScheme.surface;
    final foreground = isUser ? colorScheme.onPrimary : colorScheme.onSurface;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 12), child: child),
      ),
      child: GestureDetector(
        onLongPress: onDelete,
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(22),
              topEnd: const Radius.circular(22),
              bottomStart: Radius.circular(isUser ? 22 : 6),
              bottomEnd: Radius.circular(isUser ? 6 : 22),
            ),
            boxShadow: [
              BoxShadow(color: colorScheme.shadow.withOpacity( .08), blurRadius: 14, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.attachmentType == 'image' && message.attachmentPath != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(message.attachmentPath!), height: 160, fit: BoxFit.cover)),
                const SizedBox(height: 10),
              ],
              SelectableText(message.content, style: TextStyle(color: foreground, height: 1.45, fontSize: 15.5)),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 2,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'نسخ الرسالة',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: message.content));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرسالة')));
                      }
                    },
                    icon: Icon(Icons.copy_rounded, size: 16, color: foreground.withOpacity(.76)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'مشاركة الرسالة',
                    onPressed: () => Share.share(message.content),
                    icon: Icon(Icons.ios_share_rounded, size: 16, color: foreground.withOpacity(.76)),
                  ),
                  if (onResend != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'إعادة إرسال السؤال',
                      onPressed: onResend,
                      icon: Icon(Icons.refresh_rounded, size: 17, color: foreground.withOpacity(.76)),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'حذف الرسالة',
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded, size: 16, color: foreground.withOpacity(.76)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(22)),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              final phase = (_controller.value + index * .18) % 1;
              final scale = .65 + (math.sin(phase * math.pi) * .35);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.scale(
                  scale: scale,
                  child: CircleAvatar(radius: 4, backgroundColor: colorScheme.primary.withOpacity( .85)),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.primaryContainer),
              child: Icon(Icons.health_and_safety_rounded, size: 54, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text('اسأل مساعد نبض الطبي', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('اكتب سؤالك الصحي وسأجيبك بإرشادات آمنة ومنظمة، مع التنبيه عند الحاجة لمراجعة الطبيب أو الطوارئ.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.selectedImagePath,
    required this.onRemoveImage,
    required this.onSend,
    required this.onImage,
    required this.onFile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final String? selectedImagePath;
  final VoidCallback onRemoveImage;
  final VoidCallback onSend;
  final VoidCallback onImage;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(.55))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedImagePath != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colorScheme.primaryContainer.withOpacity(.45), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(selectedImagePath!), width: 58, height: 58, fit: BoxFit.cover)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('تم اختيار صورة. اكتب وصفاً أو سؤالك عنها ثم أرسلها مع الرسالة.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant))),
                  IconButton(onPressed: onRemoveImage, icon: const Icon(Icons.close_rounded)),
                ]),
              ),
            Row(
              children: [
            IconButton(tooltip: 'رفع صورة', onPressed: isLoading ? null : onImage, icon: const Icon(Icons.image_outlined)),
            IconButton(tooltip: 'رفع ملف', onPressed: isLoading ? null : onFile, icon: const Icon(Icons.attach_file_rounded)),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'اكتب سؤالك...',
                  filled: true,
                  fillColor: colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => IconButton.filled(
                tooltip: 'إرسال',
                onPressed: isLoading || (value.text.trim().isEmpty && selectedImagePath == null) ? null : onSend,
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }
}
