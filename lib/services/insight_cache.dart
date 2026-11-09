import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_insight.dart';

/// Persists a generated [AiInsight] together with a [marker] describing the
/// reading data it was built from. This lets the home summary appear instantly
/// (even offline) and only be regenerated when there is new reading data.
class InsightCache {
  static String _prefsKey(String cacheKey) => 'insight_$cacheKey';

  static Future<void> save(
    String cacheKey, {
    required AiInsight insight,
    required String marker,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey(cacheKey),
      jsonEncode({'marker': marker, 'insight': insight.toJson()}),
    );
  }

  static Future<CachedInsight?> load(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(cacheKey));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CachedInsight(
        marker: map['marker'] as String? ?? '',
        insight: AiInsight.fromJson(map['insight'] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A cached insight plus the data marker it was generated from.
class CachedInsight {
  final String marker;
  final AiInsight insight;
  const CachedInsight({required this.marker, required this.insight});
}
