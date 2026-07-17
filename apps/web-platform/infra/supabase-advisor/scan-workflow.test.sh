#!/usr/bin/env bash
# Shape + cross-file drift guard for the nightly Supabase advisor RLS gate (#3366).
#
# WHY THIS FILE EXISTS
# ====================
# `actionlint` runs in ZERO CI workflows (it is a local-only tool here), so there
# is no CI gate a new workflow YAML must pass. A checked-in shape guard under
# apps/*/infra/** is the enforceable pattern.
#
# It is wired into .github/workflows/infra-validation.yml as an EXPLICIT step.
# That workflow hand-enumerates ~50 `run: bash ...test.sh` steps and has no
# glob/find runner — a new .test.sh is picked up by NOTHING. An unwired guard
# passes locally and gates nothing on every PR: present, and doing nothing.
# That is the same defect shape this whole gate exists to catch, which is why
# the wiring is asserted by AC9b rather than assumed.
#
# ANCHORING RULE OBSERVED THROUGHOUT
# ==================================
# Every assertion anchors on a SYNTACTIC construct, never a bare token that the
# file's own comments also contain. This file's subject legitimately discusses
# `.lints[]?`, `schedule:`, and `failure_mode` in prose to explain them, so a
# bare-token grep would match the explanation rather than the code and pass
# while the real construct was gone. Narrowing the scope is not the fix;
# anchoring on syntax is.
set -uo pipefail

DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR_SELF/../../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/scheduled-supabase-advisor-scan.yml"
# SCRIPT_OVERRIDE points this guard at a scratch copy so a mutation test never
# edits tracked source. Consumer: scan-workflow-mutation.test.sh.
#
# It is NOT a disarm switch, and that is measured, not asserted: every $SCRIPT
# rung below is paired with a non-vacuity rung that requires the target to carry
# the real sentinels, so an override pointing at a benign file goes RED (9 FAILs),
# not vacuously green. To pass, the target must already satisfy every property
# asserted here. The residual risk is a human mistaking an override run for a
# real audit, so an override announces itself — no CI-fail-closed check, because
# the mutation harness is a legitimate CI caller and a check it must bypass
# protects nothing.
SCRIPT="${SCRIPT_OVERRIDE:-$REPO_ROOT/scripts/supabase-advisor-scan.sh}"
[[ -z "${SCRIPT_OVERRIDE:-}" ]] || printf 'NOTE: auditing an override target, NOT tracked source: %s\n' "$SCRIPT" >&2
INNGEST_FN="$REPO_ROOT/apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts"
MONITORS_TF="$REPO_ROOT/apps/web-platform/infra/sentry/cron-monitors.tf"
APPLY_YML="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
MODEL_C4="$REPO_ROOT/knowledge-base/engineering/architecture/diagrams/model.c4"
HOOK="$REPO_ROOT/.claude/hooks/new-scheduled-cron-prefer-inngest.sh"
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
HARNESS="$REPO_ROOT/tests/scripts/test-supabase-advisor-scan.sh"
MUTATION_HARNESS="$DIR_SELF/scan-workflow-mutation.test.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

for f in "$WORKFLOW" "$SCRIPT" "$INNGEST_FN" "$MONITORS_TF" "$APPLY_YML" "$MODEL_C4"; do
  if [[ ! -f "$f" ]]; then
    printf 'FATAL: missing %s\n' "$f" >&2
    exit 1
  fi
done

echo "== BOTH gates are actually WIRED (this file's header claims it; now it asserts it) =="
# Nothing in this repo auto-discovers a test. infra-validation.yml enumerates
# ~50 explicit `run: bash …test.sh` steps with no glob runner, and test-all.sh
# hand-registers every tests/scripts/ suite (its own comment at the
# stock-preflight-gate line documents this exact trap). So an unregistered gate
# is a file nobody calls: green locally, gating nothing.
#
# This block exists because review caught the header ASSERTING its own wiring
# ("asserted by AC9b rather than assumed") while asserting no such thing — and
# caught the behavioural harness, which carries this PR's entire value claim,
# registered in ZERO runners. A PR arguing that unwired guards are worse than
# none had shipped its best guard unwired. Delete either line below and this
# goes RED.
if grep -qF 'bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh' "$INFRA_VALIDATION"; then
  pass "this shape guard is registered as a step in infra-validation.yml"
