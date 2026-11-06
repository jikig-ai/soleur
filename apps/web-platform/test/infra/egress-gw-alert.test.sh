#!/usr/bin/env bash
#
# Drift guard for the egress-gateway Better Stack Logs alerts
# (apps/web-platform/infra/betterstack-logs-alerts.tf):
#   * logtail_exploration_alert.egress_gw_deny_spike   (#9534)
#   * logtail_exploration_alert.egress_gw_probe_silent (#9534, host-attributed 2026-10-12,
#     inverted to a missing-host count 2026-11-05, #12180)
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
#     scalar (toDateTime({{end_time}}) AS time, NO GROUP BY) whose value is the
#     number of roster hosts that did NOT emit, greatest(toInt64(roster) -
#     toInt64(count(DISTINCT host_name)), 0), threshold higher_than 0. Dropping
#     DISTINCT, the floor or the casts, re-adding GROUP BY, pinning a literal
#     roster size, or flipping back to lower_than all red. The metric is
#     inverted so an evaluator step that reads 0 (INFERRED zero-fill, #12180)
#     reads healthy instead of paging; the query is proven, the evaluator is not.
#   * The #12180 throwaway canary pair (the same query against an identifier no host
#     emits) fired on 2026-11-06 and was retired by #12189; the exact-count row (G2c)
#     is what keeps a second egress_gw_probe_silent* pair from coming back.
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
PR="${EGW_GUARD_PR:-$REPO/scripts/followthroughs/egress-gw-probe-silent-12180.sh}"

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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$RB"; assert_fixture_dir "$CR"; assert_fixture_dir "$IV"; assert_fixture_dir "$PR"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the mutation battery needs it
' >&2; exit 2; }
for f in "$TF" "$WF" "$RB" "$CR" "$IV" "$PR"; do
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

# Whole-window scalar: one value per window = the number of roster hosts that did NOT emit
# (#12180). The pieces are ALL load-bearing: count(DISTINCT host_name) without the scalar head
# would still bucket by time; the scalar head without DISTINCT would count rows, where one host's
# beats mask the other's silence; the greatest(..., 0) floor and the toInt64 casts stop an
# unsigned wrap (ClickHouse count() is unsigned) when more hosts emit than the roster names.
sql_has "$SILENT_SQL" "SELECT toDateTime\(\{\{end_time\}\}\) AS time, greatest\(toInt64\(\\\$\{length\(var\.web_hosts\)\}\) - toInt64\(count\(DISTINCT JSONExtractString\(raw, 'host_name'\)\)\), 0\) AS value" \
  && ok "G2: silence reports the MISSING-host count (roster - DISTINCT host_name, floored at 0)" \
  || no "G2: the silent predicate is not greatest(toInt64(roster) - toInt64(count(DISTINCT host_name)), 0) — the metric regressed or the host-mask defect is back"
! sql_has "$SILENT_SQL" "GROUP BY" \
  && ok "G2: silence predicate is a whole-window scalar (no GROUP BY)" \
  || no "G2: GROUP BY reintroduced — per-bucket counts regress to row-masking"
sql_has "$SILENT_SQL" "JSONExtractString\(raw, 'SYSLOG_IDENTIFIER'\) = 'egress-gw-probe'" \
  && ok "G2: silence keeps the egress-gw-probe tag conjunct" \
  || no "G2: the SYSLOG_IDENTIFIER='egress-gw-probe' conjunct is missing"
SILENT_FLAT="$(printf '%s' "$SILENT_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
[ "$SILENT_FLAT" = "SELECT toDateTime({{end_time}}) AS time, greatest(toInt64(\${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, 'host_name'))), 0) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'" ] \
  && ok "G2: silent predicate is byte-exact (whole-window scalar, floored missing-host count, interpolated roster, tag conjunct)" \
  || no "G2: silent predicate drifted from the pinned text"
param "$SILENT_ALERT" 'operator' '"higher_than"' \
  && param "$SILENT_ALERT" 'value' '0' \
  && ok "G2: silence fires when at least one roster host is missing (higher_than 0)" \
  || no "G2: the silent alert is not higher_than 0 — a lower_than shape pages on a zero-filled evaluator step; a raised value lets a dead host through"
