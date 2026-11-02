# Test mit Sanitas SBF 70 S-A

Dieser Schritt kann im Emulator nicht ersetzt werden. Stand: noch nicht an der
Waage des Nutzers geprüft. Keine Waage zurücksetzen und keine alten Profile löschen.

1. Release-APK auf dem Samsung A17 installieren. Android-Version notieren.
2. In der bisherigen App vorhandenes Waagenkürzel und Profildaten prüfen,
   Hersteller-App dann vollständig schließen. In HealthCoach identische Angaben
   eintragen, um den bestehenden Benutzerplatz wiederzuverwenden.
3. Bluetooth-/Gerätefreigabe erlauben. Waage aktivieren und suchen.
   Erwartung: „SANITAS SBF70“ erscheint, lässt sich verbinden und zeigt „Bereit“.
4. Barfuß vollständig messen. Gewicht, Körperfett, Wasser, Muskeln, Knochenmasse,
   BMR, AMR und BMI auf der Waage mit dem Eintrag vergleichen. Insbesondere
   BMR/AMR in kcal und BMI mit einer Nachkommastelle kontrollieren.
5. App schließen und neu öffnen: Messung bleibt erhalten.
6. Erneut verbinden: derselbe Messzeitpunkt erzeugt keinen zweiten Eintrag.
7. Eine Messung ohne geöffnete App durchführen, dann verbinden: korrekt dem
   Profil zugeordnete gespeicherte Messung wird nachgeladen.
8. Bluetooth ausschalten / Freigabe verweigern: verständlicher Hinweis,
   gespeicherte Daten bleiben bedienbar. Bluetooth wieder einschalten und erneut suchen.
9. Optional ein zweites Profil testen: Werte dürfen nicht beim falschen Profil landen.
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
