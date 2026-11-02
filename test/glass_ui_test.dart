import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthcoach/app_controller.dart';
import 'package:healthcoach/bluetooth/ble_transport.dart';
import 'package:healthcoach/data/repository.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';
import 'package:healthcoach/main.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repository;
  late AppController controller;
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('de_DE');
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  setUp(() async {
    repository = await Repository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await repository.saveProfile(testProfile());
    await repository.saveMeasurement(
      decodeMeasurement(measurementPacket(), testProfile(), now: testTime),
    );
    controller = AppController(repository, transport: _UnusedBle());
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await repository.db.close();
  });
  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'all glass tabs fit 360dp with enlarged text in ${theme.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        controller.themeMode = theme;
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: HealthCoachApp(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hallo, Testperson.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Future<void> screenshot(String tab) async {
          if (!const bool.fromEnvironment('GLASS_PREVIEW')) return;
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('artifacts/glass-preview').create(recursive: true);
            await File('artifacts/glass-preview/${theme.name}-$tab.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await screenshot('Heute');
        for (final tab in ['Verlauf', 'Messungen', 'Profil', 'Heute']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tab);
          await screenshot(tab);
        }
        await tester.tap(find.byTooltip('Waage verbinden').first);
        await tester.pumpAndSettle();
        expect(find.text('Deine Waage verbinden'), findsOneWidget);
        expect(
          find.textContaining('1. Bluetooth am Handy einschalten.'),
          findsOneWidget,
        );
        await screenshot('Waage');
        await tester.ensureVisible(find.text('Waage suchen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Original connection sheet closes by drag, backdrop or Android back.
        Navigator.of(tester.element(find.text('Deine Waage verbinden'))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Profil').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Profil & Ziel bearbeiten'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'Testperson'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Schließen').last);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _UnusedBle implements BleTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected BLE access during UI test');
}
