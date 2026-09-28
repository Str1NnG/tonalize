import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/key_profiles.dart';

class ChromaBars extends StatelessWidget {
  final List<double> profile; // 12 valores normalizados (0..1)
  final KeyCandidate? displayedKey;

  const ChromaBars({
    super.key,
    required this.profile,
    this.displayedKey,
  });

  Set<int> _computeScalePitchClasses() {
    if (displayedKey == null) return {};
    final tonic = displayedKey!.tonic;
    final intervals = displayedKey!.major
        ? const [0, 2, 4, 5, 7, 9, 11]
        : const [0, 2, 3, 5, 7, 8, 10];
    return intervals.map((d) => (tonic + d) % 12).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaleNotes = _computeScalePitchClasses();
    final primaryColor = theme.colorScheme.primary;
    final inactiveColor =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 1.05,
          minY: 0.0,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < noteNames.length) {
                    final inScale = scaleNotes.contains(idx);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        noteNames[idx],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              inScale ? FontWeight.bold : FontWeight.w500,
                          color: inScale
                              ? primaryColor
                              : theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 26,
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(12, (i) {
            final val = (i < profile.length)
                ? profile[i].clamp(0.0, 1.0)
                : 0.0;
            final inScale = scaleNotes.contains(i);
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color: inScale ? primaryColor : inactiveColor,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            );
          }),
        ),
        swapAnimationDuration: Duration.zero,
      ),
    );
  }
}
