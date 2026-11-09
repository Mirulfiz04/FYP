import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/session_analytics.dart';
import '../models/session_summary.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// One file ready to be attached to an email (CSV or PDF).
class ExportFile {
  final String filename;
  final String mimeType;
  final Uint8List bytes;
  const ExportFile({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  /// Human-readable size, e.g. "12.4 KB".
  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1) return '${bytes.length} B';
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// Builds CSV + PDF exports from session data. Pure enough to unit-test: the
/// `build*` methods take data in and return bytes out; only [loadFullExport]
/// touches Supabase.
class DataExportService {
  final SupabaseService _svc;
  final AuthService _auth;
  DataExportService([SupabaseService? svc, AuthService? auth])
      : _svc = svc ?? SupabaseService(),
        _auth = auth ?? AuthService();

  static final _fmtDate = DateFormat('dd MMM yyyy');
  static final _fmtTime = DateFormat('HH:mm:ss');
  static final _fmtStamp = DateFormat('yyyy-MM-dd HH:mm:ss');

  // PdfColor components are 0..1 doubles (the const ctor; fromInt is a factory).
  static const _brand = PdfColor(0.000, 0.659, 0.294); // #00A84B readable green
  static const _ink = PdfColor(0.106, 0.137, 0.200); // #1B2333
  static const _muted = PdfColor(0.478, 0.525, 0.600); // #7A8699
  static const _band = PdfColor(0.937, 0.965, 0.941); // #EFF6F0

  // ---------------------------------------------------------------------------
  // Single session
  // ---------------------------------------------------------------------------

  /// Builds the requested files for one session.
  Future<List<ExportFile>> buildSessionExport({
    required DetectionSession session,
    required List<EmotionReading> readings,
    required SessionAnalytics analytics,
    String? userName,
    bool includeCsv = true,
    bool includePdf = true,
  }) async {
    final out = <ExportFile>[];
    final stamp = _fileStamp(session.startTime);
    if (includeCsv) {
      out.add(ExportFile(
        filename: 'meds_session_$stamp.csv',
        mimeType: 'text/csv',
        bytes: _utf8(_sessionCsv(session, readings)),
      ));
    }
    if (includePdf) {
      out.add(ExportFile(
        filename: 'meds_session_$stamp.pdf',
        mimeType: 'application/pdf',
        bytes: await _sessionPdf(session, readings, analytics, userName),
      ));
    }
    return out;
  }

  String _sessionCsv(DetectionSession s, List<EmotionReading> readings) {
    final buf = StringBuffer()
      ..writeln('MEDS Session Export')
      ..writeln(_csvRow(['Session ID', s.sessionId]))
      ..writeln(_csvRow(['Status', s.status]))
      ..writeln(_csvRow(['Started', _fmtStamp.format(s.startTime.toLocal())]))
      ..writeln(_csvRow(
          ['Ended', s.endTime == null ? '—' : _fmtStamp.format(s.endTime!.toLocal())]))
      ..writeln(_csvRow(['Total readings', '${readings.length}']))
      ..writeln('')
      ..writeln(_csvRow(
          ['#', 'Timestamp', 'Emotion', 'Confidence %', 'HR (bpm)', 'SpO2 %', 'Sensor quality']));
    var i = 1;
    for (final r in readings) {
      buf.writeln(_csvRow([
        '${i++}',
        _fmtStamp.format(r.createdAt.toLocal()),
        r.emotion,
        r.confidence.toStringAsFixed(1),
        '${r.hr}',
        '${r.spo2}',
        r.sensorQuality,
      ]));
    }
    return buf.toString();
  }

  Future<Uint8List> _sessionPdf(
    DetectionSession s,
    List<EmotionReading> readings,
    SessionAnalytics a,
    String? userName,
  ) async {
    final dur = s.endTime != null ? s.endTime!.difference(s.startTime) : Duration.zero;
    final hrText = a.hasValidHr
        ? 'Avg ${a.avgBpm} bpm  (min ${a.minBpm}, max ${a.maxBpm})'
        : 'No valid heart-rate data';

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        _header('Session Report',
            'Generated ${_fmtStamp.format(DateTime.now())}'),
        pw.SizedBox(height: 14),
        _kvBlock({
          if (userName != null) 'User': userName,
          'Session ID': s.sessionId,
          'Status': s.status,
          'Date': _fmtDate.format(s.startTime.toLocal()),
          'Started': _fmtTime.format(s.startTime.toLocal()),
          'Ended': s.endTime == null ? '—' : _fmtTime.format(s.endTime!.toLocal()),
          'Duration': '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s',
        }),
        pw.SizedBox(height: 16),
        _sectionTitle('Summary'),
        _kvBlock({
          'Dominant emotion':
              '${a.dominantEmotion}  (${a.dominantPercent}%, ${a.dominantCount} of ${a.totalReadings})',
          'Heart rate': hrText,
          'Wellness / stress indicator': a.stressIndicator,
          'Avg face confidence': '${a.avgConfidence}%',
          'Valid HR readings': '${a.validHrCount} of ${a.totalReadings}',
          'Session reliability': a.reliability,
          'Sensor quality': a.sensorQuality,
        }),
        if (a.distribution.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('Emotion distribution'),
          _table(
            ['Emotion', 'Count', 'Share'],
            [
              for (final e in a.distribution)
                [e.emotion, '${e.count}', '${e.percent.toStringAsFixed(1)}%'],
            ],
          ),
        ],
        if (s.aiSummary != null) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('AI insight'),
          _paragraph(s.aiSummary!.emotionalSummary),
          if (s.aiSummary!.recommendations.isNotEmpty)
            _paragraph('Recommendations: '
                '${s.aiSummary!.recommendations.join('; ')}'),
        ],
        pw.SizedBox(height: 16),
        _sectionTitle('Readings (${readings.length})'),
        _table(
          ['#', 'Time', 'Emotion', 'Conf %', 'HR', 'SpO2', 'Quality'],
          [
            for (var i = 0; i < readings.length; i++)
              [
                '${i + 1}',
                _fmtTime.format(readings[i].createdAt.toLocal()),
                readings[i].emotion,
                readings[i].confidence.toStringAsFixed(0),
                '${readings[i].hr}',
                '${readings[i].spo2}',
                readings[i].sensorQuality,
              ],
          ],
        ),
      ],
      footer: _footer,
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Full "all my data" export
  // ---------------------------------------------------------------------------

  /// Fetches every session + reading for the signed-in user, then builds the
  /// requested files.
  Future<List<ExportFile>> loadFullExport({
    bool includeCsv = true,
    bool includePdf = true,
  }) async {
    final profile = await _auth.loadProfile();
    final uid = _svc.currentUserId;
    if (uid == null) {
      throw StateError('You must be signed in to export your data.');
    }
    final sessions = await _svc.fetchSessions(limit: 500);
    final readings = await _svc.fetchReadingsForUser(uid, limit: 20000);

    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }
    final summaries = sessions
        .map((s) => SessionSummary.fromSession(s, bySession[s.sessionId] ?? const []))
        .toList();

    final out = <ExportFile>[];
    final stamp = _fileStamp(DateTime.now());
    if (includeCsv) {
      out.add(ExportFile(
        filename: 'meds_all_readings_$stamp.csv',
        mimeType: 'text/csv',
        bytes: _utf8(_fullCsv(readings)),
      ));
    }
    if (includePdf) {
      out.add(ExportFile(
        filename: 'meds_data_report_$stamp.pdf',
        mimeType: 'application/pdf',
        bytes: await _fullPdf(profile, summaries, readings),
      ));
    }
    return out;
  }