else
  fail "shape guard is wired" "no 'run: bash …/supabase-advisor/scan-workflow.test.sh' step in infra-validation.yml — this guard would never run in CI"
fi
if [[ -f "$HARNESS" ]]; then
  pass "the behavioural harness exists"
else
  fail "harness exists" "$HARNESS not found"
fi
if grep -qF 'bash tests/scripts/test-supabase-advisor-scan.sh' "$TEST_ALL"; then
  pass "the behavioural harness is registered in test-all.sh (the proof actually runs)"
else
  fail "harness is wired" "test-all.sh does not run tests/scripts/test-supabase-advisor-scan.sh — the proof that the gate cannot silently pass would gate NOTHING (nothing auto-discovers tests/scripts/)"
fi
# Third gate, same reasoning: the mutation attestation is what proves the checks
# below still DISCRIMINATE (they pass on an unmutated tree either way — #6572).
# Unregistered, it would be the strongest evidence in this subsystem, running nowhere.
if [[ -f "$MUTATION_HARNESS" ]] && grep -qF 'bash apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh' "$INFRA_VALIDATION"; then
  pass "the mutation attestation exists and is registered in infra-validation.yml"
else
  fail "mutation attestation is wired" "scan-workflow-mutation.test.sh is missing or has no 'run:' step in infra-validation.yml — this guard's non-vacuity would rest on prose again (#6572)"
fi
# Fourth gate, same reasoning, for the #6578 triage probe. The assertion lives
# HERE rather than in the probe's own attestation on purpose: a script cannot
# meaningfully assert its own registration, because an unregistered script never
# runs and its self-assertion never evaluates. Only a file that is itself already
# registered can carry the claim — which is exactly why the rung above sits here
# too. The probe is the one thing standing between this repo and a false
# all-clear on the SIGPIPE class; unregistered, it would be a measurement nobody
# takes.
SIGPIPE_PROBE="$REPO_ROOT/apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh"
if [[ -f "$SIGPIPE_PROBE" ]] && grep -qF 'bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh' "$INFRA_VALIDATION"; then
  pass "the sigpipe triage-feasibility probe exists and is registered in infra-validation.yml (#6578)"
else
  fail "sigpipe triage probe is wired" "apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh is missing or has no 'run:' step in infra-validation.yml — nothing would then verify that CI's grep can still observe this defect class at all"
fi
# ...and its ATTESTATION, which is the thing that proves the probe's own gates are
# not vacuous. Pinning only the probe stopped one step short of this rung's own
# argument: delete the attestation's run: step and every gate here stayed green
# while the entire non-vacuity apparatus silently stopped running.
SIGPIPE_ATTEST="$REPO_ROOT/apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh"
if [[ -f "$SIGPIPE_ATTEST" ]] && grep -qF 'bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh' "$INFRA_VALIDATION"; then
  pass "the sigpipe probe's attestation exists and is registered in infra-validation.yml (#6578)"
else
  fail "sigpipe attestation is wired" "sigpipe-triage-feasibility.test.sh is missing or has no 'run:' step in infra-validation.yml — the probe's false-all-clear guards would rest on prose, unproven, which is the exact failure this file exists to catch"
fi

