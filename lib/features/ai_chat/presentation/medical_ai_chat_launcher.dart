import 'package:flutter/material.dart';

import 'pages/medical_ai_chat_screen.dart';

class MedicalAiChatLauncher {
  const MedicalAiChatLauncher._();

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MedicalAiChatScreen(),
        settings: const RouteSettings(name: '/medical_ai_chat'),
      ),
    );
  }

  static Widget floatingButton(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'global_ai_chat_fab',
      elevation: 0,
      highlightElevation: 0,
      onPressed: () => open(context),
      icon: const Icon(Icons.smart_toy_rounded),
      label: const Text('مساعد AI'),
    );
  }
}
