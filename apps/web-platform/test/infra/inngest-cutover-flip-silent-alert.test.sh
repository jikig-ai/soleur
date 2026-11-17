#!/usr/bin/env bash
#
# Drift guard for the "Inngest cutover-flip unit went silent" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf,
# logtail_exploration_alert.inngest_cutover_flip_silent) — #11820.
#
# WHAT THE ALERT IS FOR. After the flip-token split the cutover-flip unit runs `doppler run` under its
# own read/write Doppler token, so a revoked, rotated-alone or invalid flip token fails the unit before
# any script code runs, on every 30 s timer start. The throttled `noop-*` liveness row (one per
# CUTOVER_NOOP_THROTTLE_S, journald tag `inngest-cutover-flip`) then stops arriving as a JSON row. The
# same silence covers a boot-time flip-file write abort and the LUKS key-continuity probe, which only
# runs from the unit's terminal arms.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The tag is PINNED TO THE EMITTER: `readonly LOG_TAG=` is read from inngest-cutover-flip.sh, so a
#     one-sided retag in the .tf reds here instead of silently disarming the alert.
#   * The predicate is compared WHOLE, whitespace-normalised. Since #12726 it is ADR-218's host-count
#     canon with a roster of one: the value is
#       greatest(toInt64(1) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0)
#     (1 = the production host sent no object row in the window, 0 = healthy), over tag AND the pinned
#     production host AND `JSONType(raw,'message') = 'Object'`, with no GROUP BY (an aggregate without
#     one always returns one row, so a fully dark window reads 1, not "no data"). The JSONType conjunct
#     is the discriminator (CTO ruling, 2026-11-02): the flip rows carry an OBJECT-typed `message`, the
#     doppler error lines under the same tag carry a STRING one. The value expression, the roster
#     literal and the absence of GROUP BY each have their own row, so each revert reds for its own reason.
#   * The PINNED TRIPLE, on BOTH alerts (CTO F4, ADR-218 2026-11-17): `operator = "higher_than"`,
#     `value = 0`, `on_missing_data = "treat_as_zero"`. The evaluator has read 0 on every `lower_than`
#     silence alert measured in this account (#11869, #12180, #12726), so the inverted shape makes that
#     zero read healthy. There is no family-wide pin; this guard pins its own alert. Operator counts read
#     non-comment lines only, so a comment that records the old shape stays green.
#   * The window is checked against the emitter: query_period must hold at least three throttle
#     intervals, or one late row would page.
#   * The paging semantics (check 300, query 900, confirmation 0, recovery 900, email only,
#     critical_alert=false, the free/paid escalation ternary) and the ARMED state (`paused = false`).
#   * The THROWAWAY CANARY pair (`inngest_cutover_flip_silent_canary`, #12726, retired in PR-C): its SQL
#     is the production local with only the host pin swapped to a host no machine has, by ONE `replace()`
#     line. This guard never evaluates HCL, so the no-op hole (a `replace()` whose search text is not in
#     its input makes the canary a copy of production that never fires) is closed by presence rows: the
#     whole `replace()` line is pinned with its search text built from the host inngest-bootstrap.sh
#     renders; that host appears exactly once in the production predicate; the production local has
#     exactly 2 consumers and the canary local exactly 1; the canary host appears nowhere under
#     apps/web-platform/infra/ but that line. The canary alert block equals the production block apart
#     from name / exploration_id / incident_cause, its cause starts at byte 0 with the plain-ASCII
#     "CANARY, expected to stay open; do not resolve or close its mirror issue" (the incident mirror cuts
#     the sanitised cause at 300 bytes), each name literal appears exactly twice, and the
#     `inngest_cutover_flip_silent*` resource headers number exactly 4 across every infra *.tf (not
#     anchored to line start, so a commented-out decoy still counts; PR-C moves this to 2).
#   * All four resources are in the apply workflow's MAIN plan -target= allowlist (terraform-target-parity
#     covers terraform_data only, so this guard is the only enforcement for logtail resources).
#   * The incident text says the alert is EXPECTED during an owner-authorized replace (no suppression
#     is built; it stays open on #11820), the runbook section names the alert, the standing-alarms table
#     names it, and infra-validation.yml runs this guard in a blocking step.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is unpaused IN PRODUCTION (set by the merge apply), that the
# evaluator can deliver a non-zero value for this predicate shape (that is what the canary is for, read on the
# tracker at apply +25 min and +4 h), why the evaluator read 0 under `lower_than` (INFERRED, ADR-218
# 2026-11-05), nor that a real row reaches Better Stack. It compares values one diff can edit together —
# consistency, not integrity.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the COPY, and
# re-runs this guard against it through the FLIPSILENT_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${FLIPSILENT_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${FLIPSILENT_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
EM="${FLIPSILENT_GUARD_EM:-$REPO/apps/web-platform/infra/inngest-cutover-flip.sh}"
RB="${FLIPSILENT_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/inngest-server.md}"
LQ="${FLIPSILENT_GUARD_LQ:-$REPO/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md}"
IV="${FLIPSILENT_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"
BS="${FLIPSILENT_GUARD_BS:-$REPO/apps/web-platform/infra/inngest-bootstrap.sh}"
# The tree the anti-collision scan and the resource-header count read (every infra *.tf; the alerts
# file itself is always read through $TF, so a TF override is never double-counted).
INFRA="${FLIPSILENT_GUARD_INFRA:-$REPO/apps/web-platform/infra}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Pure-bash helpers (no pipes): has LITERAL TEXT -> TEXT contains LITERAL; cnt LITERAL TEXT -> occurrences.
has() { [[ "$2" == *"$1"* ]]; }
cnt() { local t="${2//"$1"/}"; printf '%s' $(( (${#2} - ${#t}) / ${#1} )); }

# Byte-identical to the ghcr-blocked-alert copy (the P1b assert_fixture_dir shape): a cd-failed
# override yields EMPTY and would root every read at /.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$EM"; assert_fixture_dir "$RB"; assert_fixture_dir "$LQ"; assert_fixture_dir "$IV"; assert_fixture_dir "$BS"; assert_fixture_dir "$INFRA"
[ -d "$INFRA" ] || { printf '[FATAL] not a directory: %s\n' "$INFRA" >&2; exit 2; }

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$EM" "$RB" "$LQ" "$IV" "$BS"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*inngest_cutover_flip_silent_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^[[:space:]]*SQL$/{exit} f' "$TF")"
# Layout-independent view: every run of whitespace is one space, and no space sits inside a
# parenthesis pair (the resource collapses it the same way).
SQL_1="$(tr '\n' ' ' <<< "$LOCAL_SQL" | sed 's/[[:space:]][[:space:]]*/ /g; s/( /(/g; s/ )/)/g; s/^ //; s/ $//')"
ALERT="$(awk '/^resource "logtail_exploration_alert" "inngest_cutover_flip_silent" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "inngest_cutover_flip_silent" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
CANARY_ALERT="$(awk '/^resource "logtail_exploration_alert" "inngest_cutover_flip_silent_canary" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
CANARY_EXPL="$(awk '/^resource "logtail_exploration" "inngest_cutover_flip_silent_canary" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
# Executable text only: every count below that must not be moved by a comment reads this.
TF_CODE="$(grep -vE '^[[:space:]]*#' "$TF")"
CANARY_HOST='soleur-inngest-canary-absent'
# Bounded at the first `rc=` line-start — the plan step's own `rc=${PIPESTATUS[0]}` capture.
# The old `rc=$?` terminator never matched it, so the slice silently ran to EOF (#11899).
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=/{exit}' "$WF")"

# Whole-line assertions anchored at both ends; greps over captured variables read HERE-STRINGS,
# never `printf … | grep -q` (pipefail + early-match SIGPIPE fails a negated check OPEN).
line_in() { grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"; }
top_in() { grep -qE "^  $2[[:space:]]*(#.*)?$" <<< "$1"; }
blk_in() { grep -qE "^    $2[[:space:]]*(#.*)?$" <<< "$1"; }

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "inngest_cutover_flip_silent_sql: heredoc not found — every predicate row below would be vacuous"

# ── the emitter: the tag and the cadence are READ, not retyped ────────────────────────────────
EMIT_TAG="$(sed -n 's/^readonly LOG_TAG="\([^"]*\)".*/\1/p' "$EM" | head -1)"
if [ "$EMIT_TAG" = "inngest-cutover-flip" ]; then
  ok "inngest-cutover-flip.sh logs under readonly LOG_TAG=inngest-cutover-flip; the tag is captured from it"
else
  no "inngest-cutover-flip.sh no longer defines readonly LOG_TAG=inngest-cutover-flip (got '${EMIT_TAG:-<none>}') — the alert would silently stop matching"
fi
# The host_name the alert pins is the literal the bootstrap renders into Vector's @@HOST_NAME@@ sentinel for
# the inngest host: read it from there, so a host rename that leaves the .tf behind reds here.
BS_HOST="$(sed -n "s/^[[:space:]]*sed -i 's|@@HOST_NAME@@|\([^|]*\)|g'.*/\1/p" "$BS" | head -1)"
if [ -n "$BS_HOST" ] && grep -qF "JSONExtractString(raw, 'host_name') = '${BS_HOST}'" <<< "$(tr '\n' ' ' <<< "$LOCAL_SQL" | sed 's/[[:space:]][[:space:]]*/ /g')"; then
  ok "the alert pins host_name = '${BS_HOST}', the literal inngest-bootstrap.sh renders into Vector's @@HOST_NAME@@"
else
  no "the alert's host_name pin does not match the inngest host literal inngest-bootstrap.sh renders (got '${BS_HOST:-<none>}')"
fi
THROTTLE="$(sed -n 's/^NOOP_THROTTLE_S="\${CUTOVER_NOOP_THROTTLE_S:-\([0-9][0-9]*\)}".*/\1/p' "$EM" | head -1)"
if [ -n "$THROTTLE" ]; then
  ok "the emitter's noop throttle default is ${THROTTLE} s (read from NOOP_THROTTLE_S)"
else
  no "could not read the emitter's NOOP_THROTTLE_S default — the window-vs-cadence row below would be vacuous"
fi

# ── the predicate, compared whole ─────────────────────────────────────────────────────────────
# ADR-218's host-count canon with a roster of one (#12726): the EXACT value expression of egress_gw_probe_silent_sql,
# the only inverted shape whose canary fired (incident 1048213461), so the flip alert stays on the proven form.
EXPECT_VALUE="greatest(toInt64(1) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0) AS value"
EXPECT_SQL="SELECT toDateTime({{end_time}}) AS time, ${EXPECT_VALUE} FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}}"
EXPECT_SQL+=" AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') IN ('${EMIT_TAG}')"
EXPECT_SQL+=" AND JSONExtractString(raw, 'host_name') = 'soleur-inngest-prd'"
EXPECT_SQL+=" AND JSONType(raw, 'message') = 'Object'"
if [ -n "$EMIT_TAG" ] && [ "$SQL_1" = "$EXPECT_SQL" ]; then
  ok "the predicate equals the string built from the emitter's own tag (tag + pinned host + object-typed message, one aggregate, dt column)"
else
  no "the predicate is not the expected string (missing-host count over tag + pinned host + object-typed message, no GROUP BY, dt column)"
fi
# Rows 3, 4 and 5 of the mutation matrix each break the whole-SQL row above; each also has its OWN row here, so a
# battery row proves the revert it names, not merely "the SQL changed".
grep -qE "greatest\(toInt64\([0-9]+\) - toInt64\(count\(DISTINCT JSONExtractString\(raw, 'host_name'\)\)\), 0\) AS value" <<< "$SQL_1" \
  && ok "the value expression is the missing-host count: greatest(toInt64(N) - toInt64(count(DISTINCT host_name)), 0)" \
  || no "the value expression is not the missing-host count greatest(toInt64(N) - toInt64(count(DISTINCT host_name)), 0) — a row count reads 0 as silent and the evaluator's 0 would page"
grep -qF "greatest(toInt64(1) - toInt64(count(DISTINCT " <<< "$SQL_1" \
  && ok "the roster literal is toInt64(1): one production Inngest host, so a dark window reads exactly 1" \
  || no "the roster literal is not toInt64(1) — toInt64(0) would read 0 forever (never pages), a larger roster would page on a healthy host"
if grep -qiE '(^|[^A-Za-z_])GROUP[[:space:]]+BY([^A-Za-z_]|$)' <<< "$LOCAL_SQL"; then
  no "the predicate carries a GROUP BY — a fully dark window would return no row (no data) instead of the value 1"
else
  ok "the predicate has no GROUP BY (an aggregate without one always returns one row, so a dark window reads 1)"
fi
# The canary is derived by replace() on THIS host literal: it must occur exactly once in the flattened predicate, and
# be the host inngest-bootstrap.sh renders (read above), so a host rename also moves the replace() search text below.
if [ -n "$BS_HOST" ] && [ "$(grep -oF "'${BS_HOST}'" <<< "$SQL_1" | wc -l)" -eq 1 ]; then
  ok "'${BS_HOST}' appears exactly once in the flattened production predicate (the canary's replace() swaps exactly that one)"
else
  no "the production predicate does not carry the bootstrap host '${BS_HOST:-<none>}' exactly once — the canary's replace() could be a no-op or swap a second occurrence"
fi
grep -qF "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') IN ('${EMIT_TAG}')" <<< "$SQL_1" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER IN (the emitter's tag) - written as IN so the key-probe alert's own tag equality stays the only equality form in the file" \
  || no "the SYSLOG_IDENTIFIER conjunct is missing or altered"
grep -qF "JSONExtractString(raw, 'host_name') = 'soleur-inngest-prd'" <<< "$SQL_1" \
  && ok "the host conjunct pins the production Inngest host (a web or dev host cannot satisfy it)" \
  || no "the host_name = 'soleur-inngest-prd' conjunct is missing or altered"
grep -qF "JSONType(raw, 'message') = 'Object'" <<< "$SQL_1" \
  && ok "the discriminator: the message is an OBJECT (the doppler error lines under the same tag are strings)" \
  || no "the JSONType(raw,'message') = 'Object' discriminator is missing or altered — a failing unit's own doppler error lines would keep the alert green"
if grep -qiE '(^|[^A-Za-z_])NOT([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  no "the predicate carries a negation — an unreadable row would read as a liveness row"
else
  ok "the predicate has no negation"
fi

EXPL_QRY="$(awk '/^  query \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
EXPL_VAR="$(awk '/^  variable \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
blk_in "$EXPL_QRY" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.inngest_cutover_flip_silent_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.inngest_cutover_flip_silent_sql as its sql_query"
blk_in "$EXPL_VAR" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"
[ "$(grep -cE '^  query \{' <<< "$EXPL")" -eq 1 ] && [ "$(grep -cE '^  variable \{' <<< "$EXPL")" -eq 1 ] \
  && blk_in "$EXPL_QRY" 'source_variable[[:space:]]*=[[:space:]]*"source"' \
  && blk_in "$EXPL_QRY" 'query_type[[:space:]]*=[[:space:]]*"sql_expression"' \
  && blk_in "$EXPL_VAR" 'name[[:space:]]*=[[:space:]]*"source"' \
  && ok "the exploration has exactly one query and one variable block, wired source_variable=source -> variable source" \
  || no "the exploration's query/variable wiring is not exactly one sql_expression query reading variable \"source\""

[ -n "$ALERT" ] && ok "logtail_exploration_alert.inngest_cutover_flip_silent exists (exact header)" \
  || no "logtail_exploration_alert.inngest_cutover_flip_silent is missing"
top_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.inngest_cutover_flip_silent\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.inngest_cutover_flip_silent.id"
top_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-inngest-cutover-flip-silent-prd"' \
  && top_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-inngest-cutover-flip-silent-prd"' \
  && ok "both are named soleur-inngest-cutover-flip-silent-prd" \
  || no "the exploration/alert name drifted from soleur-inngest-cutover-flip-silent-prd"
# The pinned triple (CTO F4): each attribute its own row, so mutation rows 1 and 2 and A4 red for their own reason.
top_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && ok "the production alert is a threshold alert" \
  || no "the production alert is not alert_type = threshold"
top_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && ok "the production alert pages on higher_than: the evaluator's stuck 0 reads healthy, a missing host (1) pages" \
  || no "the production alert's operator is not higher_than — under lower_than the evaluator's stuck 0 opens a false incident (#11869, #12726)"
top_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "the production alert's threshold value is 0 (any missing host pages)" \
  || no "the production alert's value is not 0 — with a one-host roster any other threshold never pages"
top_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero kept (CTO R2): a no-data read is 0 = healthy; a dark window is caught by the aggregate, which returns 1" \
  || no "on_missing_data is not treat_as_zero"
# Operator lines are counted over NON-COMMENT text: a comment recording the old shape is allowed (mutation row 18),
# a second executable operator line or a lower_than anywhere in executable text of either flip alert is not.
ALERT_CODE="$(grep -vE '^[[:space:]]*#' <<< "$ALERT")"
CANARY_ALERT_CODE="$(grep -vE '^[[:space:]]*#' <<< "$CANARY_ALERT")"
if [ "$(grep -cE '^[[:space:]]*operator[[:space:]]*=' <<< "$ALERT_CODE")" -eq 1 ] \
   && ! grep -qF 'lower_than' <<< "$ALERT_CODE"$'\n'"$CANARY_ALERT_CODE"; then
  ok "exactly one executable operator line in the production alert, and no lower_than in the executable text of either flip alert"
else
  no "the production alert has more than one executable operator line, or lower_than appears in the executable text of a flip alert"
fi
top_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && ok "paused = false on its own line — the alert is armed (re-armed under #9927 step D2-1a / #12221 decision 2; was paused under the #11869 false positive)" \
  || no "the alert is not armed (paused = false on its own line) — the #9927 D2-1a re-arm must not be lost silently"
top_in "$ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && top_in "$ALERT" 'push[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'call[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'sms[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'critical_alert[[:space:]]*=[[:space:]]*false' \
  && ok "email = true, push/call/sms/critical_alert = false (an alert that fires during every owner-authorized replace must not page)" \
  || no "the channel set drifted from email-only with critical_alert=false"
top_in "$ALERT" 'confirmation_period[[:space:]]*=[[:space:]]*0' \
  && top_in "$ALERT" 'check_period[[:space:]]*=[[:space:]]*300' \
  && top_in "$ALERT" 'query_period[[:space:]]*=[[:space:]]*900' \
  && top_in "$ALERT" 'recovery_period[[:space:]]*=[[:space:]]*900' \
  && ok "check 300 / query 900 / recovery 900 with no confirmation delay (the 900 s ceiling every recent alert stays within)" \
  || no "the paging windows drifted from check 300 / query 900 / confirmation 0 / recovery 900"
QP="$(sed -n 's/^  query_period[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<< "$ALERT" | head -1)"
if [ -n "$THROTTLE" ] && [ -n "$QP" ] && [ "$QP" -ge $((THROTTLE * 3)) ]; then
  ok "the ${QP} s window holds at least three of the emitter's ${THROTTLE} s noop intervals (one late row cannot page)"
else
  no "the query window (${QP:-<none>} s) is shorter than three of the emitter's noop intervals (${THROTTLE:-<none>} s)"
fi
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
line_in "$ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"
# No suppression exists, so the alert MUST tell the reader it is expected during a replace.
grep -qE '^  incident_cause[[:space:]]*=.*EXPECTED during an owner-authorized inngest-host-replace' <<< "$ALERT" \
  && ok "the incident text says the alert is EXPECTED during an owner-authorized inngest-host-replace" \
  || no "the incident text no longer says the alert fires during an owner-authorized replace (no suppression is built)"

RB_URL_RE='^[[:space:]]*inngest_cutover_flip_silent_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-server\.md#flip-token-split-[a-z0-9-]*"'
grep -qE '^  incident_cause[[:space:]]*=.*[Rr]unbook: \$\{local\.inngest_cutover_flip_silent_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && blk_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.inngest_cutover_flip_silent_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the alert's runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable inngest-server.md Flip-token split runbook URL"

grep -qF '### Flip-token split' "$RB" && grep -qF 'inngest_cutover_flip_silent' "$RB" \
  && ok "the runbook's Flip-token split section exists and names the alert" \
  || no "the runbook no longer names inngest_cutover_flip_silent under its Flip-token split section"
grep -qF 'logtail_exploration_alert.inngest_cutover_flip_silent' "$LQ" \
  && ok "betterstack-log-query.md's standing-alarms table names the alert" \
  || no "the standing-alarms row in betterstack-log-query.md is missing"

# The slice must have terminated ON the capture line (count-compare over its last line):
# a deleted or renamed rc= capture re-opens the silent run-to-EOF overshoot (#11899).
[ "$(printf '%s\n' "$MAIN_PLAN" | tail -1 | grep -cE '^[[:space:]]*rc=\$\{PIPESTATUS\[0\]\}$')" -eq 1 ] \
  && ok "MAIN_PLAN is bounded: its last line is the plan step's rc= capture" \
  || no "MAIN_PLAN does not end on the plan step's rc= capture — the slice overshoots past the step or the capture moved"
grep -qE '^[[:space:]]*-target=logtail_exploration\.inngest_cutover_flip_silent \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.inngest_cutover_flip_silent \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

# ── the THROWAWAY CANARY pair (#12726; retired in PR-C after the +4 h tracker read) ───────────
# The guard never evaluates replace(): every row below closes one way the canary could silently equal production.
REPLACE_LINE="  inngest_cutover_flip_silent_canary_sql = replace(local.inngest_cutover_flip_silent_sql, \"'${BS_HOST}'\", \"'${CANARY_HOST}'\")"
if [ -n "$BS_HOST" ] && [ "$(grep -cFx -- "$REPLACE_LINE" "$TF")" -eq 1 ] \
   && [ "$(grep -cE '^[[:space:]]*inngest_cutover_flip_silent_canary_sql[[:space:]]*=' <<< "$TF_CODE")" -eq 1 ]; then
  ok "the canary SQL is derived by ONE whole-line replace() of the production local, swapping only the bootstrap host '${BS_HOST}' for '${CANARY_HOST}'"
else
  no "the canary replace() line is missing, duplicated, reworded or no longer swaps the bootstrap host '${BS_HOST:-<none>}' for '${CANARY_HOST}' — the canary may not be production with one swap"
fi
if [ "$(grep -oE 'local\.inngest_cutover_flip_silent_sql([^A-Za-z0-9_]|$)' <<< "$TF_CODE" | wc -l)" -eq 2 ] \
   && [ "$(grep -oE 'local\.inngest_cutover_flip_silent_canary_sql([^A-Za-z0-9_]|$)' <<< "$TF_CODE" | wc -l)" -eq 1 ]; then
  ok "the production local has exactly 2 consumers (its exploration and the replace() line) and the canary local exactly 1 (the canary exploration)"
else
  no "the SQL locals' consumer counts drifted (want production 2, canary 1) — an exploration reads the wrong local or a decoy consumer exists"
fi
# Anti-collision: no host, Vector config or script may emit the canary host, or the canary would read real rows.
CANARY_TF_N="$(grep -oF "$CANARY_HOST" "$TF" | wc -l)"
CANARY_ELSEWHERE="$(grep -rIlF --exclude-dir=.terraform -- "$CANARY_HOST" "$INFRA" 2>/dev/null | grep -vxF -- "$INFRA/betterstack-logs-alerts.tf" || true)"
if [ "$CANARY_TF_N" -eq 1 ] && [ -z "$CANARY_ELSEWHERE" ]; then
  ok "'${CANARY_HOST}' appears nowhere under the infra tree but the replace() line (anti-collision: nothing can emit it)"
else
  no "the canary host '${CANARY_HOST}' appears outside the replace() line (alerts-file count ${CANARY_TF_N}, want 1; other files: $(printf '%s' "$CANARY_ELSEWHERE" | tr '\n' ' '))"
fi
[ -n "$CANARY_EXPL" ] && [ -n "$CANARY_ALERT" ] \
  && ok "both canary resources exist (exact headers)" \
  || no "a canary resource block is missing (logtail_exploration / logtail_exploration_alert inngest_cutover_flip_silent_canary)"
top_in "$CANARY_ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.inngest_cutover_flip_silent_canary\.id' \
  && ok "the canary alert watches ITS OWN exploration" \
  || no "the canary alert's exploration_id is not logtail_exploration.inngest_cutover_flip_silent_canary.id"
top_in "$CANARY_ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-inngest-cutover-flip-silent-canary-prd"' \
  && top_in "$CANARY_EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-inngest-cutover-flip-silent-canary-prd"' \
  && ok "both canary resources are named soleur-inngest-cutover-flip-silent-canary-prd (the tracker reads and the mirror lookup key on it)" \
  || no "the canary pair is not named soleur-inngest-cutover-flip-silent-canary-prd"
if [ "$(grep -oF '"soleur-inngest-cutover-flip-silent-prd"' <<< "$TF_CODE" | wc -l)" -eq 2 ] \
   && [ "$(grep -oF '"soleur-inngest-cutover-flip-silent-canary-prd"' <<< "$TF_CODE" | wc -l)" -eq 2 ] \
   && [ "$(grep -cE '^[[:space:]]*exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.inngest_cutover_flip_silent\.id[[:space:]]*$' <<< "$TF_CODE")" -eq 1 ] \
   && [ "$(grep -cE '^[[:space:]]*exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.inngest_cutover_flip_silent_canary\.id[[:space:]]*$' <<< "$TF_CODE")" -eq 1 ]; then
  ok "each name literal appears exactly twice (exploration + alert) and each flip exploration is watched by exactly one alert"
else
  no "a flip name literal does not appear exactly twice, or a flip exploration is watched by a number of alerts other than one — a decoy pair carries the name"
fi
HDR_RE='resource "logtail_exploration(_alert)?" "inngest_cutover_flip_silent[A-Za-z0-9_-]*"'
HDR_N="$(grep -oE "$HDR_RE" "$TF" | wc -l)"
while IFS= read -r -d '' _tf; do
  [ "$_tf" = "$INFRA/betterstack-logs-alerts.tf" ] && continue
  HDR_N=$((HDR_N + $(grep -oE "$HDR_RE" "$_tf" | wc -l)))
done < <(find "$INFRA" -name '*.tf' -not -path '*/.terraform/*' -print0)
[ "$HDR_N" -eq 4 ] \
  && ok "exactly 4 inngest_cutover_flip_silent* resource headers across every infra *.tf, comments included (2 alerts, 2 explorations)" \
  || no "the inngest_cutover_flip_silent* resource header count is ${HDR_N}, want 4 (2 alerts + 2 explorations; PR-C moves it to 2)"
CEXPL_QRY="$(awk '/^  query \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$CANARY_EXPL")"
blk_in "$CEXPL_QRY" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.inngest_cutover_flip_silent_canary_sql\), "/\\\\s\+/", " "\)' \
  && ok "the canary exploration carries the DERIVED canary local, collapsed to one line" \
  || no "the canary exploration's sql_query is not local.inngest_cutover_flip_silent_canary_sql — it would read production's query and never fire"
top_in "$CANARY_ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && top_in "$CANARY_ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && top_in "$CANARY_ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "the canary alert is threshold / higher_than / 0, the production triple" \
  || no "the canary alert is not threshold / higher_than / 0 — it no longer exercises the production evaluation"
top_in "$CANARY_ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "the canary alert keeps treat_as_zero" \
  || no "the canary alert's on_missing_data is not treat_as_zero"
# Block equality: comment and blank lines dropped, the three per-alert keys dropped, the header normalised.
strip_alert() { grep -vE '^[[:space:]]*(#|$)' <<< "$1" | grep -vE '^  (name|exploration_id|incident_cause)[[:space:]]*=' | sed -E 's/^resource .*\{$/resource {/'; }
[ -n "$CANARY_ALERT" ] && [ -n "$ALERT" ] && [ "$(strip_alert "$CANARY_ALERT")" = "$(strip_alert "$ALERT")" ] \
  && ok "the canary alert block equals the production alert block apart from name / exploration_id / incident_cause" \
  || no "the canary alert block differs from the production alert block beyond name / exploration_id / incident_cause"
strip_expl() { grep -vE '^[[:space:]]*(#|$)' <<< "$1" | grep -vE '^  name[[:space:]]*=[[:space:]]*"soleur-inngest-cutover-flip-silent(-canary)?-prd"[[:space:]]*$' | grep -vE '^    sql_query[[:space:]]*=' | sed -E 's/^resource .*\{$/resource {/'; }
[ -n "$CANARY_EXPL" ] && [ -n "$EXPL" ] && [ "$(strip_expl "$CANARY_EXPL")" = "$(strip_expl "$EXPL")" ] \
  && ok "the canary exploration equals the production exploration apart from name / sql_query" \
  || no "the canary exploration differs from the production exploration beyond name / sql_query"
# The warning starts at byte 0 in plain ASCII: the mirror files the cause after sanitize | head -c 300 (bytes).
CANARY_WARN='CANARY, expected to stay open; do not resolve or close its mirror issue'
CANARY_CAUSE="$(sed -n 's/^  incident_cause[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' <<< "$CANARY_ALERT")"
if [ "$(grep -cE '^  incident_cause[[:space:]]*=' <<< "$CANARY_ALERT")" -eq 1 ] && [[ "$CANARY_CAUSE" == "$CANARY_WARN"* ]] \
   && ! LC_ALL=C grep -q '[^ -~]' <<< "$CANARY_CAUSE"; then
  ok "the canary incident_cause starts at byte 0 with the plain-ASCII '${CANARY_WARN}'"
else
  no "the canary incident_cause does not start at byte 0 with the plain-ASCII CANARY warning — a reader of its mirror issue would act on it"
fi
grep -qE '^[[:space:]]*-target=logtail_exploration\.inngest_cutover_flip_silent_canary \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.inngest_cutover_flip_silent_canary \\$' <<< "$MAIN_PLAN" \
  && ok "both canary resources are in the MAIN plan's -target= allowlist" \
  || no "a canary -target= line is missing from the MAIN plan — the canary would never apply"

# This guard only runs in CI if infra-validation.yml runs it, and re-runs on a runbook edit.
IV_PR="$(awk '/^  pull_request:$/{p=1;next} p&&/^  [a-z_]+:/{exit} p{print}' "$IV")"
if [ "$(grep -cxF '      - "knowledge-base/engineering/operations/runbooks/inngest-server.md"' <<< "$IV_PR")" -eq 1 ]; then
  ok "infra-validation.yml's pull_request paths list the runbook"
else
  no "infra-validation.yml's pull_request paths no longer list the inngest-server.md runbook — a docs-only edit would not re-run this guard"
fi

# This suite is registered (a suite that never runs guards nothing): an uncommented step, once.
REG_RUN='        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh'
if [ "$(cnt "$REG_RUN"$'\n' "$(cat "$IV")"$'\n')" -eq 1 ]; then
  ok "this suite is registered in infra-validation.yml (exactly one uncommented run step)"
else
  no "infra-validation.yml does not run inngest-cutover-flip-silent-alert.test.sh exactly once"
fi

# A CI-dead guard must not pass. The step: no continue-on-error, no `if:`, and ONLY the keys name + run (a `shell:`,
# `env:`, `working-directory:` ... on it can neuter or redirect the run without being `if`/`continue-on-error`). The
# HOSTING JOB is derived from the step's position (the last job header above the registered run line, a header with a
# trailing comment or a quoted id included), never named here, and is read WHOLE (header, steps, anything after them:
# YAML key order is free): its `if:` must be exactly one line and the one known literal, `continue-on-error` must appear
# nowhere in it (a post-steps copy counts — job keys may sit anywhere in the block), its `needs`/`runs-on` must be the
# known literals, and its own keys are the known set (no `defaults`, `env`, `container`, `strategy`, `services` ...).
# The workflow itself must carry no top-level `defaults:` and no seam env axis in executable text: fragments, not
# literals (#11899) — a runtime-composed name ("MUT_""SKIP", a *_GUARD_* prefix built from quoted pieces) or a
# shell-injection env (BASH_ENV/SHELLOPTS/BASHOPTS) reaches the step with no literal ever present. The only DYNAMIC
# channel — a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults: inside the hosting job — is banned inside the
# derived JOB_BLOCK (an empty slice reds the composite below, so the ban cannot pass vacuously). Comments are ignored.
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
JOB_IF_N="$(awk '/^    if:/ { n++ } END { print n + 0 }' <<<"$JOB_BLOCK")"
JOB_COE_N="$(awk '/^    continue-on-error:/ { n++ } END { print n + 0 }' <<<"$JOB_BLOCK")"
JOB_NEEDS="$(awk '/^    needs:/ { print }' <<<"$JOB_BLOCK")"
JOB_RUNS_ON="$(awk '/^    runs-on:/ { print }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Anything else (or an unrecognised line shape) is listed.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
WF_BAD=""
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && WF_BAD="$WF_BAD top-level-defaults"
_seam_frag=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  has "$_frag" "$IV_CODE" && _seam_frag="$_seam_frag ${_frag}-fragment"
done
[ -n "$_seam_frag" ] && WF_BAD="$WF_BAD suite-seam-in-workflow:$_seam_frag"
if [ -z "$JOB_BLOCK" ]; then
  WF_BAD="$WF_BAD job-slice-empty"
else
  _job_seam=""
  has 'GITHUB_ENV' "$JOB_BLOCK" && _job_seam="$_job_seam GITHUB_ENV"
  has 'GITHUB_PATH' "$JOB_BLOCK" && _job_seam="$_job_seam GITHUB_PATH"
  has 'defaults:' "$JOB_BLOCK" && _job_seam="$_job_seam defaults:"
  [ -n "$_job_seam" ] && WF_BAD="$WF_BAD job-scope-env-write:$_job_seam"
fi
if [ -n "$STEP_BLOCK" ] && [[ "$STEP_BLOCK" != *continue-on-error* ]] && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
   && [ -z "$STEP_BAD" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] && [ "$JOB_COE_N" -eq 0 ] && [ -z "$JOB_BAD" ] && [ -z "$WF_BAD" ] \
   && [ "$JOB_IF_N" -eq 1 ] && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
   && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ]; then
  ok "the registered step has only name+run keys (no if:/continue-on-error:/env:/shell:/...), its hosting job '$HOST_JOB' (derived from the run line's position, never hardcoded) has exactly the one known if:, the known needs/runs-on literals, the known key set and no continue-on-error anywhere in the block, and no seam fragment, top-level or job-local defaults:, or GITHUB_ENV/GITHUB_PATH channel reaches it: the guard cannot be skipped, non-blocking, redirected or env-muted"
else
  no "infra-validation.yml: the registered step or its hosting job '$HOST_JOB' is conditional, non-blocking, redirected or extra-keyed (step keys beyond name/run: '${STEP_BAD//$'\n'/ }'; job keys beyond name/needs/if/runs-on/permissions/timeout-minutes/steps: '${JOB_BAD//$'\n'/ }'; workflow flags:${WF_BAD:- none}; '^    if:' count=$JOB_IF_N want 1 literal; '^    continue-on-error:' count=$JOB_COE_N want 0 over the whole block; needs='${JOB_NEEDS:-<none>}'; runs-on='${JOB_RUNS_ON:-<none>}'), or the step/job could not be located"
fi

echo ""
echo "=== inngest-cutover-flip-silent-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching FLIPSILENT_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
PRESENCE_ROWS=32
MUT_ROWS_EXPECTED=29
SELFTEST_ROWS=1
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t flipsilentalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  # land <copy> <python-program-on-s>: apply one mutation to a COPY. Exit 0 only when the program ran AND changed the
  # file; an anchor that matches nothing (an assert, a .index miss) or a no-op program exits non-zero.
  land() {
    MUT_PROG="$2" python3 - "$1" <<'PY'
import os, re, sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry
    # identical conjuncts earlier on.
    i = s.index("  inngest_cutover_flip_silent_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
def blk(s, rtype, label):
    # The [start, end) span of ONE resource block, from its exact header to its own closing brace: a mutation
    # anchored here cannot land on one of the other alerts in the file.
    i = s.index('resource "%s" "%s" {\n' % (rtype, label))
    return i, s.index("\n}\n", i) + 3
def blk_set(s, rtype, label, attr, new_line):
    i, j = blk(s, rtype, label)
    b, n = re.subn(r"(?m)^  %s[ \t]*=.*$" % re.escape(attr), lambda m: new_line, s[i:j], count=1)
    assert n == 1, "attribute %s not found in %s.%s" % (attr, rtype, label)
    return s[:i] + b + s[j:]
def blk_after(s, rtype, label, attr, extra):
    # Insert EXTRA (whole lines) after the block's top-level ATTR line.
    i, j = blk(s, rtype, label)
    m = re.search(r"(?m)^  %s[ \t]*=.*\n" % re.escape(attr), s[i:j])
    assert m, "attribute %s not found in %s.%s" % (attr, rtype, label)
    k = i + m.end()
    return s[:k] + extra + s[k:]
# The canary derivation line exactly as the guard pins it (rows M6-M8b mutate it).
CANARY_LINE = "  inngest_cutover_flip_silent_canary_sql = replace(local.inngest_cutover_flip_silent_sql, \"'soleur-inngest-prd'\", \"'soleur-inngest-canary-absent'\")"
exec(os.environ["MUT_PROG"])
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
  }

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|IV|EM|RB|LQ|BS|INFRA> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy ov rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      EM) src="$EM"; copy="$MUT_DIR/inngest-cutover-flip.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/inngest-server.md" ;;
      LQ) src="$LQ"; copy="$MUT_DIR/betterstack-log-query.md" ;;
      BS) src="$BS"; copy="$MUT_DIR/inngest-bootstrap.sh" ;;
      # INFRA: a fresh scratch tree holding ONE planted (initially empty) file; the override is the tree.
      INFRA) rm -rf "$MUT_DIR/infra"; mkdir -p "$MUT_DIR/infra" || { printf '[FATAL] mutate: mkdir failed\n' >&2; exit 2; }
             src=/dev/null; copy="$MUT_DIR/infra/planted.toml" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    ov="$copy"; [ "$which" = INFRA ] && ov="$MUT_DIR/infra"
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    land "$copy" "$prog" || { no "mutation '$label' did not land (anchor drifted)"; MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1)); return 0; }
    env "FLIPSILENT_GUARD_${which}=$ov" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
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
    MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
  }

  # INSTRUMENT SELF-TEST (a presence row, not a battery row): the landing step must REFUSE a program that matches
  # nothing, a program that changes nothing and a block attribute that does not exist, and accept a real edit.
  # Without it, a battery row whose anchor drifted could be graded on an unmutated copy.
  cp "$TF" "$MUT_DIR/selftest.tf" || { printf '[FATAL] self-test: cp failed\n' >&2; exit 2; }
  st_miss=0; land "$MUT_DIR/selftest.tf" 'old = "NO-SUCH-ANCHOR-12726"
