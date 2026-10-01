#!/usr/bin/env bash
#
# Drift guard for the #8611 / ADR-243 Anthropic-spend Better Stack Logs alerts
# (apps/web-platform/infra/betterstack-logs-alerts.tf, the section headed `#8611 / ADR-243`):
#   inngest_step_524         — a step was cut at the Cloudflare proxy (the double-run's cause)
#   claude_cost_daily_burn   — the cron fleet spent more than $25 (local.claude_cost_daily_burn_usd)
#                              in a trailing 24 h
#   claude_cost_capture_dark — the cost telemetry itself went dark for 24 h
#
# Guard 2 of the #8611 plan: every alert queries what its emitter writes, and nothing more.
#   * The 524 predicate is EVALUATED against synthesized rows of the observed emitter shape
#     (inngest-server journald line, PRIORITY 6, the text under message.error): one positive row per
#     measured text (the 524 and the two spike-measured stream drops — every needle must match one,
#     every positive must be matched) and negatives that must NOT match (a 523, a 502, and a 524
#     under message.msg). A changed literal, a broadened needle, a changed field path or a changed
#     unit is caught against the shape, not against a copy of the SQL.
#   * No negation anywhere (NOT / != / <> — `IS NOT NULL` excepted) and no `1 = 1`; OR only in
#     capture-dark, exactly its two arms, arm B pinned to the credit probe's own CRON_NAME and op
#     union read from its source file. GROUP BY is matched case-insensitively.
#   * The cost-alert literals are pinned to their TS emitters: component "claude-cost" and the
#     SOLEUR_CLAUDE_COST:true key in server/claude-cost-marker.ts, the `cron:${cronName}` source in
#     the substrate.
#   * The two daily alerts evaluate a 24 h window (query_period 86400) and recovery >= check period;
#     the burn threshold is local.claude_cost_daily_burn_usd, interpolated into value AND email.
#   * No PRIORITY filter on the 524 query: the live lines are PRIORITY 6.
#   * Every exploration in the section reads the vector source through the pinned local.
#   * Every cost-reading exploration reads cost_usd at its NESTED path (raw.message, since #8344)
#     and keeps the `"SOLEUR_CLAUDE_COST":true` key match (without it the _DAILY org-total rows sum
#     in). Iterated over EVERY exploration that reads cost_usd, not the first.
#   * Aggregates only: the select list is a time expression plus one count/sum, and GROUP BY is
#     `time` or absent. The inngest-server line can carry queue-item payloads (email data).
#   * A whole-window (no-bucket) query filters on the `dt` column: its `time` alias is a constant,
#     so `time BETWEEN …` would be always-true and sum the source's entire history.
#   * vector.toml's inngest_journald source keeps the exact unit + PRIORITY shape the 524 rows were
#     OBSERVED to ship through (PRIORITY 6 rows ship despite the 0..4 match); any edit reds (V1/V2).
#   * Every exploration and alert in the section is in the apply workflow's -target= allowlist
#     (#5566: an untargeted resource is never applied, so the alert never exists).
#
# The section's explorations are DISCOVERED (every `resource "logtail_exploration"` between the
# section header and the NEXT `# ── #` section header), never a fixed list, and a floor refuses a
# discovery that found fewer than 3. A later section appended below is out of scope (row S1).
#
# WHAT THIS DOES NOT PROVE: that Better Stack accepts query_period 86400 or evaluates the template
# SQL as probed — terraform validate does not see the SQL, and the provider does not bound the
# period. The apply proves acceptance; nothing in-repo proves live evaluation (the reconciler's
# `logs_alert` arm reports only paused / absent).
#
# Mutation rows live at the bottom. Each COPIES a source file into a scratch dir, mutates the
# COPY and re-runs this guard against it through the SPEND_GUARD_{TF,WF} overrides. No tracked
# file is ever written (the inngest-luks-wrong-volume-alert.test.sh design, for its reasons).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${SPEND_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${SPEND_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
VEC="${SPEND_GUARD_VECTOR:-$REPO/apps/web-platform/infra/vector.toml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails. Every path this
# file READS is checked through it; the scratch dir every mutation WRITES to is checked too.
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$VEC"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$VEC"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done
command -v python3 >/dev/null || { printf '[FATAL] python3 not found\n' >&2; exit 2; }

