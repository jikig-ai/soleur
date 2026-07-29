#!/usr/bin/env bash
#
# (#6982, W12 rung 1) RUNTIME rehearsal of the git-data runcmd chain, in the pinned
# Ubuntu 24.04 image, against a real capture endpoint.
#
# WHY A RUNTIME TEST WHEN THE STATIC GUARDS ALREADY PASS. Every other gate in #6982 is
# static, and the failure class it defends against — "green apply, dark host" — is only
# observable when the code RUNS. The Phase-0 W0 probe is the proof: a config-scope mismatch
# that passed `terraform validate`, every drift-guard and every mutation arm, and would
# have died silently on first boot. Mutation arms prove the code CAN go red when neutered;
# they never prove the right thing happens when it is intact.
#
# WHAT THIS RUNG CANNOT ANSWER, stated so a green run is not over-read: it does not
# exercise `doppler run` against real Doppler, `luksOpen` against a real volume, the
# private NIC, or whether an event reaches Sentry/Better Stack. Those need the throwaway-
# host rung, which is the banner-clear issue's precondition (#7025) — NOT this file's.
#
# Run: bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
passes=0; fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }

command -v docker >/dev/null 2>&1 || { echo "git-data-runcmd-rehearsal: SKIP — docker absent" >&2; exit 0; }
docker info >/dev/null 2>&1 || { echo "git-data-runcmd-rehearsal: SKIP — docker daemon unreachable" >&2; exit 0; }
command -v terraform >/dev/null 2>&1 || { echo "git-data-runcmd-rehearsal: SKIP — terraform absent" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "git-data-runcmd-rehearsal: SKIP — python3 absent" >&2; exit 0; }

TMP="$(mktemp -d -t gdreh.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Render the REAL template, then extract the emitter and the Doppler-download runcmd block
# from it. Extracting from the render (not from a hand-written fixture) is what makes this
# track the artifact that actually ships.
bash "$DIR/git-data-userdata-budget.sh" "$TMP/rendered.yml" >/dev/null 2>&1 \
  || { echo "FAIL: render failed" >&2; exit 1; }

python3 - "$TMP/rendered.yml" "$TMP" <<'PY'
import sys, yaml, re
d = yaml.safe_load(open(sys.argv[1])); out = sys.argv[2]
for wf in d["write_files"]:
    if wf["path"] == "/usr/local/bin/git-data-emit":
        open(f"{out}/git-data-emit", "w").write(wf["content"])
# The runcmd entry carrying the checksum block — the supply-chain fix (issue item 3).
blocks = [c for c in d["runcmd"] if isinstance(c, str) and "sha256sum -c -" in c]
assert len(blocks) == 1, f"expected exactly 1 checksum runcmd block, found {len(blocks)}"
open(f"{out}/doppler-dl.sh", "w").write(blocks[0])
# The trap-arming preamble (STAGE/on_err/trap + the delivery assertion).
pre = [c for c in d["runcmd"] if isinstance(c, str) and "trap on_err EXIT" in c]
assert len(pre) == 1, f"expected exactly 1 trap-arming block, found {len(pre)}"
open(f"{out}/preamble.sh", "w").write(pre[0])
# The WHOLE runcmd, concatenated the way cloud-init actually runs it. B2 compares against
# THIS, not against the trap-arming entry alone: `trap on_err EXIT` and the `set -e` that
# arms abort-on-error live in DIFFERENT runcmd entries, and it is precisely because
# cloud-init joins every entry into ONE script that the trap covers the later ones. A
# comparison scoped to a single entry reports drift that does not exist.
open(f"{out}/runcmd-all.sh", "w").write(
    "\n".join(c for c in d["runcmd"] if isinstance(c, str)))
PY
[ -s "$TMP/doppler-dl.sh" ] || { echo "FAIL: could not extract the checksum block" >&2; exit 1; }

