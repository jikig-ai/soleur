#!/usr/bin/env bash
# Token-path census: every workflow job that runs a `uses:
# anthropics/claude-code-action@…` step must have a resolvable GitHub-token
# path. claude-code-action v1.0.236 (SHA 20f0b248c5003db4b9ca43c45e17949bcdc36d2d,
# rolled out repo-wide by the claude-sonnet-5-5 migration ~2026-09-18) calls
# setupGitHubToken -> getOidcToken, which hard-fails ~15s in when the job's
# effective permissions lack `id-token: write` AND the step's `with:` block
# carries no `github_token:` input to short-circuit OIDC.
#
# Measured cost of the missing grant: scheduled-machinery-drain.yml died inside
# "Drain the machinery ledger" on three consecutive weekly runs (2026-09-21,
# 09-28, 10-05); `continue-on-error: true` masked it into floor BREACHes and the
# Sentry cron monitor reported "no successful check-in" and approached
# auto-mute. fix-constraints-stage-a.yml carried the same defect LATENT (its
# agent step is conditional on a red constraint gate, so it greens while unused
# and would stall ADR-074's founder-zero-touch recovery on the next trip).
# Recurrence 3 of the missing-OIDC-permission class, after
# knowledge-base/project/learnings/2026-05-04-schedule-once-template-missing-id-token.md
# and the caller-grant variant guarded by reusable-release-caller-permissions.test.sh.
#
# Semantics enforced:
#   - a job-level `permissions:` block REPLACES the workflow-level block for
#     that job;
#   - `id-token: write` grants the OIDC path; `permissions: write-all` and a
#     flow mapping containing `id-token: write` do too;
#   - the step input `with: github_token:` bypasses OIDC entirely (verified at
#     the pinned SHA: inputs.github_token -> OVERRIDE_GITHUB_TOKEN ->
#     setupGitHubToken early-returns before getOidcToken) — this is the legal
#     shape for fix-constraints-stage-a.yml, where `id-token: write` is
#     DELIBERATELY withheld in the untrusted pull_request context;
#   - a `# id-token: write` comment satisfies nothing (`^`-anchored matching).
#
# The consumer population is DERIVED by grep census, never enumerated: adding a
# workflow that uses the action without a token path is a one-file change that
# reds this suite. Fixture runs override the scan root with WF_DIR.
#
# Run via:  bash plugins/soleur/test/claude-code-action-auth.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_DIR="${WF_DIR:-$REPO_ROOT/.github/workflows}"

# Live (non-commented) `uses: anthropics/claude-code-action@…` — anchored so
# `# uses: …` comments and bare action-name mentions (marketplace URLs, doc
# comments) never count as consumers.
USES_ERE='^[[:space:]]+(-[[:space:]]+)?uses:[[:space:]]*anthropics/claude-code-action@'
# `write` terminated by whitespace, EOL, or a `#` comment (POSIX classes; the
# GNU-only `\b` is not portable to mawk/BusyBox environments).
ID_TOKEN_ERE='^[[:space:]]+id-token:[[:space:]]*write([[:space:]]|$|#)'

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# YAML helpers (idioms mirrored from reusable-release-caller-permissions.test.sh)
# ---------------------------------------------------------------------------

# Print the block of a named job (header through the line before the next job
# header), scoped to content after the top-level `jobs:` key.
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

# Print the NAME of every job in <file> whose block contains a live consumer
# `uses:` line for claude-code-action. The regex inside the accumulated buffer
# tolerates both `uses:`-as-its-own-line and `- uses:` inline step forms while
# `# uses:` comments still cannot match (a `#` precedes the whitespace run).
consumer_job_names() {
  local file="$1"
  awk '
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ {
      if (name != "" && buf ~ /(\n|^)[[:space:]]+(-[[:space:]]+)?uses:[[:space:]]*anthropics\/claude-code-action@/) print name
      name = $0; sub(/^  /, "", name); sub(/:.*/, "", name); buf = ""; next
    }
    { buf = buf $0 ORS }
    END { if (name != "" && buf ~ /(\n|^)[[:space:]]+(-[[:space:]]+)?uses:[[:space:]]*anthropics\/claude-code-action@/) print name }
  ' "$file"
}

# Classify a job block's OWN (job-level) id-token grant: granted | denied | none.
#   none    → no job-level `permissions:` at all (workflow-level applies)
#   granted → job-level perms include id-token: write (block or inline form)
#   denied  → job-level perms present but WITHOUT id-token (REPLACES workflow)
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
  value="$(printf '%s\n' "$block" | sed -n "${lineno}p" \
    | sed -E 's/^    permissions:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  if [[ -z "$value" ]]; then
    sub="$(printf '%s\n' "$block" | awk -v s="$lineno" 'NR > s { if ($0 ~ /^    [A-Za-z0-9_-]+:/) exit; print }')"
    if printf '%s\n' "$sub" | grep -qE "$ID_TOKEN_ERE"; then
      echo "granted"
    else
      echo "denied"
    fi
    return
  fi
  case "$value" in
    write-all) echo "granted" ;;
    *id-token*write*) echo "granted" ;;
    *) echo "denied" ;;
  esac
}

