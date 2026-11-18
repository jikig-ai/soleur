#!/usr/bin/env bash
#
# Drift guard for the "granted session, degraded sandboxed egress" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, logtail_exploration_alert.sandbox_network_degraded; #12585).
#
# WHAT THE ALERT IS FOR. server/permission-callback.ts logs every denied SandboxNetworkAccess request as one pino warn
# row (feature cc-permissions, op sandbox-network-denied, extra reason/granted/matchedEntry/subagent). The alert pages
# when a session whose workspace has web access ON is denied for want of a live forwarder (reason not-entitled or
# egress-not-running with granted=true): the granted-but-degraded case #12585 exists for (CTO D2).
#
# WHAT THIS FILE PROTECTS:
#   * CANONICAL EQUALITY: the flattened SQL heredoc equals a canon built from literals READ FROM THE EMITTER (the
#     SANDBOX_NETWORK_DENIED object's feature/op) and from the reason union in server/sandbox-network-access.ts, so a
#     reworded emitter or a renamed reason reds here instead of silently disarming the alert.
#   * The emitter passes `granted` as a BOOLEAN (the predicate reads it with JSONExtractRaw = 'true').
#   * FIXTURE EVALUATION: production-shaped rows (raw.message an OBJECT with the extra keys at top level) are run
#     through the SAME conjuncts: two positive controls and near-miss negatives.
#   * Paging semantics, unpaused, email, the pinned source local, both -target= lines in the MAIN plan, the runbook row
#     and this guard's own infra-validation step.
#   * A mutation battery: each row edits a copy of one input and requires this guard to go red.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TF="${SND_TF:-$ROOT/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${SND_WF:-$ROOT/.github/workflows/apply-web-platform-infra.yml}"
PC="${SND_PC:-$ROOT/apps/web-platform/server/permission-callback.ts}"
SNA="${SND_SNA:-$ROOT/apps/web-platform/server/sandbox-network-access.ts}"
RB="${SND_RB:-$ROOT/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md}"
IV="${SND_IV:-$ROOT/.github/workflows/infra-validation.yml}"

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }

set +e
python3 - "$TF" "$WF" "$PC" "$SNA" "$RB" "$IV" <<'PY'
import json, re, sys

tf, wf, pc, sna, rb, iv = (open(p, encoding="utf-8").read() for p in sys.argv[1:7])
fails, passes = [], 0

def check(cond, msg):
    global passes
    if cond:
        passes += 1
    else:
        fails.append(msg)

# ---- the emitter literals ------------------------------------------------------------------------------------------
m = re.search(r'const SANDBOX_NETWORK_DENIED = \{\s*feature: "([^"]+)",\s*op: "([^"]+)",\s*message: "([^"]+)",\s*\} as const;', pc)
check(m is not None, "emitter: SANDBOX_NETWORK_DENIED {feature, op, message} not found in permission-callback.ts")
feature, op = (m.group(1), m.group(2)) if m else ("<none>", "<none>")
check(re.search(r"^\s*const extra = \{ reason, granted, matchedEntry, subagent \};$", pc, re.M) is not None,
      "emitter: the deny reporter's extra is not { reason, granted, matchedEntry, subagent }")
check(re.search(r"^\s*granted: boolean,$", pc, re.M) is not None, "emitter: the reporter's `granted` parameter is not a boolean")
union = re.search(r"export type SandboxNetworkReason =((?:\s*\|\s*\"[a-z-]+\")+);", sna)
reasons = re.findall(r'"([a-z-]+)"', union.group(1)) if union else []
check("not-entitled" in reasons and "egress-not-running" in reasons, f"reason union lacks a degraded reason: {reasons}")

