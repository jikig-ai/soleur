#!/usr/bin/env bash
#
# Drift guard for the egress-gateway Better Stack Logs alerts
# (apps/web-platform/infra/betterstack-logs-alerts.tf):
#   * logtail_exploration_alert.egress_gw_deny_spike   (#9534)
#   * logtail_exploration_alert.egress_gw_probe_silent (#9534, host-attributed 2026-10-12)
#   * logtail_exploration_alert.egress_gw_probe_fail   (#9534 review follow-up)
#
# WHAT THE ALERTS ARE FOR. The gateway's security surface is its deny decisions
# (deny spike), and its liveness is proven only by the synthetic CONNECT probe
# (silent) — while probe VERDICT failures (result=fail, or the probe reporting
# its own gateway absent) were previously a Sentry-only op that paged nobody
# (fail). The silent alert's count is DISTINCT host_name: rows from both web
# hosts multiplex into one Logs source, so a plain count(*) lets a healthy
# host's beats mask the other's dead pipeline (measured 2026-10-12: web-2's
# probe emitted to its journal every 5 min while a birth-frozen vector.toml
# dropped every row at the Source-4 allowlist — the aggregate count looked
# fine on web-1's rows alone).
#
# WHAT THIS FILE PROTECTS, and why each row exists:
#   * Each predicate's conjuncts are pinned to the literals the emitters write
#     (SYSLOG_IDENTIFIER='egress-gw-probe' from cron-egress-resolve.sh's
#     logger -t site; result=fail / reason=gw_absent / TCP_DENIED needles), so a
#     one-sided reword reds here instead of disarming the page.
#   * The silent alert's host-attributed shape is pinned whole: whole-window
#     scalar (toDateTime({{end_time}}) AS time, NO GROUP BY), count(DISTINCT
#     JSONExtractString(raw, 'host_name')), threshold lower_than
#     length(var.web_hosts). Dropping DISTINCT, re-adding GROUP BY, or pinning
#     a literal host count all red.
#   * The fail alert pages on >0 verdict rows in 900 s with the sibling paging
#     semantics (threshold, treat_as_zero, unpaused, email, free/paid ternary).
#   * All six resources are in the apply workflow's MAIN plan -target=
#     allowlist; this guard is the only enforcement for logtail resources.
#   * The runbook URL's anchor resolves to a real heading in
#     cron-egress-blocked.md, and that runbook is in infra-validation.yml's
#     pull_request paths; this guard itself is registered as a step there.
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — each flattened heredoc must EQUAL its pinned canon
#     (DENY/SILENT/FAIL *_FLAT), so dead text and arithmetic edits go red;
#     decoy heredoc/resource openers are counted file-wide and red.
#   * BLOCK-SCOPED EXACTLY-ONCE PINS — every alert attribute is asserted inside
#     its own resource block by param(), whole value line anchored both ends.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run
#     only; the pristine-child control FATALs (rc 2) otherwise; EGW_GUARD_/MUT_SKIP
#     literals may not reach the workflow's executable text (the seam check).
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation;
#     instrument failures (rc>=2) are UNRESOLVED. Floor/ledger trips exit 1.
#
# WHAT THIS FILE DOES NOT PROVE: that the alerts are armed IN PRODUCTION (the
# twice-daily logs_alert reconciler arm reads the live world), nor that a real
# probe row reaches Better Stack (the Vector allowlist is pinned in
# journald-config.test.sh; live-probe counts are recorded in ADR-218's
# amendment).
#
# Mutation rows live at the bottom. Each COPIES one source file into a scratch
# dir, mutates the COPY, and re-runs this guard against it through the
# EGW_GUARD_* overrides. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${EGW_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${EGW_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
RB="${EGW_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md}"
CR="${EGW_GUARD_CR:-$REPO/apps/web-platform/infra/cron-egress-resolve.sh}"
IV="${EGW_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — every path this file READS is checked through it, and so is the scratch dir
# the mutation battery WRITES to.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$RB"; assert_fixture_dir "$CR"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the mutation battery needs it
' >&2; exit 2; }
for f in "$TF" "$WF" "$RB" "$CR" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# Extract a <<[-]SQL heredoc local by name: first line after `name = <<[-]SQL` to its `  SQL` terminator.
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
sql_has() {  # sql_has <sql-text> <ERE substring>
  grep -qE "$2" <<< "$1"
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

# ── G1: egress_gw_deny_spike (unchanged shape, pinned so the set has one guard) ────────────
DENY_SQL="$(sql_local egress_gw_deny_spike_sql)"
DENY_ALERT="$(res_block logtail_exploration_alert egress_gw_deny_spike)"
DENY_EXPL="$(res_block logtail_exploration egress_gw_deny_spike)"

# Opener/header counts — unanchored, file-wide, exactly once each. A /* */- or #-wrapped
# decoy opener still counts and goes red; dead text can never satisfy the live local.
for _o in   "egress_gw_deny_spike_sql[[:space:]]*=[[:space:]]*<<[-]SQL"   "egress_gw_probe_silent_sql[[:space:]]*=[[:space:]]*<<[-]SQL"   "egress_gw_probe_fail_sql[[:space:]]*=[[:space:]]*<<[-]SQL"; do
  _n="$(grep -cE "$_o" "$TF")"
  [ "$_n" -eq 1 ]     && ok "exactly one ${_o%%[*]} heredoc opener in the file (decoy copies count)"     || no "${_o%%[*]} opener count is $_n, want 1 — a decoy local exists"
done
for _r in   "logtail_exploration egress_gw_deny_spike"   "logtail_exploration_alert egress_gw_deny_spike"   "logtail_exploration egress_gw_probe_silent"   "logtail_exploration_alert egress_gw_probe_silent"   "logtail_exploration egress_gw_probe_fail"   "logtail_exploration_alert egress_gw_probe_fail"; do
  _n="$(grep -cE "resource \"${_r%% *}\" \"${_r##* }\"" "$TF")"
  [ "$_n" -eq 1 ]     && ok "exactly one resource ${_r} header in the file"     || no "resource ${_r} header count is $_n, want 1 — a decoy resource exists"
