/// Builders + parser for in-app deep links carried in notification payloads.
/// Pure Dart (no Flutter) so it stays unit-testable.
///
/// Formats:
///   meds://session/<sessionId>          → Session Details
///   meds://session/<sessionId>?tab=ai   → Session Details, AI Summary section
///   meds://trends                       → Trends / Analytics
class DeepLinks {
  static const scheme = 'meds';

  static String session(String sessionId) => 'meds://session/$sessionId';
  static String sessionAi(String sessionId) =>
      'meds://session/$sessionId?tab=ai';
  static const String trends = 'meds://trends';

  /// Parses a deep link into a [DeepLinkTarget], or null if unrecognised.
  static DeepLinkTarget? parse(String? link) {
    if (link == null || link.isEmpty) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != scheme) return null;

    if (uri.host == 'trends') {
      return const DeepLinkTarget(kind: DeepLinkKind.trends);
    }
    if (uri.host == 'session' && uri.pathSegments.isNotEmpty) {
      return DeepLinkTarget(
        kind: DeepLinkKind.sessionDetail,
        sessionId: uri.pathSegments.first,
        showAi: uri.queryParameters['tab'] == 'ai',
      );
    }
    return null;
  }
}

enum DeepLinkKind { sessionDetail, trends }

class DeepLinkTarget {
  final DeepLinkKind kind;
  final String? sessionId;
  final bool showAi;

  const DeepLinkTarget({
    required this.kind,
    this.sessionId,
    this.showAi = false,
  });
}
