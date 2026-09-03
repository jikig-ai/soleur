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

# B5: a skip is not a pass, and under CI it is not even a skip — see _skip.
_skip() {
  if [ "${CI:-}" = "true" ]; then
    echo "$1 — and CI=true, so this is a FAILURE: the runner must provide this dependency. A gate that cannot run must not report success." >&2
    exit 1
  fi
  echo "$1" >&2
  exit 0
}

command -v terraform >/dev/null 2>&1 || _skip "git-data-emit: SKIP — terraform not on PATH (the emitter is extracted from a real render)"
command -v python3 >/dev/null 2>&1 || _skip "git-data-emit: SKIP — python3 absent"

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
# (#7460 5.3) The mirror emits a SECOND Sentry body, stage:betterstack_ingest, whenever the
# Better Stack POST does not succeed -- which in this harness is EVERY arm that supplies a
# token, because no Better Stack sink is reachable from the runner. Every pre-existing arm
# here is about the PRIMARY emit, so body selection must skip the mirror; before this filter
# the mirror silently became `tail -1` and 24 arms read its tags instead of the emit's.
_primary() { grep -v '"stage":"betterstack_ingest"' "$CAPTURE" 2>/dev/null; }
last_body()   { _primary | tail -1; }
mirror_body() { grep '"stage":"betterstack_ingest"' "$CAPTURE" 2>/dev/null | tail -1; }

# ---------------------------------------------------------------------------------
# Mutation helpers.
#
# "A mutation that does not land is a null result wearing a pass's clothes" — both
# helpers EXIT NON-ZERO when the marker they were asked to change is absent, so a
# refactor that renames a rule turns the mutation arm RED instead of silently
# reporting "the mutant did not leak" (which reads identically to "the rule works").
# Every mutant is also `sh -n`-parsed: a mutation that breaks the script would emit
# nothing at all, and "nothing on the wire" is indistinguishable from "redacted".
# ---------------------------------------------------------------------------------
mutate_del() {  # <dst-basename> <marker-substring>  — drop every line containing marker
  python3 - "$TMP/git-data-emit" "$TMP/$1" "$2" <<'PY' || return 1
import sys
src, dst, marker = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
keep = [l for l in lines if marker not in l]
if len(keep) == len(lines):
    sys.stderr.write("marker not found: %r\n" % marker); sys.exit(3)
open(dst, "w").write("\n".join(keep))
PY
  chmod +x "$TMP/$1"
  sh -n "$TMP/$1" 2>/dev/null || { echo "mutant $1 does not parse" >&2; return 1; }
}
mutate_sub() {  # <dst-basename> <old-substring> <new-substring>
  python3 - "$TMP/git-data-emit" "$TMP/$1" "$2" "$3" <<'PY' || return 1
import sys
src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
if old not in s:
    sys.stderr.write("substring not found: %r\n" % old); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/$1"
  sh -n "$TMP/$1" 2>/dev/null || { echo "mutant $1 does not parse" >&2; return 1; }
}
run_mutant() { ( cd "$TMP" && "./$1" "${@:2}" ); }

# Pull one field out of the captured Sentry payload. Returns empty on unparseable JSON,
# which is itself an assertable outcome (see AC25d).
sentry_field() {  # <dotted-path e.g. tags.detail>
  python3 - "$CAPTURE" "$1" <<'PY' 2>/dev/null
import sys, json
lines = [l for l in open(sys.argv[1], "rb").read().split(b"\n")
         if l.strip() and b'"stage":"betterstack_ingest"' not in l]
if not lines: sys.exit(1)
d = json.loads(lines[-1].decode("utf-8", "replace"))
for k in sys.argv[2].split("."):
    d = d[k]
sys.stdout.write(str(d))
PY
}

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
# AC25 — the FOUR rules of the _clean chain that had no fixture at all.
#
# Each of these could be deleted individually and the suite stayed 21/21 green, so
# each was a rule the suite ASSERTED THE EXISTENCE OF and never the behaviour of.
# One fixture per rule, each paired with the mutation that proves the fixture is
# load-bearing rather than incidentally satisfied by a neighbouring rule (the trap
# AC22 already documents for the UUID-vs-repo-path pair).
# ---------------------------------------------------------------------------------