done

# Canonical-equality pins — the flattened heredoc must EQUAL this canon; dead text can never
# satisfy it, and any arithmetic/widening edit keeps no per-arm substring safe.
DENY_FLAT="$(printf '%s' "$DENY_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

[ -n "$DENY_SQL" ] \
  && ok "G1: egress_gw_deny_spike_sql heredoc is readable" \
  || no "egress_gw_deny_spike_sql: heredoc not found — the G1 rows below would be vacuous"
sql_has "$DENY_SQL" "JSONExtractString\(raw, 'CONTAINER_NAME'\) = 'soleur-egress-gw'" \
  && sql_has "$DENY_SQL" "position\(JSONExtractString\(raw, 'message'\), 'TCP_DENIED'\) > 0" \
  && ok "G1: deny predicate = container conjunct AND TCP_DENIED needle" \
  || no "G1: deny predicate lost a conjunct (container / TCP_DENIED)"
sql_has "$DENY_SQL" "GROUP BY time" \
  && ok "G1: deny predicate keeps GROUP BY time (per-bucket rate)" \
  || no "G1: deny predicate lost GROUP BY time"
[ "$DENY_FLAT" = "SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-egress-gw' AND position(JSONExtractString(raw, 'message'), 'TCP_DENIED') > 0 GROUP BY time" ] \
  && ok "G1: deny predicate is byte-exact (container conjunct, TCP_DENIED needle, GROUP BY)" \
  || no "G1: deny predicate drifted from the pinned text — diff DENY_FLAT against the canon"
param "$DENY_ALERT" 'exploration_id' 'logtail_exploration\.egress_gw_deny_spike\.id' \
  && param "$DENY_ALERT" 'operator' '"higher_than"' \
  && param "$DENY_ALERT" 'value' '20' \
  && ok "G1: deny alert watches its own exploration and pages higher_than 20" \
  || no "G1: deny alert exploration_id/operator/value drifted (not higher_than/20)"
param "$DENY_ALERT" 'paused' 'false' \
  && ok "G1: deny alert is not paused (it arms at merge)" \
  || no "G1: deny alert is paused — it would exist and never page"
[ "$(printf '%s\n' "$DENY_ALERT" | grep -c 'paused')" -eq 1 ] \
  && ok "G1: the string 'paused' occurs exactly once in the deny alert block (a commented or duplicated decoy counts)" \
  || no "G1: 'paused' occurs !=1 time in the deny alert block — a commented pinned-line decoy exists"
