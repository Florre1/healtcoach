import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_controller.dart';
import 'data/repository.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['HealthCoach / openScale protocol'],
      '${await rootBundle.loadString('THIRD_PARTY_NOTICES.md')}\n\n${await rootBundle.loadString('LICENSE')}',
    );
  });
  await initializeDateFormatting('de_DE');
  try {
    final controller = AppController(await Repository.open());
    await controller.load();
    runApp(HealthCoachApp(controller: controller));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Deine lokalen Daten konnten nicht geöffnet werden. Bitte starte die App neu. Deinstalliere sie nicht, damit deine Daten erhalten bleiben.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HealthCoachApp extends StatefulWidget {
  final AppController controller;
  const HealthCoachApp({super.key, required this.controller});
  @override
  State<HealthCoachApp> createState() => _HealthCoachAppState();
}

class _HealthCoachAppState extends State<HealthCoachApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(widget.controller.reconnect()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.scale.resume();
      unawaited(widget.controller.reconnect());
    }
    if (state == AppLifecycleState.paused) {
      unawaited(widget.controller.scale.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => MaterialApp(
      title: 'HealthCoach',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: widget.controller.themeMode,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Home(controller: widget.controller),
    ),
  );
}