param "$SILENT_ALERT" 'on_missing_data' '"treat_as_zero"' \
  && param "$SILENT_ALERT" 'paused' 'false' \
  && param "$SILENT_ALERT" 'email' 'true' \
  && ok "G2: silence keeps treat_as_zero (CTO ruling) / unpaused / email" \
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
param "$SILENT_ALERT" 'name' '"soleur-egress-gw-probe-silent-prd"' \
  && param "$SILENT_EXPL" 'name' '"soleur-egress-gw-probe-silent-prd"' \
  && ok "G2: the production alert and its exploration are named soleur-egress-gw-probe-silent-prd (the name the soak probe matches)" \
  || no "G2: the production silent alert or exploration name drifted — the soak probe matches incidents on it exactly"
param "$SILENT_ALERT" 'alert_type' '"threshold"' \
  && param "$SILENT_ALERT" 'check_period' '300' \
  && param "$SILENT_ALERT" 'query_period' '900' \
  && param "$SILENT_ALERT" 'confirmation_period' '0' \
  && param "$SILENT_ALERT" 'recovery_period' '900' \
  && param "$SILENT_ALERT" 'push' 'false' \
  && param "$SILENT_ALERT" 'call' 'false' \
  && param "$SILENT_ALERT" 'sms' 'false' \
  && param "$SILENT_ALERT" 'critical_alert' 'false' \
  && ok "G2: the production alert's windows (300/900/0/900) and channels (email only) are pinned" \
  || no "G2: the production silent alert's windows or channels drifted (a changed confirmation_period delays or swallows the page)"
# Every .tf under the infra dir, comments dropped: a consumer in a SECOND file counts the same as one in the first.
ALL_TF="$(cat "$(dirname "$TF")"/*.tf 2>/dev/null | grep -vE '^[[:space:]]*(#|//)' || true)"
[ "$(grep -cE '^[[:space:]]*exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.egress_gw_probe_silent\.id' <<< "$ALL_TF")" -eq 1 ] \
  && [ "$(grep -c 'local\.egress_gw_probe_silent_sql' <<< "$ALL_TF")" -eq 1 ] \
  && ok "G2: exactly one alert watches the production exploration, and the production SQL local has exactly one consumer (that exploration)" \
  || no "G2: a second alert watches the production exploration, or a second consumer reads the production SQL local (any .tf under the infra dir)"
param "$SILENT_EXPL" 'team_name' '"Your team"' \
  && param "$SILENT_EXPL" 'chart_type' '"line_chart"' \
  && param "$SILENT_EXPL" 'query_type' '"sql_expression"' \
  && param "$SILENT_EXPL" 'source_variable' '"source"' \
  && param "$SILENT_EXPL" 'variable_type' '"source"' \
  && [ "$(printf '%s\n' "$SILENT_EXPL" | grep -cE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"source"[[:space:]]*$')" -eq 1 ] \
  && ok "G2: the production exploration's remaining attributes (team, chart, query type, source variable) are pinned" \
  || no "G2: the production exploration's team_name, chart_type, query_type, source_variable or variable block drifted"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_probe_silent \\$' <<< "$APPLY_JOB" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_probe_silent \\$' <<< "$APPLY_JOB" \
  && ok "G2: both silent -target lines in the apply allowlist" \
  || no "G2: a silent -target line is missing"
grep -qF 'The INFERRED mechanism is that' <<< "$SILENT_ALERT" \
  && ok "G2: the alert block labels the zero-fill mechanism INFERRED (the query is proven, the evaluator is not)" \
  || no "G2: the silent alert block no longer labels the evaluator zero-fill mechanism INFERRED"