# The structural checks run in ONE python pass that prints `OK <msg>` / `FAIL <msg>` lines; each
# line becomes one ok()/no() here. A python crash prints neither, and the floor below catches it.
EMIT_MARKER="$REPO/apps/web-platform/server/claude-cost-marker.ts"
EMIT_SUBSTRATE="$REPO/apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts"
EMIT_PROBE="$REPO/apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts"
for f in "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable emitter: %s\n' "$f" >&2; exit 2; }
done

# A checker CRASH is this guard's FATAL class (rc 2), never an assertion: mutate_red grades only
# rc 1 as caught, so a mutation that merely crashes python cannot be credited as a kill.
CHECKS="$(python3 - "$TF" "$WF" "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE" "$VEC" <<'PY'
import json, re, sys
tf = open(sys.argv[1], encoding="utf-8").read()
wf = open(sys.argv[2], encoding="utf-8").read()
marker_ts = open(sys.argv[3], encoding="utf-8").read()
substrate_ts = open(sys.argv[4], encoding="utf-8").read()
probe_ts = open(sys.argv[5], encoding="utf-8").read()
vector = open(sys.argv[6], encoding="utf-8").read()
out = []
def check(cond, msg): out.append(("OK " if cond else "FAIL ") + msg)

HEADER = "# ── #8611 / ADR-243:"
if tf.count(HEADER) != 1:
    print("FAIL the #8611 section header is missing or duplicated — nothing below can be discovered")
    sys.exit(0)
_start = tf.index(HEADER)
_next = tf.find("\n# ── #", _start + len(HEADER))
sec = tf[_start:] if _next == -1 else tf[_start:_next]

def heredoc(name):
    m = re.search(r"^[ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*<<-SQL\n(.*?)^  SQL$", tf, re.S | re.M)
    return m.group(1) if m else None

def block(kind, name):
    m = re.search(r'^resource "' + kind + r'" "' + re.escape(name) + r'" \{\n(.*?)^\}', tf, re.S | re.M)
    return m.group(1) if m else None

names = re.findall(r'^resource "logtail_exploration" "([a-z0-9_]+)" \{', sec, re.M)
check(len(names) >= 3, f"discovered {len(names)} explorations in the #8611 section (floor 3)")
check(names.count("inngest_step_524") == 1, "the 524 exploration is among them")
check(names.count("claude_cost_daily_burn") == 1, "the daily burn exploration is among them")
check(names.count("claude_cost_capture_dark") == 1, "the capture-dark exploration is among them")
check(re.search(r'^\s*vector_prd_source_id\s*=\s*"2457081"\s*$', tf, re.M) is not None,
      "the pinned source local is still 2457081 (the inngest vector source)")

