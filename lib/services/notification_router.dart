import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/emotion_analytics_screen.dart';
import '../screens/session_details_page.dart';
import 'deep_links.dart';

/// Global navigator key so notification taps (which originate outside the
/// widget tree) can push routes. Attached to [MaterialApp] in main.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Routes a tapped notification's [deepLink] to the right screen.
///
/// Safe to call from a notification callback in any app state: it no-ops if the
/// navigator isn't mounted yet (e.g. launched-from-terminated before the first
/// frame — main retries once the tree is ready).
Future<void> handleDeepLink(String? deepLink) async {
  final target = DeepLinks.parse(deepLink);
  if (target == null) return;
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;

  switch (target.kind) {
    case DeepLinkKind.sessionDetail:
      if (target.sessionId == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => SessionDetailsPage(
          sessionId: target.sessionId!,
          scrollToAi: target.showAi,
        ),
      ));
      break;
    case DeepLinkKind.trends:
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => EmotionAnalyticsScreen(
          userId: userId,
          title: 'My analytics',
          subtitle: 'Your emotion & heart-rate trends',
        ),
      ));
      break;
  }
}