  /// Like [loadFullExport] but limited to the given [sessionIds] — powers the
  /// History screen's multi-select bulk export.
  Future<List<ExportFile>> loadSelectedExport({
    required Set<String> sessionIds,
    bool includeCsv = true,
    bool includePdf = true,
  }) async {
    if (sessionIds.isEmpty) {
      throw StateError('No sessions selected.');
    }
    final profile = await _auth.loadProfile();
    final uid = _svc.currentUserId;
    if (uid == null) {
      throw StateError('You must be signed in to export your data.');
    }

    final allSessions = await _svc.fetchSessions(limit: 500);
    final sessions =
        allSessions.where((s) => sessionIds.contains(s.sessionId)).toList();
    final allReadings = await _svc.fetchReadingsForUser(uid, limit: 20000);
    final readings = allReadings
        .where((r) => r.sessionId != null && sessionIds.contains(r.sessionId))
        .toList();

    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      (bySession[r.sessionId!] ??= []).add(r);
    }
    final summaries = sessions
        .map((s) => SessionSummary.fromSession(s, bySession[s.sessionId] ?? const []))
        .toList();

    final out = <ExportFile>[];
    final stamp = _fileStamp(DateTime.now());
    if (includeCsv) {
      out.add(ExportFile(
        filename: 'meds_selected_readings_$stamp.csv',
        mimeType: 'text/csv',
        bytes: _utf8(_fullCsv(readings)),
      ));
    }
    if (includePdf) {
      out.add(ExportFile(
        filename: 'meds_selected_report_$stamp.pdf',
        mimeType: 'application/pdf',
        bytes: await _fullPdf(profile, summaries, readings,
            title: 'MEDS — Selected Sessions'),
      ));
    }
    return out;
  }

  String _fullCsv(List<EmotionReading> readings) {
    final buf = StringBuffer()
      ..writeln(_csvRow([
        'Session ID',
        'Timestamp',
        'Emotion',
        'Confidence %',
        'HR (bpm)',
        'SpO2 %',
        'Sensor quality',
      ]));
    for (final r in readings) {
      buf.writeln(_csvRow([
        r.sessionId ?? '',
        _fmtStamp.format(r.createdAt.toLocal()),
        r.emotion,
        r.confidence.toStringAsFixed(1),
        '${r.hr}',
        '${r.spo2}',
        r.sensorQuality,
      ]));
    }
    return buf.toString();
  }

  Future<Uint8List> _fullPdf(
    UserProfile profile,
    List<SessionSummary> sessions,
    List<EmotionReading> readings, {
    String title = 'My MEDS Data Report',
  }) async {
    final totalReadings = readings.length;
    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final topEmotion = counts.entries.isEmpty
        ? '—'
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final validHr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final avgHr = validHr.isEmpty
        ? '—'
        : '${(validHr.reduce((a, b) => a + b) / validHr.length).round()} bpm';

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        _header(title, 'Generated ${_fmtStamp.format(DateTime.now())}'),
        pw.SizedBox(height: 14),
        _kvBlock({
          'Name': profile.displayLabel,
          if (profile.email != null) 'Email': profile.email!,
          'Sessions': '${sessions.length}',
          'Total readings': '$totalReadings',
          'Most frequent emotion': topEmotion,
          'Average heart rate': avgHr,
        }),
        pw.SizedBox(height: 16),
        _sectionTitle('Sessions (${sessions.length})'),
        _table(
          ['Date', 'Duration', 'Dominant', 'Avg HR', 'State', 'Status'],
          [
            for (final s in sessions)
              [
                _fmtDate.format(s.startTime.toLocal()),
                '${s.duration.inMinutes}m ${s.duration.inSeconds.remainder(60)}s',
                s.dominantEmotion,
                s.averageBpm > 0 ? '${s.averageBpm}' : '—',
                s.finalState,
                s.status,
              ],
          ],
        ),
        pw.SizedBox(height: 8),
        _paragraph(
          'This report is generated by MEDS for personal wellness '
          'self-awareness only. It is not a medical diagnosis. The attached '
          'CSV contains every individual reading.',
        ),
      ],
      footer: _footer,
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Shared PDF widgets
  // ---------------------------------------------------------------------------

  pw.Widget _header(String title, String subtitle) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: const pw.BoxDecoration(color: _band),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Container(
              width: 10,
              height: 10,
              decoration: const pw.BoxDecoration(color: _brand, shape: pw.BoxShape.circle),
            ),
            pw.SizedBox(width: 6),
            pw.Text('MEDS',
                style: pw.TextStyle(
                    color: _brand, fontWeight: pw.FontWeight.bold, fontSize: 14)),
          ]),
          pw.SizedBox(height: 6),
          pw.Text(title,
              style: pw.TextStyle(
                  color: _ink, fontWeight: pw.FontWeight.bold, fontSize: 20)),
          pw.Text(subtitle, style: const pw.TextStyle(color: _muted, fontSize: 9)),
        ]),
      );

  pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t,
            style: pw.TextStyle(
                color: _brand, fontWeight: pw.FontWeight.bold, fontSize: 13)),
      );

  pw.Widget _kvBlock(Map<String, String> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final e in rows.entries)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(
                  width: 150,
                  child: pw.Text(e.key,
                      style: const pw.TextStyle(color: _muted, fontSize: 10)),
                ),
                pw.Expanded(
                  child: pw.Text(e.value,
                      style: const pw.TextStyle(color: _ink, fontSize: 10)),
                ),
              ]),
            ),
        ],
      );

  pw.Widget _paragraph(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(text, style: const pw.TextStyle(color: _ink, fontSize: 10)),
      );

  pw.Widget _table(List<String> headers, List<List<String>> rows) {
    if (rows.isEmpty) {
      return _paragraph('No data.');
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
          color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: _brand),
      cellStyle: const pw.TextStyle(color: _ink, fontSize: 9),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );
  }

  pw.Widget _footer(pw.Context ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('MEDS  ·  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(color: _muted, fontSize: 8)),
      );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _csvRow(List<String> cells) => cells.map(_csvCell).join(',');

  static String _csvCell(String v) {
    final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  // BOM prefix so Excel opens the file with correct accents.
  static Uint8List _utf8(String s) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(s)]);

  static String _fileStamp(DateTime t) =>
      DateFormat('yyyyMMdd_HHmmss').format(t.toLocal());
}
