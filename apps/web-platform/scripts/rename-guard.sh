#!/usr/bin/env bash
# rename-guard.sh — block `git mv` into gitleaks-allowlisted paths (#3160).
#
# gitleaks v8.24.2 evaluates path allowlists against the rename DESTINATION
# and does NOT re-scan the diff content against the source path. A
# `git mv server/X.ts test/__synthesized__/Y.ts` slips a real secret past
# the gate. This script blocks that pattern unless the operator opts in.
#
# Inputs (env):
#   BASE_SHA       — base of the diff range (REQUIRED)
#   HEAD_SHA       — head of the diff range (REQUIRED)
#   PR_LABELS      — JSON array of label names (default: '[]')
#   GITLEAKS_TOML  — path to the gitleaks config (default: .gitleaks.toml)
#
# Override paths (operator opts in to a rename-into-allowlist):
#   1. Add label `secret-scan-allow-rename` to the PR.
#   2. Include `Rename-Allowed-By: <name>` trailer in any commit in range.
#
# Exit codes:
#   0 — no renames into allowlist OR an override is present
#   1 — at least one rename into an allowlisted path with no override
#   2 — required input missing OR allowlist parser failed
#
# Trailer key is case-sensitive in `git log --format='%(trailers:key=…)'` so
# `Rename-Allowed-By` must be capitalized exactly that way (matches the
# Co-Authored-By convention).
set -euo pipefail

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
PR_LABELS="${PR_LABELS:-[]}"
GITLEAKS_TOML="${GITLEAKS_TOML:-.gitleaks.toml}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARSER="${REPO_ROOT}/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"

if [[ ! -x "${PARSER}" && ! -f "${PARSER}" ]]; then
  echo "rename-guard: parser not found at ${PARSER}" >&2
  exit 2
fi

mapfile -t ALLOW_RES < <(node "${PARSER}" "${GITLEAKS_TOML}" | jq -r '.[]')
if [[ ${#ALLOW_RES[@]} -eq 0 ]]; then
  echo "rename-guard: no allowlist paths to guard; skipping."
  exit 0
fi

# `git diff BASE..HEAD --diff-filter=R` only sees a rename if both
# source-deleted and target-added survive across the WHOLE range. When the
# rename happened in a middle commit and surrounding commits are unrelated,
# the file appears as a plain add at HEAD and the rename is missed. Use
# `git log --diff-filter=R --name-status` to scan EACH commit's renames.
# `--no-renames` is OFF by default; `-M` rename detection is on by default
# for log/diff in modern git.
renames=$(git log --diff-filter=R --name-status --pretty=format: "${BASE_SHA}..${HEAD_SHA}" \
  | awk -F'\t' 'NF>=3 && $1 ~ /^R/ { print }' || true)
if [[ -z "${renames}" ]]; then
  echo "rename-guard: no renames in PR; nothing to guard."
  exit 0
fi

violations=""
while IFS=$'\t' read -r status source target; do
  [[ -z "${target:-}" ]] && continue
  for re in "${ALLOW_RES[@]}"; do
    if printf '%s' "${target}" | grep -qP "${re}"; then
      violations+="${source} -> ${target} (matches /${re}/)"$'\n'
      break
    fi
  done
done <<<"${renames}"

if [[ -z "${violations}" ]]; then
  echo "rename-guard: OK — no renames target allowlisted paths."
  exit 0
fi

# Override 1: PR has the label.
if printf '%s' "${PR_LABELS}" | jq -e 'index("secret-scan-allow-rename")' >/dev/null 2>&1; then
  echo "::notice::rename-guard suppressed by 'secret-scan-allow-rename' label."
  printf 'Renames into allowlisted paths (label-suppressed):\n%s' "${violations}"
  exit 0
fi

# Override 2: any commit in range carries the trailer.
trailers=$(git log --format='%(trailers:key=Rename-Allowed-By,valueonly)' "${BASE_SHA}..${HEAD_SHA}" | tr -d '\r')
trailers_clean=$(printf '%s' "${trailers}" | grep -v '^[[:space:]]*$' || true)
if [[ -n "${trailers_clean}" ]]; then
  # Strip CR/LF before echoing into annotations (log-injection guard).
  safe="${trailers_clean//[$'\n\r']/, }"
  echo "::notice::rename-guard suppressed by Rename-Allowed-By trailer: ${safe}"
  printf 'Renames into allowlisted paths (trailer-suppressed):\n%s' "${violations}"
  exit 0
fi

echo "::error::Rename(s) into gitleaks-allowlisted paths require either the 'secret-scan-allow-rename' label OR a 'Rename-Allowed-By: <name>' commit trailer." >&2
printf '%s' "${violations}" >&2
exit 1
