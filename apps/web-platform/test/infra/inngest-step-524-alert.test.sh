#!/usr/bin/env bash
#
# Drift guard for the #8611 / ADR-243 Anthropic-spend Better Stack Logs alerts
# (apps/web-platform/infra/betterstack-logs-alerts.tf, the section headed `#8611 / ADR-243`):
#   inngest_step_524         — a step was cut at the Cloudflare proxy (the double-run's cause)
#   claude_cost_daily_burn   — the cron fleet spent more than $15 in a trailing 24 h
#   claude_cost_capture_dark — the cost telemetry itself went dark for 24 h
#
# Guard 2 of the #8611 plan: every alert queries what its emitter writes, and nothing more.
#   * The 524 predicate matches a SYNTHESIZED row of the observed emitter shape (inngest-server
#     journald line, PRIORITY 6, the literal under message.error) — so a changed literal, a changed
#     field path or a changed unit is caught against the shape, not against a copy of the SQL.
#   * No PRIORITY filter on the 524 query: the live lines are PRIORITY 6.
#   * Every exploration in the section reads the vector source through the pinned local.
#   * Every cost-reading exploration reads cost_usd at its NESTED path (raw.message, since #8344)
#     and keeps the `"SOLEUR_CLAUDE_COST":true` key match (without it the _DAILY org-total rows sum
#     in). Iterated over EVERY exploration that reads cost_usd, not the first.
#   * Aggregates only: the select list is a time expression plus one count/sum, and GROUP BY is
#     `time` or absent. The inngest-server line can carry queue-item payloads (email data).
#   * A whole-window (no-bucket) query filters on the `dt` column: its `time` alias is a constant,
#     so `time BETWEEN …` would be always-true and sum the source's entire history.
#   * Every exploration and alert in the section is in the apply workflow's -target= allowlist
#     (#5566: an untargeted resource is never applied, so the alert never exists).
#
# The section's explorations are DISCOVERED (every `resource "logtail_exploration"` after the
# section header), never a fixed list, and a floor refuses a discovery that found fewer than 3.
#
# WHAT THIS DOES NOT PROVE: that Better Stack accepts query_period 86400 or evaluates the template
# SQL as probed — terraform validate does not see the SQL, and the provider does not bound the
# period. That is the apply's and the reconciler's (heartbeat-live-reconcile.ts `logs_alert` arm).
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
assert_fixture_dir "$TF"; assert_fixture_dir "$WF"

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

for f in "$TF" "$WF"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done
command -v python3 >/dev/null || { printf '[FATAL] python3 not found\n' >&2; exit 2; }

# The structural checks run in ONE python pass that prints `OK <msg>` / `FAIL <msg>` lines; each
# line becomes one ok()/no() here. A python crash prints neither, and the floor below catches it.
CHECKS="$(python3 - "$TF" "$WF" <<'PY'
import json, re, sys
tf = open(sys.argv[1], encoding="utf-8").read()
wf = open(sys.argv[2], encoding="utf-8").read()
out = []
def check(cond, msg): out.append(("OK " if cond else "FAIL ") + msg)

HEADER = "# ── #8611 / ADR-243:"
if tf.count(HEADER) != 1:
    print("FAIL the #8611 section header is missing or duplicated — nothing below can be discovered")
    sys.exit(0)
sec = tf[tf.index(HEADER):]

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
    gb = re.findall(r"GROUP BY (.*)", sql)
    check(gb in ([], ["time"]), f"{n}: GROUP BY is `time` or absent (no free-text grouping) — got {gb}")
    if items and items[0].startswith("toDateTime("):
        check(re.search(r"^\s*WHERE dt BETWEEN \{\{start_time\}\} AND \{\{end_time\}\}\s*$", sql, re.M) is not None
              and "time BETWEEN" not in sql,
              f"{n}: a whole-window query filters on the dt column, never on its constant time alias")
    else:
        check(gb == ["time"], f"{n}: a {{{{time}}}}-bucketed query groups by time")
    if "cost_usd" in sql:
        check(re.search(r"JSONExtract\w*\(raw, 'cost_usd'", sql) is None
              and "JSONExtract" in sql and "raw, 'message', 'cost_usd'" in sql,
              f"{n}: reads cost_usd at the nested raw.message path, never top-level")
        check("raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%'" in sql,
              f"{n}: keeps the \"SOLEUR_CLAUDE_COST\":true key match (the _DAILY rows stay out)")
        check("JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'" in sql,
              f"{n}: scoped to cron sources (founder BYOK spend is not the operator key's)")

