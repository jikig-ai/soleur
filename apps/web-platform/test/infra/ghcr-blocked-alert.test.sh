#!/usr/bin/env bash
#
# Drift guard for the "hosts-file GHCR deny was lost" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.ghcr_hostsfile_deny_lost).
# Plan: knowledge-base/project/plans/2026-10-03-chore-zot-adr096-wrapup-delivery-resolver-alert-adr190-plan.md (PR-2, #9391)
#
# WHAT THE ALERT IS FOR. Every host carries a hosts-file deny that sinkholes ghcr.io to 0.0.0.0 (an accident
# guard on name resolution, not an egress control; deploy pulls are zot-only). Two emitters report whether it
# is in force: a web host's ci-deploy writes `GHCR_DENY ghcr_blocked=<1|0|unknown>` to journald on every
# validated ci-deploy.sh invocation, and the registry host's SOLEUR_ZOT_DISK heartbeat carries
# ` ghcr_blocked=<1|0|unknown> ` every five minutes. Value 0 means ghcr.io resolves to a real address, i.e.
# the deny regressed. `unknown` (ghcr.io does not resolve) is deliberately NOT an alert condition: it is not
# the deny regressing, and a blind probe is silence rather than health.
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * Both needles are PINNED TO THE EMITTERS (ci-deploy.sh's logger line, cloud-init-registry.yml's heartbeat
#     line): each selector re-finds its emitter line by shape and the alert's literals are compared with what
#     it captures, so a one-sided reword reds here instead of silently disarming the alert. A COORDINATED
#     rename (emitter and alert together) needs a guard edit too: the selectors carry the literals.
#   * The predicate is compared WHOLE, whitespace-normalised, against the string built from those needles:
#     two arms (a web-host arm and a registry arm), value 0 only, exact equality on the web arm, head-scoping
#     on the registry arm (the field must sit before ` zot_last_err=`, whose free text is attacker-influenced),
#     and no host_name conjunct (web-1, web-2 and the pre-rename web-1 name carry the web arm's rows; the
#     registry rows carry no host_name at all). Layout is free (whitespace and line breaks); token ORDER is
#     not: swapping the two arms is a predicate edit and is reviewed as one.
#   * The paging semantics are the measured registry_store_not_luks combination (check 300 / query 900 /
#     recovery 1800, higher_than 0, treat_as_zero, unpaused, email, the free/paid escalation ternary).
#   * Both resources are in the apply workflow's MAIN plan -target= allowlist. This guard is the ONLY
#     enforcement of that for logtail resources: terraform-target-parity.test.ts covers terraform_data only.
#   * The runbook anchor in the alert's URL resolves to a real heading in cron-egress-blocked.md, and that
#     runbook is in infra-validation.yml's pull_request paths (a docs-only heading rename runs this guard).
#   * The DIRECTION of each emitter's value-0 branch (not only their text; the unknown/else branches are pinned
#     behaviourally by web-ghcr-deny.test.sh), the registry cadence line and POST shape, and the apply
#     workflow's push trigger: the page depends on what the emitters MEAN, when they run and whether the
#     alert is created, not only on the literals.
#
# WHAT THIS FILE DOES NOT PROVE: that the alert is armed IN PRODUCTION (it is created by an apply of
# apply-web-platform-infra.yml; the reconciler's `logs_alert` arm reads the live world twice daily), that the
# Vector allowlist ships the ci-deploy tag (journald-config.test.sh pins that), nor that a real row reaches
# Better Stack. It
# compares values that one diff can edit together, so it proves consistency, not integrity; the live-probe
# counts in ADR-218's amendment are the anchor outside this file and the .tf.
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch dir, mutates the COPY, and
# re-runs this guard against it through the GHCR_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${GHCR_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${GHCR_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
CI="${GHCR_GUARD_CI:-$REPO/apps/web-platform/infra/ci-deploy.sh}"
CR="${GHCR_GUARD_CR:-$REPO/apps/web-platform/infra/cloud-init-registry.yml}"
RB="${GHCR_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md}"
IV="${GHCR_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$CI"; assert_fixture_dir "$CR"; assert_fixture_dir "$RB"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$CI" "$CR" "$RB" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate heredoc, from the FIRST UNCOMMENTED opening line to its own terminator.
LOCAL_SQL="$(awk '/^[[:space:]]*ghcr_hostsfile_deny_lost_sql[[:space:]]*=[[:space:]]*<<-SQL/{f=1;next} f&&/^[[:space:]]*SQL$/{exit} f' "$TF")"
# Layout-independent view: every run of whitespace is one space, and no space sits inside a parenthesis pair,
# so re-wrapping the heredoc (the resource collapses it the same way) is not a contract change.
SQL_1="$(tr '\n' ' ' <<< "$LOCAL_SQL" | sed 's/[[:space:]][[:space:]]*/ /g; s/( /(/g; s/ )/)/g; s/^ //; s/ $//')"
# The alert and exploration blocks, from their exact header to the first column-0 "}".
ALERT="$(awk '/^resource "logtail_exploration_alert" "ghcr_hostsfile_deny_lost" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
EXPL="$(awk '/^resource "logtail_exploration" "ghcr_hostsfile_deny_lost" \{/{f=1} f{print} f&&/^\}/{exit}' "$TF")"
# The push-triggered MAIN plan: from the first `terraform plan -no-color` to its `rc=$?`. The workflow
# has other plan commands whose -target lists never run on a push to main, so the allowlist rows below
# read THIS region, not the whole file.
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/{f=1} f{print} f&&/^[[:space:]]*rc=\$\?/{exit}' "$WF")"

# Whole-line assertions anchored at both ends: a bare substring grep is satisfied by the same text
# inside a comment, or with a suffix that inverts it (`paused = false || true`).
# Every grep over a captured VARIABLE reads a HERE-STRING, never `printf … | grep -q`: under pipefail, grep -q exiting on its
# first match can SIGPIPE the writer and fail the pipeline, which fails a negated check OPEN.
line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
# A resource's own attributes sit at exactly two spaces and a nested block's at four, so a decoy
# `paused = false` inside `metadata = { … }` cannot satisfy a top-level check (valid HCL cannot repeat a
# top-level attribute, which is what makes one anchored line sufficient).
top_in() {  # top_in <text> <ERE for the whole line, without anchors>
  grep -qE "^  $2[[:space:]]*(#.*)?$" <<< "$1"
}
blk_in() {  # blk_in <text> <ERE for the whole line, without anchors>
  grep -qE "^    $2[[:space:]]*(#.*)?$" <<< "$1"
}

[ -n "$LOCAL_SQL" ] \
  && ok "the predicate local is a heredoc this guard can read" \
  || no "ghcr_hostsfile_deny_lost_sql: heredoc not found — every predicate row below would be vacuous"

# ── the emitters: needles are READ, not retyped ─────────────────────────────────────────────────
# Web arm. The single sink is `logger -t "$LOG_TAG" "GHCR_DENY ghcr_blocked=$_ghcr_blocked"`; the needle is
# the literal up to the variable, and the value domain is pinned by the case line just above it.
W_LINES="$(grep -E '^logger -t "\$LOG_TAG" "GHCR_DENY ghcr_blocked=\$_ghcr_blocked"( 2>/dev/null)?( \|\| .*)?$' "$CI")"
W_NEEDLE="$(sed -n 's/^logger -t "\$LOG_TAG" "\(GHCR_DENY ghcr_blocked=\)\$_ghcr_blocked".*/\1/p' <<< "$W_LINES" | head -1)"
if [ -n "$W_NEEDLE" ] && [ "$(grep -c . <<< "$W_LINES")" -eq 1 ]; then
  ok "ci-deploy.sh has exactly one column-0 GHCR_DENY logger sink; needle captured from it: '$W_NEEDLE'"
else
  no "ci-deploy.sh no longer has exactly one column-0 logger -t \"\$LOG_TAG\" \"GHCR_DENY ghcr_blocked=\$_ghcr_blocked\" sink (it may have moved inside a conditional, e.g. only for the deploy action) — the alert would silently stop matching; ci-deploy.test.sh counts GHCR_DENY lines behaviourally"
fi
SINK_N="$(grep -nE '^logger -t "\$LOG_TAG" "GHCR_DENY ghcr_blocked=\$_ghcr_blocked"' "$CI" | head -1 | cut -d: -f1)"
SHA_N="$(grep -nE '^logger -t "\$LOG_TAG" "DEPLOY_SCRIPT_SHA ' "$CI" | head -1 | cut -d: -f1)"
LOCK_N="$(grep -nE '^LOCK_FILE=' "$CI" | head -1 | cut -d: -f1)"
if [[ "$SINK_N" =~ ^[0-9]+$ && "$SHA_N" =~ ^[0-9]+$ && "$LOCK_N" =~ ^[0-9]+$ ]] && [ "$SHA_N" -lt "$SINK_N" ] && [ "$SINK_N" -lt "$LOCK_N" ] \
   && ! sed -n "${SHA_N},${LOCK_N}p" "$CI" | grep -vE '^[[:space:]]*#' | grep -qE '\b(exit|return)\b'; then
  ok "the web sink sits after the DEPLOY_SCRIPT_SHA logger and before the lock, with no exit or return (any indentation, comments stripped) anywhere between those two anchors, so nothing there can skip it"
else
  no "the GHCR_DENY sink is no longer between the DEPLOY_SCRIPT_SHA logger and LOCK_FILE=, or an exit/return now sits between those anchors — a validated invocation could skip it"
fi
grep -qxF 'readonly LOG_TAG="ci-deploy"' "$CI" \
  && ok "LOG_TAG is ci-deploy (the SYSLOG_IDENTIFIER the web arm matches)" \
  || no "ci-deploy.sh no longer declares readonly LOG_TAG=\"ci-deploy\""
[ "$(grep -cE '^case "\$_ghcr_blocked" in 1 \| 0 \| unknown\) ;; \*\) _ghcr_blocked=unknown ;; esac$' "$CI")" -eq 1 ] \
  && ok "the web emitter's value domain is exactly 1 | 0 | unknown (0 is the only value the alert needs, and it is a real value)" \
  || no "ci-deploy.sh no longer clamps _ghcr_blocked to 1 | 0 | unknown — the alert's value-0 literal may no longer be reachable"
# The DIRECTION of the derivation: 0 must be printed on the branch where a NON-sinkhole address resolves.
# Swapping the two echoes keeps every literal intact and pages on the healthy state / goes silent on a loss.
if grep -A1 -xF "  elif grep -qvxE '0\.0\.0\.0|::' <<<\"\$addrs\"; then" "$CI" | grep -qxF '    echo 0'; then
  ok "the web emitter derives 0 on the branch where a non-sinkhole address resolves (the deny is NOT in force)"
else
  no "ci-deploy.sh no longer prints 0 on the non-sinkhole branch of _ghcr_blocked_state — the alert's value-0 literal may mean the opposite"
fi

# Registry arm. The heartbeat LINE starts with the marker, carries ` ghcr_blocked=$GHCR_BLOCKED ` before the
# attacker-influenced ` zot_last_err=` free text, and ends with it.
R_LINE="$(grep -E '^[[:space:]]*LINE="SOLEUR_ZOT_DISK ' "$CR")"
R_MARK="$(sed -n 's/^[[:space:]]*LINE="\(SOLEUR_ZOT_DISK \).*/\1/p' <<< "$R_LINE" | head -1)"
R_FIELD="$(grep -o ' ghcr_blocked=\$GHCR_BLOCKED ' <<< "$R_LINE" | head -1 | sed 's/\$GHCR_BLOCKED //')"
if [ -n "$R_MARK" ] && [ "$(grep -c . <<< "$R_LINE")" -eq 1 ] && [ -n "$R_FIELD" ] \
   && grep -qE '^[[:space:]]*LINE="SOLEUR_ZOT_DISK .* ghcr_blocked=\$GHCR_BLOCKED .* zot_last_err=\$ZOT_LAST_ERR"$' <<< "$R_LINE"; then
  ok "cloud-init-registry.yml has exactly one SOLEUR_ZOT_DISK LINE; marker '$R_MARK', field '$R_FIELD' sits before ' zot_last_err='"
else
  no "cloud-init-registry.yml no longer has exactly one LINE=\"SOLEUR_ZOT_DISK … ghcr_blocked=\$GHCR_BLOCKED … zot_last_err=\$ZOT_LAST_ERR\" — arm R would silently stop matching"
fi
grep -qE '^[[:space:]]*if printf .%s\\n. "\$_gh_addrs" \| grep -qvxE .0\\\.0\\\.0\\\.0\|::.; then GHCR_BLOCKED=0; else GHCR_BLOCKED=1; fi$' "$CR" \
  && ok "the registry emitter yields 0 exactly when ghcr.io resolves to something other than the sinkhole" \
  || no "cloud-init-registry.yml no longer derives GHCR_BLOCKED=0 from a non-sinkhole address — the alert's value-0 literal may mean something else"
# The cadence the paging windows assume: the heartbeat runs every five minutes (check 300 / query 900 hold ~3 rows).
CRON_ENTRY="$(awk '/^  - path: \/etc\/cron\.d\/zot-disk-heartbeat$/{f=1} f{print} f&&/^  - path: /&&!/zot-disk-heartbeat/{exit}' "$CR")"
CRON_LINE='      */5 * * * * root set -a; . /etc/default/registry-doppler; set +a; doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh'
[ "$(grep -cxF "$CRON_LINE" <<< "$CRON_ENTRY")" -eq 1 ] \
  && ok "the registry heartbeat cron.d entry runs the whole every-five-minutes line (doppler prd config included); the paging windows assume ~3 rows per 900 s bucket" \
  || no "the /etc/cron.d/zot-disk-heartbeat entry in cloud-init-registry.yml no longer carries the exact */5 doppler-prd line — the 300/900/1800 windows were sized for it, and a neutralised line reads as a quiet fleet"
# The POST arm R's startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ') relies on: the heartbeat script's own curl body.
HB_SCRIPT="$(awk '/^  - path: \/usr\/local\/bin\/zot-disk-heartbeat\.sh$/{f=1} f{print} f&&/^      exit 0$/{exit}' "$CR")"
[ "$(grep -cF -- '--data-raw "{\"message\":\"$LINE\"' <<< "$HB_SCRIPT")" -ge 1 ] \
  && ok "the heartbeat POSTs a {\"message\":\"<LINE>\"} body, the shape arm R's startsWith(raw, ...) anchors on" \
  || no "zot-disk-heartbeat.sh no longer POSTs {\"message\":\"\$LINE\"} — arm R's startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ') would silently stop matching"

# ── the predicate, compared whole ───────────────────────────────────────────────────────────────
_msg="JSONExtractString(raw, 'message')"
EXPECT_1="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND ("
EXPECT_1+="(JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy' AND ${_msg} = '${W_NEEDLE}0')"
EXPECT_1+=" OR (startsWith(raw, '{\"message\":\"${R_MARK}') AND position(${_msg}, '${R_MARK}') = 1"
EXPECT_1+=" AND position(${_msg}, '${R_FIELD}0 ') > 0 AND position(${_msg}, '${R_FIELD}0 ') < position(${_msg}, ' zot_last_err='))"
EXPECT_1+=") GROUP BY time"
if [ -n "$W_NEEDLE" ] && [ -n "$R_MARK" ] && [ -n "$R_FIELD" ] && [ "$SQL_1" = "$EXPECT_1" ]; then
  ok "the predicate equals the string built from the emitters' own needles (two arms, value 0, nothing else)"
else
  no "the predicate is not the two-arm string built from the emitters' needles"
fi

grep -qF "JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'" <<< "$SQL_1" \
  && ok "the web arm's tag conjunct: SYSLOG_IDENTIFIER = 'ci-deploy'" \
  || no "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing or altered"
if [ -n "$W_NEEDLE" ] && grep -qF "${_msg} = '${W_NEEDLE}0')" <<< "$SQL_1"; then
  ok "the web arm's exactness: the message EQUALS the emitter's needle with value 0 (a row merely quoting it cannot alert)"
else
  no "the web arm's exactness conjunct is missing, loosened, or no longer equals the needle read from ci-deploy.sh"
fi
if [ -n "$R_MARK" ] && grep -qF "startsWith(raw, '{\"message\":\"${R_MARK}') AND position(${_msg}, '${R_MARK}') = 1" <<< "$SQL_1"; then
  ok "the registry arm's marker anchor: the raw row AND the extracted message both START with the marker"
else
  no "the registry arm's marker anchor is missing or altered"
fi
if [ -n "$R_FIELD" ] \
   && grep -qF "position(${_msg}, '${R_FIELD}0 ') > 0 AND position(${_msg}, '${R_FIELD}0 ') < position(${_msg}, ' zot_last_err=')" <<< "$SQL_1"; then
  ok "the registry arm's head-scope: ' ghcr_blocked=0 ' must sit BEFORE ' zot_last_err=' (the free text cannot forge it)"
else
  no "the registry arm's head-scope is missing or altered"
fi
if [ "$(grep -oE ' OR ' <<< "$SQL_1" | grep -c .)" -eq 1 ] \
   && [ "$(grep -oE '\) OR \(' <<< "$SQL_1" | grep -c .)" -eq 1 ] \
   && ! grep -qiE '(^|[^A-Za-z_])NOT([^A-Za-z_]|$)|!=|<>' <<< "$LOCAL_SQL"; then
  ok "exactly one OR joins exactly two arms, and the predicate has no negation"
else
  no "the predicate has more than one OR, an OR that does not join the two arms, or a negation"
fi
if grep -qiE 'ghcr_blocked=(1|unknown)' <<< "$LOCAL_SQL"; then
  no "the predicate names value 1 or unknown — the alert would page on the healthy state or on a blind probe"
else
  ok "only value 0 is matched (1 is the healthy state, unknown is a blind probe, not the deny regressing)"
fi
grep -qi 'host_name' <<< "$LOCAL_SQL" \
  && no "the predicate carries a host_name conjunct — it would exclude web-2 and web-1's pre-rename host name" \
  || ok "no host_name conjunct: any host's lost deny alerts"

EXPL_QRY="$(awk '/^  query \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
EXPL_VAR="$(awk '/^  variable \{/{f=1} f{print} f&&/^  \}/{exit}' <<< "$EXPL")"
blk_in "$EXPL_QRY" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.ghcr_hostsfile_deny_lost_sql\), "/\\\\s\+/", " "\)' \
  && ok "the exploration carries THIS predicate, collapsed to one line (the sibling's perpetual-diff rule)" \
  || no "the exploration does not carry local.ghcr_hostsfile_deny_lost_sql as its sql_query"
