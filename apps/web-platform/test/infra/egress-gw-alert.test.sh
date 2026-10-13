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
# $TF at `/` — and mutate() below writes to $TF on every row.
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

for f in "$TF" "$WF" "$RB" "$CR" "$IV"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# Whole-line assertions anchored at both ends: a bare substring grep is satisfied by the same text
# inside a comment, or with a suffix that inverts it (`paused = false || true`).
# Every grep reads a HERE-STRING, never `printf … | grep -q`: under pipefail, grep -q exiting on its
# first match can SIGPIPE the writer and fail the pipeline, which fails a negated check OPEN.
line_in() {  # line_in <text> <ERE for the whole line, without anchors>
  grep -qE "^[[:space:]]*$2[[:space:]]*(#.*)?$" <<< "$1"
}
# Extract a <<-SQL heredoc local by name: first line after `name = <<-SQL` to its `  SQL` terminator.
sql_local() {  # sql_local <local-name>
  awk -v n="$1" '
    $0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-SQL" { f=1; next }
    f && /^  SQL$/ { f=0 }
    f { print }
  ' "$TF"
}
# Extract a resource block by exact header to the first column-0 `}`.
block_of() {  # block_of <type> <name>
  awk -v t="$1" -v n="$2" '
    $0 ~ "^resource \"" t "\" \"" n "\" \\{" { f=1 }
    f { print }
    f && /^}/ { exit }
  ' "$TF"
}
sql_has() {  # sql_has <sql-text> <ERE substring>
  grep -qE "$2" <<< "$1"
}

# ── G1: egress_gw_deny_spike (unchanged shape, pinned so the set has one guard) ────────────
DENY_SQL="$(sql_local egress_gw_deny_spike_sql)"
DENY_ALERT="$(block_of logtail_exploration_alert egress_gw_deny_spike)"
DENY_EXPL="$(block_of logtail_exploration egress_gw_deny_spike)"

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
line_in "$DENY_ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$DENY_ALERT" 'value[[:space:]]*=[[:space:]]*20' \
  && ok "G1: deny alert pages higher_than 20" \
  || no "G1: deny alert is not higher_than/20"
line_in "$DENY_EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "G1: deny exploration reads the prd Vector source" \
  || no "G1: deny exploration source is not local.vector_prd_source_id"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_deny_spike \\$' "$WF" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_deny_spike \\$' "$WF" \
  && ok "G1: both deny -target lines in the apply allowlist" \
  || no "G1: a deny -target line is missing — the alert would never apply"

# ── G2: egress_gw_probe_silent — host-attributed (the review fix this guard exists for) ───
SILENT_SQL="$(sql_local egress_gw_probe_silent_sql)"
SILENT_ALERT="$(block_of logtail_exploration_alert egress_gw_probe_silent)"
SILENT_EXPL="$(block_of logtail_exploration egress_gw_probe_silent)"

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
line_in "$SILENT_ALERT" 'operator[[:space:]]*=[[:space:]]*"lower_than"' \
  && line_in "$SILENT_ALERT" 'value[[:space:]]*=[[:space:]]*length\(var\.web_hosts\)' \
  && ok "G2: silence fires when emitting hosts < the fleet roster (length(var.web_hosts))" \
  || no "G2: the silent alert is not lower_than length(var.web_hosts) — a literal count decouples from fleet growth, a row count reintroduces masking"
line_in "$SILENT_ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && line_in "$SILENT_ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && line_in "$SILENT_ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && ok "G2: silence keeps treat_as_zero / unpaused / email (absence pages)" \
  || no "G2: the silent alert lost treat_as_zero, is paused, or stopped emailing"
line_in "$SILENT_EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.egress_gw_probe_silent_sql\), "/\\\\s\+/", " "\)' \
  && line_in "$SILENT_EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "G2: silent exploration carries its own local + the prd source" \
  || no "G2: silent exploration's sql_query or source drifted"
line_in "$SILENT_ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.egress_gw_probe_silent\.id' \
  && ok "G2: silent alert watches ITS OWN exploration" \
  || no "G2: silent alert's exploration_id re-pointed"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_probe_silent \\$' "$WF" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_probe_silent \\$' "$WF" \
  && ok "G2: both silent -target lines in the apply allowlist" \
  || no "G2: a silent -target line is missing"

# ── G3: egress_gw_probe_fail — the previously-Sentry-only verdict failure ────────────────
FAIL_SQL="$(sql_local egress_gw_probe_fail_sql)"
FAIL_ALERT="$(block_of logtail_exploration_alert egress_gw_probe_fail)"
FAIL_EXPL="$(block_of logtail_exploration egress_gw_probe_fail)"

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
! sql_has "$FAIL_SQL" "GROUP BY" \
  && ok "G3: fail predicate is a whole-window scalar (no GROUP BY)" \
  || no "G3: fail predicate carries GROUP BY — bucket semantics changed"
[ -n "$FAIL_ALERT" ] \
  && ok "G3: logtail_exploration_alert.egress_gw_probe_fail exists (exact header)" \
  || no "G3: logtail_exploration_alert.egress_gw_probe_fail is missing"