param "$DENY_ALERT" 'check_period' '300' \
  && param "$DENY_ALERT" 'query_period' '300' \
  && param "$DENY_ALERT" 'confirmation_period' '0' \
  && param "$DENY_ALERT" 'recovery_period' '1800' \
  && ok "G1: deny alert's cadence is exactly 300/300/0/1800 (exactly-once pins)" \
  || no "G1: deny alert check/query/confirmation/recovery periods are not exactly 300/300/0/1800"
param "$DENY_EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "G1: deny exploration reads the prd Vector source" \
  || no "G1: deny exploration source is not local.vector_prd_source_id"
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_deny_spike \\$' <<< "$APPLY_JOB" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_deny_spike \\$' <<< "$APPLY_JOB" \
  && ok "G1: both deny -target lines in the apply allowlist" \
  || no "G1: a deny -target line is missing — the alert would never apply"

# ── G2: egress_gw_probe_silent — host-attributed (the review fix this guard exists for) ───
SILENT_SQL="$(sql_local egress_gw_probe_silent_sql)"
SILENT_ALERT="$(res_block logtail_exploration_alert egress_gw_probe_silent)"
SILENT_EXPL="$(res_block logtail_exploration egress_gw_probe_silent)"

[ -n "$SILENT_SQL" ] \
  && ok "G2: egress_gw_probe_silent_sql heredoc is readable" \
  || no "egress_gw_probe_silent_sql: heredoc not found — the G2 rows below would be vacuous"

# Whole-window scalar: one value per window = DISTINCT emitting hosts. The two
# pieces are BOTH load-bearing: count(DISTINCT host_name) without the scalar
# head would still bucket by time; the scalar head without DISTINCT would still
# count rows, where one host's beats mask the other's silence.
sql_has "$SILENT_SQL" "SELECT toDateTime\(\{\{end_time\}\}\) AS time, count\(DISTINCT JSONExtractString\(raw, 'host_name'\)\) AS value" \
  && ok "G2: silence counts DISTINCT host_name (one host's beats cannot mask the other)" \
  || no "G2: the silent predicate is not count(DISTINCT JSONExtractString(raw,'host_name')) — the host-mask defect is back"
! sql_has "$SILENT_SQL" "GROUP BY" \
  && ok "G2: silence predicate is a whole-window scalar (no GROUP BY)" \
  || no "G2: GROUP BY reintroduced — per-bucket counts regress to row-masking"
sql_has "$SILENT_SQL" "JSONExtractString\(raw, 'SYSLOG_IDENTIFIER'\) = 'egress-gw-probe'" \
  && ok "G2: silence keeps the egress-gw-probe tag conjunct" \
  || no "G2: the SYSLOG_IDENTIFIER='egress-gw-probe' conjunct is missing"
