#!/usr/bin/env bash
#
# Drift guard for the #8611 / ADR-243 Anthropic-spend Better Stack Logs alerts
# (apps/web-platform/infra/betterstack-logs-alerts.tf, the section headed `#8611 / ADR-243`):
#   inngest_step_524         — a step was cut at the Cloudflare proxy (the double-run's cause)
#   claude_cost_daily_burn   — the cron fleet spent more than $25 (local.claude_cost_daily_burn_usd)
#                              in a trailing 24 h
# (The third alarm, the cost-telemetry dead-man, was retired by #11631: it is the archive-fed heartbeat
# soleur-claude-cost-capture-prd, and its predicate, emitter-parity pins and mutants live in
# apps/web-platform/test/infra/deadman-heartbeat-feeder.test.sh.)
#
# Guard 2 of the #8611 plan: every alert queries what its emitter writes, and nothing more.
#   * The 524 predicate is EVALUATED against synthesized rows of the observed emitter shape
#     (inngest-server journald line, PRIORITY 6, the text under message.error): one positive row per
#     measured text (the 524 and the two spike-measured stream drops — every needle must match one,
#     every positive must be matched) and negatives that must NOT match (a 523, a 502, and a 524
#     under message.msg). A changed literal, a broadened needle, a changed field path or a changed
#     unit is caught against the shape, not against a copy of the SQL.
#   * No negation anywhere (NOT / != / <> — `IS NOT NULL` excepted), no `1 = 1` and no OR.
#     GROUP BY is matched case-insensitively.
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
#     OBSERVED to ship through (PRIORITY 6 rows ship despite the {3,4} match, post-#6551 partition); any edit reds (V1/V2).
#     The source now lists TWO units (inngest-server and the TLS terminator), and its rows reach the PII
#     chain only THROUGH the terminator's fail-open filter; that routing is parsed, not matched (V3).
#   * Every exploration and alert in the section is in the apply workflow's -target= allowlist
#     (#5566: an untargeted resource is never applied, so the alert never exists).
#
# The section's explorations are DISCOVERED (every `resource "logtail_exploration"` between the
# section header and the NEXT `# ── #` section header), never a fixed list, and a floor refuses a
# discovery that found fewer than 2 (the third alarm was retired by #11631). A later section
# appended below is out of scope (the S1 must-PASS row).
#
# WHAT THIS FILE NOW PROVES (post-#11720 convention):
#   * CANONICAL EQUALITY — each discovered exploration's flattened heredoc must EQUAL its pinned
#     canon inside the checker (whitespace-normalized, derived literals), so dead text and
#     arithmetic edits go red; decoy heredoc/resource openers are counted file-wide and red.
#   * EXACTLY-ONCE PINS — every pinned attribute is asserted inside its own resource block by
#     param(), whole value line anchored both ends; a decoy or duplicated pinned line is a red.
#   * THE BATTERY CANNOT BE MUTED — MUT_SKIP skips mutation rows on an inner run only; the
#     pristine-child control FATALs (rc 2) otherwise; SPEND_GUARD_/MUT_SKIP literals may not reach
#     infra-validation.yml's executable text (the seam check).
#   * RC DISCRIMINATION — only rc=1 (a real [FAIL] verdict) is a caught mutation; instrument
#     failures (rc>=2) are UNRESOLVED. Floor/ledger trips exit 1.
#
# WHAT THIS DOES NOT PROVE: that Better Stack accepts query_period 86400 or evaluates the template
# SQL as probed — terraform validate does not see the SQL, and the provider does not bound the
# period. The apply proves acceptance; nothing in-repo proves live evaluation (the reconciler's
# `logs_alert` arm reports only paused / absent).
#
# Mutation rows live at the bottom. Each COPIES a source file into a scratch dir, mutates the
# COPY and re-runs this guard against it through the SPEND_GUARD_{TF,WF,VEC,IV} overrides. No
# tracked file is ever written (the inngest-luks-wrong-volume-alert.test.sh design, for its
# reasons).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${SPEND_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${SPEND_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
VEC="${SPEND_GUARD_VEC:-$REPO/apps/web-platform/infra/vector.toml}"
IV="${SPEND_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"

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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"; assert_fixture_dir "$VEC"; assert_fixture_dir "$IV"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF" "$VEC" "$IV"; do
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
# The push-triggered MAIN plan only: first `terraform plan -no-color` to its `rc=$?`. The workflow
# has ~15 plan regions whose -target lists never run on a push to main — the allowlist rows read
# THIS region, not the whole file (sibling-parity; security P2).
_mp = re.search(r"^[ \t]*terraform plan -no-color.*?(?:^[ \t]*rc=\$\?|\Z)", wf, re.S | re.M)
main_plan = _mp.group(0) if _mp else ""
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
    m = re.search(r"^[ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*<<\x2dSQL\n(.*?)^  SQL$", tf, re.S | re.M)
    return m.group(1) if m else None

