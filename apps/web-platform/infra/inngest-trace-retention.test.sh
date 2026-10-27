#!/usr/bin/env bash
# Behavioral proof for the 7-day status-gated Inngest trace retention job.
# External binaries: bash and python3. Timestamps come from python, not date(1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNNER="${ROOT}/apps/web-platform/infra/inngest-trace-retention.sh"
SQL_DIR="${ROOT}/apps/web-platform/infra"
PG_SQL="${SQL_DIR}/inngest-trace-retention.sql"
SQLITE_SQL="${SQL_DIR}/inngest-trace-retention.sqlite.sql"
FAKE_URI='postgres://retention:secret@127.0.0.1:9/inngest'
SENTINEL='SENTINEL_EVENT_PAYLOAD_9f3a'

PASSES=0
RET_RC=0
RET_URI=""
CLEANUPS=()

# Byte-for-byte copy of plugins/soleur/test/test-helpers.sh (the canonical body).
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

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASSES=$((PASSES + 1))
  printf 'ok %s\n' "$*"
}

cleanup() {
  local d
  for d in "${CLEANUPS[@]}"; do
    assert_fixture_dir "$d"
    rm -rf "$d"
  done
}
trap cleanup EXIT

new_fix() {
  local d
  d="$(mktemp -d)"
  assert_fixture_dir "$d"
  CLEANUPS+=("$d")
  printf '%s\n' "$d"
}

dump() {
  printf '%s\n' "---- $1 ----" >&2
  cat "$1" >&2 || true
}

require_out() {
  local file="$1" needle="$2" label="$3"
  if ! grep -F -q -- "$needle" "$file"; then
    dump "$file"
    die "${label}: missing [${needle}]"
  fi
  pass "$label"
}

forbid_out() {
  local file="$1" needle="$2" label="$3"
  if grep -F -q -- "$needle" "$file"; then
    dump "$file"
    die "${label}: found forbidden [${needle}]"
  fi
  pass "$label"
}

# The battery uses the guard's exit code. A zero exit on a known-bad tree is a failure.
require_red() {
  local label="$1" outfile="$2"
  if [[ "$RET_RC" -eq 0 ]]; then
    dump "$outfile"
    die "${label}: guard exit 0, want non-zero"
  fi
  pass "$label"
}

require_green() {
  local label="$1" outfile="$2"
  if [[ "$RET_RC" -ne 0 ]]; then
    dump "$outfile"
    die "${label}: exit ${RET_RC}, want 0"
  fi
  pass "$label"
}

# Every retention invocation goes through here. --ensure-indexes is never a test path.
run_retention() {
  local outfile="$1"
  assert_fixture_dir "$outfile"
  shift
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--ensure-indexes" ]]; then
      die "test invoked --ensure-indexes"
    fi
  done
  set +e
  if [[ -n "$RET_URI" ]]; then
    INNGEST_POSTGRES_URI="$RET_URI" bash "$RUNNER" "$@" >"$outfile" 2>&1
  else
    env -u INNGEST_POSTGRES_URI bash "$RUNNER" "$@" >"$outfile" 2>&1
  fi
  RET_RC=$?
  set -e
}

run_guard() {
  local dir="$1" outfile="$2"
  assert_fixture_dir "$outfile"
  set +e
  env -u INNGEST_POSTGRES_URI bash "$RUNNER" --guard "$dir" >"$outfile" 2>&1
  RET_RC=$?
  set -e
}

if [[ ! -f "$RUNNER" ]]; then
  die "runner missing at apps/web-platform/infra/inngest-trace-retention.sh"
fi

if ! grep -F -q 'soleur_trace_runs_status_ended_at' "$RUNNER"; then
  die "runner missing soleur_trace_runs_status_ended_at"
fi
pass "source names soleur_trace_runs_status_ended_at"
if ! grep -F -q 'soleur_function_finishes_created_at' "$RUNNER"; then
  die "runner missing soleur_function_finishes_created_at"
fi
pass "source names soleur_function_finishes_created_at"
if ! grep -F -q 'soleur_traces_run_id' "$RUNNER"; then
  die "runner missing soleur_traces_run_id"
fi
pass "source names soleur_traces_run_id"
if ! grep -F -q 'soleur_events_received_at' "$RUNNER"; then
  die "runner missing soleur_events_received_at"
fi
pass "source names soleur_events_received_at"
if ! grep -F -q 'CREATE INDEX CONCURRENTLY IF NOT EXISTS' "$RUNNER"; then
  die "runner missing CREATE INDEX CONCURRENTLY IF NOT EXISTS"
fi
pass "source creates indexes concurrently"
if grep -F -q 'flock' "$RUNNER"; then
  die "runner must not call flock"
fi
pass "runner does not call flock"
if grep -F -q 'VACUUM' "$RUNNER" "$PG_SQL" "$SQLITE_SQL"; then
  die "VACUUM token present in runner or SQL"