# ---- the SQL -------------------------------------------------------------------------------------------------------
check(tf.count("sandbox_network_degraded_sql = <<-SQL") == 1, "SQL heredoc opener is not present exactly once")
h = re.search(r"\n  sandbox_network_degraded_sql = <<-SQL\n(.*?)\n  SQL\n", tf, re.S)
sql = " ".join(h.group(1).split()) if h else ""
canon = " ".join(f"""
SELECT {{{{time}}}} AS time, count(*) AS value
FROM {{{{source}}}}
WHERE time BETWEEN {{{{start_time}}}} AND {{{{end_time}}}}
  AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform'
  AND JSONExtractString(raw, 'message', 'feature') = '{feature}'
  AND JSONExtractString(raw, 'message', 'op') = '{op}'
  AND JSONExtractRaw(raw, 'message', 'granted') = 'true'
  AND JSONExtractString(raw, 'message', 'reason') IN ('not-entitled', 'egress-not-running')
GROUP BY time
""".split())
check(sql == canon, f"SQL is not the canon built from the emitter.\n  got:   {sql}\n  canon: {canon}")
check("host_name" not in sql, "SQL carries a host_name conjunct (the signal belongs to every web host)")

# ---- fixture evaluation of the as-written conjuncts ------------------------------------------------------------------
conj = re.findall(r"AND (JSONExtract(String|Raw))\(raw, ((?:'[^']+'(?:, )?)+)\) (=|IN) (\([^)]*\)|'[^']*')", sql)
check(len(conj) == 5, f"expected 5 JSON conjuncts, parsed {len(conj)}")

def extract(row, kind, path):
    node = row
    for k in path:
        if not isinstance(node, dict) or k not in node:
            return ""
        node = node[k]
    if kind == "Raw":
        return json.dumps(node, separators=(",", ":"))
    # Live-probed 2026-11-18: ClickHouse's JSONExtractString returns `true` / `false` for a JSON boolean.
    if isinstance(node, bool):
        return "true" if node else "false"
    return node if isinstance(node, str) else ""

def matches(row):
    for _fn, kind, path, oper, rhs in conj:
        keys = re.findall(r"'([^']+)'", path)
        vals = re.findall(r"'([^']*)'", rhs)
        v = extract(row, kind, keys)
        if (oper == "=" and v != vals[0]) or (oper == "IN" and v not in vals):
            return False
    return True

def row(**msg):
    base = {"feature": feature, "op": op, "level": 40, "msg": "sandboxed network request denied",
            "reason": "not-entitled", "granted": True, "matchedEntry": None, "subagent": False}
    base.update(msg)
    return {"CONTAINER_NAME": "soleur-web-platform", "message": base}

check(matches(row()), "positive control (granted, not-entitled) does NOT match: the alert would never fire")
check(matches(row(reason="egress-not-running")), "positive control (granted, egress-not-running) does NOT match")
check(not matches(row(granted=False)), "an ungranted not-entitled row matches (the default posture would page)")
check(not matches(row(reason="gateway-unverified")), "a gateway-unverified row matches (every entitled request would page)")
check(not matches(row(reason="no-proxy-match")), "a host-reason row matches")
check(not matches(row(granted="true")), "a string 'true' matches: the predicate no longer reads a JSON boolean")
bad = row(); bad["CONTAINER_NAME"] = "soleur-inngest"
check(not matches(bad), "a row from another container matches")

# ---- resource blocks -----------------------------------------------------------------------------------------------
def block(kind, name):
    b = re.search(r'\nresource "%s" "%s" \{\n(.*?)\n\}\n' % (kind, name), tf, re.S)
    return b.group(1) if b else ""

ex, al = block("logtail_exploration", "sandbox_network_degraded"), block("logtail_exploration_alert", "sandbox_network_degraded")
check(ex != "" and al != "", "exploration or alert block missing")
for line in ['    sql_query = replace(trimspace(local.sandbox_network_degraded_sql), "/\\\\s+/", " ")',
             "    values        = [local.vector_prd_source_id]"]:
    check(ex.count(line + "\n") + ex.endswith(line) == 1, f"exploration line not pinned exactly once: {line}")
