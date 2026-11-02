import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';
import 'theme.dart';
import 'glass.dart';

String number(double value, [int digits = 1]) =>
    NumberFormat.decimalPatternDigits(
      locale: 'de_DE',
      decimalDigits: digits,
    ).format(value);
String dateLabel(DateTime date) =>
    DateFormat('dd. MMM yyyy · HH:mm', 'de_DE').format(date.toLocal());

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) =>
      GlassSurface(padding: padding, child: child);
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool compact;
  const SectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            compact ? title.toUpperCase() : title,
            style: compact
                ? TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .3,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )
                : Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyCard({
    super.key,
    this.icon = Icons.insights_rounded,
    required this.title,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(17),
          decoration: const BoxDecoration(color: lime, shape: BoxShape.circle),
          child: Icon(icon, color: forest, size: 30),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class TrendChart extends StatelessWidget {
  final List<Measurement> measurements;
  final Metric metric;
  final double? goal;
  final double height;
  final ValueChanged<Measurement?>? onSelected;
  const TrendChart({
    super.key,
    required this.measurements,
    required this.metric,
    this.goal,
    this.height = 210,
    this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final points = dailyMeasurements(measurements, metric);
    if (points.isEmpty) {
      return SizedBox(
        height: 190,
        child: Center(
          child: Text(
            'Dein Verlauf beginnt mit der ersten Messung.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final first = points.first.time.toLocal();
    final start =
        DateTime.utc(
          first.year,
          first.month,
          first.day,
        ).millisecondsSinceEpoch /
        86400000;
    double x(Measurement m) {
      final t = m.time.toLocal();
      return DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch /
              86400000 -
          start;
    }

    final spots = points.map((m) => FlSpot(x(m), m.values[metric]!)).toList();
    final values = spots.map((s) => s.y).toList();
    if (goal != null) values.add(goal!);
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final padding = math.max(
      (hi - lo) * .22,
      metric == Metric.weight ? 1.0 : 2.0,
    );
    final minY = math.max(0.0, lo - padding), maxY = hi + padding;
    final maxX = math.max(1.0, spots.last.x);
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 14, top: 12),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 3,
              getDrawingHorizontalLine: (_) => FlLine(
                color: Theme.of(context).dividerColor,
                strokeWidth: 1,
                dashArray: [4, 5],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  minIncluded: false,
                  maxIncluded: false,
                  interval: (maxY - minY) / 3,
                  getTitlesWidget: (v, meta) => Text(
                    number(v, metric.digits == 0 ? 0 : 1),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: math.max(1, (maxX / 3).ceil()).toDouble(),
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    space: 9,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(
                      meta,
                      distanceFromEdge: 0,
                    ),
                    child: Text(
                      DateFormat('dd.MM.').format(
                        DateTime.fromMillisecondsSinceEpoch(
                          ((start + v) * 86400000).round(),
                          isUtc: true,
                        ),
                      ),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (goal != null)
                  HorizontalLine(
                    y: goal!,
                    color: color.withValues(alpha: .45),
                    strokeWidth: 1.5,
                    dashArray: [5, 5],
                  ),
              ],
            ),
            lineTouchData: LineTouchData(
              touchCallback: (event, response) {
                final touched = response?.lineBarSpots?.firstOrNull;
                onSelected?.call(
                  event.isInterestedForInteractions && touched != null
                      ? points[touched.spotIndex]
                      : null,
                );
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (items) => items
                    .map(
                      (s) => LineTooltipItem(
                        '${number(s.y, metric.digits)} ${metric.unit}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: color,
                barWidth: 3,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: index == spots.length - 1 ? 4 : 2,
                        color: color,
                        strokeWidth: 1.2,
                        strokeColor: Theme.of(context).colorScheme.surface,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .16),
                      color.withValues(alpha: .01),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Show newly synchronized history immediately, including after an
          // offstage tab becomes visible; avoid interpolating unequal series.
          duration: Duration.zero,
        ),
      ),
    );
  }
}

Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FormatException ? e.message : 'Das hat nicht funktioniert. Deine gespeicherten Daten bleiben erhalten. Bitte erneut versuchen.',
          ),
        ),
      );
    }
  }
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