echo "== no check in this file feeds a producer into grep -q (#6572) =="
# grep -q exits on FIRST MATCH. The producer's next write() then takes SIGPIPE
# (rc=141) and pipefail — set at the top of this file — promotes 141 to the
# pipeline status, INVERTING the if. Where match⇒pass that false-FAILs a correct
# tree (the observed #6572 symptom); where match⇒fail it false-PASSes, which is
# how the headline .lints[]? assertion below goes green while the idiom it
# forbids is present. Match against a here-string instead.
#
# SCHEDULING decides it, not a size threshold — do not reduce this to a byte
# count in either direction. The producer needs ≥2 write()s for a window to
# exist at all (~8 KB here = 2 writes), but whether the reader closes inside
# that window is a race:
#   - unperturbed locally the producer wins: 0/200 at the real 8 KB size;
#   - perturb it at that SAME size (run it under strace) and the producer is
#     killed by SIGPIPE — the window is real, not hypothetical;
#   - CI's scheduler is such a perturbation. #6572 is the log: `grep: write
#     error: Broken pipe`, same tree, re-run passed.
# It only becomes DETERMINISTIC once output exceeds the pipe buffer (~100 KB).
# So "it passes locally" is not evidence of anything, and neither is any single
# arming size; only a size-amplified differential discriminates.
#
# SCOPE: grep -q/--quiet only — the #6572 close condition. Other early-exiting
# consumers (| head -N, | jq -e) are NOT matched. They are safe here today only
# because each sits in an unchecked $( ), so nothing reads their 141; that is
# rc-discard, not design. Widen this if one ever gets status-checked.
#
# THREE NORMALISATIONS, each load-bearing — mutate any one out and a real bug
# escapes or a correct file false-FAILs (scan-workflow-mutation.test.sh proves it):
#   1. comments stripped   — this block's own prose describes the shape.
#   2. double-quoted strings stripped — a fail message naming the shape would
#      match ITSELF and false-FAIL forever. Comments are stripped here; string
#      literals are not. Real code still matches: its patterns are single-quoted
#      and the `| grep -q` token sits outside any quotes.
#   3. line-continuations and pipe-newlines folded — THIS FILE writes multi-line
#      pipes (the probe_hook jq chain above), so an author following house style
#      would otherwise evade this guard silently.
pipe_grep_q='[|][[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'
residual_hits="$(sed -E ':a;/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' "${BASH_SOURCE[0]}" \
  | grep -vE '^[[:space:]]*#' \
  | sed 's/"[^"]*"//g' \
  | sed -E ':b;/\|[[:space:]]*$/{N;s/\|[[:space:]]*\n[[:space:]]*/| /;bb}' \
  | grep -E "$pipe_grep_q")"
if [[ -z "$residual_hits" ]]; then
  pass "every check matches a here-string; none feeds a producer into an early-exiting matcher"
else
  # Print the offending text: a bare count makes the reader re-derive the regex.
  fail "no early-exit-pipe form remains" "$(printf '%s' "$residual_hits" | wc -l) site(s) invert under pipefail (#6572). Offending: $(printf '%s' "$residual_hits" | tr '\n' '~')"
fi

echo "== the hook allows this workflow (asserted by EXECUTING the hook) =="
# Assert by running the hook itself, not by re-implementing its predicate. Its
# regex is UNANCHORED — `(^|[[:space:]]|\n)(schedule|cron):([[:space:]]|\n|$)` —
# so a space-preceded `schedule:` token in a COMMENT denies the write. A
# re-implemented (anchored) check would pass here while the real hook denied.
#
# CRITICAL — WHY THE PROBE USES A SYNTHETIC PATH:
# The hook short-circuits to `allow` for any file that ALREADY EXISTS on
# origin/main (its own comment: "it's an Edit of an existing scheduled workflow
# — allow"). CI checks out with fetch-depth: 0, so origin/main is reachable.
# Probing with the REAL path would therefore return `allow` the moment this PR
# merges — passing because the file exists, NOT because its content is clean —
# and a later edit adding a bare `schedule:` would sail through a permanently
# vacuous check. Exactly the "looks present, does nothing" defect this whole
# gate exists to catch.
#
# So: probe under a `.github/workflows/scheduled-*.yml` path that matches the
# hook's glob but does NOT exist on main, which forces the CONTENT scan to run.
probe_hook() {
  # $1 = content to scan. Echoes the hook's permissionDecision.
  jq -nc --arg p "$REPO_ROOT/.github/workflows/scheduled-supabase-advisor-scan-guardprobe.yml" \
     --arg c "$1" --arg cwd "$REPO_ROOT" \
     '{tool_name:"Write", tool_input:{file_path:$p, content:$c}, cwd:$cwd}' \
    | bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}

