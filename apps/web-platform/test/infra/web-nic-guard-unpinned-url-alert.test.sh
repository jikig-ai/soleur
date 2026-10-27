#!/usr/bin/env bash
#
# Drift guard for the "web NIC guard refused to POST to an unpinned ingest URL" Better Stack
# Logs alert (apps/web-platform/infra/betterstack-logs-alerts.tf,
# logtail_exploration_alert.web_nic_guard_unpinned_url) — #9639 F8.
#
# WHAT THE ALERT IS FOR. web-private-nic-guard.sh refuses to send the Better Stack token to a
# destination other than the pinned ingest URL: on its `[nic] unpinned_url:` stderr line the POST
# is withheld AND the liveness beat lapses (a guard that cannot report must not claim health).
# The line is journald-tagged SYSLOG_IDENTIFIER='web-nic-guard' at PRIORITY 6 — NOT a SOLEUR_*
# PRIORITY-2 marker, so monitor_send_failed's predicate cannot see it. Without this alert the
# refusal mode was visible only through a post-merge query (betterstack-log-query.md's decode).
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * The needle is PINNED TO THE EMITTER: the `unpinned_url` literal is read from
#     web-private-nic-guard.sh's own stderr line, so a one-sided reword in the .tf reds here
#     instead of silently disarming the alert (a COORDINATED rename needs a guard edit too).
#   * The predicate is compared WHOLE, whitespace-normalised, against the string built from that
#     needle: SYSLOG_IDENTIFIER='web-nic-guard' AND position(message,'unpinned_url') > 0, and NO
#     host_name conjunct — the guard timer runs on web-1 and is baked for web-2-class hosts, and
#     either can refuse (the #8706 host-conjunct trap in reverse: a threshold-any-row alert).
#   * The paging semantics are monitor_send_failed's (check 60 / query 300 / confirmation 0 /
#     recovery 600, higher_than 0, treat_as_zero, unpaused, email, the free/paid escalation
#     ternary, critical_alert=false).
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist. This guard is the
#     ONLY enforcement of that for logtail resources (terraform-target-parity.test.ts covers
#     terraform_data only).
#   * The runbook exists, the standing-alarms table in betterstack-log-query.md names the alert,
#     and infra-validation.yml runs this guard in a blocking step with the runbook path in
#     pull_request paths.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (created by an apply; the
# reconciler's `logs_alert` arm reads the live world twice daily), nor that a real row reaches
# Better Stack. It compares values one diff can edit together — consistency, not integrity; the
# live-probe step in the .tf comment (betterstack-query.sh positive control) is the anchor
# outside this file.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the
# COPY, and re-runs this guard against it through the UNPINNED_GUARD_* overrides. No tracked
# file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${UNPINNED_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${UNPINNED_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
EM="${UNPINNED_GUARD_EM:-$REPO/apps/web-platform/infra/web-private-nic-guard.sh}"
RB="${UNPINNED_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md}"
LQ="${UNPINNED_GUARD_LQ:-$REPO/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md}"
IV="${UNPINNED_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$EM"; assert_fixture_dir "$RB"; assert_fixture_dir "$LQ"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$EM"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*web_nic_guard_unpinned_url_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^[[:space:]]*SQL$/{exit} f' "$TF")"
# Layout-independent view: every run of whitespace is one space, and no space sits inside a
# parenthesis pair (the resource collapses it the same way).
SQL_1="$(tr '\n' ' ' <<< "$LOCAL_SQL" | sed 's/[[:space:]][[:space:]]*/ /g; s/( /(/g; s/ )/)/g; s/^ //; s/ $//')"
ALERT="$(awk '/^resource "logtail_exploration_alert" "web_nic_guard_unpinned_url" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "web_nic_guard_unpinned_url" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"

