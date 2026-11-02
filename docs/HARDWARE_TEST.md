# Test mit Sanitas SBF 70 S-A

Dieser Schritt kann im Emulator nicht ersetzt werden. Stand: noch nicht an der
Waage des Nutzers geprüft. Keine Waage zurücksetzen und keine alten Profile löschen.

1. Release-APK auf dem Samsung A17 installieren. Android-Version notieren.
2. Hersteller-App vollständig schließen. In HealthCoach die eigenen Körperdaten
   eintragen und das gewünschte App-Profil öffnen. Ein Abgleich mit vorhandenen
   Waagenprofilen ist nicht nötig. HealthCoach benötigt einmalig einen freien
   Benutzerplatz; vorhandene Benutzer werden nicht verändert.
3. Bluetooth-/Gerätefreigabe erlauben. Waage aktivieren und suchen.
   Erwartung: „SANITAS SBF70“ erscheint, lässt sich verbinden und zeigt „Bereit“.
4. Barfuß vollständig messen. Gewicht, Körperfett, Wasser, Muskeln, Knochenmasse,
   BMR, AMR und BMI auf der Waage mit dem Eintrag vergleichen. Insbesondere
   BMR/AMR in kcal und BMI mit einer Nachkommastelle kontrollieren.
5. App schließen und neu öffnen: Messung bleibt erhalten.
6. Erneut verbinden: derselbe Messzeitpunkt erzeugt keinen zweiten Eintrag.
7. Eine Messung ohne geöffnete App auf dem HealthCoach-Benutzerplatz durchführen,
   dann verbinden: Die gespeicherte Messung wird in das jetzt geöffnete App-Profil
   geladen. Messungen anderer Benutzerplätze werden nicht aus deren Speicher gelesen.
8. Bluetooth ausschalten / Freigabe verweigern: verständlicher Hinweis,
   gespeicherte Daten bleiben bedienbar. Bluetooth wieder einschalten und erneut suchen.
9. Ein zweites App-Profil öffnen und erneut verbinden: Bereits importierte Werte
   bleiben im ersten Profil. Eine neue Live-Messung landet ausschließlich im jetzt
   geöffneten Profil, auch wenn die Waage einen anderen Benutzer meldet. Bei gleichem
   Kürzel wie ein bestehender Waagenbenutzer muss HealthCoach auf HC/HC1… ausweichen.
10. JSON-Sicherung und CSV exportieren. Eine Wiederherstellung derselben Sicherung
    darf keine Duplikate erzeugen.

Falls ein Schritt fehlschlägt: Profil → Bluetooth-Diagnose speichern. Dazu den
letzten sichtbaren App-Hinweis und die Anzeige der Waage notieren. Das Protokoll
enthält persönliche Rohdaten und sollte nicht öffentlich als GitHub-Issue angehängt werden.

## Bekannte Grenzen der ersten Version

- Keine Hintergrundsuche bei geschlossener App.
- Keine automatische Zuordnung unbekannter Messungen aus dem Waagenspeicher.
- Keine Lösch-/Reset-Kommandos an die Waage. Ist deren Speicher voll, muss das
  Speicherverhalten beim Hardwaretest geprüft werden; die App löscht nichts ungefragt.
- Nur das SBF70-Protokoll; gleiche GATT-UUIDs allein sind kein Kompatibilitätsnachweis.
- Android 8+ vorgesehen; bislang Emulatorprüfung, kein vollständiger Gerätepark.
- Firmwarevarianten mit abweichenden Datenframes werden nicht stillschweigend interpretiert.
