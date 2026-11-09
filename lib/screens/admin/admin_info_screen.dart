import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// A lightweight, reusable detail screen for admin-settings destinations that
/// are informational or not yet backed by their own full screen. Supports an
/// optional persisted toggle (e.g. for Two-Factor Authentication) and an
/// optional primary action.
class AdminInfoScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> bullets;

  /// When set, shows a switch persisted under this SharedPreferences key.
  final String? togglePrefKey;
  final String? toggleTitle;
  final String? toggleSubtitle;
  final bool toggleDefault;

  /// Optional primary action button.
  final String? actionLabel;
  final IconData? actionIcon;
  final Future<void> Function()? onAction;
  final bool actionDanger;

  const AdminInfoScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.bullets = const [],
    this.togglePrefKey,
    this.toggleTitle,
    this.toggleSubtitle,
    this.toggleDefault = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.actionDanger = false,
  });

  @override
  State<AdminInfoScreen> createState() => _AdminInfoScreenState();
}

class _AdminInfoScreenState extends State<AdminInfoScreen> {
  bool _toggle = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _toggle = widget.toggleDefault;
    _loadToggle();
  }

  Future<void> _loadToggle() async {
    if (widget.togglePrefKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() =>
            _toggle = prefs.getBool(widget.togglePrefKey!) ?? widget.toggleDefault);
      }
    } catch (_) {/* prefs unavailable — keep default */}
  }

  Future<void> _setToggle(bool v) async {
    setState(() => _toggle = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(widget.togglePrefKey!, v);
    } catch (_) {/* best-effort */}
  }

  Future<void> _runAction() async {
    if (_busy || widget.onAction == null) return;
    setState(() => _busy = true);
    try {
      await widget.onAction!();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Done')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: MedsColors.red, content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(widget.subtitle,
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.togglePrefKey != null) ...[
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: SwitchListTile(
                value: _toggle,
                title: Text(widget.toggleTitle ?? 'Enabled',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: widget.toggleSubtitle != null
                    ? Text(widget.toggleSubtitle!)
                    : null,
                onChanged: _setToggle,
              ),
            ),
          ],
          if (widget.bullets.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in widget.bullets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: widget.color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(b,
                                style: const TextStyle(
                                    fontSize: 13.5, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (widget.actionLabel != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _busy ? null : _runAction,
                style: widget.actionDanger
                    ? FilledButton.styleFrom(backgroundColor: MedsColors.red)
                    : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : Icon(widget.actionIcon ?? Icons.bolt),
                label: Text(widget.actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
