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
#   * Every discovered alert's paging windows are pinned exactly (the 524's 900/300/0/1800 and
#     the burn's 86400/3600/0/3600 — query/check/confirmation/recovery), plus name, alert_type,
#     email and the escalation ternary on each; the burn threshold is
#     local.claude_cost_daily_burn_usd, interpolated into value AND email.
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
#     The source's include_units array is pinned WHOLE — whatever unit set the file carries at read
#     time (today inngest-server, trace-retention and the TLS terminator); its rows reach the PII
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
EMIT_MARKER="${SPEND_GUARD_EMIT_MARKER:-$REPO/apps/web-platform/server/claude-cost-marker.ts}"
EMIT_SUBSTRATE="${SPEND_GUARD_EMIT_SUBSTRATE:-$REPO/apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts}"
EMIT_PROBE="${SPEND_GUARD_EMIT_PROBE:-$REPO/apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts}"
for f in "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable emitter: %s\n' "$f" >&2; exit 2; }
done

# A checker CRASH is this guard's FATAL class (rc 2), never an assertion: mutate_red grades only
# rc 1 as caught, so a mutation that merely crashes python cannot be credited as a kill.
CHECKS="$(python3 - "$TF" "$WF" "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE" "$VEC" <<'PY'
import json, re, sys
tf = open(sys.argv[1], encoding="utf-8").read()
wf = open(sys.argv[2], encoding="utf-8").read()
def ts_code(path):
    # The graded .ts view strips `//` comments — full-line AND trailing — plus `/* … */` blocks
    # first, so a commented-out decoy carrying a needle can never satisfy a re.search below
    # (#11899). `(?<!:)//` keeps `https://`-style URL literals inside strings intact.
    s = open(path, encoding="utf-8").read()
    s = re.sub(r"(?m)(?<!:)//.*$", "", s)
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)
marker_ts = ts_code(sys.argv[3])
substrate_ts = ts_code(sys.argv[4])
probe_ts = ts_code(sys.argv[5])
vector = open(sys.argv[6], encoding="utf-8").read()
# The push-triggered MAIN plan only: first `terraform plan -no-color` to the first `rc=` at
# line-start below it (the plan step's own rc=${PIPESTATUS[0]} capture — pinned by the check just
# below, so a deleted/renamed/moved capture reds instead of silently overshooting to a later rc=
# or running to EOF). The workflow has ~15 plan regions whose -target lists never run on a push
# to main — the allowlist rows read THIS region, not the whole file (sibling-parity; security P2).
_mp = re.search(r"^[ \t]*terraform plan -no-color.*?(?:^[ \t]*rc=[^\n]*|\Z)", wf, re.S | re.M)
main_plan = _mp.group(0) if _mp else ""
out = []
def check(cond, msg): out.append(("OK " if cond else "FAIL ") + msg)
_mp_tail = main_plan.rstrip("\n").rsplit("\n", 1)[-1] if main_plan else ""
check(re.fullmatch(r"[ \t]*rc=\$\{PIPESTATUS\[0\]\}", _mp_tail) is not None,
      "the MAIN plan slice terminates on the plan step's own rc=${PIPESTATUS[0]} capture — a deleted or renamed capture line would reopen the run-to-EOF overshoot")

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
# Paging-attribute pins for EVERY discovered alert — not only the first or the convenient
# subset (#11899): all four periods, name, alert_type, email, and the escalation ternary, each
# value canon-derived from the .tf blocks, exactly-once via alert_attr/param (a duplicated
# attr line yields None, never a first-match).
ALERT_PINS = {
    "inngest_step_524": {
        "query_period": "900", "check_period": "300", "confirmation_period": "0", "recovery_period": "1800",
        "name": '"soleur-inngest-step-524-prd"', "alert_type": '"threshold"', "email": "true",
    },
    "claude_cost_daily_burn": {
        "query_period": "86400", "check_period": "3600", "confirmation_period": "0", "recovery_period": "3600",
        "name": '"soleur-claude-cost-daily-burn-prd"', "alert_type": '"threshold"', "email": "true",
    },
}
for _n, _pins in ALERT_PINS.items():
    _alr = block("logtail_exploration_alert", _n) or ""
    for _attr in ("query_period", "check_period", "confirmation_period", "recovery_period",
                  "name", "alert_type", "email"):
        check(alert_attr(_n, _attr) == _pins[_attr],
              f"{_n}: {_attr} is {_pins[_attr]} (canon-derived, exactly-once) — got {alert_attr(_n, _attr)!r}")
    check(param(_alr, "policy_id", r"var\.betterstack_paid_tier \? tonumber\(betteruptime_policy\.uptime\[0\]\.id\) : null")
          and param(_alr, "team_name", r"var\.betterstack_paid_tier \? null : \"Your team\""),
          f"{_n}: escalation_target is the free/paid-tier ternary every sibling uses")
