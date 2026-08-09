#!/usr/bin/env bash
#
# Test suite for scripts/zot-inventory.sh — the READ-ONLY zot blob inventory lever (#7278).
#
# WHY A RECORDING ORIGIN AND NOT STUBS (F3). The two properties this script must hold —
# "it never issues a write-shaped verb" and "it talks to exactly two destinations" — are
# properties of the BYTES ON THE WIRE, not of the source text. A source-level grep proves
# only that no write verb appears in the file this test read; it says nothing about what a
# helper, a redirect follow, or a curl config file actually sent. So the fixture is a real
# HTTP server bound on 127.0.0.1:5000 (the port the cloudflared bridge binds in production)
# that RECORDS every request line and 405s anything that is not GET or HEAD, and the same
# server doubles as the arithmetic fixture. The source-level deny-list below is kept, and is
# explicitly LABELLED A SUPPLEMENT: it covers branches the recording origin can never reach.
#
# WHAT IS NOT ENFORCED HERE, stated so the next reader does not over-read the result:
# process-boundary egress allow-listing (a network namespace with a default-deny rule) was
# considered and rejected as out of scope for a shell unit suite — it needs privileges CI
# does not grant. This is a TEST, not an enforcement mechanism. What it does prove is that
# on the exercised paths, every recorded destination is one of the two allowed ones and the
# minimum-cardinality floor was met first (zero recorded calls satisfies every negative
# assertion, and zero is exactly what a premature exit produces).
#
# Run: bash tests/scripts/test-zot-inventory.sh
set -uo pipefail

# A direct invocation inherits a machine-global /tmp that is shared with every parallel
# worktree and, on this fleet, is a 4 GiB tmpfs. The sandbox below writes manifest bodies and
# mutant copies; /var/tmp is disk-backed. scripts/test-all.sh already defaults this, but a
# direct `bash tests/scripts/test-zot-inventory.sh` does not.
export TMPDIR="${TMPDIR:-/var/tmp}"

# LOCALE PIN. Every numeric comparison below is against a hand-computed literal, and bash's
# [[ =~ ]] uses the locale's collation for [0-9] — under a UTF-8 locale the FULLWIDTH digits
# match it, so a mangled field could compare equal to a literal it does not equal.
export LC_ALL=C

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
INV="${ROOT}/scripts/zot-inventory.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '       %s\n' "$2" >&2
  return 0
}

# A skip is not a pass, and under CI it is not even a skip.
_skip() {
  if [ "${CI:-}" = "true" ]; then
    printf '%s — and CI=true, so this is a FAILURE: the runner must provide this dependency.\n' "$1" >&2
    exit 1
  fi
  printf '%s\n' "$1" >&2
  exit 0
}

for dep in python3 jq curl; do
  command -v "$dep" >/dev/null 2>&1 || _skip "test-zot-inventory: SKIP — $dep is not on PATH"
done
# Resolved ABSOLUTELY and up front. Every script invocation below is bounded by it, so a
# hung curl against the fixture cannot wedge CI.
TIMEOUT_BIN="$(command -v timeout || true)"
[ -n "$TIMEOUT_BIN" ] || _skip "test-zot-inventory: SKIP — coreutils timeout is not on PATH"

[ -f "$INV" ] || { echo "test-zot-inventory: SETUP FAIL — $INV does not exist" >&2; exit 2; }