# --- (a) the Bearer rule ---------------------------------------------------------
# An `Authorization: Bearer <token>` echoed into a log excerpt or a curl error is the
# shape the Better Stack ingest token itself has, and no other rule matches it.
BEARER_TOK='aGVsbG8td29ybGQtdG9rZW4xMjM0NTY'
: > "$CAPTURE"
emit "ingest rejected" gitdata_runcmd_early warning "curl: 401 with Authorization: Bearer ${BEARER_TOK}" >/dev/null 2>&1
BODY="$(last_body)"
if grep -qF "$BEARER_TOK" <<<"$BODY"; then fail "AC25a bearer token reached the wire" "$BODY"; else pass; fi
if grep -qF 'Bearer REDACTED' <<<"$BODY"; then pass; else fail "AC25a bearer marker absent" "$BODY"; fi

if mutate_del emit-nobearer 'Bearer REDACTED'; then
  : > "$CAPTURE"
  run_mutant emit-nobearer "ingest rejected" s warning "Authorization: Bearer ${BEARER_TOK}" >/dev/null 2>&1
  if grep -qF "$BEARER_TOK" <<<"$(last_body)"; then pass
  else fail "AC25a MUTATION: deleting the Bearer rule did not leak — the fixture is vacuous" "$(last_body)"; fi
else fail "AC25a MUTATION did not land (Bearer rule marker absent from the rendered emitter)"; fi

# --- (b) the ://user:pass@ rule --------------------------------------------------
# A git remote with inline credentials. `git clone` echoes the full URL on failure and
# the password is arbitrary — no pattern rule can match it, only the URL-shape rule.
URLPASS='s3cr3tP4ssw0rdX'
: > "$CAPTURE"
emit "clone failed" bootstrap fatal "fatal: could not read from https://gituser:${URLPASS}@github.com/o/r.git" >/dev/null 2>&1
BODY="$(last_body)"
if grep -qF "$URLPASS" <<<"$BODY"; then fail "AC25b inline URL password reached the wire" "$BODY"; else pass; fi
if grep -qF '://REDACTED@' <<<"$BODY"; then pass; else fail "AC25b URL-credential marker absent" "$BODY"; fi

if mutate_del emit-nourlcred '://REDACTED@'; then
  : > "$CAPTURE"
  run_mutant emit-nourlcred "clone failed" b fatal "https://gituser:${URLPASS}@github.com/o/r.git" >/dev/null 2>&1
  if grep -qF "$URLPASS" <<<"$(last_body)"; then pass
  else fail "AC25b MUTATION: deleting the URL-credential rule did not leak — the fixture is vacuous" "$(last_body)"; fi
else fail "AC25b MUTATION did not land (URL-credential rule marker absent)"; fi

# --- (c) the `tail -c 180` cap ---------------------------------------------------
# The cap is the only bound on payload size. Sentry's store endpoint rejects oversized
# envelopes, and `curl -f` turns that rejection into a non-zero exit — i.e. an uncapped
# detail does not merely ship noise, it can FAIL THE BOOT via the delivery assertion.
: > "$CAPTURE"
LONG="$(printf 'A%.0s' $(seq 1 400))"
emit "long detail" bootstrap info "$LONG" >/dev/null 2>&1
CAP_LEN="$(sentry_field tags.detail | wc -c | tr -d ' ')"
if [ "${CAP_LEN:-0}" -le 180 ] && [ "${CAP_LEN:-0}" -gt 0 ]; then pass
else fail "AC25c detail not capped at 180 bytes" "len=${CAP_LEN}"; fi

if mutate_sub emit-nocap 'tail -c 180' 'cat'; then
  : > "$CAPTURE"
  run_mutant emit-nocap "long detail" b info "$LONG" >/dev/null 2>&1
  UNCAP_LEN="$(sentry_field tags.detail | wc -c | tr -d ' ')"
  if [ "${UNCAP_LEN:-0}" -gt 180 ]; then pass
  else fail "AC25c MUTATION: removing the cap did not lengthen the detail — the cap check is vacuous" "len=${UNCAP_LEN}"; fi
else fail "AC25c MUTATION did not land (tail -c 180 absent)"; fi