# Emitter contract literals the burn query matches on — SOLEUR_CLAUDE_COST, claude-cost,
# cost_usd, cron: — asserted across the stripped .ts corpus (they live in the marker and
# substrate emitters). probe_ts gets its own pin so the read can never go dead: its rows
# land as source=cron:cron-anthropic-credit-probe through the markerSource hook.
EMIT_ALL = marker_ts + substrate_ts + probe_ts
for lit in ("SOLEUR_CLAUDE_COST", "claude-cost", "cost_usd", "cron:"):
    check(lit in EMIT_ALL, f"the emitter corpus carries '{lit}' (a burn-query contract literal)")
check("markerSource: CRON_NAME" in probe_ts and 'CRON_NAME = "cron-anthropic-credit-probe"' in probe_ts,
      "probe: the credit canary still emits via markerSource: CRON_NAME (a dead probe_ts read is now a pin)")
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

# ── Workflow seam — registered, unconditionally blocking, and no env axis may reach it ───────
# Comment-stripped executable text of infra-validation.yml: this suite's own run line must be
# registered exactly once (an inline ` # MUT_SKIP` still reds — deliberate over-caution).
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
REG_RUN='        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh'
n_run="$(printf '%s\n' "$IV_CODE" | grep -cFx "$REG_RUN")"
[ "$n_run" -eq 1 ] \
  && ok "this guard's run line is registered in infra-validation.yml exactly once" \
  || no "run line count is $n_run, want 1 — the suite is unregistered or double-registered"

# A CI-dead guard must not pass. The step: ONLY the keys name + run — a `shell:`/`env:`/`with:`/
# `if:`/`continue-on-error:` (or any unrecognised line shape) flags, with if:/continue-on-error:
# read at BOTH `        ` and `      - ` positions (the `      - ` dash-line boundary is the
# flush() edge the step block is cut on). The HOSTING JOB is derived from the step's position
# (the last `jobs:`-level header above the run line — a quoted id or a trailing-comment header
# included), never named here, and is read WHOLE (header, steps, anything after them: YAML key
# order is free): `continue-on-error` must appear NOWHERE in it (post-steps included), its `if:`
# must be the one known literal (total == 1), `needs:`/`runs-on:` the known literals, and its
# own keys the known set {name needs if runs-on permissions timeout-minutes steps} — no
# `defaults`/`env`/`container`/`strategy`/`services` … . The workflow itself carries no top-level
# `defaults:` and no env-composition FRAGMENT — {MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS,
# BASHOPTS} — so literal, runtime-composed ("MUT_""SKIP"), *_GUARD_*-prefixed (SPEND_GUARD_ and
# the EMIT_* axes included) and shell-injection env muting are all barred; and no
# GITHUB_ENV/GITHUB_PATH/defaults: inside the hosting job. The verdict must also REACH the
# aggregator (a job needing the host, under if: always(), reading its result and carrying its
# entries slot), so dropping the leg is not a quiet way to make this guard CI-dead. Every
# violation accrues to the composite verdict below — slice-validity folds in, so no ban can
# pass vacuously on an empty or missed slice.
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
JOB_NEEDS="$(awk '/^    needs:/ { print }' <<<"$JOB_BLOCK")"
JOB_RUNS_ON="$(awk '/^    runs-on:/ { print }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Anything else (or an
# unrecognised line shape) is listed by name — env:/shell:/with:/if:/continue-on-error: included.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
WF_BAD=""
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && WF_BAD="$WF_BAD top-level-defaults"
# Fragments, not literals (#11899): a runtime-composed name ("MUT_""SKIP", a GUARD-fragment
# prefix) or a shell-injection env (BASH_ENV/SHELLOPTS/BASHOPTS) reaches the step with no
# literal present — MUT_/_SKIP cover MUT_SKIP at either split, GUARD covers every *_GUARD_* axis
# (SPEND_GUARD_ included — no separate literal grep needed).
_seam_frag=""
for _frag in 'MUT_' '_SKIP' 'GUARD' 'BASH_ENV' 'SHELLOPTS' 'BASHOPTS'; do
  printf '%s\n' "$IV_CODE" | grep -nF -- "$_frag" >/dev/null && _seam_frag="$_seam_frag ${_frag}-fragment"
