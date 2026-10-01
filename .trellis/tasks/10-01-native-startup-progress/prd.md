# Native Startup Progress

## Goal

Reference D:/MyNewProjects/qflistudio to keep a native startup icon/progress
surface visible until Flutter renders the initialized application, removing the
blank interval during startup in PyFlow.

## Requirements

- Native startup uses the product icon and a simple progress bar.
- Progress reflects completion of the three existing local store loads.
- The native surface survives engine initialization and deferred Flutter
  rendering, then hands off only to the ready home frame.
- Match existing light/dark startup backgrounds and avoid a white flash or a
  generic Flutter logo during the handoff.
- Cover HarmonyOS using the main project's FlutterPage splash builder and
  startupProgress event; provide the equivalent Android native loading view.
- Keep startup recoverable if a local load fails or an optional progress
  channel is unavailable.
- Preserve interpreter registration, current agreement handling, and other
  existing user edits.

## Acceptance

- Flutter tests prove progress and first-frame ordering, including failures.
- Flutter analysis and a fresh Android APK build pass.
- Android cold starts show the native product/progress surface followed by the
  usable home page; verify light/dark mode, repeated startup and runtime access.
- HarmonyOS startup source is ported and HAP build validation is attempted;
  do not launch HarmonyOS devices or emulators under the standing user limit.
- Record any unavailable packaging/tooling gate explicitly.