[ "$(printf '%s' "$SILENT_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')" = "SELECT toDateTime({{end_time}}) AS time, count(DISTINCT JSONExtractString(raw, 'host_name')) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'" ] \
  && ok "G2: silent predicate is byte-exact (whole-window scalar, DISTINCT host_name, tag conjunct)" \
  || no "G2: silent predicate drifted from the pinned text"
param "$SILENT_ALERT" 'operator' '"lower_than"' \
  && param "$SILENT_ALERT" 'value' 'length\(var\.web_hosts\)' \
  && ok "G2: silence fires when emitting hosts < the fleet roster (length(var.web_hosts))" \
  || no "G2: the silent alert is not lower_than length(var.web_hosts) — a literal count decouples from fleet growth, a row count reintroduces masking"
param "$SILENT_ALERT" 'on_missing_data' '"treat_as_zero"' \
  && param "$SILENT_ALERT" 'paused' 'false' \
  && param "$SILENT_ALERT" 'email' 'true' \
  && ok "G2: silence keeps treat_as_zero / unpaused / email (absence pages)" \
  || no "G2: the silent alert lost treat_as_zero, is paused, or stopped emailing"
[ "$(printf '%s\n' "$SILENT_ALERT" | grep -c 'paused')" -eq 1 ] \
  && ok "G2: the string 'paused' occurs exactly once in the silent alert block (a commented or duplicated decoy counts)" \
  || no "G2: 'paused' occurs !=1 time in the silent alert block — a commented pinned-line decoy exists"
param "$SILENT_EXPL" 'sql_query' 'replace\(trimspace\(local\.egress_gw_probe_silent_sql\), "/\\\\s\+/", " "\)' \
  && param "$SILENT_EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "G2: silent exploration carries its own local + the prd source" \
  || no "G2: silent exploration's sql_query or source drifted"
param "$SILENT_ALERT" 'exploration_id' 'logtail_exploration\.egress_gw_probe_silent\.id' \
  && ok "G2: silent alert watches ITS OWN exploration" \
  || no "G2: silent alert's exploration_id re-pointed"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_probe_silent \\$' <<< "$APPLY_JOB" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_probe_silent \\$' <<< "$APPLY_JOB" \
  && ok "G2: both silent -target lines in the apply allowlist" \
  || no "G2: a silent -target line is missing"

# ── G3: egress_gw_probe_fail — the previously-Sentry-only verdict failure ────────────────
FAIL_SQL="$(sql_local egress_gw_probe_fail_sql)"
FAIL_ALERT="$(res_block logtail_exploration_alert egress_gw_probe_fail)"
FAIL_EXPL="$(res_block logtail_exploration egress_gw_probe_fail)"

[ -n "$FAIL_SQL" ] \
  && ok "G3: egress_gw_probe_fail_sql heredoc is readable" \
  || no "egress_gw_probe_fail_sql: heredoc not found — the G3 rows below would be vacuous"
sql_has "$FAIL_SQL" "JSONExtractString\(raw, 'SYSLOG_IDENTIFIER'\) = 'egress-gw-probe'" \
  && ok "G3: fail predicate is scoped to the egress-gw-probe tag" \
  || no "G3: fail predicate lost the SYSLOG_IDENTIFIER conjunct"
sql_has "$FAIL_SQL" "position\(JSONExtractString\(raw, 'message'\), 'result=fail'\) > 0" \
  && ok "G3: fail predicate carries the result=fail arm (wrong verdict pages)" \
  || no "G3: the result=fail arm is missing — a deny_bypassed would not page"
sql_has "$FAIL_SQL" "position\(JSONExtractString\(raw, 'message'\), 'reason=gw_absent'\) > 0" \
  && ok "G3: fail predicate carries the reason=gw_absent arm (gateway missing pages)" \
  || no "G3: the reason=gw_absent arm is missing — a vanished gateway reads as ordinary skip"
# The OR is load-bearing and scoped: it must sit INSIDE the conjunct parens so
# the tag still binds both arms. A top-level OR would let any row page.
sql_has "$FAIL_SQL" "OR position\(JSONExtractString\(raw, 'message'\), 'reason=gw_absent'\) > 0" \
  && ok "G3: gw_absent joins result=fail by OR inside the conjunct" \
  || no "G3: the OR structure changed — verify the tag conjunct still binds both arms"
[ "$(printf '%s' "$FAIL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')" = "SELECT toDateTime({{end_time}}) AS time, count(*) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe' AND (position(JSONExtractString(raw, 'message'), 'result=fail') > 0 OR position(JSONExtractString(raw, 'message'), 'reason=gw_absent') > 0)" ] \
  && ok "G3: fail predicate is byte-exact (tag conjunct, both OR arms, whole-window scalar)" \
  || no "G3: fail predicate drifted from the pinned text"
! sql_has "$FAIL_SQL" "GROUP BY" \
  && ok "G3: fail predicate is a whole-window scalar (no GROUP BY)" \
  || no "G3: fail predicate carries GROUP BY — bucket semantics changed"
[ -n "$FAIL_ALERT" ] \
  && ok "G3: logtail_exploration_alert.egress_gw_probe_fail exists (exact header)" \
  || no "G3: logtail_exploration_alert.egress_gw_probe_fail is missing"
param "$FAIL_ALERT" 'exploration_id' 'logtail_exploration\.egress_gw_probe_fail\.id' \
  && ok "G3: fail alert watches ITS OWN exploration" \
  || no "G3: fail alert's exploration_id re-pointed"
param "$FAIL_ALERT" 'name' '"soleur-egress-gw-probe-fail-prd"' \
  && param "$FAIL_EXPL" 'name' '"soleur-egress-gw-probe-fail-prd"' \
  && ok "G3: both are named soleur-egress-gw-probe-fail-prd" \
  || no "G3: the fail exploration/alert name drifted"
param "$FAIL_ALERT" 'alert_type' '"threshold"' \
  && param "$FAIL_ALERT" 'operator' '"higher_than"' \
  && param "$FAIL_ALERT" 'value' '0' \
  && ok "G3: fail alert pages on >0 verdict rows in the window" \
  || no "G3: fail alert is not threshold/higher_than/0 — a first fail row would not page"
param "$FAIL_ALERT" 'on_missing_data' '"treat_as_zero"' \
  && param "$FAIL_ALERT" 'paused' 'false' \
  && param "$FAIL_ALERT" 'email' 'true' \
  && param "$FAIL_ALERT" 'call' 'false' \
  && param "$FAIL_ALERT" 'sms' 'false' \
  && param "$FAIL_ALERT" 'critical_alert' 'false' \
  && ok "G3: fail alert keeps the sibling paging semantics (treat_as_zero, unpaused, email-only)" \
  || no "G3: fail alert's paging semantics drifted"
[ "$(printf '%s\n' "$FAIL_ALERT" | grep -c 'paused')" -eq 1 ] \
  && ok "G3: the string 'paused' occurs exactly once in the fail alert block (a commented or duplicated decoy counts)" \
  || no "G3: 'paused' occurs !=1 time in the fail alert block — a commented pinned-line decoy exists"
param "$FAIL_ALERT" 'policy_id' 'var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && param "$FAIL_ALERT" 'team_name' 'var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "G3: fail alert escalation is the free/paid ternary every sibling uses (ADR-218)" \
  || no "G3: fail alert's escalation_target drifted from the sibling ternary"
grep -qF 'Runbook: ${local.egress_gw_runbook_url}' <<< "$FAIL_ALERT" \
  && param "$FAIL_ALERT" 'runbook' 'local\.egress_gw_runbook_url' \
  && ok "G3: fail incident carries the egress-gw runbook URL" \
  || no "G3: fail incident has no clickable runbook URL"
param "$FAIL_EXPL" 'sql_query' 'replace\(trimspace\(local\.egress_gw_probe_fail_sql\), "/\\\\s\+/", " "\)' \
  && param "$FAIL_EXPL" 'values' '\[local\.vector_prd_source_id\]' \
  && ok "G3: fail exploration carries its own local + the prd source" \
  || no "G3: fail exploration's sql_query or source drifted"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_probe_fail \\$' <<< "$APPLY_JOB" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_probe_fail \\$' <<< "$APPLY_JOB" \
  && ok "G3: both fail -target lines in the apply allowlist" \
  || no "G3: a fail -target line is missing — the alert would never apply"

# NEGATIVE row: no count/for_each/lifecycle/ignore_changes token inside ANY resource block.
if [ "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$DENY_EXPL" "$DENY_ALERT" "$SILENT_EXPL" "$SILENT_ALERT" "$FAIL_EXPL" "$FAIL_ALERT" | grep -cE '^[[:space:]]*(count|for_each|lifecycle|ignore_changes)[[:space:]]*[= {]')" -eq 0 ]; then
  ok "no count/for_each/lifecycle/ignore_changes mute knob inside any of the six resource blocks"
else
  no "a count/for_each/lifecycle/ignore_changes token sits inside a resource block — a mute knob the provider would honor silently"
fi

# ── G4: emitter needles + runbook anchor + CI registration ───────────────────────────────
# The alert's needles must be text the resolver actually emits. On the shipped
# file the verdict line is `probe_emit "result=$result …"` (post-delivery) or
# the `logger -t egress-gw-probe "egress_gw_probe result=$result"` it replaced;
# the fail literal is `result=fail;` in the verdict logic and the gw_absent
# literal is the skip emit. Pin the literals + the tagged emit site, not one
# exact line — the emit path has its own guard in cron-egress-firewall.test.sh.
grep -qF 'result=fail' "$CR" \
  && ok "G4: resolver still produces result=fail (the needle exists at the source)" \
  || no "G4: cron-egress-resolve.sh lost 'result=fail' — the alert queries a needle nothing emits"
grep -qF 'reason=gw_absent' "$CR" \
  && ok "G4: resolver still produces reason=gw_absent" \
  || no "G4: cron-egress-resolve.sh lost 'reason=gw_absent'"
grep -qF 'logger -t egress-gw-probe' "$CR" \
  && ok "G4: resolver emits on the egress-gw-probe tag the predicates match" \
  || no "G4: no 'logger -t egress-gw-probe' site — verdicts cannot reach this alert"
# The URL's #fragment must resolve to a heading that GitHub-slugifies to it —
# a loose "any heading mentions Better Stack" check is satisfied by an unrelated
# sibling section while the egress anchor is gone.
ANCHOR_OK="$(python3 - "$RB" <<'PY'
import re, sys
slugs = set()
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"^#+\s+(.*)$", line)
    if not m: continue
    h = m.group(1).strip().lower()
    h = re.sub(r"[^\w\s-]", "", h)
    h = re.sub(r"[\s_]+", "-", h)
    slugs.add(h)
print("yes" if "egress-gateway-better-stack-alerts" in slugs else "no")
PY
)"
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
grep -qE 'egress_gw_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cron-egress-blocked\.md#egress-gateway-better-stack-alerts"' "$TF" \
  && [ "$ANCHOR_OK" = "yes" ] \
  && grep -n 'cron-egress-blocked\.md' <<< "$IV_CODE" >/dev/null \
  && ok "G4: runbook URL + slugified anchor heading + runbook-in-CI-paths chain intact" \
  || no "G4: runbook URL, the egress-gateway-better-stack-alerts anchor heading, or the runbook's path entry in infra-validation.yml drifted"
