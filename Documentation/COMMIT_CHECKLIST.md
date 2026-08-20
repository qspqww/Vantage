# Commit Checklist

Use this checklist before creating a commit.

## Scope

- [ ] The change is limited to the requested behavior and its supporting documentation.
- [ ] Source, tests, scripts, and documentation follow the existing project boundaries.
- [ ] No generated files, local caches, signing artifacts, or screenshots are included.

## Validation

- [ ] `swift test` passes.
- [ ] The affected UI state has been checked at the default window size and with the Inspector visible.
- [ ] If packaging changed, `SKIP_SIGN=1 ./Scripts/package_app.sh release` completes.
- [ ] The packaged app contains `Contents/Resources/Vantage_Vantage.bundle` when localization resources are involved.
- [ ] A signed local build passes `codesign --verify --deep --strict --verbose=2 dist/Vantage.app` when a development identity is available.
- [ ] `.github/workflows/macos.yml` keeps unsigned builds separate from the protected signing job.

## Documentation

- [ ] `README.md` still describes the supported workflow and commands.
- [ ] `ARCHITECTURE.md` reflects runtime or data-flow changes.
- [ ] `UI_DESIGN.md` reflects user-facing layout or interaction changes.
- [ ] New localization keys exist in both language catalogs.

## Commit Message

Use a short imperative subject with one purpose, for example:

```text
Stabilize capture status during background refresh
```