fi
pass "no VACUUM token"

FIX="$(new_fix)"
OUT="${FIX}/out"

# --- xtrace refusal prints neither the URI nor the password ---
set +e
INNGEST_POSTGRES_URI="$FAKE_URI" bash -x "$RUNNER" >"${FIX}/xtrace.out" 2>&1
XRC=$?
set -e
if [[ "$XRC" -ne 78 ]]; then
  dump "${FIX}/xtrace.out"
  die "xtrace exit ${XRC}, want 78"
fi
pass "xtrace exits 78"
forbid_out "${FIX}/xtrace.out" 'secret' "xtrace hides password"
forbid_out "${FIX}/xtrace.out" 'postgres://' "xtrace hides uri"

# --- guard: real SQL directory, then the mutation rows ---
run_guard "$SQL_DIR" "$OUT"
require_green "guard accepts the shipped SQL" "$OUT"

mutate() {
  local mode="$1" dest="$2"
  python3 - "$mode" "$PG_SQL" "$SQLITE_SQL" "$dest" <<'PY'
import pathlib, re, shutil, sys
mode, pg_path, sqlite_path, dest = sys.argv[1:]
dest = pathlib.Path(dest)
pg = pathlib.Path(pg_path).read_text()
sqlite = pathlib.Path(sqlite_path).read_text()

def split_sql(text):
    return re.split(r"(?m)^-- soleur:statement\s*$", text)

def render(parts):
    out = [parts[0]]
    for body in parts[1:]:
        out.append("-- soleur:statement")
        out.append(body)
    return "".join(out)

def find_body(parts, table):
    pat = re.compile(r"DELETE FROM %s\b" % table)
    hits = [i for i, b in enumerate(parts) if i > 0 and pat.search(b)]
    if len(hits) != 1:
        raise SystemExit("expected one DELETE FROM %s, found %s" % (table, hits))
    return hits[0]

if mode == "drop-anchor-status":
    parts = split_sql(pg)
    idx = find_body(parts, "trace_runs")
    needle = "status IN (50, 300, 400, 500, 600)"
    if needle not in parts[idx]:
        raise SystemExit("anchor statement has no status set to drop")
    parts[idx] = parts[idx].replace(needle, "status IN (300)", 1)
    (dest / "inngest-trace-retention.sql").write_text(render(parts))
    (dest / "inngest-trace-retention.sqlite.sql").write_text(sqlite)
elif mode == "drop-sqlite-not-exists":
    parts = split_sql(sqlite)
    idx = find_body(parts, "events")
    if "NOT EXISTS" not in parts[idx]:
        raise SystemExit("sqlite events delete has no NOT EXISTS")
    parts[idx] = parts[idx].replace("NOT EXISTS", "/* removed-unfinished */", 1)
    (dest / "inngest-trace-retention.sql").write_text(pg)
    (dest / "inngest-trace-retention.sqlite.sql").write_text(render(parts))
elif mode == "reorder-anchor":
    parts = split_sql(pg)
    anchor = find_body(parts, "trace_runs")
    spans = find_body(parts, "spans")
    if anchor < spans:
        raise SystemExit("anchor is already before spans")
    body = parts.pop(anchor)
    parts.insert(spans, body)
    (dest / "inngest-trace-retention.sql").write_text(render(parts))
    (dest / "inngest-trace-retention.sqlite.sql").write_text(sqlite)
elif mode == "drop-events-not-exists":
    parts = split_sql(pg)
    idx = find_body(parts, "events")
    updated, n = re.subn(
        r"\s+AND NOT EXISTS\s*\(.*?\bff\.run_id IS NULL\s*\)",
        "",
        parts[idx],
        count=1,
        flags=re.S,
    )
    if n != 1 or "NOT EXISTS" in updated or "received_at" not in updated:
        raise SystemExit("events mutation did not keep received_at and drop NOT EXISTS")
    parts[idx] = updated
    (dest / "inngest-trace-retention.sql").write_text(render(parts))
    (dest / "inngest-trace-retention.sqlite.sql").write_text(sqlite)
elif mode == "widen-status":
    parts = split_sql(pg)
    idx = find_body(parts, "spans")
    needle = "status IN (50, 300, 400, 500, 600)"
    if needle not in parts[idx]:
        raise SystemExit("spans statement has no status set")
    parts[idx] = parts[idx].replace(needle, needle + " OR tr.status IN (100, 200)", 1)
    (dest / "inngest-trace-retention.sql").write_text(render(parts))
    (dest / "inngest-trace-retention.sqlite.sql").write_text(sqlite)
elif mode == "third-file":
    (dest / "inngest-trace-retention.sql").write_text(pg)
    (dest / "inngest-trace-retention.sqlite.sql").write_text(sqlite)
    extra = pg + (
        "\n-- disclosure: finished trace and log history in the dedicated Postgres "
        "event store is removed after 7 days by a status-gated job\n"
    )
    (dest / "inngest-trace-retention-extra.sql").write_text(extra)
else:
    raise SystemExit("unknown mutation %s" % mode)
PY
}

