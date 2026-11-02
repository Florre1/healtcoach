import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_controller.dart';
import '../version.dart';
import '../domain/models.dart';
import '../bluetooth/scale_connection.dart';
import 'forms.dart';
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
  void editProfile([Profile? profile]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ProfileForm(controller: c, existing: profile),
    ),
  );
  void addMeasurement() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => MeasurementForm(controller: c)),
  );
  @override
  Widget build(BuildContext context) {
    if (c.profile == null) return _welcome();
    final p = c.profile!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: forest,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.spa_outlined, color: lime, size: 21),
            ),
            const SizedBox(width: 10),
            const Text(
              'HealthCoach',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Profil wechseln',
            onSelected: (id) {
              if (id == 'new') {
                editProfile();
              } else {
                unawaited(guarded(context, () => c.selectProfile(id)));
              }
            },
            itemBuilder: (_) => [
              for (final item in c.profiles)
                PopupMenuItem(
                  value: item.id,
                  child: Text('${item.id == p.id ? '✓ ' : ''}${item.name}'),
                ),
              const PopupMenuItem(value: 'new', child: Text('+ Neues Profil')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: lime,
                child: Text(
                  p.initials,
                  style: const TextStyle(
                    fontSize: 12,
                    color: forest,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: IndexedStack(
              index: tab,
              children: [_dashboard(), _trends(), _history(), _settings()],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Heute',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Verlauf',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'Messungen',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profil',
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
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
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.monitor_weight_outlined,
                    color: lime,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'DEIN GEWICHT',
                      style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 1.8,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (today)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: lime,
                      size: 21,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                children: [
                  Text(
                    latest == null ? '—' : number(latest.weight, 2),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: -2,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'kg',
                      style: TextStyle(color: Colors.white70, fontSize: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                latest == null
                    ? 'Deine erste Messung wartet auf dich.'
                    : 'Zuletzt ${dateLabel(latest.time)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Divider(height: 1, color: Colors.white24),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dein Ziel  ${number(p.goalKg)} kg',
                      style: const TextStyle(
                        color: lime,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    gap == null
                        ? 'Los geht’s'
                        : gap < .05
                        ? 'Ziel erreicht'
                        : '${number(gap)} kg Abstand',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: lime,
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _connectionCard(),
        SectionTitle(
          'Dein Gewichtsverlauf',
          trailing: TextButton(
            onPressed: () => setState(() => tab = 1),
            child: const Text('Alle Werte'),
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
                    width: (size.maxWidth - 12) / 2,
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
      return Panel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    s.phase == ConnectionPhase.ready
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_rounded,
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
      );
    },
  );

  void _showScale() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
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
                      '1. Bluetooth am Handy einschalten.\n2. Sanitas-App vollständig schließen.\n3. Waage kurz antippen und hier verbinden.\n4. Nach „Bereit“ barfuß aufsteigen.',
                      style: TextStyle(height: 1.7),
                    ),
                    const SizedBox(height: 18),
                    Panel(
                      child: Text(
                        s.message,
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                    if (s.liveWeight != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          '${number(s.liveWeight!, 2)} kg',
                          style: Theme.of(context).textTheme.headlineLarge,
                          textAlign: TextAlign.center,
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
                      'Beim ersten Mal wird dein Profil auf der Waage eingerichtet oder anhand deiner Angaben zugeordnet. Bereits vorhandene Messungen vor deinem App-Start werden nicht importiert.',
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
    return ListView(
      key: const PageStorageKey('trends'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      children: [
        Text(
          'Dein Fortschritt.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text('Die Entwicklung zählt. Tag für Tag.'),
        const SizedBox(height: 25),
        DropdownButtonFormField<Metric>(
          key: ValueKey(metric),
          initialValue: metric,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Körperwert'),
          items: Metric.values
              .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
              .toList(),
          onChanged: (m) => setState(() => metric = m!),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [7, 30, 90, 0])
              ChoiceChip(
                label: Text(d == 0 ? 'Alles' : '$d Tage'),
                selected: days == d,
                onSelected: (_) => setState(() => days = d),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(metric.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(metric.unit),
              TrendChart(
                measurements: data,
                metric: metric,
                goal: metric == Metric.weight ? c.profile!.goalKg : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'Pro Tag der letzte verfügbare Wert. Fehlende Tage werden nicht aufgefüllt.',
                style: TextStyle(fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: _stat(
                  'Veränderung',
                  diff == null
                      ? '—'
                      : '${diff > 0 ? '+' : ''}${number(diff, metric.digits)} ${metric.unit}',
                ),
              ),
              Expanded(
                child: _stat(
                  'Tagesdurchschnitt',
                  mean == null
                      ? '—'
                      : '${number(mean, metric.digits)} ${metric.unit}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(metric.explanation, style: const TextStyle(height: 1.5)),
        const SizedBox(height: 10),
        Text(
          '${daily.length} Tage mit Messwerten',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      const SizedBox(height: 7),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );

  Widget _history() => CustomScrollView(
    key: const PageStorageKey('history'),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deine Messungen.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text('${c.measurements.length} Einträge · ${c.profile!.name}'),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: addMeasurement,
                icon: const Icon(Icons.add),
                label: const Text('Messung eintragen'),
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
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        sliver: SliverList.builder(
          itemCount: c.measurements.length,
          itemBuilder: (context, index) {
            final m = c.measurements[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: Icon(
                    m.source == 'scale'
                        ? Icons.bluetooth_rounded
                        : Icons.edit_outlined,
                  ),
                  title: Text(
                    '${number(m.weight, 2)} kg',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${dateLabel(m.time)}\n${m.source == 'scale' ? 'Sanitas-Waage' : 'Manuell'}${m.note.isEmpty ? '' : ' · Notiz'}',
                    style: const TextStyle(fontSize: 11, height: 1.6),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _measurementDetail(m),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  void _measurementDetail(Measurement m) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .7,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
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
  );

  Widget _settings() {
    final p = c.profile!;
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
      children: [
        Text(
          'Dein Weg. Dein Ziel.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('${p.heightCm} cm · Waagenkürzel ${p.initials}'),
              const SizedBox(height: 24),
              Text(
                'ZIELGEWICHT',
                style: TextStyle(
                  letterSpacing: 1.6,
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${number(p.goalKg)} kg',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => editProfile(p),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Profil & Ziel bearbeiten'),
              ),
            ],
          ),
        ),
        const SectionTitle('So passt es zu dir'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
              ListTile(
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
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Weiteres Profil'),
                subtitle: const Text('Getrennte Ziele und Messungen'),
                onTap: () => editProfile(),
              ),
              ListTile(
                leading: const Icon(Icons.bluetooth_rounded),
                title: const Text('Waage'),
                subtitle: Text(p.deviceName ?? 'Noch nicht verbunden'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showScale,
              ),
              if (p.deviceId != null)
                ListTile(
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
        const SectionTitle('Deine Daten gehören dir'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              ListTile(
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
              ListTile(
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
              ListTile(
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
        const SectionTitle('Hilfe & Informationen'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Verbinden & messen'),
                onTap: _showScale,
              ),
              ListTile(
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
              ListTile(
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
