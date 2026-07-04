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
# block for that job, so the ceiling is granted iff EITHER the calling job's
# job-level `permissions:` grants `id-token: write`, OR the calling job has no
# job-level `permissions:` and the workflow-level `permissions:` grants it.
#
# Robustness (a drift guard must not itself fail open — review of #6018):
#   - job headers are matched with an optional trailing comment (`release: # x`)
#     so a legal YAML comment cannot merge two jobs and bleed a sibling's grant;
#   - the job-level id-token check is scoped to the `permissions:` sub-block, not
#     the whole job (an `id-token: write`-shaped line under `with:`/`env:` must
#     not satisfy it);
#   - inline `permissions:` forms (`write-all`, flow-mapping `{id-token: write}`)
#     are classified, so a job broadened to inline perms is not mis-read;
#   - EVERY calling job in a caller file is checked (not just the first);
#   - both local (`./…`) and remote (`owner/repo/…@ref`) `uses:` reference forms
#     are enumerated;
#   - every id-token grep is `^`-anchored so a commented `# id-token: write`
#     never satisfies a check.
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

# NOTE on job-header matching (inlined as `/^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/`
# in the awk functions below): the `(#.*)?` tail is load-bearing — `release: # the
# release job` is legal YAML and without it the header is unrecognised, silently
# merging the job into its predecessor's block (a fail-open the guard must avoid).
# An indented `uses:` key pointing at the reusable workflow, local (`./…`) or
# remote (`owner/repo/…/reusable-release.yml@ref`). Anchored to `^<indent>uses:`
# so a `# uses: …` comment line never matches.
USES_GREP_ERE='^[[:space:]]+uses:[[:space:]]*[^[:space:]]*reusable-release\.yml'
ID_TOKEN_ERE='^[[:space:]]+id-token:[[:space:]]*write\b'

# Print the block of a named job (header through the line before the next job
# header), scoped to content after the top-level `jobs:` key so `on.push:` and
# workflow-level keys can never be mistaken for a job.
named_job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      cur = $0; sub(/^  /, "", cur); sub(/:.*/, "", cur)
      inblock = (cur == job)
    }
    inblock { print }
  ' "$file"
}

# Print the NAME of every job in <file> whose block contains a `uses:` line
# pointing at the reusable workflow. `(\n|^)[[:space:]]+uses:` matches the key
# inside the accumulated multi-line buffer while still excluding `# uses:`
# comment lines (a `#` immediately precedes the space in a comment, so no
# newline/start-anchored whitespace run reaches `uses:`).
calling_job_names() {
  local file="$1"
  awk '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      if (name != "" && buf ~ /(\n|^)[[:space:]]+uses:[[:space:]]*[^[:space:]]*reusable-release\.yml/) print name
      name = $0; sub(/^  /, "", name); sub(/:.*/, "", name); buf = ""; next
    }
    { buf = buf $0 ORS }
    END { if (name != "" && buf ~ /(\n|^)[[:space:]]+uses:[[:space:]]*[^[:space:]]*reusable-release\.yml/) print name }
  ' "$file"
}

# Workflow-level `permissions:` block (top-level key, entries indented 2 spaces),
# terminated by the next top-level key. Block form only — a top-level inline
# `permissions: write-all` is not extracted here (no current caller uses it; the
# fail direction is a loud FAIL, not a silent pass).
workflow_perms() {
  local file="$1"
  awk '
    /^permissions:[[:space:]]*$/ { inblock = 1; next }
    inblock && /^[A-Za-z]/ { exit }
    inblock { print }
  ' "$file"
}

