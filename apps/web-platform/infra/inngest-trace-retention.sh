#!/usr/bin/env bash
# 7-day status-gated retention for finished Inngest trace and log history.
# Schema pin: Inngest server v1.45.1. Queue state is not deleted by age.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1-}"
ARG="${2-}"

exec python3 - "$MODE" "$ARG" "$HERE" <<'PY'
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse
from datetime import datetime, timezone

GLOB = "inngest-trace-retention*.sql"
STATUS = "status IN (50, 300, 400, 500, 600)"
TRACE_TABLES = ("spans", "traces", "event_batches", "trace_runs")
PROTECTED = (
    "apps",
    "functions",
    "worker_connections",
    "migrations",
    "goose_db_version",
    "queue_snapshot_chunks",
)
COUNT_KEYS = (
    "spans",
    "traces",
    "event_batches",
    "trace_runs",
    "history",
    "function_runs",
    "function_finishes",
    "events",
)
# A capped child holds only its anchor. The other statements still run.
ANCHOR_GATES = {
    "trace_runs": ("spans", "traces", "event_batches"),
    "function_finishes": ("history", "function_runs"),
}
SEQ_SCAN = re.compile(r"(?:Parallel )?Seq Scan on (\w+)")
EXPLAIN_TAG = re.compile(r"(?m)^-- soleur:explain=([a-z,]+)\s*$")
SPLIT = re.compile(r"(?m)^-- soleur:statement\s*$")
DELETE_FROM = re.compile(r"DELETE\s+FROM\s+(\w+)\b", re.I)
INDEX_TRACE_RUNS = (
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS soleur_trace_runs_status_ended_at "
    "ON trace_runs (status, ended_at)"
)
INDEX_FINISHES = (
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS soleur_function_finishes_created_at "
    "ON function_finishes (created_at)"
)
INDEX_TRACES = (
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS soleur_traces_run_id ON traces (run_id)"
)
INDEX_EVENTS = (
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS soleur_events_received_at "
    "ON events (received_at)"
)


