#!/usr/bin/env bash
# Exit-code harness for zot-upload-ceiling-7556.sh (#7556).
#
# The probe's exit code auto-closes a P1 tracker and unblocks ADR-190 (adopting -> accepted), so every
# case below is a way the verdict can be wrong in the PASS direction, or a way it can be wedged at
# TRANSIENT forever. The live defect this exists for: the sample floor counted the zot handler NAME
# (`PatchBlobUpload`), which appears only on error lines and on the disk heartbeat's echo of a stale
# error, so a week with 44 real PATCH uploads read `too-few-samples patch_rows=2`. Case 1 is that input.
#
# FIXTURES ARE PRODUCTION-SHAPED AND THE STUB REPLAYS THE REAL TOOL'S CONTRACT, not the probe author's
# reading of it. scripts/betterstack-query.sh returns rows sorted dt ASC but keeps the NEWEST --limit rows
# when more match; --grep is OR-combined `raw LIKE '%x%'` over the DOUBLE-ENCODED raw column; --until is
# `dt <=`; rc 3 is the credential guard. A stub written by the consumer's author hides the bug between
# the two, so this one asserts its own argv before it answers (a dropped --grep, a widened --since, a
# missing --until or a shrunk --limit exits 64 and the case goes red).
# MAINTENANCE: if betterstack-query.sh changes its contract, this stub must change with it.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): documentation IPs, zero-uuids and an
# example repo; only the envelope and field SHAPE mirror a measured emission.
#
# Knobs (all env, defaults are the measured live state, synthesized):
#   CFG      ok|none|mismatch_read|mismatch_write|unparse     boot `configuration settings` row
#   PATCHES  "n:status:latency[:method];..."                  upload rows (default 43 x 202/29s + one 500/5m55s)
#   PUTS POSTS  counts of other-method upload rows (never count toward the sample)
#   ECHO     eof|timeout|""  ECHO_N                            SOLEUR_ZOT_DISK heartbeats echoing zot_last_err
#   ERRROW   timeout|eof|webhook_timeout|""                    a level:error PatchBlobUpload row
#   FORGE    comma list: webhook webhook_syntax hdr_get path_get otherhost
#   DROPS    "reason:count;..."  DROPS_QUOTE=1  DROPS_NOREASON=1   SOLEUR_ZOT_LOG_DROPPED rows
#   ANCHOR   present|absent|contaminated|slack|outside|old      heartbeat placement relative to window start
#   RAWN_LOG RAWN_DROP                                         pad the raw row count of that read to N
#   CFG_RC LOG_RC DROP_RC ANCHOR_RC  *_ERR=1                   per-read nonzero exit / error payload on rc 0
#   CLASSIFIER_FAIL=1  SENT=1  REPO  USERNAME

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/zot-upload-ceiling-7556.sh"
fails=0
passes=0
# `cases` is incremented at the CALL SITE (top of expect(), and immediately before each inline
# if/else that resolves to one verdict) and NEVER inside pass()/fail(): that placement is what the
# conservation check at the bottom measures. Never increment inside `$( )` - a subshell discards it.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }
command -v python3 >/dev/null || { echo "FATAL: python3 required" >&2; exit 1; }
REAL_PY="$(command -v python3)"

# INSTRUMENT SELF-TEST (ADR-193): drive both verdict helpers once and refuse to continue unless both
# counters moved. The two calls are undone so they do not count as cases.
p0=$passes; f0=$fails
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail, expected)" 2>/dev/null
if (( passes != p0 + 1 || fails != f0 + 1 )); then
  printf 'FATAL: verdict helpers did not move their counters (passes %d->%d, fails %d->%d)\n' "$p0" "$passes" "$f0" "$fails" >&2
  exit 1
fi
passes=$p0; fails=$f0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/shim"
: > "$WORK/argv.log"

# python3 shim: fails ONLY for the probe's classifier (recognised by a token in its program text), and
# delegates everything else to the real interpreter (resolved to an absolute path BEFORE PATH changes).
cat > "$WORK/shim/python3" <<SHIM
#!/usr/bin/env bash
if [[ "\${CLASSIFIER_FAIL:-0}" == "1" && "\${2:-}" == *upload_any* ]]; then exit 3; fi
exec "$REAL_PY" "\$@"
SHIM
chmod +x "$WORK/shim/python3"

cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env python3
import os, sys, json, datetime, re

