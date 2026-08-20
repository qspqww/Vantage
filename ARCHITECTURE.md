# Architecture

## Runtime boundaries

`WindowCaptureService` owns the ScreenCaptureKit lifecycle. It discovers eligible windows, produces size-bounded snapshots, publishes immutable `CapturedWindow` values, and owns the selected-window state.

The capture loop uses the persisted `PreviewRefreshRate` setting. Each cycle measures capture work and waits only for the remaining portion of the interval, so screenshot latency is not added on top of the configured refresh period. Changing the rate through either the Inspector or an overlay context menu cancels the current wait and immediately starts a loop using the new interval.

`AccessibilityService` is intentionally stateless. It first resolves the captured `CGWindowID` through the AX window-number attribute when available, then falls back to a unique exact title and geometry match before activating the owning process and raising that target. It does not use coordinate hit-testing or activate all windows from the process, so an unresolved target is reported instead of falling back to an unrelated window.

`OverlayWindowController` is the AppKit boundary. It creates one borderless `NSPanel` per captured window and hosts the shared SwiftUI preview component in each panel. It does not own capture state, so the main grid and floating panels always render the same published snapshot.

Floating panel context menus are owned by an AppKit `OverlayHostingView` and built as native `NSMenu` instances. This keeps menu lifetime independent from the ScreenCaptureKit refresh stream and prevents size/opacity menus from flickering while thumbnails update.

Floating preview clicks pass through `SettingsStore.activateOnOverlayClick`. The main grid always activates a selected window, while floating panels can be configured to select without activating. Overlay panels accept the first click without becoming key, never render the main workspace's selected state, and explicitly leave Vantage inactive after switching so another preview can switch back with one click. Compact overlay cards expose persisted size and opacity presets through their context menu, and a drag-distance guard prevents a panel move from being interpreted as a client activation. Each panel saves its origin under a stable application, exact-title, instance, and geometry key, restores that origin on launch, and clamps it to the current screen when display geometry changes.

`SettingsStore` owns persisted user preferences. Capture pause is session-only; window matching, overlay appearance, and floating-panel positions persist in `UserDefaults`.

`Localization` loads English and Simplified Chinese catalogs from the SwiftPM resource bundle. In a packaged app, the bundle is copied into `Contents/Resources` and resolved through the main application bundle first, with `Bundle.module` retained as the development fallback. `SettingsStore.language` is persisted and published, so SwiftUI views and AppKit overlay menus update immediately when the user changes the language.

The main SwiftUI surface is intentionally task-focused: the sidebar handles discovery, the workspace handles comparison and activation, and the Inspector is optional and collapsed by default. Preview cards use a separate metadata footer in the main grid and a compact bottom overlay only for floating panels.

`WindowCaptureService` tags every asynchronous refresh with a monotonically increasing sequence. A slower ScreenCaptureKit request is discarded when a newer manual refresh or settings change has already started, so stale window lists cannot replace current state.

The main workspace shows the loading state only before the first completed refresh. Later refresh cycles update data in place, so an empty result does not alternate between “scanning” and “no matching windows.”

## Data flow

1. `WindowCaptureService` reads `SCShareableContent` on its refresh loop.
2. `WindowFilter` applies exact owner-name and exact bundle-identifier rules, then rejects off-screen, non-zero-layer, empty-title, or undersized surfaces. Window titles are never used as discovery keywords, and there is no setting that bypasses application identity filtering.
3. `SCScreenshotManager` produces a bounded snapshot for every accepted window.
4. SwiftUI updates the sidebar and preview grid from the published window list.
5. `OverlayWindowController` reconciles the same list with floating AppKit panels, restoring saved positions and placing new panels in the first available non-overlapping slot.
6. A preview click calls `AccessibilityService` through `WindowCaptureService.select`.
7. Accessibility activation prefers the captured `CGWindowID`, then requires a unique exact title and geometry match; it never uses an unrelated coordinate hit-test fallback.

Window activation returns a typed result to `WindowCaptureService`. Permission, process-lifetime, and target-resolution failures are surfaced to the user instead of being treated as successful selection.

Permission actions use the native macOS request APIs and also provide direct Privacy & Security deep links for Screen Recording and Accessibility. This keeps the first-run flow inside the application while still taking the user to the exact system panel when macOS requires manual approval.

## Packaging

Swift Package Manager builds the executable. `Scripts/package_app.sh` assembles the standard macOS bundle structure, copies the generated SwiftPM resource bundle into `Contents/Resources`, generates a multi-resolution icon, copies `Info.plist`, and optionally signs with an Apple Development identity from the local keychain. Signing must be performed as the regular logged-in user.