REG_RUN='        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh'
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "G4: this guard's run line is registered in infra-validation.yml exactly once" \
  || no "G4: run line count is $n_run, want 1 — the suite is unregistered or double-registered"
# Fragments, not literals (#11899): a runtime-composed name ("MUT_""SKIP", a GUARD-fragment
# prefix) or a shell-injection env reaches the step with no literal present — GUARD covers
# EGW_GUARD_* and every sibling's *_GUARD_* axis; MUT_/_SKIP cover MUT_SKIP at either split.
seam_bad=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  printf '%s\n' "$IV_CODE" | grep -nF "$_frag" >/dev/null && seam_bad="$seam_bad ${_frag}-fragment"
done
[ -z "$seam_bad" ] \
  && ok "G4: no muting/shell-injection env fragment (MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS, BASHOPTS) reaches the workflow's executable text" \
  || no "G4: workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"
# The only DYNAMIC channel is a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults: inside
# the enclosing job. The slice is DERIVED from the pinned run line — back to the nearest
# `^  <job-id>:` header, forward to the next or EOF — never a hardcoded job name, and it must
# carry the run line or the ban below would pass vacuously on a misslice.
IV_JOB="$(awk -v run="$REG_RUN" '
  /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { if (inside) exit; n = 0 }
  { buf[++n] = $0 }
  index($0, run) { inside = 1 }
  END { if (inside) for (i = 1; i <= n; i++) print buf[i] }' <<< "$IV_CODE")"
{ [ -n "$IV_JOB" ] && grep -qFx "$REG_RUN" <<< "$IV_JOB"; } \
  && ok "G4: the enclosing-job slice is non-empty and carries the pinned run line (the env-write ban cannot pass vacuously)" \
  || no "G4: the enclosing-job slice is empty or lost the pinned run line — a missliced job-scope ban would grade green"
