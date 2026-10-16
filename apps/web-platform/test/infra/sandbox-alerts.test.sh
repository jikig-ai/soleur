#!/usr/bin/env bash
#
# Drift guard for the "hosted agent Bash hit the apply-seccomp helper EPERM" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.agent_sandbox_bash_denial; #10445).
#
# WHAT THE ALERT IS FOR. server/cc-dispatcher.ts `mirrorBashSandboxFailure` mirrors a live Bash tool_result that
# carries a sandbox denial as ONE pino row (feature agent-sandbox, op bash-tool-result, extra.sandboxErrorCode).
# For the SDK helper line `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` the code is
# `helper_userns_eperm` (server/sandbox-startup-classifier.ts). Before this alert that row reached Sentry only,
# and "no alert pages on this op" was the recorded posture; this alert is the paging path.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The SQL's feature/op needles are READ FROM THE EMITTER (the mirrorBashSandboxFailure body) and the code
#     needle from the classifier, never retyped, so a reworded emitter reds here instead of silently disarming it.
#   * The predicate is exactly four ANDed conjuncts (container, feature, op, code) plus GROUP BY time, with the
#     NESTED `JSONExtractString(raw, 'message', '<key>')` form the production row shape needs, and NO host_name.
#   * A fixture row shaped like the sampled production row (raw.message is an OBJECT with top-level feature, op,
#     level, msg and the extra keys; raw.CONTAINER_NAME = soleur-web-platform) is run through the SAME predicate:
#     a positive control plus near-miss negatives. Mutating the SQL alone proves a string; this proves the shape.
#   * The paging semantics are bwrap_probe_rollback's (ADR-218): threshold, higher_than 0, 300 s window,
#     treat_as_zero, unpaused, email, and the free/paid escalation ternary.
#   * CENSUS over the .tf file, not over any plan's names: EVERY logtail_exploration / logtail_exploration_alert
#     resource the file declares has its -target= line in the push-triggered MAIN plan. terraform-target-parity.test.ts
#     covers terraform_data only, so this is the enforcement for logtail resources.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (the reconciler's `logs_alert` arm reads the
# live world twice daily), nor that a real denial row reaches Better Stack (Vector path). It compares values that one
# diff can edit together, so it proves consistency, not integrity. The classifier's own fixtures live in
# test/sandbox-startup-classifier.test.ts; the dispatcher's event shape in test/server/cc-dispatcher-bash-sandbox-mirror.test.ts.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the COPY, and re-runs this
# guard against it through the SANDBOX_ALERTS_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${SANDBOX_ALERTS_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${SANDBOX_ALERTS_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
DISP="${SANDBOX_ALERTS_GUARD_DISP:-$REPO/apps/web-platform/server/cc-dispatcher.ts}"
CLS="${SANDBOX_ALERTS_GUARD_CLS:-$REPO/apps/web-platform/server/sandbox-startup-classifier.ts}"
ALERT_NAME="agent_sandbox_bash_denial"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Byte-identical to the sibling alert suites' guard (the P1a suite pins every tracked copy).
# `$(cd X && pwd)` yields EMPTY when the cd fails, which would root a path at `/`.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$DISP"; assert_fixture_dir "$CLS"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$DISP" "$CLS"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate heredoc, from its opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*agent_sandbox_bash_denial_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
# Whitespace-normalised view: the resource collapses every run of whitespace to one space.
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
ALERT="$(awk -v n="$ALERT_NAME" '$0 == "resource \"logtail_exploration_alert\" \"" n "\" {" {f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk -v n="$ALERT_NAME" '$0 == "resource \"logtail_exploration\" \"" n "\" {" {f=1} f{print} f&&/^\}/{exit}' "$TF")"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to its `rc=$?`.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"
# The emitter: the mirrorBashSandboxFailure body, from its export line to the first column-0 "}".
EMITTER="$(awk '/^export function mirrorBashSandboxFailure\(/{f=1} f{print} f&&/^\}/{exit}' "$DISP")"