# Whole-line assertions anchored at both ends; greps over captured variables read HERE-STRINGS,
# never `printf … | grep -q` (pipefail + early-match SIGPIPE fails a negated check OPEN).
line_in() { grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"; }
top_in() { grep -qE "^  $2[[:space:]]*(#.*)?$" <<< "$1"; }
blk_in() { grep -qE "^    $2[[:space:]]*(#.*)?$" <<< "$1"; }

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "web_nic_guard_unpinned_url_sql: heredoc not found — every predicate row below would be vacuous"

# ── the emitter: the needle is READ, not retyped ──────────────────────────────────────────────
# The refusal line is `echo "[nic] unpinned_url: refusing to send the Better Stack token to an
# unpinned destination — …"` on stderr in the unpinned arm. The needle the alert matches is the
# `unpinned_url` literal INSIDE that line; a reworded emitter (or a reworded .tf) reds below.
EMIT_LINE="$(grep -nE 'unpinned_url' "$EM" | grep 'echo' | head -1)"
EMIT_NEEDLE="$(sed -n 's/.*\[nic\] \([a-z_]*\):.*/\1/p' <<< "$EMIT_LINE" | head -1)"
if [ -n "$EMIT_LINE" ] && [ "$EMIT_NEEDLE" = "unpinned_url" ]; then
  ok "web-private-nic-guard.sh emits exactly the '[nic] unpinned_url:' refusal line; needle captured from it"
else
  no "web-private-nic-guard.sh no longer emits a '[nic] unpinned_url:' refusal line — the alert would silently stop matching (got needle '${EMIT_NEEDLE:-<none>}')"
fi
# The refusal withholds the beat: the unpinned arm must sit inside a SHIP_REFUSED=true branch, or
# a page would mean "alert on a healthy POST". Read the arm ordering: SHIP_REFUSED=true must be
# assigned in the arm that echoes the needle.
if grep -qE 'SHIP_REFUSED=true' < <(grep -nB6 'unpinned_url' "$EM"); then
  ok "the unpinned_url arm withholds the beat (SHIP_REFUSED=true sits in the same arm)"
else
  no "the unpinned_url arm no longer sets SHIP_REFUSED — the alert would page on a beat the guard still sends"
fi

# ── the predicate, compared whole ─────────────────────────────────────────────────────────────
_msg="JSONExtractString(raw, 'message')"
EXPECT_1="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}"
EXPECT_1+=" AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard' AND position(${_msg}, 'unpinned_url') > 0 GROUP BY time"
if [ -n "$EMIT_NEEDLE" ] && [ "$EMIT_NEEDLE" = "unpinned_url" ] && [ "$SQL_1" = "$EXPECT_1" ]; then
  ok "the predicate equals the string built from the emitter's own needle (tag + position, nothing else)"
else
  no "the predicate is not the expected conjunct pair built from the emitter's needle"
fi
grep -qF "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard'" <<< "$SQL_1" \
  && ok "the tag conjunct: SYSLOG_IDENTIFIER = 'web-nic-guard'" \
  || no "the SYSLOG_IDENTIFIER='web-nic-guard' conjunct is missing or altered"
grep -qF "position(${_msg}, 'unpinned_url') > 0" <<< "$SQL_1" \
  && ok "the needle conjunct: position(message, 'unpinned_url') > 0 (a row merely absent the marker cannot alert)" \
  || no "the unpinned_url needle conjunct is missing or altered"
if grep -qiE '(^|[^A-Za-z_])NOT([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  no "the predicate carries a negation — an unreadable row would read as a refusal"
else
  ok "the predicate has no negation"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would blind the OTHER web host's refusals (the #8706 trap in reverse)" \
  || ok "no host_name conjunct: a refusal on web-1 or web-2 alerts"

EXPL_QRY="$(awk '/^  query \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
EXPL_VAR="$(awk '/^  variable \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
blk_in "$EXPL_QRY" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.web_nic_guard_unpinned_url_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.web_nic_guard_unpinned_url_sql as its sql_query"
blk_in "$EXPL_VAR" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"
[ "$(grep -cE '^  query \{' <<< "$EXPL")" -eq 1 ] && [ "$(grep -cE '^  variable \{' <<< "$EXPL")" -eq 1 ] \
  && blk_in "$EXPL_QRY" 'source_variable[[:space:]]*=[[:space:]]*"source"' \
  && blk_in "$EXPL_QRY" 'query_type[[:space:]]*=[[:space:]]*"sql_expression"' \
  && blk_in "$EXPL_VAR" 'name[[:space:]]*=[[:space:]]*"source"' \
  && ok "the exploration has exactly one query and one variable block, wired source_variable=source -> variable source" \
  || no "the exploration's query/variable wiring is not exactly one sql_expression query reading variable \"source\""

[ -n "$ALERT" ] && ok "logtail_exploration_alert.web_nic_guard_unpinned_url exists (exact header)" \
  || no "logtail_exploration_alert.web_nic_guard_unpinned_url is missing"
top_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.web_nic_guard_unpinned_url\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.web_nic_guard_unpinned_url.id"
top_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-web-nic-guard-unpinned-url-prd"' \
  && top_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-web-nic-guard-unpinned-url-prd"' \
  && ok "both are named soleur-web-nic-guard-unpinned-url-prd" \
  || no "the exploration/alert name drifted from soleur-web-nic-guard-unpinned-url-prd"
top_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && top_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && top_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE unpinned_url row alerts" \
  || no "the alert is not threshold/higher_than/0 — a single refusal row would not alert"
top_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
top_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
top_in "$ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && top_in "$ALERT" 'push[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'call[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'sms[[:space:]]*=[[:space:]]*false' \
  && top_in "$ALERT" 'critical_alert[[:space:]]*=[[:space:]]*false' \
  && ok "email = true, push/call/sms/critical_alert = false (the free-tier sibling channel set)" \
  || no "the channel set drifted from the sibling shape (email-only, critical_alert=false)"
top_in "$ALERT" 'confirmation_period[[:space:]]*=[[:space:]]*0' \
  && top_in "$ALERT" 'check_period[[:space:]]*=[[:space:]]*60' \
  && top_in "$ALERT" 'query_period[[:space:]]*=[[:space:]]*300' \
  && top_in "$ALERT" 'recovery_period[[:space:]]*=[[:space:]]*600' \
  && ok "check 60 / query 300 / recovery 600 with no confirmation delay (monitor_send_failed's combination)" \
  || no "the paging windows drifted from check 60 / query 300 / confirmation 0 / recovery 600"
if grep -qE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)\b' <<< "$ALERT"$'\n'"$EXPL"; then
  no "the alert or exploration carries count/for_each/lifecycle/ignore_changes — the resource could silently not exist or never reconcile"
