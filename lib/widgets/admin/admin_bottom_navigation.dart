import 'package:flutter/material.dart';

import '../meds_bottom_bar.dart' show medsNavAccent, medsNavMuted;

/// Admin bottom navigation: Dashboard · Sessions · Insights · Users · Settings.
/// Mirrors the user-side bottom bar styling so both shells feel consistent.
class AdminBottomNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const AdminBottomNavigation({
    super.key,
    required this.index,
    required this.onSelect,
  });

  static const _items = <(IconData, IconData, String)>[
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.monitor_heart_outlined, Icons.monitor_heart, 'Sessions'),
    (Icons.insights_outlined, Icons.insights, 'Insights'),
    (Icons.people_outline, Icons.people, 'Users'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.surface,
      height: 66,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            _item(i, _items[i].$1, _items[i].$2, _items[i].$3),
        ],
      ),
    );
  }

  Widget _item(int i, IconData icon, IconData activeIcon, String label) {
    final selected = index == i;
    final color = selected ? medsNavAccent : medsNavMuted;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(i),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