# Classify the workflow-level `permissions:` grant: granted | denied | none.
# Handles both the block form (`permissions:` + indented entries) and inline
# forms (`permissions: write-all`, `permissions: {id-token: write}`).
workflow_id_token_verdict() {
  local file="$1" permline lineno value sub
  permline="$(grep -nE '^permissions:' "$file" | head -1)"
  if [[ -z "$permline" ]]; then
    echo "none"
    return
  fi
  lineno="${permline%%:*}"
  value="$(sed -n "${lineno}p" "$file" \
    | sed -E 's/^permissions:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  if [[ -z "$value" ]]; then
    sub="$(awk -v s="$lineno" 'NR > s { if ($0 ~ /^[A-Za-z]/) exit; print }' "$file")"
    if printf '%s\n' "$sub" | grep -qE "$ID_TOKEN_ERE"; then
      echo "granted"
    else
      echo "denied"
    fi
    return
  fi
  case "$value" in
    write-all) echo "granted" ;;
    *id-token*write*) echo "granted" ;;
    *) echo "denied" ;;
  esac
}

# Echo "yes" iff the consumer step in <job-block-on-stdin> declares
# `github_token:` inside its `with:` block. The step span runs from the
# `uses:` line to the next step item (a `- ` line at a shallower indent) or
# the next job-level key; `with:` must sit at the `uses:` indent (sibling
# key of the step) and `github_token:` strictly below it — an `env:` entry
# or a `with:` of a neighbouring step does not count.
step_has_github_token() {
  awk '
    /^[[:space:]]+(-[[:space:]]+)?uses:[[:space:]]*anthropics\/claude-code-action@/ {
      match($0, /^[[:space:]]+/); uind = RLENGTH
      # `- uses:` inline form: the key sits two columns right of the dash indent
      if ($0 ~ /^[[:space:]]+-/) uind += 2
      instep = 1; inwith = 0; next
    }
    instep {
      if (match($0, /^[[:space:]]+/)) ind = RLENGTH; else ind = 0
      # step span ends at a shallower-indented line (next `- ` step item or a
      # job-level key). `with:`/`env:` siblings sit AT uind and do NOT end it.
      if (ind < uind) { instep = 0; inwith = 0 }
      if (instep) {
        if (ind == uind && $0 ~ /^[[:space:]]+with:[[:space:]]*(#.*)?$/) { inwith = 1; next }
        if (inwith && ind == uind) { inwith = 0 }
        if (inwith && ind > uind && $0 ~ /^[[:space:]]+github_token:/) { print "yes"; exit }
      }
    }
  '
}

# ---------------------------------------------------------------------------
# Census: scan every workflow file in $WF_DIR, evaluate each consuming job.
# Prints per-file verdicts; returns 0 when every consuming job resolves a token
# path AND at least one consumer exists, non-zero otherwise.
# ---------------------------------------------------------------------------
census_dir() {
  local dir="$1"
  local consumers=0 failures=0 file name jobs job verdict jv wv block
  local -a files=()

  mapfile -t files < <(grep -rlE "$USES_ERE" "$dir"/*.yml "$dir"/*.yaml 2>/dev/null | sort)
  for file in "${files[@]:-}"; do
    [[ -n "$file" ]] || continue
    name="${file##*/}"
    mapfile -t jobs < <(consumer_job_names "$file")
    if [[ "${#jobs[@]}" -eq 0 ]]; then
      echo "  FAIL: $name: consumer uses: line found but no containing job resolved"
      failures=$((failures + 1))
      continue
    fi
    for job in "${jobs[@]}"; do
      consumers=$((consumers + 1))
      block="$(named_job_block "$file" "$job")"
      # Arm A — the step bypasses OIDC with an explicit token input.
      if printf '%s\n' "$block" | step_has_github_token | grep -q yes; then
        echo "  ok: $name [$job]: consumer step carries github_token: input (OIDC bypassed)"
        continue
      fi
      # Arm B — the effective permissions grant id-token: write.
      jv="$(printf '%s\n' "$block" | job_id_token_verdict)"
      wv="$(workflow_id_token_verdict "$file")"
      case "$jv" in
        granted)
          echo "  ok: $name [$job]: job-level permissions grant id-token: write"
          ;;
        denied)
          echo "  FAIL: $name [$job]: job-level permissions: WITHOUT id-token: write (replaces workflow-level) and no github_token: input — getOidcToken hard-fails"
          failures=$((failures + 1))
          ;;
        none)
          if [[ "$wv" == "granted" ]]; then
            echo "  ok: $name [$job]: inherits workflow-level id-token: write"
          else
            echo "  FAIL: $name [$job]: no id-token: write (job or workflow level) and no github_token: input — getOidcToken hard-fails"
            failures=$((failures + 1))
          fi
          ;;
      esac
    done
  done
  echo "token-path census: ${consumers} consumer(s), ${failures} failure(s)"
  [[ "$consumers" -ge 1 && "$failures" -eq 0 ]]
}