sqls = {}
for n in names:
    exp = block("logtail_exploration", n) or ""
    alr = block("logtail_exploration_alert", n) or ""
    m = re.search(r'^\s*sql_query = replace\(trimspace\(local\.([a-z0-9_]+)\), "/\\\\s\+/", " "\)\s*$', exp, re.M)
    local = m.group(1) if m else None
    sql = heredoc(local) if local else None
    sqls[n] = sql or ""
    check(sql is not None, f"{n}: sql_query is a collapsed local heredoc this guard can read")
    check(re.search(r'^\s*values\s*=\s*\[local\.vector_prd_source_id\]\s*$', exp, re.M) is not None
          and len(re.findall(r'^\s*values\s*=', exp, re.M)) == 1,
          f"{n}: reads exactly the pinned vector source")
    check(re.search(r'^\s*exploration_id = logtail_exploration\.' + n + r'\.id\s*$', alr, re.M) is not None,
          f"{n}: its alert exists and points at THIS exploration")
    check(re.search(r'^\s*paused = false\s*$', alr, re.M) is not None, f"{n}: alert is unpaused")
    check(re.search(r'^\s*on_missing_data\s*=\s*"treat_as_zero"\s*$', alr, re.M) is not None,
          f"{n}: on_missing_data is treat_as_zero")
    check(re.search(r'^\s*-target=logtail_exploration\.' + n + r' \\$', wf, re.M) is not None
          and re.search(r'^\s*-target=logtail_exploration_alert\.' + n + r' \\$', wf, re.M) is not None,
          f"{n}: exploration AND alert are in the apply -target= allowlist")
    if not sql:
        continue
    # Aggregates only: select list = one time expression + one count/sum AS value.
    sel = re.search(r"SELECT (.*?)\n\s*FROM \{\{source\}\}", sql, re.S)
    items = [i.strip() for i in re.split(r",(?![^()]*\))", sel.group(1))] if sel else []
    time_ok = len(items) == 2 and items[0] in ("{{time}} AS time", "toDateTime({{end_time}}) AS time")
    val_ok = len(items) == 2 and re.fullmatch(r"(count\(\*\)|sum\(JSONExtractFloat\(raw, 'message', 'cost_usd'\)\)) AS value", items[1]) is not None
    check(time_ok and val_ok, f"{n}: selects aggregates only (a time expression and one count/sum) — got {items}")
    gb = re.findall(r"GROUP BY (.*)", sql, re.I)
    check(gb in ([], ["time"]), f"{n}: GROUP BY is `time` or absent (no free-text grouping) — got {gb}")
    _neg = re.sub(r"\bIS NOT NULL\b", "", sql, flags=re.I)
    check(re.search(r"\bNOT\b", _neg, re.I) is None and "!=" not in sql and "<>" not in sql,
          f"{n}: no negation (NOT / != / <>; `IS NOT NULL` excepted) — a negated arm inverts the alert")
    check(re.search(r"\b1\s*=\s*1\b", sql) is None, f"{n}: no `1 = 1` tautology")
    if n != "claude_cost_capture_dark":
        check(re.search(r"\bOR\b", sql, re.I) is None, f"{n}: no OR (an appended OR arm widens the window or the rows)")
    if items and items[0].startswith("toDateTime("):
        check(re.search(r"^\s*WHERE dt BETWEEN \{\{start_time\}\} AND \{\{end_time\}\}\s*$", sql, re.M) is not None
              and "time BETWEEN" not in sql,
              f"{n}: a whole-window query filters on the dt column, never on its constant time alias")
    else:
        check(gb == ["time"] and re.search(r"^\s*WHERE time BETWEEN \{\{start_time\}\} AND \{\{end_time\}\}\s*$", sql, re.M) is not None,
              f"{n}: a {{{{time}}}}-bucketed query groups by time and keeps its time-window filter")
    if "cost_usd" in sql:
        check(re.search(r"JSONExtract\w*\(raw, 'cost_usd'", sql) is None
              and "JSONExtract" in sql and "raw, 'message', 'cost_usd'" in sql,
              f"{n}: reads cost_usd at the nested raw.message path, never top-level")
        check("raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%'" in sql,
              f"{n}: keeps the \"SOLEUR_CLAUDE_COST\":true key match (the _DAILY rows stay out)")
        check("JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'" in sql,
              f"{n}: scoped to cron sources (founder BYOK spend is not the operator key's)")

# The 524 predicate EVALUATED against synthesized rows of the observed emitter shape (2026-09-23
# probe: keys error/item_kind/level/msg/time under an object `message`, PRIORITY 6, unit
# inngest-server). multiSearchAny is a case-sensitive substring test, reproduced literally.
s524 = sqls.get("inngest_step_524", "")
unit = re.search(r"JSONExtractString\(raw, '_SYSTEMD_UNIT'\) = '([^']*)'", s524)
needle = re.search(r"multiSearchAny\(JSONExtractString\(raw, 'message', '([a-z_]+)'\), \[([^\]]*)\]\)", s524)
field = needle.group(1) if needle else None
needles = re.findall(r"'([^']*)'", needle.group(2)) if needle else []
def row(error, msg="error handling queue item"):
    return {"PRIORITY": "6", "_SYSTEMD_UNIT": "inngest-server.service", "SYSLOG_IDENTIFIER": "doppler",
            "message": {"time": "2026-01-01T00:00:00Z", "level": "ERROR", "msg": msg,
                        "item_kind": "edge", "error": error}}
