# Codebewertung 1.2.0

Geprüft am 2. November 2026. Umfang: Änderungen seit 1.1.1 sowie die betroffenen
Speicher-, Verbindungs- und Profilwechselpfade.

## Ergebnis

Das Hauptziel ist im Code umgesetzt: Eine vollständige Live-Messung wird dem
aktiven App-Profil zugeordnet, unabhängig von der Benutzerkennung im Waagenpaket.
Ein Profilwechsel trennt die laufende Sitzung, bevor ein anderes Profil aktiv wird.
Der eigene HealthCoach-Benutzerplatz wird mit den aktuellen Körperdaten beschrieben;
bestehende fremde Benutzer werden nicht anhand persönlicher Angaben ausgewählt.
Bei belegtem Kürzel wird ein freies Ersatzkürzel verwendet.

Die Trennung von Protokoll, BLE-Transport, Speicherung und Oberfläche ist klar.
Paketlängen, Reihenfolge, Wiederholungen und Sitzungswechsel sind abgesichert.
Die automatisierten Tests prüfen auch fremde Live-Benutzerkennungen und das
erneute Laden derselben Messung nach einem App-Profilwechsel.

## Gefundene und behobene Probleme

- **P1 – Kennungswechsel umging Duplikat- und Löschschutz:** Alte Messungen
  verwendeten `scale:<profil>:<sekunden>`, neue verwenden `scale:<sekunden>`.
  Vor der Korrektur wurden alte gespeicherte oder gelöschte Messungen beim
  Einlesen derselben Messung unter neuer Kennung erneut angelegt. Regressionstests
  reproduzierten beide Fälle. Speicherung und Sicherungsimport erkennen jetzt
  beide Kennungsformen, ohne bestehende Datensätze umzuschreiben.
- **P2 – Veraltete Anleitung:** Oberfläche und Hardwaretest beschrieben noch den
  Abgleich vorhandener Waagenprofile. Die Hinweise erklären jetzt das aktive
  App-Profil und den eigenen HealthCoach-Platz.
- **P2 – CI brach vor den Prüfungen ab:** Die bisherigen GitHub-Läufe scheiterten
  im Android-Setup am nicht mehr verfügbaren Paket `tools`. Der Workflow fordert
  jetzt explizit `platform-tools` an.

## Verbleibende Grenzen

- Ein freier Benutzerplatz wird beim ersten Verbinden weiterhin benötigt. Das ist
  eine Voraussetzung des aktuellen Protokollablaufs. Eine volle Waage wird mit
  einer verständlichen Meldung abgewiesen, ohne Benutzer automatisch zu löschen.
- Offline-Messungen des gemeinsamen HealthCoach-Platzes gehen beim nächsten
  Verbinden in das dann aktive App-Profil. Eine automatische Personenerkennung
  ist bewusst nicht vorgesehen. Speicher anderer Waagenbenutzer werden nicht gelesen.
- Messungskennungen basieren auf Sekunden und enthalten keine Gerätekennung.
  Gleichzeitige Messungen verschiedener Waagen können daher kollidieren. Für
  mehrere Waagen wäre eine gerätebezogene Kennung samt Migration erforderlich.
- Firmware, Funkverbindung und BMR/AMR/BMI müssen weiterhin an der realen SBF 70
  S-A geprüft werden. Synthetische Pakete und Emulator ersetzen diesen Test nicht.
- Der Android-Build meldet eine zukünftige Flutter-Inkompatibilität des
  Kotlin-Gradle-Plugins von `reactive_ble_mobile` 5.5.0. Ein späteres Flutter-Upgrade
  benötigt deshalb eine erneute Plugin- und Buildprüfung.

Die Version wird wie die bisherigen Releases als Vorabversion veröffentlicht.
Die ausgeführten Prüfungen stehen in [VALIDATION.md](VALIDATION.md).
