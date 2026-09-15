#!/usr/bin/env bash
# Fail if clipboard-empty / files-empty / launcher-empty PNGs are overlay-tall.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/docs/screenshots"
python3 - "$DIR" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
slugs = ("launcher-empty", "clipboard-empty", "files-empty")
failed = False
for path in sorted(root.glob("*.png")):
    if not any(path.name.startswith(s) for s in slugs):
        continue
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        print(f"not a png: {path}", file=sys.stderr)
        failed = True
        continue
    height = struct.unpack(">I", data[20:24])[0]
    print(f"{path.name}: {height}px tall")
    if height > 420:
        print(f"OVERLAY: {path.name} is {height}px (compact bar stills must be <= 420px)", file=sys.stderr)
        failed = True
if failed:
    sys.exit(1)
print("Compact screenshot heights look like the pill bar, not a dim overlay.")
PY
