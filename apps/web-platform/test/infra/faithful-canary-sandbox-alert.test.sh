#!/usr/bin/env bash
#
# Drift guard for the "deploy-time SDK Bash smoke failed" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.faithful_canary_sandbox_broken; #10453).
# Plan: knowledge-base/project/plans/archive/20261019-203025-2026-10-19-fix-sandbox-incident-followups-plan.md, Guard 1.
#
# WHAT THE ALERT IS FOR. ci-deploy.sh `run_sdk_bash_smoke` (non-blocking) runs one real wrapped Bash call through the real
# Agent SDK in the canary container. A `sdk_bash_smoke_failed` verdict is paged through `sandbox_canary_sentry_event`, which
# writes ONE journald row under `logger -t ci-deploy` whose message starts
#   SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed: <detail> sdk=<v> (op=sandbox-canary; report-only canary, never gated)
# The emitter format is SHARED by every canary arm (the inner faithful canary's `bwrap_*` reasons, the retired outer-wrap arm's
# rows still inside log retention, the workspace-isolation probe), so the alert's needles must discriminate on the reason AND
# the op terminator. A wrong needle either pages on a different arm's row (noise) or goes silent on the one that matters.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The three needles are READ FROM THE EMITTER (the `logger` format inside sandbox_canary_sentry_event and the
#     `sandbox_canary_sentry_event sandbox_broken "sdk_bash_smoke_failed: …" "" "sandbox-canary"` call in run_sdk_bash_smoke),
#     never retyped, so a reworded marker, reason or op reds here instead of silently disarming the alert.
#   * The SQL predicate is EVALUATED against fixture rows in the real `raw` shape (one positive, a permitted-variation
#     positive, and negatives for an outer-wrap row, the standing outer-wrap row with this reason, an inner bwrap_* row, a
#     doppler-identifier row quoting the marker, a smoke_infra_error row, a mid-message quote and a workspace-isolation row).
#   * The predicate is exactly THREE ANDed conjuncts plus GROUP BY time: no OR, no negation, no host_name (web-2 must page).
#   * The paging semantics are bwrap_probe_rollback's (ADR-218).
#   * CENSUS: every logtail_exploration_alert in the .tf has both -target= lines in the MAIN plan (terraform-target-parity
#     checks terraform_data only, so this guard is the enforcement for logtail resources).
#   * The runbook anchor in the alert's URL resolves to a real heading in canary-probe-set.md.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — the flattened heredoc must EQUAL a canon built from literals derived
#     out of the emitter (ci-deploy.sh's SANDBOX_CANARY_FAIL format and the smoke page call),
#     never re-pinned literals. Dead text — a /* */- or #-wrapped decoy heredoc — can never
#     satisfy the pin: the extractor reads the live local, the opener counts see the decoy,
#     and the canon pins the body.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside its own
#     resource block by param(), which requires the whole value line anchored both ends,
#     exactly once. A second matching line inside the block, or a decoy block anywhere, goes red.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control exits the suite FATAL (rc 2) if the un-mutated inner run is not
#     green; MUT_SKIP/FCSB_GUARD_* literals may not reach the workflow's executable text (the
#     seam check below); and mutate_floor_red proves the assertion floor itself fires.
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; an instrument
#     failure (rc>=2) is UNRESOLVED, never evidence. Floor and ledger trips are verdict-class
#     (exit 1); instrument failures are exit 2.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (the reconciler's `logs_alert` arm reads the live world
# twice daily) or that a real failed-smoke row reaches Better Stack (post-merge positive control in the runbook). It compares
# values one diff can edit together, so it proves consistency, not integrity.
#
# Mutation rows live at the bottom. Each COPIES one source file (or this guard) into a scratch dir, mutates the COPY, and
# re-runs this guard against it through the FCSB_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${FCSB_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${FCSB_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CI="${FCSB_GUARD_CI:-$REPO/apps/web-platform/infra/ci-deploy.sh}"
RB="${FCSB_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/canary-probe-set.md}"
IV="${FCSB_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

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

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the fixture evaluator and the mutation battery need it
' >&2; exit 2; }
for f in "$TF" "$WF" "$CI" "$RB" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
# sql_local: the heredoc body of `faithful_canary_sandbox_broken_sql = <<[-]SQL` up to its `  SQL`
# closer, from the FIRST UNCOMMENTED opener line.
sql_local() {
  awk '/^[[:space:]]*faithful_canary_sandbox_broken_sql[[:space:]]*=[[:space:]]*<<[-]SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF"
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
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
ALERT="$(res_block logtail_exploration_alert faithful_canary_sandbox_broken)"
EXPL="$(res_block logtail_exploration faithful_canary_sandbox_broken)"
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=/{exit}' "$WF")"
# The slice must actually TERMINATE on the plan step's own rc=${PIPESTATUS[0]} capture: a
# deleted or renamed capture line would silently reopen the run-to-EOF overshoot this bound
# fixes (a bare `rc=` terminator lands on a LATER step's `rc=0` and overshoots undetected).
# Anchored ERE on tail -1 — never `| grep -q` (SIGPIPE under pipefail); a prefix match would
# let rc=${PIPESTATUS[1]} or rc=${PIPESTATUS[0]}x through.
[ "$(tail -1 <<< "$MAIN_PLAN" | grep -cE '^[[:space:]]*rc=\$\{PIPESTATUS\[0\]\}$')" -eq 1 ] \
  && ok "the MAIN plan slice terminates on the plan step's rc=\${PIPESTATUS[0]} capture (no run-to-EOF overshoot)" \
  || no "the MAIN plan slice never terminated on the plan step's rc=\${PIPESTATUS[0]} capture — a deleted or renamed capture line reopened the run-to-EOF overshoot"

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "faithful_canary_sandbox_broken_sql: heredoc not found — every predicate row below would be vacuous"

# Opener counts — an unanchored file-wide count must equal exactly 1, so a /* */- or #-wrapped
# decoy opener still counts and goes red.
_n_sql_openers="$(grep -cE 'faithful_canary_sandbox_broken_sql[[:space:]]*=[[:space:]]*<<[-]SQL' "$TF")"
[ "$_n_sql_openers" -eq 1 ] \
  && ok "exactly one faithful_canary_sandbox_broken_sql heredoc opener in the file (decoy copies count)" \
  || no "faithful_canary_sandbox_broken_sql opener count is $_n_sql_openers, want 1 — a decoy local exists"
_n_exp="$(grep -cE 'resource "logtail_exploration" "faithful_canary_sandbox_broken"' "$TF")"
[ "$_n_exp" -eq 1 ] \
  && ok "exactly one logtail_exploration.faithful_canary_sandbox_broken resource header" \
  || no "logtail_exploration header count is $_n_exp, want 1 — a decoy resource exists"
_n_alr="$(grep -cE 'resource "logtail_exploration_alert" "faithful_canary_sandbox_broken"' "$TF")"
[ "$_n_alr" -eq 1 ] \
  && ok "exactly one logtail_exploration_alert.faithful_canary_sandbox_broken resource header" \
  || no "logtail_exploration_alert header count is $_n_alr, want 1 — a decoy resource exists"

_head="$(head -3 <<< "$SQL_N" | paste -sd' ')"
grep -qxF 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}' <<< "$_head" \
  && ok "the head is the per-bucket count shape monitor_send_failed uses (ADR-218)" \
  || no "the predicate head is not SELECT {{time}} … count(*) … WHERE time BETWEEN {{start_time}} AND {{end_time}}"