row_red() {
  local mode="$1" label="$2" needle="${3-}"
  local dir
  dir="$(new_fix)"
  mutate "$mode" "$dir"
  run_guard "$dir" "$OUT"
  require_red "$label" "$OUT"
  if [[ -n "$needle" ]]; then
    require_out "$OUT" "$needle" "${label} message"
  fi
}

row_red drop-anchor-status "row1 anchor status set dropped is red"
EMPTY="$(new_fix)"
run_guard "$EMPTY" "$OUT"
require_red "row2 empty directory is red" "$OUT"
require_out "$OUT" "guard checked 0 files" "row2 names the empty glob"
row_red drop-sqlite-not-exists "row3 sqlite events unfinished-run guard dropped is red"
row_red reorder-anchor "row4 trace_runs deleted before spans is red"
row_red drop-events-not-exists "row5 events age predicate without NOT EXISTS is red"
row_red widen-status "row6 in-flight status widens the predicate" "in-flight status"
THIRD="$(new_fix)"
mutate third-file "$THIRD"
run_guard "$THIRD" "$OUT"
require_green "row7 third file with the same predicates passes" "$OUT"

# --- sqlite fixture harness ---
HARNESS="${FIX}/harness.py"
cat >"$HARNESS" <<'PY'
import sqlite3, sys, time
from datetime import datetime, timezone

SENTINEL = "SENTINEL_EVENT_PAYLOAD_9f3a"

def tid(tag):
    s = (tag + ("0" * 26))[:26]
    if len(s) != 26:
        raise SystemExit("id %s is not 26 chars" % tag)
    return s