# --- (d) `tr -d '"\'` — PAYLOAD INTEGRITY, not privacy ---------------------------
# The emitter builds its JSON with printf, not a serialiser. An unescaped `"` or `\`
# in a git error therefore produces MALFORMED JSON -> Sentry 400 -> `curl -f` non-zero
# -> the boot's delivery assertion fails. So this rule is load-bearing for the boot
# succeeding at all, and the assertion is "the captured body parses", not "a string is
# absent".
: > "$CAPTURE"
emit 'quote "test"' bootstrap info 'fatal: pathspec "a\b" did not match' >/dev/null 2>&1
if python3 -c 'import sys,json;ls=[l for l in open(sys.argv[1],"rb").read().split(b"\n") if l.strip() and b"betterstack_ingest" not in l];json.loads(ls[-1].decode())' "$CAPTURE" 2>/dev/null; then pass
else fail "AC25d a quote/backslash in the detail produced malformed JSON" "$(last_body)"; fi

if mutate_del emit-noquotestrip "tr -d '\"" ; then
  : > "$CAPTURE"
  run_mutant emit-noquotestrip 'quote "test"' b info 'fatal: pathspec "a\b" did not match' >/dev/null 2>&1
  if python3 -c 'import sys,json;ls=[l for l in open(sys.argv[1],"rb").read().split(b"\n") if l.strip() and b"betterstack_ingest" not in l];json.loads(ls[-1].decode())' "$CAPTURE" 2>/dev/null; then
    fail "AC25d MUTATION: dropping the quote strip still produced valid JSON — the check is vacuous" "$(last_body)"
  else pass; fi
else fail "AC25d MUTATION did not land (quote-strip marker absent)"; fi

# ---------------------------------------------------------------------------------
# AC30 — the boot-completion payload carries the four booleans and claims NOTHING about
# the repositories being encrypted at rest. They are NOT: REPO_ROOT is the PLAINTEXT
# volume until the GIT_DATA_STORE_ENABLED cutover, and duplicating that false claim into
# telemetry would be the same defect the Art. 30 register is being corrected for.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
emit "git-data bootstrap complete" boot_complete info "" \
  "luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" "disk_pct=7" "inode_pct=9" >/dev/null 2>&1
BODY="$(last_body)"
# KEY **AND VALUE**. The former loop grepped `"$k"` only, so blanking every value on the
# wire left it 21/21 green — and the value is the entire content of this payload: THREE
# consumers read these four booleans to decide whether the birth succeeded. A key with an
# empty value is a boot report that says nothing while looking complete.
for kv in luks_mounted=yes repo_root=yes hooks_path=yes provision=yes disk_pct=7 inode_pct=9; do
  k="${kv%%=*}"; v="${kv#*=}"
  if grep -qF "\"$k\":\"$v\"" <<<"$BODY"; then pass; else fail "AC30 boot_complete $k != $v" "$BODY"; fi
done

# B6 — PARITY WITH THE PRODUCER. The fixture above is a hand-written copy of the payload
# git-data-bootstrap.sh actually emits, and nothing tied the two together: dropping
# `hooks_path=yes` from the producer left this suite green and would surface only during a
# real birth, on the one signal whose ARRIVAL is supposed to mean every assertion passed.
#
# So derive the producer's key set from the producer and compare it to the set asserted here.
# Both directions: a key added to the producer and never asserted is untested, and a key
# asserted here but no longer produced is a fixture that has drifted off the artifact.
# COMMENTS STRIPPED FIRST, and the window anchored on the CALL, not on a bare token. Both
# `sed` addresses were unanchored greps over an unstripped file, and `|| true` already occurs
# in prose two lines above the emit. Measured: planting a comment above the call listing all
# six keys, while DELETING luks_mounted and hooks_path from the real emit, harvested the keys
# from the COMMENT and reported 44/44 GREEN — and because ADR-152 strips comments at render
# time, the text making the gate green does not exist on the host. The boot signal whose
# arrival is supposed to mean the LUKS device mounted would no longer say so, with three
# consumers reading a payload this suite swore was complete. (cq-assert-anchor-not-bare-token)
#
# `[a-z0-9_]` not `[a-z_]`: the old class was blind to any key containing a digit, so a
# `sha256_ok=` key would ship unasserted.
_producer_keys="$(grep -vE '^[[:space:]]*#' "$DIR/git-data-bootstrap.sh" \
  | sed -n '/^[[:space:]]*"\$GIT_DATA_EMIT".*boot_complete/,/|| true$/p' \
  | grep -oE '"[a-z0-9_]+=' | tr -d '"=' | sort -u | tr '\n' ' ')"