# Whole-line assertions anchored at both ends. Every grep over a captured VARIABLE reads a HERE-STRING, never
# `printf … | grep -q` (under pipefail, grep -q exiting early can SIGPIPE the writer and fail a negated check OPEN).
line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
sql_has() {  # sql_has <fixed conjunct text, one normalised line of the heredoc>
  grep -qxF -- "AND $1" <<< "$SQL_N"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "agent_sandbox_bash_denial_sql: heredoc not found — every predicate row below would be vacuous"
[ -n "$EMITTER" ] \
  && ok "the emitter body (mirrorBashSandboxFailure) is readable" \
  || no "mirrorBashSandboxFailure not found in cc-dispatcher.ts — the needles cannot be read from the emitter"

_head="$(head -3 <<< "$SQL_N" | paste -sd' ')"
grep -qxF 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}' <<< "$_head" \
  && ok "the head is the per-bucket count shape monitor_send_failed uses (ADR-218)" \
  || no "the predicate head is not SELECT {{time}} … count(*) … WHERE time BETWEEN {{start_time}} AND {{end_time}}"

# Needles READ from the emitter. Each must be exactly one parseable assignment, or the alert could silently stop matching.
EM_FEATURE="$(sed -n 's/^[[:space:]]*feature: "\([A-Za-z0-9_-]*\)",[[:space:]]*$/\1/p' <<< "$EMITTER")"
EM_OP="$(sed -n 's/^[[:space:]]*op: "\([A-Za-z0-9_-]*\)",[[:space:]]*$/\1/p' <<< "$EMITTER")"
if [ -n "$EM_FEATURE" ] && [ "$(grep -c . <<< "$EM_FEATURE")" -eq 1 ] && [ -n "$EM_OP" ] && [ "$(grep -c . <<< "$EM_OP")" -eq 1 ]; then
  ok "the emitter has exactly one feature and one op literal; needles read from it: feature='$EM_FEATURE' op='$EM_OP'"
else
  no "mirrorBashSandboxFailure no longer has exactly one parseable feature: \"…\" and op: \"…\" literal — the alert would silently stop matching"
fi
# The code the alert pages on is carried in extra.sandboxErrorCode (a top-level key of the pino row).
grep -qE '^[[:space:]]*sandboxErrorCode: failure\.errorCode,[[:space:]]*$' <<< "$EMITTER" \
  && ok "the emitter forwards the classifier code as extra.sandboxErrorCode (the row key the alert reads)" \
  || no "mirrorBashSandboxFailure no longer sets sandboxErrorCode: failure.errorCode — the code never reaches the row"

# The code needle is read from the ALERT's SQL and must exist in the classifier in both places it is declared.
SQL_CODE="$(sed -n "s/^AND JSONExtractString(raw, 'message', 'sandboxErrorCode') = '\([a-z_]*\)'\$/\1/p" <<< "$SQL_N")"
if [ -n "$SQL_CODE" ] \
   && grep -qE "^export interface BashSandboxFailure" "$CLS" \
   && grep -qE "^[[:space:]]*errorCode: \"proc_mount_eperm\" \| \"bwrap_eperm\" \| \"$SQL_CODE\";[[:space:]]*\$" "$CLS" \
   && [ "$(grep -cE "^[[:space:]]*\? \"$SQL_CODE\"[[:space:]]*\$" "$CLS")" -eq 1 ]; then
  ok "the classifier declares and returns the alert's code '$SQL_CODE' (union member plus the helper-arm return)"
else
  no "the classifier no longer declares and returns the code the alert's SQL pages on ('${SQL_CODE:-?}')"
fi

# ── The four conjuncts, each against the emitter's own value ──────────────────────────────────
sql_has "JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform'" \
  && ok "the container conjunct: CONTAINER_NAME = 'soleur-web-platform' (web-1 and web-2 share it)" \
  || no "the CONTAINER_NAME = 'soleur-web-platform' conjunct is missing or altered"
