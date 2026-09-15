#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "check-screenshot-compact.sh only runs on macOS." >&2
  exit 2
fi

shopt -s nullglob
screenshots=(docs/screenshots/*.png)
if [[ "${#screenshots[@]}" -eq 0 ]]; then
  echo "No UI screenshots found." >&2
  exit 1
fi

swift Scripts/check-ui-screenshots.swift "${screenshots[@]}"
