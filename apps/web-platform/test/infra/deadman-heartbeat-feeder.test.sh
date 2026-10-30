#!/usr/bin/env bash
# Harness for scripts/deadman-heartbeat-feeder.sh (#11631; Guards 1, 2 and 4 of the plan).
#
# WHAT THE FEEDER IS. It beats betteruptime_heartbeat.{luks_monitor_host_timer,claude_cost_capture} ONLY
# while the target's own predicate finds a qualifying row inside the retired alert's OLD window (97200 s /
# 86400 s) in the Better Stack Logs HOT arm (remote()) UNION the ARCHIVE arm (s3Cluster). The failure this
# suite exists to stop is a SPURIOUS BEAT: a feeder that keeps a dead-man alive without a qualifying row hides
# exactly what the control exists to find. Exit 0 must mean exactly {beat, qualifying_row_heartbeat_paused};
# nothing in the script may ever reach a heartbeat /fail URL.
#
# THE FAKE TREE. The feeder is copied to $root/scripts/ and resolves its repo from its own location, so the
# stub scripts/betterstack-query.sh at $root/scripts is what it runs. It runs under `env -i` with a PRIVATE PATH
# ($root/bin holds a stub curl and symlinks to the tools it needs), and a canary proves curl resolves inside it.
# The stub curl models EXACTLY two request shapes (the uptime-API GET and the beat) and refuses anything else with
# status 64 and a line in its call log; every case asserts there is no refusal line.
#
# THE STUB HELPER IS NOT CLICKHOUSE. scripts/betterstack-query.sh is replaced by a small python evaluator for
# the SQL SUBSET the two predicates use (JSONExtractString / JSONExtract path lookups, `= LIKE IN IS NOT NULL`,
# AND / OR / parentheses, the `dt` window against a frozen clock, `_row_type`, the hot/archive UNION). It
# evaluates the SQL the feeder ACTUALLY SENT, so a changed predicate or window changes the verdict. Anything outside
# the subset is refused (status 65), never guessed. Its limits: no type coercion, no locale, no `raw` quirks.
# Phase 0.1 of the plan (the live positive control, knowledge-base/project/specs/fix-observable-deadman-11631/
# phase0-measurements.md) is what proves the predicates against the real service; the answer shapes used below
# (n as a JSON number or a quoted string, the epoch row for an empty window) were captured there.
#
# EMITTER PINS (Guard 2). The predicate literals are read back from their writers:
#   * `_SYSTEMD_UNIT` is stamped by journald from the unit that logged; luks-monitor.service sets
#     SyslogIdentifier=luks-monitor, which equals luks-monitor.sh's LOG_TAG and the vector.toml
#     host_scripts_journald include_matches tag. `host_name` is written by vector.toml's journald transform
#     (`.host_name = "@@HOST_NAME@@"`), rendered per host from server.tf (web-1 = soleur-web-platform).
#   * the luks needle is luks-monitor.sh's own OK log line; the cost literals are server/claude-cost-marker.ts
#     (`SOLEUR_CLAUDE_COST: true`, pino base component 'claude-cost'), the substrate's `cron:${cronName}` source,
#     and the credit probe's CRON_NAME and op union.
#
# MUTATIONS ARE COMMITTED, NOT HAND-RUN. Each row is applied to a scratch copy by an exact-string replace that
# must match exactly once (it LANDED), and must go RED FOR THE PREDICTED REASON (status and verdict), never a
# crash. Harness rows prove the fixtures can fail (a stub evaluator that qualifies every row flips the negative
# fixtures) and that non-canonical must-PASS inputs stay green. A known-positive and known-negative run prove the
# red detector first. Fixtures are synthesized (cq-test-fixtures-synthesized-only); the live captures contributed
# only the one-line aggregate answer SHAPE, never a row.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
FEEDER_NAME="deadman-heartbeat-feeder.sh"
FEEDER_SRC="$REPO/scripts/$FEEDER_NAME"
WORKFLOW="$REPO/.github/workflows/scheduled-deadman-heartbeat-feeder.yml"
TABLE_TS="$REPO/apps/web-platform/server/watchdog-dispatch-table.ts"
UPTIME_TF="$REPO/apps/web-platform/infra/uptime-alerts.tf"
APPLY_WF="$REPO/.github/workflows/apply-web-platform-infra.yml"
MONITORS_TF="$REPO/apps/web-platform/infra/sentry/cron-monitors.tf"
ALERTS_TF="$REPO/apps/web-platform/infra/sentry/cron-monitor-alerts.tf"
MANIFEST_TS="$REPO/plugins/soleur/lib/heartbeat-manifest.ts"
EMIT_LUKS="$REPO/apps/web-platform/infra/luks-monitor.sh"
EMIT_LUKS_UNIT="$REPO/apps/web-platform/infra/luks-monitor.service"
EMIT_VECTOR="$REPO/apps/web-platform/infra/vector.toml"
EMIT_SERVER_TF="$REPO/apps/web-platform/infra/server.tf"
EMIT_MARKER="$REPO/apps/web-platform/server/claude-cost-marker.ts"
EMIT_SUBSTRATE="$REPO/apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts"
EMIT_PROBE="$REPO/apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts"

fails=0
passes=0
cases=0
beat_asserts=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$FEEDER_SRC" ]] || { echo "FATAL: feeder not found at $FEEDER_SRC" >&2; exit 1; }
PY="$(type -P python3)" || { echo "FATAL: python3 not found" >&2; exit 1; }
BASH_BIN="$(type -P bash)"

# Canonical guard, copied byte-for-byte from plugins/soleur/test/test-helpers.sh.
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
WORK="$(mktemp -d "${TMPDIR}/deadman-heartbeat-feeder.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/fx" "$WORK/mut"

# ── fabricated identities and the pinned clock ────────────────────────────────────────────────
NOW_EPOCH=1793361600   # 2026-10-30T12:00:00Z; the stub evaluator's `now()`
TOKEN="SYNTHtokenAbCdEf0123456789xyz"
HB_ID_SENTINEL="SYNTHping9Xk2Zq"
HB_URL="https://uptime.betterstack.com/api/v1/heartbeat/$HB_ID_SENTINEL"
FAKE_CRED="dp.ct.NOT_A_REAL_TOKEN_11631_synthetic"
Q_PASS="pw-SYNTH-9f2c1d7a"
Q_USER="user-SYNTH-77aa"
BAD_TOKEN_SENT="SYNTHbadTOKENqq9"
BAD_URL_SENT="SYNTHbadURLid9"
TLS_NAMES="SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS"

# The independent expected target set, frozen HERE (set identity, never a `>= N` floor). An edit that changes
# the script and this table in one diff proves consistency only; integrity comes from the emitter pins below, the
# Phase 0.1 live capture and the Phase 0.5 verbatim-move check.
T_LUKS="luks-monitor-host-timer"; T_COST="claude-cost-capture"
EXPECT_TARGETS="$T_LUKS $T_COST"
declare -A E_WINDOW=([$T_LUKS]=97200 [$T_COST]=86400)
declare -A E_NAME=([$T_LUKS]="soleur-luks-monitor-host-timer-prd" [$T_COST]="soleur-claude-cost-capture-prd")
declare -A E_PRED=(
  [$T_LUKS]="JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'"
  [$T_COST]="((raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%' AND JSONExtractString(raw, 'message', 'component') = 'claude-cost' AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%' AND JSONExtract(raw, 'message', 'cost_usd', 'Nullable(Float64)') IS NOT NULL) OR (JSONExtractString(raw, 'message', 'feature') = 'cron-anthropic-credit-probe' AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')))"
)
expect_sql() { # <target> <predicate> -> the SQL the feeder must send (frozen shape)
  local w="${E_WINDOW[$1]}" win
  win="dt > now() - INTERVAL $w SECOND AND dt <= now() + INTERVAL 300 SECOND"
  printf 'SELECT count() AS n, toString(max(dt)) AS newest FROM (SELECT dt, raw FROM remote($BS_TABLE) WHERE %s UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND %s) WHERE %s FORMAT JSONEachRow' "$win" "$win" "$2"
}

# ── fixture builders ──────────────────────────────────────────────────────────────────────────
H=3600
OK_MSG='OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/synth escrow=ok header=readable boot_id=synthetic)'
FAIL_MSG='FAIL (not_mounted): device_type=none mount_source=none mapper_present=0 luks_open_result=skipped'
luks_raw() { # [identifier] [unit|__none__] [message] [host_name]
  jq -cn --arg id "${1:-luks-monitor}" --arg unit "${2-luks-monitor.service}" --arg msg "${3:-$OK_MSG}" --arg host "${4:-soleur-web-platform}" \
    '{SYSLOG_IDENTIFIER: $id, host_name: $host, message: $msg} + (if $unit == "__none__" then {} else {_SYSTEMD_UNIT: $unit} end)'
}
cost_raw() { # <source> [cost-json|"absent"] [component] [flag-key]
  jq -cn --arg src "$1" --arg comp "${3:-claude-cost}" --arg flag "${4:-SOLEUR_CLAUDE_COST}" --argjson cost "${2:-0.25}" \
    '{message: ({($flag): true, component: $comp, source: $src} + (if $cost == "absent" then {} else {cost_usd: $cost} end))}'
}
probe_raw() { # <op>
  jq -cn --arg op "$1" '{message: {feature: "cron-anthropic-credit-probe", op: $op}}'
}
row() { # <arm hot|s3> <age_s> <raw-json> [row_type]
  jq -cn --arg arm "$1" --argjson age "$2" --argjson raw "$3" --argjson rt "${4:-1}" '{arm: $arm, age: $age, row_type: $rt, raw: $raw}'
}
fx() { cat > "$WORK/fx/$1.jsonl"; printf '%s' "$WORK/fx/$1.jsonl"; }
hb_json() { # <name> <paused-literal|__absent__> <url> -> one-heartbeat API body
  jq -cn --arg n "$1" --arg p "$2" --arg u "$3" '
    {data: [{id: "504655", type: "heartbeat",
      attributes: ({name: $n, url: $u, period: 3600, grace: 7200, status: "paused"}
        + (if $p == "__absent__" then {} else {paused: ($p | fromjson)} end))}], pagination: {}}'
}

# ── the stub evaluator (python; see the header for its limits) ───────────────────────────────────
write_evaluator() { # <dest>
  cat > "$1" <<'PYEVAL'
import json, re, sys, datetime

sql, cfg_path, rows_path = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(cfg_path))
NOW = float(cfg["now"])


class Unsupported(Exception):
    pass


TOK = re.compile(
    r"""\s*(?:(?P<str>'(?:[^'\\]|\\.|'')*')|(?P<num>\d+(?:\.\d+)?)|(?P<id>\$?[A-Za-z_][A-Za-z0-9_]*)|(?P<op><=|>=|!=|=|<|>|\(|\)|,|\+|-))"""
)


def tokenize(s):
    s = s.strip()
    pos, out = 0, []
    while pos < len(s):
        m = TOK.match(s, pos)
        if not m or m.end() == pos:
            raise Unsupported("token at %d: %r" % (pos, s[pos:pos + 20]))
        pos = m.end()
        if m.group("str") is not None:
            body = m.group("str")[1:-1].replace("''", "'")
            body = re.sub(r"\\(.)", r"\1", body)
            out.append(("str", body))
        elif m.group("num") is not None:
            out.append(("num", float(m.group("num"))))
        elif m.group("id") is not None:
            out.append(("id", m.group("id")))
        else:
            out.append(("op", m.group("op")))
    return out


class Parser:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else ("eof", None)

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def kw(self, word):
        k, v = self.peek()
        return k == "id" and v.upper() == word

    def expect_kw(self, word):
        if not self.kw(word):
            raise Unsupported("expected %s at %r" % (word, self.peek()))
        self.take()

    def expect_op(self, op):
        if self.peek() != ("op", op):
            raise Unsupported("expected %s at %r" % (op, self.peek()))
        self.take()

    # value expressions ------------------------------------------------------------------
    def value(self):
        k, v = self.take()
        if k == "str":
            e = lambda row, c=v: c
        elif k == "num":
            e = lambda row, c=v: c
        elif k == "id":
            if self.peek() == ("op", "("):
                self.take()
                args = []
                if self.peek() != ("op", ")"):
                    while True:
                        args.append(self.value())
                        if self.peek() == ("op", ","):
                            self.take()
                            continue
                        break
                self.expect_op(")")
                e = self.call(v.lower(), args)
            elif v == "dt":
                e = lambda row: row["dt"]
            elif v == "_row_type":
                e = lambda row: row["row_type"]
            elif v == "raw":
                e = lambda row: row["rawtext"]
            else:
                raise Unsupported("identifier %r" % v)
        else:
            raise Unsupported("value at %r" % ((k, v),))
        while self.peek() in (("op", "+"), ("op", "-")):
            sign = 1 if self.take()[1] == "+" else -1
            self.expect_kw("INTERVAL")
            nk, nv = self.take()
            if nk != "num":
                raise Unsupported("interval count")
            self.expect_kw("SECOND")
            e = (lambda row, a=e, d=sign * nv: a(row) + d)
        return e

    def call(self, name, args):
        if name == "now":
            return lambda row: NOW
        if name in ("jsonextractstring", "jsonextract"):
            consts = [a(None) for a in args[1:]]
            if name == "jsonextractstring":
                path = consts

                def f(row):
                    o = json.loads(row["rawtext"])
                    for k in path:
                        if isinstance(o, dict) and k in o:
                            o = o[k]
                        else:
                            return ""
                    return o if isinstance(o, str) else ""

                return f
            if consts[-1] != "Nullable(Float64)":
                raise Unsupported("JSONExtract type %r" % consts[-1])
            path = consts[:-1]

            def g(row):
                o = json.loads(row["rawtext"])
                for k in path:
                    if isinstance(o, dict) and k in o:
                        o = o[k]
                    else:
                        return None
                return float(o) if isinstance(o, (int, float)) and not isinstance(o, bool) else None

            return g
        raise Unsupported("function %r" % name)

    # boolean expressions ----------------------------------------------------------------
    def atom(self):
        if self.peek() == ("op", "("):
            self.take()
            e = self.or_()
            self.expect_op(")")
            return e
        left = self.value()
        k, v = self.peek()
        if k == "op" and v in ("=", "!=", "<", ">", "<=", ">="):
            self.take()
            right = self.value()
            ops = {
                "=": lambda a, b: a == b, "!=": lambda a, b: a != b, "<": lambda a, b: a < b,
                ">": lambda a, b: a > b, "<=": lambda a, b: a <= b, ">=": lambda a, b: a >= b,
            }
            f = ops[v]
            return lambda row: f(left(row), right(row))
        if self.kw("LIKE"):
            self.take()
            pk, pv = self.take()
            if pk != "str":
                raise Unsupported("LIKE pattern")
            rx = re.compile("^" + "".join(".*" if c == "%" else "." if c == "_" else re.escape(c) for c in pv) + "$", re.S)
            return lambda row: bool(rx.match(left(row) or "")) if LIKE_MODE == "real" else True
        if self.kw("IN"):
            self.take()
            self.expect_op("(")
            vals = []
            while True:
                pk, pv = self.take()
                if pk != "str":
                    raise Unsupported("IN member")
                vals.append(pv)
                if self.peek() == ("op", ","):
                    self.take()
                    continue
                break
            self.expect_op(")")
            return lambda row: left(row) in vals
        if self.kw("IS"):
            self.take()
            self.expect_kw("NOT")
            self.expect_kw("NULL")
            return lambda row: left(row) is not None
        raise Unsupported("atom at %r" % (self.peek(),))

    def and_(self):
        parts = [self.atom()]
        while self.kw("AND"):
            self.take()
            parts.append(self.atom())
        return lambda row: all(p(row) for p in parts)

    def or_(self):
        parts = [self.and_()]
        while self.kw("OR"):
            self.take()
            parts.append(self.and_())
        return lambda row: any(p(row) for p in parts)