assert s.count(old) == 1' 2>/dev/null || st_miss=$?
  st_noop=0; land "$MUT_DIR/selftest.tf" 'pass' 2>/dev/null || st_noop=$?
  st_blk=0; land "$MUT_DIR/selftest.tf" 's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent", "no_such_attribute_12726", "x")' 2>/dev/null || st_blk=$?
  st_hit=0; land "$MUT_DIR/selftest.tf" 's = s + "\n"' || st_hit=$?
  if [ "$st_miss" -ne 0 ] && [ "$st_noop" -ne 0 ] && [ "$st_blk" -ne 0 ] && [ "$st_hit" -eq 0 ]; then
    ok "instrument self-test: the landing step refuses a non-matching anchor (rc $st_miss), a no-op program (rc $st_noop) and a missing block attribute (rc $st_blk), and lands a real edit"
  else
    no "instrument self-test: the landing step graded a non-landing mutation as landed (miss rc $st_miss, no-op rc $st_noop, missing-attribute rc $st_blk, want all non-zero; real edit rc $st_hit, want 0)"
  fi
  MUT_ROWS_RUN=0

  # A1 — the object-typed discriminator is dropped: the failing unit's own doppler lines keep it green.
  mutate RED "A1 the JSONType object discriminator is dropped (a string doppler error line would count as liveness)" TF \
    "the JSONType(raw,'message') = 'Object' discriminator is missing" \
    's = sql_replace(s, "\n      AND JSONType(raw, \x27message\x27) = \x27Object\x27", "")'
  # A2 — the host pin is dropped: a web or dev host emitting the tag could satisfy the alert.
  mutate RED "A2 the host_name pin is dropped (another host's rows could satisfy the alert)" TF \
    "the host_name = 'soleur-inngest-prd' conjunct is missing" \
    's = sql_replace(s, "\n      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-inngest-prd\x27", "")'
  # A3 — a -target= line is dropped from the apply allowlist.
  mutate RED "A3 the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration_alert.inngest_cutover_flip_silent \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # A4 — on_missing_data is no longer treat_as_zero: a fully dark window would not read as 0.
  mutate RED "A4 on_missing_data is no longer treat_as_zero" TF \
    "on_missing_data is not treat_as_zero" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"inngest_cutover_flip_silent\" \{.*?\n  on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  # A5 — the guard's OWN dispatch: the run: step goes non-blocking in infra-validation.yml.
  mutate RED "A5 the guard step becomes non-blocking (continue-on-error)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)'
  # A7 — the emitter is retagged while the .tf is untouched (the alert would silently stop matching).
  mutate RED "A7 the emitter's LOG_TAG is retagged (the .tf tag is read from it)" EM \
    "inngest-cutover-flip.sh no longer defines readonly LOG_TAG" \
    'old = "readonly LOG_TAG=\"inngest-cutover-flip\""