if [ -n "$EM_FEATURE" ] && sql_has "JSONExtractString(raw, 'message', 'feature') = '$EM_FEATURE'"; then
  ok "the feature conjunct reads the NESTED message.feature and equals the emitter's value"
else
  no "the message.feature conjunct is missing, altered, or no longer equals the emitter's feature"
fi
if [ -n "$EM_OP" ] && sql_has "JSONExtractString(raw, 'message', 'op') = '$EM_OP'"; then
  ok "the op conjunct reads the NESTED message.op and equals the emitter's value"
else
  no "the message.op conjunct is missing, altered, or no longer equals the emitter's op"
fi
[ -n "$SQL_CODE" ] \
  && ok "the code conjunct reads the NESTED message.sandboxErrorCode: '$SQL_CODE'" \
  || no "the message.sandboxErrorCode conjunct is missing or altered"

# Exactly the head, four AND conjuncts and GROUP BY: no OR, no negation, no fifth clause.
_body="$(sed -n '4,$p' <<< "$SQL_N")"
if [ "$(grep -c '^AND ' <<< "$_body")" -eq 4 ] \
   && [ "$(grep -vc '^AND ' <<< "$_body")" -eq 1 ] \
   && [ "$(tail -1 <<< "$_body")" = 'GROUP BY time' ] \
   && ! grep -qiE '(^|[^A-Za-z_])(OR|NOT)([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "the predicate is exactly four ANDed conjuncts and GROUP BY time (no OR, no negation)"
else
  no "the predicate carries an OR, a negation or an extra or missing clause"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would exclude web-2 and web-1's pre-rename host name" \
  || ok "no host_name conjunct: any web host's denial alerts"

# ── The production-shaped fixture row, run through the SAME predicate ─────────────────────────
# The row is shaped like the live row sampled 2026-10-16: raw.message is an OBJECT whose top-level keys are the pino
# fields (level, feature, op, msg) plus the `extra` keys; raw.CONTAINER_NAME is the container. Values are synthesized.
# The evaluator parses the conjuncts OUT OF THE SQL under test (not retyped here), and follows ClickHouse's
# JSONExtractString: the string at the path, else ''. A SQL that reads a flat key for a nested one matches nothing.
SCRATCH="$(mktemp -d -t soleur-run.$$.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
printf '%s\n' "$SQL_N" > "$SCRATCH/predicate.sql"

eval_row() {  # eval_row <row-json> ; prints MATCH or NOMATCH (exit 2 on an evaluator fault)
  python3 - "$SCRATCH/predicate.sql" "$1" <<'PY'
import json, re, sys
sql = open(sys.argv[1], encoding="utf-8").read().splitlines()
raw = json.loads(sys.argv[2])
conj = []
for line in sql:
    m = re.match(r"^AND JSONExtractString\(raw((?:, '[A-Za-z0-9_]+')+)\) = '([^']*)'$", line)
    if m:
        path = re.findall(r"'([A-Za-z0-9_]+)'", m.group(1))
        conj.append((path, m.group(2)))
    elif line.startswith("AND "):
        print("UNPARSED " + line); sys.exit(2)
if not conj:
    print("NOCONJUNCTS"); sys.exit(2)
def extract(node, path):
    for k in path:
        if not isinstance(node, dict) or k not in node:
            return ""
        node = node[k]
    return node if isinstance(node, str) else ""
print("MATCH" if all(extract(raw, p) == v for p, v in conj) else "NOMATCH")
PY
}