# The soak probe matches incidents on exact alert names and reads the emitter tag: each literal is assigned EXACTLY ONCE at
# column 0 and equals the Terraform value (a later re-assignment would otherwise win at run time).
probe_lit() { [ "$(grep -cE "^$1=" "$PR")" -eq 1 ] && sed -nE "s/^$1=\"([^\"]*)\".*/\1/p" "$PR"; }
[ "$(probe_lit PROD_NAME)" = "soleur-egress-gw-probe-silent-prd" ] \
  && [ "$(probe_lit EMITTER_TAG)" = "egress-gw-probe" ] \
  && sql_has "$SILENT_SQL" "JSONExtractString\(raw, 'SYSLOG_IDENTIFIER'\) = '$(probe_lit EMITTER_TAG)'" \
  && ok "G2b: the soak probe's PROD_NAME / EMITTER_TAG are each assigned once and equal the Terraform values" \
  || no "G2b: the soak probe's alert-name or emitter-tag literals drifted (or are assigned more than once) — it would match no incident and close its tracker over a live recurrence"

# Exact count: the structure suite's resource-count rows are FLOORS and rows 9-10 pass for an extra pair that
# brings its own exploration, so a stray second egress_gw_probe_silent* pair (the retired #12180 canary re-added
# under that label prefix) is only visible here; the label-agnostic block count is EXPECT_BLOCKS in the ceiling suite.
[ "$(grep -cE '^resource "logtail_exploration(_alert)?" "egress_gw_probe_silent[A-Za-z0-9_]*" \{' <<< "$ALL_TF")" -eq 2 ] \
  && [ "$(grep -cE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"soleur-egress-gw-probe-silent' <<< "$ALL_TF")" -eq 2 ] \
  && ok "G2c: exactly two egress_gw_probe_silent* resources (the production pair; the #12180 canary pair is retired)" \
  || no "G2c: the egress_gw_probe_silent* resource count is not 2, or the name literal count is not 2 — a second egress_gw_probe_silent* pair (the retired canary re-added under that label prefix, in any .tf) exists, or one is missing; a pair under a different label is caught by the label-agnostic EXPECT_BLOCKS=18 in logs-alert-query-period-ceiling.test.sh"

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
# A CI-dead guard must not pass (the clientip idiom, #11899). The step's allowed keys are
# name + run ONLY — an `env:`, `shell:`, `with:`, `if:` or `continue-on-error:` can neuter or
# redirect the run — at EITHER step position (the `      - ` dash line or an `        ` key
# line). The HOSTING JOB is derived from the step's position (the last `jobs:`-level header
# above the run line — a trailing-comment or quoted-id header included), never named here,
# and is read WHOLE: header, steps AND any keys after `steps:` (YAML key order is free, so a
# post-steps key must grade). Its `^    if:` must occur exactly once and equal the known
# literal, `^    continue-on-error:` zero times over the whole block, needs/runs-on the known
# literals, and its own keys only the known set (no `env`, `defaults`, `container`,
# `strategy`, `services` ...).
# hdr LINE -> the job id when LINE is a `jobs:`-level key header (`  id:`, `  "id":`,
# `  id: # note`), else "".
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
JOB_IF_N="$(awk '/^    if:/ { n++ } END { print n + 0 }' <<<"$JOB_BLOCK")"
JOB_COE_N="$(awk '/^    continue-on-error:/ { n++ } END { print n + 0 }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Any other key —
# or an unrecognised line shape, which grades "?" — is listed.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
{ [ -n "$STEP_BLOCK" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && grep -qFx "$REG_RUN" <<< "$JOB_BLOCK"; } \
  && ok "G4: the registered step and its hosting job '$HOST_JOB' were located (run-line-derived, comment-stripped, the slice carries the run line)" \
  || no "G4: the registered step or its hosting job could not be located (step ${#STEP_BLOCK}B, host '${HOST_JOB:-none}', job ${#JOB_BLOCK}B) — every step/job pin below would grade vacuous"
[ -n "$STEP_BLOCK" ] && [ -z "$STEP_BAD" ] \
  && [[ "$STEP_BLOCK" != *continue-on-error* ]] \
  && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] \
  && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
  && ok "G4: the registered step has only name+run keys — no env/shell/with/if:/continue-on-error: at the run-key or - dash position" \
  || no "G4: the registered step is conditional, non-blocking or redirected (offending keys beyond name+run: '${STEP_BAD//$'\n'/ }'; an if: or continue-on-error: at the run-key or - dash position), or the step could not be located"
[ -n "$JOB_BLOCK" ] && [ -z "$JOB_BAD" ] \
  && [ "$JOB_IF_N" -eq 1 ] && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
  && [ "$JOB_COE_N" -eq 0 ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] \
  && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ] \
  && ok "G4: the hosting job '$HOST_JOB' keeps the one known if:, the needs+runs-on literals, the known key set and no continue-on-error anywhere (post-steps keys grade)" \
  || no "G4: the hosting job '$HOST_JOB' is conditional, non-blocking or carries keys beyond name/needs/if/runs-on/permissions/timeout-minutes/steps: '${JOB_BAD//$'\n'/ }' (^    if: lines seen: $JOB_IF_N, want 1 and the known literal; ^    continue-on-error: lines seen: $JOB_COE_N, want 0 over the WHOLE job — post-steps keys included; needs/runs-on differ), or the job could not be located"
