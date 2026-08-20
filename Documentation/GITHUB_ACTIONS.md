# GitHub Actions

The repository includes `.github/workflows/macos.yml` for repeatable macOS builds.

## Workflow Behavior

- Pull requests and pushes to `main` run tests and create an unsigned `.app` artifact.
- Tags matching `v*` run tests, package the app, pass the archive to a protected signing job, import the certificate into a temporary keychain, sign the app, and publish a GitHub release with a ZIP archive.
- A manual `workflow_dispatch` run can create a signed archive by setting `sign` to `true`.
- Fork pull requests never receive signing secrets and therefore remain unsigned.

The workflow uses the `macos-15` hosted runner and explicitly selects Xcode 16.4. This prevents the runner default from selecting Swift 5.10, which cannot load the package's Swift tools version 6.1 manifest. Keep the runner label and selected Xcode version aligned with the project's supported toolchain.

## Required Secrets

Configure these secrets in a protected GitHub environment named `release`:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` containing the distribution certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` file |
| `MACOS_KEYCHAIN_PASSWORD` | Random password used for the ephemeral CI keychain |
| `MACOS_SIGNING_IDENTITY` | Exact signing identity, normally `Developer ID Application: ...` for distribution or `Apple Development: ...` for development builds |

The signing job validates all four signing secrets before creating a keychain, prints the identities imported into that temporary keychain, and passes the keychain explicitly to `codesign`. If a tag build reports missing secrets, check the `release` environment rather than the local machine. Listing secret names without exposing values:

```sh
gh secret list --repo qspqww/Vantage --env release
```

Create the base64 value on macOS without committing the certificate:

```sh
base64 -i DeveloperID.p12 | pbcopy
```

Paste the clipboard value into `MACOS_CERTIFICATE_P12_BASE64`. Store the other values directly as encrypted environment secrets. Add required reviewers to the `release` environment when tags can be pushed by multiple maintainers. The signing job uses a temporary keychain and removes it even when a later step fails.

`MACOS_SIGNING_IDENTITY` must exactly match one of the identities printed by `security find-identity -v -p codesigning` for the exported `.p12`. For example:

```text
Developer ID Application: Example Company (ABCDE12345)
```

Do not use a certificate name from a different keychain or replace the full identity with only `Developer ID Application`.

## Release Flow

Create and push a version tag after the change has passed review:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow verifies the signed app, creates `Vantage-v0.1.0.zip`, and attaches it to the matching GitHub release. Signing and release publishing are intentionally limited to version tags; ordinary branch builds cannot use the private certificate. The manual workflow can sign only after the `release` environment policy allows it.

## Notarization

This workflow signs the app but does not submit it to Apple's notary service. Add a separate notarization step after signing when the app is ready for external distribution. That step should use an App Store Connect API key or an Apple ID app-specific password stored as protected secrets, then run `xcrun notarytool` and `xcrun stapler` before publishing the archive.
