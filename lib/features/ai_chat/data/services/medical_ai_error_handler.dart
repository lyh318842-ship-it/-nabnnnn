import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class MedicalAiErrorHandler {
  static const String busyMessage = 'الخدمة مشغولة حالياً، يرجى المحاولة بعد قليل.';
  static const String unavailableMessage = 'المساعد الطبي غير متاح مؤقتاً، يرجى المحاولة مرة أخرى بعد قليل.';
  static const String networkMessage = 'تعذر الاتصال بالإنترنت، يرجى التحقق من الشبكة ثم المحاولة مرة أخرى.';
  static const String timeoutMessage = 'استغرق الطلب وقتاً أطول من المعتاد، يرجى المحاولة مرة أخرى بعد قليل.';
  static const String unclearMessage = 'يرجى توضيح سؤالك بشكل أكبر حتى أتمكن من مساعدتك.';
  static const String genericMessage = 'تعذر الحصول على رد حالياً، يرجى المحاولة مرة أخرى بعد قليل.';

  static String friendlyMessage(Object error) {
    logTechnicalError(error);

    final text = error.toString().toLowerCase();
    if (text.contains(busyMessage) || text.contains('الخدمة مشغولة')) return busyMessage;
    if (text.contains(unavailableMessage) || text.contains('غير متاح مؤقت')) return unavailableMessage;
    if (text.contains(genericMessage) || text.contains('تعذر الحصول على رد')) return genericMessage;

    if (error is SocketException ||
        text.contains('socket') ||
        text.contains('network') ||
        text.contains('internet') ||
        text.contains('connection refused')) {
      return networkMessage;
    }

    if (error is TimeoutException ||
        text.contains('timeout') ||
        text.contains('receive timeout') ||
        text.contains('send timeout')) {
      return timeoutMessage;
    }

    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 400 || text.contains('invalid argument') || text.contains('bad request')) {
        return unclearMessage;
      }
      if (status == 401 || status == 403) return unavailableMessage;
      if (status == 408 ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return timeoutMessage;
      }
      if (status == 429 || _isQuotaOrRateLimit(text)) return busyMessage;
      if (status != null && status >= 500) return unavailableMessage;
      return genericMessage;
    }

    if (_isQuotaOrRateLimit(text) ||
        text.contains('503') ||
        text.contains('502') ||
        text.contains('504') ||
        text.contains('unavailable') ||
        text.contains('high_demand') ||
        text.contains('high demand') ||
        text.contains('overloaded')) {
      return busyMessage;
    }

    if (text.contains('400') || text.contains('bad request') || text.contains('تعذر فهم')) {
      return unclearMessage;
    }

    return genericMessage;
  }

  static void logTechnicalError(Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('Medical AI technical error: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }

  static bool _isQuotaOrRateLimit(String text) =>
      text.contains('429') ||
      text.contains('resource_exhausted') ||
      text.contains('quota_exceeded') ||
      text.contains('quota') ||
      text.contains('rate_limit') ||
      text.contains('rate limit');
}
