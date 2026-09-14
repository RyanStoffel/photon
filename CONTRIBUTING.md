# Contributing to Photon

Photon is a small, macOS-only launcher. Keep changes focused, native-feeling, and easy to review.

## Branching model

- `develop` is the default integration branch. Day-to-day work targets `develop`.
- `main` is the release branch. Only merge `develop` (or a `release/*` branch) into `main` when cutting a release.
- Never push commits directly to `develop` or `main`. Open a pull request.

### Branch names

CI rejects pull requests whose head branch does not match (Dependabot's `dependabot/*` branches are allowed):

| Kind | Pattern | Example |
| --- | --- | --- |
| Feature | `feature/GH-<issue>-<slug>` | `feature/GH-12-clipboard-history` |
| Bug fix | `bug/GH-<issue>-<slug>` | `bug/GH-34-hotkey-crash` |
| Chore | `chore/<slug>` | `chore/bump-swiftlint` |
| Docs | `docs/<slug>` | `docs/releasing` |
| Release | `release/<slug>` | `release/0.1.0` |

`<slug>` is lowercase letters, digits, and hyphens. Create the GitHub issue first, then name the branch after it.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(launcher): rank apps by frecency
fix(hotkey): detect Spotlight conflict on first launch
docs: describe how to add a provider
chore(ci): cache SwiftPM build artifacts
```

Keep commits small and scoped to one concern.

## Pull requests

1. Branch from the latest `develop`.
2. Open the PR against `develop` (never `main`, except release PRs).
3. Fill in the PR template. Link the issue with `Closes #N`.
4. Wait for CI: `branch-name`, `lint`, `build`, `test`.
5. Squash-merge once checks are green.

Workers cannot compile macOS code locally. GitHub Actions `macos-latest` is the compiler: push, watch the run, read failed logs, fix, repeat. Do not claim a change builds until CI is green.

## Local development

Photon is a Swift Package. There is no committed `.xcodeproj`. The menu-bar app is produced by `Scripts/package_app.sh`.

### Prerequisites

- macOS 14 or later
- Xcode 16+ / a Swift 6 toolchain
- [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (both are preinstalled on GitHub-hosted macOS runners)

### Build the app

```sh
git clone https://github.com/RyanStoffel/photon.git
cd photon
git checkout develop
Scripts/package_app.sh
open build/Photon.app
```

`Scripts/package_app.sh` builds the `Photon` executable in Release, wraps it as `build/Photon.app`, writes the version from `VERSION` into `Info.plist`, and ad-hoc signs the bundle.

### Tests and lint

```sh
swift test --package-path .
swiftformat --lint .
swiftlint
```

`PhotonCore` (fuzzy matching, frecency, the command registry) has no AppKit dependency and compiles on Linux, as does the non-AppKit half of `PhotonClipboard` (its AppKit files are wrapped in `#if canImport(AppKit)`). The other feature modules are gated with `#if os(macOS)` in `Package.swift`.

### Opening in Xcode

```sh
xed .
```

Xcode generates a workspace from `Package.swift`. Do not commit it.

## Adding a feature

Phase 2 features land as their own provider module. See [docs/architecture.md](docs/architecture.md). In short:

1. Open (or create) the issue, branch `feature/GH-<n>-<name>` from `develop`.
2. Implement the provider under `Sources/Photon<Name>/`. Register it in `AppRuntime` only.
3. Keep shared files (`Command.swift`, `CommandRegistry.swift`, `AppRuntime.swift`) stable. Prefer adding a new file over editing a shared one.
4. Open a PR against `develop`.

## Releases

See [docs/releasing.md](docs/releasing.md). Do not push `v*.*.*` tags unless you intend to publish a GitHub Release.