done
[ -n "$_seam_frag" ] && WF_BAD="$WF_BAD suite-seam-in-workflow:$_seam_frag"
# The only DYNAMIC channel: a $GITHUB_ENV/$GITHUB_PATH write or a job-local defaults: inside the
# hosting job. An empty JOB_BLOCK reds the composite below via job-slice-empty AND the slice-
# validity conjuncts, so the ban cannot pass vacuously.
if [ -z "$JOB_BLOCK" ]; then
  WF_BAD="$WF_BAD job-slice-empty"
else
  _job_seam=""
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'GITHUB_ENV' >/dev/null && _job_seam="$_job_seam GITHUB_ENV"
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'GITHUB_PATH' >/dev/null && _job_seam="$_job_seam GITHUB_PATH"
  printf '%s\n' "$JOB_BLOCK" | grep -nF 'defaults:' >/dev/null && _job_seam="$_job_seam defaults:"
  [ -n "$_job_seam" ] && WF_BAD="$WF_BAD job-scope-env-write:$_job_seam"
fi
# The aggregator: every job (other than the host) whose `needs:` names the host; one of them must
# run under if: always() AND read needs.<host>.result AND carry "<host>:$" in its entries array.
AGG_CANDS="$(awk -v host="$HOST_JOB" "$AWK_HDR"'
  function emit(l,   n, t, i) { sub(/[ \t]#.*$/, "", l); gsub(/[\[\],"\047]/, " ", l); n = split(l, t, /[ \t]+/); for (i = 1; i <= n; i++) if (t[i] == host && job != host) print job }
  /^[[:space:]]*#/ { next }
  { h = hdr($0); if (h != "") { job = h; innd = 0; next } }
  job == "" { next }
  /^    needs:/ { innd = 1; l = $0; sub(/^    needs:/, "", l); emit(l); next }
  innd && /^      -/ { l = $0; sub(/^      -/, "", l); emit(l); next }
  /^    [A-Za-z_-]+:/ { innd = 0 }' <<<"$IV_CODE")"
AGG_OK=0; AGG_NAMES=""
if [ -n "$HOST_JOB" ]; then
  while IFS= read -r _agg; do
    [ -n "$_agg" ] || continue
    AGG_NAMES="$AGG_NAMES $_agg"
    _agg_block="$(awk -v j="$_agg" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f { print }' <<<"$IV_CODE")"
    if [[ $'\n'"$_agg_block" == *$'\n    if: always()'* ]] && [[ "$_agg_block" == *"needs.${HOST_JOB}.result"* ]] && [[ "$_agg_block" == *"\"${HOST_JOB}:\$"* ]]; then AGG_OK=1; fi
  done <<<"$AGG_CANDS"
fi
if [ -n "$STEP_BLOCK" ] && [[ "$STEP_BLOCK" != *continue-on-error* ]] && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
   && [ -z "$STEP_BAD" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] && [ -z "$JOB_BAD" ] && [ -z "$WF_BAD" ] \
   && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
   && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ] && [ "$AGG_OK" -eq 1 ]; then
  ok "the registered step has only name+run keys (no continue-on-error / if: / shell / env / ...), its hosting job '$HOST_JOB' (derived from the step's position) has the one known if:, needs and runs-on, the known key set and no continue-on-error anywhere, the workflow carries no top-level defaults: or suite-seam fragment, and the verdict reaches the aggregator ('${AGG_NAMES# }': if: always(), the leg's result, its entries slot): it cannot be skipped, non-blocking, redirected or dropped"
else
  no "infra-validation.yml: the registered step or its hosting job '$HOST_JOB' is conditional, non-blocking, redirected or unaggregated (step keys beyond name/run: '${STEP_BAD//$'\n'/ }'; job keys beyond the known set: '${JOB_BAD//$'\n'/ }'; workflow:${WF_BAD:- none}; aggregator ok=$AGG_OK; continue-on-error anywhere in the job; an if:/needs/runs-on other than the known literals), or could not be located"
fi

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

  # mutate_red <label> <TF|WF|VEC|IV|EMIT_MARKER|EMIT_SUBSTRATE|EMIT_PROBE> <python-program-on-s> [expected [FAIL] fragment] [red|wrong]
  mutate_red() {
    local label="$1" which="$2" prog="$3" tag="${4:-}" want="${5:-red}" src copy rc=0 olog="$MUT_DIR/inner.log"
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      VEC) src="$VEC"; copy="$MUT_DIR/vector.toml" ;;
      IV)  src="$IV";  copy="$MUT_DIR/infra-validation.yml" ;;
      EMIT_MARKER)    src="$EMIT_MARKER";    copy="$MUT_DIR/claude-cost-marker.ts" ;;
      EMIT_SUBSTRATE) src="$EMIT_SUBSTRATE"; copy="$MUT_DIR/_cron-claude-eval-substrate.ts" ;;
      EMIT_PROBE)     src="$EMIT_PROBE";     copy="$MUT_DIR/cron-anthropic-credit-probe.ts" ;;
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

  # mutate_green <label> <TF|WF|VEC|IV> <python-program-on-s> — a legitimate edit must NOT red
  # the guard. Axis-widened past the donor's TF-only shape so the wiring must-PASS controls
  # ride the same helper.
  mutate_green() {
    local label="$1" which="$2" prog="$3" src copy rc=0
    case "$which" in
      TF)  src="$TF";  copy="$MUT_DIR/betterstack-logs-alerts.tf" ;;
      WF)  src="$WF";  copy="$MUT_DIR/apply-web-platform-infra.yml" ;;
      VEC) src="$VEC"; copy="$MUT_DIR/vector.toml" ;;
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
    env "SPEND_GUARD_${which}=$copy" MUT_SKIP=1 bash "$SELF" >"$MUT_DIR/green.log" 2>&1 || rc=$?
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
    "query_period is 86400"
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
    "suite-seam-in-workflow"
  mutate_red "a SPEND_GUARD_ literal reaches the workflow's executable text (the GUARD fragment sees it)" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "        env:\n          SPEND_GUARD_TF: /dev/null\n")' \
    "suite-seam-in-workflow"
  mutate_red "the suite's own run line is dropped from the workflow" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' \
    "unregistered or double-registered"
  mutate_red "a runtime-composed MUT_/SKIP name is written to \$GITHUB_ENV inside the job" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"MUT_\"\"SKIP=1\" >> \"$GITHUB_ENV\"\n")' \
    "suite-seam-in-workflow"
  mutate_red "a foreign-prefix *_GUARD_* env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          FOO_GUARD_X: /dev/null\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a BASH_ENV shell-injection env reaches the workflow's executable text" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env:\n          BASH_ENV: /tmp/x\n" + old)' \
    "suite-seam-in-workflow"
  mutate_red "a \$GITHUB_ENV write lands inside the suite's own job" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, old + "      - run: echo \"POISON=1\" >> \"$GITHUB_ENV\"\n")' \
    "job-scope-env-write"
  mutate_red "a top-level defaults: is added to the workflow (the file-wide ban is keyed on column 0)" IV \
    'old = "\nenv:\n  TERRAFORM_VERSION"