# The 524 predicate against a SYNTHESIZED row of the observed emitter shape (2026-09-23 probe:
# keys error/item_kind/level/msg/time under an object `message`, PRIORITY 6, unit inngest-server).
s524 = sqls.get("inngest_step_524", "")
fixture = {"PRIORITY": "6", "_SYSTEMD_UNIT": "inngest-server.service", "SYSLOG_IDENTIFIER": "doppler",
           "message": {"time": "2026-01-01T00:00:00Z", "level": "ERROR", "msg": "error handling queue item",
                       "item_kind": "edge", "error": "invalid status code: 524"}}
unit = re.search(r"JSONExtractString\(raw, '_SYSTEMD_UNIT'\) = '([^']*)'", s524)
needle = re.search(r"multiSearchAny\(JSONExtractString\(raw, 'message', 'error'\), \[([^\]]*)\]\)", s524)
needles = re.findall(r"'([^']*)'", needle.group(1)) if needle else []
matches = bool(unit and fixture["_SYSTEMD_UNIT"] == unit.group(1)
               and any(n and n in fixture["message"]["error"] for n in needles))
check(matches, f"524: the predicate matches the observed emitter shape (unit={unit.group(1) if unit else None}, needles={needles})")
check(len(re.findall(r"multiSearchAny\(", s524)) == 1 and len(re.findall(r"JSONExtractString\(raw, '_SYSTEMD_UNIT'\)", s524)) == 1,
      "524: exactly one unit scope and one needle array (no OR-appended second arm)")
check(re.search(r"PRIORITY", s524) is None, "524: no PRIORITY filter (the live 524 lines are PRIORITY 6)")
check(re.search(r"\bOR\b", s524) is None and " LIKE " not in s524, "524: field-isolated — no OR, no raw LIKE (issue bodies quote the literal)")

def alert_attr(n, key):
    m = re.search(r"^\s*" + key + r"\s*=\s*(\S+)\s*$", block("logtail_exploration_alert", n) or "", re.M)
    return m.group(1) if m else None
check(alert_attr("inngest_step_524", "operator") == '"higher_than"' and alert_attr("inngest_step_524", "value") == "0",
      "524: any matching row pages (higher_than 0)")
check(alert_attr("claude_cost_daily_burn", "operator") == '"higher_than"' and alert_attr("claude_cost_daily_burn", "value") == "15",
      "burn: pages above $15 per window")
check(alert_attr("claude_cost_capture_dark", "operator") == '"lower_than"' and alert_attr("claude_cost_capture_dark", "value") == "1",
      "capture-dark: pages when the window holds nothing (lower_than 1 over treat_as_zero)")
dark = sqls.get("claude_cost_capture_dark", "")
check("'Nullable(Float64)') IS NOT NULL" in dark and "'anthropic-credit-exhausted'" in dark,
      "capture-dark: counts non-null cost markers, and credit-probe RED rows suppress it")
check("runbooks/betterstack-log-query.md" in sec, "the incidents carry a clickable runbook URL")
print("\n".join(out))
PY
)"
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
fi

# 60 = 47 presence rows + 13 mutation rows. The MUT_SKIP floor is exactly today's presence count
# (3 discovered explorations): a discovery that finds fewer, or a checker that dies part-way,
# drops below it. Raise both in the same edit that adds a row.
_floor=60
[ -n "${MUT_SKIP:-}" ] && _floor=47
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-step-524-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
