import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_admin_report.dart';
import '../models/ai_insight.dart';
import '../models/ai_trend_report.dart';
import '../models/emotion_reading.dart';
import 'ai_config.dart';

/// Talks to the Google Gemini (Generative Language) API to turn MEDS data into
/// AI analyses:
///   • [generateInsight]        — per-user / per-session wellness insight
///   • [generateTrendAnalysis]  — weekly / monthly emotional-trend report (admin)
///   • [generateAdminReport]    — one-click platform-wide report (admin)
///
/// This calls the REST API directly with the `http` package. Structured output
/// (`generationConfig.responseSchema` + `responseMimeType: application/json`)
/// guarantees the model replies with JSON that matches the target model.
class AiService {
  // ---- Public API ---------------------------------------------------------

  /// Per-user / per-session insight: summary, stress level, trend, tips.
  Future<AiInsight> generateInsight(List<EmotionReading> readings) async {
    if (readings.isEmpty) {
      throw const AiException(
        'No readings yet — run a detection session first.',
      );
    }

    final map = await _request(
      systemPrompt:
          'You are a supportive emotional-wellness assistant inside MEDS, an '
          'app that detects emotions from a phone camera and combines them with '
          'heart-rate (and SpO2) data from an ESP32 sensor. You receive '
          'aggregated statistics for ONE user. Write warm, encouraging, '
          'plain-language insights. You are NOT a doctor: never diagnose. If the '
          'data suggests ongoing distress, gently suggest talking to someone '
          'they trust or a professional. Base every statement only on the data '
          'provided.',
      userPrompt: "Here is the user's emotion + heart-rate data:\n\n"
          '${_buildDataSummary(readings)}\n\n'
          'Produce: (1) a short emotional summary (2-3 sentences), (2) an '
          'overall stress level, (3) a trend analysis describing how their '
          'emotional and physiological state appears to be changing over time, '
          'and (4) 3-5 short, practical, personalized recommendations.',
      schema: _insightSchema,
    );
    return AiInsight.fromJson(map);
  }

  /// Admin trend dashboard: analyse emotional/physiological data that has
  /// already been bucketed by the caller into weekly or monthly periods.
  /// [dataSummary] is a compact text summary of those buckets; [granularity]
  /// is 'weekly' or 'monthly' (used only to phrase the prompt).
  Future<AiTrendReport> generateTrendAnalysis({
    required String dataSummary,
    required String granularity,
  }) async {
    if (dataSummary.trim().isEmpty) {
      throw const AiException('Not enough data yet to analyze trends.');
    }

    final map = await _request(
      systemPrompt:
          'You are an analytics assistant inside MEDS, an app that detects '
          'emotions from a phone camera and combines them with heart-rate '
          '(and SpO2) data from an ESP32 sensor. You are summarizing '
          'AGGREGATED, anonymized data across users for an administrator. Write '
          'clear, plain-language analytics. You are NOT a doctor: never '
          'diagnose individuals. Base every statement only on the data '
          'provided.',
      userPrompt: 'Here is $granularity emotion + heart-rate data, aggregated '
          'per period across all users (oldest to newest):\n\n$dataSummary\n\n'
          'Analyze how the emotional and physiological picture is changing over '
          'the periods. Produce a one-line headline, a short analysis '
          'paragraph, what is going well, what to keep an eye on, and a few '
          'practical recommendations.',
      schema: _trendSchema,
    );
    return AiTrendReport.fromJson(map);
  }

  /// Admin one-click report: turn aggregated platform statistics (built by the
  /// caller) into a structured written report.
  Future<AiAdminReport> generateAdminReport({
    required String dataSummary,
  }) async {
    if (dataSummary.trim().isEmpty) {
      throw const AiException('Not enough data yet to generate a report.');
    }

    final map = await _request(
      systemPrompt:
          'You write concise platform-analytics reports for administrators of '
          'MEDS, an app that detects emotions from a phone camera and combines '
          'them with heart-rate (and SpO2) data from an ESP32 sensor. You '
          'receive AGGREGATED, anonymized statistics. Write clear, '
          'professional, plain-language reporting. You are NOT a doctor: never '
          'diagnose individuals. Base every statement only on the data '
          'provided.',
      userPrompt: 'Here is aggregated platform data for MEDS:\n\n$dataSummary\n\n'
          'Write a concise admin report covering: an executive summary, the '
          'overall emotional climate, user engagement, key findings, concerns '
          'to watch, and prioritized, practical recommendations.',
      schema: _reportSchema,
      maxOutputTokens: 3072,
    );
    return AiAdminReport.fromJson(map);
  }

  // ---- Shared Gemini call -------------------------------------------------