def pred(r):
    if not (unit and field and r["_SYSTEMD_UNIT"] == unit.group(1)):
        return False
    v = r["message"].get(field, "")
    return any(nd in v for nd in needles)
POS = ["invalid status code: 524",
       "error parsing stream: error reading response body to check for status code: unexpected end of JSON input",
       "Your server reset the connection while we were reading the reply: Unexpected ending response"]
check(field == "error" and len(needles) >= 1,
      f"524: the needle array reads message.error (field={field}, needles={needles})")
check(all(pred(row(t)) for t in POS),
      "524: every measured positive text (the 524 and both spike stream-drop texts) is matched")
check(len(needles) > 0 and all(any(nd in t for t in POS) for nd in needles),
      "524: every needle matches at least one measured positive text (no stale or typo'd needle)")
check(not pred(row("invalid status code: 523")), "524: a 523 does NOT match (the needle is not broadened)")
check(not pred(row("invalid status code: 502")), "524: a 502 does NOT match")
check(not pred(row("context canceled", msg="invalid status code: 524")),
      "524: a 524 under message.msg (not message.error) does NOT match — the field path is pinned")
check(len(re.findall(r"multiSearchAny\(", s524)) == 1 and len(re.findall(r"JSONExtractString\(raw, '_SYSTEMD_UNIT'\)", s524)) == 1,
      "524: exactly one unit scope and one needle array (no OR-appended second arm)")
check(re.search(r"PRIORITY", s524) is None, "524: no PRIORITY filter (the live 524 lines are PRIORITY 6)")
check(re.search(r"\bOR\b", s524) is None and " LIKE " not in s524, "524: field-isolated — no OR, no raw LIKE (issue bodies quote the literal)")

def alert_attr(n, key):
    m = re.search(r"^\s*" + key + r"\s*=\s*(\S+)\s*$", block("logtail_exploration_alert", n) or "", re.M)
    return m.group(1) if m else None
check(alert_attr("inngest_step_524", "operator") == '"higher_than"' and alert_attr("inngest_step_524", "value") == "0",
      "524: any matching row pages (higher_than 0)")
_burn_local = re.search(r"^\s*claude_cost_daily_burn_usd\s*=\s*([0-9]+)\s*$", tf, re.M)
check(alert_attr("claude_cost_daily_burn", "operator") == '"higher_than"'
      and alert_attr("claude_cost_daily_burn", "value") == "local.claude_cost_daily_burn_usd"
      and _burn_local is not None and _burn_local.group(1) == "25",
      "burn: pages above local.claude_cost_daily_burn_usd (= 25) per window")
check("${local.claude_cost_daily_burn_usd}" in (block("logtail_exploration_alert", "claude_cost_daily_burn") or ""),
      "burn: the email text interpolates the same threshold local (it cannot drift from value)")
for _n in ("claude_cost_daily_burn", "claude_cost_capture_dark"):
    _qp, _cp, _rp = alert_attr(_n, "query_period"), alert_attr(_n, "check_period"), alert_attr(_n, "recovery_period")
    check(_qp == "86400" and _cp is not None and _rp is not None and _cp.isdigit() and _rp.isdigit() and int(_rp) >= int(_cp),
          f"{_n}: evaluates a 24 h window (query_period 86400) and recovery_period >= check_period — got {_qp}/{_cp}/{_rp}")
check(alert_attr("claude_cost_capture_dark", "operator") == '"lower_than"' and alert_attr("claude_cost_capture_dark", "value") == "1",
      "capture-dark: pages when the window holds nothing (lower_than 1 over treat_as_zero)")
dark = sqls.get("claude_cost_capture_dark", "")
check("'Nullable(Float64)') IS NOT NULL" in dark and "'anthropic-credit-exhausted'" in dark,
      "capture-dark: counts non-null cost markers, and credit-probe RED rows suppress it")