job_bad=""
printf '%s\n' "$IV_JOB" | grep -nF 'GITHUB_ENV' >/dev/null && job_bad="$job_bad GITHUB_ENV"
printf '%s\n' "$IV_JOB" | grep -nF 'GITHUB_PATH' >/dev/null && job_bad="$job_bad GITHUB_PATH"
printf '%s\n' "$IV_JOB" | grep -nF 'defaults:' >/dev/null && job_bad="$job_bad defaults:"
[ -n "$IV_JOB" ] && [ -z "$job_bad" ] \
  && ok "G4: no GITHUB_ENV/GITHUB_PATH write or defaults: sits inside the enclosing job (the only dynamic env channel)" \
  || no "G4: job-scope seam violated:${job_bad:- empty-slice} — a runtime env write inside the job can carry a composed name past the literal seam"

echo ""
echo "=== egress-gw-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching EGW_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t egressgwalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade a broken invocation as "mutation RED".
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
def egw_replace(s, old, new):
    # Occurrence AFTER the fail local'"'"'s opening line, when a needle could
    # legitimately appear in an earlier local (silent'"'"'s tag conjunct).
    i = s.index("  egress_gw_probe_fail_sql = <<\x2dSQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
FAILLOC = "  egress_gw_probe_fail_sql = <<\x2dSQL"
SILLOC = "  egress_gw_probe_silent_sql = <<\x2dSQL"
SQLEND = "\n  SQL\n"
FAILRES = "resource \"logtail_exploration_alert\" \"egress_gw_probe_fail\" {"
SILRES = "resource \"logtail_exploration_alert\" \"egress_gw_probe_silent\" {"'

  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|RB|CR|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      RB)  src="$RB";  copy="$MUT_DIR/cron-egress-blocked.md" ;;
      CR)  src="$CR";  copy="$MUT_DIR/cron-egress-resolve.sh" ;;
      IV)  src="$IV";  copy="$MUT_DIR/infra-validation.yml" ;;
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
    env "EGW_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  mutate_green() {
    local label="$1" which="$2" prog="$3" src copy rc=0
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      IV)  src="$IV";  copy="$MUT_DIR/infra-validation.yml" ;;
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
    env "EGW_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
    case "$rc" in
      0) ok "must-PASS stays green: $label" ;;
      1) no "legitimate edit went RED: $label" ;;
      *) no "must-PASS UNRESOLVED (inner rc=$rc): $label - instrument, not evidence" ;;
    esac
  }

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
  mutate_red "a /* */-wrapped decoy heredoc sits before the fail local while the live body is gutted" TF \
    's = edit(s, FAILLOC, "count(*) AS value", "count(*) * 0 AS value", SQLEND)