# Classify a job block's OWN (job-level) id-token grant: granted | denied | none.
#   none    → no job-level `permissions:` at all (workflow-level applies)
#   granted → job-level perms include id-token: write (block or inline form)
#   denied  → job-level perms present but WITHOUT id-token (REPLACES workflow-level)
# stdin: the job block (from named_job_block).
job_id_token_verdict() {
  local block permline lineno value sub
  block="$(cat)"
  permline="$(printf '%s\n' "$block" | grep -nE '^    permissions:' | head -1)"
  if [[ -z "$permline" ]]; then
    echo "none"
    return
  fi
  lineno="${permline%%:*}"
  # Everything after `permissions:` on that line (strip trailing comment + ws).
  value="$(printf '%s\n' "$block" | sed -n "${lineno}p" \
    | sed -E 's/^    permissions:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  if [[ -z "$value" ]]; then
    # Block form: scan the sub-block (indent deeper than the 4-space key) until
    # the next 4-space job key, and require id-token WITHIN it (not the whole job).
    sub="$(printf '%s\n' "$block" | awk -v s="$lineno" 'NR > s { if ($0 ~ /^    [A-Za-z0-9_-]+:/) exit; print }')"
    if printf '%s\n' "$sub" | grep -qE "$ID_TOKEN_ERE"; then
      echo "granted"
    else
      echo "denied"
    fi
    return
  fi
  # Inline form: `write-all` grants everything incl. id-token; a flow-mapping that
  # lists `id-token: write` grants it; anything else (`read-all`, `{}`, `read`)
  # does not.
  case "$value" in
    write-all) echo "granted" ;;
    *id-token*write*) echo "granted" ;;
    *) echo "denied" ;;
  esac
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
if named_job_block "$REUSABLE" release | grep -qE "$ID_TOKEN_ERE"; then
  pass "reusable release job requires id-token: write"
else
  fail "reusable release job no longer declares id-token: write — revisit this guard's premise (cosign signing removed?)"
fi

# ---------------------------------------------------------------------------
# 2. Enumerate every caller (grep, not a hardcoded list). apply-deploy-pipeline-
#    fix.yml mentions reusable-release.yml only in a comment (no `uses:`), so it
#    is correctly excluded by matching the anchored `uses:` construct.
# ---------------------------------------------------------------------------
echo ""
echo "2. Enumerate callers of reusable-release.yml"
mapfile -t callers < <(grep -rlE "$USES_GREP_ERE" "$WF_DIR" | sort)
echo "   found ${#callers[@]} caller(s): $(printf '%s ' "${callers[@]##*/}")"

# Vacuous-pass guard: a future grep-scope / path regression that finds zero (or
# one) callers must FAIL loudly, not pass silently over an un-enumerated surface.
if [[ "${#callers[@]}" -ge 2 ]]; then
  pass "caller enumeration found >= 2 callers (not a vacuous grep)"
else
  fail "expected >= 2 callers of reusable-release.yml, found ${#callers[@]} — grep scope regressed?"
fi

# ---------------------------------------------------------------------------
# 3. Each caller's EVERY calling job must grant id-token: write (job-level
#    replaces workflow-level; either satisfies the ceiling per replace semantics).
# ---------------------------------------------------------------------------
echo ""
echo "3. Each caller grants id-token: write to its calling job(s)"
for file in "${callers[@]}"; do
  name="${file##*/}"
  mapfile -t jobs < <(calling_job_names "$file")
  if [[ "${#jobs[@]}" -eq 0 ]]; then
    fail "$name: could not locate the job that calls reusable-release.yml"
    continue
  fi
  for job in "${jobs[@]}"; do
    verdict="$(named_job_block "$file" "$job" | job_id_token_verdict)"
    case "$verdict" in
      granted)
        pass "$name [$job]: calling job grants id-token: write (job-level)"
        ;;
      denied)
        fail "$name [$job]: job-level permissions: WITHOUT id-token: write (job-level REPLACES workflow-level → startup_failure)"
        ;;
      none)
        if workflow_perms "$file" | grep -qE "$ID_TOKEN_ERE"; then
          pass "$name [$job]: calling job inherits workflow-level id-token: write"
        else
          fail "$name [$job]: no id-token: write at job level OR workflow level → the reusable release job will startup_failure"
        fi
        ;;
    esac
  done
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