# ── Needles READ FROM THE EMITTER ──────────────────────────────────────────────────────────────────
# (1) the emitter format: the single logger line in sandbox_canary_sentry_event.
FMT_LINES="$(grep -E '^[[:space:]]*logger -t "\$LOG_TAG" "SANDBOX_CANARY_FAIL: verdict=\$verdict reason=\$reason sdk=\$sdk_version \(op=\$op; ' "$CI")"
if [ "$(grep -c . <<< "$FMT_LINES")" -eq 1 ]; then
  ok "ci-deploy.sh has exactly one SANDBOX_CANARY_FAIL emitter format (sandbox_canary_sentry_event)"
else
  no "ci-deploy.sh no longer has exactly one 'SANDBOX_CANARY_FAIL: verdict=\$verdict reason=\$reason sdk=\$sdk_version (op=\$op;' logger format"
fi
# (2) the call: the single sandbox_canary_sentry_event call that carries the smoke's reason, naming verdict, reason and op.
CALL_LINES="$(grep -E '^[[:space:]]*sandbox_canary_sentry_event [a-z_]+ "sdk_bash_smoke_failed[:"]' "$CI")"
CALL_PARTS="$(sed -n 's/^[[:space:]]*sandbox_canary_sentry_event \([a-z_]*\) "\(sdk_bash_smoke_failed\)[:"][^"]*" "[^"]*" "\([a-z-]*\)".*/\1 \2 \3/p' <<< "$CALL_LINES")"
read -r E_VERDICT E_REASON E_OP <<< "$CALL_PARTS"
if [ "$(grep -c . <<< "$CALL_LINES")" -eq 1 ] && [ -n "${E_VERDICT:-}" ] && [ -n "${E_REASON:-}" ] && [ -n "${E_OP:-}" ]; then
  ok "ci-deploy.sh has exactly one smoke page call; verdict='$E_VERDICT' reason='$E_REASON' op='$E_OP' read from it"
else
  no "ci-deploy.sh no longer has exactly one parseable 'sandbox_canary_sentry_event <verdict> \"sdk_bash_smoke_failed: …\" \"\" \"<op>\"' call — the alert would silently stop matching"
fi
NEEDLE_MARKER="SANDBOX_CANARY_FAIL: verdict=${E_VERDICT:-?} reason=${E_REASON:-?}"
NEEDLE_OP="(op=${E_OP:-?};"
grep -qxF 'readonly LOG_TAG="ci-deploy"' "$CI" \
  && ok "LOG_TAG is ci-deploy (the SYSLOG_IDENTIFIER the predicate matches, Vector-allowlisted)" \
  || no "ci-deploy.sh no longer declares readonly LOG_TAG=\"ci-deploy\""

sql_has "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'ci-deploy'" \
  || no "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing or altered"
if sql_has "startsWith(JSONExtractString(raw, 'message'), '$NEEDLE_MARKER')"; then
  ok "the marker anchor: the message STARTS with '$NEEDLE_MARKER' (emitter verdict + reason; a row merely quoting it cannot alert)"
else
  no "the startsWith conjunct is missing, altered, or no longer equals the marker read from ci-deploy.sh ('$NEEDLE_MARKER')"
fi
if sql_has "position(JSONExtractString(raw, 'message'), '$NEEDLE_OP') > 0"; then
  ok "the op terminator: the message contains '$NEEDLE_OP' (the ';' keeps op=sandbox-canary-outer-wrap out)"
else
  no "the position() conjunct is missing, altered, or no longer equals the op terminator read from ci-deploy.sh ('$NEEDLE_OP')"
fi

_body="$(sed -n '4,$p' <<< "$SQL_N")"
if [ "$(grep -c '^AND ' <<< "$_body")" -eq 3 ] \
   && [ "$(grep -vc '^AND ' <<< "$_body")" -eq 1 ] \
   && [ "$(tail -1 <<< "$_body")" = 'GROUP BY time' ] \
   && ! grep -qiE '(^|[^A-Za-z_])(OR|NOT)([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "the predicate is exactly three ANDed conjuncts and GROUP BY time (no OR, no negation)"
else
  no "the predicate carries an OR, a negation or an extra clause"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would exclude web-2 and web-1's pre-rename host name" \
  || ok "no host_name conjunct: any deploy host's failed smoke alerts"

# CANONICAL EQUALITY — the flattened heredoc must EQUAL this canon, built from the
# emitter-derived NEEDLE_MARKER/NEEDLE_OP (never re-pinned literals). A dead-text copy satisfies
# no row: the extractor reads the live local, and any arithmetic/widening edit breaks the byte compare.
PRED_FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
FCSB_CANON="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy' AND startsWith(JSONExtractString(raw, 'message'), '${NEEDLE_MARKER}') AND position(JSONExtractString(raw, 'message'), '${NEEDLE_OP}') > 0 GROUP BY time"
[ "$PRED_FLAT" = "$FCSB_CANON" ] \
  && ok "the whole predicate is byte-exact against the emitter-derived canon (dead text cannot satisfy it)" \
  || no "the predicate drifted from the pinned text — diff the flat extraction against FCSB_CANON"

# ── The predicate EVALUATED against fixture rows in the real `raw` shape ───────────────────────────
# The fixtures are built from the emitter's own format (so a reworded emitter changes the rows the predicate is graded on)
# and the evaluator understands exactly the three conjunct forms the predicate may use; any other form is FATAL (exit 2).
EVAL_OUT="$(FMT="$FMT_LINES" E_VERDICT="${E_VERDICT:-}" E_REASON="${E_REASON:-}" E_OP="${E_OP:-}" python3 - "$SQL_N" <<'PY'
import json, os, re, sys

sql = sys.argv[1]
conjuncts = [l[4:] for l in sql.splitlines() if l.startswith("AND ")]
FMT = re.search(r'"(SANDBOX_CANARY_FAIL: [^"]*)"', os.environ["FMT"]).group(1)

def render(verdict, reason, sdk, op):
    return FMT.replace("$verdict", verdict).replace("$reason", reason).replace("$sdk_version", sdk).replace("$op", op)

def raw_row(ident, message, prio="6", host="soleur-web-platform"):
    return json.dumps({"SYSLOG_IDENTIFIER": ident, "PRIORITY": prio, "message": message, "host_name": host, "_HOSTNAME": host})

V, R, O = os.environ["E_VERDICT"], os.environ["E_REASON"], os.environ["E_OP"]
canonical = render(V, R + ": apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted", "", O)
FIXTURES = [
    ("canonical smoke failure row", "ci-deploy", canonical, True),
    ("permitted variation: longer sdk= token and extra reason detail", "ci-deploy", render(V, R + ": no_nonce: some other wording | second line", "0.3.284-rc1+build.7", O), True),
    ("permitted variation: another host (web-2) carries the same row", "ci-deploy", canonical, True),
    ("standing outer-wrap row (its own reason, op=sandbox-canary-outer-wrap)", "ci-deploy", render("sandbox_broken", "wrong_elevation_userns", "0.3.284", "sandbox-canary-outer-wrap"), False),
    ("outer-wrap op carrying the SMOKE reason (only the ';' terminator keeps it out)", "ci-deploy", render(V, R + ": x", "", O + "-outer-wrap"), False),
    ("inner faithful canary bwrap_* reason (shares the verdict prefix)", "ci-deploy", render("sandbox_broken", "bwrap_operation_not_permitted", "0.3.284", O), False),
    ("a doppler-identifier row quoting the canonical marker", "doppler", canonical, False),
    ("smoke_infra_error summary row (never pages)", "ci-deploy", "SDK_BASH_SMOKE: verdict=smoke_infra_error reason=probe_absent coverage=", False),
    ("a ci-deploy row that merely QUOTES the marker mid-message", "ci-deploy", "note: " + canonical, False),
    ("workspace-isolation fail row", "ci-deploy", "WORKSPACE_ISOLATION_FAIL: verdict=workspace_isolation_failed reason=vitest_rc_1 (report-only canary probe; deploy NOT rolled back)", False),
]
HOSTS = {"permitted variation: another host (web-2) carries the same row": "soleur-web-2"}

def jx(raw, key):
    return str(json.loads(raw).get(key, ""))

def check(conj, raw):
    m = re.fullmatch(r"JSONExtractString\(raw, '([A-Za-z_]+)'\) = '([^']*)'", conj)
    if m: return jx(raw, m.group(1)) == m.group(2)
    m = re.fullmatch(r"startsWith\(JSONExtractString\(raw, '([A-Za-z_]+)'\), '([^']*)'\)", conj)
    if m: return jx(raw, m.group(1)).startswith(m.group(2))
    m = re.fullmatch(r"position\(JSONExtractString\(raw, '([A-Za-z_]+)'\), '([^']*)'\) > 0", conj)
    if m: return m.group(2) in jx(raw, m.group(1))
    print("FATAL unsupported conjunct form: " + conj)
    sys.exit(2)

# EVAL-BEGIN
def matches(raw):
    return all(check(c, raw) for c in conjuncts)
# EVAL-END

evaluated = 0
for name, ident, message, want in FIXTURES:
    raw = raw_row(ident, message, host=HOSTS.get(name, "soleur-web-platform"))
    got = matches(raw)
    evaluated += 1
    print(("EVAL-OK " if got == want else "EVAL-BAD ") + name + " got=" + str(got) + " want=" + str(want))
print("EVALUATED %d" % evaluated)
PY
)" || { printf '[FATAL] the predicate evaluator failed (rc=%s):\n%s\n' "$?" "$EVAL_OUT" >&2; exit 2; }

while IFS= read -r _l; do
  case "$_l" in
    "EVAL-OK "*)  ok "fixture row: ${_l#EVAL-OK }" ;;
    "EVAL-BAD "*) no "fixture row graded wrong: ${_l#EVAL-BAD }" ;;
  esac