_asserted_keys="$(printf '%s\n' luks_mounted repo_root hooks_path provision disk_pct inode_pct | sort -u | tr '\n' ' ')"
if [ -z "$_producer_keys" ]; then
  fail "AC30-parity: derived NO keys from git-data-bootstrap.sh — the extraction drifted, so this parity check would pass vacuously"
elif [ "$_producer_keys" = "$_asserted_keys" ]; then
  pass
else
  fail "AC30-parity: boot_complete key set drifted between producer and this suite" \
    "producer: ${_producer_keys}| asserted: ${_asserted_keys}"
fi

# The `[ -n "$k" ]` empty-key guard. A malformed tag (`=value`, the shape a `"$var=..."`
# with an unset var produces) must be DROPPED, not emitted as `"":"value"` — an empty JSON
# key is legal JSON that no consumer query can select, so the value would ride to the sink
# unreadable and unredactable-by-key.
: > "$CAPTURE"
emit "orphan tag" boot_complete info "" "=orphanvaluexyz" "ok=1" >/dev/null 2>&1
BODY="$(last_body)"
if grep -qF 'orphanvaluexyz' <<<"$BODY"; then fail "AC30 empty-key tag was emitted" "$BODY"; else pass; fi
if grep -qF '"ok":"1"' <<<"$BODY"; then pass; else fail "AC30 well-formed sibling tag was dropped" "$BODY"; fi

if mutate_sub emit-noemptyguard '[ -n "${k}" ] &&' 'true &&'; then
  : > "$CAPTURE"
  run_mutant emit-noemptyguard "orphan tag" b info "" "=orphanvaluexyz" >/dev/null 2>&1
  if grep -qF 'orphanvaluexyz' <<<"$(last_body)"; then pass
  else fail "AC30 MUTATION: removing the empty-key guard changed nothing — the check is vacuous" "$(last_body)"; fi
else fail "AC30 MUTATION did not land (empty-key guard absent)"; fi

# A VALUE CONTAINING `=`. `${kv#*=}` (shortest prefix) is correct; `${kv##*=}` (longest)
# would silently truncate `7=8` to `8`, and `${kv%%=*}` would yield the key. disk_pct-style
# values are the realistic carrier — any `k=a=b` shape reaches here.
: > "$CAPTURE"
emit "eq in value" boot_complete info "" "notes=a=b" >/dev/null 2>&1
GOT_EQ="$(sentry_field tags.notes)"
if [ "$GOT_EQ" = "a=b" ]; then pass; else fail "AC30 value containing '=' was mangled" "got='${GOT_EQ}' want='a=b'"; fi

if mutate_sub emit-noeqvalue 'kv#*=' 'kv##*='; then
  : > "$CAPTURE"
  run_mutant emit-noeqvalue "eq in value" b info "" "notes=a=b" >/dev/null 2>&1
  if [ "$(sentry_field tags.notes)" = "a=b" ]; then
    fail "AC30 MUTATION: ##-expansion still produced a=b — the '=' check is vacuous" "$(last_body)"
  else pass; fi
else fail "AC30 MUTATION did not land (kv#*= absent)"; fi
# RE-CAPTURE. $BODY was last assigned by the orphan-tag arm above, so this check used to
# inspect a payload that could never carry the phrase -- the only far-side fixture in the AC30
# family, and it was dead. Measured: making the boot_complete fixture claim "repos encrypted at
# rest" left the suite 44/44 GREEN, i.e. the exact Art. 30 misstatement the comment above says
# this exists to prevent was unguarded.
: > "$CAPTURE"
emit "git-data bootstrap complete" boot_complete info "" \
  "luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" "disk_pct=7" "inode_pct=9" >/dev/null 2>&1
BODY="$(last_body)"
if printf '%s' "$BODY" | grep -qiE 'encrypted at rest|repos.*encrypted|at-rest encryption'; then
  fail "AC30 the emit claims at-rest encryption of the repositories" "$BODY"