assert s.count(old) == 1
s = s.replace(old, "readonly LOG_TAG=\"inngest-cutover-flop\"")'
  # A8 — the emitter's noop throttle grows past a third of the window (one late row would page).
  mutate RED "A8 the noop throttle default grows to 600 s (the 900 s window no longer holds three intervals)" EM \
    "the query window (900 s) is shorter than three of the emitter" \
    'old = "NOOP_THROTTLE_S=\"${CUTOVER_NOOP_THROTTLE_S:-300}\""
assert s.count(old) == 1
s = s.replace(old, "NOOP_THROTTLE_S=\"${CUTOVER_NOOP_THROTTLE_S:-600}\"")'
  # A9 — the runbook stops naming the alert.
  mutate RED "A9 the runbook no longer names the alert" RB \
    "the runbook no longer names inngest_cutover_flip_silent" \
    'assert "inngest_cutover_flip_silent" in s
s = s.replace("inngest_cutover_flip_silent", "inngest_cutover_flip_gone")'
  # A10 — the standing-alarms row disappears from the log-query runbook.
  mutate RED "A10 the standing-alarms row is removed" LQ \
    "the standing-alarms row in betterstack-log-query.md is missing" \
    'assert "logtail_exploration_alert.inngest_cutover_flip_silent" in s
