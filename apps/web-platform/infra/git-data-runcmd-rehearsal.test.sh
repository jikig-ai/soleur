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

# B5: A SKIP IS NOT A PASS, AND UNDER CI IT IS NOT EVEN A SKIP. Every guard below exits 0 when
# a tool is missing, which is right on a laptop and wrong in CI: the runner is the one place
# this suite is REQUIRED to execute, and a missing dependency there silently converts a
# runtime gate into a green no-op that nothing distinguishes from a real pass. Under CI=true
# the absence is a FAILURE of the runner's provisioning, reported as such.
_skip() {
  if [ "${CI:-}" = "true" ]; then
    echo "$1 — and CI=true, so this is a FAILURE: the runner must provide this dependency. A gate that cannot run must not report success." >&2
    exit 1
  fi
  echo "$1" >&2
  exit 0
}

command -v docker >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — docker absent"
docker info >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — docker daemon unreachable"
command -v terraform >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — terraform absent"
command -v python3 >/dev/null 2>&1 || _skip "git-data-runcmd-rehearsal: SKIP — python3 absent"

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
    # (#7025, S1) The hardening drop-in, so the sshd stage is validated against the REAL
    # directives rather than against a stock sshd_config that would exercise nothing.
    if wf["path"] == "/etc/ssh/sshd_config.d/01-hardening.conf":
        open(f"{out}/01-hardening.conf", "w").write(wf["content"])
# (#7025, S1) The sshd_config stage. Extracted from the render for the same reason every
# other block here is: a hand-written copy would keep passing after the shipped one drifted.
sshd = [c for c in d["runcmd"] if isinstance(c, str) and "STAGE=sshd_config" in c]
assert len(sshd) == 1, f"expected exactly 1 sshd_config runcmd block, found {len(sshd)}"
open(f"{out}/sshd-stage.sh", "w").write(sshd[0])
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
# already parsed.
#
# IT ASSERTS A SET, IN BOTH DIRECTIONS, NOT A COUNT. The first version of this check mapped
# each delivered path to `<srcdir>/<basename>`, `continue`d when no such file existed, and
# floored on `checked >= 9`. Three ways that is narrower than the property it names:
#
#   1. UNCHECKED PAYLOADS. The bare `continue` cannot tell "legitimately inline" from
#      "should have been file-backed, but the basename stopped resolving". A payload that
#      falls out of the mapping is silently not compared, and silence reads as a pass.
#   2. A COUNT IS NOT A SET. Dropping one file-backed payload while any other resolves keeps
#      the total at 9. Measured fail-open.
#   3. DUPLICATE BASENAMES could satisfy the count twice while a real member went missing.
#
# So the expected set is derived from the AUTHORITATIVE producer — the `indent(6, <var>)`
# call sites in the template, resolved through the render module's `<var> = file(".../<name>")`
# bindings — and compared as a set against what was actually delivered. Every inline payload
# is named in an explicit allowlist; an unrecognised path is a FAILURE, not a skip.
_b1_out="$(python3 - "$TMP/rendered.yml" "$DIR" <<'PY'
import sys, yaml, os, re, hashlib
rendered, srcdir = sys.argv[1], sys.argv[2]

# Payloads written inline in the template rather than from a repo file. Explicit, because
# "no source file found" must not be self-certifying. These are NOT exempt from the
# duplicate check below — an attacker-supplied second entry at an allowlisted path (a
# permissive authorized_keys, a relaxed sshd_config) is precisely the escape an exemption
# would open, and cloud-init applies write_files in order so the LAST one wins.
INLINE_ALLOWLIST = {
    "/usr/local/bin/git-data-emit",
    "/home/git/.ssh/authorized_keys",
    "/etc/ssh/sshd_config.d/01-hardening.conf",
}
# An absolute floor, NOT a self-derived one. The first rewrite of this check derived the
# expected roster from cloud-init-git-data.yml — the same artifact that produces the
# delivered set — so deleting a payload shrank BOTH sides and the equality held. Measured:
# deleting the git-data-gc.timer block reported "OK: 8 payloads". That was a net REGRESSION
# against the `checked >= 9` floor it replaced, in the arm whose comment claimed to have
# fixed a measured fail-open. The roster authority is modules/git-data-userdata/main.tf (it
# moved there in #7025/R7 so both roots render from one map); the floor is absolute.
MIN_PAYLOADS = 9