line_in "$FAIL_ALERT" 'exploration_id[[:space:]]*=[[:space:]]*logtail_exploration\.egress_gw_probe_fail\.id' \
  && ok "G3: fail alert watches ITS OWN exploration" \
  || no "G3: fail alert's exploration_id re-pointed"
line_in "$FAIL_ALERT" 'name[[:space:]]*=[[:space:]]*"soleur-egress-gw-probe-fail-prd"' \
  && line_in "$FAIL_EXPL" 'name[[:space:]]*=[[:space:]]*"soleur-egress-gw-probe-fail-prd"' \
  && ok "G3: both are named soleur-egress-gw-probe-fail-prd" \
  || no "G3: the fail exploration/alert name drifted"
line_in "$FAIL_ALERT" 'alert_type[[:space:]]*=[[:space:]]*"threshold"' \
  && line_in "$FAIL_ALERT" 'operator[[:space:]]*=[[:space:]]*"higher_than"' \
  && line_in "$FAIL_ALERT" 'value[[:space:]]*=[[:space:]]*0' \
  && ok "G3: fail alert pages on >0 verdict rows in the window" \
  || no "G3: fail alert is not threshold/higher_than/0 — a first fail row would not page"
line_in "$FAIL_ALERT" 'on_missing_data[[:space:]]*=[[:space:]]*"treat_as_zero"' \
  && line_in "$FAIL_ALERT" 'paused[[:space:]]*=[[:space:]]*false' \
  && line_in "$FAIL_ALERT" 'email[[:space:]]*=[[:space:]]*true' \
  && line_in "$FAIL_ALERT" 'call[[:space:]]*=[[:space:]]*false' \
  && line_in "$FAIL_ALERT" 'sms[[:space:]]*=[[:space:]]*false' \
  && line_in "$FAIL_ALERT" 'critical_alert[[:space:]]*=[[:space:]]*false' \
  && ok "G3: fail alert keeps the sibling paging semantics (treat_as_zero, unpaused, email-only)" \
  || no "G3: fail alert's paging semantics drifted"
line_in "$FAIL_ALERT" 'policy_id[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null' \
  && line_in "$FAIL_ALERT" 'team_name[[:space:]]*=[[:space:]]*var\.betterstack_paid_tier \? null : "Your team"' \
  && ok "G3: fail alert escalation is the free/paid ternary every sibling uses (ADR-218)" \
  || no "G3: fail alert's escalation_target drifted from the sibling ternary"
grep -qF 'Runbook: ${local.egress_gw_runbook_url}' <<< "$FAIL_ALERT" \
  && line_in "$FAIL_ALERT" 'runbook[[:space:]]*=[[:space:]]*local\.egress_gw_runbook_url' \
  && ok "G3: fail incident carries the egress-gw runbook URL" \
  || no "G3: fail incident has no clickable runbook URL"
line_in "$FAIL_EXPL" 'sql_query[[:space:]]*=[[:space:]]*replace\(trimspace\(local\.egress_gw_probe_fail_sql\), "/\\\\s\+/", " "\)' \
  && line_in "$FAIL_EXPL" 'values[[:space:]]*=[[:space:]]*\[local\.vector_prd_source_id\]' \
  && ok "G3: fail exploration carries its own local + the prd source" \
  || no "G3: fail exploration's sql_query or source drifted"
grep -qE '^[[:space:]]*-target=logtail_exploration\.egress_gw_probe_fail \\$' "$WF" \
  && grep -qE '^[[:space:]]*-target=logtail_exploration_alert\.egress_gw_probe_fail \\$' "$WF" \
  && ok "G3: both fail -target lines in the apply allowlist" \
  || no "G3: a fail -target line is missing — the alert would never apply"

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
grep -qE 'egress_gw_runbook_url[[:space:]]*=[[:space:]]*"https://github\.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cron-egress-blocked\.md#egress-gateway-better-stack-alerts"' "$TF" \
  && [ "$ANCHOR_OK" = "yes" ] \
  && grep -n 'cron-egress-blocked\.md' "$IV" >/dev/null \
  && ok "G4: runbook URL + slugified anchor heading + runbook-in-CI-paths chain intact" \
  || no "G4: runbook URL, the egress-gateway-better-stack-alerts anchor heading, or the runbook's path entry in infra-validation.yml drifted"
grep -qF 'bash apps/web-platform/test/infra/egress-gw-alert.test.sh' "$IV" \
  && ok "G4: this guard is registered as an infra-validation step (unregistered = never runs)" \
  || no "G4: egress-gw-alert.test.sh is not run by infra-validation.yml"

echo ""
echo "=== egress-gw-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
if [ "$pass" -lt 30 ]; then
  printf '[FAIL] guard is vacuous: only %d rows ran (expected >=30)\n' "$pass" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching EGW_GUARD_* override pointing at the copy.