def block(kind, name):
    m = re.search(r'^resource "' + kind + r'" "' + re.escape(name) + r'" \{\n(.*?)^\}', tf, re.S | re.M)
    return m.group(1) if m else None

def param(blk, key, val_re):
    # Value-matching exactly-once, whole line anchored both ends — a decoy or duplicated
    # pinned line is a red, not a shrug. Residual gap (accepted, donor-parity): a planted
    # same-attr/different-value line does not move the count; attr-name cardinality cannot
    # apply where blocks legitimately nest `name` (variable { name = "source" }).
    return len(re.findall(r"^[ \t]*" + key + r"[ \t]*=[ \t]*" + val_re + r"[ \t]*(#.*)?$", blk, re.M)) == 1

names = re.findall(r'^resource "logtail_exploration" "([a-z0-9_]+)" \{', sec, re.M)
check(len(names) >= 2, f"discovered {len(names)} explorations in the #8611 section (floor 2)")
check(names.count("inngest_step_524") == 1, "the 524 exploration is among them")
check(names.count("claude_cost_daily_burn") == 1, "the daily burn exploration is among them")
check(re.search(r'^\s*vector_prd_source_id\s*=\s*"2457081"\s*$', tf, re.M) is not None,
      "the pinned source local is still 2457081 (the inngest vector source)")

sqls = {}
# Whitespace-normalized canons — DERIVED literals (flattened extraction), pinned so dead text
# (a decoy copy, a gutted live body) can never satisfy the predicate rows below. A whitespace
# reflow of a heredoc is a must-PASS (mutate_green row); any literal/structure edit is RED.
CANON = {
    "inngest_step_524": "SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'inngest-server.service' AND multiSearchAny(JSONExtractString(raw, 'message', 'error'), ['invalid status code: 524', 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply']) GROUP BY time",
    "claude_cost_daily_burn": "SELECT toDateTime({{end_time}}) AS time, sum(JSONExtractFloat(raw, 'message', 'cost_usd')) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%' AND JSONExtractString(raw, 'message', 'component') = 'claude-cost' AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'",
}
for n in names:
    exp = block("logtail_exploration", n) or ""
    alr = block("logtail_exploration_alert", n) or ""
    m = re.search(r'^\s*sql_query = replace\(trimspace\(local\.([a-z0-9_]+)\), "/\\\\s\+/", " "\)\s*$', exp, re.M)
    local = m.group(1) if m else None
    sql = heredoc(local) if local else None
    sqls[n] = sql or ""
    check(sql is not None
          and param(exp, "sql_query", r'replace\(trimspace\(local\.[a-z0-9_]+\), "/\\\\s\+/", " "\)'),
          f"{n}: sql_query is a collapsed local heredoc this guard can read")
    if local:
        # Unanchored, file-wide opener census — a /* */- or #-wrapped decoy copy still counts.
        check(len(re.findall(re.escape(local) + r"[ \t]*=[ \t]*<<\x2dSQL", tf)) == 1,
              f"{local}: exactly one heredoc opener in the file (decoy copies count)")
    check(len(re.findall(r'resource "logtail_exploration" "' + re.escape(n) + '"', tf)) == 1,
          f"{n}: exactly one exploration resource header in the file (decoy copies count)")
    check(len(re.findall(r'resource "logtail_exploration_alert" "' + re.escape(n) + '"', tf)) == 1,
          f"{n}: exactly one alert resource header in the file (decoy copies count)")
    check(param(exp, "values", r"\[local\.vector_prd_source_id\]"),
          f"{n}: reads exactly the pinned vector source")
    check(param(alr, "exploration_id", r"logtail_exploration\." + n + r"\.id"),
          f"{n}: its alert exists and points at THIS exploration")
    check(param(alr, "paused", "false"), f"{n}: alert is unpaused")
    check(sum(1 for _l in alr.splitlines() if "paused" in _l) == 1,
          f"{n}: 'paused' occurs exactly once in the alert block (a commented or duplicated decoy counts)")
    check(param(alr, "on_missing_data", '"treat_as_zero"'),
          f"{n}: on_missing_data is treat_as_zero")
    check(re.search(r'^\s*-target=logtail_exploration\.' + n + r' \\$', main_plan, re.M) is not None
          and re.search(r'^\s*-target=logtail_exploration_alert\.' + n + r' \\$', main_plan, re.M) is not None,
          f"{n}: exploration AND alert are in the apply -target= allowlist")
    if n in CANON:
        check(re.sub(r"\s+", " ", sql or "").strip() == CANON[n],
              f"{n}: predicate is byte-exact (whitespace-normalized canon compare — dead text never satisfies)")
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
    # Exactly-once attr extraction: a duplicated attr line yields None, not the first match.
    vals = re.findall(r"^\s*" + key + r"\s*=\s*(\S+)\s*$", block("logtail_exploration_alert", n) or "", re.M)
    return vals[0] if len(vals) == 1 else None