E = os.environ.get
argv = sys.argv[1:]
log = E("ARGLOG")
if log:
    with open(log, "a") as fh:
        fh.write(" ".join(argv) + "\n")
if E("STUB_NOCRED") == "1":
    sys.exit(3)

def die(msg):
    sys.stderr.write("stub: %s (argv: %s)\n" % (msg, " ".join(argv)))
    sys.exit(64)

greps, since, until, limit = [], None, None, None
i = 0
while i < len(argv):
    a = argv[i]
    if a == "--grep": greps.append(argv[i + 1]); i += 2
    elif a == "--since": since = argv[i + 1]; i += 2
    elif a == "--until": until = argv[i + 1]; i += 2
    elif a == "--limit": limit = int(argv[i + 1]); i += 2
    else: die("unknown arg " + a)

now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
if greps == ["configuration settings"]: kind = "cfg"
elif greps == ["SOLEUR_ZOT_LOG_DROPPED"]: kind = "drop"
elif sorted(greps) == ["PatchBlobUpload", "blobs/uploads"]: kind = "log"
elif greps == ["SOLEUR_ZOT_DISK"]: kind = "anchor"
else: die("unexpected --grep set %r" % (greps,))

if since != "7d": die("--since must be the 7d window")
if kind == "log" and (limit != 5000 or until is not None): die("uploads read needs --limit 5000 and no --until")
if kind == "drop" and (limit != 20000 or until is not None): die("dropped read needs --limit 20000 and no --until")
if kind == "cfg" and (limit is None or limit < 1 or until is not None): die("config read needs --limit and no --until")
if kind == "anchor":
    if limit != 20 or until is None: die("anchor read needs --limit 20 and --until")
    for f in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%d %H:%M:%S"):
        try: u = datetime.datetime.strptime(until, f); break
        except ValueError: u = None
    if u is None: die("--until not parseable")
    want = now - datetime.timedelta(hours=168 - 6)
    if abs((u - want).total_seconds()) > 300: die("--until must be window start + 6h, got %s want ~%s" % (until, want))

k = {"cfg": "CFG", "log": "LOG", "drop": "DROP", "anchor": "ANCHOR"}[kind]
if E(k + "_RC", "0") != "0": sys.exit(int(E(k + "_RC")))
if E(k + "_ERR") == "1":
    print("Code: 62. DB::Exception: Syntax error: failed at position 1 (SELEC): stub")
    sys.exit(0)

PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
UUID = "00000000-0000-4000-8000-%012d"
REPO = E("REPO", "example-org/example-image")
USER = E("USERNAME", "zot-push")
UA = "ExampleAgent/1.0" + (" SENTINEL_7556_ROW_TEXT" if E("SENT") == "1" else "")
rows = []

def ts(h): return now - datetime.timedelta(hours=h)
def emit(h, msg):
    t = ts(h)
    rows.append((t, json.dumps({"dt": t.strftime("%Y-%m-%d %H:%M:%S.%f"), "raw": json.dumps({"message": msg}, separators=(",", ":"))}, separators=(",", ":"))))

def up(h, method, status, lat, n=1, pfx=PFX, ua=UA, path_tail="", user=USER):
    emit(h, pfx + "{time:%s,level:info,message:HTTP API,module:http,username:%s,component:session,clientIP:192.0.2.10:37042,method:%s,path:/v2/%s/blobs/uploads/%s%s,statusCode:%s,latency:%s,bodySize:0,headers:{User-Agent:[%s]},caller:example/session.go:92,func:example.SessionLogger.func1.1,goroutine:1}" % (ts(h).strftime("%Y-%m-%dT%H:%M:%SZ"), user, method, REPO, UUID % n, path_tail, status, lat, ua))

def spread(n, lo, hi, j):  # hours-ago for member j of n, spread over [lo, hi]
    return lo if n <= 1 else lo + (hi - lo) * j / (n - 1)

ERRMSG = "unexpected error, removing .uploads/ files,error:%s,caller:example/routes.go:2078,func:zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload,goroutine:1"
def errtext(kind): return ERRMSG % ("read tcp 192.0.2.1:5000->192.0.2.10:37042: i/o timeout" if kind == "timeout" else "unexpected EOF")

