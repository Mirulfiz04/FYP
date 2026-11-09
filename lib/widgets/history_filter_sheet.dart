import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../viewmodels/history_view_model.dart';

const _emotions = ['Happy', 'Sad', 'Angry', 'Fear', 'Surprise', 'Disgust', 'Neutral'];
const _states = ['Calm', 'Content', 'Stressed', 'Excited', 'Low Mood', 'Neutral'];
const _statuses = ['completed', 'active', 'cancelled'];

/// Opens the advanced-filter sheet and resolves to the chosen [HistoryFilters],
/// or null if the user dismisses it without applying.
Future<HistoryFilters?> showHistoryFilterSheet(
  BuildContext context,
  HistoryFilters current,
) {
  return showModalBottomSheet<HistoryFilters>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HistoryFilterSheet(initial: current),
  );
}

class _HistoryFilterSheet extends StatefulWidget {
  final HistoryFilters initial;
  const _HistoryFilterSheet({required this.initial});

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  late String? _emotion = widget.initial.emotion;
  late String? _state = widget.initial.state;
  late String? _status = widget.initial.status;
  late bool _aiOnly = widget.initial.aiAvailableOnly;
  late final _minCtrl =
      TextEditingController(text: widget.initial.minBpm?.toString() ?? '');
  late final _maxCtrl =
      TextEditingController(text: widget.initial.maxBpm?.toString() ?? '');

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      HistoryFilters(
        emotion: _emotion,
        state: _state,
        status: _status,
        aiAvailableOnly: _aiOnly,
        minBpm: int.tryParse(_minCtrl.text.trim()),
        maxBpm: int.tryParse(_maxCtrl.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MedsColors.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Filters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _dropdown(
              'Emotion', Icons.mood, _emotion, _emotions, (v) => setState(() => _emotion = v)),
          const SizedBox(height: 14),
          _dropdown('Emotional state', Icons.self_improvement, _state, _states,
              (v) => setState(() => _state = v)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min BPM',
                    prefixIcon: Icon(Icons.south, color: MedsColors.purple),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max BPM',
                    prefixIcon: Icon(Icons.north, color: MedsColors.purple),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dropdown('Session status', Icons.flag_outlined, _status, _statuses,
              (v) => setState(() => _status = v)),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: MedsColors.purple,
            value: _aiOnly,
            onChanged: (v) => setState(() => _aiOnly = v),
            title: const Text('AI insight available only',
                style: TextStyle(fontSize: 14)),
            secondary: const Icon(Icons.auto_awesome, color: MedsColors.purple),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, const HistoryFilters()),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  style:
                      FilledButton.styleFrom(backgroundColor: MedsColors.purple),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String label, IconData icon, String? value,
      List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: MedsColors.purple),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Any')),
        ...items.map((e) => DropdownMenuItem(value: e, child: Text(e))),
      ],
      onChanged: onChanged,
    );
  }
}
