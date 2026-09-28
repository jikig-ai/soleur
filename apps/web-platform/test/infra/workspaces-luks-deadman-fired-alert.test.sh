#!/usr/bin/env bash
#
# Drift guard for the "#9045 the workspaces-LUKS dead-man FIRED" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.workspaces_luks_deadman_fired).
# Plan: knowledge-base/project/plans/2026-09-28-fix-luks-deadman-host-canary-disarm-and-snapshot-411798619-release-plan.md
# (Phase 2 step 6, §Test Scenarios → Other suites → Alert).
#
# WHAT THE ALERT IS FOR. The cutover's dead-man (a transient systemd timer armed by
# workspaces-cutover.sh arm_dead_man) reverts web-1 to the plaintext volume when it fires. A fire is
# unattended by construction: the SIGKILL residual, or any future path that leaves it armed. On
# 2026-07-20 a fire remounted the plaintext over a healthy LUKS mount and nothing paged for ~6 h
# (#6812). The fire command's FIRST act is a `logger -t luks-monitor` marker carrying
# `op=workspaces-luks-deadman result=fired`; this alert pages on that row.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The needle is the literal the fire command logs, read from workspaces-cutover.sh itself, so a
#     reworded marker reds here instead of silencing the page.
#   * The predicate carries the tag (SYSLOG_IDENTIFIER='luks-monitor'), the host
#     (host_name='soleur-web-platform' — web-2 ships to the same source) and the result=fired
#     conjunct, ANDed, with no OR and no negation. Dropping any one of them reds (mutation rows).
#   * The paging semantics are monitor_send_failed's (ADR-218): threshold, higher_than 0,
#     treat_as_zero, unpaused, email, and the free/paid escalation ternary.
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist (#5566: an untargeted
#     resource is never applied and never exists).
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (the reconciler's `logs_alert`
# arm, plugins/soleur/lib/heartbeat-live-reconcile.ts, reads the world twice daily), nor that a real
# fire's row reaches Better Stack (Vector allowlists the luks-monitor tag; the nightly
# `OK: /mnt/data is LUKS-backed` row proves that path live).
#
# Mutation rows live at the bottom. Each one COPIES a source file into a scratch dir, mutates the
# COPY, and re-runs this guard against it through the DEADMAN_GUARD_* overrides. No tracked file is
# ever written (the sibling inngest-luks-wrong-volume-alert.test.sh records why in-place mutation
# was abandoned).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${DEADMAN_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${DEADMAN_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CUT="${DEADMAN_GUARD_CUT:-$REPO/apps/web-platform/infra/workspaces-cutover.sh}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — and mutate_red() below writes to $TF on every row.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CUT"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$CUT"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

NEEDLE='op=workspaces-luks-deadman result=fired'
MARKER='SOLEUR_WORKSPACES_LUKS_DEADMAN'

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*workspaces_luks_deadman_fired_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
# The alert and exploration blocks, from their exact header to the first column-0 "}".
ALERT="$(awk '/^resource "logtail_exploration_alert" "workspaces_luks_deadman_fired" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "workspaces_luks_deadman_fired" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"

# Whole-line assertions anchored at both ends: a bare substring grep is satisfied by the same text
# inside a comment, or with a suffix that inverts it (`paused = false || true`).
# Every grep reads a HERE-STRING, never `printf … | grep -q`: under pipefail, grep -q exiting on its
# first match can SIGPIPE the writer and fail the pipeline, which fails a negated check OPEN.
line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
sql_has() {  # sql_has <fixed conjunct text, one line of the heredoc>
  grep -qxF -- "      AND $1" <<< "$LOCAL_SQL"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "workspaces_luks_deadman_fired_sql: heredoc not found — every predicate row below would be vacuous"

_head="$(head -3 <<< "$LOCAL_SQL" | tr -s ' ' | sed 's/^ //' | paste -sd' ')"
grep -qxF 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}' <<< "$_head" \
  && ok "the head is the per-bucket count shape monitor_send_failed uses (ADR-218)" \
  || no "the predicate head is not SELECT {{time}} … count(*) … WHERE time BETWEEN {{start_time}} AND {{end_time}}"

sql_has "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'luks-monitor' (the fire command's logger -t)" \
  || no "the SYSLOG_IDENTIFIER='luks-monitor' conjunct is missing or altered"

sql_has "JSONExtractString(raw, 'host_name') = 'soleur-web-platform'" \
  && ok "the host conjunct: host_name = 'soleur-web-platform' (web-2 ships to the same source)" \
  || no "the host_name='soleur-web-platform' conjunct is missing or altered"

sql_has "position(JSONExtractString(raw, 'message'), '$NEEDLE') > 0" \
  && ok "the result=fired conjunct: the message contains '$NEEDLE'" \
  || no "the '$NEEDLE' conjunct is missing or altered"

sql_has "startsWith(JSONExtractString(raw, 'message'), '$MARKER ')" \
  && ok "the marker anchor: the message STARTS with the dead-man marker (a row merely quoting it cannot page)" \
  || no "the startsWith '$MARKER ' anchor is missing"

# Exactly the head, four AND conjuncts and GROUP BY: no OR, no negation, no fifth clause that could
# narrow the rule to nothing.
_body="$(sed -n '4,$p' <<< "$LOCAL_SQL")"
if [ "$(grep -c '^      AND ' <<< "$_body")" -eq 4 ] \
   && [ "$(grep -vc '^      AND ' <<< "$_body")" -eq 1 ] \
   && [ "$(tail -1 <<< "$_body")" = '    GROUP BY time' ] \
   && ! grep -qiE '(^|[^A-Za-z_])(OR|NOT)([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "the predicate is exactly four ANDed conjuncts and GROUP BY time (no OR, no negation)"
else
  no "the predicate carries an OR, a negation or an extra clause"
fi

# The needle must be what the fire command actually logs: the systemd-run inline command's first
# logger call, on the luks-monitor tag. Read ONLY from arm_dead_man's body, full-line comments
# dropped, and only a line that STARTS with the /bin/sh -c argument: the same text in a comment, in
# another function or after other code on a line is not the fire command.
FIRE_PFX="/bin/sh -c \"logger -t \${LUKS_LOG_TAG} -- '$MARKER feature=workspaces-luks $NEEDLE "
FIRE_LINE="$(awk -v pfx="$FIRE_PFX" '
  /^arm_dead_man\(\)[[:space:]]*\{/ { f = 1; next }
  f && /^\}/ { exit }
  f { l = $0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next; if (index(l, pfx) == 1) { print l; exit } }' "$CUT")"
[ -n "$FIRE_LINE" ] \
  && ok "workspaces-cutover.sh's fire command logs '$MARKER … $NEEDLE ' first, on \${LUKS_LOG_TAG}" \
  || no "the fire command no longer logs '$MARKER … $NEEDLE ' as its first act — the alert would never page"
grep -qE '^LUKS_LOG_TAG="\$\{WORKSPACES_LUKS_LOG_TAG:-luks-monitor\}"' "$CUT" \
  && ok "LUKS_LOG_TAG defaults to luks-monitor (the tag the predicate matches, Vector-allowlisted)" \
  || no "LUKS_LOG_TAG no longer defaults to luks-monitor"

line_in "$EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.workspaces_luks_deadman_fired_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.workspaces_luks_deadman_fired_sql as its sql_query"
line_in "$EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

[ -n "$ALERT" ] && ok "logtail_exploration_alert.workspaces_luks_deadman_fired exists (exact header)" \
  || no "logtail_exploration_alert.workspaces_luks_deadman_fired is missing"
line_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.workspaces_luks_deadman_fired\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.workspaces_luks_deadman_fired.id"
line_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-workspaces-luks-deadman-fired-prd"' \
  && line_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-workspaces-luks-deadman-fired-prd"' \
  && ok "both are named soleur-workspaces-luks-deadman-fired-prd" \
  || no "the exploration/alert name drifted from soleur-workspaces-luks-deadman-fired-prd"
line_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && line_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE fired row pages (monitor_send_failed's semantics)" \
  || no "the alert is not threshold/higher_than/0 — a single fire would not page"
line_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
line_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
line_in "$ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && ok "email = true (the free-tier paging surface)" \
  || no "email is not true"
QP="$(grep -oE '^[[:space:]]*query_period[[:space:]]*=[[:space:]]*[0-9]+' <<< "$ALERT" | grep -oE '[0-9]+$')"
CK="$(grep -oE '^[[:space:]]*check_period[[:space:]]*=[[:space:]]*[0-9]+' <<< "$ALERT" | grep -oE '[0-9]+$')"
if [ -n "$QP" ] && [ -n "$CK" ] && [ "$CK" -ge 1 ] && [ "$QP" -ge "$CK" ] && [ "$CK" -le 300 ]; then
  ok "evaluated at least every 5 min (check_period ${CK}s) over a window that covers it (query_period ${QP}s)"
else
  no "the evaluation cadence is too slow or the window misses buckets (check_period=${CK:-?} query_period=${QP:-?})"
fi
line_in "$ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"
grep -qF 'Runbook: ${local.workspaces_luks_deadman_runbook_url}' <<< "$ALERT" \
  && line_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.workspaces_luks_deadman_runbook_url' \
  && grep -qE '^[[:space:]]*workspaces_luks_deadman_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604\.md[#"]' "$TF" \
  && ok "incident_cause and metadata.runbook carry the cutover runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable cutover-runbook URL"

grep -qE '^[[:space:]]*-target=logtail_exploration\.workspaces_luks_deadman_fired \\$' "$WF" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.workspaces_luks_deadman_fired \\$' "$WF" \
  && ok "both resources are in an apply allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching DEADMAN_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=22
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t deadmanalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|CUT> <python-program-on-s>
    local want="$1" label="$2" which="$3" prog="$4" src copy rc=0
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CUT) src="$CUT"; copy="$MUT_DIR/workspaces-cutover.sh" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def dm_replace(s, old, new):
    # The first occurrence AFTER the dead-man local's opening line: the luks-monitor host-timer
    # predicate earlier in the file carries identical tag/host conjuncts.
    i = s.index("  workspaces_luks_deadman_fired_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    case "$which" in
      TF)  DEADMAN_GUARD_TF="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      WF)  DEADMAN_GUARD_WF="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      CUT) DEADMAN_GUARD_CUT="$copy" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
    esac
    # Only rc=1 (an assertion went red) is a caught mutation; rc>=2 is this guard's own FATAL class.
    case "$want:$rc" in
      RED:1)  ok "mutation RED: $label" ;;
      RED:0)  no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      PASS:0) ok "must-PASS edit stays green: $label" ;;
      PASS:*) no "must-PASS edit went red (inner rc=$rc): $label — the guard over-fits" ;;
      *)      no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  mutate RED "the tag conjunct is dropped" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n", "")'
  mutate RED "the host conjunct is dropped (web-2 rows would page)" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n", "")'
  mutate RED "the result=fired conjunct is dropped (every dead-man row would page)" TF \
    'old = "      AND position(JSONExtractString(raw, \x27message\x27), \x27op=workspaces-luks-deadman result=fired\x27) > 0\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "the needle is reworded to result=ok (pages on the recovery, never on the fire)" TF \
    'old = "\x27op=workspaces-luks-deadman result=fired\x27"
