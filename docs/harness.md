# Verification harness

Agents and CI must pass these checks before merging clipboard or files work. Hope is not a release strategy.

Run locally (Linux or macOS):

```sh
Scripts/check-harness.sh
```

The `test` job on `macos-latest` runs the same script, then `cargo test --workspace`.

## 1. File search — `ember` and the fixture home

`photon-files` builds a temporary home:

```
<tmp>/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf
<tmp>/Developer/school/capstone/ember/          (folder)
<tmp>/Developer/school/capstone/ember_poc/      (folder)
```

`FileSearchEngine::search("ember")` uses `mdfind -onlyin` when `/usr/bin/mdfind` exists, then **always** walks the fixture for basename matches. GitHub-hosted Macs often have an empty Spotlight index; the walk still returns the PDF.

Assertions:

- `engine::tests::ember_ranks_pitch_pdf_from_fixture_without_spotlight_index`
- `ranker::tests::ember_surfaces_pitch_pdf_above_prefixed_folders` (PDF relevance ≥ 0.93)

Do not merge a files PR if either is red.

## 2. Clipboard key handling

`photon-core::launcher` tests, no GPUI:

- `clipboard_opens_compact_even_with_history` — Cmd+Shift+V height is compact (89 pt)
- `down_expands_then_up_down_cycle` — Down expands, Up/Down move, wrapping
- `typing_filters_and_arrows_still_move`
- `dismiss_and_reopen_restores_compact_bar` — hide then show clipboard is compact again (no overlay)
- `opening_clipboard_from_main_launcher_is_compact`

## 3. Screenshot scenarios vs compact-bar stills

- `screenshot::tests::compact_scenarios_match_stills` applies `launcher-empty`, `clipboard-empty`, `files-empty` and asserts `SearchOnly` + compact height
- `screenshot::tests::overlay_detector_flags_tall_png_header`
- On macOS, `Scripts/screenshots.sh` writes `docs/screenshots/*.png`. `Scripts/check-screenshot-compact.sh` fails if those three slugs are taller than 420 px (a dim overlay, not the pill bar)

Reference stills from the Swift 0.2.3 compact bar live beside the new captures. Videos are optional; GitHub Macs lack Screen Recording TCC.
