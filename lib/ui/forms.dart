import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_controller.dart';
import '../domain/models.dart';
import 'widgets.dart';

class ProfileForm extends StatefulWidget {
  final AppController controller;
  final Profile? existing;
  const ProfileForm({super.key, required this.controller, this.existing});
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, initials, height, goal;
  DateTime? birthday;
  String? sex;
  int activity = 2;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    name = TextEditingController(text: p?.name);
    initials = TextEditingController(text: p?.initials);
    height = TextEditingController(text: p?.heightCm.toString());
    goal = TextEditingController(text: p == null ? '' : number(p.goalKg));
    birthday = p?.birthday;
    sex = p?.sex;
    activity = p?.activity ?? 2;
  }

  @override
  void dispose() {
    name.dispose();
    initials.dispose();
    height.dispose();
    goal.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    if (birthday == null) {
      toast(context, 'Bitte wähle dein Geburtsdatum.');
      return;
    }
    final old = widget.existing;
    setState(() => saving = true);
    await guarded(context, () async {
      // Profile edits are local; the saved Bluetooth device remains usable.
      final p = Profile(
        id: old?.id ?? newId(),
        name: name.text.trim(),
        initials: initials.text.trim().toUpperCase(),
        birthday: birthday!,
        sex: sex!,
        heightCm: int.parse(height.text),
        activity: activity,
        goalKg: double.parse(goal.text.replaceAll(',', '.')),
        trackingSince: old?.trackingSince ?? DateTime.now(),
        deviceId: old?.deviceId,
        deviceName: old?.deviceName,
        remoteId: null,
      );
      await widget.controller.saveProfile(p);
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Schließen',
        icon: const Icon(CupertinoIcons.xmark),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.existing == null ? 'Dein Profil' : 'Profil bearbeiten',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Ein guter Anfang.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Dein Ziel und deine Körperwerte bleiben auf deinem Handy. Die Waage benötigt diese Angaben für ihre Körperanalyse.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Dein Name'),
                  validator: (s) => s == null || s.trim().isEmpty
                      ? 'Bitte einen Namen eingeben.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: initials,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Profilkürzel',
                    helperText: '1–3 Zeichen, z. B. FLO. Erscheint auf dem Waagendisplay.',
                  ),
                  validator: (s) =>
                      s == null || !RegExp(r'^[a-zA-Z0-9]{1,3}$').hasMatch(s)
                      ? 'Bitte 1–3 Buchstaben oder Ziffern eingeben.'
                      : null,
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(
                    birthday == null
                        ? 'Geburtsdatum wählen'
                        : DateFormat(
                            'dd. MMMM yyyy',
                            'de_DE',
                          ).format(birthday!),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: birthday ?? DateTime(now.year - 25),
                      firstDate: DateTime(now.year - 100, now.month, now.day),
                      lastDate: DateTime(now.year - 10, now.month, now.day),
                      helpText: 'Geburtsdatum · Waage unterstützt 10–100 Jahre',
                    );
                    if (selected != null) setState(() => birthday = selected);
                  },
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: sex,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Geschlecht für die Waagenberechnung',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'female', child: Text('Weiblich')),
                    DropdownMenuItem(value: 'male', child: Text('Männlich')),
                  ],
                  onChanged: (s) => setState(() => sex = s),
                  validator: (s) => s == null ? 'Bitte auswählen.' : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Körpergröße',
                    suffixText: 'cm',
                  ),
                  validator: (s) {
                    final v = int.tryParse(s ?? '');
                    return v == null || v < 100 || v > 220
                        ? 'Bitte 100 bis 220 cm eingeben.'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  initialValue: activity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aktivitätsniveau',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 1,
                      child: Text('1 · Kaum Bewegung'),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text('2 · Wenig Bewegung'),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text('3 · Regelmäßig aktiv'),
                    ),
                    DropdownMenuItem(
                      value: 4,
                      child: Text('4 · Häufig sportlich'),
                    ),
                    DropdownMenuItem(
                      value: 5,
                      child: Text('5 · Sehr intensiv aktiv'),
                    ),
                  ],
                  onChanged: (v) => setState(() => activity = v!),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: goal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Dein Zielgewicht',
                    suffixText: 'kg',
                  ),
                  validator: (s) {
                    final v = double.tryParse((s ?? '').replaceAll(',', '.'));
                    return v == null || !v.isFinite || v < 20 || v > 180
                        ? 'Bitte ein Ziel zwischen 20 und 180 kg eingeben.'
                        : null;
                  },
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(
                    saving ? 'Wird gespeichert …' : 'Profil speichern',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Messungen landen im geöffneten App-Profil. Größe, Alter, Geschlecht und Aktivität werden beim Verbinden in den HealthCoach-Platz der Waage geschrieben, damit sie Körperwerte berechnet. Andere Waagenprofile bleiben unverändert.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MeasurementForm extends StatefulWidget {
  final AppController controller;
  const MeasurementForm({super.key, required this.controller});
  @override
  State<MeasurementForm> createState() => _MeasurementFormState();
}

class _MeasurementFormState extends State<MeasurementForm> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final m in Metric.values.where((m) => m != Metric.bmi))
      m: TextEditingController(),
  };
  final note = TextEditingController();
  DateTime time = DateTime.now();
  bool saving = false;
  late final Profile owner;
  @override
  void initState() {
    super.initState();
    owner = widget.controller.profile!;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    await guarded(context, () async {
      final values = <Metric, double>{};
      for (final e in fields.entries) {
        final v = double.tryParse(e.value.text.replaceAll(',', '.'));
        if (v != null) values[e.key] = v;
      }
      values[Metric.bmi] =
          values[Metric.weight]! /
          ((owner.heightCm / 100) * (owner.heightCm / 100));
      await widget.controller.addMeasurement(
        Measurement(
          id: 'manual:${newId()}',
          profileId: owner.id,
          time: time,
          values: values,
          source: 'manual',
          note: note.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => saving = false);
  }

  Widget field(Metric m) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: fields[m],
      style: m == Metric.weight
          ? const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.8,
            )
          : null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: m.label, suffixText: m.unit),
      validator: (s) {
        if ((s ?? '').isEmpty && m != Metric.weight) return null;
        final v = double.tryParse((s ?? '').replaceAll(',', '.'));
        return v == null || !v.isFinite || v <= 0 || v > m.max
            ? 'Bitte einen Wert größer 0 und bis ${number(m.max, 0)} eingeben.'
            : null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Schließen',
        icon: const Icon(CupertinoIcons.xmark),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('Messung eintragen'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Für Tage ohne Bluetooth. Weitere Körperwerte kannst du optional ergänzen.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(dateLabel(time)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: time,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (date == null || !context.mounted) return;
                    final clock = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(time),
                    );
                    if (clock != null) {
                      final value = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        clock.hour,
                        clock.minute,
                      );
                      if (value.isAfter(DateTime.now())) {
                        if (context.mounted) {
                          toast(
                            context,
                            'Bitte einen Zeitpunkt in der Vergangenheit wählen.',
                          );
                        }
                        return;
                      }
                      setState(() => time = value);
                    }
                  },
                ),
                const SizedBox(height: 20),
                field(Metric.weight),
                ExpansionTile(
                  title: const Text('Weitere Körperwerte'),
                  subtitle: const Text(
                    'Optional · nur bekannte Werte eintragen',
                  ),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 16),
                    ...fields.keys.where((m) => m != Metric.weight).map(field),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: note,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notiz (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(
                    saving ? 'Wird gespeichert …' : 'Messung speichern',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
