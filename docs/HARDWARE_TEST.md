# Hardwaretest für Körperwerte (1.3.2)

1.3.0/1.3.1 haben nur das Gewicht empfangen: Ohne Benutzerangaben berechnet die
Waage keine Körperzusammensetzung. 1.3.2 richtet dafür wieder einen eigenen
HealthCoach-Benutzerplatz ein und startet die Messung für diesen Platz.

1. Signierte APK 1.3.2 über die vorhandene App installieren.
2. Gewünschtes App-Profil öffnen, Sanitas-App schließen, Waage aufwecken.
3. Waage suchen und auswählen. Erwartung beim ersten Mal: „Die Waage wird für
   HealthCoach eingerichtet.“, danach „Bereit. Steige barfuß auf die Waage.“
4. Barfuß aufsteigen, App im Vordergrund lassen.
5. Live-Empfang: alle neun Werte müssen ankommen. Mit dem Waagendisplay
   vergleichen, insbesondere Fett, Wasser, Muskeln, BMR/AMR/BMI.
6. Zweites App-Profil wählen und neu verbinden. Die Waage rechnet nun mit dessen
   Größe/Alter/Geschlecht; die Messung gehört zum zweiten Profil.
7. Erscheint „Verbunden, nur Gewicht: …“, konnte der Platz nicht eingerichtet
   werden (Grund steht dahinter). Dann Profil → Bluetooth-Diagnose speichern.
   Der Export enthält persönliche Rohdaten, daher nicht öffentlich posten.

Ausgehende Befehle: E6 01 (Anmeldung), E9 (Uhrzeit), E7 4F (Status), E7 33
(Benutzerliste), E7 31 bzw. E7 35 (HealthCoach-Platz anlegen/aktualisieren),
E7 40 (Messstart), E7 F1 (Empfangsbestätigung). Keine Historien- oder
Löschbefehle; andere Waagenbenutzer bleiben unverändert. Gespeicherte Messungen
sammeln sich im HealthCoach-Platz der Waage und werden von der Waage selbst
überschrieben, wenn ihr Speicher voll ist.

Protokollreferenz: https://github.com/oliexdev/openScale/wiki/Beurer-Sanitas