def ts_days_ago(days):
    return datetime.fromtimestamp(time.time() - days * 86400, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

OLD_MS = int(time.time() * 1000) - 8 * 86400000
RECENT_MS = int(time.time() * 1000) - 1 * 86400000
OLD_TS = ts_days_ago(8)
RECENT_TS = ts_days_ago(1)

RUN_OLD = tid("olddone")
RUN_50 = tid("stat50")
RUN_RECENT = tid("recent")
RUN_LIVE = tid("inflight")
FR_OLD = b"fr-olddone"
FR_RECENT = b"fr-recent"
FR_LIVE = b"fr-inflight"
EV_OLD = b"ev-olddone"
EV_RECENT = b"ev-recent"
EV_LIVE = b"ev-inflight"
EV_ORPHAN = b"ev-orphan"

SCHEMA = """
CREATE TABLE trace_runs (
  run_id CHAR(26) PRIMARY KEY,
  ended_at INT NOT NULL,
  status INT NOT NULL
);
CREATE TABLE spans (
  span_id TEXT NOT NULL,
  trace_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  PRIMARY KEY (trace_id, span_id)
);
CREATE TABLE traces (
  trace_id VARCHAR NOT NULL,
  span_id VARCHAR NOT NULL,
  run_id CHAR(26)
);
CREATE TABLE event_batches (
  id CHAR(26) PRIMARY KEY,
  run_id CHAR(26) NOT NULL
);
CREATE TABLE function_finishes (
  run_id BLOB,
  status VARCHAR NOT NULL,
  created_at TIMESTAMP NOT NULL
);
CREATE TABLE function_runs (
  run_id BLOB NOT NULL,
  event_id BLOB NOT NULL
);
CREATE TABLE history (
  run_id BLOB NOT NULL,
  event_id BLOB NOT NULL
);
CREATE TABLE events (
  internal_id BLOB,
  received_at TIMESTAMP NOT NULL,
  event_data VARCHAR NOT NULL
);
CREATE TABLE apps (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE functions (id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE worker_connections (id TEXT PRIMARY KEY);
CREATE TABLE migrations (id INTEGER PRIMARY KEY, version TEXT NOT NULL);
CREATE TABLE goose_db_version (id INTEGER PRIMARY KEY, version_id INTEGER NOT NULL);
CREATE TABLE queue_snapshot_chunks (id TEXT PRIMARY KEY);
CREATE TRIGGER keep_trace_children BEFORE DELETE ON trace_runs
WHEN EXISTS (SELECT 1 FROM spans WHERE run_id = OLD.run_id)
  OR EXISTS (SELECT 1 FROM traces WHERE run_id = OLD.run_id)
  OR EXISTS (SELECT 1 FROM event_batches WHERE run_id = OLD.run_id)
BEGIN
  SELECT RAISE(ABORT, 'anchor before spans');
END;
CREATE TRIGGER keep_finish_children BEFORE DELETE ON function_finishes
WHEN EXISTS (SELECT 1 FROM history WHERE run_id = OLD.run_id)
  OR EXISTS (SELECT 1 FROM function_runs WHERE run_id = OLD.run_id)
BEGIN
  SELECT RAISE(ABORT, 'anchor before history');
END;
"""

def connect(path):
    conn = sqlite3.connect(path)
    conn.isolation_level = None
    return conn

def seed(path):
    conn = connect(path)
    conn.executescript(SCHEMA)
    def run(status, ended, run_id, with_trace):
        conn.execute(
            "INSERT INTO trace_runs (run_id, ended_at, status) VALUES (?, ?, ?)",
            (run_id, ended, status),
        )
        conn.execute(
            "INSERT INTO spans (span_id, trace_id, run_id) VALUES (?, ?, ?)",
            ("span-" + run_id[:8], "tr-" + run_id[:8], run_id),
        )
        if with_trace:
            conn.execute(
                "INSERT INTO traces (trace_id, span_id, run_id) VALUES (?, ?, ?)",
                ("trace-" + run_id[:8], "sp-" + run_id[:8], run_id),
            )
            conn.execute(
                "INSERT INTO event_batches (id, run_id) VALUES (?, ?)",
                (tid("eb" + run_id[:6]), run_id),
            )
    run(300, OLD_MS, RUN_OLD, True)
    run(50, OLD_MS, RUN_50, False)
    run(300, RECENT_MS, RUN_RECENT, True)
    run(200, OLD_MS, RUN_LIVE, True)
    conn.execute(
        "INSERT INTO traces (trace_id, span_id, run_id) VALUES ('nulltrace', 'nullspan', NULL)"
    )
    def finish(run_id, event_id, created, data):
        conn.execute(
            "INSERT INTO events (internal_id, received_at, event_data) VALUES (?, ?, ?)",
            (event_id, created, data),
        )
        conn.execute(
            "INSERT INTO function_runs (run_id, event_id) VALUES (?, ?)",
            (run_id, event_id),
        )
        conn.execute(
            "INSERT INTO history (run_id, event_id) VALUES (?, ?)",
            (run_id, event_id),
        )
    finish(FR_OLD, EV_OLD, OLD_TS, SENTINEL)
    conn.execute(
        "INSERT INTO function_finishes (run_id, status, created_at) VALUES (?, 'Completed', ?)",
        (FR_OLD, OLD_TS),
    )
    finish(FR_RECENT, EV_RECENT, RECENT_TS, "recent-payload")
    conn.execute(
        "INSERT INTO function_finishes (run_id, status, created_at) VALUES (?, 'Completed', ?)",
        (FR_RECENT, RECENT_TS),
    )
    finish(FR_LIVE, EV_LIVE, OLD_TS, SENTINEL)
    conn.execute(
        "INSERT INTO events (internal_id, received_at, event_data) VALUES (?, ?, ?)",
        (EV_ORPHAN, OLD_TS, "orphan-payload"),
    )
    conn.execute("INSERT INTO apps (id, name) VALUES ('app1', 'keep')")
    conn.execute("INSERT INTO functions (id, name) VALUES ('fn1', 'keep')")
    conn.execute("INSERT INTO worker_connections (id) VALUES ('wc1')")
    conn.execute("INSERT INTO migrations (id, version) VALUES (1, '000001')")
    conn.execute("INSERT INTO goose_db_version (id, version_id) VALUES (1, 1)")
    conn.execute("INSERT INTO queue_snapshot_chunks (id) VALUES ('chunk1')")
    conn.close()

def expect(got, want, label, errors):
    if got != want:
        errors.append("%s: got %s want %s" % (label, got, want))

def check(path):
    conn = connect(path)
    errors = []
    def n(sql, args=()):
        return conn.execute(sql, args).fetchone()[0]
    expect(n("SELECT count(*) FROM trace_runs WHERE run_id=?", (RUN_OLD,)), 0, "olddone run", errors)
    expect(n("SELECT count(*) FROM trace_runs WHERE run_id=?", (RUN_50,)), 0, "stat50 run", errors)
    expect(n("SELECT count(*) FROM trace_runs WHERE run_id=?", (RUN_RECENT,)), 1, "recent run", errors)
    expect(n("SELECT count(*) FROM trace_runs WHERE run_id=?", (RUN_LIVE,)), 1, "inflight run", errors)
    expect(n("SELECT count(*) FROM spans WHERE run_id=?", (RUN_OLD,)), 0, "old span", errors)
    expect(n("SELECT count(*) FROM spans WHERE run_id=?", (RUN_50,)), 0, "stat50 span", errors)
    expect(n("SELECT count(*) FROM spans WHERE run_id=?", (RUN_RECENT,)), 1, "recent span", errors)
    expect(n("SELECT count(*) FROM spans WHERE run_id=?", (RUN_LIVE,)), 1, "inflight span", errors)
    expect(n("SELECT count(*) FROM traces WHERE run_id=?", (RUN_OLD,)), 0, "old trace", errors)
    expect(n("SELECT count(*) FROM traces WHERE run_id=?", (RUN_RECENT,)), 1, "recent trace", errors)
    expect(n("SELECT count(*) FROM traces WHERE run_id=?", (RUN_LIVE,)), 1, "inflight trace", errors)
    expect(n("SELECT count(*) FROM traces WHERE run_id IS NULL"), 1, "null run_id trace", errors)
    expect(n("SELECT count(*) FROM event_batches WHERE run_id=?", (RUN_OLD,)), 0, "old batch", errors)
    expect(n("SELECT count(*) FROM event_batches WHERE run_id=?", (RUN_RECENT,)), 1, "recent batch", errors)
    expect(n("SELECT count(*) FROM event_batches WHERE run_id=?", (RUN_LIVE,)), 1, "inflight batch", errors)
    expect(n("SELECT count(*) FROM function_finishes WHERE run_id=?", (FR_OLD,)), 0, "old finish", errors)
    expect(n("SELECT count(*) FROM function_finishes WHERE run_id=?", (FR_RECENT,)), 1, "recent finish", errors)
    expect(n("SELECT count(*) FROM function_runs WHERE run_id=?", (FR_OLD,)), 0, "old function run", errors)
    expect(n("SELECT count(*) FROM function_runs WHERE run_id=?", (FR_RECENT,)), 1, "recent function run", errors)
    expect(n("SELECT count(*) FROM function_runs WHERE run_id=?", (FR_LIVE,)), 1, "inflight function run", errors)
    expect(n("SELECT count(*) FROM history WHERE run_id=?", (FR_OLD,)), 0, "old history", errors)
    expect(n("SELECT count(*) FROM history WHERE run_id=?", (FR_RECENT,)), 1, "recent history", errors)
    expect(n("SELECT count(*) FROM history WHERE run_id=?", (FR_LIVE,)), 1, "inflight history", errors)
    expect(n("SELECT count(*) FROM events WHERE internal_id=?", (EV_OLD,)), 0, "old event", errors)
    expect(n("SELECT count(*) FROM events WHERE internal_id=?", (EV_RECENT,)), 1, "recent event", errors)
    expect(n("SELECT count(*) FROM events WHERE internal_id=?", (EV_LIVE,)), 1, "inflight event", errors)
    expect(n("SELECT count(*) FROM events WHERE internal_id=?", (EV_ORPHAN,)), 0, "orphan event", errors)
    for table in (
        "apps", "functions", "worker_connections", "migrations",
        "goose_db_version", "queue_snapshot_chunks",
    ):
        expect(n("SELECT count(*) FROM " + table), 1, table, errors)
    conn.close()
    if errors:
        raise SystemExit("fixture mismatch:\n" + "\n".join(errors))
    print("CHECK_OK")

def insert_extra(path):
    conn = connect(path)
    run_id = tid("extram")
    ended = int(time.time() * 1000) - 9 * 86400000
    conn.execute(
        "INSERT INTO trace_runs (run_id, ended_at, status) VALUES (?, ?, 300)",
        (run_id, ended),
    )
    conn.close()
    print(run_id)

def count_run(path, run_id):
    conn = connect(path)
    n = conn.execute("SELECT count(*) FROM trace_runs WHERE run_id=?", (run_id,)).fetchone()[0]
    conn.close()
    print(n)

def seed_plain(path, rows, with_span):
    conn = connect(path)
    conn.executescript(SCHEMA)
    base = int(time.time() * 1000) - 8 * 86400000
    for i in range(rows):
        run_id = tid("plain%d" % i)
        conn.execute(
            "INSERT INTO trace_runs (run_id, ended_at, status) VALUES (?, ?, 300)",
            (run_id, base - i),
        )
        if with_span:
            conn.execute(
                "INSERT INTO spans (span_id, trace_id, run_id) VALUES (?, ?, ?)",
                ("s%d" % i, "t%d" % i, run_id),
            )
    conn.close()

def seed_cap(path):
    conn = connect(path)
    conn.executescript(SCHEMA)
    base = int(time.time() * 1000) - 8 * 86400000
    old = "2000-01-01 00:00:00"
    for i in range(2):
        run_id = tid("cap%d" % i)
        conn.execute(
            "INSERT INTO trace_runs (run_id, ended_at, status) VALUES (?, ?, 300)",
            (run_id, base - i),
        )
        conn.execute(
            "INSERT INTO spans (span_id, trace_id, run_id) VALUES (?, ?, ?)",
            ("cs%d" % i, "ct%d" % i, run_id),
        )
        finish = ("fr-cap-%d" % i).encode()
        conn.execute(
            "INSERT INTO function_finishes (run_id, status, created_at) VALUES (?, ?, ?)",
            (finish, "Completed", old),
        )
        conn.execute(
            "INSERT INTO history (run_id, event_id) VALUES (?, ?)",
            (finish, b"ev-cap"),
        )
    conn.execute(
        "INSERT INTO events (internal_id, received_at, event_data) VALUES (?, ?, ?)",
        (b"ev-cap-free", old, "cap"),
    )
    conn.close()

def count_table(path, table):
    conn = connect(path)
    n = conn.execute("SELECT count(*) FROM " + table).fetchone()[0]
    conn.close()
    print(n)

cmd = sys.argv[1]
if cmd == "seed":
    seed(sys.argv[2])
elif cmd == "check":
    check(sys.argv[2])
elif cmd == "insert-extra":
    insert_extra(sys.argv[2])
elif cmd == "count-run":
    count_run(sys.argv[2], sys.argv[3])
elif cmd == "seed-plain":
    seed_plain(sys.argv[2], int(sys.argv[3]), sys.argv[4] == "span")
elif cmd == "seed-cap":
    seed_cap(sys.argv[2])
elif cmd == "count-table":
    count_table(sys.argv[2], sys.argv[3])
else:
    raise SystemExit("unknown harness command")
PY

write_stub() {
  local path="$1"
  assert_fixture_dir "$path"
  cat >"$path" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
log="${INNGEST_TRACE_RETENTION_STUB_LOG}"
mode="${INNGEST_TRACE_RETENTION_STUB_MODE}"
if [[ -z "$log" || -z "$mode" ]]; then
  printf 'stub missing log or mode\n' >&2
  exit 2
fi
sql=""
prev=""
for a in "$@"; do
  case "$a" in
    *postgres://*) printf 'stub saw uri on argv\n' >>"$log"; exit 3 ;;
  esac
  if [[ "$prev" == "-c" ]]; then
    sql="$a"
  fi
  prev="$a"
done
kind="other"
case "$sql" in
  EXPLAIN*|explain*) kind="explain" ;;
  *pg_database_size*) kind="size" ;;
  *DELETE*) kind="delete" ;;