# THE DESTINATION CONTRACT, OWNED BY THIS TEST. Deriving the expected path from the template
# too would re-create the tautology one level down: relocating a payload moves BOTH sides and
# the equality holds. Measured — moving git-data-gc.timer to /tmp/junk/ (same basename, same
# bytes) passed a derivation-based check while systemd would never see the unit again.
#
# These paths are load-bearing, not incidental: /etc/systemd/system is where systemd looks,
# /usr/local/bin is what the authorized_keys forced commands name, and /tmp is where the
# placeholder is staged for the bootstrap to install. A deliberate move must edit this map,
# which is the review point.
EXPECTED_PATHS = {
    "git_data_bootstrap":               "/usr/local/bin/git-data-bootstrap.sh",
    "git_data_provision":               "/usr/local/bin/git-data-provision.sh",
    "git_data_transport_wrapper":       "/usr/local/bin/git-data-transport-wrapper.sh",
    "git_data_remove":                  "/usr/local/bin/git-data-remove.sh",
    "git_data_gc":                      "/usr/local/bin/git-data-gc.sh",
    "git_data_gc_service":              "/etc/systemd/system/git-data-gc.service",
    "git_data_gc_failure_service":      "/etc/systemd/system/git-data-gc-failure.service",
    "git_data_gc_timer":                "/etc/systemd/system/git-data-gc.timer",
    "git_data_pre_receive_placeholder": "/tmp/git-data-pre-receive-placeholder.sh",
}

# (#7025, R7) The templatefile map and the strip expression moved out of git-data.tf and into
# modules/git-data-userdata/main.tf, which BOTH the production root and the rung-2 rehearsal
# root call. `${path.module}` there is the MODULE dir, so every binding reads `../../<name>`
# and must be resolved against moduledir — resolving against srcdir lands two levels too high
# and every payload would fail to open.
moduledir = os.path.join(srcdir, "modules", "git-data-userdata")
tf = open(os.path.join(moduledir, "main.tf")).read()
tpl = open(os.path.join(srcdir, "cloud-init-git-data.yml")).read()

# The payloads are delivered with whole-line `#` comments stripped at render time (ADR-152),
# so the source must be stripped the same way before the bytes are compared. Read the
# expression FROM git-data.tf rather than restating it: a hand-copied spelling would drift,
# and a stripper that silently disagreed with production would make this whole check compare
# the wrong bytes while still reporting byte-identity.
m = re.search(r'git_data_rationale_strip\s*=\s*"(.*)"', tf)
if not m:
    print("B1 FAIL: no git_data_rationale_strip in modules/git-data-userdata/main.tf — cannot mirror the render-time strip")
    sys.exit(1)
_expr = m.group(1)
if not (_expr.startswith("/") and _expr.endswith("/")):
    print("B1 FAIL: git_data_rationale_strip is not a /…/ regex literal: %r" % _expr)
    sys.exit(1)
STRIP = re.compile(_expr[1:-1].replace("\\t", "\t").replace("\\n", "\n"))
if not STRIP.search("#!/bin/sh\n# a comment\n"):
    print("B1 FAIL: the strip expression matches nothing on a known-commented probe — it "
          "would make every payload trivially 'identical'")
    sys.exit(1)