assert s.count(old) == 1
s = s.replace(old, "\x27op=workspaces-luks-deadman result=ok\x27")'
  mutate RED "a conjunct is OR-joined (the predicate widens to every luks-monitor row)" TF \
    's = dm_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n", "      OR JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n")'
  mutate RED "the fire command's marker is reworded in workspaces-cutover.sh only" CUT \
    'old = "op=workspaces-luks-deadman result=fired reason=timer_elapsed"
assert s.count(old) == 1
s = s.replace(old, "op=workspaces-luks-deadman result=engaged reason=timer_elapsed")'
  mutate RED "the alert is paused" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"workspaces_luks_deadman_fired\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  mutate RED "on_missing_data is no longer treat_as_zero" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"workspaces_luks_deadman_fired\" \{.*?on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  mutate RED "the operator flips to lower_than (silence pages, a fire does not)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"workspaces_luks_deadman_fired\" \{.*?operator\s*=\s*)\"higher_than\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"lower_than\"" + s[m.end():]'
  mutate RED "the alert watches another exploration" TF \
    'old = "exploration_id = logtail_exploration.workspaces_luks_deadman_fired.id"
assert s.count(old) == 1
s = s.replace(old, "exploration_id = logtail_exploration.monitor_send_failed.id")'
  mutate RED "the alert is dropped from the apply allowlist" WF \
    'old = "            -target=logtail_exploration_alert.workspaces_luks_deadman_fired \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "the marker anchor loses its trailing space (SOLEUR_WORKSPACES_LUKS_DEADMAN_X rows would page)" TF \
    's = dm_replace(s, "\x27SOLEUR_WORKSPACES_LUKS_DEADMAN \x27)", "\x27SOLEUR_WORKSPACES_LUKS_DEADMAN\x27)")'
  mutate RED "the fire line survives only as a COMMENT inside arm_dead_man (the real one reworded)" CUT \
    'import re