esac
if [[ "$kind" == "delete" ]]; then
  case "$sql" in
    *"<"*) ;;
    *) printf 'stub: delete missing age comparison\n' >&2; exit 4 ;;
  esac
  case "$sql" in
    *86400000*|*'make_interval(days'*) ;;
    *) printf 'stub: delete missing age token\n' >&2; exit 4 ;;
  esac
fi
printf 'KIND=%s\n' "$kind" >>"$log"
case "$mode" in
  seq)
    if [[ "$kind" == "explain" ]]; then
      for t in spans traces events history; do
        case "$sql" in
          *"$t"*) printf 'Seq Scan on %s\n' "$t" ;;
        esac
      done
    fi
    ;;
  budget)
    state="${log}.state"
    seen=0
    if [[ -f "$state" ]]; then
      seen="$(cat "$state")"
    fi
    if [[ "$kind" == "explain" ]]; then
      printf 'Index Scan using soleur_traces_run_id on traces\n'
    elif [[ "$kind" == "size" ]]; then
      if [[ "$seen" == "0" ]]; then
        printf '1000\n'
      else
        printf '1000001000\n'
      fi
    elif [[ "$kind" == "delete" ]]; then
      printf '1\n' >"$state"
      printf '1\n'
    fi
    ;;
  index)
    if [[ "$kind" == "explain" ]]; then
      printf 'Index Scan using soleur_traces_run_id on traces\n'
    elif [[ "$kind" == "size" ]]; then
      printf '1000\n'
    elif [[ "$kind" == "delete" ]]; then
      printf '0\n'
    fi
    ;;
