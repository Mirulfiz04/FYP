import 'package:flutter/material.dart';

/// Accent + muted colours for the bottom navigation (matches the dashboard).
const Color medsNavAccent = Color(0xFF6A5AE0);
const Color medsNavMuted = Color(0xFF9AA3B2);

/// The app's 5-slot bottom bar with a notched centre for the docked Live FAB.
/// Page indices: 0 Home · 1 History · 2 Insights · 3 Profile. The centre slot
/// is the "Live" label under the floating action button (supplied by the host
/// Scaffold), not a selectable destination.
class MedsBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const MedsBottomBar({super.key, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircularNotchedRectangle(),
      notchMargin: 7,
      height: 66,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _item(0, Icons.home_outlined, Icons.home, 'Home'),
          _item(1, Icons.history_outlined, Icons.history, 'History'),
          const Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Live',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: medsNavAccent)),
              ),
            ),
          ),
          _item(2, Icons.insights_outlined, Icons.insights, 'Insights'),
          _item(3, Icons.person_outline, Icons.person, 'Profile'),
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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 23),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
