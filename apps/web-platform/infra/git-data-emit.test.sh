#!/usr/bin/env bash
#
# (#6982) Behavioural tests for /usr/local/bin/git-data-emit.
#
# WHY BEHAVIOURAL AND NOT STATIC. git-data-luks.test.sh already carries the static
# drift-guards (the emitter exists, reads the baked DSN, the traps carry the rc guard).
# Those cannot answer the question the CLO panel actually raised: does a repo path or a
# passphrase SURVIVE to the wire? On this host the repo identifier IS the user identifier
# — repos are <workspace_id>.git and workspace_id === user_id (mig-053 N2) — and Better
# Stack's shared `pii_scrub_string` does NOT scrub a bare UUID in free text. So the only
# assertion worth making is against the bytes that leave the process.
#
# The emitter is EXTRACTED FROM THE RENDERED TEMPLATE, never from a hand-copied fixture: a
# test that greps a copy of the script proves the copy is correct. Rendering is what makes
# this test track the artifact that actually ships.
#
# Run: bash apps/web-platform/infra/git-data-emit.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }

command -v terraform >/dev/null 2>&1 || {
  echo "git-data-emit: SKIP — terraform not on PATH (the emitter is extracted from a real render)" >&2
  exit 0
}
command -v python3 >/dev/null 2>&1 || { echo "git-data-emit: SKIP — python3 absent" >&2; exit 0; }

TMP="$(mktemp -d -t gdemit.XXXXXXXX)"
trap 'kill "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------------
# Extract the emitter from a REAL terraform render of the template.
# ---------------------------------------------------------------------------------
RENDERED="$TMP/rendered.yml"
bash "$DIR/git-data-userdata-budget.sh" "$RENDERED" >/dev/null 2>&1 || {
  echo "FAIL: could not render cloud-init-git-data.yml" >&2; exit 1;
}
python3 - "$RENDERED" "$TMP/git-data-emit" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for wf in d["write_files"]:
    if wf["path"] == "/usr/local/bin/git-data-emit":
        open(sys.argv[2], "w").write(wf["content"])
        sys.exit(0)
sys.exit(1)
PY
[ -s "$TMP/git-data-emit" ] || { echo "FAIL: emitter not found in the rendered template" >&2; exit 1; }
chmod +x "$TMP/git-data-emit"