done <<< "$EVAL_OUT"
EV_N="$(sed -n 's/^EVALUATED \([0-9][0-9]*\)$/\1/p' <<< "$EVAL_OUT")"
EV_N="${EV_N:-0}"
# Anti-vacuity floor on the fixture loop (a `no` row, so its [FAIL] is fragment-matchable): a loop that evaluated
# zero rows would otherwise print no [FAIL] and pass.
EVAL_SUB=0
EVAL_MIN=10
EVAL_REAL=$((EV_N - EVAL_SUB))
if [ "$EVAL_REAL" -lt "$EVAL_MIN" ]; then
  no "fixture floor: only $EVAL_REAL fixture rows evaluated (floor $EVAL_MIN)"
fi

# ── The exploration and the alert ──────────────────────────────────────────────────────────────────
param "$EXPL" 'sql_query' 'replace\(trimspace\(local\.faithful_canary_sandbox_broken_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.faithful_canary_sandbox_broken_sql as its sql_query"
param "$EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.faithful_canary_sandbox_broken exists (exact header)" \
  || no "logtail_exploration_alert.faithful_canary_sandbox_broken is missing"
param "$ALERT" 'exploration_id' 'logtail_exploration\.faithful_canary_sandbox_broken\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.faithful_canary_sandbox_broken.id"
param "$ALERT" 'name' '"soleur-faithful-canary-sandbox-broken-prd"' \
  && param "$EXPL" 'name' '"soleur-faithful-canary-sandbox-broken-prd"' \
  && ok "both are named soleur-faithful-canary-sandbox-broken-prd" \
  || no "the exploration/alert name drifted from soleur-faithful-canary-sandbox-broken-prd"