TMP="$(mktemp -d)"
[ -d "$TMP" ] || { echo "test-zot-inventory: SETUP FAIL — mktemp -d produced no directory" >&2; exit 2; }
cleanup() {
  local p
  for p in ${REG_PID:-} ${ING_PID:-} ${CAN_PID:-}; do kill "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

FIXTURE="$TMP/fixture.json"
REQLOG="$TMP/registry-requests.log"
INGEST_REQ="$TMP/ingest-requests.log"
INGEST_BODY="$TMP/ingest-requests.log.body"
CANARY_REQ="$TMP/canary-requests.log"
CANARY_BODY="$TMP/canary-requests.log.body"
OUT="$TMP/out.txt"
ERR="$TMP/err.txt"
: > "$REQLOG"; : > "$INGEST_REQ"; : > "$INGEST_BODY"; : > "$CANARY_REQ"; : > "$CANARY_BODY"

# ---------------------------------------------------------------------------------
# The recording origin.
# ---------------------------------------------------------------------------------
cat > "$TMP/server.py" <<'PY'
import json, os, sys, threading
from http.server import BaseHTTPRequestHandler
from socketserver import ThreadingTCPServer
from urllib.parse import urlparse, parse_qs

FIX, RECLOG, PORTFILE, ROLE, PORT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
LOCK = threading.Lock()


def build_manifest(spec):
    body = {"schemaVersion": 2,
            "mediaType": spec.get("mediaType", "application/vnd.oci.image.manifest.v1+json")}
    if "config" in spec:
        body["config"] = spec["config"]
    if "layers" in spec:
        body["layers"] = spec["layers"]
    if "manifests" in spec:
        body["manifests"] = spec["manifests"]
    raw = json.dumps(body, separators=(",", ":")).encode()
    target = spec.get("size")
    if target:
        body["_pad"] = ""
        raw = json.dumps(body, separators=(",", ":")).encode()
        need = target - len(raw)
        if need < 0:
            raise ValueError("fixture size %d is below the minimal body %d" % (target, len(raw)))
        body["_pad"] = "x" * need
        raw = json.dumps(body, separators=(",", ":")).encode()
    return raw


class H(BaseHTTPRequestHandler):
    # HTTP/1.0 so every response closes its connection: keep-alive against a threaded
    # fixture makes the recorded ordering depend on connection reuse.
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    # The recorded line is exactly `"%s %s" % (command, path)`. Verb confinement is asserted
    # against this file, so it must carry the method verbatim and nothing else.
    def _rec(self):
        with LOCK:
            with open(RECLOG, "a") as f:
                f.write("%s %s\n" % (self.command, self.path))

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def _send(self, code, payload=b"", ctype="application/json", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    # --- fixture state -----------------------------------------------------------
    def _fx(self):
        with open(FIX) as f:
            fx = json.load(f)
        gen = fx.get("generation", 0)
        if getattr(self.server, "gen", None) != gen:
            self.server.gen = gen
            self.server.counts = {}
        return fx

    def _fail_now(self, fx, key):
        if key in fx.get("fail_always", []):
            return True
        if key in fx.get("fail_once", []):
            with LOCK:
                n = self.server.counts.get(key, 0) + 1
                self.server.counts[key] = n
            return n == 1
        return False

    # --- verbs -------------------------------------------------------------------
    def do_GET(self):
        self._rec()
        if ROLE == "registry":
            self._registry()
        else:
            self._send(405, b'{"error":"only POST is accepted here"}')

    def do_HEAD(self):
        self._rec()
        if ROLE == "registry":
            self._registry()
        else:
            self._send(405, b"")

    def do_POST(self):
        self._rec()
        body = self._body()
        if ROLE == "registry":
            # A write-shaped verb against the registry origin is refused AT THE WIRE.
            self._send(405, b'{"error":"read-only origin"}')
            return
        with LOCK:
            with open(RECLOG + ".body", "a") as f:
                # One captured payload per line. Trailing whitespace is stripped (the
                # producer's JSON ends with a newline) and any interior newline is escaped,
                # so a multi-line payload stays visible as one record rather than silently
                # becoming several.
                f.write(body.decode("utf-8", "replace").strip().replace("\n", "\\n") + "\n")
        self._send(202, b"")

    def _refuse(self):
        self._rec()
        self._send(405, b'{"error":"read-only origin"}')

    do_PUT = _refuse
    do_PATCH = _refuse
    do_DELETE = _refuse
    do_OPTIONS = _refuse

    # --- the registry surface ----------------------------------------------------
    def _registry(self):
        fx = self._fx()
        u = urlparse(self.path)
        p = u.path
        q = parse_qs(u.query)
        page = int(q.get("p", ["0"])[0])

        if p == "/v2/":
            self._send(fx.get("v2_code", 200), b"{}")
            return

        if p == "/v2/_catalog":
            if self._fail_now(fx, "catalog"):
                self._send(500, b'{"errors":[{"code":"UNAVAILABLE"}]}')
                return
            code = fx.get("catalog_code", 200)
            if code != 200:
                self._send(code, b'{"errors":[{"code":"DENIED"}]}')
                return
            pages = fx.get("catalog", [{"repositories": [], "next": None}])
            pg = pages[min(page, len(pages) - 1)]
            extra = {}
            # `link_raw` emits the Link header VERBATIM. Without it every fixture Link is a
            # rooted path built by format string, so the non-rooted-target rejection in
            # link_next() had no reachable input class — the exact gap the guard's own
            # comment predicted, and the reason deleting that guard left the suite 125/0.
            if pg.get("link_raw") is not None:
                extra["Link"] = pg["link_raw"]
            elif pg.get("next") is not None:
                extra["Link"] = '</v2/_catalog?p=%d>; rel="next"' % pg["next"]
            self._send(200, json.dumps({"repositories": pg["repositories"]}).encode(), extra=extra)
            return

        if p.startswith("/v2/") and p.endswith("/tags/list"):
            repo = p[len("/v2/"):-len("/tags/list")]
            spec = fx.get("tags", {}).get(repo)
            if spec is None:
                self._send(404, b'{"errors":[{"code":"NAME_UNKNOWN"}]}')
                return
            if self._fail_now(fx, "tags:" + repo):
                self._send(500, b'{"errors":[{"code":"UNAVAILABLE"}]}')
                return
            code = spec.get("code", 200)
            if code != 200:
                self._send(code, b'{"errors":[{"code":"DENIED"}]}')
                return
            pages = spec.get("pages", [{"tags": [], "next": None}])
            pg = pages[min(page, len(pages) - 1)]
            extra = {}
            # See the catalog handler's note on `link_raw`.
            if pg.get("link_raw") is not None:
                extra["Link"] = pg["link_raw"]
            elif pg.get("next") is not None:
                extra["Link"] = '</v2/%s/tags/list?p=%d>; rel="next"' % (repo, pg["next"])
            self._send(200, json.dumps({"name": repo, "tags": pg["tags"]}).encode(), extra=extra)
            return

        if p.startswith("/v2/") and "/manifests/" in p:
            repo, ref = p[len("/v2/"):].rsplit("/manifests/", 1)
            key = "%s/%s" % (repo, ref)
            spec = fx.get("manifests", {}).get(key)
            if spec is None:
                self._send(404, b'{"errors":[{"code":"MANIFEST_UNKNOWN"}]}')
                return
            if self._fail_now(fx, "manifest:" + key):
                self._send(500, b'{"errors":[{"code":"UNAVAILABLE"}]}')
                return
            try:
                payload = build_manifest(spec)
            except ValueError as exc:
                self._send(500, str(exc).encode())
                return
            self._send(spec.get("code", 200), payload,
                       ctype=spec.get("mediaType", "application/vnd.oci.image.manifest.v1+json"),
                       extra={"Docker-Content-Digest": spec["digest"]})
            return

        if p.startswith("/v2/") and "/referrers/" in p:
            repo, dig = p[len("/v2/"):].rsplit("/referrers/", 1)
            key = "%s/%s" % (repo, dig)
            spec = fx.get("referrers", {}).get(key, fx.get("referrers_default",
                                                           {"code": 200, "manifests": []}))
            if self._fail_now(fx, "referrers:" + key):
                self._send(500, b'{"errors":[{"code":"UNAVAILABLE"}]}')
                return
            code = spec.get("code", 200)
            if code != 200:
                self._send(code, b'{"errors":[{"code":"DENIED"}]}')
                return
            self._send(200, json.dumps({
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "manifests": spec.get("manifests", []),
            }).encode())
            return

        self._send(404, b'{"errors":[{"code":"UNSUPPORTED"}]}')


ThreadingTCPServer.allow_reuse_address = True
ThreadingTCPServer.daemon_threads = True
httpd = ThreadingTCPServer(("127.0.0.1", PORT), H)
httpd.gen = None
httpd.counts = {}
with open(PORTFILE, "w") as f:
    f.write(str(httpd.server_address[1]))
httpd.serve_forever()
PY

start_server() {  # $1 reclog, $2 portfile, $3 role, $4 port -> echoes pid
  python3 "$TMP/server.py" "$FIXTURE" "$1" "$2" "$3" "$4" >>"$TMP/server.err" 2>&1 &
  echo $!
}
wait_port() {  # $1 portfile
  local i
  for i in $(seq 1 100); do [ -s "$1" ] && return 0; sleep 0.1; done
  return 1
}

# A minimal fixture must exist before the servers start (they read it per request).
printf '{"generation":0}' > "$FIXTURE"

# The registry origin is pinned to 127.0.0.1:5000 — the port cloudflared binds in
# production, so the script under test needs no port rewriting to be exercised. A harness
# that cannot bind it must exit 2, never continue against a stale or foreign listener.
REG_PID="$(start_server "$REQLOG" "$TMP/reg.port" registry 5000)"
if ! wait_port "$TMP/reg.port"; then
  echo "test-zot-inventory: SETUP FAIL — could not bind the recording origin on 127.0.0.1:5000." >&2
  echo "                    Something else holds that port; this suite will not run against it." >&2
  sed -n '1,20p' "$TMP/server.err" >&2 2>/dev/null
  exit 2
fi
ING_PID="$(start_server "$INGEST_REQ" "$TMP/ing.port" ingest 0)"
wait_port "$TMP/ing.port" || { echo "test-zot-inventory: SETUP FAIL — ingest fixture did not start" >&2; exit 2; }
CAN_PID="$(start_server "$CANARY_REQ" "$TMP/can.port" ingest 0)"
wait_port "$TMP/can.port" || { echo "test-zot-inventory: SETUP FAIL — canary fixture did not start" >&2; exit 2; }

ING_PORT="$(cat "$TMP/ing.port")"
CAN_PORT="$(cat "$TMP/can.port")"
REGISTRY_URL="http://127.0.0.1:5000"
INGEST_URL="http://127.0.0.1:${ING_PORT}/"
CANARY_URL="http://127.0.0.1:${CAN_PORT}/"

# ---------------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------------
GEN=0
write_fixture() {  # stdin = python that assigns `fx`
  GEN=$((GEN + 1))
  python3 - "$FIXTURE" "$GEN" <<PY
import json, sys
$(cat)
fx["generation"] = int(sys.argv[2])
with open(sys.argv[1], "w") as f:
    json.dump(fx, f)
PY
}

PULL_SENTINEL='pullsentinel-Xq7x2LmZ0pQvR8nT4wYb'
BS_SENTINEL='bssentinel-Zt5w9QnB2xLmK7vR4pYd'
RUN_ID=17772222
COMMIT_SHA=1f2e3d4c5b6a798877665544332211aabbccddee

RC=0
run_inv() {  # $1 = script path; $2.. = extra env assignments (they win — env is left-to-right)
  local script="$1"; shift
  : > "$REQLOG"; : > "$INGEST_REQ"; : > "$INGEST_BODY"; : > "$CANARY_REQ"; : > "$CANARY_BODY"
  env -i \
    PATH="$PATH" HOME="$HOME" LC_ALL=C TMPDIR="$TMPDIR" \
    ZOT_PULL_USER=puller \
    ZOT_PULL_TOKEN="$PULL_SENTINEL" \
    BETTERSTACK_LOGS_TOKEN="$BS_SENTINEL" \
    ZOT_INVENTORY_REGISTRY_URL="$REGISTRY_URL" \
    ZOT_INVENTORY_INGEST_URL="$INGEST_URL" \
    ZOT_INVENTORY_RETRY_SLEEP_S=0 \
    ZOT_INVENTORY_HTTP_TIMEOUT_S=10 \
    GITHUB_RUN_ID="$RUN_ID" \
    GITHUB_SHA="$COMMIT_SHA" \
    ZOT_DISK_PCENT=100 \
    ZOT_DISK_FS_SIZE_GB=59 \
    ZOT_DISK_BOOT_ID=6f1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9 \
    ZOT_DISK_SAMPLE_AGE_S=60 \
    ZOT_RESTARTS_AT_START=15640 \
    ZOT_RESTARTS_AT_END=15640 \
    "$@" \
    "$TIMEOUT_BIN" 120 bash "$script" >"$OUT" 2>"$ERR"
  RC=$?
}

marker() { tail -1 "$INGEST_BODY" 2>/dev/null | jq -r '.message // empty' 2>/dev/null; }
# Field reader. The leading `(^| )` is what keeps `repos=` from matching
# `repos_enumerated=` — a bare `grep repos=` would.
field() { grep -oE "(^| )$1=[^ ]*" <<<"$(marker)" | tail -1 | cut -d= -f2-; }

expect_field() {  # $1 name, $2 want, $3 label
  local got; got="$(field "$1")"
  if [ "$got" = "$2" ]; then pass "$3 ($1=$2)"
  else fail "$3: $1 want='$2' got='$got'" "marker=$(marker)"; fi
}

# ---------------------------------------------------------------------------------
# Digests. Distinct 64-hex values so a size-keyed accumulator cannot pass for a
# digest-keyed one.
# ---------------------------------------------------------------------------------
d() { python3 -c 'import sys; print("sha256:" + (sys.argv[1]*64)[:64])' "$1"; }
M1="$(d 1)"; M2="$(d 2)"; M3="$(d 3)"
C0="$(d c)"; AAAA="$(d a)"; BBBB="$(d b)"; CCCC="$(d e)"

echo "== 1.1.1 / F2 — dedup by DIGEST, hand-computed literals =="
# R_a:t1 -> m1(501), c0(13), aaaa(1000), bbbb(1000)
# R_a:t2 -> m2(502), c0(13), aaaa(1000)
# R_b:t1 -> m3(503), c0(13), aaaa(1000), cccc(7)
# correct 7/3526 · naive-sum 11/5552 · by-size 6/2526 · per-repo 9/4539
# · manifest-self-omitted 4/2020 · config-omitted 6/3513 — no two collide.
dedup_fixture() {
  write_fixture <<PY
M1, M2, M3 = "$M1", "$M2", "$M3"
C0, A, B, C = "$C0", "$AAAA", "$BBBB", "$CCCC"
def cfg(d, s): return {"mediaType": "c", "digest": d, "size": s}
def lay(d, s): return {"mediaType": "l", "digest": d, "size": s}
fx = {
  "catalog": [{"repositories": ["R_a", "R_b"], "next": None}],
  "tags": {
    "R_a": {"pages": [{"tags": ["t1", "t2"], "next": None}]},
    "R_b": {"pages": [{"tags": ["t1"], "next": None}]},
  },
  "manifests": {
    "R_a/t1": {"digest": M1, "size": 501, "config": cfg(C0, 13),
               "layers": [lay(A, 1000), lay(B, 1000)]},
    "R_a/t2": {"digest": M2, "size": 502, "config": cfg(C0, 13),
               "layers": [lay(A, 1000)]},
    "R_b/t1": {"digest": M3, "size": 503, "config": cfg(C0, 13),
               "layers": [lay(A, 1000), lay(C, 7)]},
  },
  "referrers_default": {"code": 200, "manifests": []},
}
PY
}
dedup_fixture
run_inv "$INV"
if [ "$RC" -eq 0 ]; then pass "dedup sweep exits 0"; else fail "dedup sweep rc=$RC" "$(tail -5 "$ERR")"; fi
expect_field unique_blobs 7 "dedup"
expect_field manifest_referenced_bytes 3526 "dedup"
expect_field enumeration_complete true "dedup"
expect_field outcome ok "dedup"
expect_field reason none "dedup"
expect_field repos 2 "dedup"
expect_field repos_enumerated 2 "dedup"
expect_field tags 3 "dedup"
expect_field manifests_fetched 3 "dedup"
expect_field manifest_errors 0 "dedup"
# On mismatch the accumulated digest:size set must be dumped, not just the total: a bare
# total cannot tell WHICH of the six defect shapes produced it.
if grep -qE '^[[:space:]]*sha256:[0-9a-f]{64}:[0-9]+$' "$OUT"; then
  pass "the accumulated digest:size set is dumped on stdout"
else
  fail "no digest:size dump on stdout — a mismatch would report only a total"
fi

echo "== 1.1.2 — index recursion, a child under TWO indexes, a child that is also a tag =="
IDX1="$(d 4)"; IDX2="$(d 5)"; MC1="$(d 6)"; MSH="$(d 7)"
CFGA="$(d 8)"; L1="$(d 9)"; L2="$(d f)"
write_fixture <<PY
IDX1, IDX2, MC1, MSH = "$IDX1", "$IDX2", "$MC1", "$MSH"
CFGA, L1, L2 = "$CFGA", "$L1", "$L2"
IDXT = "application/vnd.oci.image.index.v1+json"
def cfg(d, s): return {"mediaType": "c", "digest": d, "size": s}
def lay(d, s): return {"mediaType": "l", "digest": d, "size": s}
def dsc(d, s): return {"mediaType": "m", "digest": d, "size": s}
mc1 = {"digest": MC1, "size": 420, "config": cfg(CFGA, 11), "layers": [lay(L1, 500)]}
msh = {"digest": MSH, "size": 360, "config": cfg(CFGA, 11), "layers": [lay(L2, 600)]}
fx = {
  "catalog": [{"repositories": ["R_i"], "next": None}],
  "tags": {"R_i": {"pages": [{"tags": ["dup", "idx1", "idx2"], "next": None}]}},
  "manifests": {
    "R_i/dup": msh,
    "R_i/" + MSH: msh,
    "R_i/idx1": {"digest": IDX1, "size": 400, "mediaType": IDXT,
                 "manifests": [dsc(MC1, 420), dsc(MSH, 360)]},
    "R_i/idx2": {"digest": IDX2, "size": 350, "mediaType": IDXT,
                 "manifests": [dsc(MSH, 360)]},
    "R_i/" + MC1: mc1,
  },
  "referrers_default": {"code": 200, "manifests": []},
}
PY
run_inv "$INV" ZOT_INVENTORY_REPO_FLOOR=1
expect_field unique_blobs 7 "index recursion"
expect_field manifest_referenced_bytes 2641 "index recursion"
# 4, not 6: the shared child is fetched once. A non-memoizing recursion fetches it under
# `dup`, under idx1 and under idx2.
expect_field manifests_fetched 4 "index recursion memoizes the shared child"
expect_field enumeration_complete true "index recursion"

echo "== 1.1.3 — partial sweep: a manifest that fails after retry =="
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["fail_always"] = ["manifest:R_b/t1"]
fx["generation"] += 100
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
if [ "$RC" -eq 1 ]; then pass "partial sweep exits 1"; else fail "partial sweep rc=$RC (want 1)" "$(tail -3 "$ERR")"; fi
expect_field manifest_errors 1 "partial"
expect_field enumeration_complete false "partial"
expect_field outcome partial "partial"
expect_field reason manifest_incomplete "partial"

echo "== 1.1.4 — catalog unreadable (non-2xx) =="
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["catalog_code"] = 403
fx["generation"] += 200
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
expect_field reason catalog_unreadable "catalog non-2xx"
expect_field outcome failed "catalog non-2xx"
expect_field catalog_errors 1 "catalog non-2xx"
if [ "$RC" -ne 0 ]; then pass "catalog non-2xx exits non-zero"; else fail "catalog non-2xx exited 0"; fi

echo "== 1.1.4b / V2 — catalog 2xx-EMPTY and catalog UNDERCOUNT =="
write_fixture <<'PY'
fx = {"catalog": [{"repositories": [], "next": None}], "tags": {}, "manifests": {}}
PY
run_inv "$INV"
expect_field reason catalog_empty "catalog 2xx-empty"
expect_field enumeration_complete false "catalog 2xx-empty"
# The whole point: a permissions failure that returns 200 [] must NOT be dressed up as a
# complete enumeration with a 59 GB delta.
if [ "$(field enumeration_complete)" = "true" ]; then
  fail "catalog 2xx-empty: enumeration_complete=true — the script manufactured a conclusion from an empty catalog"
else
  pass "catalog 2xx-empty never yields enumeration_complete=true"
fi
if [ "$RC" -ne 0 ]; then pass "catalog 2xx-empty exits non-zero"; else fail "catalog 2xx-empty exited 0"; fi

write_fixture <<PY
M1, C0, A = "$M1", "$C0", "$AAAA"
fx = {
  "catalog": [{"repositories": ["R_a"], "next": None}],
  "tags": {"R_a": {"pages": [{"tags": ["t1"], "next": None}]}},
  "manifests": {"R_a/t1": {"digest": M1, "size": 501,
                           "config": {"mediaType": "c", "digest": C0, "size": 13},
                           "layers": [{"mediaType": "l", "digest": A, "size": 1000}]}},
  "referrers_default": {"code": 200, "manifests": []},
}
PY
run_inv "$INV"
expect_field reason catalog_undercount "catalog below the measured floor of 2"
expect_field enumeration_complete false "catalog undercount"
expect_field repos 1 "catalog undercount"

echo "== 1.1.4c / A4 — an unfollowed Link header =="
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["catalog"] = [{"repositories": ["R_a", "R_b"], "next": 1},
                 {"repositories": [], "next": None}]
fx["generation"] += 300
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV" ZOT_INVENTORY_MAX_PAGES=1
expect_field enumeration_complete false "unfollowed Link"
expect_field reason link_unfollowed "unfollowed Link"
# Positive control for the same fixture: with the page budget raised, the Link IS followed
# and completeness is restored. Without this, "always false" would pass the arm above.
run_inv "$INV" ZOT_INVENTORY_MAX_PAGES=10
expect_field enumeration_complete true "a FOLLOWED Link restores completeness"

echo "== 1.1.4d / A4b — a NON-ROOTED Link target is refused AND counted =="
# The rejection arm of link_next(). Distinct from A4 above, which exercises the MAX_PAGES
# budget arm: that one increments in the caller's shell and always worked. This one is the
# arm the guard was ADDED for, and it had no reachable fixture until `link_raw` existed.
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
# curl parses everything before `@` as userinfo, so this resolves OFF-BOX. It is also the
# shape a spec-legal ABSOLUTE Link takes, which needs no attacker at all.
fx["catalog"] = [{"repositories": ["R_a", "R_b"],
                  "link_raw": '<@127.0.0.1:1/v2/_catalog>; rel="next"'}]
fx["generation"] += 310
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
expect_field enumeration_complete false "a refused Link target is an INCOMPLETE sweep"
expect_field reason link_unfollowed "a refused Link target must reach the reason vocabulary"
expect_field link_unfollowed 1 "the refusal must be COUNTED, not merely printed"
if [ "$(grep -cE '.' "$CANARY_REQ" || true)" -eq 0 ]; then
  pass "the refused Link reached no third-party destination"
else
  fail "a refused Link target still produced an off-box request" "$(head -3 "$CANARY_REQ")"
fi

echo "== 1.1.4e / A4c — paginated content is FLATTENED, not first-page-only =="
# Pins the accumulator, not the counter. The same content as the dedup fixture, split across
# pages: correct flattening must produce byte-identical numbers to the single-page case, so
# a first-page-only regression cannot hide behind "the Link was followed".
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["catalog"] = [{"repositories": ["R_a"], "next": 1},
                 {"repositories": ["R_b"], "next": None}]
fx["tags"]["R_a"] = {"pages": [{"tags": ["t1"], "next": 1},
                               {"tags": ["t2"], "next": None}]}
fx["generation"] += 320
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
expect_field repos 2 "catalog page 2 contributes its repositories"
expect_field tags 3 "tags/list page 2 contributes its tags"
expect_field unique_blobs 7 "paginated sweep sees every blob the single-page sweep sees"
expect_field manifest_referenced_bytes 3526 "paginated byte total equals the single-page total"
expect_field enumeration_complete true "a fully-followed paginated sweep is complete"

echo "== 1.1.5 / V3 — a tags/list that fails after retry =="
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["fail_always"] = ["tags:R_b"]
fx["generation"] += 400
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
expect_field tag_list_errors 1 "tag-list failure"
expect_field repos 2 "tag-list failure"
expect_field repos_enumerated 1 "tag-list failure"
expect_field enumeration_complete false "tag-list failure"
expect_field reason tag_list_incomplete "tag-list failure"

echo "== 1.1.6 — retry positive control =="
dedup_fixture
python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["fail_once"] = ["manifest:R_b/t1", "tags:R_a", "catalog"]
fx["generation"] += 500
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV"
expect_field enumeration_complete true "transient failures that succeed on retry"
expect_field manifest_errors 0 "retry positive control"
expect_field tag_list_errors 0 "retry positive control"
expect_field catalog_errors 0 "retry positive control"
expect_field unique_blobs 7 "retry positive control preserves the arithmetic"
expect_field manifest_referenced_bytes 3526 "retry positive control preserves the arithmetic"

echo "== 1.2a / B2 — origin reachability is adjudicated BEFORE the catalog =="
dedup_fixture
run_inv "$INV" ZOT_INVENTORY_REGISTRY_URL="http://127.0.0.1:1"
expect_field reason origin_unreachable "dead origin"
expect_field outcome failed "dead origin"
expect_field origin_verdict dial_failed "dead origin"
if [ "$(field reason)" = "catalog_unreadable" ]; then
  fail "a transport-layer failure was reported as an application-layer verdict (catalog_unreadable)"
else
  pass "catalog_unreadable is not claimed before the origin is proven to answer"
fi
run_inv "$INV"
expect_field origin_verdict answered "live origin"

echo "== 0.3 — referrer coverage is a first-class input to enumeration_complete =="
MR="$(d 0)"; RD="$(d 7)"; RC1="$(d 8)"; RL="$(d 9)"
CR="$(d c)"; LR="$(d a)"
write_fixture <<PY
MR, RD, RC1, RL, CR, LR = "$MR", "$RD", "$RC1", "$RL", "$CR", "$LR"
def cfg(d, s): return {"mediaType": "c", "digest": d, "size": s}
def lay(d, s): return {"mediaType": "l", "digest": d, "size": s}
fx = {
  "catalog": [{"repositories": ["R_r"], "next": None}],
  "tags": {"R_r": {"pages": [{"tags": ["t1"], "next": None}]}},
  "manifests": {
    "R_r/t1": {"digest": MR, "size": 400, "config": cfg(CR, 10), "layers": [lay(LR, 100)]},
    "R_r/" + RD: {"digest": RD, "size": 876, "config": cfg(RC1, 20), "layers": [lay(RL, 300)]},
  },
  "referrers": {"R_r/" + MR: {"code": 200, "manifests": [
      {"mediaType": "m", "digest": RD, "size": 876,
       "artifactType": "application/vnd.dev.sigstore.bundle.v0.3+json"}]}},
  "referrers_default": {"code": 200, "manifests": []},
}
PY
run_inv "$INV" ZOT_INVENTORY_REPO_FLOOR=1
# Referrers are INVISIBLE to tags/list, so their bytes are counted only if the referrers
# API is actually walked. 400+10+100+876+20+300 = 1706 over 6 unique digests.
expect_field unique_blobs 6 "referrer bytes are counted"
expect_field manifest_referenced_bytes 1706 "referrer bytes are counted"
expect_field referrer_errors 0 "referrer coverage complete"
expect_field enumeration_complete true "referrer coverage complete"

python3 - "$FIXTURE" <<'PY'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["fail_always"] = ["referrers:" + list(fx["referrers"].keys())[0]]
fx["generation"] += 600
json.dump(fx, open(sys.argv[1], "w"))
PY
run_inv "$INV" ZOT_INVENTORY_REPO_FLOOR=1
expect_field referrer_errors 1 "a referrers read that fails after retry"
expect_field enumeration_complete false "referrer coverage is a first-class completeness input"
expect_field reason referrer_incomplete "referrer failure"

echo "== E8 — restart straddle, and E9 — the stale-disk arm is degraded, not partial =="
dedup_fixture
run_inv "$INV" ZOT_RESTARTS_AT_END=15641
expect_field outcome partial "restart straddle"
expect_field reason restart_during_sweep "restart straddle"
if [ "$RC" -eq 1 ]; then pass "restart straddle exits 1"; else fail "restart straddle rc=$RC (want 1)"; fi

dedup_fixture
run_inv "$INV" ZOT_DISK_SAMPLE_AGE_S=99999
expect_field outcome degraded "stale disk sample"
expect_field reason disk_sample_stale "stale disk sample"
if [ "$RC" -eq 0 ]; then pass "the stale-disk arm is exit 0 (degraded), not exit 1"; else fail "stale-disk arm rc=$RC (want 0)"; fi

echo "== A2/A3 — the delta is an upper bound with a stated error bar =="
dedup_fixture
run_inv "$INV"
FS_USED="$(field fs_used_gb)"
DELTA="$(field delta_gb)"
if [ "$FS_USED" = "59.00" ]; then pass "fs_used_gb = fs_size_gb x pcent/100 (59.00)"
else fail "fs_used_gb want 59.00 got '$FS_USED'"; fi
if [ "$DELTA" = "59.00" ]; then pass "delta_gb = fs_used_gb - manifest_referenced_gb (59.00)"
else fail "delta_gb want 59.00 got '$DELTA'"; fi
if grep -qF 'MEASURED-BY' "$INV" && grep -qE 'ext4|reserve' "$INV"; then
  pass "the ~3 GB ext4-reserve error bar is carried in the script"
else
  fail "the script does not state the ext4-reserve error bar on delta_gb"
fi
# The lever must never present the delta as a cause.
if grep -qE '^[^#]*(echo|printf)[^#]*(caused by|the cause is|root cause)' "$INV"; then
  fail "an operator-facing message names a cause for delta_gb"
else
  pass "no operator-facing message assigns a cause to delta_gb"
fi

echo "== 1.1.7 / F3 — verb confinement at the wire =="
dedup_fixture
run_inv "$INV"
# MINIMUM CARDINALITY FIRST. Zero recorded requests satisfies "every request was a GET",
# and zero is exactly what an early exit produces.
n_req="$(grep -cE '.' "$REQLOG" || true)"
if [ "${n_req:-0}" -ge 8 ]; then pass "the recording origin logged ${n_req} requests (floor 8)"
else fail "only ${n_req} recorded requests — every negative assertion below would pass vacuously"; fi
bad_verbs="$(grep -cvE '^(GET|HEAD) ' "$REQLOG" || true)"
if [ "${bad_verbs:-0}" -eq 0 ]; then pass "every recorded request line matches ^(GET|HEAD) "
else fail "${bad_verbs} recorded request(s) used a verb other than GET/HEAD" "$(grep -vE '^(GET|HEAD) ' "$REQLOG" | head -3)"; fi

# SUPPLEMENT (explicitly labelled): a source-level deny-list. It covers branches the
# recording origin cannot reach, and it is NOT the primary evidence.
if grep -nE '^[^#]*\b(wget|ncat|socat)\b|^[^#]*/dev/tcp|^[^#]*--request[[:space:]]+(PUT|POST|PATCH|DELETE)[^#]*/v2/' "$INV" >/dev/null; then
  fail "SUPPLEMENT: the source names a non-curl egress tool or a write verb against /v2/" "$(grep -nE '\b(wget|ncat|socat)\b|/dev/tcp' "$INV" | head -3)"
else
  pass "SUPPLEMENT: no wget/ncat/socat//dev/tcp and no write verb against /v2/ in the source"
fi

echo "== 1.1.8 — egress confinement, floor asserted FIRST =="
if [ "$(grep -cE '.' "$INGEST_REQ" || true)" -ge 1 ]; then pass "the ingest fixture recorded at least one request (floor)"
else fail "the ingest fixture recorded nothing — 'no call reached the canary' would be vacuous"; fi
if [ "$(grep -cE '.' "$INGEST_BODY" || true)" -ge 1 ]; then pass "the ingest fixture captured a payload body (floor)"
else fail "no ingest payload captured"; fi
if [ "$(grep -cE '.' "$CANARY_REQ" || true)" -eq 0 ]; then pass "zero requests reached the third-party canary"
else fail "a request reached a destination that is neither the registry nor the pinned ingest" "$(head -3 "$CANARY_REQ")"; fi

echo "== 1.1.9 / C1 / F6 — masking of the actually-consumed secrets =="
# ASSERTED ON THE RIGHT STREAM. These two used to require `::add-mask::<token>` in
# $OUT — i.e. in STDOUT — which is the shape that caused the leak, not the shape
# that prevents it: the caller redirects stdout into $MARKER_FILE and posts that
# file into a comment on PUBLIC issue #7339, so a raw token on stdout is published.
# The assertions certified the defect and a mutation arm made that certification
# load-bearing.
#
# The mask must be EMITTED (the runner parses workflow commands from stderr too)
# and must NOT be on stdout. Both directions are pinned, plus a whole-stream
# sentinel sweep — the marker line was always clean; the leak was everything
# around it, so an assertion scoped to the marker cannot see this class.
if grep -qF "::add-mask::${PULL_SENTINEL}" "$ERR"; then pass "::add-mask:: emitted for ZOT_PULL_TOKEN (on stderr)"
else fail "no ::add-mask:: for ZOT_PULL_TOKEN on stderr" "$(head -5 "$ERR")"; fi
if grep -qF "::add-mask::${BS_SENTINEL}" "$ERR"; then pass "::add-mask:: emitted for BETTERSTACK_LOGS_TOKEN (on stderr)"
else fail "no ::add-mask:: for BETTERSTACK_LOGS_TOKEN on stderr" "$(head -5 "$ERR")"; fi

# THE LEAK GATE: no credential byte may appear ANYWHERE in stdout, because stdout
# is what becomes the public issue comment.
if grep -qF "$PULL_SENTINEL" "$OUT"; then
  fail "ZOT_PULL_TOKEN appears in captured stdout — stdout becomes a PUBLIC issue comment" "$(grep -nF "$PULL_SENTINEL" "$OUT" | head -3)"
else pass "no ZOT_PULL_TOKEN byte anywhere in stdout"; fi
if grep -qF "$BS_SENTINEL" "$OUT"; then
  fail "BETTERSTACK_LOGS_TOKEN appears in captured stdout — stdout becomes a PUBLIC issue comment" "$(grep -nF "$BS_SENTINEL" "$OUT" | head -3)"
else pass "no BETTERSTACK_LOGS_TOKEN byte anywhere in stdout"; fi
if grep -qF "$PULL_SENTINEL" <<<"$(marker)"; then fail "the pull token reached the marker line"; else pass "the pull token is absent from the marker"; fi
if grep -qF "$BS_SENTINEL" <<<"$(marker)"; then fail "the ingest token reached the marker line"; else pass "the ingest token is absent from the marker"; fi
if grep -qF "$PULL_SENTINEL" "$REQLOG" "$INGEST_BODY"; then fail "a sentinel reached a recorded request path or payload"; else pass "no sentinel in the recorded request paths or payload"; fi

echo "== 1.1.10 / I2 / E9 — marker hygiene against a construction-site-derived allow-list =="
LINE="$(marker)"
if [ -n "$LINE" ]; then pass "a marker line was emitted"; else fail "no marker line"; fi
# Guarded on non-empty: `wc -l` of the empty string is 1, so an unguarded single-line check
# reports its strongest result for a marker that was never produced.
if [ -n "$LINE" ] && [ "$(wc -l <<<"$LINE" | tr -d ' ')" = "1" ]; then pass "the marker is a single line"
else fail "the marker is absent or spans multiple lines"; fi
if [[ "$LINE" == "SOLEUR_ZOT_INVENTORY run_id="* ]]; then pass "the marker is prefix-anchored on 'SOLEUR_ZOT_INVENTORY run_id='"
else fail "the marker does not start with 'SOLEUR_ZOT_INVENTORY run_id='" "$LINE"; fi
# Derived from the CONSTRUCTION SITE, comments stripped and the window anchored on syntax a
# comment cannot produce (`MARKER_FIELDS=(` ... `)` at column 0). A hand-copied key list has
# gone green in this repo while the producer silently dropped two keys.
derived_keys="$(grep -vE '^[[:space:]]*#' "$INV" \
  | sed -n '/^[[:space:]]*MARKER_FIELDS=($/,/^[[:space:]]*)$/p' \
  | grep -oE '"[a-z0-9_]+=' | tr -d '"=' | tr '\n' ' ')"
emitted_keys="$(tr ' ' '\n' <<<"$LINE" | tail -n +2 | cut -d= -f1 | tr '\n' ' ')"
if [ -z "$derived_keys" ]; then
  fail "derived NO field names from the marker construction site — this parity check would pass vacuously"
elif [ "$derived_keys" = "$emitted_keys" ]; then
  pass "the emitted field set matches the construction site exactly"
else
  fail "marker field drift" "construction: ${derived_keys}| emitted: ${emitted_keys}"
fi
# The 1.5 contract, asserted by name so a rename cannot silently drop a field.
for k in run_id commit_sha marker_schema outcome reason repos repos_enumerated tags \
         manifests_fetched catalog_errors tag_list_errors manifest_errors \
         enumeration_complete unique_blobs manifest_referenced_bytes \
         manifest_referenced_gb fs_size_gb pcent fs_used_gb delta_gb disk_sample_age_s \
         boot_id zot_restarts_at_start zot_restarts_at_end sweep_started_at sweep_duration_s; do
  if grep -qE "(^| )$k=" <<<"$LINE"; then pass "field $k present"; else fail "task-1.5 field $k is missing" "$LINE"; fi
done
# All values space-free. Tokenising on space and requiring EVERY token to be a non-empty
# `key=value` is what catches a value that carried a space: the space would have split it
# into a token with no `=`.
bad_tok=0
[ -n "$LINE" ] || bad_tok=$((bad_tok + 1))
for tok in $LINE; do
  [ "$tok" = "SOLEUR_ZOT_INVENTORY" ] && continue
  [[ "$tok" =~ ^[a-z0-9_]+=[^[:space:]]+$ ]] || { bad_tok=$((bad_tok + 1)); fail "malformed marker token '$tok'" "$LINE"; }
done
if [ "$bad_tok" -eq 0 ]; then pass "every marker token is a non-empty, space-free key=value"; fi
# CLOSED enums, and the script's own reason vocabulary must equal this list — otherwise a
# typo'd reason passes an allow-list that was hand-copied from the same typo.
OUTCOME_ENUM='^(ok|degraded|partial|failed)$'
REASON_LIST='none origin_unreachable catalog_unreadable catalog_empty catalog_undercount link_unfollowed tag_list_incomplete manifest_incomplete referrer_incomplete restart_during_sweep disk_sample_stale disk_sample_missing'
if [[ "$(field outcome)" =~ $OUTCOME_ENUM ]]; then pass "outcome is inside the closed enum"; else fail "outcome outside the closed enum: $(field outcome)"; fi
script_reasons="$(grep -vE '^[[:space:]]*#' "$INV" \
  | sed -n '/^REASON_ENUM=($/,/^)$/p' \
  | grep -oE '^[[:space:]]+[a-z_]+$' | tr -d ' ' | tr '\n' ' ')"
# shellcheck disable=SC2086  # deliberate word-splitting: REASON_LIST is a token list.
want_reasons="$(printf '%s ' $REASON_LIST)"
if [ -z "$script_reasons" ]; then
  fail "derived NO reason vocabulary from the script — the closed-enum check would be vacuous"
elif [ "$script_reasons" = "$want_reasons" ]; then
  pass "the script's reason vocabulary is exactly the closed enum this suite pins"
else
  fail "reason vocabulary drift" "script: ${script_reasons}| suite: ${want_reasons}"
fi

echo "== 1.1.11 — no-stub emitter =="
dedup_fixture
run_inv "$INV" BETTERSTACK_LOGS_TOKEN=
if [ "$RC" -ne 0 ]; then pass "an unset ingest token fails loudly"; else fail "an unset ingest token exited 0 — a silent skip"; fi
if [ "$(grep -cE '.' "$INGEST_REQ" || true)" -eq 0 ]; then pass "no ingest attempt was made without a token"; else fail "an ingest request was made with no token"; fi
if grep -qiE 'BETTERSTACK_LOGS_TOKEN' "$ERR"; then pass "the failure names the missing variable"; else fail "the failure does not name BETTERSTACK_LOGS_TOKEN" "$(cat "$ERR")"; fi

echo "== 1.1.12 / D7 — ZOT_PUSH_* self-enforcement at entry =="
dedup_fixture
run_inv "$INV" ZOT_PUSH_USER=pusher
if [ "$RC" -ne 0 ]; then pass "ZOT_PUSH_USER populated -> non-zero exit"; else fail "ZOT_PUSH_USER populated and the script ran"; fi
if [ "$(grep -cE '.' "$REQLOG" || true)" -eq 0 ]; then pass "the entry guard fires BEFORE any request is issued"; else fail "requests were issued despite ZOT_PUSH_USER being set"; fi
dedup_fixture
run_inv "$INV" ZOT_PUSH_TOKEN=secret
if [ "$RC" -ne 0 ]; then pass "ZOT_PUSH_TOKEN populated -> non-zero exit"; else fail "ZOT_PUSH_TOKEN populated and the script ran"; fi

echo "== AP-022 — errexit is provably clear at every rc capture =="
# This script's rc-capture sites are only safe because errexit is NEVER enabled. Asserted
# mechanically rather than by comment: `set -e` anywhere would kill the shell at the failing
# command and every `rc=$?` below it would be unreachable.
if grep -nE '^[^#]*set[[:space:]]+-[a-z]*e' "$INV" >/dev/null; then
  fail "the script enables errexit somewhere — every rc=\$? site below it is unreachable" "$(grep -nE '^[^#]*set[[:space:]]+-[a-z]*e' "$INV" | head -3)"
else
  pass "errexit is never enabled, so every rc=\$? capture is reachable"
fi

# ---------------------------------------------------------------------------------
# 1.1.13 / F1 — mutation arms. Copied from apps/web-platform/infra/git-data-emit.test.sh
# INCLUDING its exit-non-zero-when-the-marker-is-absent behaviour: a mutation that does not
# land is a null result wearing a pass's clothes.
#
# `bash -n` rather than that file's `sh -n`: this script uses bash associative arrays, which
# are a dash SYNTAX error, so `sh -n` would report every mutant as unparseable.
# ---------------------------------------------------------------------------------
mutate_del() {  # <dst-basename> <marker-substring>
  python3 - "$INV" "$TMP/$1" "$2" <<'PY' || return 1
import sys
src, dst, marker = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
keep = [l for l in lines if marker not in l]
if len(keep) == len(lines):
    sys.stderr.write("marker not found: %r\n" % marker); sys.exit(3)
open(dst, "w").write("\n".join(keep))
PY
  chmod +x "$TMP/$1"
  bash -n "$TMP/$1" 2>/dev/null || { echo "mutant $1 does not parse" >&2; return 1; }
}
mutate_sub() {  # <dst-basename> <old-substring> <new-substring>
  python3 - "$INV" "$TMP/$1" "$2" "$3" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
if old not in s:
    sys.stderr.write("substring not found: %r\n" % old); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/$1"
  bash -n "$TMP/$1" 2>/dev/null || { echo "mutant $1 does not parse" >&2; return 1; }
}

echo "== 1.1.13 MUTATION — dedup deleted must produce the naive sum 11/5552 =="
if mutate_sub inv-nodedup 'BLOB_SIZE["$1"]="$2"' 'BLOB_SEQ=$(( ${BLOB_SEQ:-0} + 1 )); BLOB_SIZE["$1#$BLOB_SEQ"]="$2"'; then
  dedup_fixture
  run_inv "$TMP/inv-nodedup"
  if [ "$(field unique_blobs)" = "11" ] && [ "$(field manifest_referenced_bytes)" = "5552" ]; then
    pass "the naive-sum mutant produces 11/5552 — the 7/3526 assertion is load-bearing"
  else
    fail "MUTATION(dedup) did not produce the naive sum" "got $(field unique_blobs)/$(field manifest_referenced_bytes)"
  fi
else
  fail "MUTATION(dedup) did not land — the digest-keyed accumulation site was not found"
fi

echo "== 1.1.13 MUTATION — an exfil URL must break egress confinement =="
if mutate_sub inv-exfil '"${ZOT_INVENTORY_INGEST_URL:-https://s2457081.eu-fsn-3.betterstackdata.com/}"' "\"$CANARY_URL\""; then
  dedup_fixture
  run_inv "$TMP/inv-exfil"
  n_can="$(grep -cE '.' "$CANARY_REQ" || true)"
  n_ing="$(grep -cE '.' "$INGEST_REQ" || true)"
  if [ "${n_can:-0}" -ge 1 ] && [ "${n_ing:-0}" -eq 0 ]; then
    pass "the exfil mutant reaches the canary and starves the pinned ingest — 1.1.8 is load-bearing"
  else
    fail "MUTATION(exfil) changed no observable destination" "canary=${n_can} ingest=${n_ing}"
  fi
else
  fail "MUTATION(exfil) did not land — the pinned ingest URL literal was not found"
fi

echo "== 1.1.13 MUTATION — a write verb must be visible at the wire =="
if mutate_sub inv-writeverb '--request GET' '--request DELETE'; then
  dedup_fixture
  run_inv "$TMP/inv-writeverb"
  if [ "$(grep -cvE '^(GET|HEAD) ' "$REQLOG" || true)" -ge 1 ]; then
    pass "the write-verb mutant is recorded by the origin — 1.1.7 is load-bearing"
  else
    fail "MUTATION(write-verb) produced no non-GET/HEAD request line" "$(head -3 "$REQLOG")"
  fi
else
  fail "MUTATION(write-verb) did not land — no '--request GET' in the source"
fi

echo "== 1.1.13 MUTATION — deleting the masking rule must leak the sentinels =="
if mutate_del inv-nomask '::add-mask::'; then
  dedup_fixture
  run_inv "$TMP/inv-nomask"
  # $ERR, not $OUT. The masks moved to stderr when the leak was fixed, so grepping
  # stdout here would pass whether or not the mutation landed — the arm would be
  # vacuous in exactly the way it exists to disprove. A mutation arm has to read
  # the stream the property lives on, and that stream changed.
  if grep -qF "::add-mask::${BS_SENTINEL}" "$ERR" || grep -qF "::add-mask::${PULL_SENTINEL}" "$ERR"; then
    fail "MUTATION(mask): an ::add-mask:: survived the deletion — the masking check is vacuous"
  else
    pass "the masking mutant emits no ::add-mask:: — 1.1.9 is load-bearing"
  fi
else
  fail "MUTATION(mask) did not land — no ::add-mask:: in the source"
fi

# ---------------------------------------------------------------------------------
# Minimum-cardinality guard: a silently-empty harness must fail loud.
# ---------------------------------------------------------------------------------
total=$((passes + fails))
if [ "$total" -lt 90 ]; then
  echo "FAIL: ran only ${total} assertions (<90) — the suite did not execute fully" >&2
  exit 1
fi

echo "test-zot-inventory: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