else pass; fi

# ---------------------------------------------------------------------------------
# (#7460) TOKEN SOURCE, all three branches. The old arm here asserted that early boot
# stages are "Sentry-only BY CONSTRUCTION rather than by a flag anyone can set wrongly".
# #7460 DELETED that property: the emitter now reads a baked file when the env var is
# absent, so the split is a function of the file too. The arm kept passing only because
# the runner has no /etc/default/git-data-betterstack -- it had become a property of the
# TEST BOX, not of the code, and would have flipped red on any host where the file exists.
#
# The default path is absolute, so the branch was untestable until the emitter took
# GIT_DATA_BS_ENV_FILE. That override is the ONLY reason these four branches are reachable.
# ---------------------------------------------------------------------------------
# THE TEMPLATE MUST SHIP THE FILE, at the mode the whole security argument rests on.
# The behavioural arms below drive GIT_DATA_BS_ENV_FILE at a file the HARNESS writes, so
# they prove the emitter READS a baked file -- not that cloud-init CREATES one. Without
# this structural half, deleting the write_files entry outright left every suite green
# (measured). And nothing anywhere asserted `permissions: 0600`, which is the single
# property ADR-198 and the encryption-posture ledger both stake their claim on: a one
# character edit to '0644' rendered, booted and passed 53 assertions.
for _spec in "/etc/default/git-data-betterstack:BETTERSTACK_LOGS_TOKEN" \
             "/etc/default/git-data-doppler:DOPPLER_TOKEN"; do
  _wf_path="${_spec%%:*}"; _wf_var="${_spec##*:}"
  _wf=$(python3 - "$RENDERED" "$_wf_path" <<'PY2'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for wf in d.get("write_files", []):
    if wf.get("path") == sys.argv[2]:
        print("%s|%s|%s" % (wf.get("permissions"), wf.get("owner"), "\\n" not in "" and "" or wf.get("content","").replace("\n","\\n")))
        sys.exit(0)
sys.exit(1)
PY2
) || _wf=""
  if [ -n "$_wf" ]; then pass; else
    fail "$_wf_path is not written by the template at all" "write_files entry absent"; fi
  case "$_wf" in
    "0600|root:root|"*) pass ;;
    *) fail "$_wf_path must be 0600 root:root -- the mode ADR-198 and the ledger both rely on" "$_wf" ;;
  esac
  case "$_wf" in
    *"$_wf_var="*) pass ;;
    *) fail "$_wf_path does not bind $_wf_var" "$_wf" ;;
  esac
done

sed -i "s#curl --connect-timeout 5 -m 10 -sf -X POST '.*'#curl --connect-timeout 5 -m 10 -sf -X POST 'http://127.0.0.1:${PORT}/bs'#" "$TMP/git-data-emit"
BAKED="$TMP/etc-default-betterstack"
printf 'BETTERSTACK_LOGS_TOKEN=%s\n' 'Qk7vN2pR9wLmNOT-A-REAL-TOKEN' > "$BAKED"

# (a) BAKED FILE ONLY, sink reachable: both arms deliver. This is the arm that reddens if
#     the write_files entry, the load block, or the token variable is removed -- the PR's
#     central artifact, which nothing covered before.
: > "$CAPTURE"
( cd "$TMP" && GIT_DATA_BS_ENV_FILE="$BAKED" ./git-data-emit "baked" gc info "" ) >/dev/null 2>&1
rc_baked=$?
n_baked=$(wc -l < "$CAPTURE")
if [ "$n_baked" -eq 2 ]; then pass; else
  fail "baked token: both arms must deliver from the baked file alone" "n=$n_baked"; fi
if [ "$rc_baked" -eq 0 ]; then pass; else
  fail "baked token: a delivered emit must exit 0" "rc=$rc_baked"; fi

# Repoint Better Stack at a CLOSED port so the mirror fires. Everything below is the 5.3
# silent-fallback mirror, which had zero coverage: no suite ever set BS_TOKEN_SOURCE.
sed -i "s#-X POST 'http://127.0.0.1:${PORT}/bs'#-X POST 'http://127.0.0.1:1/bs'#" "$TMP/git-data-emit"

