import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'data/repository.dart';
import 'domain/models.dart';
import 'bluetooth/scale_connection.dart';
import 'bluetooth/ble_transport.dart';

class AppController extends ChangeNotifier {
  final Repository repository;
  late final ScaleConnection scale;
  List<Profile> profiles = [];
  List<Measurement> measurements = [];
  String? activeId;
  ThemeMode themeMode = ThemeMode.dark;
  bool autoConnect = true;
  Profile? get profile => profiles.where((p) => p.id == activeId).firstOrNull;
  AppController(this.repository, {BleTransport? transport}) {
    scale = ScaleConnection(
      transport: transport,
      onReading: addMeasurement,
      onBound: (p, id, name) async {
        final latest = profiles.where((item) => item.id == p.id).firstOrNull;
        if (latest == null) return;
        await repository.saveProfile(latest.withDevice(id, name));
        profiles = await repository.profiles();
        notifyListeners();
      },
    );
  }
  Future<void> load() async {
    profiles = await repository.profiles();
    final selected = await repository.setting('activeProfile');
    activeId = profiles.any((p) => p.id == selected)
        ? selected
        : profiles.firstOrNull?.id;
    autoConnect = await repository.setting('autoConnect') != 'false';
    final theme = await repository.setting('theme');
    themeMode =
        ThemeMode.values.where((m) => m.name == theme).firstOrNull ??
        ThemeMode.dark;
    await refresh();
  }

  Future<void> refresh() async {
    final id = activeId;
    final rows = id == null
        ? <Measurement>[]
        : await repository.measurements(id);
    if (id == activeId) {
      measurements = rows;
      notifyListeners();
    }
  }

  Future<void> selectProfile(String id) async {
    await scale.disconnect(quiet: true);
    activeId = id;
    await repository.setSetting('activeProfile', id);
    await refresh();
  }

  Future<void> saveProfile(Profile p) async {
    await scale.disconnect(quiet: true);
    await repository.saveProfile(p);
    profiles = await repository.profiles();
    activeId = p.id;
    await repository.setSetting('activeProfile', p.id);
    await refresh();
  }

  Future<bool> addMeasurement(Measurement m) async {
    final inserted = await repository.saveMeasurement(m);
    if (activeId == m.profileId) await refresh();
    return inserted;
  }

  Future<void> removeMeasurement(String id) async {
    await repository.deleteMeasurement(id);
    await refresh();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await repository.setSetting('theme', mode.name);
  }

  Future<void> setAutoConnect(bool enabled) async {
    autoConnect = enabled;
    notifyListeners();
    await repository.setSetting('autoConnect', '$enabled');
  }

  Future<void> reconnect() async {
    final p = profile;
    if (autoConnect && p?.deviceId != null && !scale.busy) {
      await scale.scan(p!, automatic: true);
    }
  }

  Future<bool> exportFile(String content, String name, String mime) async =>
      await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: mime,
      ) !=
      null;
  Future<bool> exportBackup() async => exportFile(
    await repository.backup(),
    'healthcoach-sicherung-${DateTime.now().toIso8601String().substring(0, 10)}.json',
    'application/json',
  );
  Future<int?> importBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    if (await file.xFile.length() > 20 * 1024 * 1024) {
      throw const FormatException('Sicherung ist zu groß (maximal 20 MB).');
    }
    final bytes = await file.xFile.readAsBytes();
    await scale.disconnect(quiet: true);
    final count = await repository.restore(utf8.decode(bytes));
    await load();
    return count;
  }

  Future<bool> exportCsv() async {
    String cell(String s) {
      // Prevent exported notes from being interpreted as spreadsheet formulas.
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final rows = <List<String>>[
      [
        'Zeitpunkt',
        'Quelle',
        ...Metric.values.map((m) => '${m.label} (${m.unit})'),
        'Notiz',
      ],
      ...measurements.reversed.map(
        (m) => [
          m.time.toIso8601String(),
          m.source == 'scale' ? 'Waage' : 'Manuell',
          ...Metric.values.map(
            (metric) =>
                m.values[metric]
                    ?.toStringAsFixed(metric.digits)
                    .replaceAll('.', ',') ??
                '',
          ),
          m.note,
        ],
      ),
    ];
    return exportFile(
      '\uFEFF${rows.map((row) => row.map(cell).join(';')).join('\r\n')}',
      'healthcoach-messungen.csv',
      'text/csv',
    );
  }

  @override
  void dispose() {
    scale.dispose();
    super.dispose();
  }
}
