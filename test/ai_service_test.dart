import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/services/ai_service.dart';

List<EmotionReading> _readings() => [
      for (var i = 0; i < 3; i++)
        EmotionReading(
          id: i,
          createdAt: DateTime(2026, 1, 1, 9, i),
          emotion: i.isEven ? 'happy' : 'neutral',
          confidence: 0.9,
          hr: 70 + i,
          spo2: 98,
          sensorQuality: 'GOOD',
        ),
    ];

const _insightJson = {
  'emotionalSummary': 'Mostly calm and positive.',
  'stressLevel': 'Low',
  'trendAnalysis': 'Stable over the session.',
  'recommendations': ['Keep it up'],
};

/// Resolves [invoke] with [respond], recording the function name and body.
AiService _service(
  Future<FunctionResponse> Function() respond, {
  List<String>? names,
  List<Object?>? bodies,
}) =>
    AiService(invoke: (name, {body}) {
      names?.add(name);
      bodies?.add(body);
      return respond();
    });

Future<String> _errorOf(AiService ai) async {
  try {
    await ai.generateInsight(_readings());
  } on AiException catch (e) {
    return e.message;
  }
  fail('expected AiException');
}

void main() {
  group('AiService via ai-proxy Edge Function', () {
    test('sends prompts + JSON schema to ai-proxy and parses the reply',
        () async {
      final names = <String>[];
      final bodies = <Object?>[];
      final ai = _service(
        () async => FunctionResponse(
          status: 200,
          data: {'text': jsonEncode(_insightJson)},
        ),
        names: names,
        bodies: bodies,
      );

      final insight = await ai.generateInsight(_readings());

      expect(insight.stressLevel, 'Low');
      expect(insight.recommendations, ['Keep it up']);
      expect(names, ['ai-proxy']);
      final body = bodies.single as Map;
      // Only prompts + schema travel from the app — no credentials.
      expect(body.keys, unorderedEquals(['system', 'prompt', 'schema']));
      expect(body['system'], contains('MEDS'));
      expect(body['prompt'], contains('Total readings: 3'));
      final schema = body['schema'] as Map;
      expect(schema['type'], 'object');
      expect(schema['additionalProperties'], false);
    });

    test('shows the server error message on a non-2xx reply', () async {
      final ai = _service(() async => throw const FunctionException(
            status: 429,
            details: {'error': 'AI rate limit reached.'},
          ));
      expect(await _errorOf(ai), 'AI rate limit reached.');
    });

    test('falls back to a status message when the server sends none',
        () async {
      final ai = _service(() async => throw const FunctionException(
            status: 404,
          ));
      expect(await _errorOf(ai), contains('not deployed'));
    });

    test('reports a network failure as unreachable', () async {
      final ai = _service(() async => throw Exception('socket closed'));
      expect(await _errorOf(ai), contains('Could not reach'));
    });

    test('rejects a reply that is not the expected JSON', () async {
      final ai = _service(
        () async => FunctionResponse(status: 200, data: {'text': 'not json'}),
      );
      expect(await _errorOf(ai), contains('unexpected response'));
    });

    test('empty readings fail before any network call', () async {
      final names = <String>[];
      final ai = _service(
        () async => FunctionResponse(status: 200),
        names: names,
      );
      await expectLater(
        ai.generateInsight(const []),
        throwsA(isA<AiException>()),
      );
      expect(names, isEmpty);
    });
  });
}
