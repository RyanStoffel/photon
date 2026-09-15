#!/usr/bin/env bash
# Automated checks agents and CI must pass before merging clipboard or files work.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> clipboard key-handling (compact, Down expands, Up/Down, dismiss reset)"
cargo test -p photon-core --lib launcher::tests -- --nocapture

echo "==> screenshot compact-bar layout (no overlay)"
cargo test -p photon-core --lib screenshot::tests -- --nocapture

echo "==> files: ember ranks Ember_Individual_Pitch.pdf from a fixture home"
cargo test -p photon-files --lib engine::tests::ember_ranks_pitch_pdf_from_fixture_without_spotlight_index -- --nocapture
cargo test -p photon-files --lib ranker::tests::ember_surfaces_pitch_pdf_above_prefixed_folders -- --nocapture

echo "Harness green."