blk_in "$EXPL_VAR" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "the exploration reads the prd Vector source" \
  || no "the exploration's source variable is not local.vector_prd_source_id"
[ "$(grep -cE '^  query \{' <<< "$EXPL")" -eq 1 ] && [ "$(grep -cE '^  variable \{' <<< "$EXPL")" -eq 1 ] \
  && blk_in "$EXPL_QRY" 'source_variable[[:space:]]*=[[:space:]]*"source"' \
  && blk_in "$EXPL_QRY" 'query_type[[:space:]]*=[[:space:]]*"sql_expression"' \
  && blk_in "$EXPL_VAR" 'name[[:space:]]*=[[:space:]]*"source"' \
  && ok "the exploration has exactly one query and one variable block, and the wiring is read inside each (source_variable=source -> variable source, the prd source)" \
  || no "the exploration's query/variable wiring is not exactly one sql_expression query reading variable \"source\""

[ -n "$ALERT" ] && ok "logtail_exploration_alert.ghcr_hostsfile_deny_lost exists (exact header)" \
  || no "logtail_exploration_alert.ghcr_hostsfile_deny_lost is missing"
top_in "$ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.ghcr_hostsfile_deny_lost\.id' \
  && ok "the alert watches ITS OWN exploration" \
  || no "the alert's exploration_id is not logtail_exploration.ghcr_hostsfile_deny_lost.id"