if kind == "cfg":
    mode = E("CFG", "ok")
    base = PFX + "{time:%s,level:info,message:configuration settings,HTTP:{Address:0.0.0.0,Port:5000,%s}}"
    vals = {"ok": "ReadTimeout:1800000000000,WriteTimeout:1800000000000",
            "mismatch_read": "ReadTimeout:60000000000,WriteTimeout:1800000000000",
            "mismatch_write": "ReadTimeout:1800000000000,WriteTimeout:60000000000",
            "unparse": "Timeouts:unset"}
    if mode != "none":
        emit(40, base % (ts(40).strftime("%Y-%m-%dT%H:%M:%SZ"), vals[mode]))
elif kind == "log":
    seg = E("PATCHES", "43:202:29s;1:500:5m55s")
    idx = 1
    for s in [x for x in seg.split(";") if x.strip()]:
        parts = s.split(":")
        n, st, lat = int(parts[0]), parts[1], parts[2]
        method = parts[3] if len(parts) > 3 else "PATCH"
        for j in range(n):
            up(spread(n, 1, 154, j) + (idx % 7) * 0.01, method, st, lat, idx); idx += 1
    for m, cnt in (("PUT", int(E("PUTS", "47"))), ("POST", int(E("POSTS", "12")))):
        for j in range(cnt):
            up(spread(cnt, 2, 150, j) + 0.02, m, "201" if m == "PUT" else "202", "2s", idx); idx += 1
    for j in range(int(E("ECHO_N", "2")) if E("ECHO", "eof") else 0):
        h = 60 + j * 10
        emit(h, "SOLEUR_ZOT_DISK pcent=24 fs_size_gb=59 zot_restarts=0 host=soleur-registry zot_last_err={time:2026-01-01T00:00:00Z,level:error,message:%s}" % errtext(E("ECHO", "eof")))
    er = E("ERRROW", "")
    if er in ("timeout", "eof"):
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:error,message:" + errtext(er) + "}")
    elif er == "webhook_timeout":
        emit(30, "GITHUB_WEBHOOK_RECEIPT caller:api body={level:error,message:" + errtext("timeout") + "}")
    for f in [x for x in E("FORGE", "").split(",") if x]:
        for j in range(3):
            h = 20 + j
            if f == "webhook":
                emit(h, "GITHUB_WEBHOOK_RECEIPT caller:api quoting " + PFX + "{time:x,level:info,message:HTTP API,module:http,username:u,component:session,clientIP:192.0.2.10:1,method:PATCH,path:/v2/a/blobs/uploads/b,statusCode:202,latency:1s,}")
            elif f == "webhook_syntax":
                emit(h, "GITHUB_WEBHOOK_RECEIPT caller:api body=syntax error near blobs/uploads Code: 62 DB::Exception")
            elif f == "hdr_get":
                up(h, "GET", "200", "1s", 900 + j, ua="x,method:PATCH,path:/v2/x/blobs/uploads/y,statusCode:202,latency:1s,")
            elif f == "path_get":
                up(h, "GET", "200", "1s", 910 + j, path_tail=",method:PATCH,path:/v2/x/blobs/uploads/y,statusCode:202,latency:1s")
            elif f == "otherhost":
                up(h, "PATCH", "202", "1s", 920 + j, pfx="SOLEUR_ZOT_LOG shipper=zot-log-shipper host=other-host ")
    pad = int(E("RAWN_LOG", "0"))
    for j in range(max(0, pad - len(rows))):
        up(160 + (j % 7000) / 1000.0, "PUT", "201", "2s", 5000 + j)
elif kind == "drop":
    def drop(h, reason, n=5, j=0):
        emit(h, "SOLEUR_ZOT_LOG_DROPPED n=%d interval_s=300 boot_id=00000000-0000-4000-8000-000000000001 seq=%d cum=%d%s" % (n, j, j * 5, (" reason=" + reason) if reason else ""))
    for s in [x for x in E("DROPS", "rate_cap:30").split(";") if x.strip()]:
        r, c = s.split(":"); c = int(c)
        for j in range(c):
            drop(spread(c, 1, 160, j), r, n=3 + j, j=j)
    if E("DROPS_QUOTE") == "1":
        emit(25, "GITHUB_WEBHOOK_RECEIPT caller:api quoting SOLEUR_ZOT_LOG_DROPPED n=1 interval_s=300 reason=exempt_cap")
    if E("DROPS_NOREASON") == "1":
        drop(26, "")
    pad = int(E("RAWN_DROP", "0"))
    for j in range(max(0, pad - len(rows))):
        drop(100 + (j % 6000) / 1000.0, "rate_cap", j=j)