# ROSTER AUTHORITY: the render module's file() bindings. var -> source path, RELATIVE TO
# THE MODULE DIR (it is written `../../<name>`; see the moduledir note above).
bindings = dict(re.findall(
    r'^\s*([a-z_]+)\s*=\s*(?:replace\()?file\("\$\{path\.module\}/([^"]+)"\)', tf, re.M))
if len(bindings) < MIN_PAYLOADS:
    print("B1 FAIL: the render module binds only %d payload file()s (<%d) — the roster extraction "
          "drifted, and a shrunken roster would make every check below vacuous"
          % (len(bindings), MIN_PAYLOADS))
    sys.exit(1)

# PATH AUTHORITY: the template pairs `- path: <P>` with `${indent(6, <var>)}`. This is what
# says WHERE each payload lands; identity is the FULL PATH, never the basename (relocating
# git-data-gc.timer to /tmp/junk/ keeps its basename and its bytes, and systemd never sees it).
delivery = dict((v, pth) for pth, v in re.findall(
    r'-\s*path:\s*(\S+)\s*\n\s*content:\s*\|\s*\n\s*\$\{indent\(6,\s*([a-z_]+)\)\}', tpl))

undelivered = sorted(v for v in bindings if v not in delivery)
if undelivered:
    print("B1 FAIL: %d payload(s) bound by file() in the render module are NOT delivered by any "
          "indent(6, …) block in cloud-init-git-data.yml: %s"
          % (len(undelivered), ", ".join(undelivered)))
    print("  A payload the render module reads but the template never writes is a file the "
          "host will not have. If it is genuinely retired, remove its file() binding too.")
    sys.exit(1)

# The template must deliver each payload to the path this test pins, not merely to SOME path.
misrouted = sorted(
    "%s -> %s (expected %s)" % (v, delivery[v], EXPECTED_PATHS[v])
    for v in bindings if v in EXPECTED_PATHS and delivery[v] != EXPECTED_PATHS[v])
if misrouted:
    print("B1 FAIL: %d payload(s) are delivered to the WRONG PATH — same bytes, same "
          "basename, wrong destination, so the consumer never sees them:" % len(misrouted))
    for mr in misrouted:
        print("  " + mr)
    sys.exit(1)
unpinned = sorted(v for v in bindings if v not in EXPECTED_PATHS)
if unpinned:
    print("B1 FAIL: %d payload(s) have no pinned destination in EXPECTED_PATHS: %s"
          % (len(unpinned), ", ".join(unpinned)))
    print("  Add the destination to EXPECTED_PATHS so a later relocation is a review event.")
    sys.exit(1)

expected = {EXPECTED_PATHS[v]: bindings[v] for v in bindings}   # full path -> source filename

d = yaml.safe_load(open(rendered))
seen_paths, delivered, unknown, bad = [], {}, [], []
for wf in d["write_files"]:
    path = wf["path"]
    seen_paths.append(path)
    if path in expected:
        delivered[path] = wf["content"].encode()
    elif path not in INLINE_ALLOWLIST:
        unknown.append(path)

dupes = sorted({p for p in seen_paths if seen_paths.count(p) > 1})
if dupes:
    print("B1 FAIL: duplicate write_files path(s) %s — cloud-init applies in ORDER, so a "
          "second entry at a delivered or allowlisted path silently overrides the first "
          "(an unrestricted authorized_keys beats three command=-restricted ones)"
          % ", ".join(dupes))
    sys.exit(1)

if unknown:
    print("B1 FAIL: %d delivered payload(s) are neither a known file-backed source nor on "
          "the inline allowlist, so nothing compared their bytes:" % len(unknown))
    for u in unknown:
        print("  " + u)
    sys.exit(1)

missing = sorted(set(expected) - set(delivered))
if missing:
    print("B1 FAIL: %d expected payload path(s) were never delivered: %s"
          % (len(missing), ", ".join(missing)))
    sys.exit(1)