LIKE_MODE = "real"
ROW_FILTER_MODE = "real"
# (harness rows rewrite the two constants above to build the "every row qualifies" evaluators)


def keep(expr, row):
    return bool(expr(row))


def main():
    p = Parser(tokenize(sql))
    for w in ("SELECT", "count"):
        p.take()
    p.expect_op("("); p.expect_op(")")
    p.expect_kw("AS"); p.take(); p.expect_op(",")
    for w in ("toString",):
        p.take()
    p.expect_op("("); p.take(); p.expect_op("("); p.take(); p.expect_op(")"); p.expect_op(")")
    p.expect_kw("AS"); p.take(); p.expect_kw("FROM"); p.expect_op("(")
    rows = []
    for raw_row in open(rows_path):
        raw_row = raw_row.strip()
        if raw_row:
            rows.append(json.loads(raw_row))
    union = []
    first = True
    while True:
        p.expect_kw("SELECT"); p.take(); p.expect_op(","); p.take(); p.expect_kw("FROM")
        fn = p.take()[1]
        p.expect_op("(")
        if fn == "remote":
            tbl = p.take()
            if tbl != ("id", "$BS_TABLE"):
                raise Unsupported("hot table %r" % (tbl,))
            arm = "hot"
        elif fn == "s3Cluster":
            if p.take() != ("id", "primary"):
                raise Unsupported("cluster")
            p.expect_op(",")
            tbl = p.take()
            if tbl != ("id", "$BS_TABLE_S3"):
                raise Unsupported("archive table %r" % (tbl,))
            arm = "s3"
        else:
            raise Unsupported("table function %r" % fn)
        p.expect_op(")")
        p.expect_kw("WHERE")
        expr = p.or_()
        for r in rows:
            if r["arm"] != arm:
                continue
            row = {"dt": NOW - float(r["age"]), "row_type": r["row_type"],
                   "rawtext": json.dumps(r["raw"], separators=(",", ":"), ensure_ascii=False)}
            if keep(expr, row):
                union.append(row)
        if p.kw("UNION"):
            p.take(); p.expect_kw("ALL")
            continue
        break
    p.expect_op(")")
    p.expect_kw("WHERE")
    outer = p.or_()
    p.expect_kw("FORMAT"); p.expect_kw("JSONEACHROW")
    if p.peek()[0] != "eof":
        raise Unsupported("trailing tokens")
    hits = [r for r in union if keep(outer, r)]
    n = len(hits)
    if hits:
        ts = max(r["dt"] for r in hits)
        newest = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")
    else:
        newest = "1970-01-01 00:00:00.000000"
    print(json.dumps({"n": str(n) if cfg.get("n_string") else n, "newest": newest}, separators=(",", ":")))


try:
    main()
except Unsupported as e:
    sys.stderr.write("STUB EVALUATOR: unsupported SQL: %s\n" % e)
    sys.exit(65)
PYEVAL
}
write_evaluator "$WORK/evaluator.py"
# Harness-row evaluators (the fixtures must be able to FAIL): every row qualifies / LIKE is always true.
"$PY" -I - "$WORK/evaluator.py" "$WORK/eval-allrows.py" "$WORK/eval-likeall.py" <<'PYM'
import sys
s = open(sys.argv[1]).read()
a = "def keep(expr, row):\n    return bool(expr(row))"
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, "def keep(expr, row):\n    return True"))
b = 'LIKE_MODE = "real"'
assert s.count(b) == 1
open(sys.argv[3], "w").write(s.replace(b, 'LIKE_MODE = "all"'))
PYM

# ── the runner ────────────────────────────────────────────────────────────────────────────────
# Per-case seams (reset_case clears them):
#   C_TARGET  feeder argv[1]                        C_ARGS    argv override (string, word-split) when non-empty
#   C_ROWS    fixture rows file the evaluator reads C_STUB    ok | okstr | fail | failbody | garbage | zero | two | ...
#   C_API     API body file                          C_APIMODE ok | fail
#   C_BEATMODE 200|429|500|302|403body|curlfail|timeout  C_TOKEN __unset__ | value  C_UNSET a BETTERSTACK_QUERY_* to blank
#   C_XTRACE  1 -> bash -x                           C_SRC     feeder source (default shipped)   C_EVAL evaluator file
#   C_BEATS / C_APIS / C_Q expected beat calls, API calls, helper queries
reset_case() {
  C_TARGET="$T_LUKS"; C_ARGS=""; C_ROWS="/dev/null"; C_STUB="ok"; C_API=""; C_APIMODE="ok"; C_BEATMODE="200"
  C_TOKEN="$TOKEN"; C_UNSET=""; C_XTRACE=0; C_SRC="$FEEDER_SRC"; C_EVAL="$WORK/evaluator.py"
  C_BEATS=0; C_APIS=0; C_Q=1; C_TLSENV=0; C_GHA=0; C_NAME_OVERRIDE=""
}
reset_case

OUT="$WORK/out"
CALLS="$WORK/root/calls.log"
SQLLOG="$WORK/root/sql.log"
write_stubs() { # <root>
  local root="$1"
  assert_fixture_dir "$root"
  mkdir -p "$root/bin" "$root/scripts"
  local t p
  for t in jq date grep sed tr cut head tail sort wc mktemp rm cat dirname bash env; do
    p="$(type -P "$t")" || { echo "FATAL: $t not found" >&2; exit 1; }
    ln -s "$p" "$root/bin/$t"
  done
  cat > "$root/bin/curl" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
LOG="\$R/calls.log"
argv="\$*"
stdin="\$(cat)"
tok="\$(cat "\$R/token.txt")"
for n in $TLS_NAMES; do if [ -n "\${!n:-}" ]; then echo "refused env \$n" >> "\$LOG"; exit 64; fi; done
A_ARGV='--disable --noproxy * -fsS --max-time 20 --connect-timeout 10 --config - https://uptime.betterstack.com/api/v2/heartbeats?per_page=250'
B_ARGV='--disable --noproxy * -fsS --max-time 15 --connect-timeout 10 -o /dev/null -w %{http_code} --config -'
if [[ "\$argv" == "\$A_ARGV" ]]; then
  if [[ "\$stdin" != "header = \"Authorization: Bearer \$tok\"" ]]; then echo "refused api-stdin" >> "\$LOG"; exit 64; fi
  echo api >> "\$LOG"
  [[ "\$(cat "\$R/api.mode")" == fail ]] && exit 7
  cat "\$R/api.body"
  exit 0
elif [[ "\$argv" == "\$B_ARGV" ]]; then
  exp="\$(cat "\$R/expect_url")"
  echo beat >> "\$LOG"
  if [[ "\$stdin" != "url = \"\$exp\"" ]]; then echo "refused beat-stdin" >> "\$LOG"; exit 64; fi
  case "\$(cat "\$R/beat.mode")" in
    200) printf 200; exit 0 ;;
    429) echo "Retry-After: 30" >&2; printf 429; exit 22 ;;
    500) printf 500; exit 22 ;;
    302) printf 302; exit 0 ;;
    403body) echo "{\"error\":\"denied token=$FAKE_CRED url=\$exp\"}" >&2; printf 403; exit 22 ;;
    timeout) exit 28 ;;
    *)   exit 7 ;;
  esac
fi
echo "refused argv" >> "\$LOG"
exit 64
STUB
  chmod +x "$root/bin/curl"
}

run_feeder() { # -> echoes the status; combined output in $OUT
  local root="$WORK/root" feeder
  feeder="$root/scripts/$FEEDER_NAME"
  case "$root" in "$WORK"/root) rm -rf -- "$root" ;; *) echo 199; return ;; esac
  write_stubs "$root"
  cp "$C_SRC" "$feeder"
  : > "$CALLS"; : > "$SQLLOG"
  printf '%s' "$TOKEN" > "$root/token.txt"
  printf '%s' "$HB_URL" > "$root/expect_url"
  printf '%s' "$C_APIMODE" > "$root/api.mode"
  printf '%s' "$C_BEATMODE" > "$root/beat.mode"
  if [[ -n "$C_API" ]]; then cp "$C_API" "$root/api.body"; else hb_json "${C_NAME_OVERRIDE:-${E_NAME[$C_TARGET]:-x}}" false "$HB_URL" > "$root/api.body"; fi
  printf '{"now": %s, "n_string": %s}' "$NOW_EPOCH" "$([[ "$C_STUB" == okstr ]] && echo true || echo false)" > "$root/stub.cfg"
  cp "$C_ROWS" "$root/rows.jsonl"
  cp "$C_EVAL" "$root/evaluator.py"

  if [[ "$C_STUB" != "none" ]]; then
    cat > "$root/scripts/betterstack-query.sh" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
printf '%s\n' "\$*" >> "\$R/sql.log"
# The helper's mode-1 dispatch: ONE argument that starts with SELECT. A flag (--no-archive) or an extra
# argument is refused, exactly as the real helper would not treat it as raw SQL.
[[ \$# -eq 1 ]] || { echo "STUB: unexpected argc \$#" >&2; exit 64; }
[[ "\$1" =~ ^[[:space:]]*(SELECT|WITH|SHOW)[[:space:]] ]] || { echo "STUB: not raw SQL" >&2; exit 64; }
# The feeder must scrub these before the helper (the helper exports its own).
[[ -z "\${BS_TABLE+x}" && -z "\${BS_TABLE_S3+x}" ]] || { echo "STUB: BS_TABLE leaked into the helper env" >&2; exit 64; }
case "\$1" in *\$'\n'*) echo "STUB: SQL contains a newline" >&2; exit 64 ;; esac
evaluate() { $PY -I "\$R/evaluator.py" "\$1" "\$R/stub.cfg" "\$R/rows.jsonl"; }
case "$C_STUB" in
  ok|okstr) evaluate "\$1"; exit \$? ;;
  fail)
    echo "betterstack-query: auth failed for user=$Q_USER password=$FAKE_CRED" >&2
    echo "curl: (22) https://stub/?token=$FAKE_CRED"
    exit 7 ;;
  failbody)
    echo '{"exception":"Code: 62. DB::Exception: password='"$FAKE_CRED"'"}'
    exit 22 ;;
  garbage) echo "<html>502 Bad Gateway</html>"; exit 0 ;;
  zero) exit 0 ;;
  two) evaluate "\$1"; evaluate "\$1"; exit 0 ;;
  nonnumeric) echo '{"n":"abc","newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  negn) echo '{"n":"-1","newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  floatn) echo '{"n":1.5,"newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  bign) echo '{"n":"99999999999999999999","newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  exception) echo '{"exception":"Code: 60. DB::Exception: Table does not exist"}'; exit 0 ;;
  nolinen) echo '{"newest":"2026-10-30 00:04:56.747448"}'; exit 0 ;;
  nonobj) echo '[1]'; exit 0 ;;
  nulln) echo '{"n":null,"newest":"x"}'; exit 0 ;;
  hostile) echo '{"n":3,"newest":"2026-10-30 00:04:56 ::set-output name=x::y"}'; exit 0 ;;
  hugenewest) echo '{"n":3,"newest":"'"\$(printf 'A%.0s' \$(seq 1 300))"'"}'; exit 0 ;;
  numnewest) echo '{"n":3,"newest":12345}'; exit 0 ;;
esac
STUB
    chmod +x "$root/scripts/betterstack-query.sh"
  fi

  local -a envv=(PATH="$root/bin" HOME="$HOME" TMPDIR="$TMPDIR")
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ "$C_UNSET" == "$v" ]]; then
      envv+=("$v=")
    else
      case "$v" in
        BETTERSTACK_QUERY_PASSWORD) envv+=("$v=$Q_PASS") ;;
        BETTERSTACK_QUERY_USERNAME) envv+=("$v=$Q_USER") ;;
        *) envv+=("$v=stub.example") ;;
      esac
    fi
  done
  [[ "$C_TOKEN" == "__unset__" ]] || envv+=("BETTERSTACK_API_TOKEN_READONLY=$C_TOKEN")
  # A stale export of the sibling's seam names must change nothing here (this script has no seams at all).
  envv+=("INNGEST_FEEDER_NOW=2000-01-01T00:00:00Z" "BS_TABLE=stale_table_from_caller" "BS_TABLE_S3=stale_s3_from_caller")
  if [[ "$C_TLSENV" == 1 ]]; then
    local _tn
    for _tn in $TLS_NAMES; do envv+=("$_tn=/dev/null"); done
  fi
  [[ "$C_GHA" != 1 ]] || envv+=("GITHUB_ACTIONS=true")
  local -a sh=("$BASH_BIN")
  [[ "$C_XTRACE" == "1" ]] && sh=("$BASH_BIN" -x)
  if [[ -n "$C_ARGS" ]]; then
    # shellcheck disable=SC2086
    env -i "${envv[@]}" "${sh[@]}" "$feeder" $C_ARGS >"$OUT" 2>&1
  else
    env -i "${envv[@]}" "${sh[@]}" "$feeder" "$C_TARGET" >"$OUT" 2>&1
  fi
  echo $?
}

markers_of() { grep -oE 'verdict=[a-z_]+' "$OUT" | cut -d= -f2 | paste -sd, - || true; }
count_calls() { # <pattern>
  { grep -cE "$1" "$CALLS" 2>/dev/null || true; } | head -1
}
count_sql() { { grep -c . "$SQLLOG" 2>/dev/null || true; } | head -1; }

# The generic invariant: exit 0 if and only if the verdict is beat or qualifying_row_heartbeat_paused.
assert_exit_zero_iff_fed() { # <rc> <verdict-token> <label>
  local good=0
  [[ "$2" == beat || "$2" == qualifying_row_heartbeat_paused ]] && good=1
  if [[ "$1" == "0" && "$good" != 1 ]] || [[ "$1" != "0" && "$good" == 1 ]]; then
    fail "INVARIANT: rc=$1 with verdict=$2 ($3) — exit 0 must mean exactly {beat, qualifying_row_heartbeat_paused}"
    return 1
  fi
  return 0
}

