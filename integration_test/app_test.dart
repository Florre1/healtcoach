import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:healthcoach/app_controller.dart';
import 'package:healthcoach/data/repository.dart';
import 'package:healthcoach/domain/models.dart';
import 'package:healthcoach/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'onboarding, daily tracking, all charts, profile isolation and persistence',
    (tester) async {
      await initializeDateFormatting('de_DE');
      final testDbPath =
          '${await getDatabasesPath()}/healthcoach-integration.db';
      await deleteDatabase(
        testDbPath,
      ); // Dedicated disposable test database only.
      final repo = await Repository.open(path: testDbPath);
      final c = AppController(repo);
      await c.load();
      await tester.pumpWidget(HealthCoachApp(controller: c));
      await tester.pumpAndSettle();
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      expect(find.text('Dein Körper.\nDein Fortschritt.'), findsOneWidget);
      await binding.takeScreenshot('01-welcome');
      await tester.tap(find.text('Mein Profil einrichten'));
      await tester.pumpAndSettle();
      // Complete onboarding through the real form, including the date picker.
      expect(find.text('Ein guter Anfang.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dein Name'),
        'Alex',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Kürzel auf der Waage'),
        'ALX',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Geburtsdatum wählen'));
      await tester.tap(find.text('Geburtsdatum wählen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Männlich').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Körpergröße'),
        '180',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dein Zielgewicht'),
        '75',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Profil speichern'));
      await tester.tap(find.text('Profil speichern'));
      await tester.pumpAndSettle();
      final p = c.profile!;
      final now = DateTime.now();
      expect(find.text('Hallo, Alex.'), findsOneWidget);
      await binding.takeScreenshot('02-empty-dashboard');
      // Test real form entry, decimal comma, automatic BMI and immediate chart update.
      await tester.tap(find.text('Messungen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Messung eintragen').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Gewicht'),
        '80,25',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Messung speichern'));
      await tester.tap(find.text('Messung speichern'));
      await tester.pumpAndSettle();
      expect(c.measurements.single.weight, 80.25);
      expect(c.measurements.single.values[Metric.bmi], closeTo(24.7685, .001));
      // Seed synthetic history; never included in release builds or the user's DB.
      for (var day = 28; day >= 1; day--) {
        final weight = 80 + day * .085 + (day % 3) * .12;
        await c.addMeasurement(
          Measurement(
            id: 'demo-$day',
            profileId: p.id,
            time: now.subtract(Duration(days: day)),
            source: 'scale',
            values: {
              Metric.weight: weight,
              Metric.bmi: weight / 3.24,
              Metric.fat: 20.5 + day * .04,
              Metric.water: 57.3,
              Metric.muscle: 41.2,
              Metric.bone: 3.15,
              Metric.bmr: 1760,
              Metric.amr: 2640,
              Metric.impedance: 520,
            },
          ),
        );
      }
      await tester.tap(find.text('Heute').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03-dashboard');
      await tester.tap(find.text('Verlauf').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('04-trends');
      expect(tester.takeException(), isNull);
      for (final metric in [
        Metric.fat,
        Metric.bmr,
        Metric.amr,
        Metric.impedance,
      ]) {
        await tester.tap(find.byType(DropdownButtonFormField<Metric>));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(metric.label).last);
        await tester.tap(find.text(metric.label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Messungen').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('05-history');
      await tester.tap(find.text('80,25 kg').first);
      await tester.pumpAndSettle();
      expect(find.text('Manuell eingetragen · BMI berechnet'), findsOneWidget);
      await binding.takeScreenshot('06-measurement');
      // Bottom sheet dismissal, then profile and dark theme.
      Navigator.of(
        tester.element(find.text('Manuell eingetragen · BMI berechnet')),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profil').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('07-profile');
      await c.setTheme(ThemeMode.dark);
      await tester.tap(find.text('Heute').last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('08-dark');
      expect(tester.takeException(), isNull);
      final other = Profile(
        id: 'integration-other',
        name: 'Sam',
        initials: 'SAM',
        sex: 'female',
        birthday: DateTime(1997, 1, 2),
        heightCm: 170,
        activity: 2,
        goalKg: 65,
        trackingSince: now,
      );
      await c.saveProfile(other);
      await tester.pumpAndSettle();
      expect(c.measurements, isEmpty);
      await c.selectProfile(p.id);
      expect(c.measurements.length, 29);
      final backup = await repo.backup();
      expect(await repo.restore(backup), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      c.dispose();
      await repo.db.close();
      final reopened = await Repository.open(path: testDbPath);
      expect((await reopened.measurements(p.id)).length, 29);
      expect(await reopened.setting('theme'), 'dark');
      await reopened.db.close();
      await deleteDatabase(testDbPath);
    },
  );
}