top_in "$ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-ghcr-hostsfile-deny-lost-prd"' \
  && top_in "$EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-ghcr-hostsfile-deny-lost-prd"' \
  && ok "both are named soleur-ghcr-hostsfile-deny-lost-prd" \
  || no "the exploration/alert name drifted from soleur-ghcr-hostsfile-deny-lost-prd"
top_in "$ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && top_in "$ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && top_in "$ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "threshold, higher_than 0: ONE row reading ghcr_blocked=0 alerts" \
  || no "the alert is not threshold/higher_than/0 — a single lost-deny row would not alert"
top_in "$ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is not treat_as_zero"
top_in "$ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && ok "paused = false on its own line" \
  || no "the alert is paused (or paused carries a suffix)"
top_in "$ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && ok "email = true (the free-tier alerting surface)" \
  || no "email is not true"
top_in "$ALERT" 'confirmation_period[[:space:]]*=[[:space:]]*0' \
  && top_in "$ALERT" 'check_period[[:space:]]*=[[:space:]]*300' \
  && top_in "$ALERT" 'query_period[[:space:]]*=[[:space:]]*900' \
  && top_in "$ALERT" 'recovery_period[[:space:]]*=[[:space:]]*1800' \
  && ok "check 300 / query 900 / recovery 1800 with no confirmation delay: the registry heartbeat is */5 so the window holds three emissions, and one quiet bucket does not close an incident the next would re-open" \
  || no "the paging windows drifted from check 300 / query 900 / confirmation 0 / recovery 1800 (the registry_store_not_luks combination)"
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
grep -qE '^  incident_cause[[:space:]]*=.*does NOT mean the deny is back' <<< "$ALERT" \
  && ok "the incident text says resolution does NOT mean the deny is back (an auto-resolved page is not a fix)" \
  || no "the incident text no longer warns that auto-resolution does not mean the deny is restored"