check(alert_attr("inngest_step_524", "operator") == '"higher_than"' and alert_attr("inngest_step_524", "value") == "0",
      "524: any matching row pages (higher_than 0)")
_burn_locals = re.findall(r"^\s*claude_cost_daily_burn_usd\s*=\s*([0-9]+)\s*$", tf, re.M)
check(alert_attr("claude_cost_daily_burn", "operator") == '"higher_than"'
      and alert_attr("claude_cost_daily_burn", "value") == "local.claude_cost_daily_burn_usd"
      and len(_burn_locals) == 1 and _burn_locals[0] == "25",
      "burn: pages above local.claude_cost_daily_burn_usd (= 25) per window")
check("${local.claude_cost_daily_burn_usd}" in (block("logtail_exploration_alert", "claude_cost_daily_burn") or ""),
      "burn: the email text interpolates the same threshold local (it cannot drift from value)")
for _n in ("claude_cost_daily_burn",):
    _qp, _cp, _rp = alert_attr(_n, "query_period"), alert_attr(_n, "check_period"), alert_attr(_n, "recovery_period")
    check(_qp == "86400" and _cp is not None and _rp is not None and _cp.isdigit() and _rp.isdigit() and int(_rp) >= int(_cp),
          f"{_n}: evaluates a 24 h window (query_period 86400) and recovery_period >= check_period — got {_qp}/{_cp}/{_rp}")
# Emitter parity: the literals every cost query matches on are the ones the TS emitters write.
check(re.search(r'pino\(\{ base: \{ component: "claude-cost" \} \}\)', marker_ts) is not None
      and "JSONExtractString(raw, 'message', 'component') = 'claude-cost'" in sqls.get("claude_cost_daily_burn", ""),
      "emitter parity: component 'claude-cost' is the marker logger's pino base AND the burn query's filter")
check(re.search(r"log\.warn\(\{ SOLEUR_CLAUDE_COST: true, \.\.\.m \}", marker_ts) is not None,
      "emitter parity: the marker writes the SOLEUR_CLAUDE_COST: true key the queries match")
check("source: `cron:${cronName}`" in substrate_ts,
      "emitter parity: the substrate writes source `cron:${cronName}` (the queries' LIKE 'cron:%')")
check("runbooks/betterstack-log-query.md" in sec, "the incidents carry a clickable runbook URL")
# The 524 alert's rows reach Better Stack only through vector.toml's inngest_journald source, and
# they are PRIORITY 6 while that source lists PRIORITY {3,4} since the #6551 partition: OBSERVED to ship anyway (the unit
# match admits them; see the .tf comment and #6551). That observed shape is pinned here, so ANY
# edit to the source's unit or PRIORITY filter reds this guard and forces a re-probe of the path
# (scripts/probe-inngest-524-count.sh prints unit_rows) before the alert can be trusted again.
_vsrc = re.search(r"^\[sources\.inngest_journald\]\n(.*?)(?=^\[|\Z)", vector, re.S | re.M)
_vbody = _vsrc.group(1) if _vsrc else ""
check(re.search(r'^include_units = \["inngest-server\.service", "inngest-trace-retention\.service", "soleur-inngest-tls\.service"\]\s*$', _vbody, re.M) is not None
      and re.search(r'^include_matches\.PRIORITY = \["3", "4"\]\s*$', _vbody, re.M) is not None
      and re.search(r'^exclude_matches\.SYSLOG_IDENTIFIER = ', _vbody, re.M) is not None
      and re.search(r'^exclude_matches\.CONTAINER_NAME = \["soleur-web-platform", "soleur-egress-gw"\]\s*$', _vbody, re.M) is not None
      and len(re.findall(r"^include_matches\.", _vbody, re.M)) == 1,
      "vector: the inngest_journald source is exactly the observed shape the 524 rows ship through (the three units + PRIORITY {3,4} + emitter/container excludes)")