assert s.count(old) == 1
s = s.replace(old, "\ndefaults:\n  run:\n    shell: /bin/true {0}\nenv:\n  TERRAFORM_VERSION")' \
    "top-level-defaults"

  # ── Step/job-shape rows: an if:/continue-on-error: or a foreign key on the step or job would
  # mute this suite — read at BOTH `        ` and `      - ` positions across the WHOLE job block.
  mutate_red "the suite's step becomes conditional (if: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        if: false\n" + old)' \
    "name/run: 'if'"
  mutate_red "the suite's step opens with a dash-line if: (the step body never runs)" IV \
    'old = "      - name: Run Anthropic-spend alerts drift guard (#8611)\n"
assert s.count(old) == 1
s = s.replace(old, "      - if: false\n        name: Run Anthropic-spend alerts drift guard (#8611)\n")' \
    "name/run: 'if'"
  mutate_red "the suite's step becomes non-blocking (continue-on-error: at step indent)" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        continue-on-error: true\n" + old)' \
    "name/run: 'continue-on-error'"
  mutate_red "the suite's step gets an env: key (only name+run are legal on a step)" IV \
    'old = "        run: bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "        env: {NEUTRAL: \"1\"}\n" + old)' \
    "name/run: 'env'"
  mutate_red "the suite's job becomes non-blocking (continue-on-error: on the job)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n"
