import 'package:flutter/material.dart';

class DashboardStat {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onTap;
  const DashboardStat(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.actionLabel,
    this.onTap,
  });
}

/// Landscape summary cards; narrow screens and larger text use one column.
class DashboardStatGrid extends StatelessWidget {
  final List<DashboardStat> stats;
  const DashboardStatGrid({super.key, required this.stats});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final single =
          box.maxWidth < 320 || MediaQuery.textScalerOf(context).scale(14) > 20;
      final width = single ? box.maxWidth : (box.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final stat in stats)
            SizedBox(
              width: width,
              child: _StatCard(stat: stat),
            ),
        ],
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  final DashboardStat stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark
        ? Color.lerp(stat.color, Colors.white, .55)!
        : stat.color;
    final radius = BorderRadius.circular(18);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Color.alphaBlend(
        stat.color.withValues(alpha: dark ? .14 : .06),
        theme.colorScheme.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: accent.withValues(alpha: dark ? .3 : .18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stat.onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: dark ? .14 : .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(stat.icon, size: 30, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${stat.value}',
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 38,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (stat.actionLabel != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stat.actionLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (stat.onTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: accent,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