# Routing is a PARSE of the real file, not a regex over its text: the old `inputs = [...\"inngest_journald\"` regex
# would now pass vacuously on the terminator filter's OWN `inputs = ["inngest_journald"]` line, whatever the PII
# stage reads. The 524 rows are inngest-server.service rows, so they must still reach the PII chain, now THROUGH
# the fail-open filter (which passes every row of any other unit unchanged).
import tomllib
_vcfg = tomllib.loads(vector)
_vtr = _vcfg.get("transforms", {})
_filt_in = _vtr.get("inngest_terminator_filter", {}).get("inputs", [])
_drop_in = _vtr.get("pii_scrub_drop_userdata", {}).get("inputs", [])
check(_filt_in == ["inngest_journald"] and "inngest_terminator_filter" in _drop_in and "inngest_journald" not in _drop_in,
      "vector: the 524 rows still ship - inngest_journald feeds the terminator filter and ONLY the filter feeds pii_scrub_drop_userdata (parsed, not matched)")
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

# ── Workflow seam: the battery cannot be muted or redirected from CI ──────────────────────────
# Comment-stripped executable text of infra-validation.yml: no MUT_SKIP or SPEND_GUARD_* literal
# may reach it (a step env: entry would mute or redirect this suite's battery without a trace),
# and this suite's own run line must be registered exactly once.
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
REG_RUN='        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh'
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this guard's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"
seam_bad=""
printf '%s\n' "$IV_CODE" | grep -nE 'SPEND_GUARD_' >/dev/null && seam_bad="$seam_bad SPEND_GUARD_-literal"
printf '%s\n' "$IV_CODE" | grep -nE 'MUT_SKIP' >/dev/null && seam_bad="$seam_bad MUT_SKIP-literal"
[ -z "$seam_bad" ] \
  && ok "no SPEND_GUARD_/MUT_SKIP literal reaches the workflow's executable text (env muting is barred)" \
  || no "workflow seam violated:$seam_bad — a guard env axis is reachable from infra-validation.yml"

echo ""
echo "=== inngest-step-524-alert guard: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi

