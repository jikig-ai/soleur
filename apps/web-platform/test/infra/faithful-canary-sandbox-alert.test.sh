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

LOCAL_SQL="$(awk '/^[[:space:]]*faithful_canary_sandbox_broken_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
SQL_N="$(sed 's/^[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/ $//' <<< "$LOCAL_SQL")"
ALERT="$(awk '/^resource "logtail_exploration_alert" "faithful_canary_sandbox_broken" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "faithful_canary_sandbox_broken" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"

line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
sql_has() {  # sql_has <fixed conjunct text, one normalised line of the heredoc>
  grep -qxF -- "AND $1" <<< "$SQL_N"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "faithful_canary_sandbox_broken_sql: heredoc not found — every predicate row below would be vacuous"

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
# Anti-vacuity floor on the fixture loop (reported by printf + exit 2, never through ok()/no()): a loop that evaluated
# zero rows would otherwise print no [FAIL] and pass.
EVAL_SUB=0
EVAL_MIN=10
EVAL_REAL=$((EV_N - EVAL_SUB))
if [ "$EVAL_REAL" -lt "$EVAL_MIN" ]; then
  no "fixture floor: only $EVAL_REAL fixture rows evaluated (floor $EVAL_MIN)"
fi

# ── The exploration and the alert ──────────────────────────────────────────────────────────────────
line_in "$EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.faithful_canary_sandbox_broken_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.faithful_canary_sandbox_broken_sql as its sql_query"
line_in "$EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.faithful_canary_sandbox_broken exists (exact header)" \
  || no "logtail_exploration_alert.faithful_canary_sandbox_broken is missing"
line_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.faithful_canary_sandbox_broken\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.faithful_canary_sandbox_broken.id"
line_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-faithful-canary-sandbox-broken-prd"' \
  && line_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-faithful-canary-sandbox-broken-prd"' \
  && ok "both are named soleur-faithful-canary-sandbox-broken-prd" \
  || no "the exploration/alert name drifted from soleur-faithful-canary-sandbox-broken-prd"
line_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && line_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE failed-smoke row alerts (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single failed smoke would not alert"
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
  && ok "confirmation_period 0 and recovery_period 600: one row alerts within about a minute, auto-resolve after 10 quiet minutes" \
  || no "confirmation_period is not 0 or recovery_period is not 600"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
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

RB_URL_RE='^[[:space:]]*faithful_canary_sandbox_broken_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set\.md#[a-z0-9_-]+"'
grep -qE '^[[:space:]]*incident_cause[[:space:]]*=.*Runbook: \$\{local\.faithful_canary_sandbox_broken_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && line_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.faithful_canary_sandbox_broken_runbook_url' \
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

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file (or this guard) into $MUT_DIR, mutates the copy, and re-runs the guard with
# MUT_SKIP=1 and the matching FCSB_GUARD_* override pointing at the copy. SELF rows mutate a copy of THIS file.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=37   # the real count of non-mutation assertions in a green run (47 total - 10 mutation rows); the 10 fixture rows are also floored on their own (EVAL_MIN above), so an emptied loop fails THAT row first
MUT_ROWS=10
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t fcsbalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below would grade a broken
  # invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|CI|RB|SELF> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/ci-deploy.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/canary-probe-set.md" ;;
      SELF) src="$SELF"; copy="$MUT_DIR/guard-copy.sh" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    # The heredoc below is UNQUOTED on purpose: the shell interpolates $prog into it exactly once and never rescans the
    # result. Its own body must therefore stay free of $, backticks and backslashes.
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry identical tag conjuncts.
    i = s.index("  faithful_canary_sandbox_broken_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    if [ "$which" = SELF ]; then
      # The guard copy lives outside the repo: pin every input to the pristine absolute paths.
      env "FCSB_GUARD_TF=$TF" "FCSB_GUARD_WF=$WF" "FCSB_GUARD_CI=$CI" "FCSB_GUARD_RB=$RB" MUT_SKIP=1 bash "$copy" >"$ilog" 2>&1 || rc=$?
    else
      env "FCSB_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
    fi
    # Only rc=1 (an assertion went red) is a caught mutation; rc>=2 is this guard's own FATAL class, with ONE exception: the
    # inner assertion floor is now the EXACT inner count, so a mutation that removes assertion rows (an emptied fixture loop)
    # ALSO trips the floor (rc=2, "[FATAL] assertion floor"). That is the floor doing its job, and it is accepted only together
    # with the targeted `[FAIL] <row>` line below. A RED row must ALSO name the row it targets: "any row failed" would let one
    # unrelated red row certify every mutation.
    if [ "$want:$rc" = "RED:2" ] && grep -qF -- '[FATAL] assertion floor' "$ilog"; then rc=1; fi
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

  # M1 — the reason needle is dropped in the .tf: inner bwrap_* rows (and, while they exist, outer-wrap rows) would page.
  mutate RED "the reason needle is dropped from the startsWith (inner bwrap_* and outer-wrap rows would match)" TF \
    "the startsWith conjunct is missing" \
    's = sql_replace(s, " reason=sdk_bash_smoke_failed\x27)", "\x27)")'
  # M3 — a second alert resource without its -target= lines, after a compliant first.
  mutate RED "a second logtail alert is added to the .tf without its -target= lines (census)" TF \
    "census: -target= lines missing from the main plan for: logtail_exploration.second_probe_alert" \
    's = s + "\nresource \"logtail_exploration_alert\" \"second_probe_alert\" {\n  name = \"x\"\n}\n"'
  # M4 — the ';' terminator is dropped from the op needle: op=sandbox-canary-outer-wrap rows would match.
  mutate RED "the ';' is dropped from the op needle (op=sandbox-canary-outer-wrap would match)" TF \
    "the position() conjunct is missing" \
    's = sql_replace(s, "(op=sandbox-canary;\x27) > 0", "(op=sandbox-canary\x27) > 0")'
  # M5 — the emitter's op string is edited in ci-deploy.sh (the needle is read from it).
  mutate RED "the smoke page call's op is edited in ci-deploy.sh (the alert would silently stop matching)" CI \
    "the position() conjunct is missing, altered, or no longer equals the op terminator" \
    'old = "\"\" \"sandbox-canary\" || true"
assert s.count(old) == 1
s = s.replace(old, "\"\" \"sandbox-canary-smoke\" || true")'
  # M5b — the smoke reason is reworded in ci-deploy.sh only.
  mutate RED "the smoke reason is reworded in ci-deploy.sh only (the alert would silently stop matching)" CI \
    "the startsWith conjunct is missing, altered, or no longer equals the marker" \
    's = s.replace("\"sdk_bash_smoke_failed: ", "\"sdk_bash_smoke_broke: ")'
  # M6 — the tag conjunct is dropped.
  mutate RED "the tag conjunct is dropped (quoting rows under another SYSLOG_IDENTIFIER could alert)" TF \
    "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing" \
    's = sql_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n", "")'
  # M7 — either -target= line is dropped.
  mutate RED "the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration_alert.faithful_canary_sandbox_broken \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # M2 — the guard's fixture loop is emptied (zero rows evaluated) while everything else stays intact.
  mutate RED "the fixture loop is emptied (zero rows evaluated: the floor must catch it)" SELF \
    "fixture floor: only 0 fixture rows evaluated" \
    'old = "for name, ident, message, want in " + "FIXTURES:"
assert s.count(old) == 1
s = s.replace(old, "for name, ident, message, want in []:")'
  # M8 — the predicate evaluator is replaced by a constant true: the negative fixtures must then be graded wrong.
  mutate RED "the predicate evaluator is replaced by constant true (negative fixtures must grade wrong)" SELF \
    "fixture row graded wrong: standing outer-wrap row" \
    'old = "    return all(check(c, raw) " + "for c in conjuncts)"
assert s.count(old) == 1
s = s.replace(old, "    return True")'
  # M9 — must-PASS: the emitter's human tail after the op terminator is reworded (a permitted variation): the needles stop at
  # the terminator, so the alert still matches.
  mutate PASS "the emitter's human-readable tail after the op terminator is lengthened (the needles do not read it)" CI \
    "" \
    'old = "(op=$op; report-only canary, never gated)"
assert s.count(old) == 1
s = s.replace(old, "(op=$op; report-only canary, never gated; extra human-readable tail words)")'
fi

# INNER (MUT_SKIP) floor = the real inner count, 37 presence rows (the same number as PRESENCE_ROWS above); the OUTER floor is
# PRESENCE_ROWS + MUT_ROWS = 47.
# Reported by printf + exit 2 (never through ok()/no()), with both operands literal on the lines immediately above the if.
SELFTEST_ROWS=0
MIN_ASSERTIONS=37
REAL=$((pass + fail - SELFTEST_ROWS))
if [ -z "${MUT_SKIP:-}" ]; then MIN_ASSERTIONS=$((PRESENCE_ROWS + MUT_ROWS)); fi
if [ "$REAL" -lt "$MIN_ASSERTIONS" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$REAL" "$MIN_ASSERTIONS" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== faithful-canary-sandbox-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$REAL" "$MIN_ASSERTIONS"
[ "$fail" -eq 0 ]
