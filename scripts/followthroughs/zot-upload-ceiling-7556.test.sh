#!/usr/bin/env bash
# Exit-code harness for zot-upload-ceiling-7556.sh (#7556).
#
# The probe's exit code auto-closes a P1 tracker and unblocks ADR-190 (adopting -> accepted), so every
# case below is a way the verdict can be wrong in the PASS direction, or a way it can be wedged at
# TRANSIENT forever. The live defect this exists for: the sample floor counted the zot handler NAME
# (`PatchBlobUpload`), which appears only on error lines and on the disk heartbeat's echo of a stale
# error, so a week with 44 real uploads read `too-few-samples patch_rows=2`. Case 1 is that input.
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
# example repo; only the envelope and field SHAPE mirror a measured emission. The config row mirrors the
# measured `{time:..,level:info,message:configuration settings,params:{...}}` shape.
#
# Knobs (all env, defaults are the measured live state, synthesized):
#   CFG      ok|none|mismatch_read|mismatch_write|unparse|multi_ok|older_bad|older_bad_outside|newest_bad|
#            forged|ua_forged|forged_only|otherhost|aged_ok  boot `configuration settings` rows
#   PATCHES  "n:status:latency[:method];..."                  upload rows (default 43 x 202/29s + one 500/5m55s)
#   PUTS POSTS  counts of other-method upload rows (never count toward the sample)
#   ECHO     eof|timeout|""  ECHO_N                            SOLEUR_ZOT_DISK heartbeats echoing zot_last_err
#   ERRROW   timeout|eof|webhook_timeout|other_handler|warn_level|tls_timeout|quoted_envelope|""
#   FORGE    comma list: webhook webhook_syntax hdr_get path_get otherhost nl_floor status_forge status_mask
#            user_forge dup cut5xx
#   DROPS    "reason:count;..."  DROPS_QUOTE=1  DROPS_NOREASON=1  DROPS_UNDECODABLE=1  DROPS_NL=1
#   ANCHOR   present|absent|contaminated|slack|slack_out|outside|old|otherhost|hostforge|nl_forge
#   TAIL     fresh|stale|absent|otherhost                      newest-heartbeat read (last day)
#   RAWN_LOG RAWN_DROP                                         pad the raw row count of that read to N
#   CFG_RC LOG_RC DROP_RC ANCHOR_RC TAIL_RC  *_ERR=1|json      per-read nonzero exit / error payload on rc 0
#   FAIL_STAGE log|dropped|config|decode|until|heartbeat       make that python3 stage crash (shim)
#   SENT=1  REPO  USERNAME

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
: > "$WORK/argv.log"

# python3 shim: crashes ONLY the probe's python stage named by FAIL_STAGE (recognised by a token in that
# stage's program text) and delegates everything else to the real interpreter (resolved to an absolute
# path BEFORE PATH changes), so each `classifier-failed`/`decoder-failed` arm is drivable.
mkdir -p "$WORK/shim"
cat > "$WORK/shim/python3" <<SHIM
#!/usr/bin/env bash
case "\${FAIL_STAGE:-}" in
  log) tok='upload_any' ;;
  dropped) tok='collections' ;;
  config) tok='older_bad' ;;
  decode) tok='ok = bad = 0' ;;
  until) tok='hours=slack' ;;
  heartbeat) tok='newest_age_h' ;;
  *) tok='' ;;
esac
if [[ -n "\$tok" && "\${2:-}" == *"\$tok"* ]]; then exit 3; fi
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
elif greps == ["SOLEUR_ZOT_DISK"]: kind = "anchor" if until is not None else "tail"
else: die("unexpected --grep set %r" % (greps,))

want_since = {"cfg": "30d", "log": "7d", "drop": "7d", "anchor": "7d", "tail": "1d"}[kind]
if since != want_since: die("--since must be %s for the %s read" % (want_since, kind))
if kind == "log" and (limit != 5000 or until is not None): die("uploads read needs --limit 5000 and no --until")
if kind == "drop" and (limit != 20000 or until is not None): die("dropped read needs --limit 20000 and no --until")
if kind == "cfg" and (limit is None or limit < 1 or until is not None): die("config read needs --limit and no --until")
if kind == "tail" and (limit != 20 or until is not None): die("tail read needs --limit 20 and no --until")
if kind == "anchor":
    if limit != 20 or until is None: die("anchor read needs --limit 20 and --until")
    for f in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%d %H:%M:%S"):
        try: u = datetime.datetime.strptime(until, f); break
        except ValueError: u = None
    if u is None: die("--until not parseable")
    want = now - datetime.timedelta(hours=168 - 6)
    if abs((u - want).total_seconds()) > 300: die("--until must be window start + 6h, got %s want ~%s" % (until, want))

