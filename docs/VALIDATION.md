# Prüfstand

## Version 1.1.1

- Verbindungs-Sheet wieder mit der Anordnung aus Release 1.0.0: Anleitung,
  Status, Live-Gewicht, Geräteliste, Suchen/Beenden und Profilhinweis.
  Glass-Oberfläche und aktuelle BLE-Zustandsmaschine bleiben bestehen.
- Zusätzliche Schließen-Zeile und doppelte Safe-Area-Einrückung entfernt.
- Codeanalyse ohne Befunde; gezielte UI-Tests in Hell und Dunkel auf 360 dp
  mit 130% Schriftgröße prüfen das Öffnen und Bedienen des Sheets.
- Signierte APK 1.1.1 (Build 4) geprüft und als Update über 1.1.0 auf dem
  eigenen Android-Emulator installiert und gestartet.

## Version 1.1.0

- Glass-Redesign aus dem gelieferten ZIP-Handoff umgesetzt; Details in
  [DESIGN.md](DESIGN.md), einschließlich Importweg und Grenzen der Vorlage.
- 58 automatisierte Tests erfolgreich. Neue Oberflächentests prüfen alle vier
  Tabs mit 360 dp Breite und 130% Schriftgröße in Hell und Dunkel.
- Codeanalyse ohne Befunde.
- Android-Integrationstest auf API 34 mit realen Formularen, manueller Messung,
  Diagrammen, Messdetails, Profiltrennung und Speicherung erfolgreich.
- Gerenderte Ansichten visuell geprüft. Der Emulator benötigt für stabile
  Screenshot-Erfassung Software-GLES und `--no-enable-impeller`. Auch der
  Impeller-Release-Start beendete den Emulator; die Android-App wählt daher
  für dieses Release den bereits getesteten Skia-Renderer.
- Ein Test des neuen Designs auf dem Samsung A17 ist weiterhin erforderlich.
- Release-APK 1.1.0 (Build 3) signiert, Signatur identisch mit 1.0.1 geprüft;
  ARM32, ARM64 und x86-64 enthalten, Android 8+.
- Installation als Update über signierte Version 1.0.1 erfolgreich.
- Finale Release-APK mit Skia gestartet, Willkommensansicht per Android-
  Screenshot geprüft; App und Emulator bleiben aktiv.

## Version 1.0.1

- 56 erfolgreiche automatisierte Tests, einschließlich simulierter BLE-Abbrüche,
  verspäteter Antworten, Schreib-Zeitüberschreitungen, doppelter Verbindungsversuche,
  Berechtigungsdialoge, Bluetooth-Abschaltung und fehlgeschlagener Speicherung.
- Protokolltests prüfen Paketfolge, Wiederholungen, Profilzuordnung und
  unvollständige Messungen. Bereitschaft erst nach Bestätigung des Messstarts.
- Codeanalyse ohne Befunde.
- Signierte Release-APK für Android 8+, ARM32, ARM64 und x86-64 gebaut;
  Signatur mit `apksigner verify` geprüft und identisch zu Version 1.0.0.
- Update von signierter Version 1.0.0 auf 1.0.1 mit `adb install -r` auf dem
  eigenen API-34-Emulator erfolgreich installiert und gestartet.
- Android-Integrationstest auf API 34 erneut erfolgreich: Profilformular,
  manuelle Messung, Diagramme, Profiltrennung und Datenpersistenz.
- Funk- und Firmwaretest an der konkreten Waage weiterhin offen.

## Version 1.0.0

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
