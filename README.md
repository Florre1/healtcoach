# HealthCoach

Lokale Android-App für die Sanitas SBF 70 / SBF 70 S-A, mit Profilen,
Gewichtsverlauf, Körperwerten, manuellen Einträgen und JSON-/CSV-Export.

## Direkter Bluetooth-Empfang ab 1.3.0

1. Das gewünschte Profil in der App öffnen.
2. Bluetooth einschalten und die Sanitas-App vollständig schließen.
3. Waage aufwecken, „Waage suchen“ wählen und das Gerät antippen.
4. Nach „Verbunden“ die Messung an der Waage starten und die App geöffnet lassen.
5. Eine vollständig übertragene Live-Messung wird im geöffneten App-Profil gespeichert.

Die App sendet keine Profilangaben, fordert keine Benutzerliste oder alten
Messungen an und erstellt, verändert oder löscht keine Waagenbenutzer.
Ein freier Benutzerplatz wird nicht benötigt. Die Benutzerkennung eingehender
Live-Pakete entscheidet nicht über deren Zuordnung. Gerätefreigaben und das
Merken des Bluetooth-Geräts bleiben erforderlich.

Die App sendet nur die Bluetooth-Protokollanmeldung und Empfangsbestätigungen.
Die angezeigte Messzeit ist die Empfangszeit auf dem Handy. Doppelte Pakete werden
lokal unterdrückt. Unvollständige Messungen werden verworfen; die Verbindung bleibt
für den nächsten Versuch offen. Kurzzeitige Gewichtsanzeigen sind noch keine
vollständige gespeicherte Messung.

**Hardwareprüfung offen:** Das dokumentierte Protokoll startet eine Messung per
App mit einer Waagen-Benutzerkennung. Dieser Befehl entfällt hier bewusst.
Ob die konkrete Firmware nach Anmeldung und manuellem Wiegen vollständige
Live-Pakete überträgt, muss an der echten Waage geprüft werden. „Verbunden“ bestätigt
die Anmeldung, nicht die erfolgreiche Messwertübertragung. Wenn nur Gewicht oder
keine Werte eintreffen: unter Profil die Bluetooth-Diagnose speichern.

Profilangaben bleiben lokal. Körperanalysewerte werden nur übernommen, soweit die
Waage sie sendet; die App errechnet keine fehlenden Körperwerte. Offline-Messungen
werden nicht nachgeladen. Android 8+, ARM32/ARM64/x86-64.