param "$ALERT" 'alert_type' '"threshold"' \
  && param "$ALERT" 'operator' '"higher_than"' \
  && param "$ALERT" 'value' '0' \
  && ok "threshold, higher_than 0: ONE failed-smoke row alerts (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single failed smoke would not alert"
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
  && ok "confirmation_period 0 and recovery_period 600: one row alerts within about a minute, auto-resolve after 10 quiet minutes" \
  || no "confirmation_period is not 0 or recovery_period is not 600"
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

RB_URL_RE='^[[:space:]]*faithful_canary_sandbox_broken_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set\.md#[a-z0-9_-]+"'
grep -qE '^[[:space:]]*incident_cause[[:space:]]*=.*Runbook: \$\{local\.faithful_canary_sandbox_broken_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && param "$ALERT" 'runbook' 'local\.faithful_canary_sandbox_broken_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the canary-probe-set runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable canary-probe-set runbook URL"

# ── Both -target= lines, for THIS alert and (census) for every logtail alert in the file ───────────
grep -qE '^[[:space:]]*-target=logtail_exploration\.faithful_canary_sandbox_broken \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.faithful_canary_sandbox_broken \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

CENSUS_NAMES="$(sed -n 's/^resource "logtail_exploration_alert" "\([A-Za-z0-9_]*\)" {.*/\1/p' "$TF")"
CENSUS_N="$(grep -c . <<< "$CENSUS_NAMES")"
CENSUS_MISSING=""
while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  grep -qE "^[[:space:]]*-target=logtail_exploration\\.${_n} \\\\\$" <<< "$MAIN_PLAN" || CENSUS_MISSING+="logtail_exploration.${_n} "
  grep -qE "^[[:space:]]*-target=logtail_exploration_alert\\.${_n} \\\\\$" <<< "$MAIN_PLAN" || CENSUS_MISSING+="logtail_exploration_alert.${_n} "