else
  ok "no count/for_each/lifecycle/ignore_changes on the alert or exploration (the resource exists and reconciles)"
fi
line_in "$ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "the escalation target is the free/paid ternary every sibling uses (ADR-218)" \
  || no "the escalation_target drifted from the sibling ternary"
# The incident text must not claim resolution means a fix: the alert auto-resolves after quiet minutes.
grep -qE '^  incident_cause[[:space:]]*=.*does NOT mean' <<< "$ALERT" \
  && ok "the incident text says resolution does NOT mean the cause was fixed" \
  || no "the incident text no longer warns that auto-resolution is not a fix"

RB_URL_RE='^[[:space:]]*web_nic_guard_unpinned_url_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert\.md"'
grep -qE '^  incident_cause[[:space:]]*=.*[Rr]unbook: \$\{local\.web_nic_guard_unpinned_url_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && blk_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.web_nic_guard_unpinned_url_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the alert's runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable web-nic-guard-unpinned-url runbook URL"

[ -f "$RB" ] \
  && ok "the runbook file exists (knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md)" \
  || no "the runbook file is missing"
[ -f "$RB" ] && grep -qF 'unpinned_url' "$RB" && grep -qF 'web-nic-guard' "$RB" \
  && ok "the runbook names the marker and the SYSLOG_IDENTIFIER an operator reads" \
  || no "the runbook no longer names unpinned_url / web-nic-guard"