k = {"cfg": "CFG", "log": "LOG", "drop": "DROP", "anchor": "ANCHOR", "tail": "TAIL"}[kind]
if E(k + "_RC", "0") != "0":
    # what the real tool's curl would say: it can name the warehouse host. The probe must never print it.
    sys.stderr.write("curl: (6) Could not resolve host: SENTINEL_HOST_7556.example.invalid\n")
    sys.exit(int(E(k + "_RC")))
if E(k + "_ERR") == "1":
    print("Code: 62. DB::Exception: Syntax error: failed at position 1 (SELEC): stub")
    sys.exit(0)
if E(k + "_ERR") == "json":
    print(json.dumps({"error": "something", "code": 62}))
    sys.exit(0)

PFX = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
UUID = "00000000-0000-4000-8000-%012d"
REPO = E("REPO", "example-org/example-image")
USER = E("USERNAME", "zot-push")
SENT = " SENTINEL_7556_ROW_TEXT" if E("SENT") == "1" else ""
UA = "ExampleAgent/1.0" + SENT
rows = []

def ts(h): return now - datetime.timedelta(hours=h)
def stamp(h): return ts(h).strftime("%Y-%m-%dT%H:%M:%SZ")
def emit(h, msg, raw=None):
    t = ts(h)
    r = raw if raw is not None else json.dumps({"message": msg}, separators=(",", ":"))
    rows.append((t, json.dumps({"dt": t.strftime("%Y-%m-%d %H:%M:%S.%f"), "raw": r}, separators=(",", ":"))))

def uprow(h, method, status, lat, n=1, pfx=PFX, ua=UA, path_tail="", user=USER):
    return (pfx + "{time:%s,level:info,message:HTTP API,module:http,username:%s,component:session,clientIP:192.0.2.10:37042,method:%s,path:/v2/%s/blobs/uploads/%s%s,statusCode:%s,latency:%s,bodySize:0,headers:{User-Agent:[%s]},caller:example/session.go:92,func:example.SessionLogger.func1.1,goroutine:1}" % (stamp(h), user, method, REPO, UUID % n, path_tail, status, lat, ua))
def up(h, *a, **kw): emit(h, uprow(h, *a, **kw))

def spread(n, lo, hi, j):  # hours-ago for member j of n, spread over [lo, hi]
    return lo if n <= 1 else lo + (hi - lo) * j / (n - 1)

ERRMSG = "unexpected error, removing .uploads/ files,error:%s,caller:example/routes.go:2078,func:zotregistry.dev/zot/v2/pkg/api.(*RouteHandler).PatchBlobUpload,goroutine:1"
def errtext(kind): return ERRMSG % ("read tcp 192.0.2.1:5000->192.0.2.10:37042: i/o timeout" if kind == "timeout" else "unexpected EOF")

def heartbeat(h, host="soleur-registry", tail=""):
    return "SOLEUR_ZOT_DISK pcent=24 fs_size_gb=59 zot_restarts=0 host=%s zot_last_err={time:2026-01-01T00:00:00Z,level:error,message:%s%s}" % (host, errtext("eof"), tail)

def cfgrow(h, read, write, pfx=PFX, level="info"):
    t = "ReadTimeout:%s,WriteTimeout:%s" % (read, write) if read else "Unrelated:1"
    return pfx + "{time:%s,level:%s,message:configuration settings,params:{distSpecVersion:1.1.0,HTTP:{Address:0.0.0.0,Port:5000,%s}%s}}" % (stamp(h), level, t, SENT)