expect() { # <name> <rc> <verdict> [required-token]
  cases=$((cases + 1))
  local name="$1" want="$2" verdict="$3" extra="${4:-}" got ok=1 all
  got="$(run_feeder)"
  [[ -s "$OUT" ]] || { fail "$name — the feeder produced NO output; did it run?"; return; }
  all="$(cat "$OUT")"
  assert_exit_zero_iff_fed "$got" "$verdict" "$name" || return
  [[ "$got" == "$want" ]] || ok=0
  grep -qE "verdict=${verdict}( |\$)" "$OUT" || ok=0
  if [[ -n "$extra" ]] && ! grep -qF -- "$extra" "$OUT"; then
    ok=0; printf '        | missing required token: %s\n' "$extra" >&2
  fi
  local beats apis refused queries
  beats=$(( $(count_calls '^beat$') + $(count_calls '^refused argv$') ))
  apis="$(count_calls '^api$')"
  refused="$(count_calls '^refused')"
  queries="$(count_sql)"
  beat_asserts=$((beat_asserts + 1))
  if [[ "$beats" != "$C_BEATS" ]]; then ok=0; printf '        | beat calls: expected %s, saw %s\n' "$C_BEATS" "$beats" >&2; fi
  if [[ "$apis" != "$C_APIS" ]]; then ok=0; printf '        | API calls: expected %s, saw %s\n' "$C_APIS" "$apis" >&2; fi
  if [[ "$queries" != "$C_Q" ]]; then ok=0; printf '        | helper queries: expected %s, saw %s\n' "$C_Q" "$queries" >&2; fi
  if [[ "$refused" != 0 ]]; then ok=0; printf '        | the stub curl REFUSED %s call(s): %s\n' "$refused" "$(grep '^refused' "$CALLS" | paste -sd, -)" >&2; fi
  # No secret, bearer, ping URL or helper error text anywhere: stdout, stderr and every argv log.
  local s
  for s in "$TOKEN" "$HB_ID_SENTINEL" "$HB_URL" "$FAKE_CRED" "$Q_PASS" "$Q_USER" "$BAD_TOKEN_SENT" "$BAD_URL_SENT"; do
    if grep -qF -- "$s" <<<"$all" || grep -qF -- "$s" "$CALLS"; then
      ok=0; printf '        | a secret-shaped sentinel leaked into output or an argv log\n' >&2
    fi
  done
  if [[ "$C_XTRACE" != "1" && "$(grep -c 'verdict=' "$OUT" || true)" != 1 ]]; then
    ok=0; printf '        | expected exactly one verdict= line, saw %s\n' "$(grep -c 'verdict=' "$OUT" || true)" >&2
  fi
  if [[ "$C_XTRACE" != "1" ]] && grep -qiE '\bexit' <<<"$all"; then
    ok=0; printf '        | human-readable output contains the word "exit"\n' >&2
  fi
  if (( ok )); then
    pass "$name (status $got, verdict $verdict)"
  else
    fail "$name — expected status $want + verdict=$verdict, got status $got [$(markers_of)]"
    sed 's/^/        | /' "$OUT" >&2
  fi
}

# ── self-tests of the machinery ───────────────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass "SELFTEST pass() moves its counter"
fail "SELFTEST fail() moves its counter (expected, reversed below)" 2>/dev/null
assert_exit_zero_iff_fed 0 query_failed SELFTEST 2>/dev/null
if (( passes != _p0 + 1 || fails != _f0 + 2 )); then
  echo "FATAL: the verdict helpers do not move their counters — every assertion below is unbacked." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo "== private PATH canary =="
cases=$((cases + 1))
reset_case; _c="$(run_feeder)"
if [[ "$(PATH="$WORK/root/bin" type -P curl)" == "$WORK/root/bin/curl" ]]; then pass "canary: curl resolves inside the private PATH"
else fail "canary: curl resolves OUTSIDE the private PATH"; fi
cases=$((cases + 1))
if ! PATH="$WORK/root/bin" type -P nc >/dev/null 2>&1 && ! PATH="$WORK/root/bin" type -P wget >/dev/null 2>&1; then pass "canary: no other network client on the private PATH"
else fail "canary: nc or wget is reachable from the private PATH"; fi

echo "== verdict-owning helper controls =="
# expect() decides the verdict of every case below. Each control drives it with ONE deliberate wrong
# expectation that passes the invariant check and trips a single later check; the control requires BOTH exactly
# one failure AND that check's own diagnostic (a control that failed early would prove nothing about the checks
# after it).
ctl() { # <label> <needle> <expect args...>
  local label="$1" needle="$2" out nf np
  shift 2
  out="$(expect "$@" 2>&1)"
  nf="$(grep -c '^  FAIL:' <<<"$out" || true)"; np="$(grep -c '^  PASS:' <<<"$out" || true)"
  cases=$((cases + 1))
  if [[ "$nf" == 1 && "$np" == 0 ]] && grep -qF -- "$needle" <<<"$out"; then pass "expect() control: $label"
  else fail "expect() control: $label — expected 1 failure ($needle), saw $nf failures / $np passes"; sed 's/^/        | /' <<<"$out" >&2; fi
}
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl1)"; C_BEATS=1; C_APIS=1
ctl "a wrong expected status is a failure" "expected status 3 + verdict=beat, got status 0" "x" 3 beat
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl2)"; C_BEATS=1; C_APIS=1
ctl "a wrong expected verdict is a failure" "expected status 0 + verdict=qualifying_row_heartbeat_paused, got status 0 [beat]" "x" 0 qualifying_row_heartbeat_paused
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl3)"; C_BEATS=1; C_APIS=1
ctl "a missing required token is a failure" "missing required token: NO_SUCH_TOKEN" "x" 0 beat "NO_SUCH_TOKEN"
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl4)"; C_BEATS=0; C_APIS=1
ctl "a wrong expected beat-call count is a failure" "beat calls: expected 0, saw 1" "x" 0 beat
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl5)"; C_BEATS=1; C_APIS=0
ctl "a wrong expected API-call count is a failure" "API calls: expected 0, saw 1" "x" 0 beat
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl6)"; C_BEATS=1; C_APIS=1; C_Q=2
ctl "a wrong expected query count is a failure" "helper queries: expected 2, saw 1" "x" 0 beat

# mutate <name> <old> <new> [src]: exact-string replace that must match EXACTLY ONCE (it LANDED); prints the path.
mutate() {
  local src="${4:-$FEEDER_SRC}" out="$WORK/mut/$1.sh"
  "$PY" -I - "$src" "$out" "$2" "$3" <<'PYM' || return 3
import sys
s = open(sys.argv[1]).read()
old, new = sys.argv[3], sys.argv[4]
n = s.count(old)
if n != 1:
    sys.stderr.write("mutate: %d occurrences of the target text\n" % n)
    sys.exit(3)
open(sys.argv[2], "w").write(s.replace(old, new))
PYM
  chmod +x "$out"
  printf '%s' "$out"
}
land() { # <row> <old> <new> -> sets M (path) or fails the case
  cases=$((cases + 1))
  if M="$(mutate "$1" "$2" "$3" "${4:-$FEEDER_SRC}" 2>"$WORK/mut.err")" && ! cmp -s "$FEEDER_SRC" "$M"; then pass "mutation row $1 landed"
  else fail "mutation row $1 did NOT land (its RED would be vacuous): $(cat "$WORK/mut.err")"; M="$FEEDER_SRC"; fi
}
ctl_mutant() { # <name> <old> <new> -> sets M
  land "$1" "$2" "$3"
}
ctl_mutant ctl-leak 'marker() { # <verdict>' 'marker() { printf "%s\n" "$BETTERSTACK_API_TOKEN_READONLY"; # <verdict>'
reset_case; C_SRC="$M"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl7)"; C_BEATS=1; C_APIS=1
ctl "a feeder that prints the token is a failure" "a secret-shaped sentinel leaked" "x" 0 beat
ctl_mutant ctl-dup 'marker() { # <verdict>' 'marker() { printf "deadman-feeder: target=x verdict=dup\n"; # <verdict>'
reset_case; C_SRC="$M"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl8)"; C_BEATS=1; C_APIS=1
ctl "a feeder that prints two verdict lines is a failure" "expected exactly one verdict= line" "x" 0 beat
ctl_mutant ctl-exit 'marker() { # <verdict>' 'marker() { echo "will exit now"; # <verdict>'
reset_case; C_SRC="$M"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctl9)"; C_BEATS=1; C_APIS=1
ctl "a feeder that prints the word exit is a failure" 'contains the word "exit"' "x" 0 beat

# ── static checks of the feeder source ────────────────────────────────────────────────────────
# static_violations <file>: one line per violated pin (empty = the file satisfies every static pin). The same
# function grades the shipped feeder and the mutants, so a mutant that breaks a pin is judged by the pin itself.
strip_comments() { sed -E 's/^[[:space:]]*#.*$//' "$1"; }
fn_body() { # <file> <fn> -> the function's lines (from "fn() {" to the closing "}" at column 0)
  awk -v f="$2" '$0 == f "() {" { on = 1 } on { print } on && $0 == "}" { on = 0 }' "$1"
}
static_violations() {
  local f="$1" S
  S="$(strip_comments "$f")"
  # exit contract
  local bad
  bad="$(grep -noE "\bexit\b[[:space:]]*[^[:space:];)'\"]*" <<<"$S" | sed -E 's/[[:space:]]+$//' | grep -vE ':exit[[:space:]]+(0|3|4|64|78)$' || true)"
  [[ -z "$bad" ]] || echo "exit-token-outside-{0,3,4,64,78}"
  [[ "$(grep -vE '^[[:space:]]*$' "$f" | tail -1)" == "exit 3" ]] || echo "last-line-not-exit-3"
  grep -qxF 'trap on_exit EXIT' "$f" && [[ "$(grep -cE '(^|[;&|[:space:]])trap[[:space:]]' <<<"$S" || true)" == 1 ]] || echo "not-exactly-one-EXIT-trap"
  ! grep -qE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' <<<"$S" || echo "exec-or-kill"
  grep -qE '^set -uo pipefail$' "$f" && ! grep -qE '^set -e' "$f" || echo "set-flags"
  grep -qF 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' "$f" && ! grep -q 'rev-parse' "$f" || echo "repo-root-not-from-BASH_SOURCE"
  # DECIDED: starts 0, set to 1 at exactly three sites (selftest, paused, beat), each directly before exit 0
  if ! [[ "$(grep -cE '^DECIDED=0$' <<<"$S" || true)" == 1 && "$(grep -cE '^[[:space:]]*DECIDED=1$' <<<"$S" || true)" == 3 \
       && "$(awk '/^[[:space:]]*DECIDED=1$/{getline n; if (n ~ /^[[:space:]]*exit 0$/) c++} END{print c+0}' <<<"$S")" == 3 ]]; then
    echo "DECIDED-sites"
  fi
  # ONE beat call site, no /fail, no sibling BEAT_MODE or fail_beat verdict, no --no-archive
  [[ "$(grep -cE "%\{http_code\}" <<<"$S" || true)" == 1 ]] || echo "beat-curl-count"
  [[ "$(grep -cE '^[[:space:]]*beat_once$' <<<"$S" || true)" == 1 && "$(grep -cE '^beat_once\(\) \{' <<<"$S" || true)" == 1 ]] || echo "beat_once-not-defined-once-called-once"
  [[ "$(grep -cE '\| curl --disable' <<<"$S" || true)" == 2 ]] || echo "curl-invocation-count"
  [[ "$(grep -cE '(^|[^[:alnum:]_])curl([[:space:]]|$)' <<<"$S" || true)" == 2 ]] || echo "bare-curl-word-count"
  ! grep -qE -- '--retry' <<<"$S" || echo "curl-retry"
  [[ "$(grep -cE -- '--max-time [0-9]+ --connect-timeout [0-9]+' <<<"$S" || true)" == 2 ]] || echo "curl-missing-max-time-or-connect-timeout"
  [[ "$(grep -cE -- "--disable --noproxy '\*'" <<<"$S" || true)" == 2 ]] || echo "curl-missing-disable-noproxy"
  [[ "$(grep -E -- '--config -' <<<"$S" | grep -c '2>/dev/null' || true)" == 2 ]] || echo "curl-stderr-not-silenced"
  grep -qF '/fail' <<<"$S" && echo "slash-fail-literal"
  grep -qE 'BEAT_MODE|fail_beat' <<<"$S" && echo "sibling-fail-arm"
  grep -qE -- '--no-archive' <<<"$S" && echo "no-archive-flag"
  # HB_URL is read ONLY inside resolve_heartbeat (assignment + shape guard) and beat_once
  local outside
  outside="$(awk '
    /^(resolve_heartbeat|beat_once)\(\) \{$/ { skip = 1 }
    skip { if ($0 == "}") skip = 0; next }
    /HB_URL/ && $0 != "HB_URL=\"\"" { print }' <<<"$S")"
  [[ -z "$outside" ]] || echo "HB_URL-read-outside-beat_once"
  ! grep -qE '(echo|printf|marker|fmarker)[^|]*HB_URL' <<<"$(grep -vF "printf 'url = " <<<"$S")" || echo "HB_URL-printed"
  # xtrace refusal present, names the four credential variables
  grep -qF 'case "$-" in' "$f" && grep -qF 'BETTERSTACK_API_TOKEN_READONLY:+x' "$f" && grep -qF 'BETTERSTACK_QUERY_PASSWORD:+x' "$f" || echo "xtrace-refusal"
  # the target is matched by literal equality and never interpolated
  fn_body "$f" select_target | grep -qE '^\s*case "\$1" in' || echo "select_target-not-a-literal-case"
  local top
  top="$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { if ($0 !~ /\}[[:space:]]*$/) skip = 1; next }
    skip { if ($0 == "}") skip = 0; next }
    /\$1|\$\{1|\$\{#1/ { print }' <<<"$S" | sed -E 's/^[[:space:]]+//')"
  [[ "$(printf '%s\n' "$top" | LC_ALL=C sort | paste -sd'|' -)" == 'if ! select_target "$1"; then|if [[ "$1" == "--selftest" ]]; then|marker "usage" "target_len=${#1}"' ]] || echo "positional-arg-interpolated"
}
echo "== static: shipped feeder =="
printf '#!/usr/bin/env bash\nexit 0\nfoo; exit 1\nexit "$rc"\n' > "$WORK/scan-positive.sh"
cases=$((cases + 1))
_v="$(grep -noE "\bexit\b[[:space:]]*[^[:space:];)'\"]*" "$WORK/scan-positive.sh" | sed -E 's/[[:space:]]+$//' | grep -vE ':exit[[:space:]]+(0|3|4|64|78)$' || true)"
if [[ "$_v" == $'3:exit 1\n4:exit' ]]; then pass "scanner known-positive: flags exit 1 and a bare/variable exit"
else fail "scanner known-positive: got [$_v]"; fi
cases=$((cases + 1))
_sv="$(static_violations "$FEEDER_SRC")"
if [[ -z "$_sv" ]]; then pass "feeder: every static pin holds (exit contract, one EXIT trap, one beat site, no /fail, curl transport, HB_URL reads)"
else fail "feeder static violations: $(paste -sd, - <<<"$_sv")"; fi
cases=$((cases + 1))
if [[ -x "$FEEDER_SRC" ]]; then pass "feeder is executable"; else fail "feeder is not executable"; fi
cases=$((cases + 1))
_order="$(grep -nxE '  count_query "\$W" "\$PRED"|  resolve_heartbeat|  beat_once' <<<"$(strip_comments "$FEEDER_SRC")" | cut -d: -f2- | sed 's/^ *//' | paste -sd, -)"
if [[ "$_order" == 'count_query "$W" "$PRED",resolve_heartbeat,beat_once' ]]; then pass "main flow order: count_query, resolve_heartbeat, beat_once"
else fail "main flow order is [$_order]"; fi
cases=$((cases + 1))
if ! grep -qE 'FEEDER_NOW|_NOW\b|date -u' <<<"$(strip_comments "$FEEDER_SRC")"; then pass "feeder has no clock and no test seam (the SQL window is the only place time lives)"
else fail "feeder reads a clock or declares a test seam"; fi

echo "== target table: derived from the script, compared with the frozen expected set =="
discover_targets() { sed -n 's/^TARGETS="\(.*\)"$/\1/p' "$1" | head -1; }
_targets="$(discover_targets "$FEEDER_SRC")"
cases=$((cases + 1))
if [[ -n "$_targets" ]] && [[ "$(tr ' ' '\n' <<<"$_targets" | sort | paste -sd' ' -)" == "$(tr ' ' '\n' <<<"$EXPECT_TARGETS" | sort | paste -sd' ' -)" ]]; then
  pass "TARGETS is exactly {$EXPECT_TARGETS}"
else fail "TARGETS is [$_targets], expected [$EXPECT_TARGETS]"; fi
cases=$((cases + 1))
if [[ "$(wc -w <<<"$_targets")" -ge 1 ]]; then pass "anti-vacuity: at least one target discovered ($(wc -w <<<"$_targets"))"
else fail "anti-vacuity: 0 targets discovered — every per-target check would be vacuous"; fi
for t in $EXPECT_TARGETS; do
  cases=$((cases + 1))
  _body="$(fn_body "$FEEDER_SRC" select_target | awk -v t="$t" '$0 ~ "^[[:space:]]*" t "\\)" {on=1; next} on && /;;/ {print; on=0} on {print}')"
  if grep -qF "W=${E_WINDOW[$t]}" <<<"$_body" && grep -qF "NAME=\"${E_NAME[$t]}\"" <<<"$_body"; then pass "target $t: window ${E_WINDOW[$t]} and heartbeat name ${E_NAME[$t]}"
  else fail "target $t: window/name arm not as expected in select_target: [$_body]"; fi
done

echo "== selftest, usage and the target gate =="
cases=$((cases + 1))
_t0=$SECONDS
_o="$(env -i PATH=/usr/bin:/bin "$BASH_BIN" "$FEEDER_SRC" --selftest 2>&1)"; _rc=$?
if [[ "$_rc" == 0 && "$_o" == "deadman-feeder: selftest=ok" ]] && (( SECONDS - _t0 < 15 )); then pass "--selftest under env -i prints selftest=ok inside the 15 s cap"
else fail "--selftest: rc=$_rc output=[$_o]"; fi
reset_case; C_ARGS="--selftest"; C_Q=0
cases=$((cases + 1)); _rc="$(run_feeder)"
if [[ "$_rc" == 0 && "$(count_calls '.')" == 0 && "$(count_sql)" == 0 ]]; then pass "--selftest makes no curl call and no helper query (rc 0)"
else fail "--selftest touched the network or the helper: rc=$_rc calls=$(count_calls '.') sql=$(count_sql)"; fi
reset_case; C_ARGS=""; C_TARGET=""; C_Q=0
expect "an empty target is a usage error (64), no query" 64 usage "target=none"
reset_case; C_ARGS="--whatever"; C_Q=0
expect "an unknown flag is a usage error (64)" 64 usage "target_len=10"
reset_case; C_ARGS="$T_LUKS extra"; C_Q=0
expect "two arguments are a usage error (64)" 64 usage
reset_case; C_ARGS="--selftest extra"; C_Q=0
expect "--selftest with an extra argument is a usage error" 64 usage
reset_case; C_TARGET="bogus"; C_Q=0
expect "unknown target: 64, prints only the length" 64 usage "target_len=5"
reset_case; C_TARGET="luks-monitor-host-timer-x"; C_Q=0
expect "a target that merely starts with a real one is unknown" 64 usage
reset_case; C_TARGET="LUKS-MONITOR-HOST-TIMER"; C_Q=0
expect "target match is case-sensitive literal equality" 64 usage
reset_case; C_TARGET="$T_LUKS' OR 1=1 --"; C_Q=0
expect "a hostile target value is never interpolated or echoed" 64 usage "target_len=${#C_TARGET}"
cases=$((cases + 1))
if ! grep -qF "OR 1=1" "$OUT" && [[ "$(count_sql)" == 0 ]]; then pass "the hostile target value appears nowhere in the output and reached no query"
else fail "the hostile target value leaked or reached a query"; fi
reset_case; C_XTRACE=1; C_Q=0
expect "traced with a credential set is refused (78)" 78 xtrace_refused
reset_case; C_GHA=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx gha)"; C_BEATS=1; C_APIS=1
expect "inside GitHub Actions with a stale seam-named export the feeder runs normally (no seams exist)" 0 beat
reset_case; C_TLSENV=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx tlsenv)"; C_BEATS=1; C_APIS=1
expect "TLS/CA environment is scrubbed before the credentialed curls" 0 beat