# File-wide seam (over the comment-stripped workflow view): guard env axes may not reach
# executable text. Fragments, not literals (#11899): a runtime-composed name ("MUT_""SKIP",
# a GUARD-fragment prefix) or a shell-injection env reaches the step with no literal present
# — MUT_/_SKIP cover MUT_SKIP at either split, GUARD covers EGW_GUARD_* and every sibling's
# *_GUARD_* axis; EGW_ stays literal so a future EGW_* seam carrying no GUARD fragment still
# reds. A top-level `defaults:` block would smuggle run.shell/env into every job — banned.
seam_bad=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS' 'EGW_'; do
  [[ "$IV_CODE" == *"$_frag"* ]] && seam_bad="$seam_bad ${_frag}-fragment"
done
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && seam_bad="$seam_bad top-level-defaults"
[ -z "$seam_bad" ] \
  && ok "G4: no muting/shell-injection env fragment (MUT_, _SKIP, GUARD, EGW_, BASH_ENV, SHELLOPTS, BASHOPTS) or top-level defaults: reaches the workflow's executable text" \
  || no "G4: workflow seam violated:$seam_bad — a guard env axis or a top-level defaults: is reachable from infra-validation.yml"
# The only DYNAMIC channel is a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults:
# inside the HOSTING job. JOB_BLOCK is derived above — an empty slice reds the located row
# and is re-checked here, so the ban cannot pass vacuously on a misslice.
job_bad=""
[[ "$JOB_BLOCK" == *GITHUB_ENV* ]] && job_bad="$job_bad GITHUB_ENV"
[[ "$JOB_BLOCK" == *GITHUB_PATH* ]] && job_bad="$job_bad GITHUB_PATH"
[[ "$JOB_BLOCK" == *defaults:* ]] && job_bad="$job_bad defaults:"
[ -n "$JOB_BLOCK" ] && [ -z "$job_bad" ] \
  && ok "G4: no GITHUB_ENV/GITHUB_PATH write or defaults: sits inside the hosting job '$HOST_JOB' (the only dynamic env channel)" \
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
SILRES = "resource \"logtail_exploration_alert\" \"egress_gw_probe_silent\" {"
SILEXPL = "resource \"logtail_exploration\" \"egress_gw_probe_silent\" {"'

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
      PR)  src="$PR";  copy="$MUT_DIR/egress-gw-probe-silent-12180.sh" ;;
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

  # ── Silent-alert rows (inverted metric, #12180) ────────────────────────────────────────────
  mutate_red "silent: operator reverted to lower_than (a zero-filled evaluator step pages again)" TF \
    's = edit(s, SILRES, "operator            = \"higher_than\"", "operator            = \"lower_than\"")' \
    "higher_than 0"
  mutate_red "silent: value raised from 0 to 1 (one missing host no longer pages)" TF \
    's = edit(s, SILRES, "value               = 0\n", "value               = 1\n")' \
    "higher_than 0"
  mutate_red "silent: the greatest(..., 0) floor dropped (surplus emitters yield a negative or wrapped value)" TF \
    'old = "greatest(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, \x27host_name\x27))), 0) AS value"