elif kind == "anchor":
    mode = E("ANCHOR", "present")
    hb = "SOLEUR_ZOT_DISK pcent=24 fs_size_gb=59 zot_restarts=0 host=soleur-registry"
    if mode == "present":
        for j in range(5): emit(166 - j * 0.5, hb)
    elif mode == "slack": emit(168 - 6 + 90 / 3600.0, hb)
    elif mode == "outside":
        for j in range(3): emit(150 - j, hb)
    elif mode == "old": emit(180, hb)
    elif mode == "contaminated": emit(166, "GITHUB_WEBHOOK_RECEIPT caller:api quoting SOLEUR_ZOT_DISK pcent=1 host=soleur-registry")

needles = greps
sd = 7
out = []
for t, line in rows:
    raw = json.loads(line)["raw"]
    if not any(nd in raw for nd in needles): continue
    if t < now - datetime.timedelta(days=sd): continue
    if until is not None:
        for f in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%d %H:%M:%S"):
            try: u = datetime.datetime.strptime(until, f); break
            except ValueError: u = None
        if t > u: continue
    out.append((t, line))
out.sort(key=lambda r: r[0])
if limit is not None: out = out[-limit:]
for _, line in out: print(line)
STUB
chmod +x "$WORK/stub-query"

DEFAULTS=(CFG=ok "PATCHES=43:202:29s;1:500:5m55s" PUTS=47 POSTS=12 ECHO=eof ECHO_N=2 ERRROW= FORGE= "DROPS=rate_cap:30" DROPS_QUOTE=0 DROPS_NOREASON=0 ANCHOR=present RAWN_LOG=0 RAWN_DROP=0 CFG_RC=0 LOG_RC=0 DROP_RC=0 ANCHOR_RC=0 CFG_ERR=0 LOG_ERR=0 DROP_ERR=0 ANCHOR_ERR=0 CLASSIFIER_FAIL=0 SENT=0)

run() { # run KEY=VAL ... (later assignments override DEFAULTS)
  OUT="$(env "${DEFAULTS[@]}" "$@" ARGLOG="$WORK/argv.log" PATH="$WORK/shim:$PATH" \
         ZOT_CEILING_QUERY="${ZOT_CEILING_QUERY:-$WORK/stub-query}" bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { local l="$1" wrc="$2" wsub="$3"
  cases=$((cases + 1))
  if [[ "$RC" != "$wrc" ]]; then fail "$l: wanted rc=$wrc, got rc=$RC. Output: $OUT"; return; fi
  if [[ -n "$wsub" && "$OUT" != *"$wsub"* ]]; then fail "$l: rc ok but output lacks '$wsub'. Output: $OUT"; return; fi
  pass "$l (rc=$RC)"
}
expect_not() { local l="$1" bad="$2"
  cases=$((cases + 1))
  if [[ "$OUT" == *"$bad"* ]]; then fail "$l: output must NOT contain '$bad'. Output: $OUT"; else pass "$l"; fi
}

echo "zot-upload-ceiling-7556 harness"

# 1. THE LIVE DEFECT: 44 real PATCH rows plus two heartbeat echoes of a stale EOF error.
run
expect "regression: live-shaped week passes with the real PATCH count" 0 "PASS"
expect "regression: patch_rows is the PATCH upload count, not the echo count" 0 "patch_rows=44"
expect "regression: verdict names the other-method population" 0 "upload_rows_any=103"
expect_not "regression: no wedge reason on the live shape" "TRANSIENT"
# 2. Heartbeats only: nothing to grade, and the verdict must say rows were present-but-unmatched-free.
run PATCHES= PUTS=0 POSTS=0
expect "heartbeats only is too-few-samples with patch_rows=0" 2 "too-few-samples patch_rows=0"
# 3-6. n1 (error-row corroboration) and the echo that must never feed it.
run ECHO=timeout
expect "a heartbeat echo carrying i/o timeout does not FAIL" 0 "PASS"
run ERRROW=timeout
expect "a SOLEUR_ZOT_LOG level:error PatchBlobUpload i/o timeout row FAILs" 1 "deadline-submode-present"
run ERRROW=webhook_timeout
expect "the same text in a non-SOLEUR_ZOT_LOG row does not FAIL" 0 "PASS"
run ERRROW=eof
expect "an EOF error row is out of scope and does not FAIL" 0 "PASS"
# 7. n2: a 5xx on an upload row at deadline-shaped latency, any method.
for lat in 30m0s 28m31s 1h0m0s; do
  run "PATCHES=43:202:29s;1:500:${lat}"
  expect "n2: PATCH 5xx at ${lat} FAILs" 1 "deadline-submode-present"