RB_URL_RE='^[[:space:]]*ghcr_hostsfile_deny_lost_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cron-egress-blocked\.md#[a-z0-9_-]+"'
grep -qE '^  incident_cause[[:space:]]*=.*[Rr]unbook: \$\{local\.ghcr_hostsfile_deny_lost_runbook_url\}"[[:space:]]*$' <<< "$ALERT" \
  && blk_in "$ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.ghcr_hostsfile_deny_lost_runbook_url' \
  && grep -qE "$RB_URL_RE" "$TF" \
  && ok "incident_cause and metadata.runbook carry the cron-egress-blocked runbook URL (the email is what a reader acts on)" \
  || no "the incident has no clickable cron-egress-blocked runbook URL"

grep -qE '^[[:space:]]*-target=logtail_exploration\.ghcr_hostsfile_deny_lost \\$' <<< "$MAIN_PLAN" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.ghcr_hostsfile_deny_lost \\$' <<< "$MAIN_PLAN" \
  && ok "both resources are in the push-triggered MAIN plan's -target= allowlist (#5566: an untargeted resource is never applied)" \
  || no "one or both -target= lines are missing — the alert would never exist in Better Stack"
# Reachability: -target= lines only matter if a merge to main runs this plan at all.
WF_PUSH="$(awk '/^on:$/{o=1;next} o&&/^[a-z]/{exit} o&&/^  push:$/{p=1;next} o&&p&&/^  [a-z_]+:/{exit} p{print}' "$WF")"
if grep -qxF '    branches: [main]' <<< "$WF_PUSH" && grep -qxF '      - "apps/web-platform/infra/**"' <<< "$WF_PUSH" \
   && [ -z "$(grep -E '^      - "!' <<< "$WF_PUSH" | grep -vxF -e '      - "!apps/web-platform/infra/rung2-rehearsal/**"' -e '      - "!apps/web-platform/infra/git-data-root-key/**"' || true)" ] \
   && [ "$(grep -cxF "      (github.event_name == 'push' || inputs.apply_target == 'manual-rerun')" "$WF")" -eq 1 ]; then
  ok "apply-web-platform-infra.yml's push block runs on main for apps/web-platform/infra/** with no path negation beyond the two known sub-roots, and the apply job runs on push (the alert is created by the merge, not by hand)"
else
  no "apply-web-platform-infra.yml no longer triggers the apply on push to main for apps/web-platform/infra/** (branch, path, a negation of the alert's file, or the apply job's push clause changed) — the alert would not be created on merge"
fi
# This guard only runs in CI if infra-validation.yml runs it, and re-runs on a runbook heading rename or an edit of
# the apply workflow (both read from the pull_request block, not anywhere in the file).
IV_PR="$(awk '/^  pull_request:$/{p=1;next} p&&/^  [a-z_]+:/{exit} p{print}' "$IV")"
IV_JOB="$(awk '/^  deploy-script-tests-fixed:$/{f=1;print;next} f&&/^  [A-Za-z0-9_-]+:$/{exit} f{print}' "$IV")"
IV_STEP="$(awk '/^      - name: Run hosts-file GHCR deny lost alert drift guard \(#9391\)$/{f=1;print;next} f&&/^      - name:/{exit} f{print}' <<< "$IV_JOB")"
IV_HDR="$(awk '/^    steps:$/{exit} {print}' <<< "$IV_JOB")"
if [ "$(grep -cxF '      - "knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '      - ".github/workflows/apply-web-platform-infra.yml"' <<< "$IV_PR")" -eq 1 ] \
   && [ "$(grep -cxF '        run: bash apps/web-platform/test/infra/ghcr-blocked-alert.test.sh' <<< "$IV_STEP")" -eq 1 ] \
   && ! grep -qE '^        (if|continue-on-error):' <<< "$IV_STEP" \
   && [ "$(grep -cxF "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" <<< "$IV_HDR")" -eq 1 ] \
   && ! grep -qE '^    continue-on-error:' <<< "$IV_HDR"; then
  ok "infra-validation.yml's pull_request paths list the runbook and the apply workflow, and deploy-script-tests-fixed runs this guard in an unconditional, blocking step"
else
  no "infra-validation.yml no longer wires this guard: runbook or apply-workflow path missing from pull_request paths, the step missing/conditional/non-blocking, or its job conditional/non-blocking"
fi

# The runbook's decode is the only no-SSH reader of this alert: run its own function body against synthetic rows
# (a non-JSON row, an object-message row, a forged ` zot_last_err` tail, healthy rows) with the two network tools stubbed.
JQ_DIR="$(mktemp -d -t ghcrjq.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
assert_fixture_dir "$JQ_DIR"
awk '/^ghcr_deny_rows\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$RB" | sed "s#scripts/betterstack-query.sh#$JQ_DIR/bq.sh#" > "$JQ_DIR/fn.sh"
printf '#!/bin/bash\ncat "%s/rows.jsonl"\n' "$JQ_DIR" > "$JQ_DIR/bq.sh"
printf '#!/bin/bash\nwhile [ "$1" != "--" ] && [ $# -gt 0 ]; do shift; done; shift; exec "$@"\n' > "$JQ_DIR/doppler"
chmod +x "$JQ_DIR/bq.sh" "$JQ_DIR/doppler"
cat > "$JQ_DIR/rows.jsonl" <<'ROWS'
{"dt":"2026-10-04 10:00:00","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"message\":\"GHCR_DENY ghcr_blocked=0\",\"host_name\":\"soleur-web-2\"}"}
{"dt":"2026-10-04 10:01:00","raw":"not json at all ghcr_blocked=0"}
{"dt":"2026-10-04 10:02:00","raw":"{\"SYSLOG_IDENTIFIER\":\"doppler\",\"message\":{\"x\":\"ghcr_blocked=0\"},\"host_name\":\"soleur-inngest-prd\"}"}
{"dt":"2026-10-04 10:03:00","raw":"{\"message\":\"SOLEUR_ZOT_DISK pcent=1 resize_ok=true ghcr_blocked=0 host=soleur-registry zot_last_err=none\"}"}
{"dt":"2026-10-04 10:04:00","raw":"{\"message\":\"SOLEUR_ZOT_DISK pcent=1 ghcr_blocked=1 host=soleur-registry zot_last_err=quoted ghcr_blocked=0 \"}"}
{"dt":"2026-10-04 10:05:00","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"message\":\"GHCR_DENY ghcr_blocked=1\",\"host_name\":\"soleur-web-platform\"}"}
ROWS
JQ_GOT="$(PATH="$JQ_DIR:$PATH" bash -c ". '$JQ_DIR/fn.sh'; ghcr_deny_rows x 0" 2>&1)"
JQ_WANT=$'2026-10-04 10:00:00\tsoleur-web-2\tghcr_blocked=0\n2026-10-04 10:03:00\tsoleur-registry\tghcr_blocked=0'
JQ_ONE="$(PATH="$JQ_DIR:$PATH" bash -c ". '$JQ_DIR/fn.sh'; ghcr_deny_rows x 1" 2>&1)"
JQ_ONE_WANT=$'2026-10-04 10:04:00\tsoleur-registry\tghcr_blocked=1\n2026-10-04 10:05:00\tsoleur-web-platform\tghcr_blocked=1'
rm -rf "$JQ_DIR"
if [ "$JQ_GOT" = "$JQ_WANT" ] && [ "$JQ_ONE" = "$JQ_ONE_WANT" ]; then
  ok "the runbook's ghcr_deny_rows decode selects the web and registry value-0 rows (host from host_name or host=), skips non-JSON and object-message rows, ignores a forged tail past zot_last_err, and its =1 control selects the healthy rows"
else
  no "the runbook's ghcr_deny_rows decode no longer returns exactly the expected rows for the synthetic fixture (=0: '$JQ_GOT' / =1: '$JQ_ONE')"
fi

# The alert's runbook link must land on a real heading: the URL slug is compared with the GitHub
# slug of every heading in the runbook (fenced blocks skipped; punctuation dropped, spaces to dashes).
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
  && ok "the runbook anchor '#${RB_SLUG}' resolves to a heading in cron-egress-blocked.md" \
  || no "the runbook anchor '#${RB_SLUG:-?}' matches no heading in cron-egress-blocked.md — the alert's link would dangle"

# ── Mutation rows: each must make a row above RED ─────────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching GHCR_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
PRESENCE_ROWS=38
MUT_ROWS_EXPECTED=40
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t ghcralert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|CI|CR|RB|IV> <expected [FAIL] substring, "" for PASS> <python-program-on-s>
    local want="$1" label="$2" which="$3" expect="$4" prog="$5" src copy rc=0
    local ilog="$MUT_DIR/inner.log"
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      CI) src="$CI"; copy="$MUT_DIR/ci-deploy.sh" ;;
      CR) src="$CR"; copy="$MUT_DIR/cloud-init-registry.yml" ;;
      RB) src="$RB"; copy="$MUT_DIR/cron-egress-blocked.md" ;;
      IV) src="$IV"; copy="$MUT_DIR/infra-validation.yml" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    # The program is handed to python through the ENVIRONMENT, so no shell layer rewrites it.
    MUT_PROG="$prog" python3 - "$copy" <<'PY' || { no "mutation '$label' did not land (anchor drifted)"; MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1)); return 0; }