# ---------------------------------------------------------------------------------
# A capture server standing in for Sentry. Records every POST body to a file.
# ---------------------------------------------------------------------------------
CAPTURE="$TMP/capture.log"
: > "$CAPTURE"
python3 - "$CAPTURE" "$TMP/port" <<'PY' &
import sys, http.server, socketserver, threading
cap, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        with open(cap, "ab") as f:
            f.write(body + b"\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
with socketserver.TCPServer(("127.0.0.1", 0), H) as httpd:
    open(portfile, "w").write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT="$(cat "$TMP/port" 2>/dev/null || true)"
[ -n "$PORT" ] || { echo "FAIL: capture server did not start" >&2; exit 1; }

# Point the extracted emitter at the capture server. Two rewrites, both HARNESS-ONLY —
# the shipped emitter is untouched:
#   1. the baked DSN (the rendered copy carries the budget script's stub value), and
#   2. the `https://` in the Sentry POST URL -> `http://`, because a local capture server
#      speaks plain HTTP. Without (2) curl fails TLS and NOTHING is captured, which
#      presents as every assertion failing at once rather than as a connection error.
# python rather than sed: the target contains `${SHOST}`, and `\{` is INTERVAL syntax in a
# BRE, so the natural sed form dies with "Invalid content of \{\}".
python3 - "$TMP/git-data-emit" "$PORT" <<'PY'
import sys
p, port = sys.argv[1], sys.argv[2]
s = open(p).read()
out = []
for line in s.split("\n"):
    if line.startswith("DSN='"):
        line = "DSN='https://testkey@127.0.0.1:%s/424242'" % port
    line = line.replace('"https://${SHOST}/api/${PROJ}/store/"',
                        '"http://${SHOST}/api/${PROJ}/store/"')
    out.append(line)
open(p, "w").write("\n".join(out))
PY
grep -q "127.0.0.1:${PORT}" "$TMP/git-data-emit" || { echo "FAIL: could not repoint the DSN" >&2; exit 1; }
grep -q 'http://${SHOST}' "$TMP/git-data-emit" || { echo "FAIL: could not downgrade the POST scheme for the harness" >&2; exit 1; }

emit() { ( cd "$TMP" && ./git-data-emit "$@" ); }
last_body() { tail -1 "$CAPTURE" 2>/dev/null; }

# ---------------------------------------------------------------------------------
# E1 — the emitter delivers, and reports delivery by EXIT CODE. This is what makes the
# Phase-3 delivery assertion (AC34) mechanical rather than decorative.
# ---------------------------------------------------------------------------------
if emit "hello" runcmd_early info "" >/dev/null 2>&1; then pass; else fail "E1 delivery: exit non-zero against a live endpoint"; fi
if printf '%s' "$(last_body)" | grep -q '"stage":"runcmd_early"'; then pass; else fail "E1 payload" "$(last_body)"; fi

# E2 — a NON-DELIVERING transport must exit non-zero, so the boot fails LOUDLY rather
# than continuing into a boot nothing can report on (R8: v1 asserted the opposite).
sed "s#127.0.0.1:${PORT}#127.0.0.1:1#" "$TMP/git-data-emit" > "$TMP/emit-dead"; chmod +x "$TMP/emit-dead"
if ( cd "$TMP" && ./emit-dead "x" s info "" ) >/dev/null 2>&1; then
  fail "E2 dead transport: exited 0 — the delivery assertion would pass on a dark boot"
else pass; fi

# ---------------------------------------------------------------------------------
# AC22 — NO repo path and NO workspace/user UUID reaches the wire.
#
# Asserted as a UUID-SHAPE regex, not as the literal fixture string: the sanitiser chain
# ends `tail -c 180`, so a truncated-but-still-identifying prefix would survive a literal
# grep. The fixture repo lives under the REAL REPO_ROOT (/mnt/git-data/repositories),
# because a fixture on the LUKS mount would pass vacuously — that volume is empty by
# construction until the cutover.
# ---------------------------------------------------------------------------------
UUID="3f2504e0-4f89-11d3-9a0c-0305e82c3301"
UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# TWO RULES, TWO FIXTURES — and they must not be conflated. The repo-path rule fires first
# and rewrites the whole path, so a UUID embedded in a repo path is redacted even with the
# UUID rule deleted. Testing only that fixture makes the UUID rule's mutation arm VACUOUS:
# measured, the mutant did not leak, because the other rule was doing the work.
#
# So the UUID rule is exercised against a BARE UUID in free text — which is precisely the
# case that matters, since Better Stack's pii_scrub_string handles userid=<tok> pairs,
# emails, bearer tokens and DSNs but NOT a bare UUID.

# --- (a) bare UUID in free text: only the UUID rule can catch this ---
: > "$CAPTURE"
emit "workspace ${UUID} failed to replicate" bootstrap info \
  "fatal: object store for ${UUID} is corrupt" >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -qiE "$UUID_RE"; then
  fail "AC22 bare UUID leaked to the wire" "$BODY"
else pass; fi
if printf '%s' "$BODY" | grep -q 'UUID_REDACTED'; then pass; else fail "AC22 UUID marker absent" "$BODY"; fi

# NON-VACUITY for (a): with the UUID rule deleted the bare UUID MUST reach the wire.
python3 - "$TMP/git-data-emit" "$TMP/emit-nouuid" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
keep = [l for l in open(src).read().split("\n") if "UUID_REDACTED" not in l]
open(dst, "w").write("\n".join(keep))
PY
chmod +x "$TMP/emit-nouuid"
: > "$CAPTURE"
( cd "$TMP" && ./emit-nouuid "workspace ${UUID} failed" b info "" ) >/dev/null 2>&1
if printf '%s' "$(last_body)" | grep -qiE "$UUID_RE"; then
  pass  # the mutant leaks => the assertion above is load-bearing, not vacuous
else
  fail "AC22 MUTATION(uuid): deleting the UUID rule did not leak — that check is vacuous" "$(last_body)"
fi

# --- (b) a real repo path under the REAL repo root ---
# Fixtured at /mnt/git-data/repositories (git-data-provision.sh's REPO_ROOT), never the
# LUKS mount: that volume is EMPTY BY CONSTRUCTION until the cutover, so a fixture there
# would pass vacuously.
: > "$CAPTURE"
emit "pushed to /mnt/git-data/repositories/${UUID}.git" bootstrap info \
  "fatal: /mnt/git-data/repositories/${UUID}.git/objects is corrupt" >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -qiE "$UUID_RE"; then
  fail "AC22 repo-path UUID leaked to the wire" "$BODY"
else pass; fi
if printf '%s' "$BODY" | grep -q 'repositories/REDACTED'; then pass; else fail "AC22 repo-path marker absent" "$BODY"; fi

# ---------------------------------------------------------------------------------
# AC23 — BOTH redactor arms: the pattern chain AND the value-based substitution.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
emit "creds" bootstrap fatal 'token dp.st.prd_git_data.AAAAAAAAAAAAAAAAAAAAAAAA and ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -q 'dp.REDACTED'; then pass; else fail "AC23 doppler-token pattern" "$BODY"; fi
if printf '%s' "$BODY" | grep -q 'REDACTED_GH'; then pass; else fail "AC23 github-token pattern" "$BODY"; fi

# The value arm: a PASSPHRASE-SHAPED value that no pattern could ever catch. This is the
# arm the pattern chain structurally cannot replace.
: > "$CAPTURE"
PASS='Xq7x2LmZ0pQvR8nT4wYb'
( cd "$TMP" && GIT_DATA_LUKS_KEY="$PASS" ./git-data-emit "luks" luks_open fatal "cryptsetup: bad passphrase $PASS supplied" ) >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -q "$PASS"; then fail "AC23 VALUE arm: the passphrase reached the wire" "$BODY"; else pass; fi
if printf '%s' "$BODY" | grep -q 'LUKS_KEY_REDACTED'; then pass; else fail "AC23 value-redaction marker absent" "$BODY"; fi

# ---------------------------------------------------------------------------------
# AC24 — a captured LOG EXCERPT is redacted too, not just inline strings. The detail
# argument may be a FILE (that is how the traps ship the tail of cloud-init-output.log),
# and that path must go through the same chain.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
LOGF="$TMP/excerpt.log"
{
  echo "Using DOPPLER_TOKEN from the environment"
  echo "-----BEGIN OPENSSH PRIVATE KEY-----"
  echo "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB"
  echo "-----END OPENSSH PRIVATE KEY-----"
  echo "dp.st.prd_git_data.BBBBBBBBBBBBBBBBBBBBBBBB"
} > "$LOGF"
emit "boot failed" bootstrap fatal "$LOGF" >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -q 'BEGIN OPENSSH PRIVATE KEY'; then
  fail "AC24 private-key block reached the wire" "$BODY"
else pass; fi
if printf '%s' "$BODY" | grep -q 'dp.st.prd_git_data'; then
  fail "AC24 doppler token from the log excerpt reached the wire" "$BODY"
else pass; fi

# ---------------------------------------------------------------------------------
# AC30 — the boot-completion payload carries the four booleans and claims NOTHING about
# the repositories being encrypted at rest. They are NOT: REPO_ROOT is the PLAINTEXT
# volume until the GIT_DATA_STORE_ENABLED cutover, and duplicating that false claim into
# telemetry would be the same defect the Art. 30 register is being corrected for.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
emit "git-data bootstrap complete" boot_complete info "" \
  "luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" "disk_pct=7" >/dev/null 2>&1
BODY="$(last_body)"
for k in luks_mounted repo_root hooks_path provision disk_pct; do
  if printf '%s' "$BODY" | grep -q "\"$k\""; then pass; else fail "AC30 boot_complete missing $k" "$BODY"; fi
done
if printf '%s' "$BODY" | grep -qiE 'encrypted at rest|repos.*encrypted|at-rest encryption'; then
  fail "AC30 the emit claims at-rest encryption of the repositories" "$BODY"
else pass; fi

# ---------------------------------------------------------------------------------
# The Better Stack arm fires ONLY when the ingest token is in the environment. That is
# the D1 channel split, and it is structural: early boot stages have no token, so they
# are Sentry-only by construction rather than by a flag anyone can set wrongly.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
emit "no-token" gc info "" >/dev/null 2>&1
n_without=$(wc -l < "$CAPTURE")
: > "$CAPTURE"
sed -i "s#curl --connect-timeout 5 -m 10 -sf -X POST '.*'#curl --connect-timeout 5 -m 10 -sf -X POST 'http://127.0.0.1:${PORT}/bs'#" "$TMP/git-data-emit"
( cd "$TMP" && BETTERSTACK_LOGS_TOKEN=stub ./git-data-emit "with-token" gc info "" ) >/dev/null 2>&1
n_with=$(wc -l < "$CAPTURE")
if [ "$n_with" -gt "$n_without" ]; then pass; else
  fail "channel split: the Better Stack arm did not fire with the token present" "without=$n_without with=$n_with"
fi

# --- Minimum-cardinality guard: a silently-empty harness must fail loud ---
total=$((passes + fails))
if [ "$total" -lt 20 ]; then
  echo "FAIL: ran only ${total} assertions (<20) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-emit: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