done
run "PATCHES=43:202:29s;1:500:30m0s:PUT"
expect "n2: PUT 5xx at the deadline FAILs (the deadline is server-wide)" 1 "deadline-submode-present"
for lat in 5m55s 3m31s 28m29s; do
  run "PATCHES=43:202:29s;1:500:5m55s;1:500:${lat}"
  expect "n2: 5xx at ${lat} is other5xx, not a deadline cut" 0 "other5xx=2"
done
run
expect "PASS text states the EOF scope" 0 "unexpected EOF"
expect "PASS text states n1 is best-effort and the PATCH count is a lower bound" 0 "lower bound"
expect "PASS text states DELIVERY is the causal evidence" 0 "tripwire"
# 8. unparseable latency, alone and beside a genuine cut.
run "PATCHES=43:202:29s;1:500:abc"
expect "an unparseable 5xx latency is TRANSIENT latency-unparseable" 2 "latency-unparseable"
run "PATCHES=43:202:29s;1:500:abc;1:500:30m0s"
expect "an unparseable 5xx beside a genuine cut still FAILs" 1 "deadline-submode-present"
# 9-10. FAIL precedes the floor and the truncation arm.
run "PATCHES=3:202:5s;1:500:30m0s" PUTS=0 POSTS=0
expect "a finding with only 3 PATCH rows FAILs (FAIL precedes the floor)" 1 "deadline-submode-present"
run "PATCHES=43:202:29s;1:500:30m0s" RAWN_LOG=5000
expect "a finding on a full (truncated) page still FAILs" 1 "deadline-submode-present"
# 11. floor boundary.
run "PATCHES=11:202:5s" PUTS=0 POSTS=0
expect "floor: 11 PATCH rows is too-few-samples" 2 "too-few-samples"
run "PATCHES=12:202:5s" PUTS=0 POSTS=0
expect "floor: exactly 12 PATCH rows passes" 0 "patch_rows=12"
# 12. truncation boundary on the uploads read.
run RAWN_LOG=5000
expect "uploads read: a full 5000-row page is query-truncated-log" 2 "query-truncated-log"
run RAWN_LOG=4999
expect "uploads read: 4999 rows is graded" 0 "PASS"
# 13. exempt-lane drop guard: benign is an allow-list of one.
run "DROPS=rate_cap:9;exempt_cap:1"
expect "drops: an exempt_cap row blocks PASS" 2 "exempt-lane-dropped"
for r in redact_failed sanitized_empty cursor_invalidated new_cause; do
  run "DROPS=rate_cap:9;${r}:1"
  expect "drops: reason ${r} blocks PASS" 2 "exempt-lane-dropped"