import os, sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def sql_replace(s, old, new):
    # The first occurrence AFTER the predicate local's opening line: other alerts in this file carry
    # identical tag conjuncts earlier on.
    i = s.index("  ghcr_hostsfile_deny_lost_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
exec(os.environ["MUT_PROG"])
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    env "GHCR_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$ilog" 2>&1 || rc=$?
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
    MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
  }
  MUT_ROWS_RUN=0

  # M1 — the web arm's tag conjunct is dropped: rows quoting the marker under another identifier could alert.
  mutate RED "M1a the tag conjunct is dropped (quoting rows under another SYSLOG_IDENTIFIER could alert)" TF \
    "the SYSLOG_IDENTIFIER='ci-deploy' conjunct is missing" \
    's = sql_replace(s, "(JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n          AND ", "(")'
  # M1 — exactness is loosened to startsWith: a row that merely begins with the marker could alert.
  mutate RED "M1b equality is loosened to startsWith (a longer row beginning with the marker could alert)" TF \
    "the web arm's exactness conjunct is missing" \
    's = sql_replace(s, "JSONExtractString(raw, \x27message\x27) = \x27GHCR_DENY ghcr_blocked=0\x27", "startsWith(JSONExtractString(raw, \x27message\x27), \x27GHCR_DENY ghcr_blocked=0\x27)")'
  # M2 — the registry arm's head-scope is dropped: the free text after ` zot_last_err=` could forge the field.
  mutate RED "M2 the registry head-scope is dropped (zot_last_err free text could forge ghcr_blocked=0)" TF \
    "the registry arm's head-scope is missing" \
    's = sql_replace(s, "\n          AND position(JSONExtractString(raw, \x27message\x27), \x27 ghcr_blocked=0 \x27) < position(JSONExtractString(raw, \x27message\x27), \x27 zot_last_err=\x27)", "")'
  # M3 — the emitter literal is reworded in a COPY of each emitter; the alert's literal is untouched. The
  # guard must be reading the consumer's own needle, not a pinned string.
  mutate RED "M3a the web emitter is reworded in ci-deploy.sh only (GHCR_DENY -> GHCR_STATE; no sink is found and arm W no longer matches it)" CI \
    "the web arm's exactness conjunct is missing" \
    'old = "\"GHCR_DENY ghcr_blocked=$_ghcr_blocked\""