PROD_ROW='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":"error","feature":"agent-sandbox","op":"bash-tool-result","msg":"bash sandbox denial: helper_userns_eperm","userId":"0123456789abcdef","conversationId":"c0ffee00-0000-4000-8000-000000000001","sandboxErrorCode":"helper_userns_eperm","sandboxStderr":"apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted"}}'
NEG_OTHER_CODE='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":"error","feature":"agent-sandbox","op":"bash-tool-result","msg":"bash sandbox denial: proc_mount_eperm","sandboxErrorCode":"proc_mount_eperm"}}'
NEG_OTHER_OP='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":"error","feature":"agent-sandbox","op":"sdk-startup","msg":"x","sandboxErrorCode":"helper_userns_eperm"}}'
NEG_OTHER_CONTAINER='{"CONTAINER_NAME":"soleur-inngest","message":{"level":"error","feature":"agent-sandbox","op":"bash-tool-result","msg":"x","sandboxErrorCode":"helper_userns_eperm"}}'
NEG_STRING_MESSAGE='{"CONTAINER_NAME":"soleur-web-platform","message":"{\"feature\":\"agent-sandbox\",\"op\":\"bash-tool-result\",\"sandboxErrorCode\":\"helper_userns_eperm\"}"}'
NEG_FLAT_KEYS='{"CONTAINER_NAME":"soleur-web-platform","feature":"agent-sandbox","op":"bash-tool-result","sandboxErrorCode":"helper_userns_eperm","message":"bash sandbox denial: helper_userns_eperm"}'

_v="$(eval_row "$PROD_ROW")"
[ "$_v" = "MATCH" ] \
  && ok "the production-shaped row (message is an object with top-level feature/op/sandboxErrorCode) matches the predicate" \
  || no "the production-shaped fixture row does NOT match the predicate (got '$_v') — the alert would never fire on a real row"
_neg_ok=1
for neg in "$NEG_OTHER_CODE" "$NEG_OTHER_OP" "$NEG_OTHER_CONTAINER" "$NEG_STRING_MESSAGE" "$NEG_FLAT_KEYS"; do
  [ "$(eval_row "$neg")" = "NOMATCH" ] || _neg_ok=0
done
[ "$_neg_ok" -eq 1 ] \
  && ok "near-miss rows do not match: another code, another op, another container, a string message, flat keys" \
  || no "a near-miss fixture row matches the predicate — it is wider than the rows it names"

# ── Resource wiring and paging semantics ──────────────────────────────────────────────────────
line_in "$EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.agent_sandbox_bash_denial_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.agent_sandbox_bash_denial_sql as its sql_query"
line_in "$EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.$ALERT_NAME exists (exact header)" \
  || no "logtail_exploration_alert.$ALERT_NAME is missing"
line_in "$ALERT" "exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\\.$ALERT_NAME\\.id" \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.$ALERT_NAME.id"
line_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && line_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE denial row alerts" \
  || no "the alert is not threshold/higher_than/0 — a single denial would not alert"
line_in "$ALERT" 'query_period[[:space:]]*=[[:space:]]*300' \
  && line_in "$ALERT" 'check_period[[:space:]]*=[[:space:]]*60' \
  && ok "check_period 60 over a 300 s query window" \
  || no "the evaluation window is not check_period 60 over query_period 300"
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
  && ok "confirmation_period 0: one row alerts within about a minute" \
  || no "confirmation_period is not 0 — a single denial would not alert promptly"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
line_in "$ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"

# ── The -target= lines and the census ─────────────────────────────────────────────────────────
grep -qE "^[[:space:]]*-target=logtail_exploration\\.$ALERT_NAME \\\\\$" <<< "$MAIN_PLAN" \
  && grep -qE "^[[:space:]]*-target=logtail_exploration_alert\\.$ALERT_NAME \\\\\$" <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (an untargeted resource is never applied)" \
  || no "one or both -target= lines for $ALERT_NAME are missing — the alert would never exist in Better Stack"

