import 'package:flutter/material.dart';

import '../../widgets/admin/admin_bottom_navigation.dart';
import 'admin_dashboard_screen.dart';
import 'admin_insights_screen.dart';
import 'admin_sessions_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_users_screen.dart';

/// The admin app shell: a 5-tab bottom navigation hosting the dashboard and the
/// existing admin screens. Uses an [IndexedStack] so each tab keeps its state
/// and the selected tab is preserved while navigating between them.
///
/// Tabs: 0 Dashboard · 1 Sessions · 2 Insights · 3 Users · 4 Settings.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          AdminDashboardScreen(onOpenTab: _select),
          AdminSessionsScreen(onOpenTab: _select),
          AdminInsightsScreen(onOpenTab: _select),
          AdminUsersScreen(onOpenTab: _select),
          AdminSettingsScreen(onOpenTab: _select),
        ],
      ),
      bottomNavigationBar:
          AdminBottomNavigation(index: _index, onSelect: _select),
    );
  }
}
