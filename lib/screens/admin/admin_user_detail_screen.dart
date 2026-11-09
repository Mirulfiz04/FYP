import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_user_detail.dart';
import '../../models/detection_session.dart';
import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/user_badges.dart';
import '../../widgets/ui_kit.dart';
import '../emotion_analytics_screen.dart';

/// Read-only profile + activity summary for one user. Never shows passwords or
/// raw authentication data — only profile fields and aggregated session stats.
class AdminUserDetailScreen extends StatefulWidget {
  final UserProfile user;

  const AdminUserDetailScreen({super.key, required this.user});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final _admin = AdminService();

  UserDetailStats? _stats;
  bool _loading = true;
  Object? _error;

  UserProfile get _u => widget.user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await _admin.fetchSessionsForUser(_u.id);
      final readings = await _admin.fetchReadingsForUser(_u.id);
      if (!mounted) return;
      setState(() => _stats =
          UserDetailStats.build(sessions: sessions, readings: readings));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Details'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        color: MedsColors.purple,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _profileCard(),
            const SizedBox(height: 16),
            if (_error != null && _stats == null)
              _error_()
            else if (_loading && _stats == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child:
                        CircularProgressIndicator(color: MedsColors.purple)),
              )
            else ...[
              _statsGrid(_stats ?? UserDetailStats.empty),
              const SizedBox(height: 16),
              _recentSessions(_stats ?? UserDetailStats.empty),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EmotionAnalyticsScreen(
                    userId: _u.id,
                    title: _u.displayLabel,
                    subtitle: _u.email,
                    avatarUrl: _u.avatarUrl,
                  ),
                )),
                icon: const Icon(Icons.insights_outlined),
                label: const Text('View full emotion analytics'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    final hasPhoto = _u.avatarUrl != null && _u.avatarUrl!.isNotEmpty;
    final accent = roleColor(_u.role);
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: accent.withValues(alpha: 0.15),
                backgroundImage: hasPhoto ? NetworkImage(_u.avatarUrl!) : null,
                child: hasPhoto
                    ? null
                    : Text(_u.initials,
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_u.displayLabel,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(_u.email ?? '—',
                        style: const TextStyle(
                            color: MedsColors.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        RoleBadge(role: _u.role),
                        StatusBadge(status: _u.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 6),
          _infoRow('Joined',
              _u.createdAt != null
                  ? DateFormat('d MMM yyyy').format(_u.createdAt!.toLocal())
                  : '—'),
          _infoRow('Gender', _u.gender ?? '—'),
          _infoRow('Age group', _u.ageGroup ?? (_u.age?.toString() ?? '—')),
          _infoRow('Category', _u.userCategory ?? '—'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(color: MedsColors.muted, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(UserDetailStats s) {
    final items = [
      ('Completed sessions', '${s.completedSessions}', Icons.event_available_outlined, MedsColors.blue),
      ('Total sessions', '${s.totalSessions}', Icons.event_note_outlined, MedsColors.purple),
      ('Average heart rate', s.avgBpm == 0 ? '—' : '${s.avgBpm} BPM', Icons.favorite_outline, MedsColors.coral),
      ('Most frequent emotion', s.dominantEmotion, Icons.sentiment_satisfied_alt_outlined, MedsColors.greenDark),
      ('Last active', s.lastActive == null ? '—' : DateFormat('d MMM, h:mm a').format(s.lastActive!), Icons.schedule, MedsColors.amber),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
            title: 'Activity', icon: Icons.analytics_outlined, color: MedsColors.purple),
        ...items.map((it) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: it.$4.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(it.$3, color: it.$4, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(it.$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ),
                    Text(it.$2,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _recentSessions(UserDetailStats s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
            title: 'Recent sessions',
            icon: Icons.history,
            color: MedsColors.blue),
        if (s.recentSessions.isEmpty)
          const AppCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No sessions recorded for this user yet.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            ),
          )
        else
          ...s.recentSessions.map(_sessionRow),
      ],
    );
  }

  Widget _sessionRow(DetectionSession s) {
    final color = switch (s.status) {
      'completed' => MedsColors.blue,
      'active' => MedsColors.greenDark,
      'cancelled' => MedsColors.red,
      _ => MedsColors.muted,
    };
    final dur = s.endTime == null
        ? 'In progress'
        : '${s.duration.inMinutes}m ${s.duration.inSeconds.remainder(60)}s';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.monitor_heart_outlined, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      DateFormat('d MMM yyyy • h:mm a')
                          .format(s.startTime.toLocal()),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Duration $dur',
                      style: const TextStyle(
                          color: MedsColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Pill(text: s.status, color: color),
          ],
        ),
      ),
    );
  }

  Widget _error_() {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        color: MedsColors.red,
        title: 'Could not load activity',
        message: 'Failed to load this user\'s sessions.',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ),
    );
  }
}