if [[ ! -f "$HOOK" ]]; then
  fail "hook present" "$HOOK not found"
else
  # Prove the probe path is genuinely absent from main, or the content scan is
  # skipped and every assertion below is vacuous.
  if git -C "$REPO_ROOT" cat-file -e \
      "origin/main:.github/workflows/scheduled-supabase-advisor-scan-guardprobe.yml" 2>/dev/null; then
    fail "probe path is absent from main" "the probe path exists on main — the hook would early-allow and this check would be vacuous"
  else
    pass "probe path is absent from main (the hook's content scan will actually run)"
  fi

  if [[ "$(probe_hook "$(cat "$WORKFLOW")")" == "allow" ]]; then
    pass "new-scheduled-cron-prefer-inngest permits the workflow content"
  else
    fail "hook allows the workflow" "hook denied; a bare schedule/cron token likely leaked into prose — backtick-wrap it"
  fi

  # Mutation control: the same content plus one bare `schedule:` MUST be denied.
  # Without this, a hook that allowed everything (or a probe that never reached
  # the content scan) would look identical to a passing check.
  mutated="$(printf '%s\n# schedule: 0 3 * * *\n' "$(cat "$WORKFLOW")")"
  if [[ "$(probe_hook "$mutated")" == "deny" ]]; then
    pass "  ...and the hook DENIES the same file with a bare schedule token (probe is non-vacuous)"
  else
    fail "hook denies a bare schedule token" "the mutation was not denied — the probe is not reaching the hook's content scan, so the check above proves nothing"
  fi
fi

echo "== the workflow is dispatch-only and Inngest-scheduled =="
if grep -qE '^\s+workflow_dispatch:' "$WORKFLOW"; then
  pass "declares workflow_dispatch"
else
  fail "declares workflow_dispatch" "no workflow_dispatch trigger found"
fi
# Anchor on the YAML KEY at trigger indentation, not the bare word: the header
# comment legitimately explains why there is no GHA-fired schedule.
if grep -qE '^\s{0,4}(schedule|cron):' "$WORKFLOW"; then
  fail "no GHA schedule: trigger" "workflow declares a schedule:/cron: key — Inngest is the scheduling substrate (ADR-033)"
else
  pass "declares no GHA schedule:/cron: trigger key"
fi

echo "== the API host is pinned (PAT-exfil-via-redirect seam) =="
if grep -qF 'API="https://api.supabase.com"' "$SCRIPT"; then
  pass "host literal pinned in the script"
else
  fail "host literal pinned" "expected API=\"https://api.supabase.com\" in $SCRIPT"
fi
# The host line must not be interpolated from anywhere — an overridable host is
# the exfil seam. Assert on the host-assignment line specifically. Captured to a
# variable like every other producer here, so the match reads left-to-right.
api_line="$(grep -E '^\s*API=' "$SCRIPT")"
if grep -qE '\$\{|\$\(|\$[A-Za-z_]' <<<"$api_line"; then
  fail "host is not interpolated" "the API= line contains a shell/GHA expansion — it must be a literal"
else
  pass "host assignment contains no interpolation"
fi

echo "== all three refs are present and PAIRED with their expected project name =="
# Pairing is what makes a rotated/mis-pinned ref fail closed. grep cannot see
# variable flow, so the harness proves the behavior; here we prove the data is
# present and adjacent (ref:name on one line).
for pair in "mlwiodleouzwniehynfz:soleur-dev" "ifsccnjhymdmidffkzhl:soleur-web-platform" "pigsfuxruiopinouvjwy:soleur-inngest-prd"; do
  if grep -qF "\"$pair\"" "$WORKFLOW"; then
    pass "ref<->name pair present: $pair"
  else
    fail "ref<->name pair present: $pair" "not found as an adjacent pair in $WORKFLOW"
  fi