done
run "DROPS=rate_cap:9" DROPS_NOREASON=1
expect "drops: a pinned row with no parseable reason blocks PASS" 2 "exempt-lane-dropped"
run DROPS_QUOTE=1
expect "drops: a webhook row quoting reason=exempt_cap is ignored" 0 "PASS"
run RAWN_DROP=20000
expect "dropped read: a full 20000-row page is query-truncated-dropped" 2 "query-truncated-dropped"
run RAWN_DROP=19999
expect "dropped read: 19999 rows is graded" 0 "PASS"
run DROP_RC=2
expect "dropped read: nonzero rc is query-failed-dropped" 2 "query-failed-dropped"
run DROP_ERR=1
expect "dropped read: an error payload on rc 0 is query-error-payload-dropped" 2 "query-error-payload-dropped"
# 14. coverage anchor.
run ANCHOR=absent
expect "anchor: no heartbeat in the window start slack is retention-shorter-than-window" 2 "retention-shorter-than-window"
run ANCHOR=contaminated
expect "anchor: a webhook row quoting the heartbeat does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=outside
expect "anchor: a heartbeat only outside [start, start+6h] does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=old
expect "anchor: a heartbeat older than the window does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=slack
expect "anchor: a heartbeat just inside the slack satisfies it" 0 "PASS"
run ANCHOR_RC=2
expect "anchor read: nonzero rc is query-failed-anchor" 2 "query-failed-anchor"
run ANCHOR_ERR=1
expect "anchor read: an error payload on rc 0 is query-error-payload-anchor" 2 "query-error-payload-anchor"
run
expect "coverage no longer depends on the span of the upload rows (155h span passes)" 0 "PASS"
# 15-16. forgery: a client-controlled field must not add to any count.
run "PATCHES=11:202:5s" PUTS=0 POSTS=0 FORGE=hdr_get,path_get,webhook,otherhost
expect "forgery: header, path, webhook-quote and other-host rows add nothing (11 stays 11)" 2 "patch_rows=11"
run FORGE=webhook_syntax
expect "a webhook row quoting 'syntax error' does not wedge the probe" 0 "PASS"
# 17. helper failure must never fold to zero.
run CLASSIFIER_FAIL=1
expect "a crashed classifier is TRANSIENT classifier-failed, never a pass" 2 "classifier-failed"
# 18. every other distinct reason. (`no-python3` is not driven: the harness itself needs python3 to build its stub.)
ZOT_CEILING_QUERY=/nonexistent/stub run
expect "reason query-not-executable" 2 "query-not-executable"
unset ZOT_CEILING_QUERY
run ZOT_CEILING_WINDOW=3d
expect "reason window-too-short" 2 "window-too-short"
run CFG_RC=3
expect "reason query-failed-config (rc 3 names the credential guard)" 2 "query-failed-config query_rc=3"
expect "rc 3 prints the credential-guard hint" 2 "credential guard"
run CFG_ERR=1
expect "reason query-error-payload-config" 2 "query-error-payload-config"
run CFG=none
expect "reason no-config-line" 2 "no-config-line"
run CFG=unparse
expect "reason deadlines-unparseable" 2 "deadlines-unparseable"
run CFG=mismatch_read
expect "reason deadline-mismatch is a FAIL (rc 1)" 1 "deadline-mismatch"
run CFG=mismatch_write
expect "one mismatched deadline is also deadline-mismatch" 1 "deadline-mismatch"
run LOG_RC=2
expect "reason query-failed-log" 2 "query-failed-log"
run LOG_ERR=1
expect "reason query-error-payload-log" 2 "query-error-payload-log"
cases=$((cases + 1))
if grep -q 'span-underivable' "$PROBE"; then fail "the deleted span guard's reason span-underivable must not linger in the probe"; else pass "span-underivable is gone with the span guard"; fi
# 19. must-PASS inputs that are not the canonical.
run REPO=other-org/deeper/path/image USERNAME=other-user
expect "a different repo depth and username still count" 0 "patch_rows=44"
run "PATCHES=12:202:0s" PUTS=0 POSTS=0
expect "a PATCH at latency 0s counts" 0 "patch_rows=12"
# 20. stdout never carries row text (the sweeper posts it on a public issue).
for variant in "" "ERRROW=timeout" "ANCHOR=absent" "DROPS=rate_cap:9;exempt_cap:1" "PATCHES=43:202:29s;1:500:abc" "CFG_RC=3" "RAWN_LOG=5000"; do
  run SENT=1 ${variant:+"$variant"}
  expect_not "no fixture row text reaches the output (${variant:-default})" "SENTINEL_7556_ROW_TEXT"
done
# 21. argv fidelity is enforced by the stub (exit 64 -> query-failed-*): assert it ran the four reads.
run
cases=$((cases + 1))
nreads=$(grep -c . "$WORK/argv.log" || true)
if [[ "${nreads:-0}" -ge 4 ]]; then pass "the probe issued its config, uploads, dropped and anchor reads"; else fail "expected >= 4 reads in the argv log"; fi

# FLOORS AND CONSERVATION (ADR-193): reported with printf + exit, never through the helpers they back-stop.
# MIN_CASES is a literal; raise it in the SAME edit that adds a row.
MIN_CASES=71
if (( cases < MIN_CASES )); then
  printf 'FATAL: only %d cases ran, floor is %d (a gutted harness reports green)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if (( passes + fails != cases )); then
  printf 'FATAL: conservation broken: passes=%d fails=%d cases=%d (a verdict helper was neutered)\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
printf '\nzot-upload-ceiling-7556: %d passed, %d failed, cases=%d (floor %d)\n' "$passes" "$fails" "$cases" "$MIN_CASES"
(( fails == 0 ))
