import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/ai_chat_message.dart';
import '../models/medical_intake.dart';
import 'medical_ai_error_handler.dart';

class MedicalAiApiService {
  static const String _geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY');
  static const String _geminiApiKeyLower =
      String.fromEnvironment('gemini_api_key');
  static const String _medicalAiBaseUrl =
      String.fromEnvironment('MEDICAL_AI_BASE_URL');
  static const String _openRouterApiKey =
      String.fromEnvironment('OPENROUTER_API_KEY');
  static const String _aiProvider =
      String.fromEnvironment('AI_PROVIDER', defaultValue: 'gemini');
  static const String _geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const String _geminiModels = String.fromEnvironment(
    'GEMINI_MODELS',
    defaultValue: 'gemini-2.5-flash,gemini-2.0-flash,gemini-1.5-flash',
  );
  static const String _openRouterModel = String.fromEnvironment(
    'OPENROUTER_MODEL',
    defaultValue: 'google/gemini-2.0-flash-exp:free',
  );
  static const String _openRouterModels = String.fromEnvironment(
    'OPENROUTER_MODELS',
    defaultValue: 'google/gemini-2.0-flash-exp:free,meta-llama/llama-3.1-8b-instruct:free,mistralai/mistral-7b-instruct:free',
  );

  final Dio _dio;
  final String? baseUrl;
  final String? apiKey;
  final String model;