assert s.count(old) == 1
s = s.replace(old, "(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, \x27host_name\x27)))) AS value")' \
    "silent predicate"
  mutate_red "silent: the toInt64 casts removed (unsigned count() wraps on a surplus of emitters)" TF \
    'old = "greatest(toInt64(${length(var.web_hosts)}) - toInt64(count(DISTINCT JSONExtractString(raw, \x27host_name\x27))), 0) AS value"
assert s.count(old) == 1
s = s.replace(old, "greatest(${length(var.web_hosts)} - count(DISTINCT JSONExtractString(raw, \x27host_name\x27)), 0) AS value")' \
    "silent predicate"
  mutate_red "silent: the roster interpolation replaced by a literal 2 (fleet growth silently detaches it)" TF \
    'old = "greatest(toInt64(${length(var.web_hosts)}) - toInt64("
assert s.count(old) == 1
s = s.replace(old, "greatest(toInt64(2) - toInt64(")' \
    "silent predicate"
  mutate_red "silent: DISTINCT host_name regresses to count(*) (the host-mask defect)" TF \
    'old = "toInt64(count(DISTINCT JSONExtractString(raw, \x27host_name\x27)))"
assert s.count(old) == 1
s = s.replace(old, "toInt64(count(*))")' \
    "host-mask defect"
  mutate_red "silent: GROUP BY time reintroduced (per-bucket row counts again)" TF \
    'old = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n  SQL\n\n  # Verdict failures"