echo "== luks-monitor-host-timer: the window, the host, the unit =="
LP() { reset_case; C_TARGET="$T_LUKS"; }
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx l26)"; C_BEATS=1; C_APIS=1
expect "a passing row 26 h old (archive) beats" 0 beat "n=1"
LP; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx l28)"; C_Q=3
expect "a passing row 28 h old withholds" 3 no_qualifying_row "n=0"
LP; C_ROWS="$(row s3 97199 "$(luks_raw)" | fx lb1)"; C_BEATS=1; C_APIS=1
expect "boundary: 97199 s old beats" 0 beat
LP; C_ROWS="$(row s3 97200 "$(luks_raw)" | fx lb2)"; C_Q=3
expect "boundary: exactly 97200 s old withholds (strict >)" 3 no_qualifying_row
LP; C_ROWS="$(row hot 600 "$(luks_raw)" | fx lhot)"; C_BEATS=1; C_APIS=1
expect "a passing row in the HOT arm beats" 0 beat
LP; C_ROWS="$(printf '' | fx lempty)"; C_Q=3
expect "empty window withholds; the diagnostics say the host is dark" 3 no_qualifying_row "any_rows=0 fail_rows=0"
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor luks-monitor.service "$OK_MSG" soleur-web-2)" | fx lweb2)"; C_Q=3
expect "a soleur-web-2 row withholds (host_name conjunct)" 3 no_qualifying_row "any_rows=0"
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor __none__)" | fx lverify)"; C_Q=3
expect "a verify-job row without _SYSTEMD_UNIT withholds" 3 no_qualifying_row
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor session-41.scope)" | fx lscope)"; C_Q=3
expect "a verify-job row under a session scope withholds" 3 no_qualifying_row
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw other-tag)" | fx lident)"; C_Q=3
expect "a row with another SYSLOG_IDENTIFIER withholds" 3 no_qualifying_row
LP; C_ROWS="$(row s3 "$((2 * H))" "$(luks_raw luks-monitor luks-monitor.service "$FAIL_MSG")" | fx lfail)"; C_Q=3
expect "a FAIL row (correct tag/unit/host) withholds; the diagnostics name it" 3 no_qualifying_row "any_rows=1 fail_rows=1"
LP; C_ROWS="$(row s3 "$((2 * H))" "$(luks_raw luks-monitor luks-monitor.service 'helper: probing the mount')" | fx lhelper)"; C_Q=3
expect "a helper row (same tag/unit/host, no OK needle) withholds; any_rows counts it" 3 no_qualifying_row "any_rows=1 fail_rows=0"
LP; C_ROWS="$(row hot -400 "$(luks_raw)" | fx lfut)"; C_Q=3
expect "a future-dated row (+400 s) withholds" 3 no_qualifying_row
LP; C_ROWS="$(row hot -300 "$(luks_raw)" | fx lfut300)"; C_BEATS=1; C_APIS=1
expect "future slack boundary: +300 s is accepted" 0 beat
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" 0 | fx lrt0)"; C_Q=3
expect "an archive row with _row_type != 1 withholds" 3 no_qualifying_row
LP; C_ROWS="$({ row s3 "$((28 * H))" "$(luks_raw)"; row s3 "$((26 * H))" "$(luks_raw luks-monitor luks-monitor.service "$OK_MSG" soleur-web-2)"; } | fx lmix)"; C_Q=3
expect "only out-of-window and wrong-host rows: withholds" 3 no_qualifying_row
LP; C_ROWS="$({ row s3 "$((28 * H))" "$(luks_raw)"; row s3 "$((25 * H))" "$(luks_raw)"; } | fx lmix2)"; C_BEATS=1; C_APIS=1
expect "an old row beside an in-window one: the window row decides" 0 beat "n=1"
LP; C_ROWS="$({ row hot 60 "$(luks_raw)"; row s3 "$((25 * H))" "$(luks_raw)"; } | fx lmix3)"; C_BEATS=1; C_APIS=1
expect "rows in both arms are both counted" 0 beat "n=2"

echo "== claude-cost-capture: the cost marker arm and the credit-probe arm =="
CP() { reset_case; C_TARGET="$T_COST"; }
CP; C_ROWS="$(row s3 "$((20 * H))" "$(cost_raw cron:cron-roadmap-review)" | fx c20)"; C_BEATS=1; C_APIS=1
expect "a cron cost marker 20 h old beats" 0 beat "n=1"
CP; C_ROWS="$(row s3 "$((26 * H))" "$(cost_raw cron:cron-roadmap-review)" | fx c26)"
expect "a cron cost marker 26 h old withholds" 3 no_qualifying_row "n=0"
CP; C_ROWS="$(row s3 86399 "$(cost_raw cron:x)" | fx cb1)"; C_BEATS=1; C_APIS=1
expect "boundary: 86399 s old beats" 0 beat
CP; C_ROWS="$(row s3 86400 "$(cost_raw cron:x)" | fx cb2)"
expect "boundary: exactly 86400 s old withholds" 3 no_qualifying_row
CP; C_ROWS="$(row hot 300 "$(cost_raw cron:x)" | fx chot)"; C_BEATS=1; C_APIS=1
expect "a cost marker in the HOT arm beats" 0 beat
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x null)" | fx cnull)"
expect "a marker with cost_usd null withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x absent)" | fx cabsent)"
expect "a marker with no cost_usd key withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x 0)" | fx czero)"; C_BEATS=1; C_APIS=1
expect "a marker with cost_usd 0 is a real (non-null) cost row and beats" 0 beat
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x 3.1 claude-cost SOLEUR_CLAUDE_COST_DAILY)" | fx cdaily)"
expect "an org-total _DAILY row withholds (key match)" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw session:abc123)" | fx cbyok)"
expect "a founder BYOK source (not cron:) withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x 0.1 github-issue)" | fx cecho)"
expect "an echoed marker under another component withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(probe_raw anthropic-credit-exhausted)" | fx cprobe)"; C_BEATS=1; C_APIS=1
expect "a credit-probe RED row (credit exhausted) alone beats" 0 beat
CP; C_ROWS="$(row s3 "$((20 * H))" "$(probe_raw anthropic-key-invalid)" | fx cprobe2)"; C_BEATS=1; C_APIS=1
expect "a credit-probe RED row (key invalid), 20 h old, alone beats" 0 beat
CP; C_ROWS="$(row s3 "$((2 * H))" "$(probe_raw anthropic-key-missing)" | fx cprobe3)"
expect "a credit-probe row with another op withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((2 * H))" "$(jq -cn '{message:{feature:"cron-something-else",op:"anthropic-credit-exhausted"}}')" | fx cprobe4)"
expect "another feature with the RED op withholds" 3 no_qualifying_row
CP; C_ROWS="$(printf '' | fx cempty)"
expect "empty window withholds (no diagnostics for this target)" 3 no_qualifying_row "n=0"
CP; C_ROWS="$(row hot -400 "$(cost_raw cron:x)" | fx cfut)"
expect "a future-dated cost marker withholds" 3 no_qualifying_row
CP; C_ROWS="$(row s3 "$((20 * H))" "$(cost_raw cron:x)" 0 | fx crt0)"
expect "an archive cost row with _row_type != 1 withholds" 3 no_qualifying_row

echo "== the answer contract (the one-line aggregate) =="
LP; C_STUB="okstr"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx a1)"; C_BEATS=1; C_APIS=1
expect "n as a quoted string (\"1\") beats" 0 beat "n=1"
LP; C_STUB="okstr"; C_ROWS="$(printf '' | fx a2)"; C_Q=3
expect "n as a quoted string (\"0\") on the epoch row withholds, never beats" 3 no_qualifying_row "n=0"
LP; C_STUB="ok"; C_ROWS="$(printf '' | fx a2b)"; C_Q=3
expect "n as the JSON number 0 on the epoch row withholds" 3 no_qualifying_row "n=0"
for _m in zero two garbage nonnumeric negn floatn bign exception nolinen nonobj nulln; do
  LP; C_STUB="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx a-$_m)"
  expect "answer shape '$_m' is query_failed (never a beat, never a withhold-as-absent)" 3 query_failed "reason="
done
LP; C_STUB="fail"
expect "helper fails with a credential-bearing error: class only" 3 query_failed "class=auth"
LP; C_STUB="failbody"
expect "helper exits non-zero with a JSON error body on stdout: stdout is discarded unread" 3 query_failed "reason=helper_status"
LP; C_STUB="none"; C_Q=0
expect "helper missing" 3 query_failed "reason=helper_missing"
LP; C_UNSET="BETTERSTACK_QUERY_PASSWORD"; C_Q=0
expect "query secret unset" 3 query_failed "reason=secret_unset"
LP; C_STUB="hostile"; C_BEATS=1; C_APIS=1
expect "a hostile newest string is never echoed (newest_dt=unparsed)" 0 beat "newest_dt=unparsed"
cases=$((cases + 1))
if ! grep -q 'set-output' "$OUT"; then pass "the remote-derived newest string reached no output line"
else fail "a remote-derived string leaked into the output"; fi
LP; C_STUB="hugenewest"; C_BEATS=1; C_APIS=1
expect "an over-long newest string is never echoed" 0 beat "newest_dt=unparsed"
LP; C_STUB="numnewest"; C_BEATS=1; C_APIS=1
expect "a non-string newest is informational only (unparsed)" 0 beat "newest_dt=unparsed"
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx a-newest)"; C_BEATS=1; C_APIS=1
expect "a well-formed newest is echoed in the marker-safe form (underscore for the space)" 0 beat "newest_dt=2026-10-29_"

