import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../services/auth_service.dart';
import '../services/notification_prefs.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/trend_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/animated_fun.dart';
import '../widgets/notification_bell.dart';
import '../widgets/ui_kit.dart';
import 'emotion_analytics_screen.dart';
import 'session_details_page.dart';
import 'session_readiness_screen.dart';
import 'notifications_screen.dart';

/// Purple gradient used by the status hero, matching the dashboard mockup.
const LinearGradient _statusGradient = LinearGradient(
  colors: [Color(0xFF8B7CF6), Color(0xFF6A5AE0)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const Color _accent = Color(0xFF6A5AE0);

/// Emotions that count toward the stress indicator.
const _stressful = {'Angry', 'Fear', 'Sad', 'Disgust'};

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onSessionEnded;

  const HomeScreen({
    super.key,
    required this.cameras,
    required this.onOpenTab,
    required this.onSessionEnded,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _svc = SupabaseService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _name;
  String? _avatarUrl;

  // Dashboard data.
  bool _loading = true;
  EmotionReading? _latest;
  int _sessionsThisWeek = 0;
  int? _avgHr;
  String? _topEmotion;
  double? _avgStress;
  DetectionSession? _recentSession;
  String? _recentEmotion;
  int? _recentHr;
  String? _recentState;
  List<_DayPoint> _week = const [];

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadDashboard();
    _evaluateTrend();
  }

  Future<void> _loadName() async {
    try {
      final profile = await _auth.loadProfile();
      if (mounted) {
        setState(() {
          _name = profile.name?.isNotEmpty == true ? profile.name : profile.email;
          _avatarUrl = profile.avatarUrl;
        });
      }
    } catch (_) {/* greeting is non-critical */}
  }

  Future<void> _loadDashboard() async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return;
    try {
      final readings = await _svc.fetchReadingsForUser(uid, limit: 500);
      final sessions = await _svc.fetchSessions(limit: 50);
      if (!mounted) return;

      final now = DateTime.now();
      final weekStart = _mondayOf(now);

      // This-week readings (current calendar week).
      final thisWeek = readings
          .where((r) => !r.createdAt.toLocal().isBefore(weekStart))
          .toList();

      // Group readings by session for the recent-session summary.
      final bySession = <String, List<EmotionReading>>{};
      for (final r in readings) {
        final sid = r.sessionId;
        if (sid != null) (bySession[sid] ??= []).add(r);
      }

      // Per-weekday buckets (Mon..Sun) for the trend chart.
      final byDay = List.generate(7, (_) => <EmotionReading>[]);
      for (final r in thisWeek) {
        final wd = r.createdAt.toLocal().weekday; // 1=Mon..7=Sun
        byDay[wd - 1].add(r);
      }

      final recent = sessions.isNotEmpty ? sessions.first : null;
      final List<EmotionReading> recentReadings = recent != null
          ? (bySession[recent.sessionId] ?? const <EmotionReading>[])
          : const <EmotionReading>[];

      setState(() {
        _latest = readings.isNotEmpty ? readings.first : null;
        _sessionsThisWeek = sessions
            .where((s) => !s.startTime.toLocal().isBefore(weekStart))
            .length;
        _avgHr = _avgHrOf(thisWeek);
        _topEmotion = _modeEmotion(thisWeek);
        _avgStress = _stressIndex(thisWeek);
        _recentSession = recent;
        _recentEmotion = _modeEmotion(recentReadings);
        _recentHr = _avgHrOf(recentReadings);
        _recentState = recent == null
            ? null
            : _deriveState(_recentEmotion ?? 'Neutral', _recentHr ?? 0);
        _week = byDay
            .map((rs) => _DayPoint(hr: _avgHrOf(rs), stress: _stressIndex(rs)))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Weekly-trend notification (unchanged logic): notify once per week when the
  /// preference is on; otherwise the in-app trend chart speaks for itself.
  Future<void> _evaluateTrend() async {
    final uid = _auth.currentUser?.id;
    if (uid == null || !notificationPrefs.weeklyTrend) return;
    List<SessionStat> stats;
    try {
      stats = await _svc.fetchSessionStats();
    } catch (_) {
      return;
    }
    final evaluation = TrendService.evaluate(stats);
    if (!evaluation.enough) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'last_trend_notified_$uid';
    final last = DateTime.tryParse(prefs.getString(key) ?? '');
    final now = DateTime.now();
    if (TrendService.isNewWeek(now, last)) {
      await notifications.weeklyTrend(
        message: evaluation.message,
        evidence: evaluation.evidence,
        userId: uid,
      );
      await prefs.setString(key, now.toIso8601String());
    }
  }

  Future<void> _startSession() async {
    final ranSession = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SessionReadinessScreen(
          cameras: widget.cameras,
          onOpenTab: widget.onOpenTab,
        ),
      ),
    );
    if (ranSession == true) {
      widget.onSessionEnded();
      _loadDashboard();
    }
  }

  void _openMyAnalytics() {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmotionAnalyticsScreen(
          userId: userId,
          title: _name ?? 'My analytics',
          subtitle: 'Your emotion & heart-rate analytics',
        ),
      ),
    );
  }

  void _openRecentSummary() {
    final s = _recentSession;
    if (s == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => SessionDetailsPage(sessionId: s.sessionId)),
    );
  }

  // ---- Aggregation helpers ------------------------------------------------

  DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  int? _avgHrOf(List<EmotionReading> rs) {
    final hr = rs.where((r) => r.hr > 0).map((r) => r.hr).toList();
    if (hr.isEmpty) return null;
    return (hr.reduce((a, b) => a + b) / hr.length).round();
  }

  String? _modeEmotion(List<EmotionReading> rs) {
    if (rs.isEmpty) return null;
    final c = <String, int>{};
    for (final r in rs) {
      c[r.emotion] = (c[r.emotion] ?? 0) + 1;
    }
    return c.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// A 1–5 stress index from the share of stressful emotions.
  double? _stressIndex(List<EmotionReading> rs) {
    if (rs.isEmpty) return null;
    final frac = rs.where((r) => _stressful.contains(r.emotion)).length / rs.length;
    return 1 + frac * 4;
  }

  String _deriveState(String emotion, int hr) {
    final positive = emotion == 'Happy' || emotion == 'Surprise';
    final elevated = hr > 100;
    if (elevated) return positive ? 'Excited' : 'Stressed';
    if (emotion == 'Neutral') return 'Calm';
    if (positive) return 'Content';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          color: _accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _header(),
              const SizedBox(height: 18),
              FadeSlideIn(child: _StatusCard(latest: _latest, onStart: _startSession)),
              const SizedBox(height: 22),
              _SectionRow(
                title: 'Quick Overview',
                linkLabel: 'View All',
                onTap: _openMyAnalytics,
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: _OverviewGrid(
                  sessions: _sessionsThisWeek,
                  avgHr: _avgHr,
                  topEmotion: _topEmotion,
                  avgStress: _avgStress,
                ),
              ),
              const SizedBox(height: 22),
              _SectionRow(
                title: 'Recent Session',
                linkLabel: 'View History',
                onTap: () => widget.onOpenTab(1),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: _RecentSessionCard(
                  session: _recentSession,
                  emotion: _recentEmotion,
                  avgHr: _recentHr,
                  state: _recentState,
                  loading: _loading,
                  onViewSummary: _openRecentSummary,
                ),
              ),
              const SizedBox(height: 22),
              const FadeSlideIn(
                delay: Duration(milliseconds: 220),
                child: SectionHeader(
                  title: 'AI Insight',
                  icon: Icons.auto_awesome,
                  color: MedsColors.purple,
                ),
              ),
              FadeSlideIn(
                delay: const Duration(milliseconds: 260),
                child: AiInsightCard(
                  autoGenerate: true,
                  cacheKey: 'home_${_auth.currentUser?.id ?? 'anon'}',
                  fetchReadings: () async {
                    final uid = _auth.currentUser?.id;
                    if (uid == null) return <EmotionReading>[];
                    return _svc.fetchReadingsForUser(uid, limit: 200);
                  },
                ),
              ),
              const SizedBox(height: 22),
              _SectionRow(
                title: 'Weekly Trends',
                linkLabel: 'View Trends',
                onTap: _openMyAnalytics,
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 300),
                child: _WeeklyTrendsCard(week: _week),
              ),
              const SizedBox(height: 18),
              const Text(
                'MEDS is for educational and wellbeing awareness only and is not '
                'a medical diagnosis.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MedsColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.menu,
          tooltip: 'Menu',
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _name != null ? 'Hello, $_name' : 'Welcome',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const WavingHand(size: 18),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                "Good morning! Let's check your wellbeing.",
                style: TextStyle(color: MedsColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Notification bell with unread badge, in a white rounded button.
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: const NotificationBell(),
        ),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _accent.withValues(alpha: 0.15),
                    backgroundImage: (_avatarUrl ?? '').isNotEmpty
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    child: (_avatarUrl ?? '').isEmpty
                        ? const Icon(Icons.person, color: _accent)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _name ?? 'MEDS user',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _drawerItem(Icons.home_outlined, 'Home', () => Navigator.pop(context)),
            _drawerItem(Icons.event_note_outlined, 'My sessions', () {
              Navigator.pop(context);
              widget.onOpenTab(1);
            }),
            _drawerItem(Icons.insights_outlined, 'My analytics', () {
              Navigator.pop(context);
              _openMyAnalytics();
            }),
            _drawerItem(Icons.notifications_outlined, 'Notifications', () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsScreen()));
            }),
            _drawerItem(Icons.settings_outlined, 'Settings', () {
              Navigator.pop(context);
              widget.onOpenTab(3);
            }),
            const Spacer(),
            const Divider(height: 1),
            _drawerItem(Icons.logout, 'Sign out', () async {
              Navigator.pop(context);
              await _auth.signOut();
            }, color: MedsColors.red),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? _accent),
      title: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w500, fontSize: 14.5)),
      onTap: onTap,
    );
  }
}