assert s.count(old) == 1
s = s.replace(old, "\"GHCR_STATE ghcr_blocked=$_ghcr_blocked\"")'
  mutate RED "M3b the registry field is renamed in cloud-init-registry.yml only (arm R would silently stop matching)" CR \
    "cloud-init-registry.yml no longer has exactly one LINE" \
    'old = " ghcr_blocked=$GHCR_BLOCKED "
assert s.count(old) == 1
s = s.replace(old, " ghcr_state=$GHCR_BLOCKED ")'
  mutate RED "M3c the web sink is indented off column 0 (a conditional wrapper would; ci-deploy.test.sh owns per-action reachability)" CI \
    "ci-deploy.sh no longer has exactly one column-0" \
    'old = "\nlogger -t \"$LOG_TAG\" \"GHCR_DENY ghcr_blocked=$_ghcr_blocked\""
assert s.count(old) == 1
s = s.replace(old, "\n  logger -t \"$LOG_TAG\" \"GHCR_DENY ghcr_blocked=$_ghcr_blocked\"")'
  # M4 — either -target= line is dropped, and then both are MOVED out of the main plan (still in the
  # file, never applied).
  mutate RED "M4a the exploration is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration.ghcr_hostsfile_deny_lost \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "M4b the alert is dropped from the apply allowlist" WF \
    "one or both -target= lines are missing" \
    'old = "              -target=logtail_exploration_alert.ghcr_hostsfile_deny_lost \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "M4c the -target= lines move out of the main plan (still in the file, never applied)" WF \
    "one or both -target= lines are missing" \
    'a = "              -target=logtail_exploration.ghcr_hostsfile_deny_lost \\\n"
b = "              -target=logtail_exploration_alert.ghcr_hostsfile_deny_lost \\\n"
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, "").replace(b, "") + "\n" + a + b'
  # M5 — a THIRD arm is appended after a compliant pair: a check that stops at the first member passes it.
  mutate RED "M5 a third OR arm matching ghcr_blocked=1 is appended after the compliant pair" TF \
    "the predicate has more than one OR" \
    's = sql_replace(s, "\n      )\n    GROUP BY time", "\n    OR (JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27 AND JSONExtractString(raw, \x27message\x27) = \x27GHCR_DENY ghcr_blocked=1\x27)\n  )\n    GROUP BY time")'
  # M6 — the guard's OWN dispatch: the locals key is renamed so the heredoc extractor returns empty.
  mutate RED "M6 the predicate local is renamed so the heredoc extractor finds nothing (the guard must not go vacuous)" TF \
    "ghcr_hostsfile_deny_lost_sql: heredoc not found" \
    'old = "  ghcr_hostsfile_deny_lost_sql = <<-SQL"