if len(delivered) < MIN_PAYLOADS:
    print("B1 FAIL: only %d file-backed payloads compared (<%d)" % (len(delivered), MIN_PAYLOADS))
    sys.exit(1)

for path in sorted(delivered):
    want = STRIP.sub("", open(os.path.join(moduledir, expected[path])).read()).encode()
    got = delivered[path]
    if hashlib.sha256(got).hexdigest() != hashlib.sha256(want).hexdigest():
        bad.append("%s: rendered sha=%s (%d B) != stripped source sha=%s (%d B)" % (
            path, hashlib.sha256(got).hexdigest()[:12], len(got),
            hashlib.sha256(want).hexdigest()[:12], len(want)))
if bad:
    print("B1 FAIL: %d payload(s) are NOT byte-identical to their stripped source:" % len(bad))
    for b in bad:
        print("  " + b)
    sys.exit(1)

print("B1 OK: %d file-backed payloads delivered at their exact paths, byte-identical to the "
      "stripped source; %d inline payload(s) allowlisted; no duplicate paths"
      % (len(delivered), len(INLINE_ALLOWLIST)))
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

# ── S1 — the sshd_config stage must SURVIVE a fresh 24.04 boot ─────────────────────
#
# (#7025) THIS ARM EXISTS BECAUSE THE STAGE DID NOT SURVIVE ONE. `sshd -t` validates the
# privilege-separation directory as well as the config text, and ubuntu-24.04 ships ssh
# socket-activated: /run/sshd is created by ssh.service's `RuntimeDirectory=sshd`, which has
# not run at runcmd time. So `sshd -t` exited 255 "Missing privilege separation directory:
# /run/sshd" on every fresh boot, the stage took its fatal branch, and cloud-init aborted
# BEFORE LUKS — a host that answers nothing, on a route whose whole purpose is to catch that.
# Measured on rehearsal hosts -rehearsal-30560266736 and -30581408745; found only because the
# emitter ships `sshd -t`'s stderr and Sentry kept it.
#
# EVERY STATIC GUARD PASSED THE BROKEN VERSION, and would still: the template was well-formed,
# the drop-in was valid, the branch logic was right. The missing precondition is only visible
# when the stage RUNS in the pinned image — which is what this file is for.
#
# The stage is run under `sh` with errexit OFF, matching the shipped chain: the template arms
# `set -e` in a LATER runcmd entry, and production evidence confirms it (the failing `sshd -t`
# was followed by `_sshd_t_rc=$?` and an emit, neither of which runs under errexit).
if [ -s "$TMP/sshd-stage.sh" ] && [ -s "$TMP/01-hardening.conf" ]; then
  cat > "$TMP/sshd-drive.sh" <<'S1DRV'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq openssh-server >/dev/null 2>&1