done <<< "$CENSUS_NAMES"
# Anti-vacuity floor on the census: a regex that found zero alert blocks would pass an empty loop.
CENSUS_SUB=0
CENSUS_MIN=17
CENSUS_REAL=$((CENSUS_N - CENSUS_SUB))
if [ "$CENSUS_REAL" -lt "$CENSUS_MIN" ]; then
  no "census floor: only $CENSUS_REAL logtail_exploration_alert blocks parsed (floor $CENSUS_MIN)"
fi
[ -z "$CENSUS_MISSING" ] \
  && ok "census: every logtail_exploration_alert in the .tf ($CENSUS_N) has both -target= lines in the main plan" \
  || no "census: -target= lines missing from the main plan for: $CENSUS_MISSING"

RB_SLUG="$(grep -E "$RB_URL_RE" "$TF" | head -1 | sed 's/.*#\([a-z0-9_-]*\)".*/\1/')"
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
# the suite; whole-line comments are stripped before the executable text is graded (an inline
# ` # MUT_SKIP` still reds — deliberate over-caution).
REG_RUN='        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh'
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this suite's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"

# A CI-dead guard must not pass. The step: ONLY the keys name + run — a `shell:`/`env:`/`with:`/
# `if:`/`continue-on-error:` (or any unrecognised line shape) flags, with if:/continue-on-error:
# read at BOTH `        ` and `      - ` positions. The HOSTING JOB is derived from the step's
# position (the last `jobs:`-level header above the run line — a quoted id or a trailing-comment
# header included), never named here, and is read WHOLE (header, steps, anything after them: YAML
# key order is free): `continue-on-error` must appear NOWHERE in it (post-steps included), its
# `if:` must be the one known literal (total == 1), `needs:`/`runs-on:` the known literals, and
# its own keys the known set {name needs if runs-on permissions timeout-minutes steps} — no
# `defaults`/`env`/`container`/`strategy`/`services` … . The workflow itself carries no top-level
# `defaults:` and no env-composition FRAGMENT — {MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS,
# BASHOPTS} — so literal, runtime-composed ("MUT_""SKIP"), *_GUARD_*-prefixed and shell-injection
# env muting are all barred; and no GITHUB_ENV/GITHUB_PATH/defaults: inside the hosting job. The
# verdict must also REACH the aggregator (a job needing the host, under if: always(), reading its
# result and carrying its entries slot), so dropping the leg is not a quiet way to make this
# guard CI-dead. Every violation accrues to the composite verdict below — slice-validity folds
# in, so no ban can pass vacuously on an empty or missed slice.
# hdr LINE -> the job id when LINE is a `jobs:`-level key header (`  id:`, `  "id":`, `  id: # note`), else "".
AWK_HDR='function hdr(l,   n) { if (l ~ /^  [\047"]?[A-Za-z0-9_-]+[\047"]?:[ \t]*(#.*)?$/) { n = l; sub(/^  [\047"]?/, "", n); sub(/[\047"]?:.*$/, "", n); return n } return "" }'
STEP_BLOCK="$(awk -v r="$REG_RUN" "$AWK_HDR"'
  function flush() { if (blk != "" && index(blk, r "\n") > 0) printf "%s", blk; blk = "" }
  /^      - / || hdr($0) != "" { flush() }
  { if ($0 !~ /^[[:space:]]*#/) blk = blk $0 "\n" }
  END { flush() }' "$IV")"
HOST_JOB="$(awk -v r="$REG_RUN" "$AWK_HDR"'{ h = hdr($0); if (h != "") j = h } $0 == r { print j; exit }' "$IV")"
JOB_BLOCK=""
[ -n "$HOST_JOB" ] && JOB_BLOCK="$(awk -v j="$HOST_JOB" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f && !/^[[:space:]]*#/ { print }' "$IV")"
JOB_IF="$(awk '/^    if:/ { print }' <<<"$JOB_BLOCK")"
JOB_NEEDS="$(awk '/^    needs:/ { print }' <<<"$JOB_BLOCK")"
JOB_RUNS_ON="$(awk '/^    runs-on:/ { print }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Anything else (or an
# unrecognised line shape) is listed by name — env:/shell:/with:/if:/continue-on-error: included.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
WF_BAD=""
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && WF_BAD="$WF_BAD top-level-defaults"
# Fragments, not literals (#11899): a runtime-composed name ("MUT_""SKIP", a GUARD-fragment
# prefix) or a shell-injection env (BASH_ENV/SHELLOPTS/BASHOPTS) reaches the step with no
# literal present — MUT_/_SKIP cover MUT_SKIP at either split, GUARD covers every *_GUARD_* axis
# (FCSB_GUARD_ included — no separate literal grep needed).
_seam_frag=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  printf '%s\n' "$IV_CODE" | grep -nF -- "$_frag" >/dev/null && _seam_frag="$_seam_frag ${_frag}-fragment"
done
[ -n "$_seam_frag" ] && WF_BAD="$WF_BAD suite-seam-in-workflow:$_seam_frag"
# The only DYNAMIC channel: a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults: inside the
# hosting job. An empty JOB_BLOCK reds the composite below via job-slice-empty AND the slice-
# validity conjuncts, so the ban cannot pass vacuously.
if [ -z "$JOB_BLOCK" ]; then
  WF_BAD="$WF_BAD job-slice-empty"
else
  _job_seam=""
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'GITHUB_ENV' >/dev/null && _job_seam="$_job_seam GITHUB_ENV"
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'GITHUB_PATH' >/dev/null && _job_seam="$_job_seam GITHUB_PATH"
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'defaults:' >/dev/null && _job_seam="$_job_seam defaults:"
  [ -n "$_job_seam" ] && WF_BAD="$WF_BAD job-scope-env-write:$_job_seam"
fi
# The aggregator: every job (other than the host) whose `needs:` names the host; one of them must
# run under if: always() AND read needs.<host>.result AND carry "<host>:$" in its entries array.
AGG_CANDS="$(awk -v host="$HOST_JOB" "$AWK_HDR"'
  function emit(l,   n, t, i) { sub(/[ \t]#.*$/, "", l); gsub(/[\[\],"\047]/, " ", l); n = split(l, t, /[ \t]+/); for (i = 1; i <= n; i++) if (t[i] == host && job != host) print job }
  /^[[:space:]]*#/ { next }
  { h = hdr($0); if (h != "") { job = h; innd = 0; next } }
  job == "" { next }
  /^    needs:/ { innd = 1; l = $0; sub(/^    needs:/, "", l); emit(l); next }
  innd && /^      -/ { l = $0; sub(/^      -/, "", l); emit(l); next }
  /^    [A-Za-z_-]+:/ { innd = 0 }' <<<"$IV_CODE")"
AGG_OK=0; AGG_NAMES=""
if [ -n "$HOST_JOB" ]; then
  while IFS= read -r _agg; do
    [ -n "$_agg" ] || continue
    AGG_NAMES="$AGG_NAMES $_agg"
    _agg_block="$(awk -v j="$_agg" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f { print }' <<<"$IV_CODE")"
    if [[ $'\n'"$_agg_block" == *$'\n    if: always()'* ]] && [[ "$_agg_block" == *"needs.${HOST_JOB}.result"* ]] && [[ "$_agg_block" == *"\"${HOST_JOB}:\$"* ]]; then AGG_OK=1; fi
  done <<<"$AGG_CANDS"
fi
if [ -n "$STEP_BLOCK" ] && [[ "$STEP_BLOCK" != *continue-on-error* ]] && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
   && [ -z "$STEP_BAD" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] && [ -z "$JOB_BAD" ] && [ -z "$WF_BAD" ] \
   && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
   && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ] && [ "$AGG_OK" -eq 1 ]; then
  ok "the registered step has only name+run keys (no continue-on-error / if: / shell / env / ...), its hosting job '$HOST_JOB' (derived from the step's position) has the one known if:, needs and runs-on, the known key set and no continue-on-error anywhere, the workflow carries no top-level defaults: or suite-seam fragment, and the verdict reaches the aggregator ('${AGG_NAMES# }': if: always(), the leg's result, its entries slot): it cannot be skipped, non-blocking, redirected or dropped"
else
  no "infra-validation.yml: the registered step or its hosting job '$HOST_JOB' is conditional, non-blocking, redirected or unaggregated (step keys beyond name/run: '${STEP_BAD//$'\n'/ }'; job keys beyond the known set: '${JOB_BAD//$'\n'/ }'; workflow:${WF_BAD:- none}; aggregator ok=$AGG_OK; continue-on-error anywhere in the job; an if:/needs/runs-on other than the known literals), or could not be located"
fi

echo ""
echo "=== faithful-canary-sandbox-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED (must-PASS rows stay GREEN) ─────────────
# OUTER RUN ONLY. Each row copies ONE source file (or this guard) into $MUT_DIR, mutates the copy, and re-runs the guard with
# MUT_SKIP=1 and the matching FCSB_GUARD_* override pointing at the copy. SELF rows mutate a copy of THIS file.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t fcsbalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below would grade a broken
  # invocation as "mutation RED".
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
def fc_replace(s, old, new):
    # The first occurrence AFTER the predicate local'\''s opening line: other alerts in this
    # file carry identical tag conjuncts earlier on.
    i = s.index("  faithful_canary_sandbox_broken_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
SQLLOC = "  faithful_canary_sandbox_broken_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
EXPRES = "resource \"logtail_exploration\" \"faithful_canary_sandbox_broken\" {"
ALRRES = "resource \"logtail_exploration_alert\" \"faithful_canary_sandbox_broken\" {"'

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

  # mutate_red <label> <TF|WF|CI|RB|SELF|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
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
      SELF) src="$SELF"; copy="$MUT_DIR/guard-copy.sh" ;;
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
    if [ "$which" = SELF ]; then
      # The guard copy lives outside the repo: pin every input to the pristine absolute paths.
      env "FCSB_GUARD_TF=$TF" "FCSB_GUARD_WF=$WF" "FCSB_GUARD_CI=$CI" "FCSB_GUARD_RB=$RB" "FCSB_GUARD_IV=$IV" MUT_SKIP=1 bash "$copy" >"$olog" 2>&1 || rc=$?
    else
      env "FCSB_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    fi
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
  # the guard. Deliberately axis-widened past the donor's TF-only shape: the emitter-tail
  # must-PASS edits ci-deploy.sh, not the tf.
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
    env "FCSB_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
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
s = s[:i] + "/*\n  faithful_canary_sandbox_broken_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the live local" TF \
    'i = s.index(SQLLOC)
s = s[:i] + "  # faithful_canary_sandbox_broken_sql = <<\x2dSQL\n" + s[i:]' \
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
    's = s + "\nresource \"logtail_exploration_alert\" \"faithful_canary_sandbox_broken\" {\n}\n"' \
    "decoy resource exists"

  # ── Needle / conjunct rows ─────────────────────────────────────────────────────────────────
  # M1 — the reason needle is dropped in the .tf: inner bwrap_* rows (and, while they exist, outer-wrap rows) would page.
  mutate_red "the reason needle is dropped from the startsWith (inner bwrap_* and outer-wrap rows would match)" TF \
    's = fc_replace(s, " reason=sdk_bash_smoke_failed\x27)", "\x27)")' \
    "the startsWith conjunct is missing"
  # M4 — the ';' terminator is dropped from the op needle: op=sandbox-canary-outer-wrap rows would match.
  mutate_red "the ';' is dropped from the op needle (op=sandbox-canary-outer-wrap would match)" TF \
    's = fc_replace(s, "(op=sandbox-canary;\x27) > 0", "(op=sandbox-canary\x27) > 0")' \
    "the position() conjunct is missing"
  # M6 — the tag conjunct is dropped.
  mutate_red "the tag conjunct is dropped (quoting rows under another SYSLOG_IDENTIFIER could alert)" TF \
    's = fc_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n", "")' \
    "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing"
  # M5 — the emitter's op string is edited in ci-deploy.sh (the needle is read from it).
  mutate_red "the smoke page call's op is edited in ci-deploy.sh (the alert would silently stop matching)" CI \
    'old = "\"\" \"sandbox-canary\" || true"
assert s.count(old) == 1
s = s.replace(old, "\"\" \"sandbox-canary-smoke\" || true")' \
    "the position() conjunct is missing, altered, or no longer equals the op terminator"
  # M5b — the smoke reason is reworded in ci-deploy.sh only.
  mutate_red "the smoke reason is reworded in ci-deploy.sh only (the alert would silently stop matching)" CI \
    's = s.replace("\"sdk_bash_smoke_failed: ", "\"sdk_bash_smoke_broke: ")' \
    "the startsWith conjunct is missing, altered, or no longer equals the marker"

  # ── Alert-attribute rows ──────────────────────────────────────────────────────────────────
  mutate_red "the alert is paused" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  paused = true\n")' \
    "the alert is paused"
  mutate_red "the alert watches another exploration" TF \
    'old = "exploration_id = logtail_exploration.faithful_canary_sandbox_broken.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")' \
    "the alert's exploration_id is not"
  mutate_red "count = 0 is added to the alert (every pinned line present, resource never created)" TF \
    's = edit(s, ALRRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  # ── Apply-allowlist / census rows ─────────────────────────────────────────────────────────
  # M7 — the alert's -target= line is dropped.
  mutate_red "the alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.faithful_canary_sandbox_broken \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "one or both -target= lines are missing"
  # M3 — a second alert resource without its -target= lines, after a compliant first.
  mutate_red "a second logtail alert is added to the .tf without its -target= lines (census)" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"second_probe_alert\" {\n  name = \"x\"\n}\n"' \
    "census: -target= lines missing from the main plan for: logtail_exploration.second_probe_alert"

  # ── Guard-internal (SELF) rows ─────────────────────────────────────────────────────────────
  # M2 — the guard's fixture loop is emptied (zero rows evaluated) while everything else stays intact.
  mutate_red "the fixture loop is emptied (zero rows evaluated: the floor must catch it)" SELF \
    'old = "for name, ident, message, want in " + "FIXTURES:"
assert s.count(old) == 1
s = s.replace(old, "for name, ident, message, want in []:")' \
    "fixture floor: only 0 fixture rows evaluated"
  # M8 — the predicate evaluator is replaced by a constant true: the negative fixtures must then be graded wrong.
  mutate_red "the predicate evaluator is replaced by constant true (negative fixtures must grade wrong)" SELF \
    'old = "    return all(check(c, raw) " + "for c in conjuncts)"
assert s.count(old) == 1
s = s.replace(old, "    return True")' \
    "fixture row graded wrong: standing outer-wrap row"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a FCSB_GUARD_ literal reaches the workflow's executable text (the GUARD fragment sees it)" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          FCSB_GUARD_TF: /dev/null\n")' \
    "suite-seam-in-workflow"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"
  mutate_red "a runtime-composed MUT_/SKIP name is written to \$GITHUB_ENV inside the job" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"MUT_\"\"SKIP=1\" >> \"$GITHUB_ENV\"\n")' \
    "suite-seam-in-workflow"
  mutate_red "a foreign-prefix *_GUARD_* env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO_GUARD_X: /dev/null\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a BASH_ENV shell-injection env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          BASH_ENV: /tmp/x\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a \$GITHUB_ENV write lands inside the suite's own job" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"POISON=1\" >> \"$GITHUB_ENV\"\n")' \
    "job-scope-env-write"
  mutate_red "a top-level defaults: is added to the workflow (the file-wide ban is keyed on column 0)" IV \
    'old = "\nenv:\n  TERRAFORM_VERSION"
