# Development Guide

## Source Layout

```text
Config/                         App bundle metadata
Documentation/                  Development and release workflow
Scripts/                        Build, packaging, and icon generation tools
Sources/Vantage/Models/         Window and filtering models
Sources/Vantage/Services/       Capture, accessibility, settings, overlays, and localization
Sources/Vantage/Views/          SwiftUI views and shared visual rules
Sources/Vantage/Resources/      English and Simplified Chinese catalogs
Tests/VantageTests/             Focused behavior tests
```

Generated files are kept outside the source tree in `.build/` and `dist/`. Both paths are excluded by `.gitignore`.

## Local Development

Requirements:

- macOS 14 or later
- Xcode 26.6 or later
- Swift 6.3 or later

Run the test suite from the repository root:

```sh
swift test
```

The application requires Screen Recording permission to capture previews and Accessibility permission to raise an exact target window. The permissions can be granted from System Settings > Privacy & Security.

## Packaging

Build an unsigned local bundle:

```sh
SKIP_SIGN=1 ./Scripts/package_app.sh release
```

Build and sign a local development bundle:

```sh
./Scripts/package_app.sh release
```

The script creates `dist/Vantage.app`, copies the generated SwiftPM resource bundle into `Contents/Resources`, generates `AppIcon.icns`, and optionally signs the bundle with the first Apple Development identity in the login keychain.

Signing must be performed as the regular logged-in user. A development signature is suitable for local testing; distribution signing and notarization are separate release steps.

## Localization

English is the source language for identifiers, comments, and documentation. User-facing strings live in:

- `Sources/Vantage/Resources/Localization/en.json`
- `Sources/Vantage/Resources/Localization/zh-Hans.json`

When adding a string, add the English key first and provide the matching Simplified Chinese value in the same change. SwiftUI and AppKit surfaces should resolve text through `SettingsStore.localized` or `L10n.string` rather than embedding user-facing literals.

## Change Review

Before committing, follow [COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md). Keep changes scoped to the affected layer, update the relevant architecture or UI documentation when behavior changes, and avoid committing `.build/` or `dist/` output.

For CI signing and tagged releases, see [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md).