echo "== the SQL the feeder sends (frozen shape, both arms, the archive filter) =="
for t in $EXPECT_TARGETS; do
  reset_case; C_TARGET="$t"; C_ROWS="$(printf '' | fx sqlpin-$t)"; C_Q=3; _g="$(run_feeder)"
  [[ "$t" == "$T_LUKS" ]] || C_Q=1
  _sql="$(head -1 "$SQLLOG")"
  cases=$((cases + 1))
  if [[ "$_sql" == "$(expect_sql "$t" "${E_PRED[$t]}")" ]]; then pass "$t: the first query equals the frozen SQL byte for byte (window ${E_WINDOW[$t]} in BOTH arms)"
  else fail "$t: the SQL differs from the frozen shape"; printf '        | got:  %s\n        | want: %s\n' "$_sql" "$(expect_sql "$t" "${E_PRED[$t]}")" >&2; fi
  cases=$((cases + 1))
  _w="${E_WINDOW[$t]}"
  if [[ "$(grep -oF "dt > now() - INTERVAL $_w SECOND" <<<"$_sql" | wc -l)" == 2 && "$(grep -oF "dt <= now() + INTERVAL 300 SECOND" <<<"$_sql" | wc -l)" == 2 \
        && "$_sql" == *'s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND '* && "$_sql" == *'remote($BS_TABLE)'* ]]; then
    pass "$t: remote() AND s3Cluster arms each carry the lower and upper dt bound; the archive arm filters _row_type = 1"
  else fail "$t: window/archive pins do not hold in the sent SQL"; fi
  cases=$((cases + 1))
  _dollar="${_sql//\$BS_TABLE_S3/}"; _dollar="${_dollar//\$BS_TABLE/}"
  if [[ "$_dollar" != *'$'* && "$_sql" != *$'\n'* && "$_sql" != *--no-archive* ]]; then pass "$t: a dollar sign appears only as the two table tokens; one line; no --no-archive"
  else fail "$t: stray dollar sign, newline or --no-archive in the SQL"; fi
done
reset_case; C_ROWS="$(printf '' | fx sqlpin-diag)"; C_Q=3; _g="$(run_feeder)"
cases=$((cases + 1))
_d2="$(sed -n 2p "$SQLLOG")"; _d3="$(sed -n 3p "$SQLLOG")"
_anyp="JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'"
if [[ "$_d2" == "$(expect_sql "$T_LUKS" "$_anyp")" && "$_d3" == "$(expect_sql "$T_LUKS" "$_anyp AND JSONExtractString(raw, 'message') LIKE 'FAIL (%'")" ]]; then
  pass "the two diagnostic queries are the same window with the identifier/unit/host (and the FAIL prefix) only"
else fail "the diagnostic queries are not the frozen shapes"; printf '        | %s\n        | %s\n' "$_d2" "$_d3" >&2; fi
cases=$((cases + 1))
if [[ "$(grep -c . <<<"$(fn_body "$FEEDER_SRC" withhold_no_row)")" -gt 0 ]]; then pass "withhold_no_row exists (the diagnostics live in one function)"
else fail "withhold_no_row function not found"; fi

echo "== heartbeat resolution =="
HP() { LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx hb)"; C_APIS=1; }
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" true "$HB_URL" | fx apiPaused)"
expect "heartbeat paused: exit 0, nothing sent" 0 qualifying_row_heartbeat_paused "n=1"
HP; C_TARGET="$T_COST"; C_ROWS="$(row s3 "$((20 * H))" "$(cost_raw cron:x)" | fx hbc)"; C_API="$(hb_json "${E_NAME[$T_COST]}" true "$HB_URL" | fx apiPausedC)"
expect "heartbeat paused (cost target): exit 0, nothing sent" 0 qualifying_row_heartbeat_paused
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" __absent__ "$HB_URL" | fx apiNoPaused)"
expect "paused attribute absent" 4 beat_failed "reason=paused_not_boolean"
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" null "$HB_URL" | fx apiNullPaused)"
expect "paused attribute null" 4 beat_failed "reason=paused_not_boolean"
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" '"false"' "$HB_URL" | fx apiStrPaused)"
expect "paused attribute the string \"false\"" 4 beat_failed "reason=paused_not_boolean"
HP; C_API="$(hb_json "soleur-other-heartbeat" false "$HB_URL" | fx apiOther)"
expect "heartbeat name absent" 4 beat_failed "reason=heartbeat_not_unique matches=0"
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}-old" false "$HB_URL" | fx apiPrefix)"
expect "prefix decoy (name plus a suffix) is not a match" 4 beat_failed "matches=0"
HP; C_API="$(hb_json "old-${E_NAME[$T_LUKS]}" false "$HB_URL" | fx apiPrefix2)"
expect "leading decoy (old-NAME) is not a match" 4 beat_failed "matches=0 paged=0"
HP; C_API="$(hb_json "${E_NAME[$T_COST]}" false "$HB_URL" | fx apiOtherTarget)"
expect "the OTHER target's heartbeat is not this target's (exact name per target)" 4 beat_failed "matches=0"
HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" false "$HB_URL" | jq -c '. + {pagination: {next: "https://x.example/page2"}}' | fx apiPaged1)"
expect "a unique match on page 1 is not trusted while a later page exists" 4 beat_failed "matches=1 paged=1"
HP; C_API="$(jq -cn '{data: [], pagination: {next: "https://x.example/page2"}}' | fx apiPaged2)"
expect "a heartbeat beyond page 1 is reported as paged, never as missing" 4 beat_failed "paged=1"
HP; C_API="$(jq -cn --argjson a "$(hb_json "${E_NAME[$T_LUKS]}" false "$HB_URL")" '{data: ($a.data + $a.data)}' | fx apiTwo)"
expect "two heartbeats with the name" 4 beat_failed "reason=heartbeat_not_unique matches=2"
for _u in "https://evil.example/api/v1/heartbeat/$BAD_URL_SENT" "http://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT" \
          "https://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT/fail" "https://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT/extra" \
          "https://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT?x=1" "https://uptime.betterstack.com.evil.example/api/v1/heartbeat/$BAD_URL_SENT" \
          "https://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT\"x" "https://uptime.betterstack.com/api/v1/heartbeat/" \
          " https://uptime.betterstack.com/api/v1/heartbeat/$BAD_URL_SENT" $'https://uptime.betterstack.com/api/v1/heartbeat/'"$BAD_URL_SENT"$'\nurl = "https://evil.example/"' ""; do
  HP; C_API="$(hb_json "${E_NAME[$T_LUKS]}" false "$_u" | fx apiurl)"
  expect "URL shape refused: $(printf '%s' "${_u:-<empty>}" | tr '\n' '~' | head -c 60)" 4 beat_failed "reason=url_shape"
done
HP; C_APIMODE="fail"
expect "uptime API unreadable" 4 beat_failed "reason=api_unreadable"
HP; printf '<html>not json</html>' > "$WORK/fx/notjson"; C_API="$WORK/fx/notjson"
expect "uptime API answers something that is not a heartbeat list" 4 beat_failed "reason=api_malformed"
HP; C_TOKEN="__unset__"; C_APIS=0
expect "read-only token unset" 4 beat_failed "reason=api_token_unset"
HP; C_TOKEN="${BAD_TOKEN_SENT}\"x"; C_APIS=0
expect "read-only token malformed (quote and too short)" 4 beat_failed "reason=api_token_malformed"
HP; C_TOKEN="${BAD_TOKEN_SENT}abcdefg\""; C_APIS=0
expect "read-only token malformed (a quote alone, long enough)" 4 beat_failed "reason=api_token_malformed"
LP; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx hbstale)"; C_TOKEN="__unset__"; C_Q=3
expect "a withhold happens before the credential is even read (no API call)" 3 no_qualifying_row

echo "== beat delivery =="
BP() { HP; }
BP; C_BEATMODE="500"; C_BEATS=1
expect "beat answered 500" 4 beat_failed "reason=http_status"
BP; C_BEATMODE="302"; C_BEATS=1
expect "beat answered 302 (passes curl -f; only 2xx counts)" 4 beat_failed "http=302"
BP; C_BEATMODE="429"; C_BEATS=1
expect "beat answered 429 with Retry-After: no retry (one call)" 4 beat_failed "http=429"
BP; C_BEATMODE="403body"; C_BEATS=1
expect "beat answered 403 with a credential-shaped body on stderr: nothing echoed" 4 beat_failed "http=403"
BP; C_BEATMODE="timeout"; C_BEATS=1
expect "beat stalls past --max-time (curl 28): beat_failed, no retry" 4 beat_failed "curl_rc=28"
BP; C_BEATMODE="curlfail"; C_BEATS=1
expect "beat curl fails outright" 4 beat_failed "reason=http_status"

echo "== EXIT trap: an undecided status is never an unexplained zero =="
land falloff '  beat_once' '  DECIDED=0; exit 0'; M_FALL="$M"
reset_case; C_SRC="$M_FALL"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx fo)"; C_APIS=1; _rc="$(run_feeder)"
cases=$((cases + 1))
if [[ "$_rc" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "an undecided exit 0 is remapped to 3 trap_remapped, never 0"
else fail "undecided exit 0: expected 3 trap_remapped, got $_rc [$(markers_of)]"; fi
land fallthrough5 '  beat_once' '  exit 5'; M="$M"
reset_case; C_SRC="$M"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx fo5)"; C_APIS=1; _rc="$(run_feeder)"
cases=$((cases + 1))
if [[ "$_rc" == 3 ]] && grep -qE 'verdict=trap_remapped rc=5' "$OUT"; then pass "an unknown status (5) is remapped to 3 with rc=5 recorded"
else fail "unknown status 5: expected 3 trap_remapped rc=5, got $_rc [$(markers_of)]"; fi

echo "== workflow wiring =="
workflow_violations() { # <workflow-file> -> one line per violated pin
  "$PY" -I - "$1" "$FEEDER_SRC" <<'PYW'
import re, sys
import yaml
wfp, feeder = sys.argv[1], sys.argv[2]
text = open(wfp).read()
wf = yaml.safe_load(text)
bad = []
def need(c, m):
    if not c: bad.append(m)
on = wf.get(True) or wf.get("on") or {}
need(set(on) == {"schedule", "workflow_dispatch"}, "triggers-not-exactly-schedule-and-dispatch")
need(on.get("workflow_dispatch") in ({}, None), "dispatch-takes-inputs")
need([c.get("cron") for c in on.get("schedule", [])] == ["0 * * * *"], "fallback-cron")
need((wf.get("concurrency") or {}).get("group") == "scheduled-deadman-heartbeat-feeder" and (wf.get("concurrency") or {}).get("cancel-in-progress") is False, "concurrency")
need(wf.get("permissions") == {"contents": "read"}, "permissions")
need("env" not in wf, "workflow-level-env")
jobs = wf.get("jobs") or {}
need(len(jobs) == 1, "not-exactly-one-job")
job = list(jobs.values())[0] if jobs else {}
need("environment" not in job, "declares-environment")
need("env" not in job, "job-level-env")
need(job.get("timeout-minutes") == 6, "timeout-minutes-not-6")
need(job.get("runs-on") == "ubuntu-24.04", "runs-on")
steps = job.get("steps") or []
co = [s for s in steps if "actions/checkout" in str(s.get("uses", ""))]
need(len(co) == 1 and co[0]["uses"] == "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1".split(" #")[0] and (co[0].get("with") or {}).get("persist-credentials") is False, "checkout-pin-or-persist-credentials")
fs = [s for s in steps if s.get("id") == "feeder"]
need(len(fs) == 1, "feeder-step-count")
fstep = fs[0] if fs else {}
need("continue-on-error" not in fstep and "if" not in fstep, "feeder-step-skippable")
need(fstep.get("env") == {
    "BETTERSTACK_QUERY_HOST": "${{ secrets.BETTERSTACK_QUERY_HOST }}",
    "BETTERSTACK_QUERY_USERNAME": "${{ secrets.BETTERSTACK_QUERY_USERNAME }}",
    "BETTERSTACK_QUERY_PASSWORD": "${{ secrets.BETTERSTACK_QUERY_PASSWORD }}",
    "BETTERSTACK_API_TOKEN_READONLY": "${{ secrets.BETTERSTACK_API_TOKEN_READONLY }}",
}, "feeder-step-env-not-exactly-the-four-secrets")
for s in steps:
    if s is not fstep:
        need(not any(k in (s.get("env") or {}) for k in ("BETTERSTACK_QUERY_HOST", "BETTERSTACK_QUERY_USERNAME", "BETTERSTACK_QUERY_PASSWORD", "BETTERSTACK_API_TOKEN_READONLY")), "credential-env-outside-feeder-step")
run = fstep.get("run", "")
need("${{" not in run, "expression-inside-run-block")
loops = re.findall(r"for t in ([a-z -]+); do", run)
need(len(loops) == 1, "target-loop-count")
need(loops and loops[0].split() == sorted(loops[0].split(), key=lambda x: loops[0].split().index(x)) and set(loops[0].split()) == set(re.search(r'^TARGETS="(.*)"$', open(feeder).read(), re.M).group(1).split()), "loop-targets-differ-from-script-table")
need(bool(re.search(r'out="\$\(bash scripts/deadman-heartbeat-feeder\.sh "\$t" 2>&1\)" \|\| rc=\$\?', run)), "rc-capture")
need(len(re.findall(r"^\s*bash scripts/deadman-heartbeat-feeder\.sh|bash scripts/deadman-heartbeat-feeder\.sh", run)) == 1, "invocation-count")
need("break" not in re.sub(r"#.*", "", run), "loop-breaks-on-failure")
need("all_decided=" in run and "GITHUB_OUTPUT" in run, "all_decided-output")
need("UNARMED (paused)" in run and "::warning::" in run, "unarmed-warning")
need("strip_log_injection()" in run, "strip_log_injection")
sent = steps[-1] if steps else {}
need(sent.get("uses") == "./.github/actions/sentry-heartbeat" and (sent.get("with") or {}).get("monitor-slug") == "scheduled-deadman-heartbeat-feeder", "sentry-step")
need(sent.get("if") == "always()" and sent.get("continue-on-error") is True, "sentry-step-if-always")
need((sent.get("with") or {}).get("status") == "${{ steps.feeder.outputs.all_decided == 'true' && 'ok' || 'error' }}", "sentry-status-expression")
for tok in ("DOPPLER_TOKEN", "HCLOUD_TOKEN"):
    need(tok not in re.sub(r"(?m)^\s*#.*$", "", text), "names-" + tok)
need(re.search(r"gate-override: new-scheduled-cron-prefer-inngest", text) is not None, "gate-override-header")
for u in [s.get("uses", "") for s in steps if s.get("uses")]:
    need(u.startswith("./") or re.search(r"@[0-9a-f]{40}$", u) is not None, "unpinned-action")
print("\n".join(bad))
PYW
}
cases=$((cases + 1))
if [[ -f "$WORKFLOW" ]]; then
  _wv="$(workflow_violations "$WORKFLOW" 2>&1)"
  if [[ -z "$_wv" ]]; then pass "workflow: triggers, concurrency, permissions, pins, step env, loop = script table, Sentry status, Tier A"
  else fail "workflow violations: $(paste -sd, - <<<"$_wv")"; fi
else fail "workflow file missing: $WORKFLOW"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^[^#]*bash scripts/deadman-heartbeat-feeder\.sh' "$WORKFLOW" 2>/dev/null || true)" == 1 ]]; then pass "the manifest evidence pattern appears once, on the run line"
else fail "the evidence pattern must appear exactly once outside comments"; fi

echo "== workflow step behaviour (the real run: block against a stubbed feeder) =="
WF_RUN="$WORK/wf.run.sh"
"$PY" -I - "$WORKFLOW" "$WF_RUN" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
step = [s for s in wf["jobs"][list(wf["jobs"])[0]]["steps"] if s.get("id") == "feeder"][0]
open(sys.argv[2], "w").write(step["run"])
PY
wf_run() { # <stub body> [VAR=val ...] -> WF_RC; $d/out.txt and $d/log.txt hold the outputs and the log
  local d="$WORK/wf" body="$1"; shift
  assert_fixture_dir "$d"
  case "$d" in "$WORK"/wf) rm -rf -- "$d" ;; *) echo "FATAL: wf dir" >&2; exit 2 ;; esac
  mkdir -p "$d/scripts"
  if [[ "$body" != "__missing__" ]]; then printf '%s\n' "$body" > "$d/scripts/deadman-heartbeat-feeder.sh"; fi
  : > "$d/out.txt"
  WF_RC=0
  ( cd "$d" && env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$d/out.txt" "$@" "$BASH_BIN" --noprofile --norc -eo pipefail "${WF_RUN_OVERRIDE:-$WF_RUN}" > "$d/log.txt" 2>&1 ) || WF_RC=$?
}
wf_check() { # <name> <cond-description> <exit-status-of-condition>
  cases=$((cases + 1))
  if [[ "$3" == 0 ]]; then pass "$1: $2"; else fail "$1: $2"; sed 's/^/        | /' "$WORK/wf/log.txt" >&2; fi
}
GOOD='case "$1" in
  luks-monitor-host-timer) printf "deadman-feeder: target=luks-monitor-host-timer verdict=beat n=1 newest_dt=2026-10-30_00:04:56.747448\n"; echo "fed: noise line"; exit 0 ;;
  claude-cost-capture) printf "deadman-feeder: target=claude-cost-capture verdict=beat n=4\n"; exit 0 ;;