s = s.replace("logtail_exploration_alert.inngest_cutover_flip_silent", "logtail_exploration_alert.inngest_cutover_flip_gone")'
  # A11 — the incident text stops warning that the alert fires during a replace.
  mutate RED "A11 the incident text no longer says the alert is expected during a replace" TF \
    "the incident text no longer says the alert fires during an owner-authorized replace" \
    'old = "EXPECTED during an owner-authorized inngest-host-replace"
assert s.count(old) == 1
s = s.replace(old, "possible during a host change")'
  # A12 — the host literal in the bootstrap changes while the .tf pin is untouched.
  mutate RED "A12 the inngest host literal in inngest-bootstrap.sh changes (the .tf pin is read against it)" BS \
    "the alert's host_name pin does not match the inngest host literal" \
    'old = "sed -i \x27s|@@HOST_NAME@@|soleur-inngest-prd|g\x27"
assert s.count(old) == 1
s = s.replace(old, "sed -i \x27s|@@HOST_NAME@@|soleur-inngest-prod|g\x27")'
  # A13 - the alert is re-paused: the armed declaration this guard pins is lost silently.
  mutate RED "A13 paused flips back to true (the #9927 D2-1a re-arm is silently lost)" TF \
    "the alert is not armed" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"inngest_cutover_flip_silent\" \{.*?\n  paused\s*=\s*)false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  # Must-PASS: layout is not part of the contract (the resource flattens the predicate with
  # replace(…, "/\\s+/", " ")).
  mutate PASS "A6 every heredoc line is re-indented far deeper (layout is not part of the contract)" TF \
    "" \
    'import re
