#!/usr/bin/env bash
#
# Drift guard for the "bwrap probe rolled a deploy back" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.bwrap_probe_rollback).
# Plan: knowledge-base/project/plans/2026-10-01-chore-alert-on-deploy-rollback-bwrap-probe-plan.md
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CI"; assert_fixture_dir "$RB"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$CI" "$RB"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*bwrap_probe_rollback_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
# Whitespace-normalised view: the resource collapses every run of whitespace to one space
# (replace(trimspace(…), "/\\s+/", " ")), so indentation is not part of the contract.
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
# The alert and exploration blocks, from their exact header to the first column-0 "}".
ALERT="$(awk '/^resource "logtail_exploration_alert" "bwrap_probe_rollback" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "bwrap_probe_rollback" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to its `rc=$?`. The workflow
# has other plan commands (inngest host, host replace, volume recut) whose -target lists never run on
# a push to main, so the allowlist rows below read THIS region, not the whole file.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"

# Whole-line assertions anchored at both ends: a bare substring grep is satisfied by the same text
# inside a comment, or with a suffix that inverts it (`paused = false || true`).
# Every grep over a captured VARIABLE reads a HERE-STRING, never `printf … | grep -q`: under pipefail, grep -q exiting on its
# first match can SIGPIPE the writer and fail the pipeline, which fails a negated check OPEN.
line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
sql_has() {  # sql_has <fixed conjunct text, one normalised line of the heredoc>
  grep -qxF -- "AND $1" <<< "$SQL_N"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "bwrap_probe_rollback_sql: heredoc not found — every predicate row below would be vacuous"

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

line_in "$EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.bwrap_probe_rollback_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.bwrap_probe_rollback_sql as its sql_query"
line_in "$EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.bwrap_probe_rollback exists (exact header)" \
  || no "logtail_exploration_alert.bwrap_probe_rollback is missing"
line_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.bwrap_probe_rollback\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.bwrap_probe_rollback.id"
line_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-bwrap-probe-rollback-prd"' \
  && line_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-bwrap-probe-rollback-prd"' \
  && ok "both are named soleur-bwrap-probe-rollback-prd" \
  || no "the exploration/alert name drifted from soleur-bwrap-probe-rollback-prd"
line_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && line_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE rollback row alerts (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single rollback would not alert"
line_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
line_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
line_in "$ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && ok "email = true (the free-tier alerting surface)" \
  || no "email is not true"
line_in "$ALERT" 'confirmation_period[[:space:]]*=[[:space:]]*0' \
  && line_in "$ALERT" 'recovery_period[[:space:]]*=[[:space:]]*600' \
  && ok "confirmation_period 0 and recovery_period 600: one row alerts within about a minute, and the incident auto-resolves after 10 quiet minutes" \
  || no "confirmation_period is not 0 or recovery_period is not 600 — a single rollback would not alert promptly, or the incident would not auto-resolve after 10 quiet minutes"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
# Whole-line extraction: a prefix match would read `check_period = 60 * 10` as 60.
QP="$(sed -n 's/^[[:space:]]*query_period[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\(#.*\)\{0,1\}$/\1/p' <<< "$ALERT")"
CK="$(sed -n 's/^[[:space:]]*check_period[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\(#.*\)\{0,1\}$/\1/p' <<< "$ALERT")"
if [ -n "$QP" ] && [ -n "$CK" ] && [ "$CK" -ge 1 ] && [ "$QP" -ge "$CK" ] && [ "$CK" -le 300 ]; then
  ok "evaluated at least every 5 min (check_period ${CK}s) over a window that covers it (query_period ${QP}s)"
else
  no "the evaluation cadence is too slow or the window misses buckets (check_period=${CK:-?} query_period=${QP:-?})"
fi
line_in "$ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"

RB_URL_RE='^[[:space:]]*bwrap_probe_rollback_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set\.md#[a-z0-9-]+"'
grep -qE '^[[:space:]]*incident_cause[[:space:]]*=.*Runbook: \$\{local\.bwrap_probe_rollback_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && line_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.bwrap_probe_rollback_runbook_url' \
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

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching BWRAP_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=25
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t bwrapalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|CI|RB> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/ci-deploy.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/canary-probe-set.md" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    # The heredoc below is UNQUOTED on purpose: the shell interpolates $prog into it exactly once and
    # never rescans the result. Its own body must therefore stay free of $, backticks and backslashes.
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry
    # identical tag conjuncts earlier on.
    i = s.index("  bwrap_probe_rollback_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "BWRAP_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
    # Only rc=1 (an assertion went red) is a caught mutation; rc>=2 is this guard's own FATAL class.
    # A RED row must ALSO name the row it targets: "any row failed" would let one unrelated red row
    # certify every mutation (a row with no unique catcher could then be deleted unnoticed).
    case "$want:$rc" in
      RED:1)
        if grep -qF -- "[FAIL] $expect" "$ilog"; then
          ok "mutation RED: $label"
        else
          no "mutation RED for the WRONG reason (no '[FAIL] $expect' line): $label"
        fi ;;
      RED:0)  no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      PASS:0) ok "must-PASS edit stays green: $label" ;;
      PASS:*) no "must-PASS edit went red (inner rc=$rc): $label — the guard over-fits" ;;
      *)      no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # R1 — the marker is reworded in the EMITTER only; the alert's literal is untouched.
  mutate RED "the marker is reworded in ci-deploy.sh only (the alert would silently stop matching)" CI \
    "the startsWith conjunct is missing" \
    'old = "BWRAP_LINE=\"DEPLOY_ROLLBACK: bwrap sandbox non-functional in "