esac'
wf_run "$GOOD"
wf_check "workflow step, both beat" "exits 0, all_decided=true, only marker lines echoed, no UNARMED warning" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=true' "$WORK/wf/out.txt" && grep -q 'verdict=beat n=1' "$WORK/wf/log.txt" && grep -q 'verdict=beat n=4' "$WORK/wf/log.txt" && ! grep -q 'fed: noise' "$WORK/wf/log.txt" && ! grep -q 'UNARMED' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=qualifying_row_heartbeat_paused n=1\n"; exit 0'
wf_check "workflow step, both paused" "all_decided=true and one UNARMED warning per target, every run" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=true' "$WORK/wf/out.txt" && [[ "$(grep -c '^::warning::deadman heartbeat .* is UNARMED (paused): no page can fire' "$WORK/wf/log.txt")" == 2 ]]; echo $?)"
wf_run 'case "$1" in luks-monitor-host-timer) printf "deadman-feeder: target=luks-monitor-host-timer verdict=no_qualifying_row n=0 any_rows=0 fail_rows=0\nCANNOT BEAT: the nightly row is absent\n"; exit 3 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
wf_check "workflow step, first target withheld" "the second target still runs (no break), all_decided=false, an ::error:: names the target" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" && grep -q 'verdict=beat n=2' "$WORK/wf/log.txt" && grep -q '^::error::.*luks-monitor-host-timer' "$WORK/wf/log.txt"; echo $?)"
wf_run 'case "$1" in claude-cost-capture) printf "deadman-feeder: target=claude-cost-capture verdict=beat_failed reason=http_status\n"; exit 4 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
wf_check "workflow step, second target beat_failed" "all_decided=false and an ::error::" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" && grep -q '^::error::.*claude-cost-capture' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "::set-output name=x::y\n"; printf "deadman-feeder: target=$1 verdict=no_qualifying_row n=0\n"; exit 3'
wf_check "workflow step, command injection" "a feeder line that starts with :: never reaches the log as a command" "$(! grep -q '^::set-output' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=beat \033[31mred\033[0m\n"; exit 0'
wf_check "workflow step, control characters" "an escape sequence is stripped; a line that then fails the marker shape is counted, not printed" "$(! LC_ALL=C grep -q $'\033' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=beat url=https://uptime.betterstack.com/api/v1/heartbeat/SYNTHsecret\n"; exit 0'
wf_check "workflow step, shape discipline" "a marker carrying a URL-shaped value fails the shape and is NOT printed" "$(! grep -q 'SYNTHsecret' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=weird\n"; exit 0'
wf_check "workflow step, exit 0 without a deciding verdict" "all_decided=false (Sentry error), never ok" "$(grep -qx 'all_decided=false' "$WORK/wf/out.txt"; echo $?)"
wf_run 'case "$1" in luks-monitor-host-timer) exit 0 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=1\n"; exit 0 ;; esac'
wf_check "workflow step, silent exit 0" "a feeder that exits 0 with no marker is NOT a decision: all_decided=false" "$(grep -qx 'all_decided=false' "$WORK/wf/out.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=other-target verdict=beat n=1\n"; exit 0'
wf_check "workflow step, wrong target in the marker" "a marker naming another target does not decide this one: all_decided=false" "$(grep -qx 'all_decided=false' "$WORK/wf/out.txt"; echo $?)"
wf_run __missing__
wf_check "workflow step, feeder missing" "step exits 0, all_decided=false, the cause is named" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" && grep -q 'no_marker' "$WORK/wf/log.txt"; echo $?)"
sed -E '/^ *break$/d' "$WF_RUN" > "$WORK/wf.same.sh"
cases=$((cases + 1))
if cmp -s "$WF_RUN" "$WORK/wf.same.sh"; then pass "the run block contains no bare break line"; else fail "the run block contains a bare break"; fi

echo "== Guard 2: predicate fidelity with the emitters =="
guard2_checks() { # <feeder> <luks-monitor.sh> -> "OK ..." / "FAIL ..." lines
  "$PY" -I - "$1" "$2" "$EMIT_LUKS_UNIT" "$EMIT_VECTOR" "$EMIT_SERVER_TF" "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE" <<'PYG'
import re, sys
feeder, luks, unit, vector, servertf, marker_ts, substrate_ts, probe_ts = [open(p, encoding="utf-8").read() for p in sys.argv[1:9]]
out = []
def check(c, m): out.append(("OK " if c else "FAIL ") + m)
def pred(name):
    m = re.search(r"def_pred " + name + r" <<'EOF'\n(.*?)\nEOF", feeder, re.S)
    return m.group(1).strip() if m else None
lp, cp = pred("LUKS_PRED"), pred("COST_PRED")
check(lp is not None and cp is not None, "both predicates are extractable from the feeder (anti-vacuity)")
lp, cp = lp or "", cp or ""
check(len(re.findall(r" AND ", lp)) == 3 and len(re.findall(r"JSONExtractString\(raw, '", lp)) == 4, "luks: exactly four AND-joined field conjuncts (anti-vacuity floor)")
check(" OR " not in lp, "luks: no OR (the unit conjunct cannot be bypassed)")
# --- luks: the needle is a substring of the OK line the script logs, and the other literals match their writers
okline = re.search(r'^log "(OK: /mnt/data is LUKS-backed)\b', luks, re.M)
needle = re.search(r"LIKE '%(OK: /mnt/data is LUKS-backed[^%']*)%'", lp)
check(okline is not None and needle is not None and needle.group(1) == okline.group(1), "luks: the LIKE needle equals the OK line luks-monitor.sh logs (%r vs %r)" % (needle and needle.group(1), okline and okline.group(1)))
tag = re.search(r'^LOG_TAG="([^"]+)"', luks, re.M)
ident = re.search(r"JSONExtractString\(raw, 'SYSLOG_IDENTIFIER'\) = '([^']+)'", lp)
check(tag is not None and ident is not None and tag.group(1) == ident.group(1), "luks: SYSLOG_IDENTIFIER equals luks-monitor.sh's LOG_TAG")
sid = re.search(r"^SyslogIdentifier=(\S+)", unit, re.M)
check(sid is not None and ident is not None and sid.group(1) == ident.group(1), "luks: SYSLOG_IDENTIFIER equals the unit's SyslogIdentifier")
unitq = re.search(r"JSONExtractString\(raw, '_SYSTEMD_UNIT'\) = '([^']+)'", lp)
check(unitq is not None and unitq.group(1) == "luks-monitor.service" and "[Service]" in unit, "luks: _SYSTEMD_UNIT is the unit this repo ships (luks-monitor.service)")
check(re.search(r'^\s*\.host_name = "@@HOST_NAME@@"', vector, re.M) is not None, "luks: host_name is written by vector.toml's journald transform (@@HOST_NAME@@)")
hn = re.search(r"JSONExtractString\(raw, 'host_name'\) = '([^']+)'", lp)
check(hn is not None and re.search(r'name\s*=\s*each\.key == "web-1" \? "' + re.escape(hn.group(1)) + '"', servertf) is not None, "luks: host_name literal is web-1's server name in server.tf")
check(re.search(r"include_matches\.SYSLOG_IDENTIFIER", vector) is not None and '"luks-monitor"' in vector, "luks: the tag is in vector.toml's host_scripts_journald allowlist")
# --- cost: exactly two arms; literals pinned to their TS emitters
check(len(re.findall(r"\bOR\b", cp)) == 1, "cost: exactly one OR, joining the marker arm and the credit-probe arm")
check("raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%'" in cp and "'Nullable(Float64)') IS NOT NULL" in cp, "cost: the marker arm keeps the key match and the non-null cost_usd")
check("JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'" in cp, "cost: the marker arm keeps source LIKE 'cron:%'")
check("JSONExtractString(raw, 'message', 'component') = 'claude-cost'" in cp, "cost: the marker arm keeps component = 'claude-cost'")
cron = re.search(r'^const CRON_NAME = "([a-z0-9-]+)";', probe_ts, re.M)
armb = re.search(r"OR \(JSONExtractString\(raw, 'message', 'feature'\) = '([^']*)' AND JSONExtractString\(raw, 'message', 'op'\) IN \(([^)]*)\)\)", cp)
ops_sql = set(re.findall(r"'([^']*)'", armb.group(2))) if armb else set()
opu = re.search(r"op\?:\s*([^;]+);", probe_ts)
ops_ts = set(re.findall(r'"(anthropic-[a-z-]+)"', opu.group(1))) if opu else set()
check(cron is not None and armb is not None and armb.group(1) == cron.group(1), "cost: arm B's feature literal is the credit probe's CRON_NAME (%s)" % (cron and cron.group(1)))
check(bool(ops_sql) and bool(ops_ts) and ops_sql <= ops_ts, "cost: arm B's ops are members of the probe's op union (sql=%s ts=%s)" % (sorted(ops_sql), sorted(ops_ts)))
check(re.search(r'pino\(\{ base: \{ component: "claude-cost" \} \}\)', marker_ts) is not None, "cost: component 'claude-cost' is the marker logger's pino base")
check(re.search(r"log\.warn\(\{ SOLEUR_CLAUDE_COST: true, \.\.\.m \}", marker_ts) is not None, "cost: the marker writes the SOLEUR_CLAUDE_COST: true key")
check("source: `cron:${cronName}`" in substrate_ts, "cost: the substrate writes source `cron:${cronName}`")
print("\n".join(out))
PYG
}
_g2="$(guard2_checks "$FEEDER_SRC" "$EMIT_LUKS" 2>&1)"
while IFS= read -r _l; do
  [[ -n "$_l" ]] || continue
  cases=$((cases + 1))
  case "$_l" in OK\ *) pass "${_l#OK }" ;; *) fail "${_l#FAIL }" ;; esac
done <<<"$_g2"
cases=$((cases + 1))
if [[ "$(grep -c '^OK ' <<<"$_g2")" -ge 19 && "$(grep -c '^FAIL' <<<"$_g2" || true)" == 0 ]]; then pass "Guard 2: all 19 emitter pins hold (a crashing checker would print fewer)"
else fail "Guard 2: emitter pins incomplete or failing ($(grep -c '^OK ' <<<"$_g2") OK)"; fi
# the frozen-set identity: each target's predicate in the script equals the suite's independent expected text
cases=$((cases + 1))
_gp="$("$PY" -I - "$FEEDER_SRC" "${E_PRED[$T_LUKS]}" "${E_PRED[$T_COST]}" <<'PYF'
import re, sys
s = open(sys.argv[1]).read()
def pred(name):
    m = re.search(r"def_pred " + name + r" <<'EOF'\n(.*?)\nEOF", s, re.S)
    return m.group(1).strip() if m else None
print("ok" if pred("LUKS_PRED") == sys.argv[2] and pred("COST_PRED") == sys.argv[3] else "differs")
PYF
)"
if [[ "$_gp" == ok ]]; then pass "both predicates equal the suite's frozen expected text"
else fail "a predicate differs from the frozen expected text"; fi

