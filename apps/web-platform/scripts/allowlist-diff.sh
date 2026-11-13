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
#   2 — required input missing OR the git diff that decides "did .gitleaks.toml change" failed
#
# Comment idempotency: keyed on a marker line that MUST be the first line of
# the body so the `gh api … | jq … startswith` filter matches. Re-runs PATCH
# the existing comment instead of posting a duplicate.
#
# Trailer key is case-sensitive (`Allowlist-Widened-By`).
set -euo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}${TRAILER_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
PR_LABELS="${PR_LABELS:-[]}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARSER="${REPO_ROOT}/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Hoisted constants — keep in sync with the runbook
# (knowledge-base/engineering/operations/secret-scanning.md §Allowlist-diff gate).
readonly OVERRIDE_LABEL="secret-scan-allowlist-ack"
readonly TRAILER_KEY="Allowlist-Widened-By"
readonly COMMENT_MARKER="<!-- allowlist-diff-comment -->"

# Skip cheaply if .gitleaks.toml didn't change. The pathspec is a LITERAL, repo-top path (`:(top,literal)`), so it
# cannot match `agitleaks.toml` and is independent of the cwd and of `diff.relative`; --no-renames lists a rename's
# old path (moving the config away is a change); --ignore-submodules=none is the family-wide flag. The git status is
# CHECKED: a failing diff (bad SHA, shallow clone) used to be an empty list inside a process substitution and read as
# "unchanged; skipping" at exit 0. The ::error:: line is required (the secret-scan smoke matrix expects it).
cfg="$(git -C "${REPO_ROOT}" diff --no-renames --ignore-submodules=none --name-only "${BASE_SHA}..${HEAD_SHA}" -- ':(top,literal).gitleaks.toml')" || {
  echo "::error::allowlist-diff: git diff ${BASE_SHA}..${HEAD_SHA} failed; cannot tell whether .gitleaks.toml changed" >&2
  exit 2
}
if [[ -z "${cfg}" ]]; then
  echo "allowlist-diff: .gitleaks.toml unchanged; skipping."
  exit 0
fi

# Extract allowlist arrays at base and head. `git show BASE:.gitleaks.toml`
# fails when the file did not exist at BASE — treat as empty (the parser
# emits [] for an empty file; that path is exercised below).
git show "${BASE_SHA}:.gitleaks.toml" > "${TMP_DIR}/base.toml" 2>/dev/null \
  || : > "${TMP_DIR}/base.toml"
# The path moved away or was deleted at HEAD (--no-renames lists it, so the gate got this far): name the cause with an
# ::error:: line instead of dying on an opaque `git show` fatal (rc 128) under `set -e`.
git cat-file -e "${HEAD_SHA}:.gitleaks.toml" 2>/dev/null || {
  echo "::error::allowlist-diff: .gitleaks.toml is absent at ${HEAD_SHA} (moved or deleted); cannot compare the allowlist" >&2
  exit 2
}
git show "${HEAD_SHA}:.gitleaks.toml" > "${TMP_DIR}/head.toml"

# Fail-loud if either parser invocation errors (exit 3 = malformed, 4 = v8.25+).
# Without `set -o pipefail` the parser exit would be hidden by jq's success.
set -o pipefail
node "${PARSER}" "${TMP_DIR}/base.toml" | jq -r '.[]' \
  | LC_ALL=C sort -u > "${TMP_DIR}/base-paths.txt"
node "${PARSER}" "${TMP_DIR}/head.toml" | jq -r '.[]' \
  | LC_ALL=C sort -u > "${TMP_DIR}/head-paths.txt"

added=$(LC_ALL=C comm -13 "${TMP_DIR}/base-paths.txt" "${TMP_DIR}/head-paths.txt")
removed=$(LC_ALL=C comm -23 "${TMP_DIR}/base-paths.txt" "${TMP_DIR}/head-paths.txt")

if [[ -z "${added}" && -z "${removed}" ]]; then
  echo "allowlist-diff: no allowlist path changes (regex re-orderings only)."
  exit 0
fi

# Build comment body. Marker MUST be the first line for jq startswith() match.
marker="${COMMENT_MARKER}"
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
if printf '%s' "${PR_LABELS}" | jq -e --arg label "${OVERRIDE_LABEL}" 'index($label)' >/dev/null 2>&1; then
  echo "::notice::allowlist-diff acknowledged by '${OVERRIDE_LABEL}' label."
  exit 0
fi

# Override 2: any commit in range carries the trailer.
trailers=$(git log --format="%(trailers:key=${TRAILER_KEY},valueonly)" "${BASE_SHA}..${HEAD_SHA}" | grep -v '^[[:space:]]*$' || true)
if [[ -n "${trailers}" ]]; then
  echo "::notice::allowlist-diff acknowledged by ${TRAILER_KEY} trailer."
  exit 0
fi

echo "::error::Allowlist widening detected. Add label '${OVERRIDE_LABEL}' or include '${TRAILER_KEY}: <name>' trailer." >&2
printf 'Added paths:\n%s\n' "${added}" >&2
exit 1
