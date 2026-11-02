# Hardwaretest für direkten Empfang (1.3.0)

Die tatsächliche Übertragung ist noch nicht bestätigt. Keine Waagenprofile
löschen oder zurücksetzen. Die App benötigt keine freien Benutzerplätze.

1. Signierte APK 1.3.0 über die vorhandene App installieren.
2. Gewünschtes App-Profil öffnen, Sanitas-App schließen, Waage aufwecken.
3. Waage suchen und auswählen. Erwartung: Anmeldung, dann „Verbunden“.
4. Messung direkt an der Waage starten. App im Vordergrund lassen.
5. Vollständige Messung und Waagendisplay vergleichen, insbesondere BMR/AMR/BMI.
6. Zweites App-Profil wählen und neu verbinden. Neue Messung gehört zum zweiten
   Profil, unabhängig von einer Benutzerkennung auf der Waage.
7. Bluetooth abschalten, wieder einschalten und erneut verbinden.
8. Falls Anmeldung oder Messwertempfang scheitern: Profil → Bluetooth-Diagnose
   speichern. Der Export enthält persönliche Rohdaten, daher nicht öffentlich posten.

Erwartete ausgehende Befehle: Anmeldung E6 01 und E7 F1 als Empfangsbestätigung.
Keine Benutzer-, Historien-, Lösch- oder Messstartbefehle. Eine reine
Gewichtsanzeige ohne vollständiges Messpaket wird nicht automatisch gespeichert.

Das öffentliche SBF70-Protokoll dokumentiert den aktiven Messstart mit Benutzer-ID.
Der passive Empfang ohne diesen Befehl ist eine am Gerät zu prüfende Variante:
https://github.com/oliexdev/openScale/wiki/Beurer-Sanitas
