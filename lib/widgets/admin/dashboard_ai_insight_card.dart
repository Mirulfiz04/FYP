import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_dashboard_models.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';
import 'dashboard_metric_card.dart' show SkeletonBox;

/// "AI Insight" card. Surfaces the latest AI-generated wellness summary with
/// clear loading / completed / failed / empty states. The text is always
/// framed as a wellness insight — never a medical diagnosis.
class DashboardAiInsightCard extends StatelessWidget {
  final bool loading;
  final DashboardAiInsight? insight;
  final bool failed;
  final VoidCallback onViewFull;
  final VoidCallback onRetry;

  const DashboardAiInsightCard({
    super.key,
    required this.loading,
    required this.insight,
    required this.failed,
    required this.onViewFull,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MedsColors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 16, color: MedsColors.purple),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('AI Insight',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              if (insight != null && !loading)
                Pill(text: insight!.stressLevel, color: MedsColors.stress(insight!.stressLevel)),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            _buildLoading()
          else if (failed)
            _buildFailed()
          else if (insight == null)
            _buildEmpty()
          else
            _buildContent(context),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonBox(width: double.infinity, height: 12),
        SizedBox(height: 9),
        SkeletonBox(width: double.infinity, height: 12),
        SizedBox(height: 9),
        SkeletonBox(width: 160, height: 12),
      ],
    );
  }

  Widget _buildEmpty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'No wellness insight has been generated yet. Insights appear once '
        'sessions have enough valid emotion and heart-rate data.',
        style: TextStyle(color: MedsColors.muted, fontSize: 13, height: 1.45),
      ),
    );
  }

  Widget _buildFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.error_outline, color: MedsColors.red, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('AI insight generation failed.',
                  style: TextStyle(
                      color: MedsColors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final i = insight!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote,
                color: MedsColors.purple.withValues(alpha: 0.6), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                i.text,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.5, color: MedsColors.lightText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (i.generatedAt != null)
          Text(
            'Generated ${DateFormat('d MMM yyyy, h:mm a').format(i.generatedAt!)}',
            style: const TextStyle(color: MedsColors.muted, fontSize: 11.5),
          ),
        const SizedBox(height: 8),
        const Text(
          'Wellness insight — not a medical diagnosis.',
          style: TextStyle(
              color: MedsColors.muted,
              fontSize: 11,
              fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: onViewFull,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            decoration: BoxDecoration(
              color: MedsColors.purple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('View Full Insights',
                    style: TextStyle(
                        color: MedsColors.purple,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5)),
                SizedBox(width: 6),
                Icon(Icons.chevron_right, color: MedsColors.purple, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
