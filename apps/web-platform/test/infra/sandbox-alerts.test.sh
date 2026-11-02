#!/usr/bin/env bash
#
# Drift guard for the "hosted agent Bash hit the apply-seccomp helper EPERM" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.agent_sandbox_bash_denial; #10445).
#
# WHAT THE ALERT IS FOR. server/cc-dispatcher.ts `mirrorBashSandboxFailure` mirrors a live Bash tool_result that
# carries a sandbox denial as ONE pino row (feature agent-sandbox, op bash-tool-result, extra.sandboxErrorCode).
# For the SDK helper line `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` the code is
# `helper_userns_eperm`; for every OTHER helper step line (#10455 e) it is `helper_step_eperm`
# (server/sandbox-startup-classifier.ts). Before this alert that row reached Sentry only, and "no alert pages on
# this op" was the recorded posture; this alert is the paging path, on BOTH codes.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The SQL's feature/op needles are READ FROM THE EMITTER (the mirrorBashSandboxFailure body) and BOTH code
#     needles from the classifier (its helper_* union members), never retyped, so a reworded emitter or a helper code
#     the alert does not page on reds here instead of silently disarming it.
#   * The predicate is exactly four ANDed conjuncts (container, feature, op, code IN (both codes)) plus GROUP BY time, with the
#     NESTED `JSONExtractString(raw, 'message', '<key>')` form the production row shape needs, and NO host_name.
#   * A fixture row shaped like the pino rows this app container writes (no row of THIS op has arrived yet; raw.message is an OBJECT with top-level feature, op,
#     level, msg and the extra keys; raw.CONTAINER_NAME = soleur-web-platform) is run through the SAME predicate:
#     a positive control plus near-miss negatives. Mutating the SQL alone proves a string; this proves the shape.
#   * The paging semantics are bwrap_probe_rollback's (ADR-218): threshold, higher_than 0, 300 s window,
#     treat_as_zero, unpaused, email, and the free/paid escalation ternary.
#   * CENSUS over the .tf file, not over any plan's names: EVERY logtail_exploration / logtail_exploration_alert
#     resource the file declares has its -target= line in the push-triggered MAIN plan. terraform-target-parity.test.ts
#     covers terraform_data only, so this is the enforcement for logtail resources.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL a canon built from literals derived
#     out of the emitter (feature/op) and the classifier (the helper_* union in declaration
#     order), never re-pinned literals. Dead text — a /* */- or #-wrapped decoy heredoc — can
#     never satisfy the pin: the extractor reads the live local, the opener census counts the
#     decoy, and the canon pins the body.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert/exploration attribute is asserted inside its
#     own resource block by param(), which requires the whole value line anchored both ends,
#     exactly once. The .ts emitter pins stay whole-line (no HCL blocks there).
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control exits the suite FATAL (rc 2) if the un-mutated inner run is not
#     green; SANDBOX_ALERTS_GUARD_/MUT_SKIP literals may not reach the workflow's executable
#     text (the seam check below).
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; an instrument
#     failure (rc>=2) is UNRESOLVED, never evidence. Floor and ledger trips are verdict-class
#     (exit 1); instrument failures are exit 2.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (the reconciler's `logs_alert` arm reads the
# live world twice daily), nor that a real denial row reaches Better Stack (Vector path). It compares values that one
# diff can edit together, so it proves consistency, not integrity. The classifier's own fixtures live in
# test/sandbox-startup-classifier.test.ts; the dispatcher's event shape in test/server/cc-dispatcher-bash-sandbox-mirror.test.ts.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the COPY, and re-runs this
# guard against it through the SANDBOX_ALERTS_GUARD_{TF,WF,DISP,CLS,IV} overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${SANDBOX_ALERTS_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${SANDBOX_ALERTS_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
DISP="${SANDBOX_ALERTS_GUARD_DISP:-$REPO/apps/web-platform/server/cc-dispatcher.ts}"
CLS="${SANDBOX_ALERTS_GUARD_CLS:-$REPO/apps/web-platform/server/sandbox-startup-classifier.ts}"
IV="${SANDBOX_ALERTS_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$DISP"; assert_fixture_dir "$CLS"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the fixture evaluator and the mutation battery need it
' >&2; exit 2; }
for f in "$TF" "$WF" "$DISP" "$CLS" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
# sql_local: the <<[-]SQL heredoc body of `name = <<[-]SQL` up to its `  SQL` terminator.
sql_local() {  # sql_local <local-name>
  awk -v n="$1" '
    $0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<[-]SQL" { f=1; next }
    f && /^  SQL$/ { f=0 }
    f { print }
  ' "$TF"
}
# res_block: one resource block from its column-0 header to its column-0 closing brace.
res_block() {  # res_block <type> <name>
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

# The predicate heredoc, from its opening line to its own terminator.
LOCAL_SQL="$(sql_local "$ALERT_NAME"_sql)"
# Whitespace-normalised view: the resource collapses every run of whitespace to one space.
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
ALERT="$(res_block logtail_exploration_alert "$ALERT_NAME")"
EXPL="$(res_block logtail_exploration "$ALERT_NAME")"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to its `rc=$?`.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"
# The emitter: the mirrorBashSandboxFailure body, from its export line to the first column-0 "}".
EMITTER="$(awk '/^export function mirrorBashSandboxFailure\(/{f=1} f{print} f&&/^\}/{exit}' "$DISP")"

# Whole-line assertions anchored at both ends. Every grep over a captured VARIABLE reads a HERE-STRING, never
# `printf … | grep` (under pipefail, an early-exiting reader can SIGPIPE the writer and fail a negated check OPEN).
sql_has() {  # sql_has <fixed conjunct text, one normalised line of the heredoc>
  grep -qxF -- "AND $1" <<< "$SQL_N"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "agent_sandbox_bash_denial_sql: heredoc not found — every predicate row below would be vacuous"
[ -n "$EMITTER" ] \
  && ok "the emitter body (mirrorBashSandboxFailure) is readable" \
  || no "mirrorBashSandboxFailure not found in cc-dispatcher.ts — the needles cannot be read from the emitter"

# Opener/header counts — unanchored, file-wide, exactly once each. A /* */- or #-wrapped
# decoy opener still counts and goes red; dead text can never satisfy the live local.
_n="$(grep -cE 'agent_sandbox_bash_denial_sql[[:space:]]*=[[:space:]]*<<[-]SQL' "$TF")"
[ "$_n" -eq 1 ] \
  && ok "exactly one agent_sandbox_bash_denial_sql heredoc opener in the file (decoy copies count)" \
  || no "agent_sandbox_bash_denial_sql opener count is $_n, want 1 — a decoy local exists"
_n="$(grep -cE 'resource "logtail_exploration" "agent_sandbox_bash_denial"' "$TF")"
[ "$_n" -eq 1 ] \
  && ok "exactly one logtail_exploration.agent_sandbox_bash_denial resource header" \
  || no "logtail_exploration header count is $_n, want 1 — a decoy resource exists"
_n="$(grep -cE 'resource "logtail_exploration_alert" "agent_sandbox_bash_denial"' "$TF")"
[ "$_n" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.agent_sandbox_bash_denial resource header" \
  || no "logtail_exploration_alert header count is $_n, want 1 — a decoy resource exists"

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

# The code needles are read from the ALERT's SQL (one IN list) and must exist in the classifier in both places each is
# declared (the errorCode union and the return arm); the set the alert pages on must EQUAL the classifier's helper_* set,
# so a helper code added to the classifier but not to the alert (or the reverse) reds.
SQL_CODES="$(sed -n "s/^AND JSONExtractString(raw, 'message', 'sandboxErrorCode') IN (\(.*\))\$/\1/p" <<< "$SQL_N" | tr -d " '" | tr ',' '\n' | sort)"
SQL_CODE_N="$(grep -c . <<< "$SQL_CODES")"
CLS_UNION_LINE="$(grep -E '^[[:space:]]*errorCode: "proc_mount_eperm"' "$CLS" | head -1)"
CLS_HELPER_CODES="$(grep -o '"helper_[a-z_]*"' <<< "$CLS_UNION_LINE" | tr -d '"' | sort)"
# The canon below pins the IN list in the classifier's DECLARATION order (no sort), so the canon
# moves with the classifier it is derived from.
CLS_CODES_DECL="$(grep -o '"helper_[a-z_]*"' <<< "$CLS_UNION_LINE" | tr '"' \' | paste -sd',' - | sed 's/,/, /g')"
_cls_ok=1
[ "$SQL_CODE_N" -ge 2 ] || _cls_ok=0
grep -qE "^export interface BashSandboxFailure" "$CLS" || _cls_ok=0
while IFS= read -r _c; do
  [ -n "$_c" ] || continue
  grep -qF "\"$_c\"" <<< "$CLS_UNION_LINE" || _cls_ok=0
  [ "$(grep -cE "^[[:space:]]*[?:] \"$_c\"[[:space:]]*\$" "$CLS")" -eq 1 ] || _cls_ok=0
done <<< "$SQL_CODES"
if [ "$_cls_ok" -eq 1 ]; then
  ok "the classifier declares and returns every code the alert's SQL pages on ($(paste -sd' ' <<< "$SQL_CODES"))"
else
  no "the classifier no longer declares and returns the codes the alert's SQL pages on ('$(paste -sd' ' <<< "$SQL_CODES")')"
fi
if [ -n "$CLS_HELPER_CODES" ] && [ "$CLS_HELPER_CODES" = "$SQL_CODES" ]; then
  ok "the alert pages on exactly the classifier's helper_* codes (both needles read from the classifier source)"
else
  no "the alert's code set ('$(paste -sd' ' <<< "$SQL_CODES")') no longer equals the classifier's helper_* codes ('$(paste -sd' ' <<< "$CLS_HELPER_CODES")')"
fi

# EXACT PIN — canonical equality. The flattened heredoc must EQUAL this canon, assembled from
# literals derived out of the emitter (feature/op) and the classifier (the helper_* union in
# declaration order) — never re-pinned literals, so a reworded emitter or a renamed code moves
# the canon and the .tf drifts red. The per-conjunct rows below say WHY each piece matters; this
# row says nothing else is there.
SQL_FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
EXPECTED_FLAT="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform' AND JSONExtractString(raw, 'message', 'feature') = '${EM_FEATURE}' AND JSONExtractString(raw, 'message', 'op') = '${EM_OP}' AND JSONExtractString(raw, 'message', 'sandboxErrorCode') IN (${CLS_CODES_DECL}) GROUP BY time"
[ "$SQL_FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (canon derived from the emitter + classifier literals)" \
  || no "the predicate drifted from the pinned text — diff SQL_FLAT against EXPECTED_FLAT"

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
[ "$SQL_CODE_N" -ge 2 ] \
  && ok "the code conjunct reads the NESTED message.sandboxErrorCode and is an IN list: $(paste -sd' ' <<< "$SQL_CODES")" \
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
# The row is shaped like the live agent-sandbox rows sampled 2026-10-16 (other ops; none of THIS op has arrived): raw.message is an OBJECT whose top-level keys are the pino
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
    mi = re.match(r"^AND JSONExtractString\(raw((?:, '[A-Za-z0-9_]+')+)\) IN \(('[^']*'(?:, '[^']*')*)\)$", line)
    if m:
        path = re.findall(r"'([A-Za-z0-9_]+)'", m.group(1))
        conj.append((path, [m.group(2)]))
    elif mi:
        path = re.findall(r"'([A-Za-z0-9_]+)'", mi.group(1))
        conj.append((path, re.findall(r"'([^']*)'", mi.group(2))))
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
print("MATCH" if all(extract(raw, p) in vs for p, vs in conj) else "NOMATCH")
PY
}

PROD_ROW='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":50,"feature":"agent-sandbox","op":"bash-tool-result","msg":"bash sandbox denial: helper_userns_eperm","userIdHash":"0123456789abcdef","conversationId":"c0ffee00-0000-4000-8000-000000000001","sandboxErrorCode":"helper_userns_eperm","sandboxStderr":"apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted"}}'
STEP_ROW='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":50,"feature":"agent-sandbox","op":"bash-tool-result","msg":"bash sandbox denial: helper_step_eperm","userIdHash":"0123456789abcdef","conversationId":"c0ffee00-0000-4000-8000-000000000001","sandboxErrorCode":"helper_step_eperm","sandboxStderr":"apply-seccomp: prctl(PR_CAP_AMBIENT_CLEAR_ALL): Operation not permitted"}}'
NEG_OTHER_HELPER_CODE='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":50,"feature":"agent-sandbox","op":"bash-tool-result","msg":"x","sandboxErrorCode":"helper_step_epermX"}}'
NEG_OTHER_CODE='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":50,"feature":"agent-sandbox","op":"bash-tool-result","msg":"bash sandbox denial: proc_mount_eperm","sandboxErrorCode":"proc_mount_eperm"}}'
NEG_OTHER_OP='{"CONTAINER_NAME":"soleur-web-platform","message":{"level":50,"feature":"agent-sandbox","op":"sdk-startup","msg":"x","sandboxErrorCode":"helper_userns_eperm"}}'
NEG_OTHER_CONTAINER='{"CONTAINER_NAME":"soleur-inngest","message":{"level":50,"feature":"agent-sandbox","op":"bash-tool-result","msg":"x","sandboxErrorCode":"helper_userns_eperm"}}'
NEG_STRING_MESSAGE='{"CONTAINER_NAME":"soleur-web-platform","message":"{\"feature\":\"agent-sandbox\",\"op\":\"bash-tool-result\",\"sandboxErrorCode\":\"helper_userns_eperm\"}"}'
NEG_FLAT_KEYS='{"CONTAINER_NAME":"soleur-web-platform","feature":"agent-sandbox","op":"bash-tool-result","sandboxErrorCode":"helper_userns_eperm","message":"bash sandbox denial: helper_userns_eperm"}'

_v="$(eval_row "$PROD_ROW")"
[ "$_v" = "MATCH" ] \
  && ok "the production-shaped row (message is an object with top-level feature/op/sandboxErrorCode) matches the predicate" \
  || no "the production-shaped fixture row does NOT match the predicate (got '$_v') — the alert would never fire on a real row"
_v="$(eval_row "$STEP_ROW")"
[ "$_v" = "MATCH" ] \
  && ok "a helper_step_eperm row (any other helper step) matches the predicate too" \
  || no "the helper_step_eperm fixture row does NOT match the predicate (got '$_v') — a non-userns helper failure would never page"
_neg_ok=1
for neg in "$NEG_OTHER_HELPER_CODE" "$NEG_OTHER_CODE" "$NEG_OTHER_OP" "$NEG_OTHER_CONTAINER" "$NEG_STRING_MESSAGE" "$NEG_FLAT_KEYS"; do
  [ "$(eval_row "$neg")" = "NOMATCH" ] || _neg_ok=0
done
[ "$_neg_ok" -eq 1 ] \
  && ok "near-miss rows do not match: a lookalike helper code, another code, another op, another container, a string message, flat keys" \
  || no "a near-miss fixture row matches the predicate — it is wider than the rows it names"

# ── Resource wiring and paging semantics (block-scoped, exactly once) ─────────────────────────
param "$EXPL" 'sql_query' 'replace\(trimspace\(local\.agent_sandbox_bash_denial_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.agent_sandbox_bash_denial_sql as its sql_query (exactly once)"
param "$EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id (exactly once)"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.$ALERT_NAME exists (exact header)" \
  || no "logtail_exploration_alert.$ALERT_NAME is missing"
param "$ALERT" 'exploration_id' "logtail_exploration\\.$ALERT_NAME\\.id" \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.$ALERT_NAME.id"
param "$ALERT" 'alert_type' '"threshold"' \
  && param "$ALERT" 'operator' '"higher_than"' \
  && param "$ALERT" 'value' '0' \
  && ok "threshold, higher_than 0: ONE denial row alerts" \
  || no "the alert is not threshold/higher_than/0 — a single denial would not alert"
param "$ALERT" 'query_period' '300' \
  && param "$ALERT" 'check_period' '60' \
  && ok "check_period 60 over a 300 s query window" \
  || no "the evaluation window is not check_period 60 over query_period 300"
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
  && ok "confirmation_period 0: one row alerts within about a minute" \
  || no "confirmation_period is not 0 — a single denial would not alert promptly"
param "$ALERT" 'recovery_period' '600' \
  && ok "recovery_period 600: the incident auto-resolves after 10 quiet minutes (the runbook states this number)" \
  || no "recovery_period is not 600 — the runbook's auto-resolve statement would be false"
param "$ALERT" 'push' 'false' \
  && param "$ALERT" 'call' 'false' \
  && param "$ALERT" 'sms' 'false' \
  && param "$ALERT" 'critical_alert' 'false' \
  && ok "push/call/sms/critical_alert are all false: email only, as the runbook's wake-path statement says" \
  || no "a paging channel other than email is on (or a channel key is missing) — the runbook's email-only wake-path statement would be false"
param "$ALERT" 'runbook' 'local\.agent_sandbox_bash_denial_runbook_url' \
  && ok "metadata.runbook points at the runbook URL local the incident cause text also uses" \
  || no "metadata.runbook is not local.agent_sandbox_bash_denial_runbook_url"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "a count/for_each/lifecycle/ignore_changes token sits on the alert or exploration — a mute knob the provider would honor silently"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
param "$ALERT" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$ALERT" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
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

# ── Workflow seam — the suite is registered, and no env axis may reach the workflow ──────────
# The run line pins byte-exact (exactly once) so a rename/moved step cannot silently unregister
# the suite; and no SANDBOX_ALERTS_GUARD_ or MUT_SKIP literal may appear in the workflow's
# executable text — the shipped convention's seam check, which covers step env:/shell:/
# working-directory:/job-env redirects and not just a run-line prefix. Whole-line comments are
# stripped; an inline ` # MUT_SKIP` still reds — deliberate over-caution.
REG_RUN='        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh'
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"
seam_bad=""
printf '%s\n' "$IV_CODE" | grep -nE 'SANDBOX_ALERTS_GUARD_' >/dev/null && seam_bad="$seam_bad SANDBOX_ALERTS_GUARD_-literal"
printf '%s\n' "$IV_CODE" | grep -nE 'MUT_SKIP' >/dev/null && seam_bad="$seam_bad MUT_SKIP-literal"
[ -z "$seam_bad" ] \
  && ok "no SANDBOX_ALERTS_GUARD_/MUT_SKIP literal reaches the workflow's executable text (env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this guard with
# MUT_SKIP=1 and the matching SANDBOX_ALERTS_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
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

  PRELUDE='Q = chr(39)
def edit(s, anchor, old, new, end="\n}\n"):
    i = s.index(anchor)
    j = s.index(end, i)
    region = s[i:j]
    assert region.count(old) == 1, "anchor drift: %r occurs %d times" % (old, region.count(old))
    return s[:i] + region.replace(old, new) + s[j:]
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local'"'"'s opening line: other alerts in
    # this file carry similar text.
    i = s.index("  agent_sandbox_bash_denial_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
SQLLOC = "  agent_sandbox_bash_denial_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
ALRRES = "resource \"logtail_exploration_alert\" \"agent_sandbox_bash_denial\" {"'

  # _red_verdict <rc> <log> <fragment>: prints red | wrong | survived | unresolved. Only rc=1
  # is a caught mutation; when a fragment is named a [FAIL] line must contain it. Pipe-free of
  # early-exit readers upstream (SIGPIPE under pipefail); plain grep -F >/dev/null reads all.
  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|DISP|CLS|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF)   src="$TF";   copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)   src="$WF";   copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      DISP) src="$DISP"; copy="$MUT_DIR/cc-dispatcher.ts" ;;
      CLS)  src="$CLS";  copy="$MUT_DIR/sandbox-startup-classifier.ts" ;;
      IV)   src="$IV";   copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    # The heredoc below is UNQUOTED on purpose: the shell interpolates $prog into it exactly once and never
    # rescans the result. Its own body must therefore stay free of $, backticks and backslashes.
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
    env "SANDBOX_ALERTS_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
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

  # mutate_green <label> <python-program-on-tf-copy>: a legitimate edit must NOT red the guard.
  mutate_green() {
    local label="$1" prog="$2" copy rc=0
    copy="$MUT_DIR/betterstack-logs-alerts.tf"
    cp "$TF" "$copy" || { printf '[FATAL] mutate_green: cp failed\n' >&2; exit 2; }
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
    SANDBOX_ALERTS_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

  # mutate_floor_red: bumping PRESENCE_ROWS +1 in a scratch copy of SELF must trip the floor —
  # proves the floor is not dead text. The copy's REPO line is rewritten so its reads resolve.
  mutate_floor_red() {
    local label="$1" copy rc=0
    copy="$MUT_DIR/floor-mutated.test.sh"
    local cur
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
  mutate_red "a /* */-wrapped decoy heredoc sits before the predicate local while the live body is gutted" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(SQLLOC)
s = s[:i] + "/*\n  agent_sandbox_bash_denial_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the predicate local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # agent_sandbox_bash_denial_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the alert block" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "pinned-line decoy"
  mutate_red "an inline tautology is appended inside the predicate" TF \
    's = edit(s, SQLLOC, "GROUP BY time", "GROUP BY time OR 1=1", SQLEND)' \
    "drifted from the pinned"
  mutate_red "a doubled-dollar escape literal appears inside the heredoc" TF \
    's = edit(s, SQLLOC, "count(*) AS value", "count(*) AS value /* \x24\x24escaped */", SQLEND)' \
    "drifted from the pinned"
  mutate_red "the live predicate local is gutted to a placeholder while the resource keeps its name" TF \
    's = edit(s, SQLLOC, "SELECT {{time}} AS time, count(*) AS value", "SELECT 1", SQLEND)' \
    "drifted from the pinned"

  # G3-1 — a code needle changes in the TF only (the alert stops matching what the classifier emits). One row per
  # IN-list member, so neither the first nor the second code can drift unpinned.
  mutate_red "the first code needle changes in the alert only (helper_userns_eperm -> helper_userns_epermX)" TF \
    's = sql_replace(s, "IN (\x27helper_userns_eperm\x27", "IN (\x27helper_userns_epermX\x27")' \
    "the classifier no longer declares and returns the codes"
  mutate_red "the second code needle changes in the alert only (helper_step_eperm -> helper_step_epermX)" TF \
    's = sql_replace(s, "\x27helper_step_eperm\x27)", "\x27helper_step_epermX\x27)")' \
    "the classifier no longer declares and returns the codes"
  mutate_red "the alert drops helper_step_eperm from the IN list (a non-userns helper failure would never page)" TF \
    's = sql_replace(s, "IN (\x27helper_userns_eperm\x27, \x27helper_step_eperm\x27)", "IN (\x27helper_userns_eperm\x27)")' \
    "the alert's code set"
  mutate_red "the IN list repeats the first code instead of naming the second (the step fixture row stops matching)" TF \
    's = sql_replace(s, "\x27helper_step_eperm\x27)", "\x27helper_userns_eperm\x27)")' \
    "the helper_step_eperm fixture row does NOT match"
  mutate_red "the IN list is widened with a non-helper code (a near-miss row would page)" TF \
    's = sql_replace(s, "\x27helper_step_eperm\x27)", "\x27helper_step_eperm\x27, \x27proc_mount_eperm\x27)")' \
    "a near-miss fixture row matches the predicate"
  # G3-1b — the classifier is changed while the alert is untouched.
  mutate_red "the userns classifier code is renamed while the alert keeps the old needle" CLS \
    's = s.replace("helper_userns_eperm", "helper_userns_renamed")' \
    "the classifier no longer declares and returns the codes"
  mutate_red "the step classifier code is renamed while the alert keeps the old needle" CLS \
    's = s.replace("helper_step_eperm", "helper_step_renamed")' \
    "the classifier no longer declares and returns the codes"
  mutate_red "the classifier gains a helper_* code the alert does not page on" CLS \
    'old = "| \"helper_step_eperm\";"
assert s.count(old) == 1
s = s.replace(old, "| \"helper_step_eperm\" | \"helper_other_eperm\";")' \
    "the alert's code set"
  # G3-1c — the emitter's op is reworded: the alert would silently stop matching live rows.
  mutate_red "the emitter op is reworded (the alert would silently stop matching)" DISP \
    'old = "      op: \"bash-tool-result\","
assert s.count(old) == 1
s = s.replace(old, "      op: \"bash-tool-output\",")' \
    "the message.op conjunct is missing, altered, or no longer equals the emitter"
  # G3-1d — the emitter stops forwarding the code under sandboxErrorCode.
  mutate_red "the emitter stops forwarding sandboxErrorCode (the row never carries the code)" DISP \
    'old = "        sandboxErrorCode: failure.errorCode,"
assert s.count(old) >= 1
s = s.replace(old, "        sandboxCode: failure.errorCode,")' \
    "mirrorBashSandboxFailure no longer sets sandboxErrorCode"
  # G3-2 — each -target= line is dropped.
  mutate_red "the exploration is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.agent_sandbox_bash_denial \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines for agent_sandbox_bash_denial are missing"
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.agent_sandbox_bash_denial \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines for agent_sandbox_bash_denial are missing"
  # G3-4 — a third resource pair is added to the .tf with no -target= lines: only the census (names read from the
  # FILE) can see it.
  mutate_red "a new alert pair is added to the .tf without its -target= lines (census over the file)" TF \
    's = s + "\nresource \"logtail_exploration\" \"census_probe_pair\" {\n  name = \"x\"\n}\n\nresource \"logtail_exploration_alert\" \"census_probe_pair\" {\n  name = \"x\"\n}\n"' \
    "census: the .tf declares a logtail resource with no -target= line"
  # The production-shape row — the SQL flattens a nested path: a string-level mutation test alone would call this fine.
  mutate_red "the op conjunct reads a flat key instead of message.op (production-shape row no longer matches)" TF \
    's = sql_replace(s, "JSONExtractString(raw, \x27message\x27, \x27op\x27)", "JSONExtractString(raw, \x27op\x27)")' \
    "the production-shaped fixture row does NOT match the predicate"
  mutate_red "the container conjunct is dropped (any container could page)" TF \
    's = sql_replace(s, "      AND JSONExtractString(raw, \x27CONTAINER_NAME\x27) = \x27soleur-web-platform\x27\n", "")' \
    "the CONTAINER_NAME = "
  mutate_red "a host_name conjunct is added (web-2 would go silent)" TF \
    's = sql_replace(s, "    GROUP BY time\n", "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")' \
    "the predicate carries a host_name conjunct"
  mutate_red "an OR clause is appended after the conjuncts (every anchor still present)" TF \
    's = sql_replace(s, "    GROUP BY time\n", "      OR JSONExtractString(raw, \x27CONTAINER_NAME\x27) = \x27soleur-web-platform\x27\n    GROUP BY time\n")' \
    "the predicate carries an OR, a negation or an extra or missing clause"
  mutate_red "the alert is paused" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"agent_sandbox_bash_denial\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]' \
    "the alert is paused"
  mutate_red "recovery_period changes (the runbook's 10-minute auto-resolve statement becomes false)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"agent_sandbox_bash_denial\" \{.*?\n  recovery_period\s+= )600", s, re.S)
assert m
s = s[:m.end(1)] + "1" + s[m.end():]' \
    "recovery_period is not 600"
  mutate_red "critical_alert is turned on (a paging channel beyond email)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"agent_sandbox_bash_denial\" \{.*?\n  critical_alert\s+= )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]' \
    "a paging channel other than email"
  mutate_red "the count = 0 mute knob is added inside the alert resource" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"
  # The guard's OWN dispatch: the locals key is renamed so the heredoc extractor returns empty. A guard reporting
  # "0 checked" and exiting 0 is vacuous; the heredoc-found row must RED.
  mutate_red "the predicate local is renamed so the heredoc extractor finds nothing (the guard must not go vacuous)" TF \
    'assert s.count(SQLLOC) == 1
s = s.replace(SQLLOC, "  agent_sandbox_bash_denial_sql_renamed = <<\x2dSQL")' \
    "agent_sandbox_bash_denial_sql: heredoc not found"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a SANDBOX_ALERTS_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          SANDBOX_ALERTS_GUARD_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/sandbox-alerts.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"

  # ── Scorer negative control — a mutant that reds a row other than the named one must grade
  # WRONG (never RED), or the fragment check is decoration.
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "a comment-only edit to the tf" \
    's = s + "\n# control comment\n"'
  # Must-PASS: indentation inside the heredoc is not part of the contract (the resource collapses it).
  mutate_green "the AND conjuncts are re-indented (whitespace inside the heredoc is legal)" \
    'i = s.index("  agent_sandbox_bash_denial_sql = <<\x2dSQL")
j = s.index("\n  SQL\n", i)
block = s[i:j].replace("\n      AND ", "\n          AND ")
s = s[:i] + block + s[j:]'
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# PRESENCE_ROWS is exactly the count of rows an inner (MUT_SKIP) run asserts; the outer run adds
# one row per mutation. Floor and ledger trips are verdict-class (exit 1); instrument failures
# exit 2 — the battery grades an inner rc 1 as a CAUGHT mutation and rc>=2 as UNRESOLVED.
PRESENCE_ROWS=41
MUT_ROWS=35
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); SANDBOX_ALERTS_GUARD_{TF,WF,DISP,CLS,IV}=%s,%s,%s,%s,%s\n' "$_floor" "${SANDBOX_ALERTS_GUARD_TF:-unset}" "${SANDBOX_ALERTS_GUARD_WF:-unset}" "${SANDBOX_ALERTS_GUARD_DISP:-unset}" "${SANDBOX_ALERTS_GUARD_CLS:-unset}" "${SANDBOX_ALERTS_GUARD_IV:-unset}"
printf '\n=== sandbox-alerts: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