assert s.count(old) == 1
s = s.replace(old, "  ghcr_hostsfile_deny_lost_sql_renamed = <<-SQL")'
  # M7 — paging semantics, each its own row.
  mutate RED "M7a the threshold value is raised to 1 (a single lost-deny row no longer alerts)" TF \
    "the alert is not threshold/higher_than/0" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\" \{.*?\n  value\s*=\s*)0", s, re.S)
assert m
s = s[:m.end(1)] + "1" + s[m.end():]'
  mutate RED "M7b on_missing_data is no longer treat_as_zero" TF \
    "on_missing_data is not treat_as_zero" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\" \{.*?\n  on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  mutate RED "M7c the alert is paused" TF \
    "the alert is paused" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  mutate RED "M7d the query window is shortened to 300 (a registry heartbeat gap would flap the incident)" TF \
    "the paging windows drifted" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\" \{.*?\n  query_period\s*=\s*)900", s, re.S)
assert m
s = s[:m.end(1)] + "300" + s[m.end():]'
  mutate RED "M7e email is switched off (the free-tier alerting surface)" TF \
    "email is not true" \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\" \{.*?\n  email\s*=\s*)true", s, re.S)
assert m
s = s[:m.end(1)] + "false" + s[m.end():]'
  # M8 — the runbook heading is renamed in the copy: the alert's link would dangle.
  mutate RED "M8 the runbook heading is renamed (the alert's runbook link would dangle)" RB \
    "the runbook anchor" \
    'old = "### Hosts-file deny lost (Better Stack alert)"
assert s.count(old) == 1
s = s.replace(old, "### Hosts-file deny lost (renamed)")'
  # M9 — a host conjunct is added: web-2 and the pre-rename web-1 name would go silent.
  mutate RED "M9 a host_name conjunct is added (web-2 and the pre-rename web-1 name would go silent)" TF \
    "the predicate carries a host_name conjunct" \
    's = sql_replace(s, "\n      )\n    GROUP BY time", "\n  )\n      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-platform\x27\n    GROUP BY time")'
  # M10 — a value-1 needle is added to the registry arm: the alert would page on the healthy state.
  mutate RED "M10 the registry arm matches ghcr_blocked=1 instead of 0 (it would page on the healthy state)" TF \
    "the predicate names value 1 or unknown" \
    'old = "\x27 ghcr_blocked=0 \x27) > 0"
i = s.index("  ghcr_hostsfile_deny_lost_sql = <<-SQL")
j = s.index(old, i)
s = s[:j] + "\x27 ghcr_blocked=1 \x27) > 0" + s[j + len(old):]'

  # Must-PASS: layout is not part of the contract (the resource flattens the predicate with replace(…, "/\\s+/", " ")).
  mutate PASS "M11a every heredoc line is re-indented far deeper (layout is not part of the contract)" TF \
    "" \
    'import re
i = s.index("  ghcr_hostsfile_deny_lost_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
head, rest = s[i:j].split("\n", 1)
s = s[:i] + head + "\n" + re.sub(r"(?m)^\s+", "                    ", rest) + s[j:]'
  mutate PASS "M11b the predicate is joined onto one line with irregular spacing (layout is not part of the contract)" TF \
    "" \
    'import re
i = s.index("  ghcr_hostsfile_deny_lost_sql = <<-SQL")
j = s.index("\n  SQL\n", i)
head, rest = s[i:j].split("\n", 1)
s = s[:i] + head + "\n    " + re.sub(r"\s*\n\s*", "   ", rest.strip()) + s[j:]'

  # The ">0" conjunct: without it a missing field (position 0) satisfies "< position(zot_last_err)" on a row
  # whose head lacks the field entirely.
  mutate RED "M12 the registry arm's field-present conjunct (> 0) is dropped" TF \
    "the predicate is not the two-arm string" \
    's = sql_replace(s, "\n          AND position(JSONExtractString(raw, \x27message\x27), \x27 ghcr_blocked=0 \x27) > 0", "")'
  # The DIRECTION of the web emitter's derivation: swapping the echoes keeps every literal intact.
  mutate RED "M13 the web emitter's derivation is inverted (0 printed when the deny IS in force)" CI \
    "ci-deploy.sh no longer prints 0 on the non-sinkhole branch" \
    'old = "; then\n    echo 0\n  else\n    echo 1\n  fi"
assert s.count(old) == 1
s = s.replace(old, "; then\n    echo 1\n  else\n    echo 0\n  fi")'
  # The cadence the paging windows were sized for.
  mutate RED "M14 the registry heartbeat cadence changes from every 5 to every 15 minutes" CR \
    "the /etc/cron.d/zot-disk-heartbeat entry in cloud-init-registry.yml no longer carries" \
    'old = "*/5 * * * * root set -a; . /etc/default/registry-doppler; set +a; doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh"
assert s.count(old) == 1
s = s.replace(old, old.replace("*/5", "*/15"))'
  # A decoy attribute in a nested block must not satisfy a top-level check.
  mutate RED "M15 the alert is paused at top level while a decoy paused = false sits in metadata" TF \
    "the alert is paused" \
    'k = s.index("resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\"")
t = s.index("\n  paused = false\n", k)
s = s[:t] + "\n  paused = true\n" + s[t + len("\n  paused = false\n"):]
m = s.index("    runbook = local.ghcr_hostsfile_deny_lost_runbook_url\n", k)
s = s[:m] + "    paused = false\n" + s[m:]'
  # The apply workflow must still run on a merge to main.
  mutate RED "M16 the apply workflow stops triggering on push to main" WF \
    "apply-web-platform-infra.yml no longer triggers the apply on push" \
    'old = "on:\n  push:\n    branches: [main]"
assert s.count(old) == 1
s = s.replace(old, "on:\n  push:\n    branches: [release]")'
  # The runbook is wired into infra-validation's paths.
  mutate RED "M17 the runbook path is dropped from infra-validation.yml's pull_request paths" IV \
    "infra-validation.yml no longer wires this guard" \
    'old = "      - \"knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md\"\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "M18 the push apply stops covering this alert's own file (a negation of betterstack-logs-alerts.tf)" WF \
    "apply-web-platform-infra.yml no longer triggers the apply on push" \
    'old = "    paths:\n      - \"apps/web-platform/infra/**\"\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - \"!apps/web-platform/infra/betterstack-logs-alerts.tf\"\n")'
  mutate RED "M19 the apply job no longer runs on push (manual-rerun only)" WF \
    "apply-web-platform-infra.yml no longer triggers the apply on push" \
    'old = "      (github.event_name == \x27push\x27 || inputs.apply_target == \x27manual-rerun\x27)\n"