assert s.count(old) == 1
s = s.replace(old, old + "    continue-on-error: true\n")' \
    "known set: 'continue-on-error'"
  mutate_red "a continue-on-error: is placed AFTER the job's steps (key order is free in YAML)" IV \
    'old = "\n  deploy-script-tests-done:\n"
assert s.count(old) == 1
s = s.replace(old, "\n    continue-on-error: true\n\n  deploy-script-tests-done:\n")' \
    "known set: 'continue-on-error'"
  mutate_red "the suite's job gets a job-level env: key (outside the known key set)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    env: {NEUTRAL: \"1\"}\n")' \
    "known set: 'env'"
  mutate_red "a second, differing job-level if: is appended (the job's if: must be the one literal)" IV \
    'old = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != \x27true\x27\n    runs-on: ubuntu-24.04\n"
assert s.count(old) == 1
s = s.replace(old, old + "    if: github.event_name == \x27push\x27\n")' \
    "an if:/needs/runs-on other than the known literals"

  # ── MAIN_PLAN bound rows: the slice must end at the first rc= line-start on the plan step's
  # own rc=${PIPESTATUS[0]} capture — delete/rename/move it and the assert reds. ─────────────
  mutate_red "the plan step's rc= capture line is deleted (the slice would silently run to a later rc=)" WF \
    'old = "              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n          rc=\x24{PIPESTATUS[0]}\n"
assert s.count(old) == 1
s = s.replace(old, "              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n")' \
    "the MAIN plan slice terminates on the plan step"
  mutate_red "the plan step's rc= capture is renamed to plan_rc= (the terminator misses)" WF \
    'old = "          rc=\x24{PIPESTATUS[0]}\n"
i = s.index("              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n")
j = s.index(old, i)
s = s[:j] + "          plan_rc=\x24{PIPESTATUS[0]}\n" + s[j + len(old):]' \
    "the MAIN plan slice terminates on the plan step"
  mutate_red "the plan step's rc= capture moves ABOVE the -target= lines (the bounded slice misses them)" WF \
    'old = "          rc=\x24{PIPESTATUS[0]}\n"
i = s.index("              -target=supabase_project.prd 2>&1 | tf_redact_random_ids\n")
j = s.index(old, i)
s = s[:j] + s[j + len(old):]
k = s.index("            terraform plan -no-color -input=false -out=tfplan \\\n")
k = s.index("\n", k) + 1
s = s[:k] + old + s[k:]' \
    "in the apply -target= allowlist"

  # ── Emitter (comment-strip + provenance) rows ──────────────────────────────────────────────
  mutate_red "a //-comment decoy carries the marker needle while the real emitter line is gone" EMIT_MARKER \
    'old = "    log.warn({ SOLEUR_CLAUDE_COST: true, ...m }, \"claude cost\");\n"
