import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One "I exported my data" event, stored locally on the device.
class ExportRecord {
  final String scope; // 'session' | 'all'
  final String? sessionId; // set when scope == 'session'
  final String method; // 'email' | 'file'
  final String recipient; // email address, or 'Shared as file'
  final List<String> formats; // e.g. ['PDF', 'CSV']
  final DateTime sentAt;

  const ExportRecord({
    required this.scope,
    required this.sessionId,
    required this.method,
    required this.recipient,
    required this.formats,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'sessionId': sessionId,
        'method': method,
        'recipient': recipient,
        'formats': formats,
        'sentAt': sentAt.toIso8601String(),
      };

  factory ExportRecord.fromJson(Map<String, dynamic> j) => ExportRecord(
        scope: j['scope'] as String? ?? 'all',
        sessionId: j['sessionId'] as String?,
        method: j['method'] as String? ?? 'email',
        recipient: j['recipient'] as String? ?? '',
        formats: (j['formats'] as List?)?.map((e) => '$e').toList() ?? const [],
        sentAt: DateTime.tryParse(j['sentAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Local log of data exports (email + file share). Device-local via
/// SharedPreferences — no backend or SQL migration needed.
class ExportHistoryService {
  static const _key = 'export_history_v1';
  static const _cap = 100;

  Future<List<ExportRecord>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ExportRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds [record] to the front of the log (newest first), capped at [_cap].
  Future<void> record(ExportRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await all();
    final updated = [record, ...current].take(_cap).toList();
    await prefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  /// Most recent export of a specific session, or null.
  Future<ExportRecord?> lastForSession(String sessionId) async {
    final list = await all();
    for (final r in list) {
      if (r.scope == 'session' && r.sessionId == sessionId) return r;
    }
    return null;
  }

  /// Most recent full "all my data" export, or null.
  Future<ExportRecord?> lastForScope(String scope) async {
    final list = await all();
    for (final r in list) {
      if (r.scope == scope) return r;
    }
    return null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