echo "== Guard 4: wiring parity across the surfaces that must agree =="
wiring_violations() { # <uptime_tf> <apply_yml> <table_ts> <feeder> <monitors_tf> -> one line per violated pin
  "$PY" -I - "$1" "$2" "$3" "$4" "$5" "$WORKFLOW" "$ALERTS_TF" "${EXPECT_TARGETS// /,}" <<'PYW'
import re, sys
tfp, applyp, tablep, feederp, monp, wfp, alertsp, targets = sys.argv[1:9]
tf, apply_, table, feeder, mon, wf, alerts = [open(p).read() for p in (tfp, applyp, tablep, feederp, monp, wfp, alertsp)]
bad = []
def need(c, m):
    if not c: bad.append(m)
tl = targets.split(",")
need(len(tl) >= 1, "no-targets")
names = {}
for t in tl:
    m = re.search(r'select_target\(\) \{.*?\n\s*' + re.escape(t) + r'\)(.*?);;', feeder, re.S)
    nm = re.search(r'NAME="([^"]+)"', m.group(1)) if m else None
    names[t] = nm.group(1) if nm else None
    need(names[t] is not None, "script-name-missing-" + t)
blocks = dict((m.group(1), m.group(2)) for m in re.finditer(r'^resource "betteruptime_heartbeat" "([a-z0-9_]+)" \{\n(.*?)^\}', tf, re.S | re.M))
need(len(blocks) >= 1, "no-heartbeat-blocks-discovered")
want_res = {"luks-monitor-host-timer": "luks_monitor_host_timer", "claude-cost-capture": "claude_cost_capture"}
for t in tl:
    res = want_res[t]
    b = blocks.get(res, "")
    need(b != "", "tf-resource-missing-" + res)
    need(re.search(r'^\s*name\s*=\s*"' + re.escape(names[t] or "?") + '"', b, re.M) is not None, "tf-name-differs-from-script-" + res)
    need(re.search(r'^\s*period\s*=\s*3600\s*$', b, re.M) is not None, "tf-period-" + res)
    need(re.search(r'^\s*grace\s*=\s*7200\s*$', b, re.M) is not None, "tf-grace-" + res)
    need(re.search(r'^\s*paused\s*=\s*true\s*$', b, re.M) is not None, "tf-paused-" + res)
    need(re.search(r'ignore_changes\s*=\s*\[\s*paused\s*\]', b) is not None, "tf-ignore_changes-" + res)
    need("betterstack_paid_tier" in b, "tf-policy-gate-" + res)
    need(re.search(r'^\s*-target=betteruptime_heartbeat\.' + res + r'\b', apply_, re.M) is not None, "apply-target-missing-" + res)
need(len(re.findall(r'^\s*-target=logtail_exploration(_alert)?\.(claude_cost_capture_dark|luks_monitor_host_timer_dark)\b', apply_, re.M)) == 4, "apply-retained-destroy-targets-not-4")
need(re.search(r'^\s*workflowFile: "scheduled-deadman-heartbeat-feeder\.yml",', table, re.M) is not None, "watchdog-row-workflowFile-line")
row = re.search(r'\{\s*workflowFile: "scheduled-deadman-heartbeat-feeder\.yml",(.*?)\n  \},', table, re.S)
need(row is not None and 'monitorSlug: "scheduled-deadman-heartbeat-feeder"' in row.group(1) and re.search(r'intervalMinutes: 60,', row.group(1)) is not None, "watchdog-row-fields")
need(row is not None and "11631" in row.group(1) and "second clause" in row.group(1), "watchdog-row-eligibility")
m = re.search(r'resource "sentry_cron_monitor" "scheduled_deadman_heartbeat_feeder" \{(.*?)\n\}', mon, re.S)
need(m is not None, "sentry-monitor-missing")
mb = m.group(1) if m else ""
need('name                    = "scheduled-deadman-heartbeat-feeder"' in mb, "sentry-monitor-name")
need(re.search(r'crontab = "0 \* \* \* \*"', mb) is not None, "sentry-monitor-crontab")
need(re.search(r'checkin_margin_minutes\s*=\s*60\b', mb) is not None, "sentry-monitor-margin-60")
need(re.search(r'max_runtime_minutes\s*=\s*6\b', mb) is not None, "sentry-monitor-max_runtime-6")
need(re.search(r'^\s*scheduled_deadman_heartbeat_feeder\s*=\s*"[^"]*11631', alerts, re.M) is not None, "sentry-unrouted-label")
need("sentry_cron_monitor.scheduled_deadman_heartbeat_feeder.id" not in re.sub(r"(?s)locals \{.*?\n\}\n", "", alerts, count=1), "sentry-monitor-routed-prematurely")
print("\n".join(bad))
PYW
}
cases=$((cases + 1))
_wire="$(wiring_violations "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF" 2>&1)"
if [[ -z "$_wire" ]]; then pass "wiring: script names = Terraform names/period/grace/paused/ignore_changes = apply targets; watchdog row; Sentry monitor + unrouted label"
else fail "wiring violations: $(paste -sd, - <<<"$_wire")"; fi
cases=$((cases + 1))
_man="$("$PY" -I - "$MANIFEST_TS" "$EXPECT_TARGETS" <<'PYM'
import re, sys
src = open(sys.argv[1]).read()
bad = []
for res in ("luks_monitor_host_timer", "claude_cost_capture"):
    m = re.search(r'\{\s*name: "' + res + r'",(.*?)\n  \},\n', src, re.S)
    if not m:
        bad.append("manifest-row-missing-" + res); continue
    b = m.group(1)
    if 'arming: "external-probe"' not in b: bad.append("manifest-arming-" + res)
    if "paused: true" not in b: bad.append("manifest-paused-" + res)
    if 'file: ".github/workflows/scheduled-deadman-heartbeat-feeder.yml"' not in b: bad.append("manifest-evidence-file-" + res)
    if 'pattern: "bash scripts/deadman-heartbeat-feeder.sh"' not in b: bad.append("manifest-evidence-pattern-" + res)
    if "arming_pending: { tracking_issue: 11631 }" not in b: bad.append("manifest-arming_pending-" + res)
print("\n".join(bad))
PYM
)"
if [[ -z "$_man" ]]; then pass "manifest: both rows are external-probe, paused, arming_pending, evidenced by the workflow and the feeder invocation"
else fail "manifest violations: $(paste -sd, - <<<"$_man")"; fi
if command -v bun >/dev/null 2>&1; then
  cases=$((cases + 1))
  _bm="$(cd "$REPO" && bun -e 'import { MANIFEST } from "./plugins/soleur/lib/heartbeat-manifest.ts"; const n = MANIFEST.filter((e) => ["luks_monitor_host_timer","claude_cost_capture"].includes(e.name)); console.log(n.length === 2 && n.every((e) => e.feeder && e.feeder.kind === "cron" && e.feeder.evidence.file.endsWith("scheduled-deadman-heartbeat-feeder.yml") && e.arming === "external-probe") ? "ok" : "bad");' 2>&1 | tail -1)"
  if [[ "$_bm" == ok ]]; then pass "manifest (imported at runtime via bun): both rows resolve with the cron feeder evidence"
  else fail "manifest runtime import did not resolve both rows: $_bm"; fi
fi

echo "== mutation battery: Guard 1 (the feeder never authorizes a beat without a qualifying row) =="
LAST_RC=0
run_case() { LAST_RC="$(run_feeder)"; }
verdict_holds() { [[ "$1" == "$LAST_RC" ]] && grep -qE "verdict=$2( |\$)" "$OUT"; }
MUT_TABLE="$WORK/mutations.tsv"; : > "$MUT_TABLE"
expect_red() { # <row> <name> <orig-rc> <orig-verdict> <mutant-rc> <mutant-verdict>
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if verdict_holds "$3" "$4"; then fail "mutation row $1 ($2) SURVIVED: still status $3 + verdict=$4"
  elif ! verdict_holds "$5" "$6"; then
    fail "mutation row $1 ($2) went red for another reason: status $LAST_RC verdicts [$seen], expected $5 + verdict=$6"
  else pass "mutation row $1 ($2) is RED as predicted: status $LAST_RC, verdicts [$seen]"; fi
}
static_red() { # <row> <mutant> <violation-name>
  cases=$((cases + 1))
  local v; v="$(static_violations "$2")"
  if grep -qxF "$3" <<<"$v"; then pass "mutation row $1 is RED in the static pins: $3"
  else fail "mutation row $1: expected static violation '$3', got [$(paste -sd, - <<<"$v")]"; fi
}
# Known-positive: the shipped feeder on a qualifying fixture HOLDS; known-negative: the same detector on a 28 h fixture does not.
reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx kp)"; C_BEATS=1; C_APIS=1; run_case
cases=$((cases + 1))
if verdict_holds 0 beat; then pass "runner known-positive: shipped feeder + 26 h fixture holds (beat)"; else fail "runner known-positive: got status $LAST_RC"; fi
reset_case; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx kn)"; run_case
cases=$((cases + 1))
if ! verdict_holds 0 beat; then pass "runner known-negative: a 28 h fixture does not read as a beat"; else fail "runner known-negative: the detector reports a beat on a 28 h fixture"; fi

# G1-1: drop the lower dt bound from the ARCHIVE arm only (the hot arm keeps it)
land g1-1 "WHERE _row_type = 1 AND '\"\$win\"" "WHERE _row_type = 1 AND dt <= now() + INTERVAL 300 SECOND'"; _m1="$M"
reset_case; C_SRC="$_m1"; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx g11)"; C_BEATS=1; C_APIS=1
expect_red G1-1 "archive arm loses its lower dt bound: the 28 h row beats" 3 no_qualifying_row 0 beat
cases=$((cases + 1))
reset_case; C_SRC="$_m1"; C_ROWS="$(printf '' | fx g11b)"; _g="$(run_feeder)"
_s11="$(head -1 "$SQLLOG")"
if [[ "$(grep -oF 'dt > now() - INTERVAL 97200 SECOND' <<<"$_s11" | wc -l)" == 1 && "$_s11" != "$(expect_sql "$T_LUKS" "${E_PRED[$T_LUKS]}")" ]]; then pass "G1-1: the frozen-SQL pin ALSO catches it (the sent SQL no longer equals the frozen shape; one window bound remains)"
else fail "G1-1: the SQL-text pin did not notice the dropped archive bound"; fi
# G1-2: drop the _row_type = 1 filter
land g1-2 'WHERE _row_type = 1 AND ' 'WHERE '; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" 0 | fx g12)"; C_BEATS=1; C_APIS=1
expect_red G1-2 "_row_type filter dropped: a non-primary archive row beats" 3 no_qualifying_row 0 beat
# G1-3a: drop the s3Cluster arm entirely; G1-3b: --no-archive
land g1-3a "  SQL+=' UNION ALL '
  SQL+='SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND '\"\$win\"
" ''; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g13a)"; C_BEATS=1; C_APIS=1
expect_red G1-3a "the s3Cluster arm is dropped: an archive-only row withholds" 0 beat 3 no_qualifying_row
land g1-3b '"$QUERY" "$SQL"' '"$QUERY" --no-archive "$SQL"'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g13b)"; C_BEATS=1; C_APIS=1
expect_red G1-3b "--no-archive handed to the helper" 0 beat 3 query_failed
static_red G1-3b "$_m" no-archive-flag
# G1-4: n == 0 falls through to the beat
land g1-4 'if [[ "$QN" == "0" ]]; then' 'if false; then'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(printf '' | fx g14)"; C_BEATS=1; C_APIS=1; C_Q=1
expect_red G1-4 "an empty window falls through to the beat" 3 no_qualifying_row 0 beat
reset_case; C_SRC="$_m"; C_STUB="okstr"; C_ROWS="$(printf '' | fx g14s)"; C_BEATS=1; C_APIS=1; C_Q=1
expect_red G1-4s "the same fall-through on the quoted-string n:\"0\" answer" 3 no_qualifying_row 0 beat
# G1-5: a second curl call site, and a /fail suffix
land g1-5a "printf 'url = \"%s\"\n' \"\$HB_URL\"" "printf 'url = \"%s/fail\"\n' \"\$HB_URL\""; _m="$M"
static_red G1-5a "$_m" slash-fail-literal
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g15a)"; C_BEATS=1; C_APIS=1
cases=$((cases + 1)); _rc="$(run_feeder)"
if [[ "$_rc" != 0 ]] && [[ "$(count_calls '^refused beat-stdin$')" == 1 ]]; then pass "G1-5a: at run time the stub refuses a beat to a /fail URL (rc $_rc)"
else fail "G1-5a: a /fail beat was not refused at run time (rc $_rc)"; fi
land g1-5b '  HB_PAUSED="$(printf '"'%s'"' "$sel" | cut -f2)"' '  HB_PAUSED="$(printf '"'%s'"' "$sel" | cut -f2)"; printf '"'url = \"x\"\\n'"' | curl --disable --noproxy '"'*'"' -fsS --max-time 15 --connect-timeout 10 --config - 2>/dev/null'; _m="$M"
static_red G1-5b "$_m" curl-invocation-count
# G1-6: the EXIT trap lets an unknown status exit 0
land g1-6 '    0) if [ "$DECIDED" = 1 ]; then exit 0; fi ;;' '    0) exit 0 ;;'; _m6="$M"
"$PY" -I - "$_m6" "$M_FALL" "$WORK/mut/g16combo.sh" <<'PYC'
import sys
m6 = open(sys.argv[1]).read()
open(sys.argv[3], "w").write(m6.replace("  beat_once\n", "  DECIDED=0; exit 0\n", 1))
PYC
chmod +x "$WORK/mut/g16combo.sh"
reset_case; C_SRC="$WORK/mut/g16combo.sh"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g16)"; C_APIS=1; run_case
cases=$((cases + 1))
if [[ "$LAST_RC" == 0 ]] && ! grep -q 'trap_remapped' "$OUT"; then pass "mutation row G1-6 is RED: with the trap hole an undecided fall-off exits 0 (the trap_remapped fixture above catches it)"
else fail "mutation row G1-6: expected an unexplained 0, got $LAST_RC [$(markers_of)]"; fi
# G1-7: skip the paused check
land g1-7 'if [[ "$HB_PAUSED" == "true" ]]; then' 'if false; then'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g17)"; C_API="$(hb_json "${E_NAME[$T_LUKS]}" true "$HB_URL" | fx g17api)"; C_BEATS=1; C_APIS=1
expect_red G1-7 "paused ignored: the beat is sent to a paused heartbeat" 0 qualifying_row_heartbeat_paused 0 beat
cases=$((cases + 1))
if [[ "$(count_calls '^beat$')" == 1 ]]; then pass "G1-7: the stub observed the beat to the paused heartbeat"; else fail "G1-7: no beat observed"; fi
# G1-8: anti-vacuity — an empty target table is a failure of the discovery, not a pass
land g1-8 "TARGETS=\"$T_LUKS $T_COST\"" 'TARGETS=""'; _m="$M"
cases=$((cases + 1))
if [[ -z "$(discover_targets "$_m")" ]]; then pass "mutation row G1-8 is RED: an empty target table discovers 0 targets (the anti-vacuity case above would fail)"
else fail "mutation row G1-8: the emptied table still discovered targets"; fi
# G1-9: the unknown-target arm falls through to the first target
land g1-9 '    *) return 1 ;;' "    *) select_target $T_LUKS ;;"; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="bogus"; C_NAME_OVERRIDE="${E_NAME[$T_LUKS]}"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g19)"; C_BEATS=1; C_APIS=1
expect_red G1-9 "unknown target falls through to the first target" 64 usage 0 beat
# G1-10: restore the sibling's BEAT_MODE//fail branch and a fail_beat verdict
land g1-10 'beat_once() {' 'beat_once() { if [[ "${BEAT_MODE:-ok}" == "fail" ]]; then HB_URL="${HB_URL%/}/fail"; fmarker "fail_beat"; fi'; _m="$M"
static_red G1-10 "$_m" sibling-fail-arm
static_red G1-10b "$_m" slash-fail-literal
# G1-11: the answer contract mis-graded (a zero count treated as present via arithmetic fall-through)
land g1-11 '! "$nraw" =~ ^[0-9]{1,18}$' '! "$nraw" =~ ^[0-9a-z]{1,18}$'; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="nonnumeric"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx g111)"; C_BEATS=1; C_APIS=1
expect_red G1-11 "a non-numeric n is accepted as a count" 3 query_failed 0 beat
# T1: the TLS/CA scrub removed (the stub curl refuses a call that still sees it)
land t1 'unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_TLSENV=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx t1)"; C_BEATS=0; C_APIS=1
expect_red T1 "TLS/CA environment scrub removed" 0 beat 4 beat_failed
# T2: BS_TABLE left in the helper's environment
land t2 'unset BS_TABLE BS_TABLE_S3;' ':;'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx t2)"; C_BEATS=1; C_APIS=1
expect_red T2 "caller's BS_TABLE not scrubbed before the helper" 0 beat 3 query_failed