i = s.index(FAILLOC)
s = s[:i] + "/*\n  egress_gw_probe_fail_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a #-commented decoy opener line sits above the silent local" TF \
    'i = s.index(SILLOC)
s = s[:i] + "  # egress_gw_probe_silent_sql = <<\x2dSQL\n" + s[i:]' \
    "decoy local exists"
  mutate_red "a commented-out paused=false decoy line appears inside the fail alert block" TF \
    's = edit(s, FAILRES, "  paused = false\n", "  paused = false\n  # paused = false\n")' \
    "decoy exists"
  mutate_red "an inline tautology is appended inside the deny predicate" TF \
    'i = s.index("  egress_gw_deny_spike_sql = <<\x2dSQL"); j = s.index(SQLEND, i)
blk = s[i:j]
old = "GROUP BY time"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "GROUP BY time OR 1=1") + s[j:]' \
    "drifted from the pinned"
  mutate_red "the live silent local is gutted to a placeholder while the resource keeps its name" TF \
    'i = s.index(SILLOC); j = s.index(SQLEND, i)
blk = s[i:j]
assert "count(DISTINCT" in blk
s = s[:i] + "    SELECT 1\n" + s[j:]' \
    "drifted from the pinned"

  # ── Silent-alert rows ──────────────────────────────────────────────────────────────────────
  mutate_red "silent: DISTINCT host_name regresses to count(*) (the host-mask defect)" TF \
    'old = "count(DISTINCT JSONExtractString(raw, \x27host_name\x27)) AS value"
assert s.count(old) == 1
s = s.replace(old, "count(*) AS value")' \
    "host-mask defect"
  mutate_red "silent: GROUP BY time reintroduced (per-bucket row counts again)" TF \
    'old = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n  SQL\n\n  # Verdict failures"
