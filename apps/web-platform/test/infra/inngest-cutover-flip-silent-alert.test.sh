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
#   * The predicate is compared WHOLE, whitespace-normalised: tag AND the pinned production host AND
#     `JSONType(raw,'message') = 'Object'`. The last conjunct is the discriminator (CTO ruling,
#     2026-11-02): the flip rows carry an OBJECT-typed `message`, the doppler error lines under the same
#     tag carry a STRING one, so a bare tag count stays green while the unit fails.
#   * The window is checked against the emitter: query_period must hold at least three throttle
#     intervals, or one late row would page.
#   * The paging semantics (lower_than 1, check 300, query 900, confirmation 0, recovery 900,
#     treat_as_zero, email only, critical_alert=false, the free/paid escalation ternary).
#   * The alert is PAUSED (`paused = true`) with the `#11869` pointer on the line above it (false
#     positive: the evaluator reads 0 for a window the query API shows holding rows). The pause is
#     pinned so it cannot be flipped back, or lose its issue pointer, without this guard going red;
#     re-arming means changing that row in the same diff as the measured evaluator fix.
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist (terraform-target-parity
#     covers terraform_data only, so this guard is the only enforcement for logtail resources).
#   * The incident text says the alert is EXPECTED during an owner-authorized replace (no suppression
#     is built; it stays open on #11820), the runbook section names the alert, the standing-alarms table
#     names it, and infra-validation.yml runs this guard in a blocking step.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is paused IN PRODUCTION (set by the merge apply), why the
# evaluator reads 0 (#11869; `JSONType` is the first use in the file but the sibling `egress_gw_probe_silent`
# showed the same stuck-at-0 without it, until #12180 inverted it to a missing-host count), nor that a real row reaches Better Stack. It compares values one diff can edit together — consistency, not
# integrity.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$EM"; assert_fixture_dir "$RB"; assert_fixture_dir "$LQ"; assert_fixture_dir "$IV"; assert_fixture_dir "$BS"

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
EXPECT_SQL="SELECT toDateTime({{end_time}}) AS time, count(*) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}}"
EXPECT_SQL+=" AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') IN ('${EMIT_TAG}')"
EXPECT_SQL+=" AND JSONExtractString(raw, 'host_name') = 'soleur-inngest-prd'"
EXPECT_SQL+=" AND JSONType(raw, 'message') = 'Object'"
if [ -n "$EMIT_TAG" ] && [ "$SQL_1" = "$EXPECT_SQL" ]; then
  ok "the predicate equals the string built from the emitter's own tag (tag + pinned host + object-typed message, one aggregate, dt column)"
else
  no "the predicate is not the expected conjunct set built from the emitter's tag"
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
top_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && top_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"lower_than"' \
  && top_in "$ALERT" 'value[[:space:]]*=[[:space:]]*1' \
  && ok "threshold, lower_than 1: a window with ZERO liveness rows alerts" \
  || no "the alert is not threshold/lower_than/1 — a silent window would not alert"
top_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero, so a fully dark window reads 0 and an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
top_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*true' \
  && grep -qE '^  # Paused pending #11869' <<< "$ALERT" \
  && grep -qF 'PAUSED PENDING #11869' "$TF" \
  && ok "paused = true on its own line, with the #11869 pointer in the alert block and the explanation above the locals (the false-positive pause)" \
  || no "the alert is not paused (paused = true on its own line with the #11869 pointer) - re-arm only with the measured evaluator fix in the same diff"
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

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|IV|EM|RB|LQ|BS> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      EM) src="$EM"; copy="$MUT_DIR/inngest-cutover-flip.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/inngest-server.md" ;;
      LQ) src="$LQ"; copy="$MUT_DIR/betterstack-log-query.md" ;;
      BS) src="$BS"; copy="$MUT_DIR/inngest-bootstrap.sh" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    MUT_PROG="$prog" python3 - "$copy" <<'PY' || { no "mutation '$label' did not land (anchor drifted)"; MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1)); return 0; }
import os, sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry
    # identical conjuncts earlier on.
    i = s.index("  inngest_cutover_flip_silent_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
exec(os.environ["MUT_PROG"])
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "FLIPSILENT_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
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
  # A13 - the pause is flipped back to false without the measured evaluator fix: the false positive returns.
  mutate RED "A13 paused flips back to false (the #11869 false positive would re-open)" TF \
    "the alert is not paused" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"inngest_cutover_flip_silent\" \{.*?\n  paused\s*=\s*)true", s, re.S)
assert m
s = s[:m.end(1)] + "false" + s[m.end():]'
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
fi

if [ -z "${MUT_SKIP:-}" ] && [ "${MUT_ROWS_RUN:-0}" -ne "$MUT_ROWS_EXPECTED" ]; then
  printf '[FATAL] mutation rows: %s ran, %s expected — a row was added or dropped without updating MUT_ROWS_EXPECTED\n' "${MUT_ROWS_RUN:-0}" "$MUT_ROWS_EXPECTED" >&2; exit 2
fi
# Floor self-reference (accepted residual, #11899): a row-count decrement landing alongside a
# row deletion stays green — PRESENCE_ROWS/MUT_ROWS_EXPECTED are two-write-site constants.
_floor=$((PRESENCE_ROWS))
[ -z "${MUT_SKIP:-}" ] && _floor=$((PRESENCE_ROWS + MUT_ROWS_EXPECTED))
_ran=$((pass + fail))
# Instrument failures exit 2, never 1: the battery grades an inner rc 1 as a CAUGHT mutation.
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== inngest-cutover-flip-silent-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