esac
exit 0
STUB
  chmod +x "$path"
}

DB="${FIX}/main.db"
MARKER="${FIX}/marker"
python3 "$HARNESS" seed "$DB"

export INNGEST_TRACE_RETENTION_DAYS=7
export INNGEST_TRACE_RETENTION_SQLITE="$DB"
export INNGEST_TRACE_RETENTION_MARKER="$MARKER"
RET_URI=""
run_retention "$OUT"
require_green "sqlite happy path exits 0" "$OUT"
require_out "$OUT" "INNGEST_TRACE_RETENTION_OUTCOME=ok" "happy path outcome ok"
require_out "$OUT" "INNGEST_TRACE_RETENTION_FILE=inngest-trace-retention.sqlite.sql" "sqlite file executed"
require_out "$OUT" "INNGEST_TRACE_RETENTION_GLOB=inngest-trace-retention*.sql" "glob echoed"
forbid_out "$OUT" "$SENTINEL" "logs omit event payload"
forbid_out "$OUT" "postgres://" "logs omit uri"
if ! python3 "$HARNESS" check "$DB" >"${FIX}/check.out" 2>"${FIX}/check.err"; then
  cat "${FIX}/check.err" >&2
  die "five situations did not match"
fi
require_out "${FIX}/check.out" "CHECK_OK" "finished traces expired and in-flight rows kept"
if [[ ! -f "$MARKER" ]]; then
  die "success did not write the utc marker"