mkdir -p /etc/ssh/sshd_config.d
cp /work/01-hardening.conf /etc/ssh/sshd_config.d/01-hardening.conf
# Stub the emitter: D1/T5/T17 already cover the real one end-to-end. What S1 needs is a
# record of WHICH stage/level fired and the detail file it shipped.
cat > /usr/local/bin/git-data-emit <<'EMIT'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >> /out/sshd-capture.log
if [ -n "$4" ] && [ -r "$4" ]; then sed 's/^/detail: /' "$4" >> /out/sshd-capture.log; fi
exit 0
EMIT
chmod +x /usr/local/bin/git-data-emit
# Stub systemctl on /usr/local/bin (ahead of /usr/bin on Ubuntu's default PATH) — the stage
# calls it bare. There is no init in a container; the restart's tolerance is not what S1 tests.
printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/systemctl
chmod +x /usr/local/bin/systemctl
set +e
sh /work/sshd-stage.sh
echo "STAGE_RC=$?"
S1DRV

  _s1_run() { # $1 = stage script to mount
    rm -rf "$TMP/s1out"; mkdir -p "$TMP/s1out"; : > "$TMP/s1out/sshd-capture.log"
    docker run --rm \
      -v "$1:/work/sshd-stage.sh:ro" \
      -v "$TMP/01-hardening.conf:/work/01-hardening.conf:ro" \
      -v "$TMP/sshd-drive.sh:/work/sshd-drive.sh:ro" \
      -v "$TMP/s1out:/out" \
      ubuntu:24.04 bash /work/sshd-drive.sh >"$TMP/s1out/stdout" 2>&1
    S1_RC="$(sed -n 's/^STAGE_RC=//p' "$TMP/s1out/stdout" | tail -1)"
    S1_CAP="$TMP/s1out/sshd-capture.log"
  }

  _s1_run "$TMP/sshd-stage.sh"
  if [ "${S1_RC:-none}" = "0" ]; then pass; else
    fail "S1: the sshd_config stage exited ${S1_RC:-<no marker>} on a fresh 24.04 — this is the boot abort" \
         "$(tail -5 "$TMP/s1out/stdout" 2>/dev/null)"; fi
  if grep -q '|sshd_config|fatal' "$S1_CAP" 2>/dev/null; then
    fail "S1: the stage emitted a sshd_config fatal on a healthy boot" "$(head -3 "$S1_CAP")"
  else pass; fi

  # MUTATION — remove the mkdir and prove S1 reproduces the MEASURED production failure, not
  # merely "some" failure. Without this the two asserts above would also pass on a stage that
  # never ran sshd -t at all.
  sed '/^[[:space:]]*mkdir -p \/run\/sshd[[:space:]]*$/d' "$TMP/sshd-stage.sh" > "$TMP/sshd-stage.nomkdir.sh"
  if diff -q "$TMP/sshd-stage.sh" "$TMP/sshd-stage.nomkdir.sh" >/dev/null; then
    fail "S1 MUTATION did not land: no 'mkdir -p /run/sshd' line in the shipped sshd stage" \
         "The fix this arm guards is absent — S1's green above certifies nothing."
    fail "S1 MUTATION: skipped (mutation did not land)"
    fail "S1 MUTATION: skipped (mutation did not land)"
    fail "S1 MUTATION: skipped (mutation did not land)"
  else
    pass
    _s1_run "$TMP/sshd-stage.nomkdir.sh"
    if [ "${S1_RC:-none}" = "1" ]; then pass; else
      fail "S1 MUTATION: without the mkdir the stage exited ${S1_RC:-<no marker>}, expected 1" \
           "$(tail -5 "$TMP/s1out/stdout" 2>/dev/null)"; fi
    if grep -q '|sshd_config|fatal' "$S1_CAP" 2>/dev/null; then pass; else
      fail "S1 MUTATION: no sshd_config fatal was emitted" "$(head -3 "$S1_CAP" 2>/dev/null)"; fi
    # The exact string from the rehearsal hosts. Pinning it — rather than "any failure" —
    # is what keeps this arm tied to the defect instead of to sshd being unhappy generally.
    if grep -q 'Missing privilege separation directory' "$S1_CAP" 2>/dev/null; then pass; else
      fail "S1 MUTATION: the captured stderr does not name the privsep directory — S1 is no longer reproducing the measured failure" \
           "$(head -5 "$S1_CAP" 2>/dev/null)"; fi
  fi
else
  fail "S1: could not extract the sshd stage and/or the hardening drop-in from the render"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"
fi

total=$((passes + fails))
# Floor = the ACTUAL assertion count (D1: 2, T5: 4 + 1 mutation, T17: 2 + 1 mutation,
# S1: 2 + 4 mutation). Its job is to catch a silently-empty harness — an early `exit 0` from
# a skip guard, or a docker run that never produced output — not to be an aspirational target.
if [ "$total" -lt 18 ]; then
  echo "FAIL: ran only ${total} assertions (<18) — harness did not execute fully" >&2
  exit 1
fi
echo "git-data-runcmd-rehearsal: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
