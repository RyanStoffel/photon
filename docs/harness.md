# Parity harness

Photon has two required test layers.

`Scripts/check-harness.sh` runs focused Swift fixtures for compact launcher geometry, anchored resizing and snap math, clipboard filtering/persistence, app and System Settings metadata, `ember` file ranking and home scope, notes, configurable shortcuts, and window layouts. CI also runs the complete `swift test` suite.

`Scripts/check-native-parity.sh build/Photon.app` runs only on macOS and tests the packaged application as a process. It:

- verifies `LSUIElement`, `.accessory` activation policy, a visible `NSStatusItem`, and its menu;
- opens clipboard history with the real global `Cmd+Shift+V` registration;
- inspects the actual `LauncherPanel` style, traffic-light state, floating level, frame, and corresponding `CGWindow`;
- posts a mouse click, arrows, and text, then checks that expansion and filtering keep the top edge fixed;
- cycles clipboard rows, dismisses/reopens the session, and enters clipboard from launcher search;
- opens the launcher through a non-system-reserved configured hotkey and verifies application bundle icon resolution;
- changes the system appearance while Photon remains running and verifies both effective appearance and resolved colors update;
- attempts Accessibility window introspection when the runner grants it, with `CGWindow` as the non-TCC fallback.

The app-side reporter is inert unless `PHOTON_NATIVE_PARITY_REPORT_PATH` is set. The harness also sets `PHOTON_ISOLATED_DATA_ROOT`, so it never reads or modifies the normal Photon profile.

`Scripts/screenshots.sh` captures every real built scenario in light and dark appearance. `Scripts/check-screenshot-compact.sh` rejects traffic-light-like title chrome and oversized empty-launcher captures.