m = re.search(r"(?m)^([ \t]*)(/bin/sh -c \"logger -t \$\{LUKS_LOG_TAG\} -- \x27SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fired reason=timer_elapsed\x27;.*)$", s)
assert m and s.count("result=fired reason=timer_elapsed") == 1
real = m.group(0)
s = s.replace(real, m.group(1) + "# " + m.group(2) + "\n" + real.replace("result=fired reason=timer_elapsed", "result=engaged reason=timer_elapsed"), 1)'
  mutate RED "the fire text is quoted OUTSIDE arm_dead_man (the real one reworded)" CUT \
    'old = "result=fired reason=timer_elapsed"
assert s.count(old) == 1
s = s.replace(old, "result=engaged reason=timer_elapsed") + "\n_fire_doc() {\n    /bin/sh -c \"logger -t ${LUKS_LOG_TAG} -- \x27SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fired reason=timer_elapsed\x27\"\n}\n"'
  mutate PASS "the four conjuncts reordered" TF \
    'a = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27luks-monitor\x27\n"
b = "      AND position(JSONExtractString(raw, \x27message\x27), \x27op=workspaces-luks-deadman result=fired\x27) > 0\n"
assert s.count(b) == 1
s = dm_replace(s, a, "@@A@@").replace(b, a).replace("@@A@@", b)'
fi

# 37 = 22 presence rows + 15 mutation rows. The MUT_SKIP floor is exactly the presence-row count;
# the instrument control above is what catches a floor that drifts past them.
_floor=37
[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS
_ran=$((pass + fail))
# Instrument failures exit 2, never 1: the battery grades an inner rc 1 as a CAUGHT mutation.
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== workspaces-luks-deadman-fired-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
