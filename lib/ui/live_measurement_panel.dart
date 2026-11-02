import 'package:flutter/material.dart';

import '../bluetooth/scale_connection.dart';
import '../domain/models.dart';
import 'widgets.dart';

/// Reflects actual packet arrival, without simulated progress or body estimates.
class LiveMeasurementPanel extends StatelessWidget {
  final Map<Metric, double> values;
  final ReceptionPhase reception;
  const LiveMeasurementPanel({
    super.key,
    required this.values,
    required this.reception,
  });

  @override
  Widget build(BuildContext context) {
    final complete = [
      ReceptionPhase.received,
      ReceptionPhase.saving,
      ReceptionPhase.saved,
      ReceptionPhase.duplicate,
    ].contains(reception);
    final title = switch (reception) {
      ReceptionPhase.waiting => 'Warte auf deine Messung',
      ReceptionPhase.weighing => 'Gewicht kommt an',
      ReceptionPhase.receiving => 'Körperdaten kommen an',
      ReceptionPhase.received => 'Messung vollständig empfangen',
      ReceptionPhase.saving => 'Messung wird gespeichert …',
      ReceptionPhase.saved => 'Messung gespeichert',
      ReceptionPhase.duplicate => 'Messung bereits gespeichert',
      ReceptionPhase.discarded => 'Unvollständig – bitte erneut wiegen',
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Live-Empfang', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Semantics(liveRegion: true, child: Text(title)),
          const SizedBox(height: 12),
          for (final metric in Metric.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    values.containsKey(metric)
                        ? Icons.check_circle_outline
                        : Icons.more_horiz,
                    size: 18,
                    color: values.containsKey(metric)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(metric.label),
                        Text(
                          values.containsKey(metric)
                              ? '${number(values[metric]!, metric.digits)}${metric.unit.isEmpty ? '' : ' ${metric.unit}'}'
                              : complete
                              ? 'Nicht übertragen'
                              : 'Warte …',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: values.containsKey(metric)
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            complete
                ? 'Übernommen werden alle von der Waage gelieferten Werte.'
                : 'Vorschau: Gespeichert wird erst die vollständige Messung.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