done
# The prd project is named soleur-web-platform, NOT soleur-prd. A preflight
# built on the guessed name would fail closed on every single run.
#
# Anchor on the ref:name PAIR syntax, not the bare token: the workflow's own
# comment says "NOT soleur-prd" to document this trap, and a bare-token grep
# matches that explanation and false-FAILS a correct file. This is the exact
# collision the header warns about — the moment a task needs both a
# "must-not-contain X" assertion and a comment documenting X, they fight.
if grep -qE '"[a-z0-9]+:soleur-prd"' "$WORKFLOW"; then
  fail "no phantom soleur-prd project name" "a ref is paired with the non-existent project 'soleur-prd'; the prd project is soleur-web-platform"
else
  pass "no ref is paired with a non-existent 'soleur-prd' project"
fi

echo "== the anti-fail-open sentinels are present in the script =="
# THE headline assertion. `.lints[]?` is what made the predecessor fail-open: a
# 401 body parses to 0, indistinguishable from clean.
#
# Two anchoring decisions, both load-bearing:
#  1. COMMENTS ARE STRIPPED FIRST. The script's header quotes the fail-open
#     idiom verbatim in order to explain it, so a whole-file grep matches the
#     explanation and false-FAILS a correct script. Assert over CODE only.
#  2. -F is deliberate. "Improving" this to grep -E makes the `]` optional
#     (`[]?` = zero-or-one `]`), so it would match the CORRECT `.lints[]` and
#     false-FAIL permanently.
#  3. CAPTURED ONCE, matched against a here-string — see the #6572 block above
#     for why the piped form could invert these two checks (a scheduling race,
#     not a certainty). The capture also runs the producer once rather than per
#     check.
script_code="$(grep -vE '^\s*#' "$SCRIPT")"
# NOT a fail-open guard, despite appearances — measured: delete this line, point
# $SCRIPT at an all-comment file, and the check below DOES take its `pass`
# branch, but the non-vacuity check after it catches the empty capture and the
# run still exits 1. This line is here for the DIAGNOSTIC: it turns five
# confusing downstream FAILs into one accurate line naming the cause.
# (`set -uo pipefail` carries no `-e`, so the empty assignment is itself silent.)
[[ -n "$script_code" ]] || { printf 'FATAL: no non-comment lines in %s\n' "$SCRIPT" >&2; exit 1; }
if grep -qF '.lints[]?' <<<"$script_code"; then
  fail "script never uses the fail-open .lints[]? idiom" "found .lints[]? in CODE — a 401 body parses to 0 through it"
else
  pass "script never uses the fail-open .lints[]? idiom (code, comments excluded)"
fi
# Non-vacuity: the assertion above is only meaningful if the code actually
# parses .lints at all. Without this, deleting the parse entirely would pass.
if grep -qF '.lints[]' <<<"$script_code"; then
  pass "  ...and the script does parse .lints[] (so the check above is not vacuous)"
else
  fail "script parses .lints[]" "no .lints[] parse found in code — the anti-fail-open check above would pass vacuously"
fi
if grep -qF 'has("lints")' "$SCRIPT"; then
  pass "structural assertion present (proves the array exists before counting)"
else
  fail "structural assertion present" "expected a has(\"lints\") guard"
fi
# The transport assertion: a non-200 must be a failure, never a zero.
#
# SCOPED TO THE ADVISOR BLOCK. A whole-file `grep 'code" != "200"'` matches FOUR
# sites (identity, advisor, catalog, object-lookup), so deleting the ADVISOR's
# rung — the literal 401 fail-open this PR exists to close — left this check
# green, satisfied by the catalog's line. Proven by mutation during review.
# A guard whose subject can be deleted while it stays green is not a guard.
advisor_block="$(awk '/^# --- Rung 2:/,/^# --- Rung 3:/' "$SCRIPT")"
if grep -qE 'code" != "200"' <<<"$advisor_block"; then
  pass "HTTP-status assertion present IN THE ADVISOR RUNG (not merely somewhere in the file)"
