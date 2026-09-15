# UI screenshot harness

Photon can render deterministic UI states for automated screenshots on GitHub Actions macOS runners. Compact-bar scenarios must match the pill stills (no huge dim overlay). `Scripts/check-screenshot-compact.sh` enforces a maximum PNG height on `launcher-empty`, `clipboard-empty`, and `files-empty`.

## Scenarios

Set `PHOTON_UI_SCENARIO` (or pass `--ui-scenario <name>`) at launch:

| Scenario | Description |
| --- | --- |
| `launcher-empty` | Launcher open, empty query, compact bar |
| `launcher-recs` | Empty bar after Down: recommended apps / recents |
| `launcher-query:saf` | Launcher with query `saf` (Safari and related rows) |
| `calculator` | Launcher with query `2 + 2` and the Raycast-style calculator hero card |
| `clipboard-empty` | Clipboard mode with empty history (compact bar) |
| `files-empty` | File search mode, empty query (compact panel) |
| `files-query:<text>` | File search mode with a seeded query |
| `settings:appearance` | Settings window; selects **Appearance** when that tab exists, otherwise **General** |
| `notes` | Notes window with a seeded sample note in an isolated data directory |

Optional environment variables:

- `PHOTON_ISOLATED_DATA_ROOT` — temporary Application Support root (used by `Scripts/screenshots.sh`)
- `PHOTON_UI_SCENARIO_READY_PATH` — file path; the app writes `ready` when the scenario UI has settled
- `PHOTON_APPLICATIONS_EXTRA` — colon-separated extra `/Applications` roots to index

## Run locally (macOS)

```bash
Scripts/screenshots.sh
```

PNG files are written to `docs/screenshots/` as `<scenario-slug>-<light|dark>.png` (colons in scenario names become hyphens).

## CI workflow

Workflow file: `.github/workflows/screenshots.yml`

**Manual run** (any ref):

```bash
gh workflow run screenshots.yml --ref develop -f ref=feature/GH-30-launcher-visual-redesign
```

**Pull request**: add the `screenshots` label to the PR (or push new commits while the label is present).

Download artifacts:

```bash
gh run list --workflow screenshots.yml --limit 5
gh run download <run-id> -n ui-screenshots -D /tmp/ui-screenshots
```

This job is not a required status check.

## Commit screenshots into a PR

1. Run the workflow on your branch and download `ui-screenshots`.
2. Copy PNGs into `docs/screenshots/` on that branch.
3. Add a **Screenshots** section to the PR body with raw GitHub links:

```markdown
## Screenshots

![Launcher (light)](https://raw.githubusercontent.com/RyanStoffel/photon/<branch>/docs/screenshots/launcher-empty-light.png)
```

Replace `<branch>` with your PR branch name.
