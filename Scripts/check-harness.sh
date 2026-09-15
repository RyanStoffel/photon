#!/usr/bin/env bash
# Focused parity fixtures agents and CI run in addition to the full suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> launcher compact layout, anchor and snap math"
swift test --filter LauncherLayoutTests
swift test --filter LauncherPositionTests

echo "==> clipboard filtering, persistence and launcher entry"
swift test --filter ClipboardSearchTests
swift test --filter ClipboardStoreTests

echo "==> app/settings search and icon metadata"
swift test --filter PhotonAppsTests
swift test --filter CommandIconTests

echo "==> file fixtures (ember ranking, home scope, mixed matching)"
swift test --filter FileRankerTests
swift test --filter FilePathScopeTests
swift test --filter FileFuzzyMatcherTests
swift test --filter SpotlightQueryBuilderTests
swift test --filter MdfindInvocationTests

echo "==> notes, configurable shortcuts and window layout"
swift test --filter PhotonNotesTests
swift test --filter KeybindsConfigurationTests
swift test --filter KeyShortcutTests
swift test --filter WindowLayoutTests

echo "Focused parity fixture harness green."
