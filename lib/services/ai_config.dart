/// Configuration for the AI wellness features (session summaries, insights,
/// admin AI reports).
///
/// There is NO API key in the app. The app calls the Supabase Edge Function
/// [functionName], which holds the Claude API key as a server-side secret
/// (`ANTHROPIC_API_KEY`) and calls Claude. See AI_SETUP.md to deploy it.
class AiConfig {
  /// Supabase Edge Function that proxies AI requests to Claude.
  static const functionName = 'ai-proxy';
}