fi
pass "marker written on success"

EXTRA="$(python3 "$HARNESS" insert-extra "$DB")"
run_retention "${FIX}/second.out"
require_green "same-utc-day second run exits 0" "${FIX}/second.out"
require_out "${FIX}/second.out" "INNGEST_TRACE_RETENTION_DELETED spans=0 traces=0 event_batches=0 trace_runs=0 history=0 function_runs=0 function_finishes=0 events=0" "second run deletes nothing"
LEFT="$(python3 "$HARNESS" count-run "$DB" "$EXTRA")"
if [[ "$LEFT" != "1" ]]; then
  die "same-day marker failed to keep the new old run (count ${LEFT})"
fi
pass "marker skips a second delete the same utc day"

# days=0 is rejected and deletes nothing
D0="${FIX}/days0.db"
python3 "$HARNESS" seed-plain "$D0" 1 span
export INNGEST_TRACE_RETENTION_SQLITE="$D0"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-days0"
export INNGEST_TRACE_RETENTION_DAYS=0
run_retention "${FIX}/days0.out"
if [[ "$RET_RC" -eq 0 ]]; then
  dump "${FIX}/days0.out"
  die "days=0 exited 0"
fi
pass "days=0 is rejected"
if [[ "$(python3 "$HARNESS" count-table "$D0" trace_runs)" != "1" ]]; then
  die "days=0 deleted a row"
fi
pass "days=0 deleted nothing"
if [[ -f "${FIX}/marker-days0" ]]; then
  die "days=0 wrote the marker"
fi
pass "days=0 wrote no marker"
export INNGEST_TRACE_RETENTION_DAYS=7

# a capped child holds its anchor, still deletes the other pipelines, and writes no marker
CAPDB="${FIX}/cap.db"
python3 "$HARNESS" seed-cap "$CAPDB"
export INNGEST_TRACE_RETENTION_SQLITE="$CAPDB"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-cap"
export INNGEST_TRACE_RETENTION_BATCH=1
export INNGEST_TRACE_RETENTION_MAX_BATCHES=1
run_retention "${FIX}/cap.out"
if [[ "$RET_RC" -eq 0 ]]; then
  dump "${FIX}/cap.out"
  die "batch cap exited 0"
fi
pass "batch cap exits non-zero"
require_out "${FIX}/cap.out" "reason=batch_cap" "batch cap names the reason"
if [[ "$(python3 "$HARNESS" count-table "$CAPDB" trace_runs)" != "2" ]]; then
  die "batch cap deleted a trace_runs anchor"
fi
pass "batch cap leaves trace_runs in place"
if [[ "$(python3 "$HARNESS" count-table "$CAPDB" function_finishes)" != "2" ]]; then
  die "batch cap deleted a function_finishes anchor"
fi
pass "batch cap leaves function_finishes in place"
if [[ "$(python3 "$HARNESS" count-table "$CAPDB" history)" != "1" ]]; then
  die "batch cap did not continue into history (count $(python3 "$HARNESS" count-table "$CAPDB" history))"
fi
pass "batch cap deletes one history row and holds the finish anchor"
if [[ "$(python3 "$HARNESS" count-table "$CAPDB" spans)" != "1" ]]; then
  die "batch cap did not stop the spans statement at one row"
fi
pass "batch cap deletes one span and holds the trace anchor"
if [[ "$(python3 "$HARNESS" count-table "$CAPDB" events)" != "0" ]]; then
  die "batch cap did not continue into events"
fi
pass "batch cap deletes the eligible event"
if [[ -f "${FIX}/marker-cap" ]]; then
  die "batch cap wrote the marker"
fi
pass "batch cap writes no marker"
unset INNGEST_TRACE_RETENTION_BATCH
unset INNGEST_TRACE_RETENTION_MAX_BATCHES

# seq scan aborts before any delete, including the sqlite arm
SEQDB="${FIX}/seq.db"
python3 "$HARNESS" seed-plain "$SEQDB" 1 span
write_stub "${FIX}/psql-stub"
export INNGEST_TRACE_RETENTION_SQLITE="$SEQDB"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-seq"
export INNGEST_TRACE_RETENTION_PSQL="${FIX}/psql-stub"
export INNGEST_TRACE_RETENTION_STUB_LOG="${FIX}/seq-stub.log"
export INNGEST_TRACE_RETENTION_STUB_MODE=seq
RET_URI="$FAKE_URI"
: >"$INNGEST_TRACE_RETENTION_STUB_LOG"
run_retention "${FIX}/seq.out"
RET_URI=""
if [[ "$RET_RC" -eq 0 ]]; then
  dump "${FIX}/seq.out"
  die "seq scan exited 0"
