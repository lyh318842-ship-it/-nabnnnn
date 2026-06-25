import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

class MedicalAiErrorHandler {
  static String friendlyMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (error is StateError) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    if (error is SocketException || text.contains('socket') || text.contains('network') || text.contains('internet') || text.contains('connection refused')) {
      return 'تعذر الاتصال بالإنترنت، يرجى التحقق من الشبكة.';
    }
    if (error is TimeoutException || text.contains('timeout') || text.contains('receive timeout') || text.contains('send timeout')) {
      return 'يبدو أن الاتصال بطيء، يرجى المحاولة مرة أخرى.';
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 503 || status == 502 || status == 504 || text.contains('unavailable') || text.contains('high demand')) {
        return 'فشل مزود الذكاء الاصطناعي مؤقتاً. التفاصيل: ${error.response?.data ?? error.message}';
      }
      if (status == 400 || text.contains('invalid argument')) {
        return 'يرجى توضيح سؤالك بشكل أكبر حتى أتمكن من مساعدتك.';
      }
      if (status == 408 || error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout || error.type == DioExceptionType.sendTimeout) {
        return 'يبدو أن الاتصال بطيء، يرجى المحاولة مرة أخرى.';
      }
      if (status != null && status >= 500) return 'فشل مزود الذكاء الاصطناعي (HTTP $status). التفاصيل: ${error.response?.data ?? error.message}';
    }
    if (text.contains('503') || text.contains('unavailable') || text.contains('high demand') || text.contains('overloaded')) {
      return 'فشل مزود الذكاء الاصطناعي. التفاصيل: ${error.toString()}';
    }
    if (text.contains('400') || text.contains('bad request') || text.contains('تعذر فهم')) {
      return 'يرجى توضيح سؤالك بشكل أكبر حتى أتمكن من مساعدتك.';
    }
    return 'حدث خطأ غير متوقع: ${error.toString()}';
  }
}
