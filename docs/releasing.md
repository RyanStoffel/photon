# Releasing Photon

The version string lives in one place: the `VERSION` file at the repository root. `Scripts/bump-version.sh` writes that file and `Sources/PhotonCore/PhotonVersion.swift`. `Scripts/package_app.sh` copies the same value into `Photon.app/Contents/Info.plist` at build time.

Do not edit `PhotonVersion.swift` by hand.

## Prerequisites

1. `CHANGELOG.md` has a `## [X.Y.Z] - YYYY-MM-DD` section for the version. The release workflow refuses to tag-build without one; that section becomes the body of the GitHub Release notes.
2. The commit you want to ship is on `main` (merge `develop` via a `release/*` pull request).
3. CI on that commit is green, including the `smoke` job.
4. Repository secrets below are set if you want a Developer ID + notarized build. Without them the workflow still publishes an **ad-hoc signed** GitHub Release and says so in the notes.

### Secrets (`Settings > Secrets and variables > Actions`)

| Secret | Required for | Purpose and how to obtain |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID sign | Base64 of a `.p12` export of the **Developer ID Application** certificate and its private key. In Keychain Access select the certificate, File > Export Items, choose `.p12`, set a password, then `base64 -i cert.p12 \| pbcopy`. |
| `MACOS_CERTIFICATE_PASSWORD` | Developer ID sign | The password chosen when exporting that `.p12`. |
| `APPLE_ID` | Notarization | Apple ID email of the developer account. |
| `APPLE_TEAM_ID` | Notarization | 10-character Team ID from [developer.apple.com/account](https://developer.apple.com/account) (Membership details). |
| `APPLE_APP_SPECIFIC_PASSWORD` | Notarization | App-specific password for `notarytool`, created at [account.apple.com](https://account.apple.com) under Sign-In and Security > App-Specific Passwords. |
| `HOMEBREW_TAP_TOKEN` | Cask bump | Fine-grained PAT scoped to [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps) with **Contents: read and write**. Create it at Settings > Developer settings > Fine-grained tokens. |

All five Apple secrets are needed for a notarized build. With only the two certificate secrets the app is Developer ID signed but not notarized, and the notes say so. With none of them the app is ad-hoc signed.

The tap token is **not** the default `GITHUB_TOKEN`. A workflow in `photon` cannot push to `homebrew-taps` without a PAT. When the token is missing the cask step logs a notice and the release still succeeds; bump `Casks/photon.rb` by hand (see [Homebrew](#homebrew)).

## Dry run

Before tagging, run the release workflow by hand: **Actions > Release > Run workflow** (pick `develop` or the release branch), or

```sh
gh workflow run release.yml -R RyanStoffel/photon --ref develop
```

A manual run builds, signs, packages, smoke-tests, and writes the release notes exactly like a tag build, then uploads `Photon-<version>-dry-run` (zip, dmg, `SHA256SUMS`, `RELEASE_NOTES.md`) as a workflow artifact. It creates no tag, no GitHub Release, and no cask commit. Download the artifact, read `RELEASE_NOTES.md`, and open the app on a Mac if one is available.

## Cut a release

```sh
git checkout develop
git pull
Scripts/bump-version.sh 0.1.0
# add the 0.1.0 section to CHANGELOG.md
git add VERSION Sources/PhotonCore/PhotonVersion.swift CHANGELOG.md
git commit -m "chore(release): 0.1.0"
# open a PR to develop, merge, then:
git checkout -b release/0.1.0 origin/develop
git push -u origin release/0.1.0
# PR release/0.1.0 into main, squash-merge (main requires linear history), then:
git checkout main
git pull
git tag -a v0.1.0 -m "Photon 0.1.0"
git push origin v0.1.0
```

Pushing a `v*.*.*` tag starts `.github/workflows/release.yml`. The tag **must** match `VERSION` (`v0.1.0` ↔ `0.1.0`).

The workflow:

1. Checks the tag against `VERSION` and that `CHANGELOG.md` has a section for it.
2. Builds `Photon.app` (Release, universal `arm64` + `x86_64`).
3. Signs with Developer ID, notarizes, and staples when the Apple secrets are all present; otherwise ad-hoc signs.
4. Writes `Photon-<version>.zip`, `Photon-<version>.dmg`, and `SHA256SUMS`.
5. Unpacks the zip and runs `Scripts/smoke-test.sh` against it (see below).
6. Creates a GitHub Release from `CHANGELOG.md` plus a signing section and install instructions (`Scripts/release-notes.sh`). Versions `0.y.z` are published as **pre-releases**.
7. If `HOMEBREW_TAP_TOKEN` is set, clones `RyanStoffel/homebrew-taps` and updates `Casks/photon.rb` (`version`, `sha256`, URL `Photon-#{version}.zip`). Otherwise it logs a notice and skips.

After the release, open a PR that merges `main` back into `develop` if `main` received anything `develop` does not have (the squash commit itself is fine to leave).

## Smoke test

`Scripts/smoke-test.sh [Photon.app]` is the only runtime check that runs without a person. It verifies the code signature and `Info.plist`, launches the bundle with `open`, waits eight seconds (`SMOKE_WAIT_SECONDS`), and fails if the process is gone, macOS wrote a `Photon*.ips` crash report, or the unified log contains a Swift fatal error or an uncaught exception (AppKit swallows those on the main run loop, so the process survives while startup silently stops). CI runs it as the `smoke` job on every PR against the artifact of the `build` job; the release workflow runs it against the zip it is about to publish. The log excerpt is uploaded as the `smoke-test-log` artifact.

It does not click anything. Hotkeys, the launcher panel, clipboard capture, and window management still need a manual pass on a Mac.

## Homebrew

Install line:

```sh
brew tap ryanstoffel/taps
brew install --cask ryanstoffel/taps/photon
```

The cask token is `photon`. The tap repository is [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps) (`brew tap ryanstoffel/taps`).

Homebrew 7 introduced tap trust: casks from third-party taps load only when the tap (or cask) has been trusted with `brew trust`, or when the fully qualified name is on the command line. The install line above therefore works untrusted, while `brew install --cask photon` and `brew upgrade` need `brew trust ryanstoffel/taps` first. `brew tap` itself succeeds untrusted on macOS.

Checks that work without a Mac (Homebrew on Linux cannot install casks): `brew readall ryanstoffel/taps`, `brew style ryanstoffel/taps`, and `brew audit --cask --strict --online ryanstoffel/taps/photon` (the audit needs a `plutil` on `PATH`; on Linux a small `plistlib` shim is enough). The strict audit reports that the version is a GitHub pre-release; that rule is written for homebrew/cask and is expected here while releases are `0.y.z`.

To bump by hand after a release: take the zip line from `SHA256SUMS` on the GitHub Release, then edit `version` and `sha256` in `Casks/photon.rb` and push (or let `Scripts/update-homebrew-cask.sh` do it with `HOMEBREW_TAP_TOKEN=<pat> VERSION=<x.y.z>` and `dist/SHA256SUMS` present).
