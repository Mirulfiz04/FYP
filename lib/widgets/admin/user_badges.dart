import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Normalised account status — defaults to active when the column is empty.
String normalizedStatus(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'active';
  return s;
}

/// Normalised role — defaults to "user" when the column is empty.
String normalizedRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  if (r.isEmpty) return 'user';
  return r;
}

Color statusColor(String? status) => switch (normalizedStatus(status)) {
      'active' => MedsColors.greenDark,
      'inactive' => MedsColors.amber,
      'blocked' => MedsColors.red,
      'pending' => MedsColors.muted,
      _ => MedsColors.muted,
    };

String statusLabel(String? status) {
  final s = normalizedStatus(status);
  return s[0].toUpperCase() + s.substring(1);
}

Color roleColor(String? role) => switch (normalizedRole(role)) {
      'admin' || 'administrator' => MedsColors.purple,
      'operator' || 'researcher' => MedsColors.teal,
      'viewer' || 'user' => MedsColors.blue,
      _ => MedsColors.blue,
    };

String roleLabel(String? role) {
  final r = normalizedRole(role);
  if (r == 'administrator') return 'Admin';
  return r[0].toUpperCase() + r.substring(1);
}

/// A small tinted pill used for role / status badges on user cards.
class TintBadge extends StatelessWidget {
  final String text;
  final Color color;

  const TintBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

class RoleBadge extends StatelessWidget {
  final String? role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) =>
      TintBadge(text: roleLabel(role), color: roleColor(role));
}

class StatusBadge extends StatelessWidget {
  final String? status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) =>
      TintBadge(text: statusLabel(status), color: statusColor(status));
}