if kind == "cfg":
    mode = E("CFG", "ok")
    D = "1800000000000"; OLD = "60000000000"
    plan = {
        "ok": [(40, D, D)],
        "none": [],
        "mismatch_read": [(40, OLD, D)],
        "mismatch_write": [(40, D, OLD)],
        "unparse": [(40, None, None)],
        "multi_ok": [(150, D, D), (100, D, D), (40, D, D)],
        "older_bad": [(100, OLD, OLD), (40, D, D)],
        "older_bad_outside": [(24 * 20, OLD, OLD), (40, D, D)],
        "newest_bad": [(100, D, D), (40, OLD, OLD)],
        "aged_ok": [(24 * 15, D, D)],
        "forged": [(40, OLD, OLD)],
        "ua_forged": [(40, OLD, OLD)],
        "forged_only": [],
        "otherhost": [],
    }[mode]
    for h, r, w in plan:
        emit(h, cfgrow(h, r, w))
    if mode == "forged":
        # a webhook receipt quoting a (sanitized) config line, NEWER than the real boot line
        emit(5, "GITHUB_WEBHOOK_RECEIPT caller:api body=" + cfgrow(5, D, D, pfx="").replace(PFX, ""))
    if mode == "ua_forged":
        # a PINNED SOLEUR_ZOT_LOG upload row whose client-controlled User-Agent quotes a config line, NEWER
        # than the real 60 s boot line: the envelope pin alone cannot reject it, only the row-shape check can
        emit(5, uprow(5, "GET", "200", "1s", 960, ua=cfgrow(5, D, D, pfx="")))
    if mode == "forged_only":
        emit(5, "GITHUB_WEBHOOK_RECEIPT caller:api body=" + cfgrow(5, D, D, pfx=""))
    if mode == "otherhost":
        emit(5, cfgrow(5, D, D, pfx="SOLEUR_ZOT_LOG shipper=zot-log-shipper host=other-host "))
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
        emit(60 + j * 10, "SOLEUR_ZOT_DISK pcent=24 fs_size_gb=59 zot_restarts=0 host=soleur-registry zot_last_err={time:2026-01-01T00:00:00Z,level:error,message:%s}" % errtext(E("ECHO", "eof")))
    er = E("ERRROW", "")
    if er in ("timeout", "eof"):
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:error,message:" + errtext(er) + "}")
    elif er == "webhook_timeout":
        emit(30, "GITHUB_WEBHOOK_RECEIPT caller:api body={level:error,message:" + errtext("timeout") + "}")
    elif er == "other_handler":
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:error,message:read failed,error:read tcp 192.0.2.1:5000: i/o timeout,caller:example/routes.go:1,func:example.(*RouteHandler).GetBlobUpload,goroutine:1}")
    elif er == "warn_level":
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:warn,message:" + errtext("timeout") + "}")
    elif er == "tls_timeout":
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:error,message:unexpected error,error:net/http: TLS handshake timeout,caller:example/routes.go:2078,func:example.(*RouteHandler).PatchBlobUpload,goroutine:1}")
    elif er == "quoted_envelope":
        emit(30, PFX + "{time:2026-01-01T00:00:00Z,level:error,message:upstream said {message:HTTP API,method:PATCH,path:/v2/a/blobs/uploads/b,statusCode:500,latency:30m0s,},error:boom,caller:example/x.go:1,func:example.Other,goroutine:1}")
    for f in [x for x in E("FORGE", "").split(",") if x]:
        for j in range(3):
            h = 20 + j
            if f == "webhook":
                emit(h, "GITHUB_WEBHOOK_RECEIPT caller:api quoting " + uprow(h, "PATCH", "202", "1s", 800 + j))
            elif f == "webhook_syntax":
                emit(h, "GITHUB_WEBHOOK_RECEIPT caller:api body=syntax error near blobs/uploads Code: 62 DB::Exception")
            elif f == "hdr_get":
                up(h, "GET", "200", "1s", 900 + j, ua="x,method:PATCH,path:/v2/x/blobs/uploads/y,statusCode:202,latency:1s,")
            elif f == "path_get":
                up(h, "GET", "200", "1s", 910 + j, path_tail=",method:PATCH,path:/v2/x/blobs/uploads/y,statusCode:202,latency:1s")
            elif f == "otherhost":
                up(h, "PATCH", "202", "1s", 920 + j, pfx="SOLEUR_ZOT_LOG shipper=zot-log-shipper host=other-host ")
            elif f == "status_forge" and j == 0:
                up(h, "GET", "200", "1s", 930, path_tail="?,statusCode:500,latency:30m0s")
            elif f == "status_mask" and j == 0:
                up(h, "PATCH", "500", "30m0s", 931, path_tail="?,statusCode:202,latency:1s")
            elif f == "user_forge" and j == 0:
                up(h, "GET", "200", "1s", 932, user="x,component:session,clientIP:192.0.2.9:1,method:PUT,path:/v2/a/blobs/uploads/b,statusCode:500,latency:30m0s")
            elif f == "cut5xx" and j == 0:
                # a pinned HTTP API upload row cut by the shipper's length cap before its latency field
                emit(h, uprow(h, "PATCH", "500", "30m0s", 933)[:uprow(h, "PATCH", "500", "30m0s", 933).index(",latency:") + 5])
        if f == "nl_floor":
            # ONE webhook message carrying real line breaks and twelve forged envelope lines
            lines = [uprow(20, "PATCH", "202", "1s", 940 + k) for k in range(12)]
            emit(20, "GITHUB_WEBHOOK_RECEIPT caller:api body=hello\r\n" + "\n".join(lines))
        if f == "dup":
            m = uprow(20, "PATCH", "202", "1s", 950)
            for _ in range(12):
                emit(20, m)
    pad = int(E("RAWN_LOG", "0"))
    for j in range(max(0, pad - len(rows))):
        up(160 + (j % 7000) / 1000.0, "PUT", "201", "2s", 5000 + j)
