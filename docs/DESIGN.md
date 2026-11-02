# HealthCoach Glass

[Dashboard](screenshots/dashboard.png) · [Verlauf](screenshots/trends.png) ·
[Profil](screenshots/profile.png) — Android screenshots with synthetic test data.

Native Flutter implementation of the supplied `HealthCoach Glass.dc.html`
handoff and its `GlassPhone.dc.html` component. `support.js` was reviewed: it
is the browser prototype runtime, not a dependency of the Android app.
The requested Claude Design MCP was unavailable in the session, so the supplied
ZIP export was used as the design source. No `/design-login` or live MCP import
was performed.

## Mapping

- Black canvas with green, lime and blue ambient radial gradients.
- Glass panels: 26 px corners, 29 px backdrop blur, white gradient at 10–4.5%
  opacity and a fine translucent border. Hero panels use 30 px corners and lime tint.
- Floating four-tab navigation: 24 px blur, animated selection, Cupertino icons,
  bottom inset for Android's own system navigation.
- Local Inter variable font, 34 px large titles, 60 px weight hero and goal ring.
- Touch selection in charts, month groups in measurement history, grouped settings
  and modal glass surfaces for scale setup, measurements and profile forms.
- Default dark mode for new settings; existing explicit theme preferences remain
  respected. A matching light appearance remains available.

The HTML phone bezel, fixed status bar, example people, sample dates and simulated
Bluetooth flows are presentation fixtures. Production views use AppController,
SQLite and the existing real BLE state machine. Forms keep real validation,
date/time selection, optional metrics and profile isolation. No web runtime or
online fonts are loaded by the app.

## Verification

Automated UI checks cover all four tabs at 360 logical pixels and 130% text scale
in both appearances. Set `--dart-define=GLASS_PREVIEW=true` when running
`test/glass_ui_test.dart` to write synthetic preview images to ignored artifacts.

The Android integration test covers onboarding, manual decimal-comma entry,
charts, measurement details, profile switching and persistence. The Windows
emulator's Impeller screenshot path terminated the emulator; the integration
test completed using software GLES with `--no-enable-impeller`. This emulator
workaround does not change the production renderer configuration.