assert s.count(old) == 1
s = s.replace(old, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n    GROUP BY time\n  SQL\n\n  # Verdict failures")' \
    "GROUP BY reintroduced"
  mutate_red "silent: threshold pinned to a literal 1 (fleet growth silently detaches it)" TF \
    's = edit(s, SILRES, "value               = length(var.web_hosts)", "value               = 1")' \
    "literal count"
  mutate_red "silent: operator flipped to higher_than (a healthy fleet pages)" TF \
    's = edit(s, SILRES, "operator            = \"lower_than\"", "operator            = \"higher_than\"")' \
    "lower_than"

  # ── Fail-alert rows ────────────────────────────────────────────────────────────────────────
  mutate_red "fail: the tag conjunct dropped (any row would page)" TF \
    's = egw_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n", "")' \
    "SYSLOG_IDENTIFIER conjunct"
  mutate_red "fail: result=fail arm dropped (wrong verdicts no longer page)" TF \
    's = egw_replace(s, "position(JSONExtractString(raw, \x27message\x27), \x27result=fail\x27) > 0\n", "position(JSONExtractString(raw, \x27message\x27), \x27result=ok\x27) > 0\n")' \
    "drifted from the pinned"
  mutate_red "fail: reason=gw_absent arm dropped (gateway-missing reads as ordinary skip)" TF \
    's = egw_replace(s, "position(JSONExtractString(raw, \x27message\x27), \x27reason=gw_absent\x27) > 0", "position(JSONExtractString(raw, \x27message\x27), \x27reason=budget\x27) > 0")' \
    "drifted from the pinned"
  mutate_red "fail: alert paused" TF \
    's = edit(s, FAILRES, "  paused = false\n", "  paused = true\n")' \
    "paging semantics drifted"
  mutate_red "fail: on_missing_data no longer treat_as_zero" TF \
    's = edit(s, FAILRES, "on_missing_data     = \"treat_as_zero\"", "on_missing_data     = \"keep_last_value\"")' \
    "paging semantics drifted"
  mutate_red "fail: threshold 0 -> 1 (a single deny_bypassed row would not page)" TF \
    's = edit(s, FAILRES, "value               = 0\n", "value               = 1\n")' \
    "threshold/higher_than/0"
  mutate_red "fail: alert watches another exploration" TF \
    'old = "  exploration_id = logtail_exploration.egress_gw_probe_fail.id"
assert s.count(old) == 1
s = s.replace(old, "  exploration_id = logtail_exploration.egress_gw_probe_silent.id")' \
    "re-pointed"
  mutate_red "fail: exploration dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target line is missing"
  mutate_red "fail: alert dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.egress_gw_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "-target line is missing"

  # ── Emitter / runbook rows ────────────────────────────────────────────────────────────────
  mutate_red "emitter: resolver loses the reason=gw_absent literal" CR \
    's = s.replace("reason=gw_absent", "reason=gw_missing")' \
    "reason=gw_absent"
  mutate_red "emitter: resolver loses the tagged emit (verdicts ship under a non-allowlisted identifier)" CR \
    's = s.replace("logger -t egress-gw-probe", "logger -t cron-egress-resolve")' \
    "egress-gw-probe"
  mutate_red "runbook: the egress anchor heading renamed (incident links 404 to the section)" RB \
    'old = "### Egress gateway (Better Stack alerts)"
assert s.count(old) == 1
s = s.replace(old, "### Egress gateway (native log alerts)")' \
    "anchor heading"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "an EGW_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          EGW_GUARD_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "a runtime-composed MUT_SKIP name reaches the workflow (no literal present)" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"MUT_\"\"SKIP=1\" >> \"$GITHUB_ENV\"\n")' \
    "workflow seam"
  mutate_red "a GUARD-fragmented env name reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          FOO_GUARD_X: /dev/null\n")' \
    "workflow seam"
  mutate_red "a BASH_ENV shell-injection env reaches the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          BASH_ENV: /tmp/x\n")' \
    "workflow seam"
  mutate_red "a GITHUB_ENV write inside the suite's own job (the only dynamic env channel)" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"FOO=1\" >> \"$GITHUB_ENV\"\n")' \
    "job-scope seam violated"
  mutate_green "the same GITHUB_ENV write lands in the plan: job (another job's writes are out of scope)" IV \
    'old = "  plan:\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"FOO=1\" >> \"$GITHUB_ENV\"\n")'
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"

  mutate_red "the count = 0 mute knob is added inside the fail alert resource" TF \
    's = edit(s, FAILRES, "  paused = false\n", "  count = 0\n  paused = false\n")' \
    "mute knob"

  # ── Scorer negative control ────────────────────────────────────────────────────────────────
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    's = edit(s, FAILRES, "  paused = false\n", "  paused = true\n")' \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "a comment-only edit to the tf" TF \
    's = s + "\n# control comment\n"'
  mutate_green "whitespace reflow of the deny heredoc" TF \
    'i = s.index("  egress_gw_deny_spike_sql = <<\x2dSQL"); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\n      AND position("
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, " AND\n          position(") + s[j:]'

  echo ""
  echo "=== egress-gw-alert guard + mutations: $pass passed, $fail failed ==="
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# Floor self-reference (accepted residual, #11899): a row-count decrement landing alongside a
# row deletion stays green — each constant is two-write-site (here + the floor row's sed anchor).
PRESENCE_ROWS=56
MUT_ROWS=34
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); EGW_GUARD_{TF,WF,RB,CR,IV}=%s,%s,%s,%s,%s\n' "$_floor" "${EGW_GUARD_TF:-unset}" "${EGW_GUARD_WF:-unset}" "${EGW_GUARD_RB:-unset}" "${EGW_GUARD_CR:-unset}" "${EGW_GUARD_IV:-unset}"
printf '\n=== egress-gw-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