elif kind == "drop":
    def drop(h, reason, n=5, j=0):
        emit(h, "SOLEUR_ZOT_LOG_DROPPED n=%d interval_s=300 boot_id=00000000-0000-4000-8000-000000000001 seq=%d cum=%d%s%s" % (n, j, j * 5, (" reason=" + reason) if reason else "", SENT))
    for s in [x for x in E("DROPS", "rate_cap:30").split(";") if x.strip()]:
        r, c = s.split(":"); c = int(c)
        for j in range(c):
            drop(spread(c, 1, 160, j), r, n=3 + j, j=j)
    if E("DROPS_QUOTE") == "1":
        emit(25, "GITHUB_WEBHOOK_RECEIPT caller:api quoting SOLEUR_ZOT_LOG_DROPPED n=1 interval_s=300 reason=exempt_cap")
    if E("DROPS_NOREASON") == "1":
        drop(26, "")
    if E("DROPS_UNDECODABLE") == "1":
        emit(27, "", raw="SOLEUR_ZOT_LOG_DROPPED not-json-at-all")
    if E("DROPS_NL") == "1":
        emit(28, "GITHUB_WEBHOOK_RECEIPT caller:api body=x\nSOLEUR_ZOT_LOG_DROPPED n=1 interval_s=300 reason=exempt_cap")
    pad = int(E("RAWN_DROP", "0"))
    for j in range(max(0, pad - len(rows))):
        drop(100 + (j % 6000) / 1000.0, "rate_cap", j=j)
elif kind == "anchor":
    mode = E("ANCHOR", "present")
    if mode == "present":
        for j in range(5): emit(166 - j * 0.5, heartbeat(166, tail=SENT))
    elif mode == "slack": emit(168 - 6 + 90 / 3600.0, heartbeat(0, tail=SENT))
    elif mode == "slack_out": emit(168 - 6.5, heartbeat(0))
    elif mode == "outside":
        for j in range(3): emit(150 - j, heartbeat(0))
    elif mode == "old": emit(180, heartbeat(0))
    elif mode == "contaminated": emit(166, "GITHUB_WEBHOOK_RECEIPT caller:api quoting SOLEUR_ZOT_DISK pcent=1 host=soleur-registry")
    elif mode == "otherhost": emit(166, heartbeat(0, host="other-host"))
    elif mode == "hostforge": emit(166, "SOLEUR_ZOT_DISK pcent=24 host=other-host zot_last_err={host=soleur-registry }")
    elif mode == "nl_forge": emit(166, "GITHUB_WEBHOOK_RECEIPT caller:api body=x\nSOLEUR_ZOT_DISK pcent=1 host=soleur-registry")
elif kind == "tail":
    mode = E("TAIL", "fresh")
    if mode == "fresh":
        for j in range(3): emit(0.1 + j, heartbeat(0, tail=SENT))
    elif mode == "stale": emit(20, heartbeat(0))
    elif mode == "otherhost": emit(0.1, heartbeat(0, host="other-host"))

sd = {"cfg": 30, "log": 7, "drop": 7, "anchor": 7, "tail": 1}[kind]
out = []
for t, line in rows:
    raw = json.loads(line)["raw"]
    if not any(nd in raw for nd in greps): continue
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

DEFAULTS=(CFG=ok "PATCHES=43:202:29s;1:500:5m55s" PUTS=47 POSTS=12 ECHO=eof ECHO_N=2 ERRROW= FORGE= "DROPS=rate_cap:30" DROPS_QUOTE=0 DROPS_NOREASON=0 DROPS_UNDECODABLE=0 DROPS_NL=0 ANCHOR=present TAIL=fresh RAWN_LOG=0 RAWN_DROP=0 CFG_RC=0 LOG_RC=0 DROP_RC=0 ANCHOR_RC=0 TAIL_RC=0 CFG_ERR=0 LOG_ERR=0 DROP_ERR=0 ANCHOR_ERR=0 TAIL_ERR=0 FAIL_STAGE= SENT=0)