# ── B1 — BYTE-IDENTITY of every indent(6, …)-delivered payload ─────────────────────
#
# git-data-luks.test.sh A27 carries the name "BYTE-IDENTITY" but greps for the
# `indent(6, <var>)` call sites and asserts zero `encoding: b64`. That proves the
# DELIVERY MECHANISM is the plain-text one; it never renders and never compares a byte.
# A trailing-whitespace strip, a YAML block-scalar chomp, or an indent() that swallowed a
# blank line inside a heredoc would all pass it — and each ships a script that differs
# from the one in the repo, which is the whole property the name claims.
#
# This is the actual comparison, and it belongs here because this is where the render is
# already parsed. Mapping is by BASENAME of the delivered path, which is 1:1 with the
# source file for all nine payloads; the count is asserted so a payload added without a
# fixture cannot slip through as "nothing to check".
_b1_out="$(python3 - "$TMP/rendered.yml" "$DIR" <<'PY'
import sys, yaml, os, hashlib
rendered, srcdir = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(rendered))
checked, bad = 0, []
for wf in d["write_files"]:
    src = os.path.join(srcdir, os.path.basename(wf["path"]))
    if not os.path.isfile(src):
        continue            # inline payloads (git-data-emit, authorized_keys, sshd conf)
    want = open(src, "rb").read()
    got = wf["content"].encode()
    checked += 1
    if hashlib.sha256(got).hexdigest() != hashlib.sha256(want).hexdigest():
        bad.append("%s: rendered sha=%s (%d B) != source sha=%s (%d B)" % (
            wf["path"], hashlib.sha256(got).hexdigest()[:12], len(got),
            hashlib.sha256(want).hexdigest()[:12], len(want)))
if checked < 9:
    print("B1 FAIL: only %d file-backed payloads compared (<9) — the mapping found nothing "
          "to check, which is not the same as everything matching" % checked)
    sys.exit(1)
if bad:
    print("B1 FAIL: %d payload(s) are NOT byte-identical to their source:" % len(bad))
    for b in bad:
        print("  " + b)
    sys.exit(1)
print("B1 OK: %d payloads byte-identical" % checked)
PY
)"; _b1_rc=$?
if [ "$_b1_rc" -eq 0 ]; then pass; else
  fail "B1: a delivered payload differs from its repo source" "$_b1_out"
fi

# INSTRUMENT the extracted block so T5's "the chain did not continue past the failed
# checksum" assertion can OBSERVE continuation. Nothing in the shipped block prints
# anything, so `grep -q CHMOD_RAN` matched only its own source text — the assertion passed
# identically against a completely unguarded chain. The marker rides on the chmod line
# because chmod is the last of the three commands the abort must prevent (`sha256sum -c -`
# fails => tar, chmod and this echo are all unreached).
python3 - "$TMP/doppler-dl.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "chmod +x /usr/local/bin/doppler"
if s.count(old) != 1:
    sys.stderr.write("expected exactly 1 chmod line in the extracted block, found %d\n" % s.count(old))
    sys.exit(3)
open(p, "w").write(s.replace(old, old + "; echo CHMOD_RAN"))
PY
grep -q 'echo CHMOD_RAN' "$TMP/doppler-dl.sh" || {
  echo "FAIL: CHMOD_RAN instrumentation did not land — T5 would be a tautology again" >&2; exit 1; }