Installation: signierte APK aus den [Releases](https://github.com/Florre1/healtcoach/releases)
über die bestehende Installation installieren. Die neue Testversion trägt 1.3.0.

## Daten und Sicherung

Kein Konto, keine Analyse-/Werbedienste, kein Backend. Die Haupt-App fordert keine
Internet-Berechtigung an. Android-Cloudsicherung und automatische
Geräteübertragung sind deaktiviert. Daten liegen im privaten App-Verzeichnis.
**Vor Handywechsel oder Deinstallation eine JSON-Sicherung exportieren.**
JSON- und CSV-Exporte sind unverschlüsselte Dateien am selbst gewählten Speicherort.
Der Diagnoseexport enthält Rohdaten der aktuellen Bluetooth-Sitzung und wird nur
auf ausdrücklichen Tastendruck gespeichert.

Wiederherstellen ergänzt fehlende Einträge in einer Transaktion. Vorhandene
Profile und Messungen bleiben erhalten. Importierte neue Profile müssen ihre
Waage erneut zuordnen. Lokal gelöschte Messungen werden durch erneutes
Synchronisieren nicht wieder angelegt. Die App löscht keine Benutzer oder
gespeicherten Messungen auf der Waage.

## In VS Code entwickeln

Getestete Umgebung: Flutter **3.47.0**, Dart **3.13**, JDK **17**, Android SDK
Platform 36 und NDK 28.2.13676358. Ältere SDK-Plattformen werden für die festgelegten
Plugin-Versionen beim Build zusätzlich benötigt. Flutter kann sie über Gradle
installieren, wenn die SDK-Lizenzen akzeptiert sind.

```powershell
git clone https://github.com/Florre1/healtcoach.git
cd healtcoach
code .
flutter pub get
flutter doctor
flutter devices
flutter run
```

Die Dart-/Flutter-Erweiterungen sind in `.vscode/extensions.json` empfohlen.
Im VS-Code-Gerätewähler ein Android-Handy oder einen Emulator auswählen und F5
drücken. Ein echtes Handy benötigt für diesen Entwicklungsweg USB-Debugging;
für die gewöhnliche APK-Installation ist es nicht notwendig.

```powershell
flutter analyze
flutter test
flutter build apk --debug
# Persönliche Release-Signatur einmalig einrichten (Windows / PowerShell 7):
.\tool\setup-signing.ps1
flutter build apk --release
```

Release-Ausgabe: `build/app/outputs/flutter-apk/app-release.apk`.
Die private Signatur liegt außerhalb des Repositories unter
`%USERPROFILE%/.android/healthcoach-signing/`; Kennwörter/Pfad liegen in der
ignorierten Datei `android/key.properties`. **Beides privat sichern**: spätere
App-Updates müssen mit demselben Schlüssel signiert werden. Schlüssel werden nie
automatisch ersetzt. Ohne Schlüssel erzeugt Gradle keine signierte Release-APK.
CI baut eine separate Debug-APK, die die persönlich signierte App nicht ersetzen kann.

BLE- und Berechtigungspakete sind bewusst festgelegt: neuere Versionen hatten
in dieser Umgebung eine inkonsistente Android-37-SDK-Abhängigkeit. Updates erst
nach Build- und Hardwareprüfung übernehmen.
Der Android-Build hebt für `reactive_ble_mobile` 5.5.0 das Compile-SDK von 33 auf
36 an, damit es zu Flutters AndroidX-Abhängigkeiten passt. Kotlin-Inkrementalität
ist deaktiviert, damit Projekt und Pub-Cache auf unterschiedlichen Windows-Laufwerken
liegen können.

## Tests

`flutter test` prüft Paketdekodierung, Einheiten, Zeitstempel-Flag,
direkten Empfang, fremde Benutzerkennungen, fragmentierte Daten, Duplikate, Profiltrennung,
Sicherung, Wiederherstellung und Tagesaggregation. Testpakete sind synthetisch.

Auf einem laufenden Android-Emulator:

```powershell
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d emulator-5554
```

Der Integrationstest nutzt ausschließlich `healthcoach-integration.db`, führt
einen manuellen Eintrag aus, prüft Diagramme/Profiltrennung/Persistenz und speichert
Screenshots unter `artifacts/screenshots/`. Die eigentliche App-Datenbank wird
dabei nicht gelöscht oder mit Testdaten befüllt.

Für den realen Hardwaretest siehe [docs/HARDWARE_TEST.md](docs/HARDWARE_TEST.md).

## Aufbau

```text
lib/domain/           Profile, Messwerte und Tagesaggregation
lib/data/             SQLite und transaktionale Sicherungen
lib/bluetooth/        Reines SBF70-Protokoll + Android-BLE-Transport
lib/ui/               Übersicht, Diagramme, Formulare, Historie, Einstellungen
lib/app_controller.dart  Profilwechsel und Anwendungsabläufe
```

Alle Messungen haben eine Profil-ID und eine stabile Kennung. Ein späterer
Serverabgleich kann an der Repository-Schicht ergänzt werden; derzeit ist kein
Cloud-Dienst konfiguriert. Ein iPhone-Build ist nicht enthalten.

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE). Die Bluetooth-Implementierung basiert
auf den veröffentlichten Erkenntnissen und der GPL-Referenz von openScale.
Details: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Unabhängiges Projekt,
keine offizielle Sanitas-/Beurer-App.