# (b) BAKED, sink dead: mirror fires and reports token_source=baked.
: > "$CAPTURE"
( cd "$TMP" && GIT_DATA_BS_ENV_FILE="$BAKED" ./git-data-emit "baked-dead" gc info "" ) >/dev/null 2>&1
rc_mirror=$?
if printf '%s' "$(mirror_body)" | grep -q '"token_source":"baked"'; then pass; else
  fail "5.3 mirror: a failed POST on the baked token must report token_source=baked" "$(mirror_body)"; fi
# THE RC CONTRACT (plan AC :1104). 0 delivered / 1 transient / 2 STRUCTURAL, and only 2
# refuses a boot. A second-sink failure must never promote into a boot failure.
if [ "$rc_mirror" -ne 2 ]; then pass; else
  fail "5.3 mirror: a Better Stack failure must NOT promote to the boot-refusing rc=2" "rc=$rc_mirror"; fi

# (c) NO TOKEN ANYWHERE: the completely-dark case. The first draft nested the mirror inside
#     the -n guard, so this state -- the one that most needs reporting -- emitted nothing.
: > "$CAPTURE"
( cd "$TMP" && GIT_DATA_BS_ENV_FILE="$TMP/does-not-exist" ./git-data-emit "dark" gc info "" ) >/dev/null 2>&1
if printf '%s' "$(mirror_body)" | grep -q '"reason":"no_token"'; then pass; else
  fail "5.3 mirror: a dark channel (no token at all) must be reported, not silent" "$(cat "$CAPTURE")"; fi

# (d) EMPTY baked file: BS_TOKEN_SOURCE must NOT claim `baked` when nothing loaded, or the
#     tag asserts coverage exactly where there is none.
: > "$CAPTURE"
printf 'BETTERSTACK_LOGS_TOKEN=\n' > "$TMP/empty-baked"
( cd "$TMP" && GIT_DATA_BS_ENV_FILE="$TMP/empty-baked" ./git-data-emit "empty" gc info "" ) >/dev/null 2>&1
if printf '%s' "$(mirror_body)" | grep -q '"token_source":"baked"'; then
  fail "5.3 mirror: an empty baked file must not report token_source=baked" "$(mirror_body)"
else pass; fi

# (e) ENV token still wins over the baked file -- the whole rotation-degradation story.
: > "$CAPTURE"
( cd "$TMP" && GIT_DATA_BS_ENV_FILE="$BAKED" BETTERSTACK_LOGS_TOKEN=envtok ./git-data-emit "envwins" gc info "" ) >/dev/null 2>&1
if printf '%s' "$(mirror_body)" | grep -q '"token_source":"env"'; then pass; else
  fail "env token must win over the baked file (ignore_changes rotation path)" "$(mirror_body)"; fi

# (f) THE ARGV REGRESSION GUARD. The -K - change has no other coverage: reverting either POST
#     to -H "Authorization: Bearer $TOK" leaves every other arm green.
if grep -qE '^\s*-H "Authorization: Bearer|^\s*-H "X-Sentry-Auth' "$TMP/git-data-emit"; then
  fail "a credential is back on curl argv (-H) instead of -K - on stdin" \
       "$(grep -nE '\-H "(Authorization|X-Sentry-Auth)' "$TMP/git-data-emit" | head -3)"
else pass; fi

# Restore the reachable sink for the arms below.
sed -i "s#-X POST 'http://127.0.0.1:1/bs'#-X POST 'http://127.0.0.1:${PORT}/bs'#" "$TMP/git-data-emit"

# ---------------------------------------------------------------------------------
# The Better Stack payload is built by a SEPARATE printf with its own format string, so
# nothing above covers it: every redaction assertion so far read the Sentry body. A
# regression in that second format string (an unsanitised $${MSG}, a detail interpolated
# before _clean) would ship a bare workspace UUID — which IS auth.users.id — to a sink
# whose pii_scrub_string does not scrub bare UUIDs.
#
# The two bodies are told apart structurally: Sentry nests everything under "tags",
# Better Stack is flat.
# ---------------------------------------------------------------------------------
: > "$CAPTURE"
BSPASS='Zt5w9QnB2xLmK7vR4pYd'
( cd "$TMP" && BETTERSTACK_LOGS_TOKEN=stub GIT_DATA_LUKS_KEY="$BSPASS" \
    ./git-data-emit "workspace ${UUID} down" boot_complete fatal \
    "cryptsetup: bad passphrase ${BSPASS} for ${UUID}" "luks_mounted=no" ) >/dev/null 2>&1