# ── Mutation rows: each must make a row above RED ───────────────────────────────────────────
# OUTER RUN ONLY. Each row copies ONE source file into $MUT_DIR, mutates the copy, and re-runs this
# guard with MUT_SKIP=1 and the matching SPEND_GUARD_* override pointing at the copy.
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
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

  PRELUDE='def in_block(s, start_marker, old, new, end_marker="\n}\n"):
    i = s.index(start_marker); j = s.index(end_marker, i)
    assert s[i:j].count(old) == 1, "anchor"
    return s[:i] + s[i:j].replace(old, new) + s[j:]'

  _red_verdict() {
    case "$1" in
      1) if [ -z "$3" ] || { grep -F '[FAIL]' "$2" | grep -F -- "$3" >/dev/null; }; then echo red; else echo wrong; fi ;;
      0) echo survived ;;
      *) echo unresolved ;;
    esac
  }

  # mutate_red <label> <TF|WF|VEC|IV> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      VEC) src="$VEC"; copy="$MUT_DIR/vector.toml" ;;
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
    env "SPEND_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$olog" 2>&1 || rc=$?
    case "$(_red_verdict "$rc" "$olog" "$tag"):$want" in
      red:red) ok "mutation RED: $label" ;;
      wrong:wrong) ok "scorer control: graded WRONG reason as required: $label" ;;
      wrong:red) no "mutation went red for the WRONG reason (no [FAIL] line contains '$tag'): $label" ;;
      red:wrong) no "scorer control: the wrong-reason mutant was graded RED (the fragment check accepts anything): $label" ;;
      survived:*) no "mutation SURVIVED: $label — the rows above pin nothing" ;;
      *) no "mutation UNRESOLVED (inner rc=$rc, not an assertion): $label — instrument, not evidence" ;;
    esac
  }

  # mutate_green <label> <python-program-on-s> — TF-scoped must-PASS rows.
  mutate_green() {
    local label="$1" prog="$2" copy rc=0
    copy="$MUT_DIR/betterstack-logs-alerts.tf"
    cp "$TF" "$copy" || { printf '[FATAL] mutate_green: cp failed\n' >&2; exit 2; }
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
    SPEND_GUARD_TF="$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
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

  # The `<<-` openers below are COMPOSED at runtime — a literal opener anywhere in this file's
  # scanned text would open a phantom heredoc span and hide the assertion floor from
  # guard-vacuity-floor.test.sh (the batch-3 premise).
  H524="inngest_step_524_sql = <<-${Z:-}SQL"; HBURN="claude_cost_daily_burn_sql = <<-${Z:-}SQL"

  # ── Dead-text / extraction-class rows ────────────────────────────────────────────────────────
  mutate_red "a /* */-wrapped decoy heredoc sits before the 524 local while the live body is gutted" TF \
    "i = s.index('$H524'); i = s.index('\n', i) + 1; j = s.index('\n  SQL\n', i)
s = s[:i] + '    SELECT 1\n' + s[j:]
i = s.index('$H524')
s = s[:i] + '/*\n  inngest_step_524_sql = <<\x2dSQL\n  SELECT legit\n  SQL\n*/\n' + s[i:]" \
    "decoy copies count"
  mutate_red "the live 524 local is gutted to a placeholder while the resources keep their names" TF \
    "i = s.index('$H524'); i = s.index('\n', i) + 1; j = s.index('\n  SQL\n', i)
s = s[:i] + '    SELECT 1\n' + s[j:]" \
    "byte-exact"
  mutate_red "a #-commented decoy opener line sits above the burn local" TF \
    "i = s.index('$HBURN')
s = s[:i] + '  # claude_cost_daily_burn_sql = <<\x2dSQL\n' + s[i:]" \
    "decoy copies count"
  mutate_red "a commented-out paused=false decoy line appears inside the 524 alert block" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"inngest_step_524\"', '  paused = false\n', '  paused = false\n  # paused = false\n')" \
    "occurs exactly once"
  mutate_red "an inline tautology is appended inside the 524 predicate" TF \
    "s = in_block(s, '$H524', '    GROUP BY time', '    GROUP BY time OR 1=1', '  SQL\n')" \
    "tautology"
  mutate_red "a doubled-dollar escape silences the burn window filter" TF \
    "s = in_block(s, '$HBURN', 'WHERE dt BETWEEN {{start_time}}', 'WHERE dt BETWEEN \x24\x24{{start_time}}', '  SQL\n')" \
    "dt column"
  mutate_red "discovery floor: the burn exploration resource is deleted (fewer than floor found)" TF \
    "i = s.index('resource \"logtail_exploration\" \"claude_cost_daily_burn\" {')
j = s.index('\n}\n', i)
s = s[:i] + s[j + 3:]" \
    "floor 2"

  # Row 1 — the 524 literal changes.
  mutate_red "1: the 524 literal changes" TF \
    "s = in_block(s, '$H524', \"'invalid status code: 524'\", \"'invalid status code: 504'\", '  SQL\n')" \
    "every measured positive text"
  mutate_red "1b: the 524 field path moves off message.error" TF \
    "s = in_block(s, '$H524', \"JSONExtractString(raw, 'message', 'error')\", \"JSONExtractString(raw, 'message', 'msg')\", '  SQL\n')" \
    "needle array reads message.error"
  # Row 3 — a -target= line disappears.
  mutate_red "3b: the 524 exploration is dropped from the apply allowlist" WF \
    'old = "              -target=logtail_exploration.inngest_step_524 \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "allowlist"
  # Row 4 — cost read at the top level / key match dropped (in the NON-first cost exploration).
  mutate_red "4: burn reads top-level cost_usd" TF \
    "s = in_block(s, '$HBURN', \"sum(JSONExtractFloat(raw, 'message', 'cost_usd'))\", \"sum(JSONExtractFloat(raw, 'cost_usd'))\", '  SQL\n')" \
    "nested raw.message"
  # Row 5 — a raw message column / a free-text GROUP BY.
  mutate_red "5b: the 524 query groups on free text" TF \
    "s = in_block(s, '$H524', '    GROUP BY time', \"    GROUP BY time, JSONExtractString(raw, 'message', 'error')\", '  SQL\n')" \
    "no free-text grouping"
  # Row 6 — a PRIORITY filter on the 524 query.
  mutate_red "6: the 524 query gains a PRIORITY filter" TF \
    "s = in_block(s, '$H524', \"      AND JSONExtractString(raw, '_SYSTEMD_UNIT')\", \"      AND JSONExtractString(raw, 'PRIORITY') = '2'\n      AND JSONExtractString(raw, '_SYSTEMD_UNIT')\", '  SQL\n')" \
    "PRIORITY filter"
  # Row 7 — the whole-window burn filters on its constant time alias (sums all history).
  mutate_red "7: burn's window filter moves onto the time alias" TF \
    "s = in_block(s, '$HBURN', 'WHERE dt BETWEEN', 'WHERE time BETWEEN', '  SQL\n')" \
    "dt column"
  mutate_red "8b: the 524 alert is paused" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"inngest_step_524\"', '  paused = false\n', '  paused = true\n')" \
    "unpaused"
  # Needle rows — every needle is exercised against its own measured text, and negatives stay quiet.
  mutate_red "N1: the 524 needle is broadened to any status code" TF \
    "s = in_block(s, '$H524', \"'invalid status code: 524'\", \"'invalid status code'\", '  SQL\n')" \
    "does NOT match"
  mutate_red "N2: a stream-drop needle is typo'd" TF \
    "s = in_block(s, '$H524', \"'error parsing stream: error reading response body'\", \"'error parsing strem: nothing matches this'\", '  SQL\n')" \
    "stale or typo"
  mutate_red "N3: both stream-drop needles are deleted" TF \
    "s = in_block(s, '$H524', \", 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply'\", '', '  SQL\n')" \
    "every measured positive text"
  # Negation / tautology / widening rows (the survivors of the #8611 review's test-design seat).
  mutate_red "G4: the 524 needle predicate is negated" TF \
    "s = in_block(s, '$H524', 'AND multiSearchAny(', 'AND NOT multiSearchAny(', '  SQL\n')" \
    "no negation"
  mutate_red "G5: burn's cron-source filter is negated" TF \
    "s = in_block(s, '$HBURN', \"AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\", \"AND NOT JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\", '  SQL\n')" \
    "no negation"
  mutate_red "G6: burn's SOLEUR_CLAUDE_COST key match is negated" TF \
    "s = in_block(s, '$HBURN', \"AND raw LIKE '%\\\"SOLEUR_CLAUDE_COST\\\":true%'\", \"AND NOT raw LIKE '%\\\"SOLEUR_CLAUDE_COST\\\":true%'\", '  SQL\n')" \
    "no negation"
  mutate_red "G11: burn's window gains an OR that sums all history" TF \
    "s = in_block(s, '$HBURN', 'WHERE dt BETWEEN {{start_time}} AND {{end_time}}\n', 'WHERE dt BETWEEN {{start_time}} AND {{end_time}}\n      OR dt < {{end_time}}\n', '  SQL\n')" \
    "no OR"
  mutate_red "G12: burn splits its sum with a lowercase group by source" TF \
    "s = in_block(s, '$HBURN', \"      AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\n\", \"      AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'\n    group by JSONExtractString(raw, 'message', 'source')\n\", '  SQL\n')" \
    "no free-text grouping"
  mutate_red "G13: the 524 query loses its time-window filter" TF \
    "s = in_block(s, '$H524', '    WHERE time BETWEEN {{start_time}} AND {{end_time}}\n      AND JSONExtractString', '    WHERE JSONExtractString', '  SQL\n')" \
    "time-window filter"
  # Window / threshold rows.
  mutate_red "Q1: burn's query_period shrinks to 300 s" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_daily_burn\"', 'query_period        = 86400', 'query_period        = 300')" \
    "24 h window"
  mutate_red "T1: burn's value is hardcoded apart from the threshold local" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"claude_cost_daily_burn\"', 'value               = local.claude_cost_daily_burn_usd', 'value               = 15')" \
    "pages above"

  mutate_red "V1: vector's inngest_journald source loses the inngest-server unit" VEC \
    "s = s.replace('include_units = [\"inngest-server.service\", \"inngest-trace-retention.service\", \"soleur-inngest-tls.service\"]', 'include_units = [\"inngest-other.service\", \"inngest-trace-retention.service\", \"soleur-inngest-tls.service\"]', 1)" \
    "observed shape"
  mutate_red "V2: vector's inngest_journald PRIORITY filter changes" VEC \
    "s = s.replace('include_matches.PRIORITY = [\"3\", \"4\"]\n', 'include_matches.PRIORITY = [\"3\"]\n', 1)" \
    "observed shape"
  mutate_red "V3: the PII stage reads the raw inngest_journald again (the terminator filter is unwired)" VEC \
    "s = s.replace('inputs = [\"inngest_terminator_filter\", \"system_journald\"', 'inputs = [\"inngest_journald\", \"system_journald\"', 1)" \
    "terminator filter"

  # ── Workflow seam rows ─────────────────────────────────────────────────────────────────────
  mutate_red "a MUT_SKIP literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          MUT_SKIP: \"1\"\n" + old)' \
    "workflow seam"
  mutate_red "a SPEND_GUARD_ literal reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          SPEND_GUARD_TF: /dev/null\n")' \
    "workflow seam"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"

  # ── Scorer negative control ────────────────────────────────────────────────────────────────
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"inngest_step_524\"', '  paused = false\n', '  paused = true\n')" \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "a comment-only edit to the tf" \
    's = s + "\n# control comment\n"'
  mutate_green "whitespace reflow of the 524 needle array" \
    "s = in_block(s, '$H524', \"'invalid status code: 524', 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply'\", \"'invalid status code: 524',\n        'error parsing stream: error reading response body',\n        'Your server reset the connection while we were reading the reply'\", '  SQL\n')"
  # S1 folded into mutate_green (deliberate): a must-PASS row IS the control — a later section
  # appended below this one (the .tf's own recipe) is out of scope, so a future alert with a
  # different select shape cannot trip the discovery slice. The heredoc opener is written as
  # \x2d inside the python string so this file's scanned text carries no literal dash-opener.
  mutate_green "S1: an appended later alert section is out of this guard's scope" \
    's = s + "\n# ── #9999 / ADR-999: a future alert ──\nlocals {\n  future_sql = <<\x2dSQL\n    SELECT {{time}} AS time, countIf(raw LIKE \x27%x%\x27) AS value\n    FROM {{source}}\n    GROUP BY time\n  SQL\n}\n\nresource \"logtail_exploration\" \"future_alert\" {\n}\n"'

  # C1 stays hand-rolled (deliberate): it asserts an instrument-CLASS exit (rc 2), which neither
  # mutate_red (rc 1 only) nor mutate_green (rc 0 only) can grade; its inner log is captured for
  # the same reason as the battery's $olog.
  cp "$TF" "$MUT_DIR/c1.tf" || { printf '[FATAL] C1: cp failed\n' >&2; exit 2; }
  printf '\xff\xfe' >>"$MUT_DIR/c1.tf"
  if cmp -s "$TF" "$MUT_DIR/c1.tf"; then no "C1 did not land"; else
    c1_rc=0; SPEND_GUARD_TF="$MUT_DIR/c1.tf" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/c1.log" 2>&1 || c1_rc=$?
    if [ "$c1_rc" -eq 2 ]; then ok "C1: a crashed checker exits FATAL 2, not an assertion's 1"
    else no "C1: a crashed checker exited $c1_rc (must be 2) — a crash would grade as a caught mutation"; fi
  fi

  echo ""
  echo "=== inngest-step-524-alert guard + mutations: $pass passed, $fail failed ==="
fi

# ── Assertion floor + ledger (constructible: pure assignments only inside the window) ────────
# PRESENCE_ROWS is discovery-coupled: the suite discovers explorations per section and refuses
# fewer than 2 discovered (its own pin above); the count below pins today's real 2-discovered
# shape — a future alert that grows the section is exactly the drift the floor exists to red.
# Raise both constants in the same edit that adds a row. Floor/ledger trips exit 1 (verdict
# class, so mutate_floor_red can grade them); instrument failures exit 2.
PRESENCE_ROWS=62
MUT_ROWS=38
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); SPEND_GUARD_{TF,WF,VEC,IV}=%s,%s,%s,%s\n' "$_floor" "${SPEND_GUARD_TF:-unset}" "${SPEND_GUARD_WF:-unset}" "${SPEND_GUARD_VEC:-unset}" "${SPEND_GUARD_IV:-unset}"
printf '\n=== inngest-step-524-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
