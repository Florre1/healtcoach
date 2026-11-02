# Prüfstand der ersten Testversion

Geprüft am 2. November 2026.

- `flutter analyze`: keine Befunde.
- `flutter test`: 19 erfolgreiche Tests.
- Android-Integrationstest auf eigenem Pixel-6-Emulator mit Android 14 / API 34:
  Profil über echtes Formular einschließlich Datumsauswahl anlegen, manuelle
  Gewichtseingabe mit Dezimalkomma, BMI-Berechnung, Diagramme, Historie,
  Detailansicht, Dunkelmodus, Profiltrennung, Sicherungsabgleich und Datenbank
  schließen/erneut öffnen erfolgreich.
- Screenshots der hellen und dunklen Ansichten visuell geprüft.
- Persönlich signierte Release-APK erfolgreich gebaut. Signatur mit
  `apksigner verify` geprüft; ARM32, ARM64 und x86-64 enthalten, Android 8+.
- Release-Manifest geprüft: Bluetooth-Freigaben, Standort nur bis Android 11,
  keine Internet-Berechtigung.
- Release-APK im eigenen Android-14-Emulator installiert und gestartet.

Die Tests verwenden synthetische Daten und eine eigene Testdatenbank. Die App
startet für den Nutzer leer. Ein Bluetooth-Funk-/Firmwaretest an einer echten
Sanitas SBF 70 S-A und die Prüfung auf dem Samsung A17 sind noch offen, siehe
[HARDWARE_TEST.md](HARDWARE_TEST.md).

Der Emulator kann weder den realen Funkablauf noch die Gerätemesswerte bestätigen.
Insbesondere die Interpretation von BMR/AMR/BMI ist gegen das Waagendisplay zu
prüfen. Der Quellcode enthält einen Diagnoseexport zur anschließenden Anpassung
an etwaige Firmwareabweichungen.
