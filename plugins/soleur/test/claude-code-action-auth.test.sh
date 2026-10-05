#!/usr/bin/env bash
# Token-path census: every `uses: anthropics/claude-code-action@…` step must
# resolve a GitHub-token path. The action calls setupGitHubToken ->
# getOidcToken, which hard-fails ~15 s in when the job's effective permissions
# lack `id-token: write` AND the step's `with:` block carries no `github_token:`
# input to short-circuit OIDC. This has held since at least v1.0.161 — NOT a
# v1.0.236 regression: the OIDC failure is identical at SHA 5aa6f47e (measured
# on runs 34591772975 and 34825797967, 2026-09-11/14) as at 20f0b248
# (v1.0.236, run 37287175185, 2026-10-05).
#
# Measured cost: scheduled-machinery-drain.yml was born WITHOUT the grant on
# 2026-09-11 and never drained anything (closed=0 on every run); the red was
# masked by WAIVED-SUPPLY while the machinery pool sat below the floor, and
# surfaced 2026-09-21 — the first week the pool crossed floor=20 — as a
# continue-on-error BREACH. The Sentry cron monitor reported "no successful
# check-in" and approached auto-mute. fix-constraints-stage-a.yml carried the
# same defect LATENT (its agent step is conditional on a red constraint gate,
# so it greens while unused and would stall ADR-074's founder-zero-touch
# recovery on the next trip). Recurrence 3 of the missing-OIDC-permission
# class, after
# knowledge-base/project/learnings/2026-05-04-schedule-once-template-missing-id-token.md
# and the caller-grant variant guarded by reusable-release-caller-permissions.test.sh.
#
# Semantics enforced:
#   - the property is PER-STEP: each consuming step must carry `github_token:`
#     in its own `with:` block (first-child keys only — a `github_token:`
#     literal inside a `prompt: |` block scalar or a nested subkey does NOT
#     count) OR the job's effective permissions must grant `id-token: write`;
#   - a job-level `permissions:` block REPLACES the workflow-level block for
#     that job; duplicate `permissions:` keys resolve LAST-wins (YAML
#     semantics), never first-wins;
#   - `id-token: write` grants the OIDC path; `permissions: write-all` and a
#     flow mapping with an `id-token: write` ENTRY do too — but a flow map
#     like `{id-token: none, contents: write}` does not (the `write` must
#     attach to `id-token`'s own colon, not appear anywhere downstream);
#   - `github_token:` must carry a NON-EMPTY scalar — a bare key yields
#     inputs.github_token == '' at the action and OIDC is still attempted;
#   - a `# id-token: write` comment satisfies nothing (`^`-anchored matching);
#   - consumer detection tolerates `uses :`, quoted values, and
#     `Anthropics`-case, and a second sweep flags any `claude-code-action`
#     mention on a non-canonical `uses` line (flow-style steps) — KNOWN LIMIT:
#     an expression `uses: ${{ matrix.act }}` carries no literal name and is
#     invisible to this guard;
#   - composite actions under .github/actions/*/action.y*ml run inside the
#     CALLING job's permission context — statically unverifiable, so a
#     consumer step inside a composite must carry `github_token:` on its own
#     `with:` to be resolvable (fail-loud for adjudication, never silent).
#
# The consumer population is DERIVED by grep census, never enumerated: adding
# a workflow that uses the action without a token path is a one-file change
# that reds this suite. Fixture runs override the scan roots with WF_DIR /
# ACT_DIR. NOTE: this file duplicates YAML-extraction idioms with
# reusable-release-caller-permissions.test.sh by convention (self-contained
# suites); a fix to a shared helper must be ported BOTH ways.
#
# Run via:  bash plugins/soleur/test/claude-code-action-auth.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_DIR="${WF_DIR:-$REPO_ROOT/.github/workflows}"
ACT_DIR="${ACT_DIR:-$REPO_ROOT/.github/actions}"

