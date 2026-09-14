#!/usr/bin/env bash
# Apply rulesets so develop and main require PRs + CI, and main is linear.
# Usage: GH_HOST=github.com Scripts/apply-branch-protection.sh RyanStoffel photon
set -euo pipefail

OWNER="${1:-RyanStoffel}"
REPO="${2:-photon}"

required_checks='[
  {"context":"branch-name"},
  {"context":"lint"},
  {"context":"build"},
  {"context":"test"},
  {"context":"smoke"}
]'

apply() {
  local name="$1"
  local ref="$2"
  local extra_rules="$3"

  local body
  body="$(jq -n \
    --arg name "$name" \
    --arg ref "refs/heads/${ref}" \
    --argjson checks "$required_checks" \
    --argjson extra "$extra_rules" \
    '{
      name: $name,
      target: "branch",
      enforcement: "active",
      bypass_actors: [],
      conditions: { ref_name: { include: [$ref], exclude: [] } },
      rules: ([
        {type: "deletion"},
        {type: "non_fast_forward"},
        {type: "pull_request", parameters: {
          required_approving_review_count: 0,
          dismiss_stale_reviews_on_push: false,
          required_review_thread_resolution: false,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_reviewers: []
        }},
        {type: "required_status_checks", parameters: {
          strict_required_status_checks_policy: true,
          do_not_enforce_on_create: false,
          required_status_checks: $checks
        }}
      ] + $extra)
    }')"

  if gh api "repos/${OWNER}/${REPO}/rulesets" --input - <<<"$body"; then
    echo "Applied ruleset ${name}"
    return
  fi

  echo "Rulesets API failed for ${name}; trying classic branch protection." >&2
  gh api -X PUT "repos/${OWNER}/${REPO}/branches/${ref}/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["branch-name", "lint", "build", "test"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": $([[ "$ref" == "main" ]] && echo true || echo false)
}
EOF
}

apply "Protect develop" "develop" "[]"
apply "Protect main" "main" '[{"type":"required_linear_history"}]'
