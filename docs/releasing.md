# Releasing Photon

The version string lives in one place: the `VERSION` file at the repository root. `Scripts/bump-version.sh` writes that file and `Sources/PhotonCore/PhotonVersion.swift`. `Scripts/package_app.sh` copies the same value into `Photon.app/Contents/Info.plist` at build time.

Do not edit `PhotonVersion.swift` by hand.

## Prerequisites

1. The commit you want to ship is on `main` (merge `develop` via a `release/*` pull request).
2. CI on that commit is green.
3. Repository secrets below are set if you want a Developer ID + notarized build. Without them the workflow still publishes an **ad-hoc signed** GitHub Release and says so in the notes.

### Secrets (`Settings > Secrets and variables > Actions`)

| Secret | Required for | Purpose |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID sign | Base64-encoded `.p12` of the Developer ID Application certificate. |
| `MACOS_CERTIFICATE_PASSWORD` | Developer ID sign | Password for that `.p12`. |
| `APPLE_ID` | Notarization | Apple ID email used for notarization. |
| `APPLE_TEAM_ID` | Notarization | 10-character Team ID. |
| `APPLE_APP_SPECIFIC_PASSWORD` | Notarization | App-specific password for `notarytool`. |
| `HOMEBREW_TAP_TOKEN` | Cask bump | Fine-grained (or classic) PAT that can push to [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps). Contents: write. |

The tap token is **not** the default `GITHUB_TOKEN`. A workflow in `photon` cannot push to `homebrew-taps` without a PAT.

## Cut a release

```sh
git checkout develop
git pull
Scripts/bump-version.sh 0.1.0
git add VERSION Sources/PhotonCore/PhotonVersion.swift
git commit -m "chore(release): 0.1.0"
# open a PR to develop, merge, then:
git checkout -b release/0.1.0
# PR release/0.1.0 into main, merge (linear history)
git checkout main
git pull
git tag -a v0.1.0 -m "Photon 0.1.0"
git push origin v0.1.0
```

Pushing a `v*.*.*` tag starts `.github/workflows/release.yml`. The tag **must** match `VERSION` (`v0.1.0` ↔ `0.1.0`).

The workflow:

1. Builds `Photon.app` (Release).
2. Signs with Developer ID, notarizes, and staples when the Apple secrets are all present; otherwise ad-hoc signs.
3. Writes `Photon-<version>.zip`, `Photon-<version>.dmg`, and `SHA256SUMS`.
4. Creates a GitHub Release with generated notes plus a signing caveat.
5. If `HOMEBREW_TAP_TOKEN` is set, clones `RyanStoffel/homebrew-taps` and updates `Casks/photon.rb` (`version`, `sha256`, URL `Photon-#{version}.zip`).

Phase 1 does not cut a release. The first public tag is a Phase 3 job.

## Homebrew

Install line once the first release exists:

```sh
brew install --cask ryanstoffel/taps/photon
```

The cask token is `photon`. The tap repository is [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps) (`brew tap ryanstoffel/taps`).