BS_BODY="$(grep -vF '"tags":' "$CAPTURE" | tail -1)"
if [ -n "$BS_BODY" ]; then pass; else fail "channel split: no flat (Better Stack) body was captured" "$(cat "$CAPTURE")"; fi
if grep -qiE "$UUID_RE" <<<"$BS_BODY"; then
  fail "Better Stack body: a bare workspace UUID reached the wire" "$BS_BODY"
else pass; fi
if grep -qF "$BSPASS" <<<"$BS_BODY"; then
  fail "Better Stack body: the LUKS passphrase reached the wire" "$BS_BODY"
else pass; fi
if grep -qF 'UUID_REDACTED' <<<"$BS_BODY" && grep -qF 'LUKS_KEY_REDACTED' <<<"$BS_BODY"; then pass; else
  fail "Better Stack body: redaction markers absent — the payload may bypass _clean" "$BS_BODY"
fi
if grep -qF '"luks_mounted":"no"' <<<"$BS_BODY"; then pass; else
  fail "Better Stack body: k=v tags are not carried (three consumers read them from HERE)" "$BS_BODY"
fi

# --- (#7460) THE INGEST TOKEN IS NOW IN EVERY EMIT'S ENVIRONMENT ------------------
# Before #7460 the token reached this script only under `doppler run`. It is now baked and
# loaded on EVERY emit, and 5.3 adds an emit whose entire subject is a failing Better Stack
# POST — the detail most likely to carry it. `_clean`'s `Bearer <tok>` pattern does not catch
# a BARE token, so this is a VALUE redaction (_devalue_bs), exactly like the LUKS passphrase.
#
# The token is fixtured as a distinctive high-entropy literal so a hit is unambiguous, and it
# is planted BARE in the DETAIL — the operator-controlled field that carries vendor error text
# on the path 5.3 introduces. BARE IS THE POINT: written as `Bearer <tok>` the pattern rule in
# `_clean` catches it and collapses the value redaction's own marker, so that fixture proves
# the PATTERN rule and says nothing about `_devalue_bs`. A vendor rejection quoting a bare
# token is the shape the value rule exists for.
: > "$CAPTURE"
BSTOK='Qk7vN2pR9wLmX4tZ8yHc'
( cd "$TMP" && BETTERSTACK_LOGS_TOKEN="$BSTOK" \
    ./git-data-emit "ingest rejected" betterstack_ingest warning \
    "vendor said: source token ${BSTOK} not valid" ) >/dev/null 2>&1
TOK_BODIES="$(cat "$CAPTURE")"
if [ -n "$TOK_BODIES" ]; then pass; else fail "#7460: no body captured for the ingest-token redaction arm" ""; fi
if grep -qF "$BSTOK" <<<"$TOK_BODIES"; then
  fail "#7460: the Better Stack INGEST TOKEN reached the wire" "$TOK_BODIES"
else pass; fi
if grep -qF 'BETTERSTACK_TOKEN_REDACTED' <<<"$TOK_BODIES"; then pass; else
  fail "#7460: the ingest-token redaction marker is absent — _devalue_bs did not run" "$TOK_BODIES"
fi

# --- Minimum-cardinality guard: a silently-empty harness must fail loud ---
total=$((passes + fails))
if [ "$total" -lt 59 ]; then
  echo "FAIL: ran only ${total} assertions (<47) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-emit: ${passes} passed, ${fails} failed (${total} assertions)"
# AN EXPLICIT exit, NOT A TRAILING TEST EXPRESSION. As the final statement, `[ "$fails" -eq 0 ]`
# makes the suite's exit status a property of whichever line happens to be LAST: appending any
# command after it (a printf, a stray echo) permanently greens the suite while it goes on
# printing accurate failure text, and run_suite() classifies on the exit code alone. Deleting
# the line has the same effect. Pre-existing; fixed here because #7460 is already editing this
# file and the sibling suites already carry the explicit form.
exit $(( fails > 0 ))
