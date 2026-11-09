import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_export_service.dart';

/// Thrown when the email could not be sent. [message] is safe to show to the
/// user.
class EmailExportException implements Exception {
  final String message;
  const EmailExportException(this.message);
  @override
  String toString() => message;
}

/// Sends export files to an email address by invoking the `send-data-email`
/// Supabase Edge Function. The function verifies the caller's auth token and
/// hands the attachments to the email provider (Resend / SendGrid) — no email
/// credentials ever live in the app.
class EmailExportService {
  static const _functionName = 'send-data-email';

  SupabaseClient get _client => Supabase.instance.client;

  /// Sends [files] to [toEmail]. Throws [EmailExportException] on failure.
  Future<void> send({
    required String toEmail,
    required String subject,
    String? message,
    required List<ExportFile> files,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const EmailExportException('You must be signed in to send data.');
    }
    if (files.isEmpty) {
      throw const EmailExportException('Nothing to send — pick at least one format.');
    }

    final payload = {
      'to': toEmail.trim(),
      'subject': subject,
      'message': message ?? '',
      'attachments': [
        for (final f in files)
          {
            'filename': f.filename,
            'mimeType': f.mimeType,
            'contentBase64': base64Encode(f.bytes),
          },
      ],
    };

    try {
      final res = await _client.functions.invoke(_functionName, body: payload);
      if (res.status >= 200 && res.status < 300) return;
      throw EmailExportException(_extractError(res.data) ??
          'The server rejected the request (status ${res.status}).');
    } on FunctionException catch (e) {
      throw EmailExportException(_extractError(e.details) ??
          _extractError(e.reasonPhrase) ??
          'Could not reach the email service. Check your connection and try again.');
    } on EmailExportException {
      rethrow;
    } catch (e) {
      throw EmailExportException('Could not send the email: $e');
    }
  }

  /// Pulls a human-readable message out of whatever the function returned.
  String? _extractError(Object? data) {
    if (data == null) return null;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      try {
        final decoded = jsonDecode(s);
        return _extractError(decoded) ?? s;
      } catch (_) {
        return s;
      }
    }
    if (data is Map) {
      final v = data['error'] ?? data['message'] ?? data['msg'];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