echo "== mutation battery: Guard 2 (predicate fidelity) =="
G2_LUKS_NEG_UNIT="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor __none__)" | fx g2u)"
land g2-1 "JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK" "JSONExtractString(raw, 'message') LIKE '%OK"; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$G2_LUKS_NEG_UNIT"; C_BEATS=1; C_APIS=1
expect_red G2-1 "the _SYSTEMD_UNIT conjunct dropped: a verify-job row beats" 3 no_qualifying_row 0 beat
land g2-2 "LUKS-backed%' AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'" "LUKS-backed%'"; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor luks-monitor.service "$OK_MSG" soleur-web-2)" | fx g2h)"; C_BEATS=1; C_APIS=1
expect_red G2-2 "the host_name conjunct dropped: a web-2 row beats" 3 no_qualifying_row 0 beat
land g2-3a "LIKE '%OK: /mnt/data is LUKS-backed%'" "LIKE '%OK: /mnt/data is LUKS backed%'"; _m="$M"
cases=$((cases + 1))
if guard2_checks "$_m" "$EMIT_LUKS" 2>&1 | grep -q '^FAIL luks: the LIKE needle equals'; then pass "mutation row G2-3a is RED: a reworded needle in the feeder only fails the emitter-parity pin"
else fail "mutation row G2-3a: emitter parity did not notice the reworded needle"; fi
sed 's/OK: \/mnt\/data is LUKS-backed/OK: \/mnt\/data is encrypted/' "$EMIT_LUKS" > "$WORK/mut/luks-monitor.reworded.sh"
cases=$((cases + 1))
if ! cmp -s "$EMIT_LUKS" "$WORK/mut/luks-monitor.reworded.sh" && guard2_checks "$FEEDER_SRC" "$WORK/mut/luks-monitor.reworded.sh" 2>&1 | grep -q '^FAIL luks: the LIKE needle equals'; then
  pass "mutation row G2-3b is RED (landed): a reworded OK line in luks-monitor.sh only fails the emitter-parity pin (both directions covered)"
else fail "mutation row G2-3b: emitter parity did not notice (or the edit did not land)"; fi
land g2-4 "= 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK" "= 'luks-monitor' OR JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK"; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw other-tag luks-monitor.service)" | fx g24)"; C_BEATS=1; C_APIS=1
expect_red G2-4 "the unit conjunct joined with OR: a wrong-identifier row beats" 3 no_qualifying_row 0 beat
land g2-5 " AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')))" " AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')) OR raw LIKE '%cost%')"; _m="$M"
cases=$((cases + 1))
if guard2_checks "$_m" "$EMIT_LUKS" 2>&1 | grep -q '^FAIL cost: exactly one OR'; then pass "mutation row G2-5 is RED: a second OR arm on the cost predicate fails the exactly-two-arms pin"
else fail "mutation row G2-5: the second OR arm was not noticed"; fi
land g2-6a " AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'" ''; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="$T_COST"; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw session:abc123)" | fx g26a)"; C_BEATS=1; C_APIS=1
expect_red G2-6a "source LIKE 'cron:%' dropped: a founder BYOK row beats" 3 no_qualifying_row 0 beat
land g2-6b "raw LIKE '%\"SOLEUR_CLAUDE_COST\":true%' AND " ''; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="$T_COST"; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x 3.1 claude-cost SOLEUR_CLAUDE_COST_DAILY)" | fx g26b)"; C_BEATS=1; C_APIS=1
expect_red G2-6b "the SOLEUR_CLAUDE_COST key match dropped: an org-total _DAILY row beats" 3 no_qualifying_row 0 beat
land g2-6c " AND JSONExtract(raw, 'message', 'cost_usd', 'Nullable(Float64)') IS NOT NULL" ''; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="$T_COST"; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw cron:x null)" | fx g26c)"; C_BEATS=1; C_APIS=1
expect_red G2-6c "the non-null cost_usd conjunct dropped: a null-cost marker beats" 3 no_qualifying_row 0 beat
land g2-7 'def_pred LUKS_PRED' 'def_pred LUKS_PRED_RENAMED'; _m="$M"
cases=$((cases + 1))
if guard2_checks "$_m" "$EMIT_LUKS" 2>&1 | grep -q '^FAIL both predicates are extractable'; then pass "mutation row G2-7 is RED: a renamed predicate table key trips the anti-vacuity extraction pin"
else fail "mutation row G2-7: the extractor finding nothing was not noticed"; fi
echo "-- Guard 2 harness rows: the fixtures can fail, and non-canonical inputs stay green --"
reset_case; C_EVAL="$WORK/eval-allrows.py"; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw luks-monitor __none__ "$FAIL_MSG" soleur-web-2)" | fx hr1)"; C_BEATS=1; C_APIS=1; run_case
cases=$((cases + 1))
if verdict_holds 0 beat; then pass "harness row (a): an evaluator that qualifies every row flips the 28 h / web-2 / verify-job / FAIL fixtures to a beat (the fixtures CAN fail)"
else fail "harness row (a): the all-rows evaluator did not flip the negative fixture (rc $LAST_RC)"; fi
for _hn in "28h:$(row s3 "$((28 * H))" "$(luks_raw)")" "web2:$(row s3 "$((26 * H))" "$(luks_raw luks-monitor luks-monitor.service "$OK_MSG" soleur-web-2)")" "verify-job:$(row s3 "$((26 * H))" "$(luks_raw luks-monitor __none__)")"; do
  reset_case; C_EVAL="$WORK/eval-allrows.py"; C_ROWS="$(printf '%s\n' "${_hn#*:}" | fx "hra-${_hn%%:*}")"; C_BEATS=1; C_APIS=1; run_case
  cases=$((cases + 1))
  if verdict_holds 0 beat; then pass "harness row (a, ${_hn%%:*}): the all-rows evaluator flips this negative fixture to a beat (it CAN fail)"
  else fail "harness row (a, ${_hn%%:*}): the all-rows evaluator did not flip the fixture (rc $LAST_RC)"; fi
done
reset_case; C_EVAL="$WORK/eval-likeall.py"; C_ROWS="$(row s3 "$((2 * H))" "$(luks_raw luks-monitor luks-monitor.service "$FAIL_MSG")" | fx hr2)"; C_BEATS=1; C_APIS=1; run_case
cases=$((cases + 1))
if verdict_holds 0 beat; then pass "harness row (b): an evaluator whose LIKE is always true turns the FAIL-row fixture into a beat"
else fail "harness row (b): the LIKE-all evaluator did not flip the FAIL-row fixture (rc $LAST_RC)"; fi
reset_case; C_TARGET="$T_COST"; C_EVAL="$WORK/eval-likeall.py"; C_ROWS="$(row s3 "$((2 * H))" "$(cost_raw session:abc123)" | fx hr3)"; C_BEATS=1; C_APIS=1; run_case
cases=$((cases + 1))
if verdict_holds 0 beat; then pass "harness row (b2): the same evaluator turns the BYOK fixture into a beat"
else fail "harness row (b2): the LIKE-all evaluator did not flip the BYOK fixture"; fi
"$PY" -I - "$FEEDER_SRC" "$WORK/mut/reordered.sh" <<'PYR'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(def_pred LUKS_PRED <<'EOF'\n)(.*?)(\nEOF)", s, re.S)
parts = m.group(2).split(" AND ")
assert len(parts) == 4
new = " AND ".join([parts[3], parts[2], parts[1], parts[0]])
open(sys.argv[2], "w").write(s[:m.start(2)] + new + s[m.end(2):])
PYR
chmod +x "$WORK/mut/reordered.sh"
cases=$((cases + 1)); if ! cmp -s "$FEEDER_SRC" "$WORK/mut/reordered.sh"; then pass "must-PASS input: the reordered-conjunct feeder landed"; else fail "must-PASS input did not land"; fi
reset_case; C_SRC="$WORK/mut/reordered.sh"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx hr4)"; C_BEATS=1; C_APIS=1
expect "must-PASS (non-canonical): the same four conjuncts in reverse order still beat a 26 h row" 0 beat
reset_case; C_SRC="$WORK/mut/reordered.sh"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw luks-monitor __none__)" | fx hr5)"; C_Q=3
expect "must-PASS (non-canonical): the reordered feeder still withholds the verify-job row" 3 no_qualifying_row
reset_case; C_TARGET="$T_COST"; C_ROWS="$(row s3 "$((20 * H))" "$(probe_raw anthropic-credit-exhausted)" | fx hr6)"; C_BEATS=1; C_APIS=1
expect "must-PASS (non-canonical): a 20 h old cost row with the credit-probe arm ONLY still beats" 0 beat

echo "== mutation battery: Guard 4 (wiring parity) =="
w_mut() { # <row> <file-var-name> <old> <new> -> sets WM (path) or fails
  local srcvar="$2" src out="$WORK/mut/$1.wire"
  src="${!srcvar}"
  cases=$((cases + 1))
  if "$PY" -I - "$src" "$out" "$3" "$4" <<'PYX'
import sys
s = open(sys.argv[1]).read()
if s.count(sys.argv[3]) != 1:
    sys.exit(3)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PYX
  then pass "mutation row $1 landed"; WM="$out"; else fail "mutation row $1 did NOT land"; WM="$src"; fi
}
wire_red() { # <row> <violation-substring> <uptime> <apply> <table> <feeder> <monitors>
  cases=$((cases + 1))
  local v; v="$(wiring_violations "$3" "$4" "$5" "$6" "$7" 2>&1)"
  if grep -qF -- "$2" <<<"$v"; then pass "mutation row $1 is RED in the wiring pins: $2"
  else fail "mutation row $1: expected wiring violation '$2', got [$(paste -sd, - <<<"$v")]"; fi
}
# block-scoped mutation: replace <old> by <new> inside the Terraform resource block <resource> only (exactly once there)
w_block() { # <row> <file-var> <resource> <old-regex-literal> <new>
  local srcvar="$2" src out="$WORK/mut/$1.wire"
  src="${!srcvar}"
  cases=$((cases + 1))
  if "$PY" -I - "$src" "$out" "$3" "$4" "$5" <<'PYX'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'(resource "betteruptime_heartbeat" "' + re.escape(sys.argv[3]) + r'" \{\n)(.*?)(^\})', s, re.S | re.M)
if not m or m.group(2).count(sys.argv[4]) != 1:
    sys.exit(3)
body = m.group(2).replace(sys.argv[4], sys.argv[5])
open(sys.argv[2], "w").write(s[:m.start(2)] + body + s[m.end(2):])
PYX
  then pass "mutation row $1 landed"; WM="$out"; else fail "mutation row $1 did NOT land"; WM="$src"; fi
}
w_block g4-1 UPTIME_TF claude_cost_capture 'name   = "soleur-claude-cost-capture-prd"' 'name   = "soleur-claude-cost-capture-renamed"'
wire_red G4-1 'tf-name-differs-from-script-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4-2a UPTIME_TF claude_cost_capture 'grace  = 7200' 'grace  = 3600'
wire_red G4-2a 'tf-grace-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4-2b UPTIME_TF claude_cost_capture 'ignore_changes = [paused]' 'ignore_changes = [period]'
wire_red G4-2b 'tf-ignore_changes-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4-2c UPTIME_TF claude_cost_capture 'paused    = true' 'paused    = false'
wire_red G4-2c 'tf-paused-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4-2d UPTIME_TF claude_cost_capture 'period = 3600' 'period = 1800'
wire_red G4-2d 'tf-period-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
_tg="$(grep -nE '^[[:space:]]*-target=betteruptime_heartbeat\.claude_cost_capture' "$APPLY_WF" | head -1 | cut -d: -f2-)"
w_mut g4-4 APPLY_WF "$_tg" "${_tg/claude_cost_capture/claude_cost_capture_x}"
wire_red G4-4 'apply-target-missing-claude_cost_capture' "$UPTIME_TF" "$WM" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_mut g4-5 TABLE_TS 'workflowFile: "scheduled-deadman-heartbeat-feeder.yml",' '// workflowFile: "scheduled-deadman-heartbeat-feeder.yml",'
wire_red G4-5 'watchdog-row-workflowFile-line' "$UPTIME_TF" "$APPLY_WF" "$WM" "$FEEDER_SRC" "$MONITORS_TF"
cases=$((cases + 1))
_none="$(printf 'resource "x" "y" {\n}\n' > "$WORK/mut/empty.tf"; wiring_violations "$WORK/mut/empty.tf" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF" 2>&1)"
if grep -qF 'no-heartbeat-blocks-discovered' <<<"$_none"; then pass "mutation row G4-6 is RED: a Terraform file with no heartbeat blocks trips the anti-vacuity pin"
else fail "mutation row G4-6: discovery of zero heartbeats was not noticed"; fi
# G4-3: drop one target from the workflow loop; G4-3 harness row: delete the loop assertion -> the mutation goes GREEN
"$PY" -I - "$WORKFLOW" "$WORK/mut/wf-droploop.yml" <<'PYL'
import sys
s = open(sys.argv[1]).read()
old = "for t in luks-monitor-host-timer claude-cost-capture; do"
assert s.count(old) == 1
open(sys.argv[2], "w").write(s.replace(old, "for t in luks-monitor-host-timer; do"))
PYL
cases=$((cases + 1))
if ! cmp -s "$WORKFLOW" "$WORK/mut/wf-droploop.yml" && workflow_violations "$WORK/mut/wf-droploop.yml" 2>&1 | grep -qx 'loop-targets-differ-from-script-table'; then pass "mutation row G4-3 is RED: dropping a target from the workflow loop fails the loop-vs-script-table pin"
else fail "mutation row G4-3: the dropped loop target was not noticed (or did not land)"; fi
"$PY" -I - "$WORKFLOW" "$WORK/mut/wf-reorder.yml" <<'PYL'
import sys
s = open(sys.argv[1]).read()
old = "for t in luks-monitor-host-timer claude-cost-capture; do"
open(sys.argv[2], "w").write(s.replace(old, "for t in claude-cost-capture luks-monitor-host-timer; do"))
PYL
cases=$((cases + 1))
if ! cmp -s "$WORKFLOW" "$WORK/mut/wf-reorder.yml" && ! workflow_violations "$WORK/mut/wf-reorder.yml" 2>&1 | grep -q 'loop-targets'; then pass "must-PASS (non-canonical): reordering the loop targets stays green"
else fail "must-PASS: reordering the loop targets went red (or did not land)"; fi
# harness row: with the loop assertion deleted from the checker the dropped-target mutation goes GREEN (the assertion is what catches it)
cases=$((cases + 1))
_nl="$(workflow_violations "$WORK/mut/wf-droploop.yml" 2>&1 | grep -vx 'loop-targets-differ-from-script-table' || true)"
if [[ -z "$_nl" ]]; then pass "harness row (G4-3): without the loop-vs-script assertion the dropped-target mutant reports nothing else (that assertion is the one catching it)"
else fail "harness row (G4-3): the dropped-target mutant is caught by another pin too: $_nl"; fi

echo
echo "== measured mutation verdicts (row, edit, verdicts seen, status) =="
sed 's/^/  /' "$MUT_TABLE"

# ── conservation and the floors ───────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases, $beat_asserts beat-call assertions ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# HARD-CODED floors: a runtime-derived one falls when a case is deleted.
MIN_PASSES=260
MIN_BEAT_ASSERTS=100
if (( passes < MIN_PASSES )); then
  printf 'FATAL: only %s passes, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
if (( beat_asserts < MIN_BEAT_ASSERTS )); then
  printf 'FATAL: only %s beat-call assertions, below the floor of %s.\n' "$beat_asserts" "$MIN_BEAT_ASSERTS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