else
  fail "advisor HTTP-status assertion" "the advisor rung has no explicit non-200 check — a 401 would parse to a clean 0"
fi
# Same scoping for the structural rung, for the same reason.
if grep -qF 'has("lints")' <<<"$advisor_block"; then
  pass "structural assertion present IN THE ADVISOR RUNG"
else
  fail "advisor structural assertion" "the advisor rung has no has(\"lints\") guard"
fi

echo "== the catalog assertion is authoritative and UNCONDITIONAL =="
# It must not be nested inside an advisor-non-zero conditional: staleness cuts
# both ways, and a design that consults the catalog only when the advisor fires
# misses a stale-clean advisor over a live violation — rebuilding the fail-open
# one tier up. Anchor on the SQL alias, which only the real query carries.
if grep -qF 'rls_off' "$SCRIPT"; then
  pass "catalog assertion present"
else
  fail "catalog assertion present" "expected the rls_off catalog query"
fi
# Assert the catalog rung's GATE, not its line number.
#
# The previous version of this check compared line numbers ("catalog appears
# before the advisor-non-zero branch"). Line order is not unconditionality:
# review proved that rewriting the gate to `if ok && [[ "${advisor_count:-0}" !=
# "0" ]]` — which IS the fail-open this section exists to prevent — kept the
# line-order check green. It also hardcoded one spelling of the advisor
# conditional, so any rewording silently disarmed it.
#
# The real invariant: the catalog rung is gated on IDENTITY (a genuine
# precondition — we must know which project we are asserting against) and never
# on `ok` (which is false whenever the ADVISOR failed, so gating on it would make
# the coverage-bearing tier depend on the advisory one's health — ADR-112
# inverted through the back door). The behavioural harness proves both directions
# empirically; this is the structural companion.
rung3_gate="$(awk '/^# --- Rung 3:/,/^# --- Rung 4:/' "$SCRIPT" | grep -E '^if ' | head -1)"
if [[ "$rung3_gate" == *'identity_ok'* ]]; then
  pass "catalog rung is gated on identity_ok (runs even when the advisor is broken)"
else
  fail "catalog rung gate" "rung 3's gate is '${rung3_gate:-<none found>}' — it must gate on identity_ok, not on ok/advisor state, or an advisor outage silently retires the authoritative assertion"
fi
if grep -qE '(^|[^_])\bok\b|advisor' <<<"$rung3_gate"; then
  fail "catalog rung is not advisor-coupled" "rung 3's gate '${rung3_gate}' references ok/advisor — the catalog must not depend on the advisory tier"
else
  pass "catalog rung's gate references neither ok nor advisor state"
fi

echo "== both anti-exfil libs are SOURCED, never redefined =="
# ANCHOR ON THE `.` SOURCING SYNTAX, NOT THE BARE PATH. The path also appears in
# the `# shellcheck source=…` directive on the line ABOVE each real source, so a
# bare-path grep matched the COMMENT and stayed green with both real `.` lines
# deleted — proven by mutation during review. That was not cosmetic: with the
# libs unsourced, sanitize() returns empty, and (before the companion fix in the
# script's emit block) the verdict was derived from that empty value, so a
# confirmed violation emitted `scan_result=clean` exit 0. A permanently green
# gate, reachable by deleting two lines this guard claimed to protect.
for lib in strip-log-injection scrub-supabase-pat; do
  if grep -qE '^[[:space:]]*\.[[:space:]].*lib/'"$lib"'\.sh' <<<"$script_code"; then
    pass "sources lib/${lib}.sh (real '.' source line, not the shellcheck directive)"
  else
    fail "sources lib/${lib}.sh" "no actual '. …/lib/${lib}.sh' source line in code — sanitize() would degrade silently"
  fi
done
if grep -qE '^\s*(strip_log_injection|scrub_pat)\(\)' "$SCRIPT"; then
  fail "libs are not redefined inline" "the script redefines a helper instead of sourcing it"