grep -qF 'logtail_exploration_alert.web_nic_guard_unpinned_url' "$LQ" \
  && ok "betterstack-log-query.md's standing-alarms table names the alert" \
  || no "the standing-alarms row in betterstack-log-query.md is missing"

grep -qE '^[[:space:]]*-target=logtail_exploration\.web_nic_guard_unpinned_url \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.web_nic_guard_unpinned_url \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"
# Reachability: -target= lines only matter if a merge to main runs this plan at all.
WF_PUSH="$(awk '/^on:$/{o=1;next} o&&/^[a-z]/{exit} o&&/^  push:$/{p=1;next} o&&p&&/^  [a-z_]+:/{exit} p{print}' "$WF")"
if grep -qxF '    branches: [main]' <<< "$WF_PUSH" && grep -qxF '      - "apps/web-platform/infra/**"' <<< "$WF_PUSH" \
   && [ -z "$(grep -E '^      - "!' <<< "$WF_PUSH" | grep -vxF -e '      - "!apps/web-platform/infra/rung2-rehearsal/**"' -e '      - "!apps/web-platform/infra/git-data-root-key/**"' -e '      - "!apps/web-platform/infra/inngest-provision-rehearsal/**"' || true)" ] \
   && [ "$(grep -cxF "      (github.event_name == 'push' || inputs.apply_target == 'manual-rerun')" "$WF")" -eq 1 ]; then
  ok "apply-web-platform-infra.yml's push block runs on main for apps/web-platform/infra/** with no path negation beyond the three known sub-roots, and the apply job runs on push (the alert is created by the merge, not by hand)"
else
  no "apply-web-platform-infra.yml no longer triggers the apply on push to main for apps/web-platform/infra/** (branch, path, a negation of the alert's file, or the apply job's push clause changed) — the alert would not be created on merge"
fi

# This guard only runs in CI if infra-validation.yml runs it, and re-runs on a runbook edit or an
# edit of the apply workflow (both read from the pull_request block, not anywhere in the file).
IV_PR="$(awk '/^  pull_request:$/{p=1;next} p&&/^  [a-z_]+:/{exit} p{print}' "$IV")"
IV_JOB="$(awk '/^  deploy-script-tests-fixed:$/{f=1;print;next} f&&/^  [A-Za-z0-9_-]+:$/{exit} f{print}' "$IV")"
IV_STEP="$(awk '/^      - name: Run web NIC guard unpinned ingest URL refusal alert drift guard \(#9639\)$/{f=1;print;next} f&&/^      - name:/{exit} f{print}' <<< "$IV_JOB")"
IV_HDR="$(awk '/^    steps:$/{exit} {print}' <<< "$IV_JOB")"
if [ "$(grep -cxF '      - "knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '      - ".github/workflows/apply-web-platform-infra.yml"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh' <<< "$IV_STEP")" -eq 1 ] \
   && ! grep -qE '^        (if|continue-on-error):' <<< "$IV_STEP" \
   && [ "$(grep -cxF "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" <<< "$IV_HDR")" -eq 1 ] \
   && ! grep -qE '^    continue-on-error:' <<< "$IV_HDR"; then
  ok "infra-validation.yml's pull_request paths list the runbook and the apply workflow, and deploy-script-tests-fixed runs this guard in an unconditional, blocking step"
else
  no "infra-validation.yml no longer wires this guard: runbook or apply-workflow path missing from pull_request paths, the step missing/conditional/non-blocking, or its job conditional/non-blocking"
fi

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching UNPINNED_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=29
MUT_ROWS_EXPECTED=8
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t unpinnedalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|EM|RB|LQ|IV> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      EM) src="$EM"; copy="$MUT_DIR/web-private-nic-guard.sh" ;;
      RB) src="$RB"; copy="$MUT_DIR/web-nic-guard-unpinned-url-alert.md" ;;
      LQ) src="$LQ"; copy="$MUT_DIR/betterstack-log-query.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
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
    i = s.index("  web_nic_guard_unpinned_url_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
exec(os.environ["MUT_PROG"])
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "UNPINNED_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
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

  # A1 — the tag conjunct is dropped: unpinned_url rows under ANY identifier could alert.
  mutate RED "A1 the SYSLOG_IDENTIFIER conjunct is dropped (rows from any identifier could alert)" TF \
    "the SYSLOG_IDENTIFIER='web-nic-guard' conjunct is missing" \
    's = sql_replace(s, "JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27web-nic-guard\x27\n      AND ", "")'
  # A2 — the needle is reworded in the .tf while the emitter's line is untouched.
  mutate RED "A2 the needle is reworded in the .tf only (the alert would silently disarm)" TF \
    "the unpinned_url needle conjunct is missing" \
    's = sql_replace(s, "\x27unpinned_url\x27", "\x27unpinned_dest\x27")'
  # A3 — a -target= line is dropped from the apply allowlist.
  mutate RED "A3 the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration_alert.web_nic_guard_unpinned_url \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # A4 — on_missing_data is no longer treat_as_zero: an open incident can never observe recovery.
  mutate RED "A4 on_missing_data is no longer treat_as_zero" TF \
    "on_missing_data is not treat_as_zero" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"web_nic_guard_unpinned_url\" \{.*?\n  on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  # A5 — the guard's OWN dispatch: the run: step goes non-blocking in infra-validation.yml.
  mutate RED "A5 the guard step becomes non-blocking (continue-on-error)" IV \
    "infra-validation.yml no longer wires this guard" \
    'old = "        run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)'
  # A6 — the alert's exploration_id is repointed to another exploration.
  mutate RED "A6 the alert's exploration_id is repointed (identity row)" TF \
    "the alert's exploration_id is not" \
    'old = "  exploration_id = logtail_exploration.web_nic_guard_unpinned_url.id"
assert s.count(old) == 1
s = s.replace(old, "  exploration_id = logtail_exploration.monitor_send_failed.id")'
  # A7 — a host_name conjunct is added: the OTHER web host's refusals go silent.
  mutate RED "A7 a host_name conjunct is added (web-2's refusals would go silent)" TF \
    "the predicate carries a host_name conjunct" \
    's = sql_replace(s, "\n    GROUP BY time", "\n      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time")'
  # Must-PASS: layout is not part of the contract (the resource flattens the predicate with
  # replace(…, "/\\s+/", " ")).
  mutate PASS "A8 every heredoc line is re-indented far deeper (layout is not part of the contract)" TF \
    "" \
    'import re
i = s.index("  web_nic_guard_unpinned_url_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
head, rest = s[i:j].split("\n", 1)
s = s[:i] + head + "\n" + re.sub(r"(?m)^\s+", "                    ", rest) + s[j:]'
fi

if [ -z "${MUT_SKIP:-}" ] && [ "${MUT_ROWS_RUN:-0}" -ne "$MUT_ROWS_EXPECTED" ]; then
  printf '[FATAL] mutation rows: %s ran, %s expected — a row was added or dropped without updating MUT_ROWS_EXPECTED\n' "${MUT_ROWS_RUN:-0}" "$MUT_ROWS_EXPECTED" >&2; exit 2
fi
_floor=$((PRESENCE_ROWS))
[ -z "${MUT_SKIP:-}" ] && _floor=$((PRESENCE_ROWS + MUT_ROWS_EXPECTED))
_ran=$((pass + fail))
# Instrument failures exit 2, never 1: the battery grades an inner rc 1 as a CAUGHT mutation.
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== web-nic-guard-unpinned-url-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