assert s.count(old) == 1
s = s.replace(old, "    // log.warn({ SOLEUR_CLAUDE_COST: true, ...m }, \"claude cost\");\n")' \
    "emitter parity"
  mutate_red "a trailing //-comment decoy carries the needle while the real emitter key is gone" EMIT_MARKER \
    'old = "    log.warn({ SOLEUR_CLAUDE_COST: true, ...m }, \"claude cost\");\n"
assert s.count(old) == 1
s = s.replace(old, "    log.warn({ OTHER: true, ...m }, \"claude cost\"); // SOLEUR_CLAUDE_COST: true\n")' \
    "SOLEUR_CLAUDE_COST: true key"
  mutate_red "the probe emitter is emptied (a dead probe_ts read must not satisfy the pin)" EMIT_PROBE \
    's = ""' \
    "markerSource: CRON_NAME"

  # ── Scorer negative control ────────────────────────────────────────────────────────────────
  mutate_red "scorer control: paused-flip reds a different row than the named fragment" TF \
    "s = in_block(s, 'resource \"logtail_exploration_alert\" \"inngest_step_524\"', '  paused = false\n', '  paused = true\n')" \
    "this-fragment-does-not-exist" wrong

  # ── Floor row ──────────────────────────────────────────────────────────────────────────────
  mutate_floor_red "assertion floor trips when PRESENCE_ROWS is bumped one past the real count"

  # ── must-PASS rows ─────────────────────────────────────────────────────────────────────────
  mutate_green "a comment-only edit to the tf" TF \
    's = s + "\n# control comment\n"'
  mutate_green "whitespace reflow of the 524 needle array" TF \
    "s = in_block(s, '$H524', \"'invalid status code: 524', 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply'\", \"'invalid status code: 524',\n        'error parsing stream: error reading response body',\n        'Your server reset the connection while we were reading the reply'\", '  SQL\n')"
  # S1 folded into mutate_green (deliberate): a must-PASS row IS the control — a later section
  # appended below this one (the .tf's own recipe) is out of scope, so a future alert with a
  # different select shape cannot trip the discovery slice. The heredoc opener is written as
  # \x2d inside the python string so this file's scanned text carries no literal dash-opener.
  mutate_green "S1: an appended later alert section is out of this guard's scope" TF \
    's = s + "\n# ── #9999 / ADR-999: a future alert ──\nlocals {\n  future_sql = <<\x2dSQL\n    SELECT {{time}} AS time, countIf(raw LIKE \x27%x%\x27) AS value\n    FROM {{source}}\n    GROUP BY time\n  SQL\n}\n\nresource \"logtail_exploration\" \"future_alert\" {\n}\n"'
  # Over-breadth control: a $GITHUB_ENV write inside a DIFFERENT job (plan:) is legitimate —
  # the enclosing-job slice must not reach past this suite's own job block.
  mutate_green "a \$GITHUB_ENV write inside a different job (the plan: job) stays green" IV \
    'old = "          printf \x27AWS_SECRET_ACCESS_KEY=%s\\n\x27 \"$SECRET\" >> \"$GITHUB_ENV\"\n"
assert s.count(old) == 1
s = s.replace(old, old + "          echo \"CROSS_JOB=1\" >> \"$GITHUB_ENV\"\n")'

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
# Self-reference (accepted residual, #11899 item 8): a row-count decrement landing alongside a
# row deletion stays green — PRESENCE_ROWS/MUT_ROWS are declared here and read only below.
PRESENCE_ROWS=83
MUT_ROWS=58
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
[ -n "${MUT_SKIP:-}" ] && printf '[note] MUT_SKIP active — mutation rows skipped (floor %s); SPEND_GUARD_{TF,WF,VEC,IV,EMIT_MARKER,EMIT_SUBSTRATE,EMIT_PROBE}=%s,%s,%s,%s,%s,%s,%s\n' "$_floor" "${SPEND_GUARD_TF:-unset}" "${SPEND_GUARD_WF:-unset}" "${SPEND_GUARD_VEC:-unset}" "${SPEND_GUARD_IV:-unset}" "${SPEND_GUARD_EMIT_MARKER:-unset}" "${SPEND_GUARD_EMIT_SUBSTRATE:-unset}" "${SPEND_GUARD_EMIT_PROBE:-unset}"
printf '\n=== inngest-step-524-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
