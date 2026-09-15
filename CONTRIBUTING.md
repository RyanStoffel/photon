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
| Chore | `chore/<slug>` | `chore/bump-actions` |
| Docs | `docs/<slug>` | `docs/releasing` |
| Release | `release/<slug>` | `release/0-3-0` |

`<slug>` is lowercase letters, digits, and hyphens. Create the GitHub issue first, then name the branch after it. Chore slugs must not contain dots.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(launcher): rank apps by frecency
fix(hotkey): detect Spotlight conflict on first launch
docs: describe how to add a provider
chore(ci): cache cargo build artifacts
```

Keep commits small and scoped to one concern. Do not add `Co-authored-by: Cursor` trailers.

## Pull requests

1. Branch from the latest `develop`.
2. Open the PR against `develop` (never `main`, except release PRs).
3. Fill in the PR template. Link the issue with `Closes #N`.
4. Wait for CI: `branch-name`, `lint`, `build`, `test`, `smoke`.
5. Do not merge a clipboard or files PR until `Scripts/check-harness.sh` is green (the `test` job runs it).
6. Squash-merge once checks are green.

Workers cannot compile GPUI/AppKit locally on Linux. GitHub Actions `macos-latest` is the compiler: push, watch the run, read failed logs, fix, repeat. Do not claim a change builds until CI is green. The `smoke` job launches the built app on the runner for eight seconds and fails on a crash; it is the only runtime check, so treat a red `smoke` as a real bug, not flakiness, until the log says otherwise.

## Local development

Photon is a Cargo workspace. The menu-bar app is produced by `Scripts/package_app.sh`.

### Prerequisites

- macOS 14 or later to run the app
- Rust 1.88 (`rust-toolchain.toml`)
- Xcode / Metal for GPUI

### Build the app

```sh
git clone https://github.com/RyanStoffel/photon.git
cd photon
git checkout develop
Scripts/package_app.sh
open build/Photon.app
```

`Scripts/package_app.sh` builds the `photon` binary in Release, wraps it as `build/Photon.app`, writes the version from `VERSION` into `Info.plist`, and ad-hoc signs the bundle.

### Tests and lint

```sh
Scripts/check-harness.sh
cargo test --workspace
cargo fmt --all -- --check
cargo clippy --workspace --all-targets
```

`photon-core`, `photon-clipboard`, and `photon-files` compile on Linux. The GPUI crate (`photon`) is macOS-only.

### Screenshots

`Scripts/screenshots.sh` (macOS) captures compact-bar stills. `Scripts/check-screenshot-compact.sh` rejects overlay-tall clipboard/files empty PNGs.