# capture-dark: exactly two OR'd arms; arm B pinned to the credit probe's own literals.
_cron = re.search(r'^const CRON_NAME = "([a-z0-9-]+)";', probe_ts, re.M)
_opu = re.search(r"op\?:\s*([^;]+);", probe_ts)
_ops_ts = set(re.findall(r'"(anthropic-[a-z-]+)"', _opu.group(1))) if _opu else set()
_armb = re.search(r"OR \(JSONExtractString\(raw, 'message', 'feature'\) = '([^']*)'\s+AND JSONExtractString\(raw, 'message', 'op'\) IN \(([^)]*)\)\)", dark)
_ops_sql = set(re.findall(r"'([^']*)'", _armb.group(2))) if _armb else set()
check(len(re.findall(r"\bOR\b", dark, re.I)) == 1 and _armb is not None,
      "capture-dark: exactly one OR, joining the marker arm and the credit-probe arm")
check(_cron is not None and _armb is not None and _armb.group(1) == _cron.group(1),
      f"capture-dark: arm B's feature literal is the credit probe's CRON_NAME ({_cron.group(1) if _cron else None})")
check(bool(_ops_sql) and _ops_ts and _ops_sql <= _ops_ts,
      f"capture-dark: arm B's ops are members of the probe's op union (sql={sorted(_ops_sql)}, ts={sorted(_ops_ts)})")
# Emitter parity: the literals every cost query matches on are the ones the TS emitters write.
check(re.search(r'pino\(\{ base: \{ component: "claude-cost" \} \}\)', marker_ts) is not None
      and all("JSONExtractString(raw, 'message', 'component') = 'claude-cost'" in sqls.get(x, "")
              for x in ("claude_cost_daily_burn", "claude_cost_capture_dark")),
      "emitter parity: component 'claude-cost' is the marker logger's pino base AND both cost queries' filter")
check(re.search(r"log\.warn\(\{ SOLEUR_CLAUDE_COST: true, \.\.\.m \}", marker_ts) is not None,
      "emitter parity: the marker writes the SOLEUR_CLAUDE_COST: true key the queries match")
check("source: `cron:${cronName}`" in substrate_ts,
      "emitter parity: the substrate writes source `cron:${cronName}` (the queries' LIKE 'cron:%')")
check("runbooks/betterstack-log-query.md" in sec, "the incidents carry a clickable runbook URL")
# The 524 alert's rows reach Better Stack only through vector.toml's inngest_journald source, and
# they are PRIORITY 6 while that source lists PRIORITY 0..4: OBSERVED to ship anyway (the unit
# match admits them; see the .tf comment and #6551). That observed shape is pinned here, so ANY
# edit to the source's unit or PRIORITY filter reds this guard and forces a re-probe of the path
# (scripts/probe-inngest-524-count.sh prints unit_rows) before the alert can be trusted again.
_vsrc = re.search(r"^\[sources\.inngest_journald\]\n(.*?)(?=^\[|\Z)", vector, re.S | re.M)
_vbody = _vsrc.group(1) if _vsrc else ""
check(re.search(r'^include_units = \["inngest-server\.service"\]\s*$', _vbody, re.M) is not None
      and re.search(r'^include_matches\.PRIORITY = \["0", "1", "2", "3", "4"\]\s*$', _vbody, re.M) is not None
      and len(re.findall(r"^include_matches\.", _vbody, re.M)) == 1
      and re.search(r'^inputs = \[[^\]]*"inngest_journald"', vector, re.M) is not None,
      "vector: the inngest_journald source is exactly the observed shape the 524 rows ship through (unit + PRIORITY 0..4, routed)")
print("\n".join(out))
PY
)" || { printf '[FATAL] the structural checker crashed (python rc != 0) — no verdict\n' >&2; exit 2; }
while IFS= read -r line; do
  case "$line" in
    "OK "*)   ok "${line#OK }" ;;
    "FAIL "*) no "${line#FAIL }" ;;
    "") : ;;
    *) no "unparsed checker line: $line" ;;
  esac
done <<<"$CHECKS"