assert s.count(old) == 1
s = s.replace(old, "\ndefaults:\n  run:\n    shell: /bin/true {0}\nenv:\n  TERRAFORM_VERSION")' \
    "top-level-defaults"

  # ── Step/job-shape rows: an if:/continue-on-error: or a foreign key on the step or job would
  # mute this suite — read at BOTH `        ` and `      - ` positions across the WHOLE job block.
  mutate_red "the suite's step becomes conditional (if: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "name/run: 'if'"
  mutate_red "the suite's step opens with a dash-line if: (the step body never runs)" IV \
    'old = "      - name: Run faithful canary sandbox-broken (SDK Bash smoke) alert drift guard (#10453)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run faithful canary sandbox-broken (SDK Bash smoke) alert drift guard (#10453)\n")' \
    "name/run: 'if'"
  mutate_red "the suite's step becomes non-blocking (continue-on-error: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "name/run: 'continue-on-error'"
  mutate_red "the suite's step gets an env: key (only name+run are legal on a step)" IV \
    'old = "        run: bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env: {NEUTRAL: \"1\"}\n" + old)' \
    "name/run: 'env'"
  mutate_red "the suite's job becomes non-blocking (continue-on-error: on the job)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n"
assert s.count(old) == 1
s = s.replace(old, old + "    continue-on-error: true\n")' \
    "known set: 'continue-on-error'"
  mutate_red "a continue-on-error: is placed AFTER the job's steps (key order is free in YAML)" IV \
    'old = "\n  deploy-script-tests-done:\n"
