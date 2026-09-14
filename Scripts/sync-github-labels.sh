#!/usr/bin/env bash
# Create the type/*, area/*, and priority/* labels from .github/labels.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${1:-RyanStoffel}"
REPO="${2:-photon}"

python3 - "$ROOT/.github/labels.yml" | while IFS=$'\t' read -r name color description; do
  if gh api "repos/${OWNER}/${REPO}/labels/${name}" >/dev/null 2>&1; then
    gh api -X PATCH "repos/${OWNER}/${REPO}/labels/${name}" \
      -f color="$color" -f description="$description" >/dev/null
  else
    gh api -X POST "repos/${OWNER}/${REPO}/labels" \
      -f name="$name" -f color="$color" -f description="$description" >/dev/null
  fi
  echo "label ${name}"
done <<'PY'
import sys, yaml, pathlib
# Minimal parser so we do not require PyYAML.
text = pathlib.Path(sys.argv[1]).read_text()
name = color = desc = None
for line in text.splitlines():
    line = line.rstrip()
    if line.startswith("- name:"):
        if name:
            print(f"{name}\t{color}\t{desc}")
        name = line.split(":", 1)[1].strip().strip('"')
        color = desc = ""
    elif line.startswith("  color:"):
        color = line.split(":", 1)[1].strip().strip('"')
    elif line.startswith("  description:"):
        desc = line.split(":", 1)[1].strip()
if name:
    print(f"{name}\t{color}\t{desc}")
PY