class _DayPoint {
  final int? hr;
  final double? stress;
  const _DayPoint({this.hr, this.stress});
}

// ---- Header bits ----------------------------------------------------------

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: softShadow(context),
      ),
      child: IconButton(
        icon: Icon(icon, color: _accent),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final String title;
  final String linkLabel;
  final VoidCallback onTap;
  const _SectionRow(
      {required this.title, required this.linkLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(linkLabel,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ---- Status hero ----------------------------------------------------------

class _StatusCard extends StatelessWidget {
  final EmotionReading? latest;
  final VoidCallback onStart;
  const _StatusCard({required this.latest, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final r = latest;
    final fresh = r != null &&
        DateTime.now().difference(r.createdAt) < const Duration(minutes: 2);
    final hr = r?.hr ?? 0;
    final normal = hr >= 60 && hr <= 100;
    final emotion = r?.emotion ?? '—';
    final state = r == null
        ? '—'
        : (emotion == 'Neutral'
            ? 'Calm'
            : (emotion == 'Happy' || emotion == 'Surprise' ? 'Content' : 'Low'));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _statusGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current Status',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: fresh ? const Color(0xFF3BE08A) : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(fresh ? 'Live' : 'Latest',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _avatar(state),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _metric(
                        label: 'Emotion',
                        valueRow: Row(
                          children: [
                            _emotionDot(emotion),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                emotion,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        caption:
                            r != null ? 'Confidence ${r.confidence.round()}%' : 'No data',
                        barValue: r != null ? (r.confidence / 100).clamp(0, 1) : 0,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 64,
                      color: Colors.white.withValues(alpha: 0.22),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    Expanded(
                      child: _metric(
                        label: 'Heart Rate',
                        valueRow: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Icon(Icons.favorite,
                                color: Color(0xFFFF7A93), size: 16),
                            const SizedBox(width: 5),
                            Text(hr > 0 ? '$hr' : '--',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 3),
                            const Text('BPM',
                                style:
                                    TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                        caption: normal ? 'Normal Range' : (hr > 0 ? 'Out of range' : '—'),
                        barValue: hr > 0 ? ((hr - 40) / 80).clamp(0, 1) : 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.play_circle_fill),
              label: const Text('Start New Session',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String state) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ..._corners(),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.face_retouching_natural,
                size: 34, color: _accent),
          ),
          Positioned(
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22C58A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(state,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const len = 13.0;
    const th = 2.5;
    const white = Colors.white;
    BoxDecoration deco(bool top, bool left) => BoxDecoration(
          border: Border(
            top: top ? const BorderSide(color: white, width: th) : BorderSide.none,
            bottom:
                !top ? const BorderSide(color: white, width: th) : BorderSide.none,
            left:
                left ? const BorderSide(color: white, width: th) : BorderSide.none,
            right: !left
                ? const BorderSide(color: white, width: th)
                : BorderSide.none,
          ),
        );
    return [
      Positioned(top: 2, left: 2, child: Container(width: len, height: len, decoration: deco(true, true))),
      Positioned(top: 2, right: 2, child: Container(width: len, height: len, decoration: deco(true, false))),
      Positioned(bottom: 16, left: 2, child: Container(width: len, height: len, decoration: deco(false, true))),
      Positioned(bottom: 16, right: 2, child: Container(width: len, height: len, decoration: deco(false, false))),
    ];
  }

  Widget _emotionDot(String emotion) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(color: Color(0xFFFFC83D), shape: BoxShape.circle),
      child: Center(
        child: Text(MedsColors.emoji(emotion), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _metric({
    required String label,
    required Widget valueRow,
    required String caption,
    required num barValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        const SizedBox(height: 3),
        valueRow,
        const SizedBox(height: 8),
        Text(caption,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: barValue.toDouble(),
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.28),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ],
    );
  }
}

// ---- Quick overview -------------------------------------------------------

class _OverviewGrid extends StatelessWidget {
  final int sessions;
  final int? avgHr;
  final String? topEmotion;
  final double? avgStress;

  const _OverviewGrid({
    required this.sessions,
    required this.avgHr,
    required this.topEmotion,
    required this.avgStress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_note,
            color: MedsColors.purple,
            label: 'Sessions',
            value: '$sessions',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            icon: Icons.favorite,
            color: MedsColors.pink,
            label: 'Avg. Heart Rate',
            value: avgHr != null ? '$avgHr' : '--',
            unit: 'BPM',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            icon: Icons.mood,
            color: MedsColors.greenDark,
            label: 'Most Frequent Emotion',
            value: topEmotion ?? '--',
            small: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            icon: Icons.speed,
            color: MedsColors.amber,
            label: 'Stress Level (Avg.)',
            value: avgStress != null ? avgStress!.toStringAsFixed(1) : '--',
            unit: '/ 5',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? unit;
  final bool small;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.unit,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, height: 1.1, color: MedsColors.muted),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: small ? 14 : 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                        color: MedsColors.muted),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          const Text('This Week',
              style: TextStyle(fontSize: 10, color: MedsColors.muted)),
        ],
      ),
    );
  }
}

// ---- Recent session -------------------------------------------------------

class _RecentSessionCard extends StatelessWidget {
  final DetectionSession? session;
  final String? emotion;
  final int? avgHr;
  final String? state;
  final bool loading;
  final VoidCallback onViewSummary;

  const _RecentSessionCard({
    required this.session,
    required this.emotion,
    required this.avgHr,
    required this.state,
    required this.loading,
    required this.onViewSummary,
  });

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s == null) {
      return AppCard(
        child: loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(color: _accent),
                ),
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No sessions yet — start your first one above.',
                    style: TextStyle(color: MedsColors.muted)),
              ),
      );
    }

    final start = s.startTime.toLocal();
    final timeText = 'Today, ${DateFormat('h:mm a').format(start)}';
    final today = DateTime.now();
    final isToday = start.year == today.year &&
        start.month == today.month &&
        start.day == today.day;
    final header = isToday ? timeText : DateFormat('EEE, h:mm a').format(start);
    final sub =
        '${DateFormat('dd MMM yyyy').format(start)} · ${s.endTime != null ? _fmtDuration(s.duration) : 'In progress'}';

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_month, color: _accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(header,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(
                            color: MedsColors.muted, fontSize: 11.5)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onViewSummary,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View Summary', style: TextStyle(fontSize: 12)),
                    Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Emotion',
                  Row(
                    children: [
                      Text(MedsColors.emoji(emotion ?? 'Neutral'),
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(emotion ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _miniStat(
                  'Avg. Heart Rate',
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: MedsColors.pink, size: 15),
                      const SizedBox(width: 5),
                      Text(avgHr != null ? '$avgHr BPM' : '—',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _miniStat(
                  'State',
                  Pill(text: state ?? '—', color: MedsColors.greenDark),
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, Widget value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: MedsColors.muted, fontSize: 11)),
        const SizedBox(height: 5),
        value,
      ],
    );
  }
}

// ---- Weekly trends chart --------------------------------------------------

class _WeeklyTrendsCard extends StatelessWidget {
  final List<_DayPoint> week;
  const _WeeklyTrendsCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final hrSpots = <FlSpot>[];
    final stressSpots = <FlSpot>[];
    for (var i = 0; i < week.length; i++) {
      final d = week[i];
      if (d.hr != null) {
        hrSpots.add(FlSpot(i.toDouble(), d.hr!.toDouble().clamp(40, 100)));
      }
      if (d.stress != null) {
        // Map the 1–5 stress index onto the 40–100 HR axis for a dual-line look.
        stressSpots.add(FlSpot(i.toDouble(), 40 + (d.stress! - 1) / 4 * 60));
      }
    }

    final hasData = hrSpots.isNotEmpty || stressSpots.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legend(const Color(0xFF7C6BF0), 'Avg. Heart Rate (BPM)'),
              const SizedBox(width: 16),
              _legend(const Color(0xFF1FB57F), 'Stress Level (1-5)'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: hasData
                ? LineChart(_chartData(context, hrSpots, stressSpots))
                : const Center(
                    child: Text('Run sessions this week to see your trends.',
                        style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: MedsColors.muted)),
      ],
    );
  }

  LineChartData _chartData(
      BuildContext context, List<FlSpot> hr, List<FlSpot> stress) {
    final grid = Theme.of(context).dividerColor;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const muted = TextStyle(color: MedsColors.muted, fontSize: 10);

    return LineChartData(
      minX: 0,
      maxX: 6,
      minY: 40,
      maxY: 100,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            reservedSize: 28,
            getTitlesWidget: (v, _) =>
                Text('${v.toInt()}', style: muted),
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 15,
            reservedSize: 18,
            getTitlesWidget: (v, _) {
              if (v < 40 || v > 100) return const SizedBox.shrink();
              final stressVal = ((v - 40) / 60 * 4 + 1).round();
              return Text('$stressVal', style: muted);
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i > 6) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(days[i], style: muted),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        _line(hr, const Color(0xFF7C6BF0)),
        _line(stress, const Color(0xFF1FB57F), dashed: true),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, {bool dashed = false}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dashArray: dashed ? [6, 4] : null,
      dotData: FlDotData(
        show: true,
        getDotPainter: (s, p, b, i) =>
            FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(show: false),
    );
  }
}