else
  pass "neither helper is redefined inline"
fi

echo "== liveness cannot be forged =="
# Invariant 1: the check-in fires from the GHA workflow at END of run, never
# from the Inngest fn at dispatch time (that would cover only the first hop).
if grep -qF 'monitor-slug: scheduled-supabase-advisor-scan' "$WORKFLOW"; then
  pass "check-in lives in the GHA workflow"
else
  fail "check-in lives in the GHA workflow" "no sentry-heartbeat monitor-slug found"
fi
for forbidden in 'sentry-heartbeat' 'postSentryHeartbeat' 'monitor-slug'; do
  if grep -qF "$forbidden" "$INNGEST_FN"; then
    fail "Inngest fn posts no check-in" "found '$forbidden' in the dispatcher — a dispatch-time check-in covers only the first hop"
  else
    pass "Inngest fn contains no '$forbidden'"
  fi
done
# Invariant 2: only an Inngest-sourced run may post it, else any manual
# `gh workflow run` forges liveness while the dispatcher is dead.
if grep -qE "if: always\(\) && github\.event\.inputs\.source == 'inngest'" "$WORKFLOW"; then
  pass "check-in is gated on source == 'inngest' (a manual run cannot forge liveness)"
else
  fail "check-in is source-gated" "expected: if: always() && github.event.inputs.source == 'inngest'"
fi
if grep -qF 'inputs: { source: "inngest" }' "$INNGEST_FN"; then
  pass "the dispatcher actually sends source=inngest (else the gate above pages nightly)"
else
  fail "dispatcher sends source=inngest" "the check-in gate would never be satisfied — a missed check-in every night"
fi

echo "== issue filing cannot be silently skipped =="
# `if: failure() && steps.x.outputs.failure_mode != ''` files NOTHING when an
# unanticipated abort exits before the output is written. Assert the conjunct is
# absent — anchored on the conjunct's syntax, not the bare words.
if grep -qE "failure\(\) *&& *steps\.[a-z0-9_-]+\.outputs\.failure_mode" "$WORKFLOW"; then
  fail "issue step has no failure_mode conjunct" "found the conjunct — an unanticipated abort would file no issue at all"
else
  pass "issue step's if: failure() carries no failure_mode conjunct"
fi
if grep -qF "steps.scan.outputs.failure_mode || 'unknown_error'" "$WORKFLOW"; then
  pass "failure_mode defaults to unknown_error (every failure files something)"
else
  fail "failure_mode defaults to unknown_error" "expected a || 'unknown_error' default"
fi
# Dedupe must be by label: --search can return empty under some token contexts,
# which would file a fresh duplicate every night.
if grep -qE 'gh issue list .*--label "ci/supabase-advisor"' "$WORKFLOW"; then
  pass "dedupe is label-based"
else
  fail "dedupe is label-based" "expected gh issue list --label ci/supabase-advisor"
fi
if grep -qE 'gh issue list .*--search' "$WORKFLOW"; then
  fail "dedupe does not use --search" "--search can return empty under some token contexts -> a duplicate issue nightly"
else
  pass "dedupe never uses --search"
fi
# Two classes, two titles: with one title an expired PAT pages as a data
# exposure and a real violation only comments on the token issue.
for title in 'public table without RLS' 'scan failed'; do
  if grep -qF "[ci/supabase-advisor] $title" "$WORKFLOW"; then
    pass "issue class present: $title"
  else
    fail "issue class present: $title" "the two classes must have separate titles"
  fi
done
# A hook rejects gh issue create without --milestone.
if grep -qF -- '--milestone "Post-MVP / Later"' "$WORKFLOW"; then
  pass "gh issue create passes --milestone"
else
  fail "gh issue create passes --milestone" "a hook rejects issue creation without it"
fi