i = s.index("  inngest_cutover_flip_silent_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
head, rest = s[i:j].split("\n", 1)
s = s[:i] + head + "\n" + re.sub(r"(?m)^\s+", "                    ", rest) + s[j:]'
  # A14–A19 — workflow seam rows (#11899): composed/injected env names and the job-scope channel.
  mutate RED "A14 a runtime-composed MUT_SKIP name reaches the workflow (no literal present)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"MUT_\"\"SKIP=1\" >> \"$GITHUB_ENV\"\n")'
  mutate RED "A15 a GUARD-fragmented env name reaches the workflow's executable text" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          FOO_GUARD_X: /dev/null\n")'
  mutate RED "A16 a BASH_ENV shell-injection env reaches the workflow" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          BASH_ENV: /tmp/x\n")'
  mutate RED "A17 a GITHUB_ENV write inside the suite's own job (the only dynamic env channel)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"FOO=1\" >> \"$GITHUB_ENV\"\n")'
  mutate PASS "A18 the same GITHUB_ENV write lands in the plan: job (another job's writes are out of scope)" IV \
    "" \
    'old = "  plan:\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"FOO=1\" >> \"$GITHUB_ENV\"\n")'
  mutate RED "A19 the suite's run line is removed (the registration count and the job slice both lose it)" IV \
    "infra-validation.yml does not run inngest-cutover-flip-silent-alert.test.sh exactly once" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # A24–A29 — CI-dead shape rows (#11899 clientip-dialect convergence): the step/job key
  # allowlists, the dash-line - if:, post-steps job keys, and a top-level defaults:.
  mutate RED "A24 the registered step gains an env: key (a step key beyond name+run)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "        run: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          FOO: /dev/null\n")'
  mutate RED "A25 the hosting job gains an env: key (a job key beyond the known set)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    env:\n      FOO: /dev/null\n")'
  mutate RED "A26 the registered step's dash line becomes - if: (conditional step at the - dash position)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "      - name: Run Inngest cutover-flip silence alert drift guard (#11820)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run Inngest cutover-flip silence alert drift guard (#11820)\n")'
  mutate RED "A27 a job-level continue-on-error sits AFTER the job's steps (YAML key order is free)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "          fi\n\n  # Aggregator (#8736): the single verdict"
assert s.count(old) == 1
s = s.replace(old, "          fi\n    continue-on-error: true\n\n  # Aggregator (#8736): the single verdict")'
  mutate RED "A28 a second job-level if: sits after the job's steps (the ^    if: count must stay exactly one)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "          fi\n\n  # Aggregator (#8736): the single verdict"
assert s.count(old) == 1
s = s.replace(old, "          fi\n    if: false\n\n  # Aggregator (#8736): the single verdict")'
  mutate RED "A29 the workflow gains a top-level defaults: (a run.shell or env default would reach every job)" IV \
    "infra-validation.yml: the registered step or its hosting job" \
    'old = "\nenv:\n  TERRAFORM_VERSION"
assert s.count(old) == 1
s = s.replace(old, "\ndefaults:\n  run:\n    shell: bash\nenv:\n  TERRAFORM_VERSION")'
  # A20–A23 — the bounded MAIN_PLAN slice (#11899): the overshoot shapes and the terminator itself.
  mutate RED "A20 the alert's -target= lines are moved below the plan step's rc= capture" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration.inngest_cutover_flip_silent \\\n              -target=logtail_exploration_alert.inngest_cutover_flip_silent \\\n"
assert s.count(old) == 1
s = s.replace(old, "")
anchor = "          rc=${PIPESTATUS[0]}\n"
i = s.index(anchor)
s = s[:i] + anchor + old + s[i:]'
  mutate RED "A21 the plan step's rc= capture is deleted (the slice re-overshoots silently)" WF \
    "MAIN_PLAN does not end on the plan step" \
    'i = s.index("            terraform plan -no-color")
old = "          rc=${PIPESTATUS[0]}\n"
j = s.index(old, i)
s = s[:j] + s[j + len(old):]'
  mutate PASS "A22 a second terraform plan block with decoy -target= lines sits after the real step" WF \
    "" \
    'anchor = "          rc=${PIPESTATUS[0]}\n"
i = s.index(anchor)
s = s[:i] + anchor + "            terraform plan -no-color -input=false \\\n              -target=logtail_exploration.decoy_nope \\\n          rc=${PIPESTATUS[0]}\n" + s[i:]'
  mutate RED "A23 the rc= capture is renamed to plan_rc= (the line-start terminator misses)" WF \
    "MAIN_PLAN does not end on the plan step" \
    'i = s.index("            terraform plan -no-color")
old = "          rc=${PIPESTATUS[0]}\n"
j = s.index(old, i)
s = s[:j] + "          plan_rc=${PIPESTATUS[0]}\n" + s[j + len(old):]'
  # ── #12726 matrix (plan Guard Contract rows 1-18; rows 12 and 13 are A1 and A5 above, row 10b's production
  # half is A4). Every attribute edit is anchored to ITS OWN resource block (blk_set/blk_after), so it cannot land
  # on another alert and SURVIVE for the wrong reason.
  mutate RED "M1 the production operator reverts to lower_than" TF \
    "the production alert's operator is not higher_than" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent", "operator", "  operator            = \"lower_than\"")'
  mutate RED "M2 the production value reverts to 1" TF \
    "the production alert's value is not 0" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent", "value", "  value               = 1")'
  mutate RED "M3 the value expression reverts to count(*)" TF \
    "the value expression is not the missing-host count" \
    's = sql_replace(s, "greatest(toInt64(1) - toInt64(count(DISTINCT JSONExtractString(raw, \x27host_name\x27))), 0) AS value", "count(*) AS value")'
  mutate RED "M4 a GROUP BY time is appended to the production SQL" TF \
    "the predicate carries a GROUP BY" \
    'old = "\n      AND JSONType(raw, \x27message\x27) = \x27Object\x27\n"