for line in ["  exploration_id = logtail_exploration.sandbox_network_degraded.id", '  alert_type          = "threshold"',
             '  operator            = "higher_than"', "  value               = 0", "  check_period        = 60",
             "  query_period        = 300", "  recovery_period     = 600", '  on_missing_data     = "treat_as_zero"',
             "  paused = false", "  email          = true",
             "    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null"]:
    check(len(re.findall("^" + re.escape(line) + "$", al, re.M)) == 1, f"alert line not pinned exactly once: {line}")

# ---- workflow, runbook, validation step ----------------------------------------------------------------------------
for kind in ("logtail_exploration", "logtail_exploration_alert"):
    check(len(re.findall(r"^\s+-target=%s\.sandbox_network_degraded \\$" % kind, wf, re.M)) == 1,
          f"apply-web-platform-infra.yml MAIN plan lacks -target={kind}.sandbox_network_degraded")
check("`logtail_exploration_alert.sandbox_network_degraded`" in rb, "runbook has no standing-alarm row for the alert")
check(re.search(r"^\s+run: bash apps/web-platform/test/infra/sandbox-network-denied-alert\.test\.sh$", iv, re.M) is not None,
      "infra-validation.yml has no step running this guard")

print(f"sandbox-network-denied-alert: {passes} passed, {len(fails)} failed")
for f in fails:
    print(f"  FAIL: {f}")
sys.exit(1 if fails else 0)
PY
rc=$?
set -e
[[ "${SND_INNER:-}" == "1" ]] && exit "$rc"
[[ "$rc" -eq 0 ]] || exit 1

# ---- mutation battery: each edit of a copy must red the guard --------------------------------------------------------
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
reds=0
mutate() { # label var file python-replace-old python-replace-new
  local label="$1" var="$2" src="$3" old="$4" new="$5" copy="$SCRATCH/$(basename "$3")"
  python3 - "$src" "$copy" "$old" "$new" <<'PY' || { printf 'FATAL: mutation anchor drifted: %s\n' "$label" >&2; exit 2; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old, new = sys.argv[3].encode().decode("unicode_escape"), sys.argv[4].encode().decode("unicode_escape")
assert s.count(old) >= 1, "anchor"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  if env SND_INNER=1 "$var=$copy" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    printf 'MUTANT SURVIVED: %s\n' "$label" >&2
    exit 1
  fi
  reds=$((reds + 1))
}
mutate "reason list drops egress-not-running" SND_TF "$TF" "IN ('not-entitled', 'egress-not-running')" "IN ('not-entitled')"
mutate "granted conjunct removed" SND_TF "$TF" "      AND JSONExtractRaw(raw, 'message', 'granted') = 'true'\n" ""
mutate "granted read as a string" SND_TF "$TF" "JSONExtractRaw(raw, 'message', 'granted')" "JSONExtractString(raw, 'message', 'granted')"
mutate "alert paused" SND_TF "$TF" "  paused = false\n\n  email          = true\n  push           = false\n  call           = false\n  sms            = false\n  critical_alert = false\n\n  incident_cause = \"A workspace with web access" "  paused = true\n\n  email          = true\n  push           = false\n  call           = false\n  sms            = false\n  critical_alert = false\n\n  incident_cause = \"A workspace with web access"
mutate "emitter op renamed" SND_PC "$PC" 'op: "sandbox-network-denied",' 'op: "sandbox-net-denied",'
mutate "emitter granted becomes a string" SND_PC "$PC" "  granted: boolean," "  granted: string,"
mutate "alert -target dropped" SND_WF "$WF" "              -target=logtail_exploration_alert.sandbox_network_degraded \\\\\n" ""
mutate "degraded reason renamed in the union" SND_SNA "$SNA" '| "egress-not-running"' '| "forwarder-dead"'
mutate "runbook row removed" SND_RB "$RB" '`logtail_exploration_alert.sandbox_network_degraded`' '`removed`'
printf 'sandbox-network-denied-alert mutation battery: %d/9 mutants killed\n' "$reds"
[[ "$reds" -eq 9 ]] || { printf 'FATAL: battery ran %d of 9 rows\n' "$reds" >&2; exit 1; }
