import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/admin_user_detail.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_users_screen.dart';
import 'package:meds_flutter_no_python/services/admin_service.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';

UserProfile _u(
  String id,
  String name, {
  String role = 'user',
  String status = 'active',
  DateTime? joined,
}) =>
    UserProfile(
      id: id,
      name: name,
      email: '$id@example.com',
      role: role,
      status: status,
      createdAt: joined ?? DateTime(2026, 3, 1),
    );

List<UserProfile> _sample() => [
      _u('a', 'Amirul Hakim', role: 'admin', status: 'active'),
      _u('b', 'Nur Aisyah', role: 'operator', status: 'active'),
      _u('c', 'Hakimi Daniel', role: 'operator', status: 'active'),
      _u('d', 'Siti Nurhaliza', role: 'viewer', status: 'active'),
      _u('e', 'Muhammad Ikmal', role: 'viewer', status: 'inactive'),
      _u('f', 'Aminah Zahra', role: 'viewer', status: 'blocked'),
    ];

class FakeUsersSource implements AdminUsersSource {
  List<UserProfile> users;
  final bool throwOnFetch;
  final List<String> roleCalls = [];
  final List<String> statusCalls = [];
  final List<String> deleteCalls = [];

  FakeUsersSource(this.users, {this.throwOnFetch = false});

  @override
  Future<List<UserProfile>> fetchAllUsers() async {
    if (throwOnFetch) throw Exception('boom');
    return users;
  }

  @override
  Future<void> setUserRole(String userId, String role) async =>
      roleCalls.add('$userId:$role');

  @override
  Future<void> setUserStatus(String userId, String status) async =>
      statusCalls.add('$userId:$status');

  @override
  Future<void> updateUser(String userId,
      {String? name, String? role, String? status}) async {}

  @override
  Future<void> deleteUser(String userId) async => deleteCalls.add(userId);
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  group('UserDetailStats.build', () {
    test('aggregates sessions and readings', () {
      final sessions = [
        DetectionSession(
            sessionId: 's1',
            userId: 'u',
            startTime: DateTime(2026, 6, 20, 10),
            endTime: DateTime(2026, 6, 20, 10, 5),
            status: 'completed'),
        DetectionSession(
            sessionId: 's2',
            userId: 'u',
            startTime: DateTime(2026, 6, 19, 10),
            status: 'cancelled'),
      ];
      final readings = [
        EmotionReading(
            id: 1,
            createdAt: DateTime(2026, 6, 20, 10),
            emotion: 'Happy',
            confidence: 90,
            hr: 80,
            spo2: 98,
            sensorQuality: 'GOOD'),
        EmotionReading(
            id: 2,
            createdAt: DateTime(2026, 6, 20, 10, 1),
            emotion: 'Happy',
            confidence: 90,
            hr: 100,
            spo2: 98,
            sensorQuality: 'GOOD'),
      ];
      final s = UserDetailStats.build(sessions: sessions, readings: readings);
      expect(s.totalSessions, 2);
      expect(s.completedSessions, 1);
      expect(s.avgBpm, 90);
      expect(s.dominantEmotion, 'Happy');
      expect(s.recentSessions.first.sessionId, 's1'); // newest first
    });

    test('empty input is safe', () {
      const s = UserDetailStats.empty;
      final built = UserDetailStats.build(sessions: [], readings: []);
      expect(built.hasData, isFalse);
      expect(built.avgBpm, s.avgBpm);
      expect(built.dominantEmotion, '—');
    });
  });

  group('AdminUsersScreen widget', () {
    testWidgets('renders users and stat counts', (tester) async {
      final source = FakeUsersSource(_sample());
      await tester.pumpWidget(
          _wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('Manage Users'), findsOneWidget);
      expect(find.text('Amirul Hakim'), findsOneWidget);
      expect(find.text('Total Users'), findsOneWidget);
      // 6 total, 4 active, 1 inactive, 1 blocked.
      expect(find.text('All Users (6)'), findsOneWidget);
      expect(find.text('Active (4)'), findsOneWidget);
      expect(find.text('Blocked (1)'), findsOneWidget);
    });

    testWidgets('tab filter narrows the list', (tester) async {
      final source = FakeUsersSource(_sample());
      await tester.pumpWidget(_wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Blocked (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Aminah Zahra'), findsOneWidget); // blocked user
      expect(find.text('Amirul Hakim'), findsNothing); // active user hidden
      expect(find.text('Showing 1 to 1 of 1 users'), findsOneWidget);
    });

    testWidgets('search filters by name', (tester) async {
      final source = FakeUsersSource(_sample());
      await tester.pumpWidget(_wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'aisyah');
      await tester.pumpAndSettle();

      expect(find.text('Nur Aisyah'), findsOneWidget);
      expect(find.text('Amirul Hakim'), findsNothing);
    });

    testWidgets('error state shows Try Again and retries', (tester) async {
      final source = FakeUsersSource([], throwOnFetch: true);
      await tester.pumpWidget(_wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load users'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('block action shows a confirmation dialog', (tester) async {
      final source = FakeUsersSource(_sample());
      await tester.pumpWidget(_wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      // Open the action menu for the first (admin) user via its menu button.
      await tester.tap(find.byTooltip('Actions').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Block User'));
      await tester.tap(find.text('Block User'));
      await tester.pumpAndSettle();

      expect(find.text('Block this user?'), findsOneWidget);
      await tester.tap(find.text('Block User').last); // confirm
      await tester.pumpAndSettle();

      expect(source.statusCalls, contains('a:blocked'));
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = FakeUsersSource(_sample());
      await tester.pumpWidget(_wrap(AdminUsersScreen(source: source)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