assert s.count(old) == 1
s = s.replace(old, "\n    continue-on-error: true\n\n  deploy-script-tests-done:\n")' \
    "known set: 'continue-on-error'"
  mutate_red "the suite's job gets a job-level env: key (outside the known key set)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    env: {NEUTRAL: \"1\"}\n")' \
    "known set: 'env'"
  mutate_red "a second, differing job-level if: is appended (the job's if: must be the one literal)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    if: github.event_name == \x27push\x27\n")' \
    "an if:/needs/runs-on other than the known literals"

  # ── MAIN_PLAN bound rows: the slice must end at the first rc= line-start ────────────────────
  mutate_red "the -target= lines move below the plan step's rc= capture (the bounded slice must not see them)" WF \
    'a = "              -target=logtail_exploration.faithful_canary_sandbox_broken \\\n"
b = "              -target=logtail_exploration_alert.faithful_canary_sandbox_broken \\\n"
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "").replace(b, "")
old = "              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n          rc=${PIPESTATUS[0]}\n"
assert s.count(old) == 1
s = s.replace(old, old + a + b)' \
    "one or both -target= lines are missing"
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
  # M9 — the emitter's human tail after the op terminator is reworded (a permitted variation): the
  # needles stop at the terminator, so the alert still matches.
  mutate_green "the emitter's human-readable tail after the op terminator is lengthened (the needles do not read it)" CI \
    'old = "(op=$op; report-only canary, never gated)"
assert s.count(old) == 1
s = s.replace(old, "(op=$op; report-only canary, never gated; extra human-readable tail words)")'
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
# PRESENCE_ROWS is exactly the count of rows an inner (MUT_SKIP) run asserts (the 10 fixture rows
# included — they are also floored on their own by EVAL_MIN, so an emptied loop fails THAT row
# first); the outer run adds one row per mutation. The instrument control is what catches a
# floor drifting past the rows. Floor/ledger trips exit 1 (verdict-class: the battery grades
# inner rc 1 as a CAUGHT mutation); instrument failures exit 2.
# Self-reference (accepted residual, #11899 item 8): a row-count decrement landing alongside a
# row deletion stays green — PRESENCE_ROWS/MUT_ROWS are declared here and read only below.
PRESENCE_ROWS=45
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); FCSB_GUARD_{TF,WF,CI,RB,IV}=%s,%s,%s,%s,%s\n' "$_floor" "${FCSB_GUARD_TF:-unset}" "${FCSB_GUARD_WF:-unset}" "${FCSB_GUARD_CI:-unset}" "${FCSB_GUARD_RB:-unset}" "${FCSB_GUARD_IV:-unset}"
printf '\n=== faithful-canary-sandbox-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