# NOTE — "monitor declared in cron-monitors.tf" is deliberately NOT asserted
# here. It is already covered, and covered BETTER, by
# apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts: it
# readdirSync's every workflow, extracts each `monitor-slug:`, and requires a
# matching sentry_cron_monitor — all-members and self-discovering, so it covered
# this new cron with no edit. (Until #6589 that test ALSO required a matching
# `-target=` line in apply-sentry-infra.yml; the full-root apply retired the
# allow-list, so declaring the resource now applies it and there is no target
# line to assert.) A hardcoded single-member copy here would be strictly weaker
# and would rot the moment the resource is renamed. Cite the parity test rather
# than duplicate it.

echo "== cross-file: the Inngest schedule and the Sentry monitor window agree =="
# The monitor's crontab defines the window in which a missed check-in pages. If
# the dispatcher's cron and the monitor's crontab drift apart, the gate either
# pages nightly for a run that arrived on time, or opens a blind window. Both
# operands are extracted by shape — hardcoding either would re-create the drift
# class this asserts against.
fn_cron="$(grep -oE '\{ cron: "[^"]+" \}' "$INNGEST_FN" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
tf_cron="$(awk '/resource "sentry_cron_monitor" "scheduled_supabase_advisor_scan"/,/^}/' "$MONITORS_TF" |
  grep -E '^\s*schedule\s*=' | head -1 | sed -E 's/.*crontab\s*=\s*"([^"]+)".*/\1/')"
if [[ -n "$fn_cron" && "$fn_cron" == "$tf_cron" ]]; then
  pass "Inngest cron '$fn_cron' == Sentry monitor crontab '$tf_cron'"
else
  fail "schedule agreement" "Inngest fn cron '${fn_cron:-<none>}' != monitor crontab '${tf_cron:-<none>}' — a missed check-in would page on a healthy run, or a blind window would open"
fi

echo "== cross-file: slugify(tf name) == workflow monitor-slug =="
tf_name="$(awk '/resource "sentry_cron_monitor" "scheduled_supabase_advisor_scan"/,/^}/' "$MONITORS_TF" \
  | grep -E '^\s*name\s*=' | head -1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
wf_slug="$(grep -E '^\s*monitor-slug:' "$WORKFLOW" | head -1 | sed -E 's/.*monitor-slug:\s*//')"
# Sentry derives the slug by slugifying `name`; writing `name` already
# slug-shaped makes the two literally equal.
tf_slug="$(printf '%s' "$tf_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
if [[ -n "$tf_slug" && "$tf_slug" == "$wf_slug" ]]; then
  pass "slugify('$tf_name') == monitor-slug '$wf_slug'"
else
  fail "slug agreement" "tf name '$tf_name' slugifies to '$tf_slug' but the workflow checks into '$wf_slug'"
fi

echo "== cross-file: model.c4's enumeration matches live cron-monitors.tf =="
# The C4 edge description carries a live COUNT. An AC asserting diagrams/ is
# untouched would have locked in a now-false model — verify the invariant, not
# the silence.
tf_count="$(grep -c '^resource "sentry_cron_monitor"' "$MONITORS_TF")"
c4_count="$(grep -oE 'Of [0-9]+ cron monitors' "$MODEL_C4" | head -1 | grep -oE '[0-9]+')"
if [[ -n "$c4_count" && "$tf_count" == "$c4_count" ]]; then
  pass "model.c4 says $c4_count cron monitors; cron-monitors.tf declares $tf_count"
else
  fail "model.c4 monitor count" "model.c4 says '${c4_count:-?}' but cron-monitors.tf declares $tf_count — refresh the github -> sentry description"
fi
# `--` is load-bearing: the pattern starts with a hyphen, which grep otherwise
# parses as an option (it exits 2 with a usage error, which is NOT a match and
# so reads as a legitimate failure — a real bug this guard hit on itself).
if grep -qF -- '-supabase-advisor-scan' "$MODEL_C4"; then
  pass "model.c4 names the new Inngest-dispatched workflow"
else
  fail "model.c4 names the new workflow" "the github -> sentry description enumerates the dispatch-only workflows"
fi

echo ""
if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