# CENSUS over the file: every logtail_exploration / logtail_exploration_alert resource DECLARED in the .tf needs
# BOTH of its -target= lines in the MAIN plan. The names come from the file, never from a list in this suite.
CENSUS_NAMES="$(sed -n 's/^resource "logtail_exploration\(_alert\)\{0,1\}" "\([A-Za-z0-9_]*\)" {$/\2/p' "$TF" | sort -u)"
_census_n="$(grep -c . <<< "$CENSUS_NAMES")"
_census_missing=""
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  grep -qE "^[[:space:]]*-target=logtail_exploration\\.$nm \\\\\$" <<< "$MAIN_PLAN" || _census_missing="$_census_missing logtail_exploration.$nm"
  grep -qE "^[[:space:]]*-target=logtail_exploration_alert\\.$nm \\\\\$" <<< "$MAIN_PLAN" || _census_missing="$_census_missing logtail_exploration_alert.$nm"
done <<< "$CENSUS_NAMES"
if [ "$_census_n" -ge 2 ] && [ -z "$_census_missing" ]; then
  ok "census: all $_census_n logtail alert names declared in the .tf have both -target= lines in the MAIN plan"
else
  no "census: the .tf declares a logtail resource with no -target= line in the MAIN plan (names=$_census_n, missing:${_census_missing:- none; fewer than 2 names read, the census is vacuous})"