SELF="${BASH_SOURCE[0]}"
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

  mutate() {  # mutate <want: RED|PASS> <label> <TF|WF|RB|CR> <python-program-on-s>
    local want="$1" label="$2" which="$3" prog="$4" src copy rc=0
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      RB)  src="$RB";  copy="$MUT_DIR/cron-egress-blocked.md" ;;
      CR)  src="$CR";  copy="$MUT_DIR/cron-egress-resolve.sh" ;;
      *) printf '[FATAL] mutate: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def egw_replace(s, old, new):
    # Occurrence AFTER the fail local's opening line, when a needle could
    # legitimately appear in an earlier local (silent's tag conjunct).
    i = s.index("  egress_gw_probe_fail_sql = <<-SQL")
    j = s.index(old, i)
    return s[:j] + new + s[j + len(old):]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    case "$which" in
      TF)  EGW_GUARD_TF="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      WF)  EGW_GUARD_WF="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      RB)  EGW_GUARD_RB="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      CR)  EGW_GUARD_CR="$copy"  MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
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

  mutate RED "silent: DISTINCT host_name regresses to count(*) (the host-mask defect)" TF \
    'old = "count(DISTINCT JSONExtractString(raw, \x27host_name\x27)) AS value"
assert s.count(old) == 1
s = s.replace(old, "count(*) AS value")'
  mutate RED "silent: GROUP BY time reintroduced (per-bucket row counts again)" TF \
    'old = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n  SQL\n\n  # Verdict failures"
assert s.count(old) == 1
s = s.replace(old, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n    GROUP BY time\n  SQL\n\n  # Verdict failures")'
  mutate RED "silent: threshold pinned to a literal 1 (fleet growth silently detaches it)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"egress_gw_probe_silent\" \{.*?value\s*=\s*)length\(var\.web_hosts\)", s, re.S)
assert m
s = s[:m.end(1)] + "1" + s[m.end():]'
  mutate RED "silent: operator flipped to higher_than (a healthy fleet pages)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"egress_gw_probe_silent\" \{.*?operator\s*=\s*)\"lower_than\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"higher_than\"" + s[m.end():]'
  mutate RED "fail: the tag conjunct dropped (any row would page)" TF \
    's = egw_replace(s, "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27egress-gw-probe\x27\n", "")'
  mutate RED "fail: result=fail arm dropped (wrong verdicts no longer page)" TF \
    's = egw_replace(s, "position(JSONExtractString(raw, \x27message\x27), \x27result=fail\x27) > 0\n", "position(JSONExtractString(raw, \x27message\x27), \x27result=ok\x27) > 0\n")'
  mutate RED "fail: reason=gw_absent arm dropped (gateway-missing reads as ordinary skip)" TF \
    's = egw_replace(s, "position(JSONExtractString(raw, \x27message\x27), \x27reason=gw_absent\x27) > 0", "position(JSONExtractString(raw, \x27message\x27), \x27reason=budget\x27) > 0")'
  mutate RED "fail: alert paused" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"egress_gw_probe_fail\" \{.*?\n  paused = )false", s, re.S)
assert m
s = s[:m.end(1)] + "true" + s[m.end():]'
  mutate RED "fail: on_missing_data no longer treat_as_zero" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"egress_gw_probe_fail\" \{.*?on_missing_data\s*=\s*)\"treat_as_zero\"", s, re.S)
assert m
s = s[:m.end(1)] + "\"keep_last_value\"" + s[m.end():]'
  mutate RED "fail: threshold 0 -> 1 (a single deny_bypassed row would not page)" TF \
    'import re
m = re.search(r"(resource \"logtail_exploration_alert\" \"egress_gw_probe_fail\" \{.*?value\s*=\s*)0\n", s, re.S)
assert m
s = s[:m.end(1)] + "1\n" + s[m.end():]'
  mutate RED "fail: alert watches another exploration" TF \
    'old = "  exploration_id = logtail_exploration.egress_gw_probe_fail.id"
assert s.count(old) == 1
s = s.replace(old, "  exploration_id = logtail_exploration.egress_gw_probe_silent.id")'
  mutate RED "fail: exploration dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.egress_gw_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "fail: alert dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.egress_gw_probe_fail \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate RED "emitter: resolver loses the reason=gw_absent literal" CR \
    's = s.replace("reason=gw_absent", "reason=gw_missing")'
  mutate RED "emitter: resolver loses the tagged emit (verdicts ship under a non-allowlisted identifier)" CR \
    's = s.replace("logger -t egress-gw-probe", "logger -t cron-egress-resolve")'
  mutate RED "runbook: the egress anchor heading renamed (incident links 404 to the section)" RB \
    'old = "### Egress gateway (Better Stack alerts)"
assert s.count(old) == 1
s = s.replace(old, "### Egress gateway (native log alerts)")'
  mutate PASS "control: a comment-only edit to the tf is green" TF \
    's = s + "\n# control comment\n"'

  echo ""
  echo "=== egress-gw-alert guard + mutations: $pass passed, $fail failed ==="
fi

if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