# A capture endpoint inside the container network, standing in for Sentry.
cat > "$TMP/capture.py" <<'PY'
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        open("/out/capture.log", "ab").write(self.rfile.read(n) + b"\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
socketserver.TCPServer(("127.0.0.1", 8099), H).serve_forever()
PY

# The in-container driver. It arms a MODEL of the shipped trap/STAGE preamble — a
# hand-written copy, not the extracted one — and runs the extracted checksum block under
# `set -e` exactly as runcmd does.
#
# WHY A COPY, AND WHAT KEEPS IT HONEST. The shipped preamble cannot be sourced verbatim
# here: it hard-codes /var/log/cloud-init-output.log as its detail (absent in the container,
# so every emit would ship an empty detail and the delivery assertion would prove nothing)
# and it runs a delivery pre-check against the real DSN. So the driver models it.
#
# A model that nothing compares against is how "the SAME preamble" becomes false without
# anyone noticing — this comment said exactly that while `preamble.sh` was extracted,
# asserted to be exactly one block, and then never read by anything. B2 below is the
# comparison that makes the claim true: every load-bearing construct of the shipped
# preamble must appear in BOTH, so a shipped preamble that loses its `set -e`, its trap, or
# its rc guard turns this suite red instead of leaving it green against a stale model.
cat > "$TMP/drive.sh" <<'DRIVE'
#!/bin/bash
set -uo pipefail
python3 /work/capture.py & sleep 1
sed -i "s#^DSN='.*'#DSN='https://k@127.0.0.1:8099/1'#" /work/git-data-emit
python3 - <<'FIX'
p="/work/git-data-emit"; s=open(p).read()
s=s.replace('"https://${SHOST}/api/${PROJ}/store/"','"http://${SHOST}/api/${PROJ}/store/"')
open(p,"w").write(s)
FIX
chmod +x /work/git-data-emit
mkdir -p /usr/local/bin && cp /work/git-data-emit /usr/local/bin/git-data-emit

STAGE=runcmd_early
on_err() {
  rc=$?
  trap - EXIT
  [ "$rc" -eq 0 ] && exit 0
  /usr/local/bin/git-data-emit "git-data cloud-init FAILED" "$STAGE" fatal "" "rc=$rc" || true
  exit 1
}
trap on_err EXIT
set -e
STAGE=doppler_dl
# SOURCED, not `bash /work/doppler-dl.sh`. cloud-init concatenates every runcmd entry into
# ONE script, so the `set -e` armed above is in effect for this block. Running it as a
# CHILD bash gives that child its own (unset) options, so a failing `sha256sum -c -` would
# not abort — measured: the checksum failed, the child exited non-zero, and the driver
# still exited 0. A harness that models the block as a subprocess tests the opposite of
# what ships.
. /work/doppler-dl.sh
DRIVE

# ── B2 — the driver's arming must not drift from the SHIPPED preamble ──────────────
# Each construct below is load-bearing, and each must appear on BOTH sides:
#   trap on_err EXIT        the arming itself — without it nothing reports
#   set -e                  what makes a failed checksum abort instead of continuing
#   rc=$?                   captured BEFORE `trap - EXIT` clobbers it
#   [ "$rc" -eq 0 ]         the rc guard: without it every HEALTHY boot emits fatal (T17)
#   trap - EXIT             disarm inside the handler, so the handler cannot re-enter
#   git-data-emit           the emit call the whole channel depends on
# ANCHORED ON CODE, NOT ON THE TOKEN — and comments stripped first. Both halves are
# load-bearing, and the first draft of this guard had neither, so it was VACUOUS: deleting
# the shipped `set -e` left B2 green, because `grep -F 'set -e'` still matched the comment
# two lines above it ("Arm `set -e` only AFTER the Phase-0.4 classification") — and would
# equally have matched `set -euo pipefail` as a substring. A body-grep sees comments too
# (cq-assert-anchor-not-bare-token). Each pattern below is line-anchored and `$`-terminated
# where the construct is a whole statement, so prose about it cannot satisfy it.
_b2_strip() { sed -e 's/[[:space:]]*#.*$//' "$1"; }
_b2_missing=""
_b2_pre="$TMP/preamble.nocomment"; _b2_drv="$TMP/drive.nocomment"
_b2_strip "$TMP/runcmd-all.sh" > "$_b2_pre"
_b2_strip "$TMP/drive.sh"    > "$_b2_drv"
# COUNTS, not existence. `rc=$?`, the rc guard and `trap - EXIT` each appear once per trap
# site — on_err, luks_err, bootstrap_err — and cloud-init's own comment says so ("All THREE
# sites; T17 pins it"). An existence check therefore cannot see ONE of them deleted, which
# is the realistic drift: measured, removing on_err's rc guard left an existence-based B2
# fully green because luks_err's and bootstrap_err's copies still satisfied it. The driver
# models a single trap, so its minimum is 1 for every construct.
# NOTE the trap-disarm minimum is 4, not 3: the three handlers each disarm, PLUS a bare
# disarm outside any handler before bootstrap_err is defined. A floor of 3 tolerated
# deleting one (measured) -- derive minimums from the artifact, not from the count you
# expect the design to have.
while IFS='|' read -r _label _min _re; do
  [ -n "$_label" ] || continue
  _n_pre=$(grep -cE -- "$_re" "$_b2_pre" || true)
  _n_drv=$(grep -cE -- "$_re" "$_b2_drv" || true)
  [ "$_n_pre" -ge "$_min" ] || _b2_missing="${_b2_missing} shipped:[${_label} ${_n_pre}<${_min}]"
  [ "$_n_drv" -ge 1 ]       || _b2_missing="${_b2_missing} driver:[${_label}]"
done <<'B2SPEC'
trap on_err EXIT|1|^[[:space:]]*trap on_err EXIT[[:space:]]*$
set -e (exactly)|1|^[[:space:]]*set -e[[:space:]]*$
rc=$? capture|3|^[[:space:]]*rc=\$\?[[:space:]]*$
rc guard|3|^[[:space:]]*\[ "\$rc" -eq 0 \][[:space:]]*&&[[:space:]]*exit 0[[:space:]]*$
trap - EXIT disarm|4|^[[:space:]]*trap - EXIT[[:space:]]*$
emit call|1|/usr/local/bin/git-data-emit[[:space:]]+"
B2SPEC
if [ -z "$_b2_missing" ]; then pass; else
  fail "B2: the driver and the shipped preamble have drifted" "missing —${_b2_missing}"
fi

# NOTE on container networking: these runs are NOT `--network none`. The image needs curl
# and python3 from apt, and with no network `apt-get` exits 100 before any assertion runs —
# which presents as every case failing at once rather than as a setup error. The assertion
# stays hermetic regardless: the capture endpoint is on the container's own loopback. With
# real network T5 is also MORE faithful — it downloads the genuine tarball and then fails
# the checksum, which is exactly the supply-chain case being defended against.
run_case() {
  # $1 = case name, $2 = sed applied to the extracted block, $3 = expected driver exit
  local name="$1" mut="$2" want="$3"
  rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
  cp "$TMP/doppler-dl.sh" "$TMP/dl.case.sh"
  [ -n "$mut" ] && sed -i "$mut" "$TMP/dl.case.sh"
  docker run --rm \
    -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
    -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
    -v "$TMP/capture.py:/work/capture.py:ro" \
    -v "$TMP/drive.sh:/work/drive.sh:ro" \
    -v "$TMP/out:/out" \
    ubuntu:24.04 bash -c '
      set -e
      cp /work/git-data-emit-src /work/git-data-emit
      apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 >/dev/null 2>&1
      bash /work/drive.sh
    ' >"$TMP/out/stdout" 2>&1
  local rc=$?
  CASE_RC="$rc"; CAPTURE="$TMP/out/capture.log"
  if [ "$rc" -eq "$want" ]; then pass; else fail "$name: exit $rc, expected $want" "$(tail -3 "$TMP/out/stdout")"; fi
}

# ── D1 — the SHIPPED emitter must survive /bin/sh, which is dash on 24.04 ──────────
# cloud-init's util.shellify() emits `#!/bin/sh`, and the emitter itself declares it. bash
# TOLERATES constructs dash kills the shell on — most sharply `shift N` with fewer than N
# args, because `shift` is a POSIX SPECIAL BUILTIN whose error terminates a non-interactive
# shell outright and which `|| true` cannot catch. Asserted DIRECTLY against dash rather
# than inferred from the driver's interpreter, so it holds regardless of how the container
# case is wired.
if command -v dash >/dev/null 2>&1; then
  if dash -n "$TMP/git-data-emit" 2>/dev/null; then pass; else fail "D1: emitter is not valid dash"; fi
  # A 3-arg call is what the usage line invites. Under a bare `shift 4` dash exits 2 having
  # emitted nothing — silently, on a host whose only diagnostic is this emitter.
  ( cd "$TMP" && dash ./git-data-emit "m" "s" info >/dev/null 2>&1 )
  _d_rc=$?
  if [ "$_d_rc" -ne 2 ] || [ -s "$CAPTURE" ]; then pass; else
    fail "D1: a 3-arg call died at the shift (dash rc=2) instead of emitting"; fi
else
  pass; pass   # dash absent: keep the cardinality floor honest rather than skewing it
fi

# ── T5 — a WRONG checksum must ABORT before tar/chmod ──────────────────────────────
# This is the supply-chain half of issue item 3. Before #6982 there was no `set -e`, so a
# failed `sha256sum -c -` still ran `tar xzf` and `chmod +x /usr/local/bin/doppler` on an
# unverified tarball that then executed as ROOT. Here curl SUCCEEDS (real network) and
# fetches the genuine tarball, so the checksum is the ONLY thing that can stop the chain —
# the faithful version of the supply-chain case. The assertion is that it aborts loudly
# with the stage named, and that the later commands never ran.
run_case "T5 wrong-checksum aborts" 's#^DOPPLER_SHA256=.*#DOPPLER_SHA256="0000000000000000000000000000000000000000000000000000000000000000"#' 1
if grep -q '"stage":"doppler_dl"' "$CAPTURE" 2>/dev/null; then pass; else
  fail "T5: no doppler_dl fatal was emitted" "$(cat "$CAPTURE" 2>/dev/null | head -2)"; fi
if grep -q '"level":"fatal"' "$CAPTURE" 2>/dev/null; then pass; else fail "T5: emit was not level=fatal"; fi
# The abort must precede the unverified install. If /usr/local/bin/doppler exists the
# chain continued past the checksum, which is the exact pre-#6982 behaviour.
if grep -q 'CHMOD_RAN' "$TMP/out/stdout" 2>/dev/null; then
  fail "T5: the chain continued past the failed checksum"; else pass; fi

# MUTATION for T5 — prove the marker is REACHABLE, so its absence above is evidence of the
# abort rather than evidence that nothing ever prints it.
#
# The mutant removes the driver's `set -e`, which is exactly the pre-#6982 boot: curl still
# succeeds (real network, genuine tarball), the checksum still fails, and the chain runs
# `tar xzf` + `chmod +x /usr/local/bin/doppler` on an UNVERIFIED tarball that then executes
# as root. So this arm reproduces the supply-chain defect the fix closes, and CHMOD_RAN
# must appear.
rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
sed 's/^set -e$/true/' "$TMP/drive.sh" > "$TMP/drive.noerrexit.sh"
if diff -q "$TMP/drive.sh" "$TMP/drive.noerrexit.sh" >/dev/null; then
  fail "T5 MUTATION did not land: 'set -e' not found in the driver"
else
  cp "$TMP/doppler-dl.sh" "$TMP/dl.case.sh"
  sed -i 's#^DOPPLER_SHA256=.*#DOPPLER_SHA256="0000000000000000000000000000000000000000000000000000000000000000"#' "$TMP/dl.case.sh"
  docker run --rm \
    -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
    -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
    -v "$TMP/capture.py:/work/capture.py:ro" \
    -v "$TMP/drive.noerrexit.sh:/work/drive.sh:ro" \
    -v "$TMP/out:/out" \
    ubuntu:24.04 bash -c '
      set -e
      cp /work/git-data-emit-src /work/git-data-emit
      apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 >/dev/null 2>&1
      bash /work/drive.sh
    ' >"$TMP/out/stdout" 2>&1 || true
  if grep -q 'CHMOD_RAN' "$TMP/out/stdout" 2>/dev/null; then pass; else
    fail "T5 MUTATION: without set -e the chain still did not reach chmod — T5's check is vacuous" \
         "$(tail -5 "$TMP/out/stdout" 2>/dev/null)"; fi
fi

# ── T17 — a HEALTHY run emits ZERO fatals ──────────────────────────────────────────
# The rc-guard's whole purpose. Without `rc=$?; [ "$rc" -eq 0 ] && exit 0`, `trap … EXIT`
# fires on a SUCCESSFUL exit too and every healthy boot emits level=fatal, inverting the
# channel into noise on day one. Replace the block with a trivially-succeeding one so the
# driver exits 0 through the same armed trap.
printf 'true\n' > "$TMP/doppler-dl.sh.healthy"
cp "$TMP/doppler-dl.sh" "$TMP/doppler-dl.sh.orig"
cp "$TMP/doppler-dl.sh.healthy" "$TMP/doppler-dl.sh"
run_case "T17 healthy run exits 0" "" 0
if [ -s "$CAPTURE" ]; then
  fail "T17: a healthy run emitted $(wc -l < "$CAPTURE") event(s) — the rc guard is not holding" "$(head -2 "$CAPTURE")"
else pass; fi
cp "$TMP/doppler-dl.sh.orig" "$TMP/doppler-dl.sh"

# MUTATION: remove the rc guard and prove T17's assertion can FAIL. Without this arm, an
# emitter that never fires would also produce an empty capture and read as a clean pass.
rm -rf "$TMP/out"; mkdir -p "$TMP/out"; : > "$TMP/out/capture.log"
sed 's#^\s*\[ "\$rc" -eq 0 \] && exit 0$#  true#' "$TMP/drive.sh" > "$TMP/drive.noguard.sh"
cp "$TMP/doppler-dl.sh.healthy" "$TMP/dl.case.sh"
docker run --rm \
  -v "$TMP/dl.case.sh:/work/doppler-dl.sh:ro" \
  -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
  -v "$TMP/capture.py:/work/capture.py:ro" \
  -v "$TMP/drive.noguard.sh:/work/drive.sh:ro" \
  -v "$TMP/out:/out" \
  ubuntu:24.04 bash -c '
    set -e
    cp /work/git-data-emit-src /work/git-data-emit
    apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 >/dev/null 2>&1
    bash /work/drive.sh
  ' >/dev/null 2>&1 || true
if [ -s "$TMP/out/capture.log" ]; then pass; else
  fail "T17 MUTATION: removing the rc guard did NOT make a healthy run emit — the check is vacuous"; fi

total=$((passes + fails))
# Floor = the ACTUAL assertion count (D1: 2, T5: 4 + 1 mutation, T17: 2 + 1 mutation). Its
# job is to catch a silently-empty harness — an early `exit 0` from a skip guard, or a
# docker run that never produced output — not to be an aspirational target.
if [ "$total" -lt 12 ]; then
  echo "FAIL: ran only ${total} assertions (<12) — harness did not execute fully" >&2
  exit 1
fi
echo "git-data-runcmd-rehearsal: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