# ── Mutation rows: each must make the rows above RED ───────────────────────────────────────────
SELF="${BASH_SOURCE[0]}"
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t spendalert.XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  assert_fixture_dir "$MUT_DIR"
  trap 'rm -rf "$MUT_DIR"' EXIT

  # INSTRUMENT CONTROL — the inner run against the PRISTINE tree must exit 0, or every row below
  # would grade "RED" off a broken invocation.
  ctl_rc=0; MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/control.log" 2>&1 || ctl_rc=$?
  if [ "$ctl_rc" -ne 0 ]; then
    printf '[FATAL] instrument control: the inner run exited %s on the PRISTINE tree — the battery cannot be trusted:\n' "$ctl_rc" >&2
    sed 's/^/    /' "$MUT_DIR/control.log" >&2; exit 2
  fi

  mutate_red() {  # mutate_red <label> <TF|WF> <python-expr-on-s>
    local label="$1" which="$2" prog="$3" src copy rc=0
    case "$which" in
      TF) src="$TF"; copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF) src="$WF"; copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      VEC) src="$VEC"; copy="$MUT_DIR/vector.toml" ;;
      *) printf '[FATAL] mutate_red: unknown target %s\n' "$which" >&2; exit 2 ;;
    esac
    cp "$src" "$copy" || { printf '[FATAL] mutate_red: cp %s failed\n' "$src" >&2; exit 2; }
    python3 - "$copy" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
orig = open(p, encoding="utf-8").read()
s = orig
def in_block(s, start_marker, old, new, end_marker="\n}\n"):
    i = s.index(start_marker); j = s.index(end_marker, i)
    assert s[i:j].count(old) == 1, "anchor"
    return s[:i] + s[i:j].replace(old, new) + s[j:]
