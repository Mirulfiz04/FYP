import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data_export_service.dart';

/// Opens the OS share sheet with the export files attached. Works fully
/// offline — the user can drop the files into Gmail, WhatsApp, Drive, etc.
/// The fallback when the backend email send isn't available (no internet /
/// function not deployed).
class FileShareService {
  Future<ShareResult> share(
    List<ExportFile> files, {
    String? subject,
    String? text,
  }) async {
    final dir = await getTemporaryDirectory();
    final xfiles = <XFile>[];
    for (final f in files) {
      final path = '${dir.path}/${f.filename}';
      await File(path).writeAsBytes(f.bytes, flush: true);
      xfiles.add(XFile(path, mimeType: f.mimeType, name: f.filename));
    }
    return Share.shareXFiles(xfiles, subject: subject, text: text);
  }
}
