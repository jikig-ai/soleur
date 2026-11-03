#!/usr/bin/env bash
#
# Drift guard for the "bwrap probe rolled a deploy back" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.bwrap_probe_rollback).
# Plan: knowledge-base/project/plans/archive/20261001-211644-2026-10-01-chore-alert-on-deploy-rollback-bwrap-probe-plan.md
#
# WHAT THE ALERT IS FOR. The canary stage of ci-deploy.sh runs a BLOCKING bwrap probe. When it fails
# the deploy rolls back and the script writes exactly one journald line under `logger -t ci-deploy`
# that starts `DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>:<tag> …`. Before this alert a
# recurrence was visible only through the release-failure email (which has failed once), the workflow
# annotation, or a hand-run query. The alert emails on one matching row.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The needle is READ FROM THE EMITTER (the BWRAP_LINE assignment in ci-deploy.sh), never retyped,
#     so a reworded marker reds here instead of silently disarming the alert.
#   * The predicate is exactly two ANDed conjuncts (the ci-deploy tag, and startsWith on the marker)
#     plus GROUP BY time: no OR, no negation, and deliberately NO host_name conjunct (web-2 and web-1's
#     pre-2026-09-19 host name carry the same rows; the luks sibling's host conjunct would exclude them).
#   * The paging semantics are monitor_send_failed's (ADR-218): threshold, higher_than 0,
#     treat_as_zero, unpaused, email, and the free/paid escalation ternary.
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist. This guard is the ONLY
#     enforcement of that for logtail resources: terraform-target-parity.test.ts covers terraform_data only.
#   * The runbook anchor in the alert's URL resolves to a real heading in canary-probe-set.md.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL a canon built from literals derived
#     out of the emitter (ci-deploy.sh's BWRAP_LINE assignment), never re-pinned literals.
#     Dead text — a /* */- or #-wrapped decoy heredoc — can never satisfy the pin: the extractor
#     reads the live local, the opener counts see the decoy, and the canon pins the body.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside its own
#     resource block by param(), which requires the whole value line anchored both ends,
#     exactly once. A second matching line inside the block, or a decoy block anywhere, goes red.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control exits the suite FATAL (rc 2) if the un-mutated inner run is not
#     green; MUT_SKIP/BWRAP_GUARD_* literals may not reach the workflow's executable text (the
#     seam check below); and mutate_floor_red proves the assertion floor itself fires.
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; an instrument
#     failure (rc>=2) is UNRESOLVED, never evidence. Floor and ledger trips are verdict-class
#     (exit 1); instrument failures are exit 2.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (the reconciler's `logs_alert`
# arm reads the live world twice daily), nor that a real rollback row reaches Better Stack (Vector
# allowlists the ci-deploy tag; the per-deploy SANDBOX_PROBE_OK row proves that path live). It compares
# values that one diff can edit together, so it proves consistency, not integrity.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the COPY,
# and re-runs this guard against it through the BWRAP_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${BWRAP_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${BWRAP_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CI="${BWRAP_GUARD_CI:-$REPO/apps/web-platform/infra/ci-deploy.sh}"
RB="${BWRAP_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/canary-probe-set.md}"
IV="${BWRAP_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` and point every awk/cp below at the wrong tree.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CI"; assert_fixture_dir "$RB"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the mutation battery needs it
' >&2; exit 2; }
for f in "$TF" "$WF" "$CI" "$RB" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
# sql_local: the heredoc body of `bwrap_probe_rollback_sql = <<[-]SQL` up to its `  SQL` closer,
# from the FIRST UNCOMMENTED opener line.
sql_local() {
  awk '/^[[:space:]]*bwrap_probe_rollback_sql[[:space:]]*=[[:space:]]*<<[-]SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
}
# res_block: one resource block from its column-0 header to its column-0 closing brace.
res_block() {
  awk -v h="resource \"$1\" \"$2\" {" '$0 == h {f=1} f{print} f && /^}/{exit}' "$TF"
}
# param <block> <attr> <value-ERE>: whole-line attribute assertion INSIDE a block, anchored
# both ends, required EXACTLY ONCE — a decoy or duplicated line is a red, not a shrug.
param() {
  # Value-matching exactly-once. Residual gap (accepted): a planted same-attr/different-value
  # line does not move this count — attr-name cardinality cannot apply here because blocks
  # legitimately nest a second `name` (explorations' `variable { name = "source" }`), and HCL
  # itself rejects duplicate attributes at validate. Mute/deletion classes are still covered.
  [ "$(printf '%s\n' "$1" | grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$")" -eq 1 ]
}
sql_has() {  # sql_has <fixed conjunct text, one normalised line of the heredoc>
  grep -qxF -- "AND $1" <<< "$SQL_N"
}