  MedicalAiApiService({
    Dio? dio,
    this.baseUrl = _medicalAiBaseUrl,
    String? apiKey,
    this.model = _geminiModel,
  })  : apiKey = apiKey ?? _resolveDefaultApiKey(),
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 45)));

  static String _resolveDefaultApiKey() {
    if (_geminiApiKey.trim().isNotEmpty) return _geminiApiKey.trim();
    if (_geminiApiKeyLower.trim().isNotEmpty) return _geminiApiKeyLower.trim();
    return '';
  }

  Future<String> sendMedicalMessage({
    required MedicalIntake intake,
    required List<AiChatMessage> history,
    required String message,
    String? attachmentPath,
    String? attachmentType,
  }) async {
    final configuredUrl = (baseUrl ?? '').trim();
    final key = (apiKey ?? '').trim();

    final openRouterKey = _openRouterApiKey.trim();
    final useOpenRouter = _aiProvider.trim().toLowerCase() == 'openrouter' ||
        (key.isEmpty && openRouterKey.isNotEmpty);

    if (configuredUrl.isNotEmpty) {
      return _sendToCustomMedicalAiBackend(
        configuredUrl: configuredUrl,
        key: key,
        intake: intake,
        history: history,
        message: message,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
      );
    }

    if (useOpenRouter) {
      if (openRouterKey.isEmpty) {
        throw StateError(MedicalAiErrorHandler.unavailableMessage);
      }
      return _sendToOpenRouter(
        key: openRouterKey,
        intake: intake,
        history: history,
        message: message,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
      );
    }

    if (key.isEmpty) {
      throw StateError(MedicalAiErrorHandler.unavailableMessage);
    }

    final geminiModels = _configuredModels(_geminiModels, fallback: model);
    String? lastFriendlyError;
    for (final geminiModel in geminiModels) {
      final reply = await _sendToGeminiModel(
        key: key,
        modelName: geminiModel,
        intake: intake,
        history: history,
        message: message,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
      );
      if (!_shouldTryFallback(reply)) return reply;
      lastFriendlyError = reply;
      _debug('Gemini fallback triggered after $geminiModel: $reply');
    }

    if (openRouterKey.isNotEmpty) {
      final reply = await _sendToOpenRouter(
        key: openRouterKey,
        intake: intake,
        history: history,
        message: message,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
      );
      if (!_shouldTryFallback(reply)) return reply;
      lastFriendlyError = reply;
    }

    throw StateError(lastFriendlyError ?? MedicalAiErrorHandler.genericMessage);
  }

  Future<String> _sendToGeminiModel({
    required String key,
    required String modelName,
    required MedicalIntake intake,
    required List<AiChatMessage> history,
    required String message,
    String? attachmentPath,
    String? attachmentType,
  }) async {
    final geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent';
    final promptText = _buildMedicalPrompt(intake, history, message, attachmentType);
    final parts = <Map<String, dynamic>>[];
    final inlineImage = await _buildGeminiInlineImage(attachmentPath, attachmentType);
    if (inlineImage != null) {
      parts.add(inlineImage);
    }
    parts.add({'text': promptText});

    final payload = {
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        }
      ],
      'generationConfig': {
        'temperature': 0.25,
        'maxOutputTokens': 1200,
      },
    };

    for (var attempt = 0; attempt < _maxRetryAttempts; attempt++) {
      try {
        _debug('Gemini Request URL: $geminiUrl');
        _debug('Gemini Request Model: $modelName');
        _debug('Gemini Attempt: ${attempt + 1}/$_maxRetryAttempts');

        final response = await _dio.post(
          geminiUrl,
          data: payload,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
          ),
        );

        _debug('Gemini Status Code: ${response.statusCode}');
        _debug('Gemini Response Body: ${response.data}');

        final reply = _extractGeminiReply(response.data);
        if (reply.isEmpty) {
          throw StateError(MedicalAiErrorHandler.genericMessage);
        }
        return reply;
      } on DioException catch (e) {
        if (_shouldRetryException(e) && attempt < _maxRetryAttempts - 1) {
          await _delayBeforeRetry(attempt, serviceName: 'Gemini', modelName: modelName, error: e);
          continue;
        }
        return _formatDioError(e, serviceName: 'Gemini');
      } on SocketException catch (e) {
        _debug('Gemini SocketException: $e');
        if (attempt < _maxRetryAttempts - 1) {
          await _delayBeforeRetry(attempt, serviceName: 'Gemini', modelName: modelName, error: e);
          continue;
        }
        return MedicalAiErrorHandler.friendlyMessage(e);
      } catch (e) {
        _debug('Gemini Unknown Error: $e');
        return MedicalAiErrorHandler.friendlyMessage(e);
      }
    }

    return MedicalAiErrorHandler.busyMessage;
  }

  Future<String> _sendToCustomMedicalAiBackend({
    required String configuredUrl,
    required String key,
    required MedicalIntake intake,
    required List<AiChatMessage> history,
    required String message,
    String? attachmentPath,
    String? attachmentType,
  }) async {
    try {
      _debug('Medical AI Backend URL: $configuredUrl');
      final response = await _dio.post(
        configuredUrl,
        data: {
          'system': _systemPrompt,
          'intake': intake.toPrompt(),
          'message': message,
          'attachmentType': attachmentType,
          'attachmentPath': attachmentPath,
          'history': history.map((e) => e.toMap(firestore: false)).toList(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
        ),
      );

      _debug('Medical AI Backend Status Code: ${response.statusCode}');
      _debug('Medical AI Backend Response Body: ${response.data}');

      return (response.data['reply'] ??
              response.data['message'] ??
              response.data['choices']?[0]?['message']?['content'] ??
              '')
          .toString();
    } on DioException catch (e) {
      return _formatDioError(e, serviceName: 'الخادم الطبي المخصص');
    } on SocketException catch (e) {
      _debug('Medical AI Backend SocketException: $e');
      return MedicalAiErrorHandler.friendlyMessage(e);
    }
  }

  Future<String> _sendToOpenRouter({
    required String key,
    required MedicalIntake intake,
    required List<AiChatMessage> history,
    required String message,
    String? attachmentPath,
    String? attachmentType,
  }) async {
    const openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
    final content = await _buildOpenRouterContent(
      intake: intake,
      history: history,
      message: message,
      attachmentPath: attachmentPath,
      attachmentType: attachmentType,
    );
    final models = _configuredModels(_openRouterModels, fallback: _openRouterModel);
    String? lastFriendlyError;

    for (final openRouterModel in models) {
      final payload = {
        'model': openRouterModel,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': content},
        ],
        'temperature': 0.25,
        'max_tokens': 1200,
      };

      for (var attempt = 0; attempt < _maxRetryAttempts; attempt++) {
        try {
          _debug('OpenRouter Request URL: $openRouterUrl');
          _debug('OpenRouter Request Model: $openRouterModel');
          _debug('OpenRouter Attempt: ${attempt + 1}/$_maxRetryAttempts');
          _debug('OpenRouter API Key Present: ${key.trim().isNotEmpty} length=${key.trim().length}');
          _debug('OpenRouter Headers: Content-Type=application/json, Authorization=Bearer ***${key.length >= 4 ? key.substring(key.length - 4) : 'short'}, X-Title=Nabd Medical AI');
          _debug('OpenRouter Request Payload: $payload');

          final response = await _dio.post(
            openRouterUrl,
            data: payload,
            options: Options(
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $key',
                'X-Title': 'Nabd Medical AI',
              },
            ),
          );

          _debug('OpenRouter Status Code: ${response.statusCode}');
          _debug('OpenRouter Response Body: ${response.data}');

          final reply = _extractOpenRouterReply(response.data);
          if (reply.isEmpty) {
            lastFriendlyError = MedicalAiErrorHandler.genericMessage;
            break;
          }
          if (!_shouldTryFallback(reply)) return reply;
          lastFriendlyError = reply;
          break;
        } on DioException catch (e) {
          if (_shouldRetryException(e) && attempt < _maxRetryAttempts - 1) {
            await _delayBeforeRetry(attempt, serviceName: 'OpenRouter', modelName: openRouterModel, error: e);
            continue;
          }
          lastFriendlyError = _formatDioError(e, serviceName: 'OpenRouter');
          break;
        } on SocketException catch (e) {
          _debug('OpenRouter SocketException: $e');
          if (attempt < _maxRetryAttempts - 1) {
            await _delayBeforeRetry(attempt, serviceName: 'OpenRouter', modelName: openRouterModel, error: e);
            continue;
          }
          lastFriendlyError = MedicalAiErrorHandler.friendlyMessage(e);
          break;
        } catch (e) {
          _debug('OpenRouter Unknown Error: $e');
          lastFriendlyError = MedicalAiErrorHandler.friendlyMessage(e);
          break;
        }
      }
    }

    throw StateError(lastFriendlyError ?? MedicalAiErrorHandler.genericMessage);
  }


  List<String> _configuredModels(String rawModels, {required String fallback}) {
    final models = rawModels
        .split(',')
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toList();
    if (!models.contains(fallback) && fallback.trim().isNotEmpty) {
      models.insert(0, fallback.trim());
    }
    return models.isEmpty ? [fallback] : models.toSet().toList();
  }

  bool _shouldTryFallback(String message) {
    final text = message.toLowerCase();
    return text.contains('الخدمة مشغولة') ||
        text.contains('غير متاحة') ||
        text.contains('حدث أمر غير متوقع') ||
        text.contains('slow') ||
        text.contains('timeout') ||
        text.contains('503') ||
        text.contains('unavailable') ||
        text.contains('high demand') ||
        text.contains('resource_exhausted') ||
        text.contains('quota_exceeded') ||
        text.contains('rate_limit') ||
        text.contains('rate limit') ||
        text.contains('overloaded') ||
        text.contains(MedicalAiErrorHandler.busyMessage) ||
        text.contains(MedicalAiErrorHandler.unavailableMessage);
  }

  static const int _maxRetryAttempts = 3;

  bool _shouldRetryException(Object error) {
    final text = error.toString().toLowerCase();
    if (error is SocketException) return true;
    if (error is DioException) {
      final status = error.response?.statusCode;
      return status == 408 ||
          status == 429 ||
          status == 500 ||
          status == 502 ||
          status == 503 ||
          status == 504 ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          text.contains('unavailable') ||
          text.contains('high_demand') ||
          text.contains('high demand') ||
          text.contains('resource_exhausted') ||
          text.contains('quota_exceeded') ||
          text.contains('rate_limit') ||
          text.contains('rate limit') ||
          text.contains('overloaded');
    }
    return text.contains('socket') || text.contains('timeout');
  }

  Future<void> _delayBeforeRetry(
    int attempt, {
    required String serviceName,
    required String modelName,
    required Object error,
  }) async {
    final delay = Duration(milliseconds: 700 * (attempt + 1) * (attempt + 1));
    _debug('$serviceName retry ${attempt + 2}/$_maxRetryAttempts for $modelName after ${delay.inMilliseconds}ms. Error: $error');
    await Future.delayed(delay);
  }

  String _buildMedicalPrompt(
    MedicalIntake intake,
    List<AiChatMessage> history,
    String message,
    String? attachmentType,
  ) {
    final hasImage = attachmentType == 'image';
    return 'بيانات الحالة:\n${intake.toPrompt()}\n\n'
        'سجل مختصر:\n${history.map((e) => '${e.isUser ? 'المستخدم' : 'المساعد'}: ${e.content}').join('\n')}\n\n'
        '${hasImage ? 'مهمة الصورة: لا تعتذر بأنك لا تستطيع رؤية الصورة إذا كانت مرفقة. افحص الصورة بصرياً كصورة طبية أو دواء: 1) اقرأ أي نص/أرقام/اسم دواء ظاهر. 2) إذا كانت تحليل/فحص فرتب القيم المقروءة واشرح معناها العام وحدد القيم التي تحتاج مراجعة طبيب. 3) إذا كانت دواء فاذكر الاسم الظاهر أو الأقرب، المادة/الاستخدام العام إن أمكن، وتحذيرات السلامة. 4) إذا كانت غير واضحة اذكر ما استطعت قراءته فقط واطلب صورة أوضح. لا تخترع قيماً غير ظاهرة ولا تقدم تشخيصاً نهائياً.\n\n' : ''}'
        'سؤال المستخدم:\n$message';
  }

  Future<Map<String, dynamic>?> _buildGeminiInlineImage(
    String? attachmentPath,
    String? attachmentType,
  ) async {
    if (attachmentType != 'image' || attachmentPath == null || attachmentPath.trim().isEmpty) {
      return null;
    }
    final file = File(attachmentPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return {
      'inline_data': {
        'mime_type': _mimeTypeForPath(attachmentPath),
        'data': base64Encode(bytes),
      },
    };
  }

  Future<dynamic> _buildOpenRouterContent({
    required MedicalIntake intake,
    required List<AiChatMessage> history,
    required String message,
    String? attachmentPath,
    String? attachmentType,
  }) async {
    final prompt = _buildMedicalPrompt(intake, history, message, attachmentType);
    if (attachmentType != 'image' || attachmentPath == null || attachmentPath.trim().isEmpty) {
      return prompt;
    }
    final file = File(attachmentPath);
    if (!await file.exists()) return prompt;
    final dataUri = 'data:${_mimeTypeForPath(attachmentPath)};base64,${base64Encode(await file.readAsBytes())}';
    return [
      {'type': 'text', 'text': prompt},
      {
        'type': 'image_url',
        'image_url': {'url': dataUri},
      },
    ];
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  String _extractOpenRouterReply(dynamic data) {
    if (data is! Map) return '';
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = choices.first['message'];
    if (message is! Map) return '';
    return (message['content'] ?? '').toString().trim();
  }

  String _extractGeminiReply(dynamic data) {
    if (data is! Map) return '';
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final content = candidates.first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return '';
    return parts
        .map((part) => part is Map ? part['text'] : null)
        .whereType<String>()
        .join('\n')
        .trim();
  }

  String _formatDioError(DioException e, {required String serviceName}) {
    final statusCode = e.response?.statusCode;
    final responseBody = e.response?.data;
    final requestUrl = e.requestOptions.uri.toString();

    _debug('$serviceName Request URL: $requestUrl');
    _debug('$serviceName Status Code: $statusCode');
    _debug('$serviceName DioException Type: ${e.type}');
    _debug('$serviceName Error Response: $responseBody');
    _debug('$serviceName Error Message: ${e.message}');

    _debug('$serviceName Extracted API Error: ${_extractApiErrorMessage(responseBody)}');

    return MedicalAiErrorHandler.friendlyMessage(e);
  }

  String _formatAuthenticationError({
    required int? statusCode,
    required String googleMessage,
    required String? fallbackMessage,
  }) {
    _debug('Gemini authentication error status=$statusCode message=$googleMessage fallback=$fallbackMessage');
    return MedicalAiErrorHandler.unavailableMessage;
  }

  String _extractApiErrorMessage(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final code = error['code'];
        final status = error['status'];
        final message = error['message'];
        return [
          if (code != null) 'code=$code',
          if (status != null) 'status=$status',
          if (message != null) 'message=$message',
        ].join(' | ');
      }
      return data.toString();
    }
    return data?.toString() ?? '';
  }

  void _debug(String message) {
    // ignore: avoid_print
    print(message);
  }

  String get _systemPrompt =>
      'أنت مساعد طبي عربي داخل تطبيق نبض. تستطيع تحليل الصور المرفقة بصرياً وقراءة النصوص الظاهرة في صور التحاليل والأدوية عندما تصل ضمن الطلب. قدم إجابة منظمة وواضحة، نبه للحالات الطارئة، ولا تقدم تشخيصاً نهائياً أو وصفة دوائية خطرة.';
}
