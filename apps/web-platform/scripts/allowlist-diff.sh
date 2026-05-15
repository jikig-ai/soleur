#!/usr/bin/env bash
# allowlist-diff.sh — diff `paths = [...]` arrays in .gitleaks.toml between
# two refs. When run inside CI with PR_NUMBER set, post (or update) a sticky
# PR comment listing additions; require explicit acknowledgement (#3323).
#
# Inputs (env):
#   BASE_SHA       — base of the diff range (REQUIRED)
#   HEAD_SHA       — head of the diff range (REQUIRED)
#   PR_NUMBER      — PR number for comment posting (optional in smoke mode)
#   PR_LABELS      — JSON array of label names (default: '[]')
#   GITHUB_REPOSITORY — owner/repo for gh api (default: from `gh repo view`)
#
# Override paths (operator opts in to widening the allowlist surface):
#   1. Add label `secret-scan-allowlist-ack` to the PR.
#   2. Include `Allowlist-Widened-By: <name>` trailer in any commit in range.
#
# Exit codes:
#   0 — .gitleaks.toml unchanged OR only removals OR override is present
#   1 — additions present without acknowledgement
#   2 — required input missing
#
# Comment idempotency: keyed on a marker line that MUST be the first line of
# the body so the `gh api … | jq … startswith` filter matches. Re-runs PATCH
# the existing comment instead of posting a duplicate.
#
# Trailer key is case-sensitive (`Allowlist-Widened-By`).
set -euo pipefail

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
PR_LABELS="${PR_LABELS:-[]}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARSER="${REPO_ROOT}/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Skip cheaply if .gitleaks.toml didn't change.
if ! git diff --name-only "${BASE_SHA}..${HEAD_SHA}" | grep -qx '.gitleaks.toml'; then
  echo "allowlist-diff: .gitleaks.toml unchanged; skipping."
  exit 0
fi

# Extract allowlist arrays at base and head. `git show BASE:.gitleaks.toml`
# fails when the file did not exist at BASE — treat as empty.
git show "${BASE_SHA}:.gitleaks.toml" > "${TMP_DIR}/base.toml" 2>/dev/null \
  || : > "${TMP_DIR}/base.toml"
git show "${HEAD_SHA}:.gitleaks.toml" > "${TMP_DIR}/head.toml"

node "${PARSER}" "${TMP_DIR}/base.toml" 2>/dev/null | jq -r '.[]' 2>/dev/null \
  | LC_ALL=C sort -u > "${TMP_DIR}/base-paths.txt" || : > "${TMP_DIR}/base-paths.txt"
node "${PARSER}" "${TMP_DIR}/head.toml" | jq -r '.[]' \
  | LC_ALL=C sort -u > "${TMP_DIR}/head-paths.txt"

added=$(LC_ALL=C comm -13 "${TMP_DIR}/base-paths.txt" "${TMP_DIR}/head-paths.txt")
removed=$(LC_ALL=C comm -23 "${TMP_DIR}/base-paths.txt" "${TMP_DIR}/head-paths.txt")

if [[ -z "${added}" && -z "${removed}" ]]; then
  echo "allowlist-diff: no allowlist path changes (regex re-orderings only)."
  exit 0
fi

# Build comment body. Marker MUST be the first line for jq startswith() match.
marker="<!-- allowlist-diff-comment -->"
body=$(printf '%s\n## Secret-scan allowlist diff\n\nThis PR modifies `.gitleaks.toml` allowlist paths.\n\n### Added paths\n```\n%s\n```\n\n### Removed paths\n```\n%s\n```\n\nAcknowledge via either:\n- Add the `secret-scan-allowlist-ack` label, OR\n- Include `Allowlist-Widened-By: <name>` in any commit trailer.\n' \
  "${marker}" "${added:-(none)}" "${removed:-(none)}")

# Post / update the comment idempotently when running inside CI with a PR.
if [[ -n "${PR_NUMBER:-}" && -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  existing=$(gh api "repos/${repo}/issues/${PR_NUMBER}/comments" --paginate \
    --jq ".[] | select(.body | startswith(\"${marker}\")) | .id" | head -n 1 || true)
  if [[ -n "${existing}" ]]; then
    gh api "repos/${repo}/issues/comments/${existing}" \
      --method PATCH --field body="${body}" >/dev/null
  else
    gh pr comment "${PR_NUMBER}" --body "${body}"
  fi
else
  echo "allowlist-diff: skipping PR comment (no PR_NUMBER/GH_TOKEN — smoke mode)."
fi

# Removals are net-tightening; only ADDED paths require acknowledgement.
if [[ -z "${added}" ]]; then
  echo "allowlist-diff: only removals; no acknowledgement required."
  exit 0
fi

# Override 1: PR has the label.
if printf '%s' "${PR_LABELS}" | jq -e 'index("secret-scan-allowlist-ack")' >/dev/null 2>&1; then
  echo "::notice::allowlist-diff acknowledged by label."
  exit 0
fi

# Override 2: any commit in range carries the trailer.
trailers=$(git log --format='%(trailers:key=Allowlist-Widened-By,valueonly)' "${BASE_SHA}..${HEAD_SHA}" | grep -v '^[[:space:]]*$' || true)
if [[ -n "${trailers}" ]]; then
  echo "::notice::allowlist-diff acknowledged by Allowlist-Widened-By trailer."
  exit 0
fi

echo "::error::Allowlist widening detected. Add label 'secret-scan-allowlist-ack' or include 'Allowlist-Widened-By: <name>' trailer." >&2
printf 'Added paths:\n%s\n' "${added}" >&2
exit 1