s = sql_replace(s, old, old + "    GROUP BY time\n")'
  mutate RED "M5 the roster literal toInt64(1) becomes toInt64(0) (the value would be 0 forever)" TF \
    "the roster literal is not toInt64(1)" \
    's = sql_replace(s, "greatest(toInt64(1)", "greatest(toInt64(0)")'
  mutate RED "M6 the canary local stops deriving from the production local (a hand-copied SQL string)" TF \
    "the canary replace() line is missing" \
    'assert s.count(CANARY_LINE + "\n") == 1
s = s.replace(CANARY_LINE + "\n", "  inngest_cutover_flip_silent_canary_sql = <<-SQL\n    SELECT toDateTime({{end_time}}) AS time, 1 AS value FROM {{source}}\n  SQL\n")'
  mutate RED "M7 the canary replace() swaps the tag instead of the host pin" TF \
    "the canary replace() line is missing" \
    'assert s.count(CANARY_LINE) == 1
s = s.replace(CANARY_LINE, CANARY_LINE.replace("\"\x27soleur-inngest-prd\x27\"", "\"\x27inngest-cutover-flip\x27\""))'
  mutate RED "M8 the replace() search text drifts to soleur-inngest-prod while the SQL is unchanged (a no-op replace)" TF \
    "the canary replace() line is missing" \
    'assert s.count(CANARY_LINE) == 1