fi
# The census reads declared pairs; an exploration without an alert (or the reverse) is its own defect.
_ex_n="$(grep -c '^resource "logtail_exploration" "' "$TF")"; _al_n="$(grep -c '^resource "logtail_exploration_alert" "' "$TF")"
[ "$_ex_n" -eq "$_al_n" ] \
  && ok "every exploration has its alert: $_ex_n explorations, $_al_n alerts" \
  || no "the .tf declares $_ex_n explorations but $_al_n alerts — an unpaired resource"

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $SCRATCH/mut, mutates the copy, and re-runs this guard with
# MUT_SKIP=1 and the matching SANDBOX_ALERTS_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=29
MUT_ROWS=14
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$SCRATCH/mut"; mkdir -p "$MUT_DIR" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below would grade a
  # broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|DISP|CLS> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF)   src="$TF";   copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)   src="$WF";   copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      DISP) src="$DISP"; copy="$MUT_DIR/cc-dispatcher.ts" ;;
      CLS)  src="$CLS";  copy="$MUT_DIR/sandbox-startup-classifier.ts" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    # The heredoc below is UNQUOTED on purpose: the shell interpolates $prog into it exactly once and never
    # rescans the result. Its own body must therefore stay free of $, backticks and backslashes.
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry similar text.
    i = s.index("  agent_sandbox_bash_denial_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "SANDBOX_ALERTS_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
    # Only rc=1 (an assertion went red) is a caught mutation; rc>=2 is this guard's own FATAL class. A RED row must
    # ALSO name the row it targets, or one unrelated red row would certify every mutation.
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

  # G3-1 — the needle changes in the TF only (the alert stops matching what the classifier emits).
  mutate RED "the code needle changes in the alert only (helper_userns_eperm -> helper_userns_epermX)" TF \
    "the classifier no longer declares and returns the code" \
    's = sql_replace(s, "= \x27helper_userns_eperm\x27", "= \x27helper_userns_epermX\x27")'
  # G3-1b — the classifier is renamed while the alert is untouched.
  mutate RED "the classifier code is renamed while the alert keeps the old needle" CLS \
    "the classifier no longer declares and returns the code" \
    's = s.replace("helper_userns_eperm", "helper_userns_renamed")'
  # G3-1c — the emitter's op is reworded: the alert would silently stop matching live rows.
  mutate RED "the emitter op is reworded (the alert would silently stop matching)" DISP \
    "the message.op conjunct is missing, altered, or no longer equals the emitter" \
    'old = "      op: \"bash-tool-result\","
assert s.count(old) == 1
s = s.replace(old, "      op: \"bash-tool-output\",")'
  # G3-1d — the emitter stops forwarding the code under sandboxErrorCode.
  mutate RED "the emitter stops forwarding sandboxErrorCode (the row never carries the code)" DISP \
    "mirrorBashSandboxFailure no longer sets sandboxErrorCode" \
    'old = "        sandboxErrorCode: failure.errorCode,"
assert s.count(old) >= 1
s = s.replace(old, "        sandboxCode: failure.errorCode,")'
  # G3-2 — each -target= line is dropped.
  mutate RED "the exploration is dropped from the apply allowlist" WF \
    "one or both -target= lines for agent_sandbox_bash_denial are missing" \
    'old = "              -target=logtail_exploration.agent_sandbox_bash_denial \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines for agent_sandbox_bash_denial are missing" \
    'old = "              -target=logtail_exploration_alert.agent_sandbox_bash_denial \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # G3-4 — a third resource pair is added to the .tf with no -target= lines: only the census (names read from the
  # FILE) can see it.
  mutate RED "a new alert pair is added to the .tf without its -target= lines (census over the file)" TF \
    "census: the .tf declares a logtail resource with no -target= line" \
    's = s + "\nresource \"logtail_exploration\" \"census_probe_pair\" {\n  name = \"x\"\n}\n\nresource \"logtail_exploration_alert\" \"census_probe_pair\" {\n  name = \"x\"\n}\n"'
  # The production-shape row — the SQL flattens a nested path: a string-level mutation test alone would call this fine.
  mutate RED "the op conjunct reads a flat key instead of message.op (production-shape row no longer matches)" TF \
    "the production-shaped fixture row does NOT match the predicate" \
    's = sql_replace(s, "JSONExtractString(raw, \x27message\x27, \x27op\x27)", "JSONExtractString(raw, \x27op\x27)")'
  mutate RED "the container conjunct is dropped (any container could page)" TF \
    "the CONTAINER_NAME = " \
    's = sql_replace(s, "      AND JSONExtractString(raw, \x27CONTAINER_NAME\x27) = \x27soleur-web-platform\x27\n", "")'
  mutate RED "a host_name conjunct is added (web-2 would go silent)" TF \
    "the predicate carries a host_name conjunct" \
    's = sql_replace(s, "    GROUP BY time\n", "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")'
  mutate RED "an OR clause is appended after the conjuncts (every anchor still present)" TF \
    "the predicate carries an OR, a negation or an extra or missing clause" \
    's = sql_replace(s, "    GROUP BY time\n", "      OR JSONExtractString(raw, \x27CONTAINER_NAME\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")'
  mutate RED "the alert is paused" TF \
    "the alert is paused" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"agent_sandbox_bash_denial\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  # The guard's OWN dispatch: the locals key is renamed so the heredoc extractor returns empty. A guard reporting
  # "0 checked" and exiting 0 is vacuous; the heredoc-found row must RED.
  mutate RED "the predicate local is renamed so the heredoc extractor finds nothing (the guard must not go vacuous)" TF \
    "agent_sandbox_bash_denial_sql: heredoc not found" \
    'old = "  agent_sandbox_bash_denial_sql = <<-SQL"
assert s.count(old) == 1
s = s.replace(old, "  agent_sandbox_bash_denial_sql_renamed = <<-SQL")'
  # Must-PASS: indentation inside the heredoc is not part of the contract (the resource collapses it).
  mutate PASS "the AND conjuncts are re-indented (whitespace inside the heredoc is legal)" TF \
    "" \
    'i = s.index("  agent_sandbox_bash_denial_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
block = s[i:j].replace("\n      AND ", "\n          AND ")
s = s[:i] + block + s[j:]'
fi

# Floor = presence rows (+ mutation rows on the outer run). The instrument control above catches a floor that drifts
# past the rows; instrument failures exit 2, never 1 (the battery grades an inner rc 1 as a CAUGHT mutation).
_floor=$((PRESENCE_ROWS + MUT_ROWS))
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== sandbox-alerts: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