# Live (non-commented) `uses: anthropics/claude-code-action@…` — anchored to a
# step-shaped line, tolerant of a quoted scalar, pre-colon whitespace, and
# owner-case variants. `# uses: …` comments still cannot match (the `#` sits
# where the pattern wants whitespace-or-dash).
USES_ERE="^[[:space:]]+(-[[:space:]]+)?uses[[:space:]]*:[[:space:]]*[\"']?[Aa]nthropics/claude-code-action@"
# The same ERE in awk's dynamic-regexp form, for matching inside an accumulated
# multi-line job buffer: a consumer `uses:` is preceded by a newline or the
# buffer start (comments still cannot match — the `#` precedes the run).
AWK_USES_ERE="(\\n|^)[[:space:]]+(-[[:space:]]+)?uses[[:space:]]*:[[:space:]]*[\"']?[Aa]nthropics/claude-code-action@"
# `write` terminated by whitespace, EOL, or a `#` comment (POSIX classes; the
# GNU-only `\b` is not portable to mawk/BusyBox environments). `id-token :`
# with a pre-colon space is legal YAML GitHub accepts — tolerate it.
ID_TOKEN_ERE='^[[:space:]]+id-token[[:space:]]*:[[:space:]]*write([[:space:]]|$|#)'
# Flow-map classifier for a permissions VALUE: `id-token: write` as an ENTRY —
# a `id-token` key reachable from start/`{`/`,`/whitespace whose own colon leads
# to `write` — NOT the substring `id-token` followed by `write` anywhere later
# (`{id-token: none, contents: write}` is a denial, `{x-id-token: write}` an
# unknown key — neither grants).
ID_TOKEN_FLOW_ERE='(^|[{,[:space:]])id-token[[:space:]]*:[[:space:]]*write([[:space:],}]|$)'

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# YAML helpers (idioms mirrored from reusable-release-caller-permissions.test.sh
# — fix-bug ports flow BOTH directions; see the header's duplication note)
# ---------------------------------------------------------------------------

# Print the block of a named job (header through the line before the next job
# header), scoped to content after the top-level `jobs:` key.
named_job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    /^jobs[[:space:]]*:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*(#.*)?$/ {
      cur = $0; sub(/^  /, "", cur); sub(/:.*/, "", cur)
      inblock = (cur == job)
    }
    inblock { print }
  ' "$file"
}

# Print the NAME of every job in <file> whose block contains a live consumer
# `uses:` line for claude-code-action. The buffered match uses the same ERE as
# the file-level census so a consumer that one side sees cannot be missed by
# the other.
consumer_job_names() {
  local file="$1"
  awk -v pat="$AWK_USES_ERE" '
    /^jobs[[:space:]]*:[[:space:]]*$/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*(#.*)?$/ {
      if (name != "" && buf ~ pat) print name
      name = $0; sub(/^  /, "", name); sub(/:.*/, "", name); buf = ""; next
    }
    { buf = buf $0 ORS }
    END { if (name != "" && buf ~ pat) print name }
  ' "$file"
}