s = s.replace(CANARY_LINE, CANARY_LINE.replace("\"\x27soleur-inngest-prd\x27\"", "\"\x27soleur-inngest-prod\x27\""))'
  mutate RED "M8b the replace() replacement is the real host soleur-inngest-prd (the canary equals production)" TF \
    "the canary replace() line is missing" \
    'assert s.count(CANARY_LINE) == 1
s = s.replace(CANARY_LINE, CANARY_LINE.replace("\"\x27soleur-inngest-canary-absent\x27\"", "\"\x27soleur-inngest-prd\x27\""))'
  mutate RED "M8c the canary exploration's sql_query points at the production local" TF \
    "the canary exploration's sql_query is not local.inngest_cutover_flip_silent_canary_sql" \
    'i, j = blk(s, "logtail_exploration", "inngest_cutover_flip_silent_canary")
b = s[i:j].replace("local.inngest_cutover_flip_silent_canary_sql", "local.inngest_cutover_flip_silent_sql")
assert b != s[i:j]
s = s[:i] + b + s[j:]'
  mutate RED "M9 the canary alert's check_period drifts from production's" TF \
    "the canary alert block differs from the production alert block" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent_canary", "check_period", "  check_period        = 600")'
  mutate RED "M9b the production alert alone changes an attribute (recovery_period 900 -> 1800)" TF \
    "the canary alert block differs from the production alert block" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent", "recovery_period", "  recovery_period     = 1800")'
  mutate RED "M9c the canary alert alone gains an extra attribute whose key starts with a stripped key (the strip hides nothing real)" TF \
    "the canary alert block differs from the production alert block" \
    's = blk_after(s, "logtail_exploration_alert", "inngest_cutover_flip_silent_canary", "critical_alert", "  name_suffix    = \"x\"\n")'
  mutate RED "M10a the canary alert's operator is lower_than" TF \
    "the canary alert is not threshold / higher_than / 0" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent_canary", "operator", "  operator            = \"lower_than\"")'
  mutate RED "M10b the canary alert's on_missing_data changes (the production half is A4)" TF \
    "the canary alert's on_missing_data is not treat_as_zero" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent_canary", "on_missing_data", "  on_missing_data     = \"keep_last_value\"")'
  mutate RED "M11 one canary -target= line is removed from the MAIN plan" WF \
    "a canary -target= line is missing from the MAIN plan" \
    'old = "              -target=logtail_exploration_alert.inngest_cutover_flip_silent_canary \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "M14 a fifth inngest_cutover_flip_silent* resource header is added (a commented-out decoy counts)" TF \
    "the inngest_cutover_flip_silent* resource header count is 5" \
    's = s + "\n# resource \"logtail_exploration_alert\" \"inngest_cutover_flip_silent_old\" {\n"'
  mutate RED "M14a the canary alert's name changes (the tracker reads and the mirror lookup key on it)" TF \
    "the canary pair is not named soleur-inngest-cutover-flip-silent-canary-prd" \
    's = blk_set(s, "logtail_exploration_alert", "inngest_cutover_flip_silent_canary", "name", "  name           = \"soleur-inngest-cutover-flip-canary-prd\"")'
  mutate RED "M14b a decoy exploration + alert pair under another label carries the canary name" TF \
    "a flip name literal does not appear exactly twice" \
    's = s + "\nresource \"logtail_exploration\" \"inngest_flip_decoy\" {\n  name = \"soleur-inngest-cutover-flip-silent-canary-prd\"\n}\n\nresource \"logtail_exploration_alert\" \"inngest_flip_decoy\" {\n  exploration_id = logtail_exploration.inngest_flip_decoy.id\n  name           = \"soleur-inngest-cutover-flip-silent-canary-prd\"\n}\n"'
  mutate RED "M15 text is inserted before the CANARY warning in the canary incident_cause" TF \
    "the canary incident_cause does not start at byte 0" \
    'old = "incident_cause = \"CANARY, expected to stay open"
