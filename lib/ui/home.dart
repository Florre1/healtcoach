import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'glass.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_controller.dart';
import '../version.dart';
import '../domain/models.dart';
import '../bluetooth/scale_connection.dart';
import 'forms.dart';
import 'live_measurement_panel.dart';
import 'widgets.dart';
import 'theme.dart';

class Home extends StatefulWidget {
  final AppController controller;
  const Home({super.key, required this.controller});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  Metric metric = Metric.weight;
  int days = 30;
  AppController get c => widget.controller;
  Measurement? selectedPoint;
  final scrollPhases = [0, 0, 0, 0];
  void editProfile([Profile? profile]) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => GlassSheet(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .91,
        child: ProfileForm(controller: c, existing: profile),
      ),
    ),
  );
  void addMeasurement() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => GlassSheet(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .91,
        child: MeasurementForm(controller: c),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (c.profile == null) return _welcome();
    final p = c.profile!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (event) {
                      if (event.depth == 0) {
                        final phase = event.metrics.pixels > 65
                            ? 2
                            : event.metrics.pixels > 2
                            ? 1
                            : 0;
                        if (scrollPhases[tab] != phase) {
                          setState(() => scrollPhases[tab] = phase);
                        }
                      }
                      return false;
                    },
                    child: IndexedStack(
                      index: tab,
                      children: [
                        _dashboard(),
                        _trends(),
                        _history(),
                        _settings(),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 58,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: scrollPhases[tab] > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              (dark ? Colors.black : const Color(0xffedf1ed))
                                  .withValues(alpha: .9),
                              (dark ? Colors.black : const Color(0xffedf1ed))
                                  .withValues(alpha: .0),
                            ],
                          ),
                        ),
                        child: Center(
                          child: scrollPhases[tab] == 2
                              ? Text(
                                  const [
                                    'Heute',
                                    'Verlauf',
                                    'Messungen',
                                    'Profil',
                                  ][tab],
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                if (tab == 0)
                  Positioned(
                    right: 16,
                    top: 6,
                    child: GlassSurface(
                      radius: 24,
                      floating: true,
                      child: PopupMenuButton<String>(
                        tooltip: 'Profil wechseln',
                        onSelected: (id) {
                          if (id == 'new') {
                            editProfile();
                          } else {
                            unawaited(
                              guarded(context, () async {
                                await c.selectProfile(id);
                                if (mounted) {
                                  setState(() => selectedPoint = null);
                                }
                              }),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          for (final item in c.profiles)
                            PopupMenuItem(
                              value: item.id,
                              child: Text(
                                '${item.id == p.id ? '✓ ' : ''}${item.name}',
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'new',
                            child: Text('+ Neues Profil'),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: lime,
                            child: Text(
                              p.initials,
                              style: const TextStyle(
                                fontSize: 11,
                                color: forest,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 120,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            (dark ? Colors.black : const Color(0xffedf1ed))
                                .withValues(alpha: .8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 16),
                    child: GlassNavigation(
                      selected: tab,
                      onSelected: (value) => setState(() {
                        tab = value;
                        selectedPoint = null;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(28),
            shrinkWrap: true,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: forest,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(Icons.spa_outlined, color: lime, size: 38),
                ),
              ),
              const SizedBox(height: 38),
              const Text(
                'HEALTHCOACH',
                style: TextStyle(
                  letterSpacing: 3,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Dein Körper.\nDein Fortschritt.',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 43, height: 1.08),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ein kleiner Moment am Tag. Ein klarer Blick auf deinen Weg.',
                style: TextStyle(fontSize: 18, height: 1.5),
              ),
              const SizedBox(height: 30),
              const Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Feature(
                      Icons.bluetooth_rounded,
                      'Direkt mit deiner Sanitas-Waage',
                    ),
                    SizedBox(height: 20),
                    _Feature(
                      Icons.show_chart_rounded,
                      'Gewicht & Körperwerte im Verlauf',
                    ),
                    SizedBox(height: 20),
                    _Feature(
                      Icons.lock_outline_rounded,
                      'Lokal gespeichert. Ohne Konto.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              FilledButton(
                onPressed: () => editProfile(),
                child: const Text('Mein Profil einrichten'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => guarded(context, () async {
                  final count = await c.importBackup();
                  if (count != null && mounted) {
                    toast(context, '$count Messungen wiederhergestellt.');
                  }
                }),
                child: const Text('Vorhandene Sicherung wiederherstellen'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _dashboard() {
    final p = c.profile!, latest = c.measurements.firstOrNull;
    final now = DateTime.now();
    final today = c.measurements.any((m) {
      final t = m.time.toLocal();
      return t.year == now.year && t.month == now.month && t.day == now.day;
    });
    final gap = latest == null ? null : (latest.weight - p.goalKg).abs();
    final start = c.measurements.lastOrNull?.weight;
    final total = start == null ? 0.0 : (start - p.goalKg).abs();
    final progress = gap == null
        ? 0.0
        : total < .05
        ? (gap < .05 ? 1.0 : 0.0)
        : ((start! - latest!.weight) / (start - p.goalKg)).clamp(0.0, 1.0);
    return ListView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 140),
      children: [
        Text(
          DateFormat('EEEE, d. MMMM', 'de_DE').format(now).toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Hallo, ${p.name}.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 7),
        Text(
          today
              ? 'Dein Check-in für heute ist geschafft.'
              : 'Ein neuer Tag für deinen Fortschritt.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        GlassSurface(
          prominent: true,
          radius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dein Gewicht',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  if (today)
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                latest == null ? '—' : number(latest.weight, 2),
                                style: const TextStyle(
                                  fontSize: 60,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -2.4,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'kg',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latest == null
                              ? 'Deine erste Messung wartet auf dich.'
                              : 'Zuletzt ${dateLabel(latest.time)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GoalRing(progress: progress),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                spacing: 16,
                children: [
                  Text(
                    'Dein Ziel ${number(p.goalKg)} kg',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    gap == null
                        ? 'Los geht’s'
                        : gap < .05
                        ? 'Ziel erreicht'
                        : '${number(gap)} kg Abstand',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _connectionCard(),
        SectionTitle(
          'Dein Gewichtsverlauf',
          trailing: TextButton(
            onPressed: () => setState(() => tab = 1),
            child: const Text('Alle Werte', style: TextStyle(fontSize: 14)),
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Letzte 30 Tage',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TrendChart(
                measurements: c.measurements
                    .where(
                      (m) => m.time.isAfter(
                        now.subtract(const Duration(days: 30)),
                      ),
                    )
                    .toList(),
                metric: Metric.weight,
                height: 170,
                goal: p.goalKg,
              ),
              const Text(
                'Letzter Wert pro Tag · gestrichelt: dein Ziel',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const SectionTitle('Mehr als eine Zahl'),
        if (latest == null)
          const EmptyCard(
            icon: Icons.accessibility_new_rounded,
            title: 'Deine Körperwerte',
            description: 'Nach einer vollständigen Messung erscheinen hier Körperfett, Wasser, Muskeln und weitere Werte.',
          )
        else
          LayoutBuilder(
            builder: (context, size) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final m in Metric.values.where(
                  (m) => m != Metric.weight && m != Metric.impedance,
                ))
                  SizedBox(
                    width: m == Metric.amr
                        ? size.maxWidth
                        : (size.maxWidth - 12) / 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() {
                        metric = m;
                        tab = 1;
                      }),
                      child: Panel(
                        padding: const EdgeInsets.all(17),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 5,
                              children: [
                                Text(
                                  latest.values[m] == null
                                      ? '—'
                                      : number(latest.values[m]!, m.digits),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  m.unit,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          'Körperanalysewerte sind Schätzungen der Waage. Vergleiche Messungen möglichst unter ähnlichen Bedingungen.',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: addMeasurement,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Messung manuell eintragen'),
        ),
      ],
    );
  }

  Widget _connectionCard() => ListenableBuilder(
    listenable: c.scale,
    builder: (context, _) {
      final s = c.scale;
      return GestureDetector(
        onTap: _showScale,
        child: Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      CupertinoIcons.bluetooth,
                      color: Theme.of(context).colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sanitas SBF 70',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          s.phase == ConnectionPhase.ready
                              ? 'Verbunden${s.battery == null ? '' : ' · Akku ${s.battery}%'}'
                              : 'Deine Bluetooth-Waage',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Waage verbinden',
                    onPressed: _showScale,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                s.message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: s.phase == ConnectionPhase.error
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (s.working) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      );
    },
  );

  void _showScale() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheet) => GlassSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ListenableBuilder(
            listenable: c.scale,
            builder: (context, _) {
              final s = c.scale;
              return SizedBox(
                height: MediaQuery.sizeOf(context).height * .68,
                child: ListView(
                  children: [
                    Text(
                      'Deine Waage verbinden',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Bluetooth am Handy einschalten.\n2. Sanitas-App vollständig schließen.\n3. Waage kurz antippen und hier verbinden.\n4. Sobald verbunden: an der Waage wiegen.',
                      style: TextStyle(height: 1.7),
                    ),
                    const SizedBox(height: 18),
                    Panel(
                      child: Text(
                        s.message,
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                    if (s.phase == ConnectionPhase.ready)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: LiveMeasurementPanel(
                          values: s.liveValues,
                          reception: s.reception,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (s.working) const LinearProgressIndicator(),
                    for (final device in s.devices.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.monitor_weight_outlined),
                        title: Text(
                          device.name.isEmpty ? 'Sanitas SBF 70' : device.name,
                        ),
                        subtitle: Text('Signal ${device.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            [
                              ConnectionPhase.scanning,
                              ConnectionPhase.idle,
                              ConnectionPhase.error,
                            ].contains(s.phase)
                            ? () => guarded(
                                context,
                                () => s.connect(c.profile!, device),
                              )
                            : null,
                      ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => guarded(context, () async {
                        if (s.busy) {
                          await s.disconnect();
                        } else {
                          await s.scan(c.profile!);
                        }
                      }),
                      icon: Icon(
                        s.busy ? Icons.close_rounded : Icons.search_rounded,
                      ),
                      label: Text(
                        s.busy ? 'Verbindung / Suche beenden' : 'Waage suchen',
                      ),
                    ),
                    if (s.phase == ConnectionPhase.error)
                      TextButton(
                        onPressed: openAppSettings,
                        child: const Text('Android-App-Einstellungen öffnen'),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Messungen werden im aktuell geöffneten App-Profil gespeichert, unabhängig vom Waagenprofil. Starte die Messung an der Waage. Die App empfängt ausschließlich neue Live-Messungen.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _trends() {
    final cutoff = days == 0
        ? DateTime(2000)
        : DateTime.now().subtract(Duration(days: days));
    final data = c.measurements
        .where((m) => !m.time.isBefore(cutoff) && m.values.containsKey(metric))
        .toList();
    final daily = dailyMeasurements(data, metric);
    final diff = daily.length < 2
        ? null
        : daily.last.values[metric]! - daily.first.values[metric]!;
    final mean = daily.isEmpty
        ? null
        : daily.map((m) => m.values[metric]!).reduce((a, b) => a + b) /
              daily.length;
    final selected =
        selectedPoint != null && daily.any((m) => m.id == selectedPoint!.id)
        ? selectedPoint
        : null;
    return ListView(
      key: const PageStorageKey('trends'),
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 140),
      children: [
        Text(
          'Dein Fortschritt.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Die Entwicklung zählt. Tag für Tag.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: GlassSurface(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Metric>(
                value: metric,
                icon: const Icon(CupertinoIcons.chevron_down, size: 14),
                borderRadius: BorderRadius.circular(24),
                items: Metric.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          m.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  metric = value!;
                  selectedPoint = null;
                }),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: days,
            backgroundColor: Colors.grey.withValues(alpha: .24),
            thumbColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff555559)
                : Colors.white,
            children: {
              for (final d in [7, 30, 90, 0])
                d: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    d == 0 ? 'Alles' : '$d Tage',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
            },
            onValueChanged: (d) {
              if (d != null) {
                setState(() {
                  days = d;
                  selectedPoint = null;
                });
              }
            },
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected == null
                    ? 'TAGESDURCHSCHNITT'
                    : DateFormat(
                        'EE, d. MMM yyyy',
                        'de_DE',
                      ).format(selected.time),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .3,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: selected != null
                          ? number(selected.values[metric]!, metric.digits)
                          : mean == null
                          ? '—'
                          : number(mean, metric.digits),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    TextSpan(
                      text: ' ${metric.unit}',
                      style: TextStyle(
                        fontSize: 17,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                selected == null
                    ? daily.isEmpty
                          ? 'Noch keine Werte'
                          : '${DateFormat('d. MMM', 'de_DE').format(daily.first.time)} – ${DateFormat('d. MMM yyyy', 'de_DE').format(daily.last.time)}'
                    : '${DateFormat('HH:mm').format(selected.time)} Uhr · ${selected.source == 'scale' ? 'Sanitas-Waage' : 'Manuell'}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TrendChart(
                measurements: data,
                metric: metric,
                goal: metric == Metric.weight ? c.profile!.goalKg : null,
                onSelected: (point) {
                  if (point?.id != selectedPoint?.id) {
                    setState(() => selectedPoint = point);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Pro Tag der letzte verfügbare Wert. Fehlende Tage werden nicht aufgefüllt.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _summaryRow(
                'Veränderung',
                diff == null
                    ? '—'
                    : '${diff > 0 ? '+' : ''}${number(diff, metric.digits)} ${metric.unit}',
              ),
              _summaryRow('Tage mit Messwerten', '${daily.length}'),
              if (metric == Metric.weight)
                _summaryRow('Dein Ziel', '${number(c.profile!.goalKg)} kg'),
            ],
          ),
        ),
        SectionTitle('Über ${metric.label}'),
        Panel(
          child: Text(
            metric.explanation,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Container(
    constraints: const BoxConstraints(minHeight: 50),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).dividerColor, width: .5),
      ),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _history() {
    final groups = <String, List<Measurement>>{};
    for (final m in c.measurements) {
      final key = DateFormat('MMMM yyyy', 'de_DE').format(m.time.toLocal());
      (groups[key] ??= []).add(m);
    }
    return CustomScrollView(
      key: const PageStorageKey('history'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deine Messungen.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.measurements.length} Einträge · ${c.profile!.name}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: addMeasurement,
                    icon: const Icon(CupertinoIcons.add),
                    label: const Text('Messung eintragen'),
                  ),
                ),
                if (c.measurements.isEmpty) ...[
                  const SizedBox(height: 22),
                  EmptyCard(
                    title: 'Hier wächst dein Verlauf.',
                    description: 'Verbinde deine Waage oder trage deine erste Messung ein.',
                    action: OutlinedButton(
                      onPressed: _showScale,
                      child: const Text('Waage verbinden'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
          sliver: SliverList.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final month = groups.keys.elementAt(index), rows = groups[month]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 0, 8),
                    child: Text(
                      month.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.only(left: 58),
                              child: Divider(height: .5, thickness: .5),
                            ),
                          _historyRow(rows[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _historyRow(Measurement m) {
    final accent = m.source == 'scale'
        ? Theme.of(context).colorScheme.primary
        : const Color(0xffff9f0a);
    final now = DateTime.now(), date = m.time.toLocal();
    final delta = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          m.source == 'scale'
              ? CupertinoIcons.bluetooth
              : CupertinoIcons.pencil,
          size: 17,
          color: accent,
        ),
      ),
      title: Text(
        '${number(m.weight, 2)} kg',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${m.source == 'scale' ? 'Sanitas-Waage' : 'Manuell'}${m.note.isEmpty ? '' : ' · Notiz'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                delta == 0
                    ? 'Heute'
                    : delta == 1
                    ? 'Gestern'
                    : DateFormat('dd. MMM', 'de_DE').format(date),
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                DateFormat('HH:mm').format(date),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Icon(
            CupertinoIcons.chevron_right,
            size: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _measurementDetail(m),
    );
  }

  void _measurementDetail(Measurement m) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheet) => GlassSheet(
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Messung',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                    onPressed: () => Navigator.pop(sheet),
                  ),
                ],
              ),
              Text(
                '${number(m.weight, 2)} kg',
                style: Theme.of(sheet).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(dateLabel(m.time)),
              const SizedBox(height: 8),
              Text(
                m.source == 'scale'
                    ? 'Von deiner Sanitas-Waage'
                    : 'Manuell eingetragen · BMI berechnet',
              ),
              const Divider(),
              for (final metric in Metric.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(metric.label),
                  trailing: Text(
                    m.values[metric] == null
                        ? 'Nicht verfügbar'
                        : '${number(m.values[metric]!, metric.digits)} ${metric.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (m.note.isNotEmpty) ...[const Divider(), Text(m.note)],
              const Divider(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Messung löschen'),
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: sheet,
                    builder: (dialog) => AlertDialog(
                      title: const Text('Messung löschen?'),
                      content: const Text(
                        'Dieser Eintrag wird aus deiner lokalen Historie entfernt.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Abbrechen'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Löschen'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && sheet.mounted) {
                    await guarded(sheet, () async {
                      await c.removeMeasurement(m.id);
                      if (sheet.mounted) Navigator.pop(sheet);
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _settingRow({
    Widget? leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final icon = leading is Icon ? leading.icon : null;
    final color = switch (icon) {
      Icons.bluetooth_rounded || Icons.help_outline => const Color(0xff0a84ff),
      Icons.person_add_alt_1_outlined => const Color(0xffff9f0a),
      Icons.save_alt_rounded => const Color(0xff40c8e0),
      Icons.restore_page_outlined => const Color(0xffbf5af2),
      Icons.table_chart_outlined => const Color(0xff30d158),
      _ => const Color(0xff8e8e93),
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(width: .5, color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: leading == null
            ? null
            : Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconTheme(
                  data: const IconThemeData(size: 17, color: Colors.white),
                  child: leading,
                ),
              ),
        title: title,
        subtitle: subtitle,
        trailing:
            trailing ?? const Icon(CupertinoIcons.chevron_right, size: 13),
        onTap: onTap,
      ),
    );
  }

  Widget _settings() {
    final p = c.profile!;
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 140),
      children: [
        Text(
          'Dein Weg. Dein Ziel.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 24),
        GlassSurface(
          prominent: true,
          radius: 30,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: lime,
                    child: Text(
                      p.initials,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.heightCm} cm · Profilkürzel ${p.initials}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Text(
                'ZIELGEWICHT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${number(p.goalKg)} kg',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => editProfile(p),
                icon: const Icon(CupertinoIcons.pencil, size: 16),
                label: const Text('Profil & Ziel bearbeiten'),
              ),
            ],
          ),
        ),
        const SectionTitle('So passt es zu dir', compact: true),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Automatisch verbinden'),
                subtitle: const Text(
                  'Beim Öffnen der App nach deiner gespeicherten Waage suchen.',
                ),
                value: c.autoConnect,
                onChanged: (v) => guarded(context, () => c.setAutoConnect(v)),
              ),
              _settingRow(
                title: const Text('Darstellung'),
                trailing: DropdownButton<ThemeMode>(
                  value: c.themeMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Hell'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dunkel'),
                    ),
                  ],
                  onChanged: (v) => guarded(context, () => c.setTheme(v!)),
                ),
              ),
              _settingRow(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Weiteres Profil'),
                subtitle: const Text('Getrennte Ziele und Messungen'),
                onTap: () => editProfile(),
              ),
              _settingRow(
                leading: const Icon(Icons.bluetooth_rounded),
                title: const Text('Waage'),
                subtitle: Text(p.deviceName ?? 'Noch nicht verbunden'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showScale,
              ),
              if (p.deviceId != null)
                _settingRow(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('Waagenzuordnung lösen'),
                  subtitle: const Text('Messungen bleiben erhalten.'),
                  onTap: () => guarded(
                    context,
                    () => c.saveProfile(p.withDevice(null, null)),
                  ),
                ),
            ],
          ),
        ),
        const SectionTitle('Deine Daten gehören dir', compact: true),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _settingRow(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Sicherung speichern'),
                subtitle: const Text('Alle Profile & Messungen als JSON'),
                onTap: () => guarded(context, () async {
                  final saved = await c.exportBackup();
                  if (saved && mounted) {
                    toast(context, 'Sicherung gespeichert.');
                  }
                }),
              ),
              _settingRow(
                leading: const Icon(Icons.restore_page_outlined),
                title: const Text('Sicherung wiederherstellen'),
                subtitle: const Text(
                  'Ergänzt fehlende Einträge, erhält vorhandene.',
                ),
                onTap: () => guarded(context, () async {
                  final count = await c.importBackup();
                  if (count != null && mounted) {
                    toast(context, '$count neue Messungen wiederhergestellt.');
                  }
                }),
              ),
              _settingRow(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('CSV exportieren'),
                subtitle: const Text(
                  'Messungen dieses Profils für Tabellenprogramme',
                ),
                onTap: () => guarded(context, () async {
                  final saved = await c.exportCsv();
                  if (saved && mounted) toast(context, 'CSV gespeichert.');
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Die App benötigt kein Konto und überträgt keine Daten an einen Server. Sichere deine Daten vor einem Handywechsel oder einer Deinstallation.',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
        const SectionTitle('Hilfe & Informationen', compact: true),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _settingRow(
                leading: const Icon(Icons.help_outline),
                title: const Text('Verbinden & messen'),
                onTap: _showScale,
              ),
              _settingRow(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Bluetooth-Diagnose speichern'),
                subtitle: const Text(
                  'Enthält empfangene Daten der aktuellen Sitzung.',
                ),
                onTap: () => guarded(context, () async {
                  final saved = await c.exportFile(
                    'HealthCoach $appVersion · SBF70\n${c.scale.diagnosticLog.join('\n')}',
                    'healthcoach-bluetooth.txt',
                    'text/plain',
                  );
                  if (saved && mounted) toast(context, 'Diagnose gespeichert.');
                }),
              ),
              _settingRow(
                leading: const Icon(Icons.info_outline),
                title: const Text('Über HealthCoach'),
                subtitle: const Text(
                  'Version $appVersion · Für deinen täglichen Fortschritt',
                ),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'HealthCoach',
                  applicationVersion: appVersion,
                  applicationLegalese: 'GPL-3.0-or-later · Quellcode: github.com/Florre1/healtcoach',
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Unabhängige App für Sanitas SBF 70. Bluetooth-Protokoll auf Basis der openScale-Dokumentation und Referenzimplementierung (© 2025 olie.xdev). Nicht von Sanitas oder Beurer herausgegeben.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Feature(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 14),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
    ],
  );
}