LOCAL_SQL="$(sql_local)"
# Whitespace-normalised view: the resource collapses every run of whitespace to one space
# (replace(trimspace(…), "/\\s+/", " ")), so indentation is not part of the contract.
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
# The alert and exploration blocks, from their exact header to the first column-0 "}".
ALERT="$(res_block logtail_exploration_alert bwrap_probe_rollback)"
EXPL="$(res_block logtail_exploration bwrap_probe_rollback)"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to the first `rc=`
# line-start below it (the plan step's own rc=${PIPESTATUS[0]} capture). The workflow has other
# plan commands (inngest host, host replace, volume recut) whose -target lists never run on a
# push to main, so the allowlist rows below read THIS region, not the whole file.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=/{exit}' "$WF")"
# The slice must actually TERMINATE on the plan step's own rc=${PIPESTATUS[0]} capture: a
# deleted or renamed capture line would silently reopen the run-to-EOF overshoot this bound
# fixes (a bare `rc=` terminator lands on a LATER step's `rc=0` and overshoots undetected).
# Count-compare on tail -1 — never `| grep -q` (SIGPIPE under pipefail).
[ "$(tail -1 <<< "$MAIN_PLAN" | grep -cE '^[[:space:]]*rc=[$][{]PIPESTATUS')" -eq 1 ] \
  && ok "the MAIN plan slice terminates on the plan step's rc=\${PIPESTATUS} capture (no run-to-EOF overshoot)" \
  || no "the MAIN plan slice never terminated on the plan step's rc=\${PIPESTATUS} capture — a deleted or renamed capture line reopened the run-to-EOF overshoot"

# Every grep over a captured VARIABLE reads a HERE-STRING, never `printf … | grep -q`: under pipefail, grep -q exiting on its
# first match can SIGPIPE the writer and fail the pipeline, which fails a negated check OPEN.

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "bwrap_probe_rollback_sql: heredoc not found — every predicate row below would be vacuous"

# Opener counts — an unanchored file-wide count must equal exactly 1, so a /* */- or #-wrapped
# decoy opener still counts and goes red.
_n_sql_openers="$(grep -cE 'bwrap_probe_rollback_sql[[:space:]]*=[[:space:]]*<<[-]SQL' "$TF")"
[ "$_n_sql_openers" -eq 1 ] \
  && ok "exactly one bwrap_probe_rollback_sql heredoc opener in the file (decoy copies count)" \
  || no "bwrap_probe_rollback_sql opener count is $_n_sql_openers, want 1 — a decoy local exists"
_n_exp="$(grep -cE 'resource "logtail_exploration" "bwrap_probe_rollback"' "$TF")"
[ "$_n_exp" -eq 1 ] \
  && ok "exactly one logtail_exploration.bwrap_probe_rollback resource header" \
  || no "logtail_exploration header count is $_n_exp, want 1 — a decoy resource exists"
_n_alr="$(grep -cE 'resource "logtail_exploration_alert" "bwrap_probe_rollback"' "$TF")"
[ "$_n_alr" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.bwrap_probe_rollback resource header" \
  || no "logtail_exploration_alert header count is $_n_alr, want 1 — a decoy resource exists"

_head="$(head -3 <<< "$SQL_N" | paste -sd' ')"
grep -qxF 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}' <<< "$_head" \
  && ok "the head is the per-bucket count shape monitor_send_failed uses (ADR-218)" \
  || no "the predicate head is not SELECT {{time}} … count(*) … WHERE time BETWEEN {{start_time}} AND {{end_time}}"