assert s.count(old) == 1
s = s.replace(old, "incident_cause = \"Note: CANARY, expected to stay open")'
  mutate RED "M16 the canary host is planted in another file under the infra tree (anti-collision)" INFRA \
    "the canary host 'soleur-inngest-canary-absent' appears outside the replace() line" \
    's = "host_name = \"soleur-inngest-canary-absent\"\n"'
  mutate PASS "M17 the production SQL is reflowed across different line breaks and indentation" TF \
    "" \
    's = sql_replace(s, "\n      AND JSONType(raw, \x27message\x27) = \x27Object\x27", " AND JSONType(raw, \x27message\x27) = \x27Object\x27")
s = sql_replace(s, "AS time, greatest(", "AS time,\n          greatest(")'
  mutate PASS "M18 a comment line inside the production alert block records the old lower_than shape" TF \
    "" \
    's = blk_after(s, "logtail_exploration_alert", "inngest_cutover_flip_silent", "on_missing_data", "  # The old shape was operator = \"lower_than\", value = 1 (#11869, #12726).\n")'
fi

if [ -z "${MUT_SKIP:-}" ] && [ "${MUT_ROWS_RUN:-0}" -ne "$MUT_ROWS_EXPECTED" ]; then
  printf '[FATAL] mutation rows: %s ran, %s expected — a row was added or dropped without updating MUT_ROWS_EXPECTED\n' "${MUT_ROWS_RUN:-0}" "$MUT_ROWS_EXPECTED" >&2; exit 2
fi
# Floor self-reference (accepted residual, #11899): a row-count decrement landing alongside a
# row deletion stays green — PRESENCE_ROWS/MUT_ROWS_EXPECTED are two-write-site constants.
_floor=$((PRESENCE_ROWS))
# The outer run adds the instrument self-test row (outer-only, not a battery row) and the battery.
[ -z "${MUT_SKIP:-}" ] && _floor=$((PRESENCE_ROWS + SELFTEST_ROWS + MUT_ROWS_EXPECTED))
_ran=$((pass + fail))
# Instrument failures exit 2, never 1: the battery grades an inner rc 1 as a CAUGHT mutation.
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== inngest-cutover-flip-silent-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
