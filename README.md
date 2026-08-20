# Vantage

Vantage is a native macOS SwiftUI utility for monitoring and switching between multiple game client windows. Its workflow is inspired by EVE-O Preview while using macOS-native window capture, accessibility, overlays, and settings.

## Requirements

- macOS 14 or later
- Xcode 26.6 or later; the current project is verified with Swift 6.3
- Screen Recording permission for live previews
- Accessibility permission for raising a specific target window

## Features

- Discovers windows only when the complete application name or complete Bundle ID matches the configured allowlist. Window titles are not used for discovery.
- Excludes off-screen windows, non-zero window layers, empty-title utility surfaces, and undersized helper windows before capture. Only exact application names and Bundle IDs in the allowlist are eligible.
- Captures live window thumbnails with ScreenCaptureKit.
- Provides persisted `1 / 2 / 4 / 8 FPS` capture refresh presets, defaulting to 4 FPS.
- Resolves activation by the captured `CGWindowID` when the target application exposes it through Accessibility, then falls back to unique exact title and geometry matches. It activates only the owning process and raises the target through Accessibility APIs.
- Shows a separate active-window marker based on the actual frontmost system window; selection state and activation state are not conflated.
- Reports permission, process, and target-resolution failures instead of silently falling back to an incorrect window.
- Shows optional draggable, always-on-top preview panels across Spaces and full-screen apps.
- Can switch to the corresponding client automatically when a floating preview is clicked; the preview remains non-activating so another preview can switch back with one click.
- Floating previews expose right-click menus for common size and opacity presets; dragging a panel does not activate its client.
- Supports grid, vertical, and horizontal overlay arrangements.
- Uses compact, fixed-width main previews that add columns as space allows without stretching cards into the Inspector.
- Uses a restrained macOS utility palette: neutral surfaces, one selected accent, and status colors only for success, warning, and error.
- Uses a task-focused workspace layout with a sidebar, preview grid, and optional collapsed Inspector; decorative grid backgrounds and duplicate metadata are intentionally omitted.
- Persists opacity, preview size, refresh rate, layout, accent, metadata, exact application identity filters, and draggable floating-preview positions.
- Supports runtime switching between English and Simplified Chinese from Settings; all application labels, menus, statuses, and activation errors use the selected language.
- Provides native menu commands and `Command + 1-9` window switching.
- Protects against stale asynchronous refresh results when the user refreshes or changes filters quickly.
- Keeps the empty state stable during background refreshes; the loading view is shown only for the initial scan.
- Offers direct links to the exact macOS Privacy & Security panels needed for Screen Recording and Accessibility.

## Build and test

```sh
swift test
SKIP_SIGN=1 ./Scripts/package_app.sh release
```

The unsigned application bundle is written to `dist/Vantage.app`. The package script places the generated SwiftPM resource bundle in `Contents/Resources` so runtime localization works in the packaged app.

For a signed local development build, install an Apple Development certificate in the login keychain and run:

```sh
./Scripts/package_app.sh release
```

## Permissions

On first launch, authorize Vantage in:

- System Settings > Privacy & Security > Screen & System Audio Recording
- System Settings > Privacy & Security > Accessibility

After changing Screen Recording permission, restart Vantage.

## Project layout

- `Sources/Vantage/Models`: captured-window and filtering models
- `Sources/Vantage/Services`: ScreenCaptureKit, Accessibility, settings, overlays, and localization
- `Sources/Vantage/Views`: SwiftUI application views and shared visual rules
- `Sources/Vantage/Resources/Localization`: English and Simplified Chinese catalogs
- `Config/Info.plist`: application bundle metadata and privacy usage descriptions
- `Scripts/package_app.sh`: release build, resource copying, icon generation, app bundle assembly, and signing
- `Tests/VantageTests`: focused behavior tests
- `Documentation/DEVELOPMENT.md`: source layout, development, localization, and packaging workflow
- `Documentation/COMMIT_CHECKLIST.md`: pre-commit validation checklist
- `Documentation/GITHUB_ACTIONS.md`: CI, signing secrets, and tagged release workflow

For runtime boundaries and data flow, see [ARCHITECTURE.md](ARCHITECTURE.md). For layout and interaction decisions, see [UI_DESIGN.md](UI_DESIGN.md).