assert s.count(old) == 1
s = s.replace(old, "      (inputs.apply_target == \x27manual-rerun\x27)\n")'
  mutate RED "M20 the guard step becomes non-blocking (continue-on-error)" IV \
    "infra-validation.yml no longer wires this guard" \
    'old = "        run: bash apps/web-platform/test/infra/ghcr-blocked-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)'
  mutate RED "M21 the guard's job is disabled (if: false)" IV \
    "infra-validation.yml no longer wires this guard" \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n"
assert s.count(old) == 1
s = s.replace(old, "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: false\n")'
  mutate RED "M22 the apply workflow path is dropped from the pull_request paths" IV \
    "infra-validation.yml no longer wires this guard" \
    'old = "      - \".github/workflows/apply-web-platform-infra.yml\"\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "M23 the heartbeat cron line is neutralised (root true #)" CR \
    "the /etc/cron.d/zot-disk-heartbeat entry in cloud-init-registry.yml no longer carries" \
    'old = "*/5 * * * * root set -a; . /etc/default/registry-doppler; set +a; doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh"
assert s.count(old) == 1
s = s.replace(old, "*/5 * * * * root true # /usr/local/bin/zot-disk-heartbeat.sh")'
  mutate RED "M24 the heartbeat POST body changes shape ({\"msg\":...})" CR \
    "zot-disk-heartbeat.sh no longer POSTs" \
    'k = s.index("path: /usr/local/bin/zot-disk-heartbeat.sh")
old = "--data-raw \"{\\\"message\\\":\\\"$LINE\\\""
t = s.index(old, k)
s = s[:t] + "--data-raw \"{\\\"msg\\\":\\\"$LINE\\\"" + s[t + len(old):]'
  mutate RED "M25 an exit is inserted between the web sink and the lock" CI \
    "the GHCR_DENY sink is no longer between" \
    'old = "unset _ghcr_blocked\n\nLOCK_FILE="
assert s.count(old) == 1
s = s.replace(old, "unset _ghcr_blocked\nexit 0\n\nLOCK_FILE=")'
  mutate RED "M26 the web sink moves below the lock line" CI \
    "the GHCR_DENY sink is no longer between" \
    'sink = "logger -t \"$LOG_TAG\" \"GHCR_DENY ghcr_blocked=$_ghcr_blocked\" 2>/dev/null || true\n"
assert s.count(sink) == 1
s = s.replace(sink, "")
k = s.index("\nLOCK_FILE=")
e = s.index("\n", k + 1)
s = s[:e + 1] + sink + s[e + 1:]'
  mutate RED "M27 the alert's incident_cause is cut while a decoy copy sits in metadata" TF \
    "the incident has no clickable cron-egress-blocked runbook URL" \
    'k = s.index("resource \"logtail_exploration_alert\" \"ghcr_hostsfile_deny_lost\"")
t = s.index("\n  incident_cause = ", k)
e = s.index("\n  metadata = {", t)
full = s[t + 1:e]
s = s[:t + 1] + "  incident_cause = \"A host reports a thing.\"" + s[e:]
m = s.index("    runbook = local.ghcr_hostsfile_deny_lost_runbook_url\n", t)
s = s[:m] + "  " + full.replace("\n  ", "\n  ") + "\n" + s[m:]'

  mutate RED "M28 an early exit is inserted ABOVE the web sink (a non-deploy action would skip it)" CI \
    "the GHCR_DENY sink is no longer between" \
    'old = "_ghcr_blocked=$(_ghcr_blocked_state 2>/dev/null) || _ghcr_blocked=unknown\n"
assert s.count(old) == 1
s = s.replace(old, "[[ \"${ACTION:-}\" == deploy ]] || { exit 0; }\n" + old)'
  mutate RED "M29 the runbook decode's head-scope is inverted (i < e becomes i > e)" RB \
    "the runbook's ghcr_deny_rows decode no longer returns exactly" \
    'old = "$i != null and $e != null and $i < $e"
assert s.count(old) == 1
s = s.replace(old, "$i != null and $e != null and $i > $e")'

  # Harness row (a) — edit the SUITE: delete the assertion that reads the web emitter's needle. The floor
  # must RED (rc 2, the guard's FATAL class), because a guard that reports fewer checks and exits 0 is vacuous.
  suite_copy="$MUT_DIR/suite-minus-needle.sh"
  python3 - "$SELF" "$suite_copy" <<'PY' || { no "harness row (a) did not land (anchor drifted)"; }
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
start = s.index('if [ -n "$W_NEEDLE" ] && [ "$(grep -c . <<< "$W_LINES")" -eq 1 ]; then')
end = s.index("fi\n", start) + 3
open(dst, "w", encoding="utf-8").write(s[:start] + s[end:])
PY
  # The copy lives in MUT_DIR, so its own DIR/REPO resolve there: point it at the real tree explicitly.
  h_rc=0
  env GHCR_GUARD_TF="$TF" GHCR_GUARD_WF="$WF" GHCR_GUARD_CI="$CI" GHCR_GUARD_CR="$CR" GHCR_GUARD_RB="$RB" GHCR_GUARD_IV="$IV" MUT_SKIP=1 bash "$suite_copy" >"$MUT_DIR/h.log" 2>&1 || h_rc=$?
  if [ "$h_rc" -eq 2 ] && grep -qF 'assertion floor' "$MUT_DIR/h.log"; then
    ok "harness (a): deleting the assertion that reads the web emitter's needle trips the assertion floor"
  else
    no "harness (a): the suite with the needle assertion deleted exited $h_rc without the floor firing — the guard can lose a check silently"
  fi
  MUT_ROWS_RUN=$((MUT_ROWS_RUN + 1))
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
printf '\n=== ghcr-blocked-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