assert s.count(old) == 1
s = s.replace(old, "BWRAP_LINE=\"DEPLOY_ROLLBACK: bwrap sandbox nonfunctional in ")'
  # R2 — the tag conjunct is dropped: rows quoting the marker under another identifier could alert.
  mutate RED "the tag conjunct is dropped (quoting rows under another SYSLOG_IDENTIFIER could alert)" TF \
    "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing" \
    's = sql_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n", "")'
  # R3 — startsWith becomes position(): a row that merely CONTAINS the phrase could alert.
  mutate RED "startsWith is replaced by position() (a row merely containing the phrase could alert)" TF \
    "the startsWith conjunct is missing" \
    's = sql_replace(s, "startsWith(JSONExtractString(raw, \x27message\x27), \x27DEPLOY_ROLLBACK: bwrap sandbox non-functional\x27)", "position(JSONExtractString(raw, \x27message\x27), \x27DEPLOY_ROLLBACK: bwrap sandbox non-functional\x27) > 0")'
  # R4 — the luks-precedent host conjunct is added: web-2 and web-1's pre-rename host would go silent.
  mutate RED "a host_name conjunct is added (web-2 and the pre-rename web-1 name would go silent)" TF \
    "the predicate carries a host_name conjunct" \
    's = sql_replace(s, "    GROUP BY time\n", "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")'
  # R5 — an OR clause is appended after both conjuncts with every anchor still present.
  mutate RED "an OR clause is appended after both conjuncts (every anchor still present)" TF \
    "the predicate carries an OR, a negation or an extra clause" \
    's = sql_replace(s, "    GROUP BY time\n", "      OR JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n    GROUP BY time\n")'
  # R6 — either -target= line is dropped: an untargeted resource is never applied.
  mutate RED "the exploration is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration.bwrap_probe_rollback \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration_alert.bwrap_probe_rollback \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # R7 — armed-ness and one-row alerting, each its own row.
  mutate RED "the alert is paused" TF \
    "the alert is paused" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  mutate RED "the threshold value is raised to 1 (a single rollback no longer alerts)" TF \
    "the alert is not threshold/higher_than/0" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  value\s*=\s*)0", s, re.S)
assert m
s = s[:m.end(1)] + "1" + s[m.end():]'
  # R8 — the runbook heading is renamed in the copy: the alert's link would dangle.
  mutate RED "the runbook heading is renamed (the alert's runbook link would dangle)" RB \
    "the runbook anchor" \
    'old = "## Blocking bwrap sandbox probe"
