import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/data_export_service.dart';
import '../services/email_export_service.dart';
import '../services/export_history_service.dart';
import '../services/file_share_service.dart';
import '../theme/app_theme.dart';

/// Builds the files to attach, honouring the user's format choice.
typedef ExportBuilder = Future<List<ExportFile>> Function({
  required bool includeCsv,
  required bool includePdf,
});

/// Opens the "Send to email" sheet. Returns `true` if data was sent or shared.
Future<bool> showEmailExportSheet(
  BuildContext context, {
  required String title,
  required String subject,
  required ExportBuilder builder,
  String? myEmail,
  String historyScope = 'all', // 'session' | 'all'
  String? historySessionId,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EmailExportSheet(
      title: title,
      subject: subject,
      builder: builder,
      myEmail: myEmail,
      historyScope: historyScope,
      historySessionId: historySessionId,
    ),
  );
  return sent ?? false;
}

class _EmailExportSheet extends StatefulWidget {
  final String title;
  final String subject;
  final ExportBuilder builder;
  final String? myEmail;
  final String historyScope;
  final String? historySessionId;

  const _EmailExportSheet({
    required this.title,
    required this.subject,
    required this.builder,
    required this.historyScope,
    this.myEmail,
    this.historySessionId,
  });

  @override
  State<_EmailExportSheet> createState() => _EmailExportSheetState();
}

class _EmailExportSheetState extends State<_EmailExportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  bool _includePdf = true;
  bool _includeCsv = true;
  bool _sending = false;
  String? _statusText;
  String? _error;

  static final _emailRe =
      RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$', caseSensitive: false);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  List<String> get _formats =>
      [if (_includePdf) 'PDF', if (_includeCsv) 'CSV'];

  Future<void> _record(String method, String recipient) =>
      ExportHistoryService().record(ExportRecord(
        scope: widget.historyScope,
        sessionId: widget.historySessionId,
        method: method,
        recipient: recipient,
        formats: _formats,
        sentAt: DateTime.now(),
      ));

  Future<void> _send() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_includePdf && !_includeCsv) {
      setState(() => _error = 'Choose at least one format (PDF or CSV).');
      return;
    }
    FocusScope.of(context).unfocus();
    final recipient = _emailCtrl.text.trim();
    setState(() {
      _sending = true;
      _statusText = 'Preparing your files…';
    });
    try {
      final files = await widget.builder(
        includeCsv: _includeCsv,
        includePdf: _includePdf,
      );
      if (!mounted) return;
      setState(() => _statusText = 'Sending to $recipient…');
      await EmailExportService().send(
        toEmail: recipient,
        subject: widget.subject,
        message: _messageCtrl.text.trim(),
        files: files,
      );
      await _record('email', recipient);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Data sent to $recipient'),
        backgroundColor: MedsColors.greenDark,
      ));
    } on EmailExportException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _statusText = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _statusText = null;
        _error = 'Something went wrong: $e';
      });
    }
  }

  /// Offline fallback: build the files and hand them to the OS share sheet.
  /// No recipient/internet needed.
  Future<void> _shareAsFile() async {
    setState(() => _error = null);
    if (!_includePdf && !_includeCsv) {
      setState(() => _error = 'Choose at least one format (PDF or CSV).');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _statusText = 'Preparing your files…';
    });
    try {
      final files = await widget.builder(
        includeCsv: _includeCsv,
        includePdf: _includePdf,
      );
      final result = await FileShareService().share(
        files,
        subject: widget.subject,
        text: _messageCtrl.text.trim().isEmpty ? null : _messageCtrl.text.trim(),
      );
      if (result.status == ShareResultStatus.dismissed) {
        // User backed out of the share sheet — leave the sheet open.
        if (!mounted) return;
        setState(() {
          _sending = false;
          _statusText = null;
        });
        return;
      }
      await _record('file', 'Shared as file');
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Files ready to share'),
        backgroundColor: MedsColors.greenDark,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _statusText = null;
        _error = 'Could not share the files: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: MedsColors.muted.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  const Icon(Icons.mark_email_read_outlined,
                      color: MedsColors.greenDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Enter any email address. The data is sent from the MEDS '
                  'server as a PDF report and/or a CSV spreadsheet.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  enabled: !_sending,
                  decoration: const InputDecoration(
                    labelText: 'Recipient email',
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Enter an email address';
                    if (!_emailRe.hasMatch(s)) return 'Enter a valid email address';
                    return null;
                  },
                ),
                if (widget.myEmail != null && widget.myEmail!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text('Send to me (${widget.myEmail})'),
                      onPressed: _sending
                          ? null
                          : () => setState(() => _emailCtrl.text = widget.myEmail!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _messageCtrl,
                  enabled: !_sending,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Message (optional)',
                    hintText: 'Add a short note for the recipient',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                _FormatToggle(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF report',
                  subtitle: 'Formatted, easy to read',
                  value: _includePdf,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _includePdf = v),
                ),
                _FormatToggle(
                  icon: Icons.table_chart_outlined,
                  label: 'CSV spreadsheet',
                  subtitle: 'Raw rows for Excel / Sheets',
                  value: _includeCsv,
                  onChanged: _sending
                      ? null
                      : (v) => setState(() => _includeCsv = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MedsColors.red.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: MedsColors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: MedsColors.red)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: MedsColors.greenDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_sending
                        ? (_statusText ?? 'Sending…')
                        : 'Send email'),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or',
                        style: TextStyle(
                            color: MedsColors.muted.withValues(alpha: .8),
                            fontSize: 12)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _shareAsFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MedsColors.blue,
                      side: const BorderSide(color: MedsColors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('Share as file (works offline)'),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _FormatToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      activeThumbColor: MedsColors.greenDark,
      secondary: Icon(icon, color: MedsColors.greenDark),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: MedsColors.muted, fontSize: 12)),
    );
  }
}