# Run the census against a fixture directory; expected = PASS|FAIL.
fixture_row() {
  local label="$1" dir="$2" expected="$3" out rc
  out="$(census_dir "$dir" 2>&1)"; rc=$?
  if [[ "$expected" == "PASS" && "$rc" -eq 0 ]] || [[ "$expected" == "FAIL" && "$rc" -ne 0 ]]; then
    pass "mutation row: $label (expected $expected, got rc=$rc)"
  else
    fail "mutation row: $label (expected $expected, got rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/      | /'
  fi
}

mkfixture() { # mkfixture <dir> <name> — writes stdin as <dir>/<name>
  local dir="$1" name="$2"
  mkdir -p "$dir"
  cat > "$dir/$name"
}

echo "=== claude-code-action token-path census ==="
echo ""

# --- Section 1: live-tree census --------------------------------------------
echo "1. Census consumers over $WF_DIR"
if census_dir "$WF_DIR"; then
  pass "live tree: every claude-code-action consumer resolves a token path"
else
  fail "live tree: consumer(s) without a resolvable token path (see above)"
fi

# --- Section 2: mutation matrix (fixture workflows under WF_DIR override) ---
echo ""
echo "2. Mutation matrix"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# Row 1: the drain defect shape — consumer with contents: read only, no
# github_token input. Expect RED.
mkdir -p "$FIX/row1"
mkfixture "$FIX/row1" "drain-like.yml" <<'YAML'
name: drain-like
on:
  workflow_dispatch: {}
permissions:
  contents: read
  issues: write
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0000
      - uses: anthropics/claude-code-action@deadbeef
        with:
          anthropic_api_key: ${{ secrets.X }}
YAML
fixture_row "1 consumer without token path" "$FIX/row1" FAIL

# Row 2: only non-consumer workflows → consumers=0 → RED (a census over nothing
# asserts nothing — dispatch vacuity).
mkdir -p "$FIX/row2"
mkfixture "$FIX/row2" "plain.yml" <<'YAML'
name: plain
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0000
YAML
fixture_row "2 zero consumers" "$FIX/row2" FAIL

# Row 3: compliant file PLUS a non-compliant file → RED (the census must not
# stop at the first member).
mkdir -p "$FIX/row3"
mkfixture "$FIX/row3" "good.yml" <<'YAML'
name: good
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
mkfixture "$FIX/row3" "bad.yml" <<'YAML'
name: bad
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "3 second member non-compliant" "$FIX/row3" FAIL

# Row 4: the Stage A remediation shape — github_token: under with:, no id-token
# anywhere. Expect PASS (without this row the guard reddens its own fix).
mkdir -p "$FIX/row4"
mkfixture "$FIX/row4" "stage-a-like.yml" <<'YAML'
name: stage-a-like
on: pull_request
permissions:
  contents: read
jobs:
  fix:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        with:
          anthropic_api_key: ${{ secrets.X }}
          github_token: ${{ github.token }}
YAML
fixture_row "4 github_token input, no id-token" "$FIX/row4" PASS

# Row 5: workflow-level id-token: write but job-level permissions: without it —
# job-level REPLACES workflow-level. Expect RED.
mkdir -p "$FIX/row5"
mkfixture "$FIX/row5" "job-replaces.yml" <<'YAML'
name: job-replaces
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  run:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "5 job-level perms replace workflow-level" "$FIX/row5" FAIL

# Row 6: `# id-token: write` commented out under permissions. Expect RED —
# a commented grant is no grant (and the Stage A fix file carries exactly such
# a comment, so block scoping is load-bearing on the real tree too).
mkdir -p "$FIX/row6"
mkfixture "$FIX/row6" "commented.yml" <<'YAML'
name: commented
on: workflow_dispatch
permissions:
  contents: read
  # id-token: write — withheld deliberately
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "6 commented id-token grant" "$FIX/row6" FAIL

# Row 7: `id-token: write` string inside a step's env:/with: block, permissions
# without it. Expect RED — only a permissions: block counts.
mkdir -p "$FIX/row7"
mkfixture "$FIX/row7" "misplaced.yml" <<'YAML'
name: misplaced
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        env:
          NOTE: id-token: write
YAML
fixture_row "7 id-token string outside permissions" "$FIX/row7" FAIL

# Row 8: `permissions: write-all` — functionally grants id-token. Expect PASS —
# a must-PASS non-canonical input; catches a reject-everything guard.
mkdir -p "$FIX/row8"
mkfixture "$FIX/row8" "write-all.yml" <<'YAML'
name: write-all
on: workflow_dispatch
permissions: write-all
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "8 permissions: write-all" "$FIX/row8" PASS

# Row 9: `uses: anthropics/claude-code-action` present only inside a comment —
# not a consumer. The remaining real file is compliant, so expect PASS.
mkdir -p "$FIX/row9"
mkfixture "$FIX/row9" "comment-only.yml" <<'YAML'
name: comment-only
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      # - uses: anthropics/claude-code-action@deadbeef (kept for reference)
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "9 comment-only uses: line" "$FIX/row9" PASS

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
