import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_settings_screen.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';
import 'package:meds_flutter_no_python/widgets/admin/setting_row.dart';

UserProfile _admin() => const UserProfile(
    id: 'a', name: 'Admin User', email: 'admin@example.com', role: 'admin');

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders all setting sections and rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
        AdminSettingsScreen(profileLoader: () async => _admin())));
    await tester.pumpAndSettle();

    expect(find.text('Admin Settings'), findsOneWidget);
    for (final s in ['Account', 'System', 'Security', 'System Health']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Profile Information'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget); // 2FA badge default
    expect(find.text('System Status'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.byType(SettingRow), findsNWidgets(13)); // 12 rows + logout
  });

  testWidgets('shows a loader while the profile loads', (tester) async {
    final gate = Completer<UserProfile?>();
    await tester.pumpWidget(
        _wrap(AdminSettingsScreen(profileLoader: () => gate.future)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(_admin());
    await tester.pumpAndSettle();
    expect(find.text('Profile Information'), findsOneWidget);
  });

  testWidgets('error state shows Try Again', (tester) async {
    await tester.pumpWidget(_wrap(AdminSettingsScreen(
        profileLoader: () async => throw Exception('boom'))));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load settings'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('log out asks for confirmation and signs out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var signedOut = false;
    await tester.pumpWidget(_wrap(AdminSettingsScreen(
      profileLoader: () async => _admin(),
      onSignOut: () async => signedOut = true,
    )));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Log out of Admin Panel?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Log Out'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  testWidgets('cancelling log out does not sign out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var signedOut = false;
    await tester.pumpWidget(_wrap(AdminSettingsScreen(
      profileLoader: () async => _admin(),
      onSignOut: () async => signedOut = true,
    )));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(signedOut, isFalse);
  });

  testWidgets('does not overflow on a small screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
        AdminSettingsScreen(profileLoader: () async => _admin())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
