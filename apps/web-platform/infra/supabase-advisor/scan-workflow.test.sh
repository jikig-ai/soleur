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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/scheduled-supabase-advisor-scan.yml"
SCRIPT="$REPO_ROOT/scripts/supabase-advisor-scan.sh"
INNGEST_FN="$REPO_ROOT/apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts"
MONITORS_TF="$REPO_ROOT/apps/web-platform/infra/sentry/cron-monitors.tf"
APPLY_YML="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
MODEL_C4="$REPO_ROOT/knowledge-base/engineering/architecture/diagrams/model.c4"
HOOK="$REPO_ROOT/.claude/hooks/new-scheduled-cron-prefer-inngest.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

for f in "$WORKFLOW" "$SCRIPT" "$INNGEST_FN" "$MONITORS_TF" "$APPLY_YML" "$MODEL_C4"; do
  if [[ ! -f "$f" ]]; then
    printf 'FATAL: missing %s\n' "$f" >&2
    exit 1
  fi
done

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
# the exfil seam. Assert on the host-assignment line specifically.
if grep -E '^\s*API=' "$SCRIPT" | grep -qE '\$\{|\$\(|\$[A-Za-z_]'; then
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
script_code() { grep -vE '^\s*#' "$SCRIPT"; }
if script_code | grep -qF '.lints[]?'; then
  fail "script never uses the fail-open .lints[]? idiom" "found .lints[]? in CODE — a 401 body parses to 0 through it"
else
  pass "script never uses the fail-open .lints[]? idiom (code, comments excluded)"
fi
# Non-vacuity: the assertion above is only meaningful if the code actually
# parses .lints at all. Without this, deleting the parse entirely would pass.
if script_code | grep -qF '.lints[]'; then
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
if grep -qE 'code" != "200"' "$SCRIPT"; then
  pass "HTTP-status assertion present"
else
  fail "HTTP-status assertion present" "expected an explicit non-200 check"
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
# Extract the line number of the catalog query and of any advisor-count
# conditional, and assert the catalog is not lexically inside one.
cat_line="$(grep -nF 'as rls_off' "$SCRIPT" | head -1 | cut -d: -f1)"
# shellcheck disable=SC2016  # single-quoted literal regex matching the SUT's source text, not an expansion
adv_cond_line="$(grep -nE 'if \[\[ "\$advisor_count" -gt 0' "$SCRIPT" | head -1 | cut -d: -f1)"
if [[ -n "$cat_line" && -n "$adv_cond_line" && "$cat_line" -lt "$adv_cond_line" ]]; then
  pass "catalog query runs BEFORE (not inside) the advisor-non-zero branch"
else
  fail "catalog query is unconditional" "catalog at line ${cat_line:-?}, advisor-non-zero branch at line ${adv_cond_line:-?} — the catalog must not be gated on the advisor firing"
fi

echo "== both anti-exfil libs are SOURCED, never redefined =="
for lib in strip-log-injection scrub-supabase-pat; do
  if grep -qF "lib/${lib}.sh" "$SCRIPT"; then
    pass "sources lib/${lib}.sh"
  else
    fail "sources lib/${lib}.sh" "not sourced — this PR must add no new helper copy"
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
if grep -qE "failure\(\) *&& *steps\.[a-z]+\.outputs\.failure_mode" "$WORKFLOW"; then
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

echo "== cross-file: the monitor is actually APPLIED =="
# apply-sentry-infra.yml enumerates -target= per resource with no wildcard. A
# monitor without a matching line is declared but never applied: liveness dark.
if grep -qF 'resource "sentry_cron_monitor" "scheduled_supabase_advisor_scan"' "$MONITORS_TF"; then
  pass "monitor declared in cron-monitors.tf"
else
  fail "monitor declared in cron-monitors.tf" "resource not found"
fi
if grep -qF -- '-target=sentry_cron_monitor.scheduled_supabase_advisor_scan' "$APPLY_YML"; then
  pass "monitor has a -target= line (else it is declared but never applied)"
else
  fail "monitor has a -target= line" "without it the resource never applies and liveness ships dark"
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