$prog
assert s != orig, "mutation produced no change"
open(p, 'w', encoding="utf-8").write(s)
PY
    case "$which" in
      TF) SPEND_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      WF) SPEND_GUARD_WF="$copy" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
      VEC) SPEND_GUARD_VECTOR="$copy" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$? ;;
    esac
    # Only rc=1 (an assertion went red) is a caught mutation; rc>=2 is this guard's FATAL class.
    case "$rc" in
      1) ok "mutation RED: $label" ;;
      0) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  H524='inngest_step_524_sql = <<-SQL'; HBURN='claude_cost_daily_burn_sql = <<-SQL'; HDARK='claude_cost_capture_dark_sql = <<-SQL'
  # Row 1 — the 524 literal changes.
  mutate_red "1: the 524 literal changes" TF \
    "s = in_block(s, '$H524', \"'invalid status code: 524'\", \"'invalid status code: 504'\", '  SQL\n')"
  mutate_red "1b: the 524 field path moves off message.error" TF \
    "s = in_block(s, '$H524', \"JSONExtractString(raw, 'message', 'error')\", \"JSONExtractString(raw, 'message', 'msg')\", '  SQL\n')"
  # Row 2 — an exploration reads a different source (the LAST one, so iteration is exercised).
  mutate_red "2: capture-dark exploration points at the git-data source" TF \
    "s = in_block(s, 'resource \"logtail_exploration\" \"claude_cost_capture_dark\"', 'values        = [local.vector_prd_source_id]', 'values        = [\"2734275\"]')"
  # Row 3 — a -target= line disappears.
  mutate_red "3: the capture-dark alert is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration_alert.claude_cost_capture_dark \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate_red "3b: the 524 exploration is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.inngest_step_524 \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  # Row 4 — cost read at the top level / key match dropped (in the NON-first cost exploration).
  mutate_red "4: burn reads top-level cost_usd" TF \
    "s = in_block(s, '$HBURN', \"sum(JSONExtractFloat(raw, 'message', 'cost_usd'))\", \"sum(JSONExtractFloat(raw, 'cost_usd'))\", '  SQL\n')"
  mutate_red "4b: capture-dark drops the \"SOLEUR_CLAUDE_COST\":true key match" TF \
    "s = in_block(s, '$HDARK', \"raw LIKE '%\\\"SOLEUR_CLAUDE_COST\\\":true%'\", \"raw LIKE '%SOLEUR_CLAUDE_COST%'\", '  SQL\n')"
  # Row 5 — a raw message column / a free-text GROUP BY.
  mutate_red "5: capture-dark selects the raw message column" TF \
    "s = in_block(s, '$HDARK', 'count(*) AS value', \"count(*) AS value, JSONExtractString(raw, 'message', 'msg') AS msg\", '  SQL\n')"
  mutate_red "5b: the 524 query groups on free text" TF \
    "s = in_block(s, '$H524', '    GROUP BY time', \"    GROUP BY time, JSONExtractString(raw, 'message', 'error')\", '  SQL\n')"
  # Row 6 — a PRIORITY filter on the 524 query.
  mutate_red "6: the 524 query gains a PRIORITY filter" TF \
    "s = in_block(s, '$H524', \"      AND JSONExtractString(raw, '_SYSTEMD_UNIT')\", \"      AND JSONExtractString(raw, 'PRIORITY') = '2'\n      AND JSONExtractString(raw, '_SYSTEMD_UNIT')\", '  SQL\n')"
  # Row 7 — the whole-window burn filters on its constant time alias (sums all history).
  mutate_red "7: burn's window filter moves onto the time alias" TF \
    "s = in_block(s, '$HBURN', 'WHERE dt BETWEEN', 'WHERE time BETWEEN', '  SQL\n')"
  # Row 8 — capture-dark can no longer fire on silence.
  mutate_red "8: capture-dark operator flips to higher_than" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_capture_dark\"', 'operator            = \"lower_than\"', 'operator            = \"higher_than\"')"
  mutate_red "8b: the 524 alert is paused" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"inngest_step_524\"', '  paused = false\n', '  paused = true\n')"
  # Needle rows — every needle is exercised against its own measured text, and negatives stay quiet.
  mutate_red "N1: the 524 needle is broadened to any status code" TF \
    "s = in_block(s, '$H524', \"'invalid status code: 524'\", \"'invalid status code'\", '  SQL\n')"
  mutate_red "N2: a stream-drop needle is typo'd" TF \
    "s = in_block(s, '$H524', \"'error parsing stream: error reading response body'\", \"'error parsing strem: nothing matches this'\", '  SQL\n')"
  mutate_red "N3: both stream-drop needles are deleted" TF \
    "s = in_block(s, '$H524', \", 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply'\", '', '  SQL\n')"
  # Negation / tautology / widening rows (the survivors of the #8611 review's test-design seat).
  mutate_red "G4: the 524 needle predicate is negated" TF \
    "s = in_block(s, '$H524', 'AND multiSearchAny(', 'AND NOT multiSearchAny(', '  SQL\n')"
  mutate_red "G5: burn's cron-source filter is negated" TF \
    "s = in_block(s, '$HBURN', \"AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\", \"AND NOT JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\", '  SQL\n')"
  mutate_red "G6: burn's SOLEUR_CLAUDE_COST key match is negated" TF \
    "s = in_block(s, '$HBURN', \"AND raw LIKE '%\\\"SOLEUR_CLAUDE_COST\\\":true%'\", \"AND NOT raw LIKE '%\\\"SOLEUR_CLAUDE_COST\\\":true%'\", '  SQL\n')"
  mutate_red "G7: capture-dark's credit-probe op filter becomes NOT IN" TF \
    "s = in_block(s, '$HDARK', \"'op') IN (\", \"'op') NOT IN (\", '  SQL\n')"
  mutate_red "G8: capture-dark's feature literal drifts from the probe's CRON_NAME" TF \
    "s = in_block(s, '$HDARK', \"= 'cron-anthropic-credit-probe'\", \"= 'cron-anthropic-credit-prob'\", '  SQL\n')"
  mutate_red "G9: capture-dark gains an always-true OR arm" TF \
    "s = in_block(s, '$HDARK', \"OR (JSONExtractString(raw, 'message', 'feature')\", \"OR (1 = 1 OR JSONExtractString(raw, 'message', 'feature')\", '  SQL\n')"
  mutate_red "G11: burn's window gains an OR that sums all history" TF \
    "s = in_block(s, '$HBURN', 'WHERE dt BETWEEN {{start_time}} AND {{end_time}}\n', 'WHERE dt BETWEEN {{start_time}} AND {{end_time}}\n      OR dt < {{end_time}}\n', '  SQL\n')"
  mutate_red "G12: burn splits its sum with a lowercase group by source" TF \
    "s = in_block(s, '$HBURN', \"      AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\n\", \"      AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\n    group by JSONExtractString(raw, 'message', 'source')\n\", '  SQL\n')"
  mutate_red "G13: the 524 query loses its time-window filter" TF \
    "s = in_block(s, '$H524', '    WHERE time BETWEEN {{start_time}} AND {{end_time}}\n      AND JSONExtractString', '    WHERE JSONExtractString', '  SQL\n')"
  # Window / threshold rows.
  mutate_red "Q1: burn's query_period shrinks to 300 s" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_daily_burn\"', 'query_period        = 86400', 'query_period        = 300')"
  mutate_red "Q2: capture-dark's query_period shrinks to 300 s" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_capture_dark\"', 'query_period        = 86400', 'query_period        = 300')"
  mutate_red "T1: burn's value is hardcoded apart from the threshold local" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_daily_burn\"', 'value               = local.claude_cost_daily_burn_usd', 'value               = 15')"

  mutate_red "V1: vector's inngest_journald source loses the inngest-server unit" VEC \
    "s = s.replace('include_units = [\"inngest-server.service\"]', 'include_units = [\"inngest-other.service\"]', 1)"
  mutate_red "V2: vector's inngest_journald PRIORITY filter changes" VEC \
    "s = s.replace('include_matches.PRIORITY = [\"0\", \"1\", \"2\", \"3\", \"4\"]\nj', 'include_matches.PRIORITY = [\"0\", \"1\", \"2\"]\nj', 1)"

  # S1 — must stay GREEN: a later section appended below this one (the .tf's own recipe) is out of
  # this guard's scope, so a future alert with a different select shape cannot trip it.
  cp "$TF" "$MUT_DIR/s1.tf" || { printf '[FATAL] S1: cp failed\n' >&2; exit 2; }
  printf '\n# ── #9999 / ADR-999: a future alert ──\nlocals {\n  future_sql = <<-SQL\n    SELECT {{time}} AS time, countIf(raw LIKE %s) AS value\n    FROM {{source}}\n    GROUP BY time\n  SQL\n}\n\nresource "logtail_exploration" "future_alert" {\n  query {\n    sql_query = replace(trimspace(local.future_sql), "/\\\\s+/", " ")\n  }\n}\n' "'%x%'" >>"$MUT_DIR/s1.tf"
  if cmp -s "$TF" "$MUT_DIR/s1.tf"; then no "S1 did not land"; else
    s1_rc=0; SPEND_GUARD_TF="$MUT_DIR/s1.tf" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || s1_rc=$?
    if [ "$s1_rc" -eq 0 ]; then ok "S1 stays GREEN: an alert section appended below is out of scope"
    else no "S1: an appended later section tripped this guard (inner rc=$s1_rc) — the section slice is unbounded"; fi
  fi
  # C1 — a checker CRASH is FATAL (rc 2), never graded as a caught mutation (rc 1).
  cp "$TF" "$MUT_DIR/c1.tf" || { printf '[FATAL] C1: cp failed\n' >&2; exit 2; }
  printf '\xff\xfe' >>"$MUT_DIR/c1.tf"
  if cmp -s "$TF" "$MUT_DIR/c1.tf"; then no "C1 did not land"; else
    c1_rc=0; SPEND_GUARD_TF="$MUT_DIR/c1.tf" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || c1_rc=$?
    if [ "$c1_rc" -eq 2 ]; then ok "C1: a crashed checker exits FATAL 2, not an assertion's 1"
    else no "C1: a crashed checker exited $c1_rc (must be 2) — a crash would grade as a caught mutation"; fi
  fi
fi

# 102 = 70 presence rows + 32 mutation rows (30 must-RED, S1 must-GREEN, C1 must-FATAL). The
# MUT_SKIP floor is exactly today's presence count (3 discovered explorations): a discovery that
# finds fewer, or a checker that dies part-way, drops below it. Raise both in the same edit that
# adds a row. A breached floor or ledger is FATAL (rc 2), never an assertion (rc 1).
_floor=102
[ -n "${MUT_SKIP:-}" ] && _floor=70
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 2; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 2; fi
printf '\n=== inngest-step-524-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