fi
pass "seq scan exits non-zero"
require_out "${FIX}/seq.out" "INNGEST_TRACE_RETENTION_OUTCOME=error" "seq scan outcome error"
if grep -F -q 'KIND=delete' "$INNGEST_TRACE_RETENTION_STUB_LOG"; then
  dump "$INNGEST_TRACE_RETENTION_STUB_LOG"
  die "seq scan executed a delete"
fi
pass "seq scan executed no delete"
if [[ "$(python3 "$HARNESS" count-table "$SEQDB" trace_runs)" != "1" ]]; then
  die "seq scan deleted the sqlite row"
fi
if [[ "$(python3 "$HARNESS" count-table "$SEQDB" spans)" != "1" ]]; then
  die "seq scan deleted the sqlite span"
fi
pass "seq scan leaves sqlite untouched"
if [[ -f "${FIX}/marker-seq" ]]; then
  die "seq scan wrote the marker"
fi
pass "seq scan wrote no marker"

# size budget stops the postgres arm before sqlite deletes
BUDDB="${FIX}/budget.db"
python3 "$HARNESS" seed-plain "$BUDDB" 1 span
export INNGEST_TRACE_RETENTION_SQLITE="$BUDDB"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-budget"
export INNGEST_TRACE_RETENTION_STUB_LOG="${FIX}/budget-stub.log"
export INNGEST_TRACE_RETENTION_STUB_MODE=budget
export INNGEST_TRACE_RETENTION_SIZE_BUDGET_BYTES=1000
RET_URI="$FAKE_URI"
: >"$INNGEST_TRACE_RETENTION_STUB_LOG"
run_retention "${FIX}/budget.out"
RET_URI=""
if [[ "$RET_RC" -eq 0 ]]; then
  dump "${FIX}/budget.out"
  die "size budget exited 0"
fi
pass "size budget exits non-zero"
require_out "${FIX}/budget.out" "INNGEST_TRACE_RETENTION_OUTCOME=error" "size budget outcome error"
forbid_out "${FIX}/budget.out" "VACUUM" "size budget log has no vacuum token"
if [[ "$(python3 "$HARNESS" count-table "$BUDDB" trace_runs)" != "1" ]]; then
  die "size budget deleted the sqlite row"
fi
pass "size budget leaves the sqlite row"
if [[ -f "${FIX}/marker-budget" ]]; then
  die "size budget wrote the marker"
fi
pass "size budget wrote no marker"
unset INNGEST_TRACE_RETENTION_SIZE_BUDGET_BYTES

# both stores: index-scan explain lets the sqlite arm run
BOTHDB="${FIX}/both.db"
python3 "$HARNESS" seed-plain "$BOTHDB" 1 span
export INNGEST_TRACE_RETENTION_SQLITE="$BOTHDB"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-both"
export INNGEST_TRACE_RETENTION_STUB_LOG="${FIX}/both-stub.log"
export INNGEST_TRACE_RETENTION_STUB_MODE=index
RET_URI="$FAKE_URI"
: >"$INNGEST_TRACE_RETENTION_STUB_LOG"
run_retention "${FIX}/both.out"
RET_URI=""
require_green "both stores exit 0" "${FIX}/both.out"
require_out "${FIX}/both.out" "INNGEST_TRACE_RETENTION_FILE=inngest-trace-retention.sql" "postgres file executed"
require_out "${FIX}/both.out" "INNGEST_TRACE_RETENTION_FILE=inngest-trace-retention.sqlite.sql" "sqlite file executed beside postgres"
if [[ "$(python3 "$HARNESS" count-table "$BOTHDB" trace_runs)" != "0" ]]; then
  die "both-store run left the sqlite row"
fi
pass "both-store run deletes the sqlite row"
forbid_out "${FIX}/both.out" "secret" "both-store log hides password"
forbid_out "$INNGEST_TRACE_RETENTION_STUB_LOG" "postgres://" "psql argv hides uri"

# no usable store
export INNGEST_TRACE_RETENTION_SQLITE="${FIX}/missing.db"
export INNGEST_TRACE_RETENTION_MARKER="${FIX}/marker-none"
unset INNGEST_TRACE_RETENTION_PSQL
unset INNGEST_TRACE_RETENTION_STUB_LOG
unset INNGEST_TRACE_RETENTION_STUB_MODE
RET_URI=""
run_retention "${FIX}/none.out"
if [[ "$RET_RC" -eq 0 ]]; then
  dump "${FIX}/none.out"
  die "missing store exited 0"
fi
pass "missing store exits non-zero"
require_out "${FIX}/none.out" "INNGEST_TRACE_RETENTION_OUTCOME=error" "missing store outcome error"

printf 'RETENTION_SUITE_OK passes=%s\n' "$PASSES"