  /// Posts a single structured-output request to Gemini and returns the parsed
  /// JSON object. Shared by every public method above.
  Future<Map<String, dynamic>> _request({
    required String systemPrompt,
    required String userPrompt,
    required Map<String, dynamic> schema,
    int maxOutputTokens = 2048,
  }) async {
    if (!AiConfig.hasKey) {
      throw const AiException(
        'No AI API key set. Add your Google Gemini API key in '
        'lib/services/ai_config.dart (see the instructions at the top of that '
        'file).',
      );
    }

    final body = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt}
          ],
        }
      ],
      'generationConfig': {
        'maxOutputTokens': maxOutputTokens,
        // gemini-2.5-flash "thinks" by default and thinking tokens count
        // against maxOutputTokens. These tasks are simple, so turn thinking off
        // for speed/cost and to keep the full budget for the JSON answer.
        // NOTE: if you switch model to 'gemini-2.5-pro', thinking can't be
        // fully disabled — remove this thinkingConfig or use a budget >= 128.
        'thinkingConfig': {'thinkingBudget': 0},
        'responseMimeType': 'application/json',
        'responseSchema': schema,
      },
    };

    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(
              '${AiConfig.endpoint}/${AiConfig.model}:generateContent',
            ),
            headers: {
              'content-type': 'application/json',
              'x-goog-api-key': AiConfig.apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const AiException(
        'Could not reach the AI service. Check your internet connection.',
      );
    }

    if (res.statusCode != 200) {
      throw AiException(_errorFor(res.statusCode));
    }

    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List;
      final parts = (candidates.first as Map<String, dynamic>)['content']['parts']
          as List;
      final text = parts
          .whereType<Map<String, dynamic>>()
          .firstWhere((p) => p['text'] != null)['text'] as String;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException(
        'The AI service returned an unexpected response.',
      );
    }
  }

  String _errorFor(int code) {
    switch (code) {
      case 400:
        return 'Invalid AI request or API key. Check the Gemini key in '
            'lib/services/ai_config.dart.';
      case 403:
        return 'This API key is not allowed to use the model (check the key '
            'restrictions or that the Generative Language API is enabled).';
      case 429:
        return 'AI rate limit / quota reached. Please wait a moment and try '
            'again.';
      case 500:
      case 503:
        return 'The AI service is busy right now. Try again shortly.';
      default:
        return 'AI request failed (HTTP $code).';
    }
  }

  // ---- Response schemas ---------------------------------------------------

  static final Map<String, dynamic> _insightSchema = {
    'type': 'OBJECT',
    'properties': {
      'emotionalSummary': {'type': 'STRING'},
      'stressLevel': {
        'type': 'STRING',
        'enum': ['Low', 'Moderate', 'Elevated', 'High'],
      },
      'trendAnalysis': {'type': 'STRING'},
      'recommendations': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': [
      'emotionalSummary',
      'stressLevel',
      'trendAnalysis',
      'recommendations',
    ],
    'propertyOrdering': [
      'emotionalSummary',
      'stressLevel',
      'trendAnalysis',
      'recommendations',
    ],
  };

  static final Map<String, dynamic> _trendSchema = {
    'type': 'OBJECT',
    'properties': {
      'headline': {'type': 'STRING'},
      'analysis': {'type': 'STRING'},
      'positives': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'concerns': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'recommendations': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': [
      'headline',
      'analysis',
      'positives',
      'concerns',
      'recommendations',
    ],
    'propertyOrdering': [
      'headline',
      'analysis',
      'positives',
      'concerns',
      'recommendations',
    ],
  };

  static final Map<String, dynamic> _reportSchema = {
    'type': 'OBJECT',
    'properties': {
      'executiveSummary': {'type': 'STRING'},
      'emotionalClimate': {'type': 'STRING'},
      'engagement': {'type': 'STRING'},
      'keyFindings': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'concerns': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'recommendations': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': [
      'executiveSummary',
      'emotionalClimate',
      'engagement',
      'keyFindings',
      'concerns',
      'recommendations',
    ],
    'propertyOrdering': [
      'executiveSummary',
      'emotionalClimate',
      'engagement',
      'keyFindings',
      'concerns',
      'recommendations',
    ],
  };

  /// Builds a compact, token-efficient text summary of the readings. We send
  /// aggregates (not every row) to keep requests small and cheap.
  String _buildDataSummary(List<EmotionReading> readings) {
    // Readings arrive newest-first.
    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final total = readings.length;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final emotionLines = sorted
        .map((e) =>
            '- ${e.key}: ${e.value} (${(e.value / total * 100).round()}%)')
        .join('\n');

    final hr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final spo2 = readings.where((r) => r.spo2 > 0).map((r) => r.spo2).toList();

    final buf = StringBuffer();
    buf.writeln('Total readings: $total');
    buf.writeln('Time span: ${_fmt(readings.last.createdAt)} to '
        '${_fmt(readings.first.createdAt)}');
    buf.writeln('Most frequent emotion: ${sorted.first.key}');
    buf.writeln('Emotion distribution:');
    buf.writeln(emotionLines);
    if (hr.isNotEmpty) {
      buf.writeln('Heart rate (bpm): avg ${_avg(hr)}, '
          'min ${hr.reduce((a, b) => a < b ? a : b)}, '
          'max ${hr.reduce((a, b) => a > b ? a : b)}, latest ${hr.first}');
    } else {
      buf.writeln('Heart rate: no sensor data available for these readings.');
    }
    if (spo2.isNotEmpty) {
      buf.writeln('Blood oxygen SpO2 (%): avg ${_avg(spo2)}');
    }
    // Last 15 emotions, oldest -> newest, so the model can read a trend.
    final recent =
        readings.take(15).toList().reversed.map((r) => r.emotion).join(', ');
    buf.writeln('Recent emotions (oldest to newest): $recent');
    return buf.toString();
  }

  int _avg(List<int> v) => (v.reduce((a, b) => a + b) / v.length).round();

  String _fmt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}

/// A user-friendly error from [AiService]; [message] is safe to show in the UI.
class AiException implements Exception {
  final String message;
  const AiException(this.message);

  @override
  String toString() => message;
}
