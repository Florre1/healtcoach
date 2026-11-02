import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/scale_connection.dart';
import 'package:healthcoach/domain/models.dart';
import 'package:healthcoach/ui/live_measurement_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'live values and absent fields at 360dp in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final capture = GlobalKey();
        Future<void> show(
          Map<Metric, double> values,
          ReceptionPhase phase,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness, fontFamily: 'Inter'),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: capture,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LiveMeasurementPanel(
                        values: values,
                        reception: phase,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await show({}, ReceptionPhase.waiting);
        expect(find.text('Warte …'), findsNWidgets(9));
        await show({
          Metric.weight: 80,
          Metric.fat: 21.5,
          Metric.impedance: 510,
        }, ReceptionPhase.receiving);
        expect(find.text('Warte …'), findsNWidgets(6));
        expect(find.text('Körperdaten kommen an'), findsOneWidget);
        expect(find.text('Messung gespeichert'), findsNothing);
        await show({
          Metric.weight: 80,
          Metric.fat: 21.5,
          Metric.impedance: 510,
          Metric.water: 57.2,
          Metric.muscle: 40.1,
          Metric.bone: 3.2,
          Metric.bmi: 24.7,
        }, ReceptionPhase.saved);
        expect(find.text('Nicht übertragen'), findsNWidgets(2));
        expect(find.text('Warte …'), findsNothing);
        expect(find.text('Messung gespeichert'), findsOneWidget);
        if (const bool.fromEnvironment('LIVE_PREVIEW')) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('artifacts/live-preview').create(recursive: true);
            await File('artifacts/live-preview/${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}
