/// Configuration for the AI (Google Gemini) wellness features.
///
/// ============================================================================
///  WHERE TO PUT YOUR API KEY
/// ============================================================================
///  You have a Google AI (Gemini) API key. Get one at:
///      https://aistudio.google.com/apikey
///  Provide it in ONE of these two ways:
///
///  Option A — simplest (paste it here):
///      static const _pastedKey = 'AIza...';
///      WARNING: do NOT commit your real key to a public repo / GitHub.
///
///  Option B — build flag (keeps the key out of the source code):
///      Leave _pastedKey as '' and pass the key when you run / build:
///         flutter run --dart-define=AI_API_KEY=AIza...
///         flutter build apk --dart-define=AI_API_KEY=AIza...
///
///  If both are set, Option A (the pasted key) wins.
/// ============================================================================
class AiConfig {
  // ---- Option A: paste your key between the quotes (or leave empty) ----------
  static const _pastedKey =
      '';

  // ---- Option B: supplied at run/build time via --dart-define=AI_API_KEY=... -
  static const _envKey = String.fromEnvironment('AI_API_KEY');

  /// The active API key.
  static String get apiKey => _pastedKey.isNotEmpty ? _pastedKey : _envKey;

  /// Whether a key has been configured.
  static bool get hasKey => apiKey.isNotEmpty;

  /// Gemini model to use.
  ///   'gemini-2.5-flash' -> fast & cheap, great for short summaries (default)
  ///   'gemini-2.5-pro'   -> highest quality, slower & pricier
  static const model = 'gemini-2.5-flash';

  /// Gemini REST base. The model + ':generateContent' is appended at call time:
  ///   https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent
  static const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
}