assert s.count(old) == 1
s = s.replace(old, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n    GROUP BY time\n  SQL\n\n  # Verdict failures")' \
    "GROUP BY reintroduced"
  mutate_red "silent: on_missing_data no longer treat_as_zero (a fully dark window stops evaluating)" TF \
    's = edit(s, SILRES, "on_missing_data     = \"treat_as_zero\"", "on_missing_data     = \"keep_last_value\"")' \
    "lost treat_as_zero"
  mutate_red "silent: alert paused" TF \
    's = edit(s, SILRES, "  paused = false\n", "  paused = true\n")' \
    "lost treat_as_zero"
  mutate_red "silent: the INFERRED label removed from the alert block (the evaluator claim reads as fact)" TF \
    's = edit(s, SILRES, "INFERRED", "established")' \
    "labels the evaluator zero-fill mechanism INFERRED"

  mutate_red "silent: the production alert renamed (the soak probe matches on the name)" TF \
    's = edit(s, SILRES, "name           = \"soleur-egress-gw-probe-silent-prd\"", "name           = \"soleur-egress-gw-probe-silent-v2-prd\"")' \
    "production silent alert or exploration name drifted"
  mutate_red "silent: confirmation_period raised (the page is delayed)" TF \
    's = edit(s, SILRES, "confirmation_period = 0", "confirmation_period = 3600")' \
    "windows or channels drifted"
  mutate_red "silent: query_period shortened (the evaluation window shrinks)" TF \
    's = edit(s, SILRES, "query_period        = 900", "query_period        = 300")' \
    "windows or channels drifted"
  mutate_red "silent: push channel enabled on the production alert" TF \
    's = edit(s, SILRES, "push           = false", "push           = true")' \
    "windows or channels drifted"
  mutate_red "silent: a SECOND alert watching the production exploration is added" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"zz_second\" {\n  exploration_id = logtail_exploration.egress_gw_probe_silent.id\n}\n"' \
    "second alert watches the production exploration"
  mutate_red "silent: recovery_period drifts on the production alert (window pin)" TF \
    's = edit(s, SILRES, "recovery_period     = 900", "recovery_period     = 1800")' \
    "windows or channels drifted"
  mutate_red "probe: the PROD_NAME literal no longer equals the Terraform name" PR \
    's = s.replace("PROD_NAME=\"soleur-egress-gw-probe-silent-prd\"", "PROD_NAME=\"soleur-egress-gw-probe-silent-v2-prd\"")' \
    "alert-name or emitter-tag literals drifted"

  # ── Exact-count rows (G2c): the retired #12180 canary pair coming back under any label ──────
  mutate_red "a SECOND egress_gw_probe_silent* pair is added after the compliant first (exact count)" TF \
    's = s + "\nresource \"logtail_exploration\" \"egress_gw_probe_silent_canary\" {\n}\n\nresource \"logtail_exploration_alert\" \"egress_gw_probe_silent_canary\" {\n}\n"' \
    "resource count is not 2"
  mutate_red "a second alert carrying a soleur-egress-gw-probe-silent name under a different label (name-literal count)" TF \
    's = s + "\nresource \"logtail_exploration_alert\" \"zz_other\" {\n  name = \"soleur-egress-gw-probe-silent-canary-prd\"\n}\n"' \
    "name literal count is not 2"
  mutate_red "silent: the production exploration's variable type drifts" TF \
    's = edit(s, SILEXPL, "variable_type = \"source\"", "variable_type = \"text\"")' \
    "production exploration's team_name, chart_type"
  mutate_red "silent: the production exploration's team drifts" TF \
    's = edit(s, SILEXPL, "team_name = \"Your team\"", "team_name = \"Other team\"")' \
    "production exploration's team_name, chart_type"
  mutate_red "silent: a second consumer of the production SQL local appears in a locals block" TF \
    's = s + "\nlocals {\n  zz_second = local.egress_gw_probe_silent_sql\n}\n"' \
    "second consumer reads the production SQL local"
  mutate_red "probe: a later PROD_NAME re-assignment wins at run time (assigned more than once)" PR \
    's = s + "\nPROD_NAME=\"decoy\"\n"' \
    "alert-name or emitter-tag literals drifted"
  mutate_red "probe: the EMITTER_TAG literal no longer equals the tag the alert reads" PR \
    's = s.replace("EMITTER_TAG=\"egress-gw-probe\"", "EMITTER_TAG=\"egress-gw-probe-v2\"")' \
    "alert-name or emitter-tag literals drifted"

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

  # ── Step/job shape rows (#11899): the clientip idiom — the step's keys are name+run only  #
  # at either position, the hosting job's keys are the known set, `if:` is exactly one known  #
  # literal, and continue-on-error: is absent over the WHOLE job (post-steps keys grade —     #
  # YAML key order is free).                                                                  #
  mutate_red "the registered step gets an env: key (a step-scope redirect needs no if:)" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO: bar\n" + old)' \
    "beyond name+run: 'env"
  mutate_red "the registered step gets an if: key line (a conditional step, key form)" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "beyond name+run: 'if"
  mutate_red "the registered step gets a continue-on-error: key line (a non-blocking step)" IV \
    'old = "        run: bash apps/web-platform/test/infra/egress-gw-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "beyond name+run: 'continue-on-error"
  mutate_red "the registered step is made conditional on the - dash line (- if: false)" IV \
    'old = "      - name: Run egress gateway alerts drift guard (#9534 host-mask + fail paging)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run egress gateway alerts drift guard (#9534 host-mask + fail paging)\n")' \
    "dash position"
  mutate_red "the hosting job gets an env: key (outside the known job key set)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    env:\n      FOO: bar\n")' \
    "steps: 'env'"
  mutate_red "a second, differing if: is added to the hosting job (count != 1 and not the known literal)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    if: false\n")' \
    "if: lines seen"
  mutate_red "a job-level continue-on-error: is placed AFTER the job's steps (key order is free in YAML)" IV \
    'old = "          fi\n\n  # Aggregator (#8736): the single verdict"
assert s.count(old) == 1
s = s.replace(old, "          fi\n    continue-on-error: true\n\n  # Aggregator (#8736): the single verdict")' \
    "continue-on-error: lines seen"
  mutate_red "the workflow gains a top-level defaults: (a run.shell or env default would reach every job)" IV \
    'old = "\nenv:\n  TERRAFORM_VERSION"
assert s.count(old) == 1
s = s.replace(old, "\ndefaults:\n  run:\n    shell: bash\nenv:\n  TERRAFORM_VERSION")' \
    "top-level-defaults"

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
  mutate_green "whitespace reflow of the silent heredoc (still equal after flattening)" TF \
    'i = s.index(SILLOC); j = s.index(SQLEND, i)
blk = s[i:j]
old = "\n    FROM {{source}}"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "\n\n      FROM   {{source}}") + s[j:]'
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
PRESENCE_ROWS=65
MUT_ROWS=63
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