# Classify a `permissions:` declaration's id-token grant: granted|denied|none.
# $1 = ERE anchoring the key at its level ('^    permissions…' job-level,
#      '^permissions…' workflow-level — job keys are 4-space, workflow keys 0).
# $2 = ERE for a same-level sibling key that terminates the block.
# stdin: the text to scan (job block for job-level; whole file for workflow).
# Duplicate `permissions:` keys resolve LAST-wins (YAML semantics): `tail -1`.
perms_verdict() {
  local anchor="$1" term="$2" block permline lineno value sub
  block="$(cat)"
  permline="$(printf '%s\n' "$block" | grep -nE "$anchor" | tail -1)"
  if [[ -z "$permline" ]]; then
    echo "none"
    return
  fi
  lineno="${permline%%:*}"
  value="$(printf '%s\n' "$block" | sed -n "${lineno}p" \
    | sed -E "s/${anchor}[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//")"
  if [[ -z "$value" ]]; then
    # Block form: indented entries until the next same-level key.
    sub="$(printf '%s\n' "$block" \
      | awk -v s="$lineno" -v term="$term" 'NR > s { if ($0 ~ term) exit; print }')"
    if printf '%s\n' "$sub" | grep -qE "$ID_TOKEN_ERE"; then
      echo "granted"
    else
      echo "denied"
    fi
    return
  fi
  # Inline forms: `write-all` grants everything; a flow mapping grants iff an
  # `id-token: write` ENTRY exists (ID_TOKEN_FLOW_ERE — see its comment for why
  # substring matching misclassifies).
  if [[ "$value" == "write-all" ]]; then
    echo "granted"
  elif printf '%s\n' "$value" | grep -qE "$ID_TOKEN_FLOW_ERE"; then
    echo "granted"
  else
    echo "denied"
  fi
}

# Per consumer step in <stdin>, print `token` or `notoken` — arm A is a
# PER-STEP property: one `github_token:` satisfies only the step that carries
# it. Blank lines and comments carry no structural meaning (a blank line does
# NOT end a step span). `with:` must sit at the step's key indent; only its
# FIRST-child keys (the minimal indent under `with:`) count — a `github_token:`
# literal inside a `prompt: |` block scalar sits deeper and is ignored, as is a
# nested `{github_token: …}` subkey. The key requires a non-empty value.
consumer_step_tokens() {
  awk -v uses="$USES_ERE" '
    function flush() {
      if (incons) print (got_tok ? "token" : "notoken")
      incons = 0; inwith = 0; wind = 0
    }
    {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next
      match($0, /^[[:space:]]+/); ind = RLENGTH
      if ($0 ~ uses) {
        flush()
        incons = 1; got_tok = 0; inwith = 0; wind = 0
        # `- uses:` inline: the step key indent sits 2 cols right of the dash
        uind = ind; if ($0 ~ /^[[:space:]]+-/) uind += 2
        next
      }
      if (incons) {
        if (ind < uind) { flush(); next }
        if (ind == uind) {
          if ($0 ~ /^[[:space:]]+with[[:space:]]*:[[:space:]]*(#.*)?$/) { inwith = 1; wind = 0 }
          else inwith = 0
          next
        }
        if (inwith && ind > uind) {
          if (wind == 0) wind = ind
          if (ind == wind && $0 ~ /^[[:space:]]+github_token[[:space:]]*:[[:space:]]*[^[:space:]#]/)
            got_tok = 1
        }
      }
    }
    END { flush() }
  '
}

# ---------------------------------------------------------------------------
# Census: scan every workflow file in $1 (and composite actions in $2), evaluate
# every consuming STEP. Returns 0 when every consumer resolves a token path AND
# at least one workflow consumer exists, non-zero otherwise.
# ---------------------------------------------------------------------------
census_dir() {
  local dir="$1" actdir="${2:-$ACT_DIR}"
  local consumers=0 failures=0 file name job jv wv block st evaders jv_wv_done used_oidc
  local -a files=() jobs=() verdicts=() afiles=()

  # The population is the UNION of canonically-anchored consumers and ANY file
  # mentioning the action at all — a flow-style or misspelled `uses` that the
  # canonical ERE misses must still reach the evasion sweep.
  mapfile -t files < <({ grep -rlE "$USES_ERE" "$dir"/*.yml "$dir"/*.yaml; \
    grep -rl 'claude-code-action' "$dir"/*.yml "$dir"/*.yaml; } 2>/dev/null | sort -u)
  for file in "${files[@]:-}"; do
    [[ -n "$file" ]] || continue
    name="${file##*/}"

    # Anchor-evasion sweep: a `claude-code-action` mention on a `uses`-shaped
    # line that the canonical ERE did NOT match (flow-style step lists and
    # spellings the ERE does not cover) is a consumer this census would judge
    # blind. Comments are excluded; they satisfy nothing.
    evaders="$(grep -nE 'claude-code-action' "$file" \
      | sed -E 's/^[0-9]+://' \
      | grep -E 'uses[[:space:]]*:' \
      | grep -vE "$USES_ERE" \
      | grep -vE '^[[:space:]]*#' || true)"
    if [[ -n "$evaders" ]]; then
      echo "  FAIL: $name: claude-code-action on a non-canonical uses: line (possible anchor evasion):"
      printf '%s\n' "$evaders" | sed 's/^/      | /'
      failures=$((failures + 1))
    fi

    grep -qE "$USES_ERE" "$file" || continue   # mention-only file: sweep done, no consumer

    mapfile -t jobs < <(consumer_job_names "$file")
    if [[ "${#jobs[@]}" -eq 0 ]]; then
      echo "  FAIL: $name: consumer uses: line found but no containing job resolved"
      failures=$((failures + 1))
      continue
    fi
    jv_wv_done=0
    used_oidc=0
    for job in "${jobs[@]}"; do
      block="$(named_job_block "$file" "$job")"
      mapfile -t verdicts < <(printf '%s\n' "$block" | consumer_step_tokens)
      if [[ "${#verdicts[@]}" -eq 0 ]]; then
        echo "  FAIL: $name [$job]: job flagged as consumer but no consumer step resolved"
        failures=$((failures + 1))
        continue
      fi
      for st in "${verdicts[@]}"; do
        consumers=$((consumers + 1))
        # Arm A — the step bypasses OIDC with an explicit token input.
        if [[ "$st" == "token" ]]; then
          echo "  ok: $name [$job]: consumer step carries github_token: input (OIDC bypassed)"
          continue
        fi
        # Arm B — the effective permissions grant id-token: write. wv is
        # file-scoped (cached); jv is PER-JOB (each job may carry its own
        # replacing block — caching it across jobs would bleed grants).
        jv="$(printf '%s\n' "$block" \
          | perms_verdict '^    permissions[[:space:]]*:' '^    [A-Za-z0-9_-]+[[:space:]]*:')"
        if [[ "$jv_wv_done" -eq 0 ]]; then
          wv="$(perms_verdict '^permissions[[:space:]]*:' '^[A-Za-z]' < "$file")"
          jv_wv_done=1
        fi
        case "$jv" in
          granted)
            used_oidc=1
            echo "  ok: $name [$job]: job-level permissions grant id-token: write"
            ;;
          denied)
            echo "  FAIL: $name [$job]: job-level permissions: WITHOUT id-token: write (replaces workflow-level) and no github_token: input — getOidcToken hard-fails"
            failures=$((failures + 1))
            ;;
          none)
            if [[ "$wv" == "granted" ]]; then
              used_oidc=1
              echo "  ok: $name [$job]: inherits workflow-level id-token: write"
            else
              echo "  FAIL: $name [$job]: no id-token: write (job or workflow level) and no github_token: input — getOidcToken hard-fails"
              failures=$((failures + 1))
            fi
            ;;
          *)
            echo "  FAIL: $name [$job]: permissions verdict '$jv' unexpected — refusing to guess"
            failures=$((failures + 1))
            ;;
        esac
      done
    done

    # Adjudicated exception, kept VISIBLE: OIDC on a `pull_request` trigger
    # lets PR-head-controlled code mint the app token (the ADR-074 posture
    # Stage A avoids via github_token:). claude-code-review.yml carries this
    # deliberately; new pull_request consumers should use github_token:.
    if [[ "$used_oidc" -eq 1 ]] && grep -qE 'pull_request[[:space:]]*:' "$file"; then
      echo "  note: $name resolves via id-token on a pull_request trigger — adjudicated exception (ADR-074); new pull_request consumers should prefer github_token:"
    fi
  done

  # Composite actions: a consumer inside .github/actions/*/action.y*ml inherits
  # the CALLER job's permissions — statically unverifiable — so the step must
  # carry its own github_token: to be resolvable.
  mapfile -t afiles < <(grep -rlE "$USES_ERE" \
    "$actdir"/*/action.yml "$actdir"/*/action.yaml 2>/dev/null | sort)
  for file in "${afiles[@]:-}"; do
    [[ -n "$file" ]] || continue
    name="${file#"$REPO_ROOT/"}"
    mapfile -t verdicts < <(consumer_step_tokens < "$file")
    if [[ "${#verdicts[@]}" -eq 0 ]]; then
      echo "  FAIL: $name: composite contains consumer uses: but no consumer step resolved"
      failures=$((failures + 1))
      continue
    fi
    for st in "${verdicts[@]}"; do
      consumers=$((consumers + 1))
      if [[ "$st" == "token" ]]; then
        echo "  ok: $name: composite consumer step carries github_token: input"
      else
        echo "  FAIL: $name: composite-action consumer lacks github_token: — caller permissions are statically unverifiable"
        failures=$((failures + 1))
      fi
    done
  done

  echo "token-path census: ${consumers} consumer(s), ${failures} failure(s)"
  [[ "$consumers" -ge 1 && "$failures" -eq 0 ]]
}

# Run the census against fixture dirs; expected = PASS|FAIL; an expected FAIL
# must red for the RIGHT reason: rc == 1 (caught mutation — rc >= 2 is
# instrument breakage) and, when given, output matching <reason-re>.
fixture_row() {
  local label="$1" dir="$2" expected="$3" reason_re="${4:-}" actdir="${5:-}" out rc ok=0
  [[ -n "$actdir" ]] || actdir="$dir/.no-actions"
  out="$(census_dir "$dir" "$actdir" 2>&1)"; rc=$?
  if [[ "$expected" == "PASS" ]]; then
    [[ "$rc" -eq 0 ]] && ok=1
  elif [[ "$rc" -eq 1 ]]; then
    if [[ -z "$reason_re" || "$out" =~ $reason_re ]]; then ok=1; fi
  fi
  if [[ "$ok" -eq 1 ]]; then
    pass "mutation row: $label (expected $expected, got rc=$rc)"
  else
    fail "mutation row: $label (expected $expected${reason_re:+ matching [$reason_re]}, got rc=$rc)"
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
echo "1. Census consumers over $WF_DIR (+ composites under $ACT_DIR)"
if census_dir "$WF_DIR" "$ACT_DIR"; then
  pass "live tree: every claude-code-action consumer resolves a token path"
else
  fail "live tree: consumer(s) without a resolvable token path (see above)"
fi

# --- Section 2: mutation matrix ----------------------------------------------
echo ""
echo "2. Mutation matrix"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# Row 1: the drain defect shape — consumer with contents: read only, no
# github_token input. Expect RED.
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
fixture_row "1 consumer without token path" "$FIX/row1" FAIL "no id-token: write"

# Row 2: only non-consumer workflows → consumers=0 → RED (a census over nothing
# asserts nothing — dispatch vacuity).
mkfixture "$FIX/row2" "plain.yml" <<'YAML'
name: plain
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0000
YAML
fixture_row "2 zero consumers" "$FIX/row2" FAIL "0 consumer"

# Row 3: compliant file PLUS a non-compliant file → RED (the census must not
# stop at the first member).
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
fixture_row "3 second member non-compliant" "$FIX/row3" FAIL "no id-token: write"

# Row 4: the Stage A remediation shape — github_token: under with:, no id-token
# anywhere. Expect PASS (without this row the guard reddens its own fix).
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
fixture_row "5 job-level perms replace workflow-level" "$FIX/row5" FAIL "replaces workflow-level"

# Row 6: `# id-token: write` commented out under permissions. Expect RED —
# a commented grant is no grant (and the Stage A fix file carries exactly such
# a comment, so block scoping is load-bearing on the real tree too).
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
fixture_row "6 commented id-token grant" "$FIX/row6" FAIL "no id-token: write"

# Row 7: `id-token: write` string inside a step's env:/with: block, permissions
# without it. Expect RED — only a permissions: block counts.
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
fixture_row "7 id-token string outside permissions" "$FIX/row7" FAIL "no id-token: write"

# Row 8: `permissions: write-all` — functionally grants id-token. Expect PASS —
# a must-PASS non-canonical input; catches a reject-everything guard.
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

# Row 9: one commented-out consumer line plus one live compliant consumer —
# the comment satisfies nothing and must not be counted; the live step greens
# via workflow-level id-token. Expect PASS.
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

# Row 10: TWO consumer steps in one job — github_token: on only the second.
# The per-step property means the bare first step still OIDC-fails. Expect RED.
mkfixture "$FIX/row10" "two-steps.yml" <<'YAML'
name: two-steps
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        with:
          anthropic_api_key: ${{ secrets.X }}
      - uses: anthropics/claude-code-action@deadbeef
        with:
          github_token: ${{ github.token }}
YAML
fixture_row "10 sibling consumer step without token" "$FIX/row10" FAIL "no github_token"

# Row 11: `github_token:` as literal text inside a `prompt: |` block scalar.
# It is prompt DATA, not the step's input key. Expect RED.
mkfixture "$FIX/row11" "prompt-scalar.yml" <<'YAML'
name: prompt-scalar
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        with:
          prompt: |
            Restore github_token: configuration for the step.
            And mention github_token: ${{ github.token }} again.
          anthropic_api_key: ${{ secrets.X }}
YAML
fixture_row "11 github_token inside prompt scalar" "$FIX/row11" FAIL "no id-token: write"

# Row 12: quoted `uses:` scalar carrying github_token — the broadened ERE must
# SEE it (not silently skip) and classify it correctly. Expect PASS.
mkfixture "$FIX/row12" "quoted.yml" <<'YAML'
name: quoted
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: "anthropics/claude-code-action@deadbeef"
        with:
          github_token: ${{ github.token }}
YAML
fixture_row "12 quoted uses: with github_token" "$FIX/row12" PASS

# Row 13: job-level `permissions :` (space before colon — legal YAML) replaces
# a granted workflow-level block. The anchor must not miss the spaced key.
# Expect RED.
mkfixture "$FIX/row13" "spaced-key.yml" <<'YAML'
name: spaced-key
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  run:
    runs-on: ubuntu-latest
    permissions :
      contents: read
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "13 spaced permissions: key" "$FIX/row13" FAIL "replaces workflow-level"

# Row 14: flow-map `{id-token: none, contents: write}` — `write` appears but
# attaches to a SIBLING entry, not id-token's colon. Expect RED.
mkfixture "$FIX/row14" "flow-deny.yml" <<'YAML'
name: flow-deny
on: workflow_dispatch
permissions: {id-token: none, contents: write}
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "14 flow-map id-token: none" "$FIX/row14" FAIL "no id-token: write"

# Row 15: `github_token:` present but EMPTY — inputs.github_token == '' means
# the action still reaches getOidcToken. Expect RED.
mkfixture "$FIX/row15" "empty-token.yml" <<'YAML'
name: empty-token
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        with:
          github_token:
YAML
fixture_row "15 empty github_token value" "$FIX/row15" FAIL "no id-token: write"

# Row 16: `github_token:` separated from `with:` by a blank line and a comment —
# legal YAML; the step span must not terminate on blank/comment lines. PASS.
mkfixture "$FIX/row16" "gap-in-with.yml" <<'YAML'
name: gap-in-with
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
        with:
          anthropic_api_key: ${{ secrets.X }}

          # token path follows
          github_token: ${{ github.token }}
YAML
fixture_row "16 blank line inside with: block" "$FIX/row16" PASS

# Row 17: consumer inside a composite action without github_token:. Caller
# permissions are statically unverifiable — the composite must carry the
# input. Expect RED. (Workflows dir holds one compliant consumer so the
# vacuity gate does not fire instead.)
mkfixture "$FIX/row17" "wf.yml" <<'YAML'
name: wf
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
mkfixture "$FIX/row17-actions/wrap" "action.yml" <<'YAML'
name: wrap
runs:
  using: composite
  steps:
    - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "17 composite consumer lacks github_token" "$FIX/row17" FAIL "composite-action consumer" "$FIX/row17-actions"

# Row 18: duplicate workflow-level `permissions:` keys — YAML resolves
# LAST-wins, so a first granted block followed by a denied block must red.
mkfixture "$FIX/row18" "dup-keys.yml" <<'YAML'
name: dup-keys
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "18 duplicate permissions keys last-wins" "$FIX/row18" FAIL "no id-token: write"

# Row 19: job-level `id-token: write` positive arm — the grant need not live at
# workflow level. Expect PASS.
mkfixture "$FIX/row19" "job-grant.yml" <<'YAML'
name: job-grant
on: workflow_dispatch
permissions:
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: anthropics/claude-code-action@deadbeef
YAML
fixture_row "19 job-level id-token grant" "$FIX/row19" PASS

# Row 20: flow-style step list — `{uses: anthropics/…}` inside a flow sequence
# does not match the canonical ERE, so the anchor-evasion sweep must flag it.
# Expect RED.
mkfixture "$FIX/row20" "flow-steps.yml" <<'YAML'
name: flow-steps
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  run:
    runs-on: ubuntu-latest
    steps: [{uses: anthropics/claude-code-action@deadbeef}]
YAML
fixture_row "20 flow-style uses: evasion sweep" "$FIX/row20" FAIL "anchor evasion"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
