import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/connected_devices_screen.dart';
import 'package:meds_flutter_no_python/screens/edit_profile_screen.dart';
import 'package:meds_flutter_no_python/screens/notification_settings_screen.dart';
import 'package:meds_flutter_no_python/screens/privacy_security_screen.dart';
import 'package:meds_flutter_no_python/screens/profile_screen.dart';
import 'package:meds_flutter_no_python/services/profile_repository.dart';
import 'package:meds_flutter_no_python/viewmodels/profile_view_model.dart';
import 'package:meds_flutter_no_python/widgets/meds_bottom_bar.dart';
import 'package:meds_flutter_no_python/widgets/profile_header_card.dart';

/// Gives a test a tall surface so a whole screen renders without scrolling
/// (ListView only builds visible children otherwise).
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('1. user information loads correctly', () async {
    final vm = ProfileViewModel(repository: SampleProfileRepository());
    await vm.load();
    expect(vm.profile?.name, 'Amirul Hakim');
    expect(vm.profile?.email, 'amirulhakim@email.com');
  });

  testWidgets('2. default avatar (initials) appears when no image', (tester) async {
    const p = UserProfile(id: 'u', name: 'Amirul Hakim', email: 'a@b.com');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileHeaderCard(profile: p, onEdit: () {})),
    ));
    expect(find.text('AH'), findsOneWidget);
  });

  testWidgets('3. Edit Profile opens correctly', (tester) async {
    _tall(tester);
    final vm = ProfileViewModel(repository: SampleProfileRepository());
    await vm.load();
    await tester.pumpWidget(MaterialApp(home: EditProfileScreen(vm: vm)));
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Full name'), findsWidgets);
  });

  test('4. updated information appears after saving', () async {
    final vm = ProfileViewModel(repository: SampleProfileRepository());
    await vm.load();
    final ok = await vm.save(vm.profile!.copyWith(name: 'New Name'));
    expect(ok, isTrue);
    expect(vm.profile?.name, 'New Name');
  });

  test('5. invalid email is rejected', () {
    expect(ProfileViewModel.emailIsValid('not-an-email'), isFalse);
    expect(ProfileViewModel.emailIsValid('user@domain.com'), isTrue);
  });

  testWidgets('6. Notification Preferences opens correctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationSettingsScreen()));
    expect(find.text('Sensor & Camera alerts'), findsOneWidget);
  });

  testWidgets('7. Connected Devices opens correctly', (tester) async {
    _tall(tester);
    await tester.pumpWidget(const MaterialApp(home: ConnectedDevicesScreen()));
    await tester.pump();
    expect(find.text('Connect Device'), findsOneWidget);
  });

  testWidgets('8. Privacy & Security opens correctly', (tester) async {
    _tall(tester);
    await tester.pumpWidget(const MaterialApp(home: PrivacySecurityScreen()));
    await tester.pump();
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('9. Log-out confirmation appears', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        repository: SampleProfileRepository(),
        onSignOut: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    final btn = find.widgetWithText(FilledButton, 'Log Out');
    await tester.dragUntilVisible(
        btn, find.byType(ListView), const Offset(0, -300));
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);
  });

  testWidgets('10. confirming logout clears the session', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        repository: SampleProfileRepository(),
        onSignOut: () async => signedOut = true,
      ),
    ));
    await tester.pumpAndSettle();
    final btn = find.widgetWithText(FilledButton, 'Log Out');
    await tester.dragUntilVisible(
        btn, find.byType(ListView), const Offset(0, -300));
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Log Out')));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  testWidgets('11. logout delegates to AuthGate (no self-navigation)',
      (tester) async {
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        repository: SampleProfileRepository(),
        onSignOut: () async => signedOut = true,
      ),
    ));
    await tester.pumpAndSettle();
    final btn = find.widgetWithText(FilledButton, 'Log Out');
    await tester.dragUntilVisible(
        btn, find.byType(ListView), const Offset(0, -300));
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Log Out')));
    await tester.pumpAndSettle();
    // The session was cleared and the screen did NOT push its own route —
    // AuthGate swaps in Login and drops the protected stack.
    expect(signedOut, isTrue);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('12. Profile tab is highlighted in bottom navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MedsBottomBar(index: 3, onSelect: (_) {}),
      ),
    ));
    final profile = tester.widget<Text>(find.text('Profile'));
    final home = tester.widget<Text>(find.text('Home'));
    expect(profile.style?.color, medsNavAccent);
    expect(home.style?.color, medsNavMuted);
  });
}
