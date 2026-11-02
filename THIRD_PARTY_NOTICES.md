# Open-source notices

HealthCoach is distributed under GPL-3.0-or-later. See LICENSE.

## openScale / Beurer and Sanitas protocol

The Dart protocol implementation in `lib/bluetooth/sanitas_protocol.dart` is informed
by the openScale protocol documentation and the BeurerSanitasHandler reference
implementation (GPL-3.0-or-later):

- Copyright (C) 2025 olie.xdev <olie.xdeveloper@googlemail.com>
- https://github.com/oliexdev/openScale
- https://github.com/oliexdev/openScale/wiki/Beurer-Sanitas
- https://github.com/oliexdev/openScale/blob/master/android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales/BeurerSanitasHandler.kt
- Protocol reference inspected 2026-11-02.

The new Dart implementation uses independent transport/storage layers, adds strict
length checks and profile validation, stores BMR/AMR/BMI as transmitted, rejects
out-of-order historical measurement parts, deduplicates timestamps, and does not
send scale measurement/user deletion commands. Upstream's timestamp flag handling
is retained. Synthetic test fixtures are not real hardware captures.

Flutter and package dependencies retain their respective licenses. The Flutter
license page in the app lists package notices. The complete dependency versions
are locked in pubspec.lock. Sanitas and Beurer are trademarks of their respective
owners; this app is an independent project.

## Inter

The bundled Inter variable font is copyright (c) 2016 The Inter Project Authors
(https://github.com/rsms/inter) and distributed under SIL Open Font License 1.1.
The complete license is included at `assets/fonts/OFL.txt` and in the app license page.
