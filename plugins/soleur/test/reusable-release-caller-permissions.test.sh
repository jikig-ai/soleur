#!/usr/bin/env bash
# Drift-guard: every caller of reusable-release.yml must grant `id-token: write`
# to the job that calls it.
#
# Background (#6018): a reusable workflow can only USE a GITHUB_TOKEN permission
# that its CALLER grants. #5977 (60f203c50) added `id-token: write` to the
# reusable `release` job for cosign keyless signing (#5933 Item 4). Any caller
# whose calling job does NOT grant that permission fails at DISPATCH with
# `startup_failure` (empty `jobs`, no step logs) — GitHub validates the caller's
# permission ceiling before evaluating any step `if:`, so this fires even for the
# plugin caller that passes no `docker_image` and never runs the cosign steps.
# #5981 fixed the web-platform caller but missed the plugin caller — this guard
# makes the next caller (or a future permission the reusable job adds) fail
# loudly at PR time instead of silently at merge.
#
# Same defect class as
# knowledge-base/project/learnings/2026-05-04-schedule-once-template-missing-id-token.md
# ("OIDC permission belongs to the action/reusable-job, not the caller task").
#
# Static assertion over the workflow YAML (no live GitHub API). Semantics
# enforced: a job-level `permissions:` block REPLACES the inherited workflow-level
# block for that job, so the ceiling is granted iff EITHER the calling job has a
# job-level `permissions:` containing `id-token: write`, OR the calling job has no
# job-level block and the workflow-level `permissions:` contains it.
#
# Run via:  bash plugins/soleur/test/reusable-release-caller-permissions.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_DIR="$REPO_ROOT/.github/workflows"
REUSABLE="$WF_DIR/reusable-release.yml"

PASS=0
FAIL=0
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

echo "=== reusable-release caller id-token drift guard (#6018) ==="
echo ""

# ---------------------------------------------------------------------------
# Extract the lines of a named job block (from `^  <job>:` up to the next
# 2-space-indented job header), scoped to content after the top-level `jobs:`
# key so `on.push:` and workflow-level keys can never be mistaken for a job.
# ---------------------------------------------------------------------------
named_job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      cur = $0; sub(/^  /, "", cur); sub(/:.*/, "", cur)
      inblock = (cur == job)
    }
    inblock { print }
  ' "$file"
}

# The calling job block = the job whose block contains the `uses:` line pointing
# at reusable-release.yml. Accumulate each job into a buffer; when the next job
# header (or EOF) arrives, emit the buffer iff it was the caller.
calling_job_block() {
  local file="$1"
  awk '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if (buf ~ /uses:[[:space:]]*\.\/\.github\/workflows\/reusable-release\.yml/) { printf "%s", buf; exit }
      buf = $0 ORS; next
    }
    { buf = buf $0 ORS }
    END { if (buf ~ /uses:[[:space:]]*\.\/\.github\/workflows\/reusable-release\.yml/) printf "%s", buf }
  ' "$file"
}

# Workflow-level `permissions:` block (top-level key, entries indented 2 spaces),
# terminated by the next top-level key.
workflow_perms() {
  local file="$1"
  awk '
    /^permissions:[[:space:]]*$/ { inblock = 1; next }
    inblock && /^[A-Za-z]/ { exit }
    inblock { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# 1. Premise check: the reusable `release` job must itself declare
#    `id-token: write`. If cosign signing is later removed and this permission
#    disappears, this assertion should be revisited (the guard would otherwise
#    keep enforcing a now-unneeded caller grant) — a loud FAIL here forces that
#    review rather than the guard silently drifting stale.
# ---------------------------------------------------------------------------
echo "1. reusable-release.yml release job declares id-token: write"
if [[ ! -f "$REUSABLE" ]]; then
  fail "reusable-release.yml not found at $REUSABLE"
  echo ""
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi
if named_job_block "$REUSABLE" release | grep -qE '^[[:space:]]+id-token:[[:space:]]*write\b'; then
  pass "reusable release job requires id-token: write"
else
  fail "reusable release job no longer declares id-token: write — revisit this guard's premise (cosign signing removed?)"
fi

# ---------------------------------------------------------------------------
# 2. Enumerate every caller (grep, not a hardcoded list). apply-deploy-pipeline-
#    fix.yml mentions reusable-release.yml only in a comment (no `uses:`), so it
#    is correctly excluded by matching the `uses:` construct.
# ---------------------------------------------------------------------------
echo ""
echo "2. Enumerate callers of reusable-release.yml"
mapfile -t callers < <(grep -rlE 'uses:[[:space:]]*\./\.github/workflows/reusable-release\.yml' "$WF_DIR" | sort)
echo "   found ${#callers[@]} caller(s): $(printf '%s ' "${callers[@]##*/}")"

# Vacuous-pass guard: a future grep-scope / path regression that finds zero (or
# one) callers must FAIL loudly, not pass silently over an un-enumerated surface.
if [[ "${#callers[@]}" -ge 2 ]]; then
  pass "caller enumeration found >= 2 callers (not a vacuous grep)"
else
  fail "expected >= 2 callers of reusable-release.yml, found ${#callers[@]} — grep scope regressed?"
fi

# ---------------------------------------------------------------------------
# 3. Each caller's calling job must grant id-token: write (job-level replaces
#    workflow-level; either satisfies the ceiling per the replace semantics).
# ---------------------------------------------------------------------------
echo ""
echo "3. Each caller grants id-token: write to its calling job"
for file in "${callers[@]}"; do
  name="${file##*/}"
  block="$(calling_job_block "$file")"
  if [[ -z "$block" ]]; then
    fail "$name: could not locate the job that calls reusable-release.yml"
    continue
  fi
  if grep -qE '^    permissions:[[:space:]]*$' <<<"$block"; then
    # Job-level permissions block present → it REPLACES the workflow-level block,
    # so id-token must be granted here or the ceiling is not met.
    if grep -qE '^[[:space:]]+id-token:[[:space:]]*write\b' <<<"$block"; then
      pass "$name: calling job grants id-token: write (job-level)"
    else
      fail "$name: calling job has a job-level permissions: block WITHOUT id-token: write (job-level REPLACES workflow-level → startup_failure)"
    fi
  else
    # No job-level block → workflow-level permissions apply to this job.
    if grep -qE 'id-token:[[:space:]]*write\b' <<<"$(workflow_perms "$file")"; then
      pass "$name: calling job inherits workflow-level id-token: write"
    else
      fail "$name: no id-token: write at job level OR workflow level → the reusable release job will startup_failure"
    fi
  fi
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