def say(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def error(reason):
    sys.stderr.write("INNGEST_TRACE_RETENTION_OUTCOME=error reason=%s\n" % reason)
    sys.stderr.flush()
    raise SystemExit(1)


def env_int(name, default, lo, hi, reason):
    raw = os.environ.get(name, "")
    if raw == "":
        return default
    if not raw.isdigit():
        error(reason)
    value = int(raw)
    if value < lo or value > hi:
        error(reason)
    return value


def strip_comments(sql):
    without_line = re.sub(r"(?m)--[^\n]*", "", sql)
    return re.sub(r"/\*.*?\*/", "", without_line, flags=re.S)


def list_sql(directory):
    if not os.path.isdir(directory):
        return []
    names = []
    for fn in sorted(os.listdir(directory)):
        if fn.startswith("inngest-trace-retention") and fn.endswith(".sql"):
            names.append(fn)
    return names


def is_sqlite_name(fn):
    return fn.endswith(".sqlite.sql")


def bodies_of(text):
    parts = SPLIT.split(text)
    return parts[0], parts[1:]


def delete_indexes(bodies, table):
    pat = re.compile(r"DELETE FROM %s\b" % table)
    hits = []
    for i, body in enumerate(bodies):
        if pat.search(strip_comments(body)):
            hits.append(i)
    return hits


def check_file(fn, text):
    problems = []
    if "v1.45.1" not in text:
        problems.append("%s: missing v1.45.1 pin" % fn)
    if is_sqlite_name(fn):
        for bad in ("make_interval", "ctid", "clock_timestamp"):
            if bad in text:
                problems.append("%s: sqlite file contains %s" % (fn, bad))
    else:
        if "datetime('now'" in text or re.search(r"\browid\b", text):
            problems.append("%s: postgres file contains a sqlite token" % fn)
    if STATUS not in text:
        problems.append("%s: missing status set" % fn)
    _preamble, bodies = bodies_of(text)
    for body in bodies:
        stripped = strip_comments(body)
        if not stripped.strip():
            continue
        if re.search(
            r"DELETE\s+FROM\s+(?:ONLY\s+)?(?:(?:\"?public\"?)\s*\.\s*)?\"?(?:%s)\b"
            % "|".join(PROTECTED),
            stripped,
            re.I,
        ):
            problems.append("%s: deletes a protected table" % fn)
        if len(re.findall(r"DELETE\s+FROM\s+", stripped, re.I)) > 1:
            problems.append("%s: more than one DELETE" % fn)
        if re.search(r"\bDELETE\b", stripped) and ":days" not in stripped:
            problems.append("%s: delete has no day window" % fn)
        if re.search(r"\bDELETE\b", stripped) and re.search(r"\bredis\b", stripped, re.I):
            problems.append("%s: deletes redis" % fn)
        mentions_trace = any(re.search(r"\b%s\b" % name, stripped) for name in TRACE_TABLES)
        if mentions_trace and re.search(r"\bDELETE\b", stripped) and STATUS not in stripped:
            problems.append("%s: trace statement missing the status set" % fn)
        if mentions_trace and re.search(r"\bDELETE\b", stripped) and re.search(r"\b(100|200)\b", stripped):
            problems.append("%s: trace statement names an in-flight status" % fn)
        if re.search(r"DELETE FROM (?:history|function_runs)\b", stripped):
            if "JOIN function_finishes" not in stripped or " ON " not in stripped:
                problems.append("%s: finish gate is not a join" % fn)
        if re.search(r"DELETE FROM history\b", stripped) and "function_finishes" not in stripped:
            problems.append("%s: history delete is not gated on function_finishes" % fn)
        if re.search(r"DELETE FROM events\b", stripped):
            for needle in ("NOT EXISTS", "function_finishes", "ff.run_id IS NULL"):
                if needle not in stripped:
                    problems.append("%s: events delete missing %s" % (fn, needle))
        if re.search(r"DELETE FROM traces\b", stripped) and "run_id IN" not in stripped:
            problems.append("%s: traces delete does not use run_id IN" % fn)
    for chain in (
        ("spans", "traces", "event_batches", "trace_runs"),
        ("history", "function_runs", "function_finishes"),
    ):
        indexes = []
        for table in chain:
            hits = delete_indexes(bodies, table)
            if len(hits) != 1:
                problems.append("%s: expected one DELETE FROM %s" % (fn, table))
                indexes = None
                break
            indexes.append(hits[0])
        if indexes is not None and indexes != sorted(indexes):
            problems.append("%s: children deleted after an anchor" % fn)
    return problems


def check_files(directory, names):
    problems = []
    for fn in names:
        path = os.path.join(directory, fn)
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        problems.extend(check_file(fn, text))
    return problems


def guard(directory):
    names = list_sql(directory)
    if not names:
        sys.stderr.write("guard checked 0 files\n")
        return 1
    problems = check_files(directory, names)
    if problems:
        for item in problems:
            sys.stderr.write(item + "\n")
        return 1
    return 0


def bind(sql, days, batch):
    if not str(days).isdigit() or not str(batch).isdigit():
        error("bind")
    sql = re.sub(r":days\b", str(int(days)), sql)
    sql = re.sub(r":batch\b", str(int(batch)), sql)
    return sql


def statement_plan(text, days, batch):
    _preamble, bodies = bodies_of(text)
    planned = []
    for body in bodies:
        tags = []
        for match in EXPLAIN_TAG.findall(body):
            tags.extend(part for part in match.split(",") if part)
        code = strip_comments(body).strip().rstrip(";").strip()
        if not code:
            continue
        planned.append((bind(code, days, batch), tags))
    return planned


def child_env(uri):
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme not in ("postgres", "postgresql"):
        error("uri")
    database = (parsed.path or "/").lstrip("/")
    if not parsed.hostname or not database:
        error("uri")
    query = urllib.parse.parse_qs(parsed.query)
    sslmode = query.get("sslmode", ["require"])[0]
    env = {
        "PATH": os.environ.get("PATH", ""),
        "PGHOST": parsed.hostname,
        "PGPORT": str(parsed.port or 5432),
        "PGUSER": urllib.parse.unquote(parsed.username or ""),
        "PGPASSWORD": urllib.parse.unquote(parsed.password or ""),
        "PGDATABASE": database,
        "PGSSLMODE": sslmode,
        "PGAPPNAME": "inngest-trace-retention",
        "LC_ALL": "C",
    }
    for key, value in os.environ.items():
        if key.startswith("INNGEST_TRACE_RETENTION_STUB_"):
            env[key] = value
    return env


def psql(sql):
    uri = os.environ.get("INNGEST_POSTGRES_URI", "")
    if not uri:
        error("no_store")
    binary = os.environ.get("INNGEST_TRACE_RETENTION_PSQL", "psql")
    proc = subprocess.run(
        [binary, "-w", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-A", "-t", "-c", sql],
        env=child_env(uri),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        error("psql")
    return proc.stdout


def explain_postgres(directory, names, days, batch):
    for fn in names:
        path = os.path.join(directory, fn)
        with open(path, "r", encoding="utf-8") as fh:
            planned = statement_plan(fh.read(), days, batch)
        for sql, tags in planned:
            if not tags:
                continue
            output = psql("EXPLAIN " + sql)
            if not output.strip():
                error("explain_failed")
            allowed = set(tags)
            for match in SEQ_SCAN.finditer(output):
                if match.group(1) in allowed:
                    error("seq_scan")


def query_size():
    raw = psql("SELECT pg_database_size(current_database())").strip()
    if not raw.isdigit():
        error("size")
    return int(raw)


def count_from_output(raw):
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    if not lines or not lines[0].isdigit():
        error("bad_count")
    return int(lines[0])


def table_of(sql):
    match = DELETE_FROM.search(sql)
    if not match:
        error("bad_sql")
    return match.group(1)


def anchor_held(table, capped):
    gates = ANCHOR_GATES.get(table)
    if gates is None:
        return False
    for name in gates:
        if name in capped:
            return True
    return False


def run_postgres_file(path, days, batch, max_batches, counts, start_size, budget):
    with open(path, "r", encoding="utf-8") as fh:
        planned = statement_plan(fh.read(), days, batch)
    capped = set()
    for sql, _tags in planned:
        table = table_of(sql)
        if anchor_held(table, capped):
            continue
        drained = False
        for _ in range(max_batches):
            deleted = count_from_output(psql(sql))
            counts[table] = counts.get(table, 0) + deleted
            if query_size() - start_size > budget:
                error("size_budget")
            if deleted == 0:
                drained = True
                break
        if not drained:
            capped.add(table)
    return capped


def run_sqlite_file(conn, path, days, batch, max_batches, counts):
    with open(path, "r", encoding="utf-8") as fh:
        planned = statement_plan(fh.read(), days, batch)
    capped = set()
    for sql, _tags in planned:
        table = table_of(sql)
        if anchor_held(table, capped):
            continue
        drained = False
        for _ in range(max_batches):
            try:
                conn.execute(sql)
                counted = conn.execute("SELECT changes()").fetchone()
            except sqlite3.Error as exc:
                detail = str(exc).replace("\n", " ")
                if "postgres://" in detail:
                    detail = type(exc).__name__
                sys.stderr.write("sqlite %s\n" % detail)
                error("sqlite")
            if counted is None or counted[0] is None:
                error("bad_count")
            deleted = int(counted[0])
            counts[table] = counts.get(table, 0) + deleted
            if deleted == 0:
                drained = True
                break
        if not drained:
            capped.add(table)
    return capped


def emit(counts):
    parts = ["%s=%d" % (key, counts.get(key, 0)) for key in COUNT_KEYS]
    say("INNGEST_TRACE_RETENTION_DELETED " + " ".join(parts))
    say("INNGEST_TRACE_RETENTION_OUTCOME=ok")


def write_marker(path, today):
    parent = os.path.dirname(path) or "."
    if not os.path.isdir(parent):
        error("marker_dir")
    fd, tmp = tempfile.mkstemp(prefix=".trace-retention-", dir=parent)
    try:
        os.write(fd, (today + "\n").encode())
        os.close(fd)
        fd = None
        os.replace(tmp, path)
        tmp = None
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        if tmp is not None and os.path.exists(tmp):
            os.remove(tmp)


def marker_is_today(path, today):
    if not os.path.isfile(path):
        return False
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().strip() == today


def resolve_sqlite():
    if "INNGEST_TRACE_RETENTION_SQLITE" in os.environ:
        raw = os.environ["INNGEST_TRACE_RETENTION_SQLITE"]
        if raw and os.path.isfile(raw):
            return raw
        return None
    default = "/var/lib/inngest/main.db"
    if os.path.isfile(default):
        return default
    return None


def ensure_indexes():
    for statement in (INDEX_TRACE_RUNS, INDEX_FINISHES, INDEX_EVENTS):
        psql(statement)
    present = psql("SELECT 1 FROM pg_indexes WHERE indexname = 'idx_traces_run_id'").strip()
    if present == "":
        psql(INDEX_TRACES)


def run(here):
    days = env_int("INNGEST_TRACE_RETENTION_DAYS", 7, 1, 366, "bad_days")
    batch = env_int("INNGEST_TRACE_RETENTION_BATCH", 2000, 1, 100000, "bad_batch")
    max_batches = env_int("INNGEST_TRACE_RETENTION_MAX_BATCHES", 20, 1, 10000, "bad_batches")
    budget = env_int(
        "INNGEST_TRACE_RETENTION_SIZE_BUDGET_BYTES",
        268435456,
        1,
        2**62,
        "bad_budget",
    )
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    marker = os.environ.get(
        "INNGEST_TRACE_RETENTION_MARKER",
        "/var/lib/inngest/trace-retention-utc-date",
    )
    if marker_is_today(marker, today):
        emit({})
        return
    uri = os.environ.get("INNGEST_POSTGRES_URI", "").strip()
    sqlite_path = resolve_sqlite()
    if not uri and not sqlite_path:
        error("no_store")
    names = list_sql(here)
    if not names:
        sys.stderr.write("guard checked 0 files\n")
        error("guard")
    problems = check_files(here, names)
    if problems:
        for item in problems:
            sys.stderr.write(item + "\n")
        error("guard")
    pg_files = [fn for fn in names if not is_sqlite_name(fn)]
    sl_files = [fn for fn in names if is_sqlite_name(fn)]
    selected = []
    if uri:
        selected.extend(pg_files)
    if sqlite_path:
        selected.extend(sl_files)
    if uri and sqlite_path and set(selected) != set(names):
        error("glob_mismatch")
    say("INNGEST_TRACE_RETENTION_GLOB=%s" % GLOB)
    counts = {}
    capped = set()
    if uri:
        explain_postgres(here, pg_files, days, batch)
        start_size = query_size()
        for fn in pg_files:
            say("INNGEST_TRACE_RETENTION_FILE=%s" % fn)
            capped.update(
                run_postgres_file(
                    os.path.join(here, fn),
                    days,
                    batch,
                    max_batches,
                    counts,
                    start_size,
                    budget,
                )
            )
    if sqlite_path:
        conn = sqlite3.connect(sqlite_path)
        conn.isolation_level = None
        try:
            for fn in sl_files:
                say("INNGEST_TRACE_RETENTION_FILE=%s" % fn)
                capped.update(
                    run_sqlite_file(
                        conn, os.path.join(here, fn), days, batch, max_batches, counts
                    )
                )
        finally:
            conn.close()
    if capped:
        error("batch_cap")
    write_marker(marker, today)
    emit(counts)


def main():
    mode = sys.argv[1]
    arg = sys.argv[2]
    here = sys.argv[3]
    if mode == "--guard":
        raise SystemExit(guard(arg))
    if mode == "--ensure-indexes":
        ensure_indexes()
        return
    if mode not in ("",):
        error("usage")
    run(here)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        text = "%s" % type(exc).__name__
        if "postgres://" not in str(exc):
            text = "%s" % type(exc).__name__
        sys.stderr.write("INNGEST_TRACE_RETENTION_OUTCOME=error reason=internal %s\n" % text)
        raise SystemExit(1)
PY