run() { # run KEY=VAL ... (later assignments override DEFAULTS; the caller's ZOT_CEILING_* never leak in)
  OUT="$(env -u ZOT_CEILING_DEADLINE_NS -u ZOT_CEILING_WINDOW -u ZOT_CEILING_MIN_DAYS -u ZOT_CEILING_MIN_SAMPLES -u ZOT_CEILING_QUERY \
         "${DEFAULTS[@]}" "$@" ARGLOG="$WORK/argv.log" PATH="$WORK/shim:$PATH" \
         ZOT_CEILING_QUERY="${QOVERRIDE:-$WORK/stub-query}" bash "$PROBE" 2>&1)"
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

# KNOWN-NEGATIVE CONTROL for the two matcher helpers: a wrong rc, a missing substring and a present
# forbidden substring must each MOVE the fail counter. Without this, neutering a matcher keeps ~45 reason
# assertions green (the counter self-test above only exercises pass()/fail()). Undone afterwards.
c0=$cases; p0=$passes; f0=$fails
RC=0; OUT="canned"
expect "control" 1 "" 2>/dev/null
expect "control" 0 "NOT-IN-OUTPUT" 2>/dev/null
expect_not "control" "canned" 2>/dev/null
if (( fails != f0 + 3 || passes != p0 )); then
  printf 'FATAL: expect()/expect_not() did not fail on a known-negative input (fails %d->%d, passes %d->%d)\n' "$f0" "$fails" "$p0" "$passes" >&2
  exit 1
fi
cases=$c0; passes=$p0; fails=$f0

echo "zot-upload-ceiling-7556 harness"

# 1. THE LIVE DEFECT: 43 real PATCH 2xx rows (+1 PATCH 500) plus two heartbeat echoes of a stale EOF error.
run
expect "regression: live-shaped week passes with the real PATCH count" 0 "PASS"
expect "regression: patch_rows is the PATCH 2xx upload count, not the echo count" 0 "patch_rows=43"
expect "regression: verdict names the other-method population" 0 "upload_rows_any=103"
# 2. Heartbeats only: nothing to grade.
run PATCHES= PUTS=0 POSTS=0
expect "heartbeats only is too-few-samples with patch_rows=0" 2 "too-few-samples patch_rows=0"
# 3-6. n1 (error-row corroboration) and the echo that must never feed it.
run ECHO=timeout
expect "a heartbeat echo carrying i/o timeout does not FAIL" 0 "PASS"
run ERRROW=timeout
expect "a SOLEUR_ZOT_LOG level:error PatchBlobUpload i/o timeout row FAILs" 1 "deadline-submode-present"
expect "n1 verdict attributes the row to n1, not n2" 1 "n1_error_rows=1 n2_deadline_5xx=0"
for v in webhook_timeout eof other_handler warn_level tls_timeout quoted_envelope; do
  run ERRROW=$v
  expect "n1 negative (${v}) does not FAIL" 0 "PASS"
done
# 7. n2: a 5xx on an upload row at deadline-shaped latency, any method.
for lat in 30m0s 28m31s 28m30s 1h0m0s; do
  run "PATCHES=43:202:29s;1:500:${lat}"
  expect "n2: PATCH 5xx at ${lat} FAILs" 1 "deadline-submode-present"
done
expect "n2 verdict attributes the row to n2, not n1" 1 "n1_error_rows=0 n2_deadline_5xx=1"
run "PATCHES=43:202:29s;1:500:30m0s:PUT"
expect "n2: PUT 5xx at the deadline FAILs (the deadline is server-wide)" 1 "deadline-submode-present"
for st in 502 504; do
  run "PATCHES=43:202:29s;1:${st}:30m0s"
  expect "n2: a ${st} at the deadline FAILs (any 5xx)" 1 "deadline-submode-present"
done
run "PATCHES=43:202:29s;1:408:30m0s"
expect "n2: a 408 at the deadline is not a 5xx and does not FAIL" 0 "PASS"
for lat in 5m55s 3m31s 28m29s 12ms 250us; do
  run "PATCHES=43:202:29s;1:500:5m55s;1:500:${lat}"
  expect "n2: 5xx at ${lat} is other5xx, not a deadline cut" 0 "other5xx=2"
done
run
expect "PASS text states the EOF scope" 0 "unexpected EOF"
expect "PASS text states n1 is best-effort and the PATCH count is a lower bound" 0 "lower bound"
expect "PASS text states DELIVERY is the causal evidence" 0 "tripwire"
run "PATCHES=40:202:29s;3:202:90s;1:500:5m55s"
expect "uploads that survived past the old 60 s ceiling are counted (long_ok)" 0 "long_ok=3"
# 8. unparseable latency, alone and beside a genuine cut.
run "PATCHES=43:202:29s;1:500:abc"
expect "an unparseable 5xx latency is TRANSIENT upload-rows-unparseable" 2 "upload-rows-unparseable"
run "PATCHES=43:202:29s;1:500:abc;1:500:30m0s"
expect "an unparseable 5xx beside a genuine cut still FAILs" 1 "deadline-submode-present"
# 9-10. FAIL precedes the floor, the truncation arm, the drop guard and the anchor.
run "PATCHES=3:202:5s;1:500:30m0s" PUTS=0 POSTS=0
expect "a finding with only 3 PATCH rows FAILs (FAIL precedes the floor)" 1 "deadline-submode-present"
run "PATCHES=43:202:29s;1:500:30m0s" RAWN_LOG=5000
expect "a finding on a full (truncated) page still FAILs" 1 "deadline-submode-present"
run "PATCHES=43:202:29s;1:500:30m0s" "DROPS=rate_cap:9;exempt_cap:1"
expect "a finding beside an exempt-lane drop still FAILs (FAIL precedes the drop guard)" 1 "deadline-submode-present"
run "PATCHES=43:202:29s;1:500:30m0s" ANCHOR=absent
expect "a finding beside a missing anchor still FAILs (FAIL precedes the coverage guard)" 1 "deadline-submode-present"
# 11. floor boundary.
run "PATCHES=11:202:5s" PUTS=0 POSTS=0
expect "floor: 11 PATCH rows is too-few-samples" 2 "too-few-samples"
run "PATCHES=12:202:5s" PUTS=0 POSTS=0
expect "floor: exactly 12 PATCH rows passes" 0 "patch_rows=12"
run "PATCHES=12:401:1s" PUTS=0 POSTS=0
expect "floor: PATCH rows that were refused (401) are not real uploads" 2 "patch_rows=0"
run "PATCHES=1:202:5s" PUTS=0 POSTS=0 FORGE=dup
expect "floor: twelve exact-duplicate rows (a shipper replay) count once (1 real + 1 deduplicated = 2)" 2 "patch_rows=2"
# 12. truncation boundary on the uploads read.
run RAWN_LOG=5000
expect "uploads read: a full 5000-row page is query-truncated-log" 2 "query-truncated-log"
run RAWN_LOG=4999
expect "uploads read: 4999 rows is graded" 0 "PASS"
# 13. exempt-lane drop guard: benign is an allow-list of one.
run "DROPS=rate_cap:9;exempt_cap:1"
expect "drops: an exempt_cap row blocks PASS" 2 "exempt-lane-dropped"
for r in redact_failed sanitized_empty cursor_invalidated new_cause rate_capped; do
  run "DROPS=rate_cap:9;${r}:1"
  expect "drops: reason ${r} blocks PASS" 2 "exempt-lane-dropped"
done
run "DROPS=rate_cap:9" DROPS_NOREASON=1
expect "drops: a pinned row with no parseable reason blocks PASS" 2 "exempt-lane-dropped"
run DROPS_QUOTE=1
expect "drops: a webhook row quoting reason=exempt_cap is ignored" 0 "PASS"
run DROPS_NL=1
expect "drops: a line break inside a webhook message does not forge a drop row" 0 "PASS"
run RAWN_DROP=20000
expect "dropped read: a full 20000-row page is query-truncated-dropped" 2 "query-truncated-dropped"
run RAWN_DROP=19999
expect "dropped read: 19999 rows is graded" 0 "PASS"
run DROP_RC=2
expect "dropped read: nonzero rc is query-failed-dropped" 2 "query-failed-dropped"
run DROP_ERR=1
expect "dropped read: an error payload on rc 0 is query-error-payload-dropped" 2 "query-error-payload-dropped"
run DROP_ERR=json
expect "dropped read: a JSON object without dt and raw is an error payload, not zero drops" 2 "query-error-payload-dropped"
run DROPS_UNDECODABLE=1
expect "dropped read: a row that does not decode is dropped-undecodable, never a clean guard" 2 "dropped-undecodable"
run "DROPS=rate_cap:0"
expect "dropped read: an empty page is a clean guard (no drops is the common case)" 0 "PASS"
# 14. coverage at both ends of the window.
run ANCHOR=absent
expect "anchor: no heartbeat in the window start slack is retention-shorter-than-window" 2 "retention-shorter-than-window anchor_rows=0"
run ANCHOR=contaminated
expect "anchor: a webhook row quoting the heartbeat does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=nl_forge
expect "anchor: a line break inside a webhook message does not forge a heartbeat" 2 "retention-shorter-than-window"
run ANCHOR=outside
expect "anchor: a heartbeat only outside [start, start+6h] does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=slack_out
expect "anchor: a heartbeat just past start+6h does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=otherhost
expect "anchor: another host's heartbeat does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=hostforge
expect "anchor: host= quoted inside the free-text tail does not satisfy it" 2 "retention-shorter-than-window"
run ANCHOR=slack
expect "anchor: a heartbeat just inside the slack satisfies it" 0 "PASS"
run ANCHOR_RC=2
expect "anchor read: nonzero rc is query-failed-anchor" 2 "query-failed-anchor"
run ANCHOR_ERR=1
expect "anchor read: an error payload on rc 0 is query-error-payload-anchor" 2 "query-error-payload-anchor"
run TAIL=stale
expect "tail: no heartbeat in the last 12h is heartbeat-stale" 2 "heartbeat-stale"
run TAIL=absent
expect "tail: no heartbeat at all in the last day is heartbeat-stale" 2 "heartbeat-stale"
run TAIL=otherhost
expect "tail: another host's heartbeat does not satisfy it" 2 "heartbeat-stale"
run TAIL_RC=2
expect "tail read: nonzero rc is query-failed-tail" 2 "query-failed-tail"
run TAIL_ERR=1
expect "tail read: an error payload on rc 0 is query-error-payload-tail" 2 "query-error-payload-tail"
# 15. delivery: the newest start, every start in the window, and forged config rows.
run CFG=multi_ok
expect "delivery: several starts in the window that all carry the deadlines pass" 0 "config_starts=3"
run CFG=older_bad
expect "delivery: an in-window start that predates the delivery is window-spans-pre-delivery-start" 2 "window-spans-pre-delivery-start older_starts=1"
run CFG=older_bad_outside
expect "delivery: a pre-delivery start older than the window does not block" 0 "PASS"
run CFG=newest_bad
expect "delivery: the NEWEST start decides FAIL, not the oldest" 1 "deadline-mismatch"
run CFG=aged_ok
expect "delivery: a long-lived host whose start aged out of the window still verifies (30d lookback)" 0 "PASS"
run CFG=forged
expect "delivery: a newer webhook row quoting the config cannot spoof a host still on 60 s" 1 "deadline-mismatch"
run CFG=ua_forged
expect "delivery: a pinned upload row whose User-Agent quotes the config cannot spoof a host still on 60 s" 1 "deadline-mismatch"
run CFG=forged_only
expect "delivery: a webhook row quoting the config is not a config line" 2 "no-config-line"
run CFG=otherhost
expect "delivery: another host's config row is not a config line" 2 "no-config-line"
run CFG=unparse
expect "reason deadlines-unparseable (newest start lacks the timeouts)" 2 "deadlines-unparseable"
# 16. forgery: a client-controlled field must not add to or erase from any count.
run "PATCHES=11:202:5s" PUTS=0 POSTS=0 FORGE=hdr_get,webhook,otherhost
expect "forgery: header, webhook-quote and other-host rows add nothing (11 stays 11)" 2 "patch_rows=11"
run "PATCHES=11:202:5s" PUTS=0 POSTS=0 FORGE=path_get
expect "forgery: a path carrying a fake method/statusCode tail is unparseable, never counted" 2 "upload-rows-unparseable"
run "PATCHES=11:202:5s" PUTS=0 POSTS=0 FORGE=nl_floor
expect "forgery: twelve envelope lines inside one webhook message add nothing" 2 "patch_rows=11"
run FORGE=status_forge
expect "forgery: a client path carrying statusCode/latency is unparseable, never a forged FAIL" 2 "upload-rows-unparseable"
run FORGE=status_mask
expect "forgery: a real 30m cut whose path carries a fake 202 is unparseable, never a PASS" 2 "upload-rows-unparseable"
run FORGE=user_forge
expect "forgery: a username carrying server fields is unparseable, never a forged FAIL" 2 "upload-rows-unparseable"
run FORGE=cut5xx
expect "a pinned upload row cut before its latency cannot be graded (TRANSIENT, not a pass)" 2 "upload-rows-unparseable"
run FORGE=webhook_syntax
expect "a webhook row quoting 'syntax error' does not wedge the probe" 0 "PASS"
# 17. a crashed python stage must never fold to a clean state.
run FAIL_STAGE=log
expect "a crashed upload classifier is TRANSIENT classifier-failed stage=log" 2 "classifier-failed classifier_rc=3 stage=log"
run FAIL_STAGE=dropped
expect "a crashed drop classifier is TRANSIENT classifier-failed stage=dropped" 2 "stage=dropped"
run FAIL_STAGE=config
expect "a crashed config classifier is TRANSIENT classifier-failed stage=config" 2 "stage=config"
run FAIL_STAGE=heartbeat
expect "a crashed heartbeat classifier is TRANSIENT classifier-failed stage=anchor" 2 "stage=anchor"
run FAIL_STAGE=decode
expect "a crashed row decoder is TRANSIENT decoder-failed" 2 "decoder-failed stage=log"
run FAIL_STAGE=until
expect "a failed anchor-bound computation is TRANSIENT anchor-bound-failed" 2 "anchor-bound-failed"
# 18. every other distinct reason.
QOVERRIDE=/nonexistent/stub run
expect "reason query-not-executable" 2 "query-not-executable"
run ZOT_CEILING_WINDOW=3d
expect "reason window-too-short" 2 "window-too-short"
run CFG_RC=3
expect "reason query-failed-config (rc 3 names the credential guard)" 2 "query-failed-config query_rc=3"
expect "rc 3 prints the credential-guard hint" 2 "credential guard"
run CFG_ERR=1
expect "reason query-error-payload-config" 2 "query-error-payload-config"
run CFG=none
expect "reason no-config-line" 2 "no-config-line"
run CFG=mismatch_read
expect "reason deadline-mismatch is a FAIL (rc 1)" 1 "deadline-mismatch"
run CFG=mismatch_write
expect "one mismatched deadline is also deadline-mismatch" 1 "deadline-mismatch"
run LOG_RC=2
expect "reason query-failed-log" 2 "query-failed-log"
run LOG_ERR=1
expect "reason query-error-payload-log" 2 "query-error-payload-log"
cases=$((cases + 1))
if grep -q 'span-underivable\|span-arithmetic-failed' "$PROBE"; then fail "the deleted span guard's reasons must not linger in the probe"; else pass "span-underivable and span-arithmetic-failed are gone with the span guard"; fi
# 19. must-PASS inputs that are not the canonical.
run REPO=other-org/deeper/path/image USERNAME=other-user
expect "a different repo depth and username still count" 0 "patch_rows=43"
run "PATCHES=12:202:0s" PUTS=0 POSTS=0
expect "a PATCH at latency 0s counts" 0 "patch_rows=12"
# 20. the output never carries row text or the query tool's stderr (the sweeper posts it on a public issue)
# and each variant must have reached the branch it is named for, or the leak check certifies nothing.
sent_case() { # label rc reason KEY=VAL...
  local l="$1" wrc="$2" wsub="$3"; shift 3
  run SENT=1 "$@"
  expect "branch reached (${l})" "$wrc" "$wsub"
  expect_not "no fixture row text reaches the output (${l})" "SENTINEL_7556_ROW_TEXT"
}
sent_case "pass" 0 "PASS"
sent_case "fail n1" 1 "deadline-submode-present" ERRROW=timeout
sent_case "anchor" 2 "retention-shorter-than-window" ANCHOR=absent
sent_case "tail" 2 "heartbeat-stale" TAIL=stale
sent_case "drops" 2 "exempt-lane-dropped" "DROPS=rate_cap:9;exempt_cap:1"
sent_case "unparse" 2 "upload-rows-unparseable" "PATCHES=43:202:29s;1:500:abc"
sent_case "floor" 2 "too-few-samples" "PATCHES=3:202:5s" PUTS=0 POSTS=0
sent_case "truncation" 2 "query-truncated-log" RAWN_LOG=5000
sent_case "config mismatch" 1 "deadline-mismatch" CFG=mismatch_read
sent_case "no config" 2 "no-config-line" CFG=none
sent_case "older start" 2 "window-spans-pre-delivery-start" CFG=older_bad
run CFG_RC=3
expect_not "the query tool's stderr (it can name the warehouse host) never reaches the output" "SENTINEL_HOST_7556"
# 21. argv fidelity is enforced by the stub (exit 64 -> query-failed-*): assert THIS run issued all five reads.
: > "$WORK/argv.log"
run
cases=$((cases + 1))
nreads=$(grep -c . "$WORK/argv.log" || true)
kinds=0
for pat in "--grep configuration settings" "--grep blobs/uploads" "--grep SOLEUR_ZOT_LOG_DROPPED" "--until" "--since 1d"; do
  grep -qF -- "$pat" "$WORK/argv.log" && kinds=$((kinds + 1))
done
if [[ "${nreads:-0}" -eq 5 && "$kinds" -eq 5 ]]; then pass "the probe issued its config, uploads, dropped, anchor and tail reads"; else fail "expected exactly 5 reads covering all 5 kinds in the argv log (reads=${nreads:-0} kinds=${kinds})"; fi

# FLOORS AND CONSERVATION (ADR-193): reported with printf + exit, never through the helpers they back-stop.
# MIN_CASES is a literal; raise it in the SAME edit that adds a row.
MIN_CASES=135
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
