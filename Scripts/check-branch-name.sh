#!/usr/bin/env bash
set -euo pipefail

branch="${1:-}"
branch="${branch#refs/heads/}"

if [[ -z "$branch" ]]; then
  echo "usage: $0 <branch-name>" >&2
  exit 2
fi

if [[ "$branch" == "develop" || "$branch" == "main" ]]; then
  exit 0
fi

# Dependabot / GitHub Actions version bumps.
if [[ "$branch" =~ ^dependabot/ ]]; then
  exit 0
fi

if [[ "$branch" =~ ^(feature/GH-[0-9]+-[a-z0-9-]+|bug/GH-[0-9]+-[a-z0-9-]+|chore/[a-z0-9][a-z0-9-]*|docs/[a-z0-9][a-z0-9-]*|release/[a-z0-9][a-z0-9.-]*)$ ]]; then
  exit 0
fi

cat >&2 <<EOF
Invalid branch name: ${branch}

Allowed:
  feature/GH-<issue>-<slug>
  bug/GH-<issue>-<slug>
  chore/<slug>
  docs/<slug>
  release/<slug>
  dependabot/*
  develop
  main

<slug> is lowercase letters, digits, and hyphens.
EOF
exit 1
