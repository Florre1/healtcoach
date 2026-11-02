# Prüfstand

## Version 1.3.3

- Diagnose an der echten SBF70 (1.3.2): Die leere Benutzerliste kommt als
  `E7 F0 33 01 00 08` (Status 1, 0 von 8 Benutzern). 1.3.2 hielt Status 1 für
  einen Fehler und blieb im Gewichtsmodus; die Messung lief als Gast
  (Benutzer 0, Impedanz vorhanden, Körperwerte 0).
- Leere Liste legt jetzt den HealthCoach-Platz an. Neue Tests mit den echten
  Rohdaten.

## Version 1.3.2

- Ursache „nur Gewicht“: Im reinen Empfangsmodus (1.3.0/1.3.1) kannte die Waage
  keinen Benutzer und berechnete deshalb keine Körperwerte.
- Benutzerplatz und Messstart aus 1.2.0 übernommen, Historie lesen/löschen
  entfällt. Fällt die Einrichtung aus, bleibt die Verbindung im Gewichtsmodus.
- Neue Protokolltests: Anlegen und Aktualisieren des Platzes mit Profildaten,
  Kürzelkonflikt, volle Waage, abgelehnter Messstart, keine Historienbefehle.
- GitHub Actions: Format und Codeanalyse ohne Befunde, 58 Tests erfolgreich,
  Debug-APK gebaut. Kein Hardwaretest, keine signierte Release-APK aus dieser Sitzung.
- Test an der echten Waage offen, siehe [HARDWARE_TEST.md](HARDWARE_TEST.md).

## Version 1.3.1 – Körperwerte live

- 53 automatisierte Tests erfolgreich, Codeanalyse ohne Befunde.
- Paketweiser Empfang zeigt nur vollständig übertragene Werte. Der über zwei
  Pakete verteilte Wasserwert erscheint erst mit dem letzten Paket.
- Transporttests bestätigen Speicherung aller neun Werte im aktiven Profil,
  Vorschau vor Speicherung, Zurücksetzen bei neuer Messung und Verbindungsende
  sowie Verwerfen einer unvollständigen Messung nach Zeitüberschreitung.
- Oberfläche bei 360 dp und 130% Schriftgröße in Hell und Dunkel geprüft.
- Die echte SBF70-Übertragung und Körperwert-Byteinterpretation bleiben hardwareseitig zu prüfen.

## Version 1.3.0 – direkter Empfang

- 49 automatisierte Tests erfolgreich; Tests des entfernten Benutzer-/Historienabgleichs durch Empfangstests ersetzt.
- Codeanalyse und Dart-Formatprüfung ohne Befunde.
- Empfang bestätigt fremde Benutzerkennungen, verwirft unvollständige Pakete und verarbeitet keine historischen Messungen.
- Profildaten bleiben lokal; ausgehende Protokollbefehle sind Anmeldung und Empfangsbestätigungen.
- Bluetooth-Dienste werden explizit neu erkannt; Diensterkennung, Anmeldung und Empfangsbestätigung haben unterscheidbare Fehlertexte.
- Echter passiver Messwertempfang ohne benutzerbezogenen Messstart ist noch nicht hardwarebestätigt. Siehe [HARDWARE_TEST.md](HARDWARE_TEST.md).

## Version 1.2.0

Geprüft am 2. November 2026.

- Alle 62 automatisierten Tests erfolgreich, einschließlich fremder
  Waagen-Benutzerkennungen bei Live-Messungen, des gemeinsamen HealthCoach-Platzes,
  wiederholter Synchronisierung nach Profilwechsel sowie alter Messungskennungen
  und Löschmarkierungen bei Speicherung und Sicherungsimport.
- `flutter analyze`: keine Befunde. Dart-Formatprüfung erfolgreich.
- Android-Integrationstest auf API 34 erfolgreich: Profilformular, manuelle
  Messung, Diagramme, Profiltrennung, Sicherungsabgleich und Datenpersistenz.
- Signierte Release-APK 1.2.0 (Build 5) gebaut, Signatur mit `apksigner` geprüft
  und identisch mit 1.1.1. Android 8+, ARM32/ARM64/x86-64, keine
  Internet-Berechtigung im Release-Manifest.
- Installation als Update über die signierte 1.1.1 und Kaltstart auf dem
  API-34-Emulator erfolgreich.
- Vorherige GitHub-Läufe scheiterten vor den Prüfungen am entfernten SDK-Paket
  `tools`. Der Android-Setup-Schritt installiert jetzt explizit `platform-tools`.
- Review und verbleibende Grenzen: [CODE_REVIEW_1.2.0.md](CODE_REVIEW_1.2.0.md).
- Die echte SBF 70 S-A und das Samsung A17 sind weiterhin nicht geprüft.

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