assert s.count(old) == 1
s = s.replace(old, "## Blocking bwrap sandbox probe (renamed)")'
  # R9 — the guard's OWN dispatch: the locals key is renamed so the heredoc extractor returns empty.
  # A guard reporting "0 checked" and exiting 0 is vacuous; the heredoc-found row must RED.
  mutate RED "the predicate local is renamed so the heredoc extractor finds nothing (the guard must not go vacuous)" TF \
    "bwrap_probe_rollback_sql: heredoc not found" \
    'old = "  bwrap_probe_rollback_sql = <<-SQL"
assert s.count(old) == 1
s = s.replace(old, "  bwrap_probe_rollback_sql_renamed = <<-SQL")'
  # R10 — the SINK is prefixed: the message no longer STARTS with the marker, while the assignment the
  # needle is read from is untouched.
  mutate RED "the logger sink prefixes the message (the alert would silently never match a live row)" CI \
    "ci-deploy.sh no longer emits the BWRAP_LINE logger sink" \
    'old = "logger -t \"$LOG_TAG\" \"$BWRAP_LINE\""
assert s.count(old) == 1
s = s.replace(old, "logger -t \"$LOG_TAG\" \"canary: $BWRAP_LINE\"")'
  # R11 — confirmation_period is raised: a single rollback row can then never alert.
  mutate RED "confirmation_period is raised to 3600 (one row would never alert)" TF \
    "confirmation_period is not 0" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  confirmation_period\s*=\s*)0", s, re.S)
assert m
s = s[:m.end(1)] + "3600" + s[m.end():]'
  # R12 / R13 / R16 — the remaining paging fields, each its own row.
  mutate RED "on_missing_data is no longer treat_as_zero" TF \
    "on_missing_data is not treat_as_zero" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  mutate RED "the operator flips to lower_than (silence alerts, a rollback does not)" TF \
    "the alert is not threshold/higher_than/0" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  operator\s*=\s*)\"higher_than\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"lower_than\"" + s[m.end():]'
  mutate RED "email is switched off (the free-tier alerting surface)" TF \
    "email is not true" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  email\s*=\s*)true", s, re.S)
assert m
s = s[:m.end(1)] + "false" + s[m.end():]'
  # R14 — the alert watches another exploration.
  mutate RED "the alert watches another exploration" TF \
    "the alert's exploration_id is not" \
    'old = "exploration_id = logtail_exploration.bwrap_probe_rollback.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")'
  # R15 — the needle drifts in the TF only: the emitter and the alert would disagree.
  mutate RED "the alert's needle drifts away from the emitter's (TF only)" TF \
    "the startsWith conjunct is missing" \
    's = sql_replace(s, "non-functional\x27)", "non-functionalX\x27)")'
  # R17 — both -target= lines are MOVED out of the main plan (not deleted): they would still be
  # present in the file while the push-triggered apply never plans the resources.
  mutate RED "the -target= lines move out of the main plan (still in the file, never applied)" WF \
    "one or both -target= lines are missing" \
    'a = "              -target=logtail_exploration.bwrap_probe_rollback \\\n"
b = "              -target=logtail_exploration_alert.bwrap_probe_rollback \\\n"
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "").replace(b, "") + "\n" + a + b'
  # R18 — a meta-argument is added to the alert: every pinned attribute stays, the resource does not.
  mutate RED "count = 0 is added to the alert (every pinned line present, resource never created)" TF \
    "the alert or exploration carries count/for_each/lifecycle/ignore_changes" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"bwrap_probe_rollback\" \{.*?\n  paused = false\n)", s, re.S)
assert m
s = s[:m.end(1)] + "  count = 0\n" + s[m.end():]'
  # Must-PASS: indentation inside the heredoc is not part of the contract (the resource collapses it).
  mutate PASS "the AND conjuncts are re-indented (whitespace inside the heredoc is legal)" TF \
    "" \
    'i = s.index("  bwrap_probe_rollback_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
block = s[i:j].replace("\n      AND ", "\n          AND ")
s = s[:i] + block + s[j:]'
fi

# MUT_SKIP floor = the presence-row count; the outer floor adds the mutation rows (20 RED + 1 must-PASS).
# The instrument control above is what catches a floor that drifts past the rows.
_floor=$((PRESENCE_ROWS + 21))
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
# Instrument failures exit 2, never 1: the battery grades an inner rc 1 as a CAUGHT mutation.
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== bwrap-probe-rollback-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