# The needle is READ from the emitter: the single BWRAP_LINE assignment in ci-deploy.sh, up to the
# ` in $IMAGE:$TAG` the line appends. A reworded marker changes this value and reds the rows below.
EMIT_LINES="$(grep -E '^[[:space:]]*BWRAP_LINE="DEPLOY_ROLLBACK: ' "$CI")"
NEEDLE="$(sed -n 's/^[[:space:]]*BWRAP_LINE="\(DEPLOY_ROLLBACK: [^$"]*\) in \$IMAGE:\$TAG .*/\1/p' <<< "$EMIT_LINES" | head -1)"
if [ -n "$NEEDLE" ] && [ "$(grep -c . <<< "$EMIT_LINES")" -eq 1 ]; then
  ok "ci-deploy.sh has exactly one BWRAP_LINE emitter; needle read from it: '$NEEDLE'"
else
  no "ci-deploy.sh no longer has exactly one parseable BWRAP_LINE='DEPLOY_ROLLBACK: … in \$IMAGE:\$TAG …' assignment — the alert would silently stop matching"
fi
grep -qxF 'readonly LOG_TAG="ci-deploy"' "$CI" \
  && ok "LOG_TAG is ci-deploy (the SYSLOG_IDENTIFIER the predicate matches, Vector-allowlisted)" \
  || no "ci-deploy.sh no longer declares readonly LOG_TAG=\"ci-deploy\""
# The needle is read from the ASSIGNMENT; the SINK decides what journald actually carries. Pin the one
# call that publishes the row: tagged, and with the message exactly "$BWRAP_LINE" (a prefix would stop
# the message starting with the marker).
[ "$(grep -cE '^[[:space:]]*logger -t "\$LOG_TAG" "\$BWRAP_LINE"( \|\| .*)?$' "$CI")" -eq 1 ] \
  && ok "the single sink is logger -t \"\$LOG_TAG\" \"\$BWRAP_LINE\": the journald row carries the ci-deploy tag and starts with the needle" \
  || no "ci-deploy.sh no longer emits the BWRAP_LINE logger sink as logger -t \"\$LOG_TAG\" \"\$BWRAP_LINE\" — the alert would never see the row"

sql_has "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'ci-deploy'" \
  || no "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing or altered"

if [ -n "$NEEDLE" ] && sql_has "startsWith(JSONExtractString(raw, 'message'), '$NEEDLE')"; then
  ok "the marker anchor: the message STARTS with the emitter's needle (a row merely quoting it cannot alert)"
else
  no "the startsWith conjunct is missing, altered, or no longer equals the needle read from ci-deploy.sh"
fi

# Exactly the head, two AND conjuncts and GROUP BY: no OR, no negation, no third clause that could
# narrow the rule to nothing or widen it past the marker.
_body="$(sed -n '4,$p' <<< "$SQL_N")"
if [ "$(grep -c '^AND ' <<< "$_body")" -eq 2 ] \
   && [ "$(grep -vc '^AND ' <<< "$_body")" -eq 1 ] \
   && [ "$(tail -1 <<< "$_body")" = 'GROUP BY time' ] \
   && ! grep -qiE '(^|[^A-Za-z_])(OR|NOT)([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "the predicate is exactly two ANDed conjuncts and GROUP BY time (no OR, no negation)"
else
  no "the predicate carries an OR, a negation or an extra clause"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would exclude web-2 and web-1's pre-rename host name" \
  || ok "no host_name conjunct: any deploy host's rollback alerts"

# CANONICAL EQUALITY — the flattened heredoc must EQUAL this canon, built from the
# emitter-derived NEEDLE (never a re-pinned literal). A dead-text copy satisfies no row: the
# extractor reads the live local, and any arithmetic/widening edit breaks the byte compare.
PRED_FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
BWRAP_CANON="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy' AND startsWith(JSONExtractString(raw, 'message'), '${NEEDLE}') GROUP BY time"
[ "$PRED_FLAT" = "$BWRAP_CANON" ] \
  && ok "the whole predicate is byte-exact against the emitter-derived canon (dead text cannot satisfy it)" \
  || no "the predicate drifted from the pinned text — diff the flat extraction against BWRAP_CANON"

param "$EXPL" 'sql_query' 'replace\(trimspace\(local\.bwrap_probe_rollback_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.bwrap_probe_rollback_sql as its sql_query"
param "$EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.bwrap_probe_rollback exists (exact header)" \
  || no "logtail_exploration_alert.bwrap_probe_rollback is missing"
param "$ALERT" 'exploration_id' 'logtail_exploration\.bwrap_probe_rollback\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.bwrap_probe_rollback.id"
param "$ALERT" 'name' '"soleur-bwrap-probe-rollback-prd"' \
  && param "$EXPL" 'name' '"soleur-bwrap-probe-rollback-prd"' \
  && ok "both are named soleur-bwrap-probe-rollback-prd" \
  || no "the exploration/alert name drifted from soleur-bwrap-probe-rollback-prd"
param "$ALERT" 'alert_type' '"threshold"' \
  && param "$ALERT" 'operator' '"higher_than"' \
  && param "$ALERT" 'value' '0' \
  && ok "threshold, higher_than 0: ONE rollback row alerts (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single rollback would not alert"
param "$ALERT" 'on_missing_data' '"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
param "$ALERT" 'paused' 'false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
[ "$(printf '%s\n' "$ALERT" | grep -c 'paused')" -eq 1 ] \
  && ok "the string 'paused' occurs exactly once in the alert block (a commented or duplicated decoy counts)" \
  || no "'paused' occurs !=1 time in the alert block — a commented pinned-line decoy exists"
param "$ALERT" 'email' 'true' \
  && ok "email = true (the free-tier alerting surface)" \
  || no "email is not true"
param "$ALERT" 'confirmation_period' '0' \
  && param "$ALERT" 'recovery_period' '600' \
  && ok "confirmation_period 0 and recovery_period 600: one row alerts within about a minute, and the incident auto-resolves after 10 quiet minutes" \
  || no "confirmation_period is not 0 or recovery_period is not 600 — a single rollback would not alert promptly, or the incident would not auto-resolve after 10 quiet minutes"
# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside EITHER resource block.
if [ "$(printf '%s\n%s\n' "$EXPL" "$ALERT" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes mute knob inside either resource block"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi
param "$ALERT" 'query_period' '300' \
  && param "$ALERT" 'check_period' '60' \
  && ok "evaluated every 60s over a 300s window (exact pins, not a first-hit range read)" \
  || no "query_period is not 300 or check_period is not 60 (exactly once each)"
param "$ALERT" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALERT" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"

RB_URL_RE='^[[:space:]]*bwrap_probe_rollback_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set\.md#[a-z0-9-]+"'
grep -qE '^[[:space:]]*incident_cause[[:space:]]*=.*Runbook: \$\{local\.bwrap_probe_rollback_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && param "$ALERT" 'runbook' 'local\.bwrap_probe_rollback_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the canary-probe-set runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable canary-probe-set runbook URL"

grep -qE '^[[:space:]]*-target=logtail_exploration\.bwrap_probe_rollback \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.bwrap_probe_rollback \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

# The alert's runbook link must land on a real heading: the URL slug is compared with the GitHub
# slug of every heading in the runbook (fenced blocks skipped; punctuation dropped, spaces to dashes).
RB_SLUG="$(grep -E "$RB_URL_RE" "$TF" | head -1 | sed 's/.*#\([a-z0-9-]*\)".*/\1/')"
rb_rc=0
python3 - "$RB" "$RB_SLUG" <<'PY' || rb_rc=$?
import re, sys
path, want = sys.argv[1], sys.argv[2]
fence = False
slugs = set()
for line in open(path, encoding="utf-8"):
    if line.startswith("```"):
        fence = not fence
        continue
    if fence:
        continue
    m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
    if not m:
        continue
    t = re.sub(r"[^\w\- ]", "", m.group(1).strip().lower())
    slugs.add(t.replace(" ", "-"))
sys.exit(0 if want and want in slugs else 1)
PY
[ "$rb_rc" -eq 0 ] \
  && ok "the runbook anchor '#${RB_SLUG}' resolves to a heading in canary-probe-set.md" \
  || no "the runbook anchor '#${RB_SLUG:-?}' matches no heading in canary-probe-set.md — the alert's link would dangle"

# ── Workflow seam — registered, unconditionally blocking, and no env axis may reach it ───────
# The run line pins byte-exact (exactly once) so a rename/moved step cannot silently unregister
# the suite; and no env-composition FRAGMENT may appear in the workflow's executable text — the
# literal `MUT_SKIP`/`BWRAP_GUARD_` greps are subsumed by the fragment set
# {MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS, BASHOPTS}, which also bars runtime-composed names
# ("MUT_""SKIP", any *_GUARD_* prefix) and the shell-injection env names a smuggler would use.
# Whole-line comments are stripped; an inline ` # MUT_SKIP` still reds — deliberate over-caution.
REG_RUN='        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh'
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"

seam_bad=""
printf '%s\n' "$IV_CODE" | grep -nE 'BWRAP_GUARD_' >/dev/null && seam_bad="$seam_bad BWRAP_GUARD_-literal"
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  printf '%s\n' "$IV_CODE" | grep -nF -- "$_frag" >/dev/null && seam_bad="$seam_bad ${_frag}-fragment"
done
[ -z "$seam_bad" ] \
  && ok "no BWRAP_GUARD_ literal or env-composition fragment reaches the workflow's executable text (literal, composed or injected env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

# Enclosing-job slice: the job block containing the pinned run line — walk back to the nearest
# `^  <job-id>:` header, forward to the next or EOF. Derived from the run line (never a hardcoded
# job name) and asserted non-empty AND containing the run line, so the env-write ban below can
# never pass vacuously on an empty or missliced region.
IV_JOB="$(awk -v run="$REG_RUN" '
  { L[NR] = $0 }
  $0 == run { here = NR }
  /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { hdr[++nh] = NR }
  END {
    if (!here) exit 0
    lo = 0; hi = NR + 1
    for (i = 1; i <= nh; i++) {
      if (hdr[i] < here) { lo = hdr[i] } else { hi = hdr[i]; break }
    }
    if (lo) for (i = lo; i < hi; i++) print L[i]
  }
' <<< "$IV_CODE")"
if [ -n "$IV_JOB" ] && [ "$(grep -cxF "$REG_RUN" <<< "$IV_JOB")" -eq 1 ]; then
  ok "the enclosing job block holds this suite's run line (the env-write ban below is never vacuous)"
else
  no "the enclosing job slice is empty or misses the run line — the env-write ban below would pass vacuously"
fi
job_bad=""
printf '%s\n' "$IV_JOB" | grep -nE 'GITHUB_(ENV|PATH)' >/dev/null && job_bad="$job_bad GITHUB_ENV/GITHUB_PATH"
printf '%s\n' "$IV_JOB" | grep -nE '^[[:space:]]*defaults:' >/dev/null && job_bad="$job_bad defaults:"
[ -z "$job_bad" ] \
  && ok "no \$GITHUB_ENV/\$GITHUB_PATH write or defaults: inside the enclosing job (the only runtime env-composition channel is barred)" \
  || no "enclosing-job seam violated:$job_bad — a composed env name could reach this suite's step"

# Step-shape pins — the step block and job header enclosing the run line: no `if:` or
# `continue-on-error:` at step indent inside IV_STEP; the job's `if:` is the one known literal
# exactly once; no `continue-on-error:` in IV_HDR (the job header before `steps:`).
IV_STEP="$(awk -v run="$REG_RUN" '
  { L[NR] = $0 }
  $0 == run { here = NR }
  END {
    if (!here) exit 0
    lo = 0; hi = NR + 1
    for (i = here; i >= 1; i--) { if (L[i] ~ /^      - /) { lo = i; break } }
    for (i = here + 1; i <= NR; i++) { if (L[i] ~ /^      - / || L[i] ~ /^    [^ ]/) { hi = i; break } }
    if (lo) for (i = lo; i < hi; i++) print L[i]
  }
' <<< "$IV_JOB")"
IV_HDR="$(awk '/^    steps:$/{exit} {print}' <<< "$IV_JOB")"
if [ -n "$IV_STEP" ] \
   && [ "$(grep -cxF "$REG_RUN" <<< "$IV_STEP")" -eq 1 ] \
   && ! grep -qE '^        (if|continue-on-error):' <<< "$IV_STEP" \
   && [ "$(grep -cxF "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" <<< "$IV_HDR")" -eq 1 ] \
   && ! grep -qE '^    continue-on-error:' <<< "$IV_HDR"; then
  ok "the suite's step is unconditional and blocking (no step if:/continue-on-error:, the job's dedup if: is the one literal, no job continue-on-error:)"
else
  no "the suite's step or job is conditional or non-blocking — an if: or continue-on-error: would mute or weaken this suite in CI"
fi

echo ""
echo "=== bwrap-probe-rollback-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED (must-PASS rows stay GREEN) ─────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching BWRAP_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t bwrapalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  PRELUDE='def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
def bw_replace(s, old, new):
    # The first occurrence AFTER the predicate local'\''s opening line: other alerts in this
    # file carry identical tag conjuncts earlier on.
    i = s.index("  bwrap_probe_rollback_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
SQLLOC = "  bwrap_probe_rollback_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
EXPRES = "resource \"logtail_exploration\" \"bwrap_probe_rollback\" {"
ALRRES = "resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" {"'

  # _red_verdict <rc> <log> <fragment>: prints red | wrong | survived | unresolved. Only rc=1
  # is a caught mutation; when a fragment is named a [FAIL] line must contain it. Pipe-free of
  # `grep -q` upstream (SIGPIPE under pipefail); plain grep -F >/dev/null reads the whole stream.
  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|CI|RB|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  # The heredoc below is UNQUOTED on purpose: the shell interpolates $PRELUDE/$prog exactly once
  # and never rescans the result. Their text must therefore stay free of $, backticks and
  # backslashes the shell would otherwise eat — python writes them as \xNN escapes.
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/ci-deploy.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/canary-probe-set.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
$PRELUDE
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "BWRAP_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    # rc DISCRIMINATION: rc>=2 is this guard's own FATAL class, never evidence. want=wrong is
    # the scorer's NEGATIVE CONTROL: a mutant that reds a row other than the one the fragment
    # names must grade WRONG, or every fragment check is decoration.
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # mutate_green <label> <TF|WF|CI|RB|IV> <python-program-on-s>: a legitimate edit must NOT red
  # the guard. Axis-widened past the donor's TF-only shape so the workflow/wiring must-PASS
  # controls ride the same helper.
  mutate_green() {
    local label="$1" which="$2" prog="$3" src copy rc=0
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/ci-deploy.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/canary-probe-set.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate_green: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_green: cp failed\n' >&2; exit 2; }
    python3 - "$copy" <<PY || { no "must-PASS '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
$PRELUDE
orig = open(p, encoding="utf-8").read()
s = orig
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "BWRAP_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  # mutate_floor_red: bumping PRESENCE_ROWS +1 in a scratch copy of SELF must trip the floor —
  # proves the floor is not dead text. The copy's REPO line is rewritten so its reads resolve.
  mutate_floor_red() {
    local label="$1" copy rc=0 cur
    copy="$MUT_DIR/floor-mutated.test.sh"
    cur="$(grep -oE '^PRESENCE_ROWS=[0-9]+$' "$SELF" | cut -d= -f2)"
    [ -n "$cur" ] || { no "mutation '$label' did not land (no PRESENCE_ROWS declaration)"; return 0; }
    sed -e "s/^PRESENCE_ROWS=${cur}$/PRESENCE_ROWS=$((cur + 1))/" \
        -e "s|^REPO=.*|REPO=\"$REPO\"|" "$SELF" > "$copy"
    if cmp -s "$SELF" "$copy"; then no "mutation '$label' did not land (PRESENCE_ROWS anchor drifted)"; return 0; fi
    MUT_SKIP=1 bash "$copy" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label - the assertion floor pins nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label - instrument, not evidence" ;;
    esac
  }

  # ── Dead-text / extraction-class rows ──────────────────────────────────────────────────────
  mutate_red "a /* */-wrapped decoy heredoc sits before the live local while the live body is gutted" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(SQLLOC)
s = s[:i] + "/*\n  bwrap_probe_rollback_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # bwrap_probe_rollback_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "carries an OR"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* \x24\x24escaped */", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT 1", SQLEND)' \
    "drifted from the pinned"
  mutate_red "a second logtail_exploration_alert carries the same name after the compliant first" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" {\n}\n"' \
    "decoy resource exists"

  # ── Predicate rows ─────────────────────────────────────────────────────────────────────────
  # R1 — the marker is reworded in the EMITTER only; the alert's literal is untouched.
  mutate_red "the marker is reworded in ci-deploy.sh only (the alert would silently stop matching)" CI \
    'old = "BWRAP_LINE=\"DEPLOY_ROLLBACK: bwrap sandbox non-functional in "
assert s.count(old) == 1
s = s.replace(old, "BWRAP_LINE=\"DEPLOY_ROLLBACK: bwrap sandbox nonfunctional in ")' \
    "the startsWith conjunct is missing"
  # R2 — the tag conjunct is dropped: rows quoting the marker under another identifier could alert.
  mutate_red "the tag conjunct is dropped (quoting rows under another SYSLOG_IDENTIFIER could alert)" TF \
    's = bw_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n", "")' \
    "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing"
  # R3 — startsWith becomes position(): a row that merely CONTAINS the phrase could alert.
  mutate_red "startsWith is replaced by position() (a row merely containing the phrase could alert)" TF \
    's = bw_replace(s, "startsWith(JSONExtractString(raw, \x27message\x27), \x27DEPLOY_ROLLBACK: bwrap sandbox non-functional\x27)", "position(JSONExtractString(raw, \x27message\x27), \x27DEPLOY_ROLLBACK: bwrap sandbox non-functional\x27) > 0")' \
    "the startsWith conjunct is missing"
  # R4 — the luks-precedent host conjunct is added: web-2 and web-1's pre-rename host would go silent.
  mutate_red "a host_name conjunct is added (web-2 and the pre-rename web-1 name would go silent)" TF \
    's = bw_replace(s, "    GROUP BY time\n", "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")' \
    "the predicate carries a host_name conjunct"
  # R5 — an OR clause is appended after both conjuncts with every anchor still present.
  mutate_red "an OR clause is appended after both conjuncts (every anchor still present)" TF \
    's = bw_replace(s, "    GROUP BY time\n", "      OR JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n    GROUP BY time\n")' \
    "carries an OR"
  # R15 — the needle drifts in the TF only: the emitter and the alert would disagree.
  mutate_red "the alert's needle drifts away from the emitter's (TF only)" TF \
    's = bw_replace(s, "non-functional\x27)", "non-functionalX\x27)")' \
    "the startsWith conjunct is missing"
  # R9 — the guard's OWN dispatch: the locals key is renamed so the heredoc extractor returns empty.
  # A guard reporting "0 checked" and exiting 0 is vacuous; the heredoc-found row must RED.
  mutate_red "the predicate local is renamed so the heredoc extractor finds nothing (the guard must not go vacuous)" TF \
    'assert s.count(SQLLOC) == 1
s = s.replace(SQLLOC, "  bwrap_probe_rollback_sql_renamed = <<\x2dSQL")' \
    "heredoc not found"

  # ── Alert-attribute rows ──────────────────────────────────────────────────────────────────
  # R7 — armed-ness and one-row alerting, each its own row.
  mutate_red "the alert is paused" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "the alert is paused"
  mutate_red "the threshold value is raised to 1 (a single rollback no longer alerts)" TF \
    's = edit(s, ALRRES, "  value               = 0\n", "  value               = 1\n")' \
    "the alert is not threshold/higher_than/0"
  mutate_red "confirmation_period is raised to 3600 (one row would never alert)" TF \
    's = edit(s, ALRRES, "  confirmation_period = 0\n", "  confirmation_period = 3600\n")' \
    "confirmation_period is not 0"
  mutate_red "on_missing_data is no longer treat_as_zero" TF \
    's = edit(s, ALRRES, "on_missing_data     = \"treat_as_zero\"", "on_missing_data     = \"keep_last_value\"")' \
    "on_missing_data is not treat_as_zero"
  mutate_red "the operator flips to lower_than (silence alerts, a rollback does not)" TF \
    's = edit(s, ALRRES, "operator            = \"higher_than\"", "operator            = \"lower_than\"")' \
    "the alert is not threshold/higher_than/0"
  mutate_red "email is switched off (the free-tier alerting surface)" TF \
    's = edit(s, ALRRES, "  email          = true\n", "  email          = false\n")' \
    "email is not true"
  # R14 — the alert watches another exploration.
  mutate_red "the alert watches another exploration" TF \
    'old = "exploration_id = logtail_exploration.bwrap_probe_rollback.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")' \
    "the alert's exploration_id is not"
  # R18 — a meta-argument is added to the alert: every pinned attribute stays, the resource does not.
  mutate_red "count = 0 is added to the alert (every pinned line present, resource never created)" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  # ── Apply-allowlist rows ───────────────────────────────────────────────────────────────────
  # R6 — either -target= line is dropped: an untargeted resource is never applied.
  mutate_red "the exploration is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.bwrap_probe_rollback \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines are missing"
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.bwrap_probe_rollback \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines are missing"
  # R17 — both -target= lines are MOVED out of the main plan (not deleted): they would still be
  # present in the file while the push-triggered apply never plans the resources.
  mutate_red "the -target= lines move out of the main plan (still in the file, never applied)" WF \
    'a = "              -target=logtail_exploration.bwrap_probe_rollback \\\n"
b = "              -target=logtail_exploration_alert.bwrap_probe_rollback \\\n"
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "").replace(b, "") + "\n" + a + b' \
    "one or both -target= lines are missing"

  # ── Emitter / runbook rows ────────────────────────────────────────────────────────────────
  # R10 — the SINK is prefixed: the message no longer STARTS with the marker, while the assignment
  # the needle is read from is untouched.
  mutate_red "the logger sink prefixes the message (the alert would silently never match a live row)" CI \
    'old = "logger -t \"$LOG_TAG\" \"$BWRAP_LINE\""
assert s.count(old) == 1
s = s.replace(old, "logger -t \"$LOG_TAG\" \"canary: $BWRAP_LINE\"")' \
    "ci-deploy.sh no longer emits the BWRAP_LINE logger sink"
  # R8 — the runbook heading is renamed in the copy: the alert's link would dangle.
  mutate_red "the runbook heading is renamed (the alert's runbook link would dangle)" RB \
    'old = "## Blocking bwrap sandbox probe"
assert s.count(old) == 1
s = s.replace(old, "## Blocking bwrap sandbox probe (renamed)")' \
    "the runbook anchor"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a BWRAP_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          BWRAP_GUARD_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"
  mutate_red "a runtime-composed MUT_/SKIP name is written to \$GITHUB_ENV inside the job" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"MUT_\"\"SKIP=1\" >> \"$GITHUB_ENV\"\n")' \
    "workflow seam"
  mutate_red "a foreign-prefix *_GUARD_* env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO_GUARD_X: /dev/null\n" + old)' \
    "workflow seam"
  mutate_red "a BASH_ENV shell-injection env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          BASH_ENV: /tmp/x\n" + old)' \
    "workflow seam"
  mutate_red "a \$GITHUB_ENV write lands inside the suite's own job" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"POISON=1\" >> \"$GITHUB_ENV\"\n")' \
    "enclosing-job seam"

  # ── Step-shape rows: an if:/continue-on-error: on the step or job would mute this suite ──────
  mutate_red "the suite's step becomes conditional (if: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "conditional or non-blocking"
  mutate_red "the suite's step becomes non-blocking (continue-on-error: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "conditional or non-blocking"
  mutate_red "the suite's job becomes non-blocking (continue-on-error: on the job)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n"
assert s.count(old) == 1
s = s.replace(old, old + "    continue-on-error: true\n")' \
    "conditional or non-blocking"

  # ── MAIN_PLAN bound rows: the slice must end at the first rc= line-start ────────────────────
  mutate_red "the plan step's rc= capture line is deleted (the slice would silently run to EOF)" WF \
    'old = "              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n          rc=${PIPESTATUS[0]}\n"
assert s.count(old) == 1
s = s.replace(old, "              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n")' \
    "never terminated on the plan step"
  mutate_red "the plan step's rc= capture is renamed to plan_rc= (the terminator misses)" WF \
    'old = "          rc=${PIPESTATUS[0]}\n"
i = s.index("              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n")
j = s.index(old, i)
s = s[:j] + "          plan_rc=${PIPESTATUS[0]}\n" + s[j + len(old):]' \
    "never terminated on the plan step"

  # ── Scorer negative control — a mutant that reds a row other than the named one must grade
  # WRONG (never RED), or the fragment check is decoration.
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "a comment-only edit to the tf" TF \
    's = s + "\n# control comment\n"'
  # Indentation inside the heredoc is not part of the contract (the resource collapses it).
  mutate_green "the AND conjuncts are re-indented (whitespace inside the heredoc is legal)" TF \
    'i = s.index(SQLLOC); j = s.index("\n  SQL\n", i)
block = s[i:j].replace("\n      AND ", "\n          AND ")
s = s[:i] + block + s[j:]'
  # Over-breadth control: a $GITHUB_ENV write inside a DIFFERENT job (plan:) is legitimate —
  # the enclosing-job slice must not reach past this suite's own job block.
  mutate_green "a \$GITHUB_ENV write inside a different job (the plan: job) stays green" IV \
    'old = "          printf \x27AWS_SECRET_ACCESS_KEY=%s\\n\x27 \"$SECRET\" >> \"$GITHUB_ENV\"\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"CROSS_JOB=1\" >> \"$GITHUB_ENV\"\n")'
  # Second-member control: a decoy `terraform plan` block appended after the real step is
  # outside the bounded slice — the -target= pins grade only the FIRST plan's span.
  mutate_green "a second terraform plan block with decoy -target= lines stays green (only the first bounded span is graded)" WF \
    's = s + "\n      - name: decoy second plan\n        run: |\n          terraform plan -no-color\n          -target=logtail_exploration.decoy_block \\\n"'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# PRESENCE_ROWS is exactly the count of rows an inner (MUT_SKIP) run asserts; the outer run adds
# one row per mutation. The instrument control is what catches a floor drifting past the rows.
# Floor/ledger trips exit 1 (verdict-class: the battery grades inner rc 1 as a CAUGHT mutation);
# instrument failures exit 2.
# SELF-REFERENCE CAVEAT (#11899 item 8, document-and-keep): a decrement WITH a row deletion stays
# green+FIRES; PROMOTED_FILES pins floor deletion, review covers decrement-with-deletion drift.
PRESENCE_ROWS=36
MUT_ROWS=45
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then
  printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2
  exit 1
fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then
  printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2
  exit 1
fi
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); BWRAP_GUARD_{TF,WF,CI,RB,IV}=%s,%s,%s,%s,%s\n' "$_floor" "${BWRAP_GUARD_TF:-unset}" "${BWRAP_GUARD_WF:-unset}" "${BWRAP_GUARD_CI:-unset}" "${BWRAP_GUARD_RB:-unset}" "${BWRAP_GUARD_IV:-unset}"
printf '\n=== bwrap-probe-rollback-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
