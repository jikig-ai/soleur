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
# The runcmd entry carrying the checksum block — the supply-chain fix (issue item 3).
blocks = [c for c in d["runcmd"] if isinstance(c, str) and "sha256sum -c -" in c]
assert len(blocks) == 1, f"expected exactly 1 checksum runcmd block, found {len(blocks)}"
open(f"{out}/doppler-dl.sh", "w").write(blocks[0])
# The trap-arming preamble (STAGE/on_err/trap + the delivery assertion).
pre = [c for c in d["runcmd"] if isinstance(c, str) and "trap on_err EXIT" in c]
assert len(pre) == 1, f"expected exactly 1 trap-arming block, found {len(pre)}"
open(f"{out}/preamble.sh", "w").write(pre[0])
# (#7025, S1) The sshd_config stage. Extracted from the render for the same reason every
# other block here is: a hand-written copy would keep passing after the shipped one drifted.
# DELIBERATELY LAST of the per-block extractions. Placed above, its assert would abort python
# before doppler-dl.sh was written, and the failure would surface as the `[ -s doppler-dl.sh ]`
# guard's "could not extract the checksum block" — naming an artifact that was fine. That is
# the same misattribution the cloud-init half of this PR is fixing.
sshd = [c for c in d["runcmd"] if isinstance(c, str) and "STAGE=sshd_config" in c]
assert len(sshd) == 1, f"expected exactly 1 sshd_config runcmd block, found {len(sshd)}"
open(f"{out}/sshd-stage.sh", "w").write(sshd[0])
# (#7204, D5) The LUKS stage, for R1/R3/R4. Extracted from the RENDER, not from raw
# template bytes: the #7204 comment block names the pre-fix invocation literally, so a
# raw-bytes grep for `mkfs.ext4` matches TWO lines and a `head -1` could execute a
# comment. ADR-152 strips whole-line comments at render, so the collision disappears here
# for free. `assert len(...) == 1` mirrors the other extractions — a stage that split into
# two runcmd entries must fail loudly rather than silently extract the first half.
luks = [c for c in d["runcmd"] if isinstance(c, str) and "STAGE=luks_open" in c]
assert len(luks) == 1, f"expected exactly 1 luks_open runcmd block, found {len(luks)}"
open(f"{out}/luks-stage.sh", "w").write(luks[0])
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

  # ERREXIT ORDERING IS S1's LOAD-BEARING PRECONDITION, so assert it rather than assume it.
  # S1 models the stage as a CHILD `sh`, which gets errexit OFF for free. That is faithful only
  # while the chain arms `set -e` AFTER this stage. If a later edit moved the arming earlier,
  # production would abort at `sshd -t` BEFORE `_sshd_t_rc=$?` — the stage would never emit its
  # own fatal — while S1 kept modelling the old world and stayed green through the divergence.
  _s1_stage_ln=$(grep -n '^[[:space:]]*STAGE=sshd_config[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1)
  _s1_sete_ln=$(grep -n '^[[:space:]]*set -e[[:space:]]*$' "$TMP/runcmd-all.sh" | head -1 | cut -d: -f1)
  if [ -n "$_s1_stage_ln" ] && [ -n "$_s1_sete_ln" ] && [ "$_s1_stage_ln" -lt "$_s1_sete_ln" ]; then pass; else
    fail "S1: the shipped chain arms 'set -e' at or before the sshd stage (stage=${_s1_stage_ln:-?}, set -e=${_s1_sete_ln:-?})" \
         "S1's child-sh model runs with errexit OFF and now tests the opposite of what ships."; fi

  _s1_run "$TMP/sshd-stage.sh"
  if [ "${S1_RC:-none}" = "0" ]; then pass; else
    fail "S1: the sshd_config stage exited ${S1_RC:-<no marker>} on a fresh 24.04 — this is the boot abort" \
         "$(tail -5 "$TMP/s1out/stdout" 2>/dev/null)"; fi
  # EMPTY, not "no fatal". A substring test for `|sshd_config|fatal` is satisfied by the 126/127
  # branch, which emits `sshd_config_warn`/`warning`, forces `_sshd_t_rc=0` and exits 0 — so a
  # container where /usr/sbin/sshd was missing entirely would pass both asserts while the fix
  # under test was never exercised. Measured: a healthy stage emits ZERO bytes (the systemctl
  # stub keeps the restart quiet), so `-s` is strictly stronger and cannot flake. It is also
  # what makes the systemctl stub load-bearing rather than decorative.
  if [ -s "$S1_CAP" ]; then
    fail "S1: a healthy sshd stage emitted $(wc -l < "$S1_CAP") event(s) — a warn here means sshd -t did not actually run (126/127 branch), so the privsep fix was never exercised" \
         "$(head -3 "$S1_CAP" 2>/dev/null)"
  else pass; fi

  # MUTATION — strip the WHOLE privsep preamble so the mutant is the pre-fix stage, and prove
  # S1 reproduces the MEASURED production failure rather than merely "some" failure. Leaving
  # the chmod behind would still fail, but on a `chmod: cannot access` the real boot never had.
  sed -e '/^[[:space:]]*mkdir -p \/run\/sshd[[:space:]]*$/d' \
      -e '/^[[:space:]]*chmod 0755 \/run\/sshd[[:space:]]*$/d' \
      "$TMP/sshd-stage.sh" > "$TMP/sshd-stage.nomkdir.sh"
  # Assert WHAT CHANGED, not merely that something did: an inequality would also be satisfied
  # by a sed that deleted some other line.
  _s1_before=$(grep -c 'mkdir -p /run/sshd' "$TMP/sshd-stage.sh" || true)
  _s1_after=$(grep -c 'mkdir -p /run/sshd' "$TMP/sshd-stage.nomkdir.sh" || true)
  if [ "$_s1_before" != "1" ] || [ "$_s1_after" != "0" ]; then
    fail "S1 MUTATION did not land: 'mkdir -p /run/sshd' count went ${_s1_before} -> ${_s1_after}, expected 1 -> 0" \
         "The fix this arm guards is absent or unrecognised — S1's green above certifies nothing."
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
  # SEVEN, matching S1's assertion count on every other path, so a failed extraction cannot
  # satisfy the anti-vacuity floor by emitting fewer.
  fail "S1: could not extract the sshd stage and/or the hardening drop-in from the render"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
  fail "S1: skipped (extraction failed)"; fail "S1: skipped (extraction failed)"
fi

# ══ #7204 — R1 / R3 / R4: the birth filesystem, and the diagnostic that named it ══
#
# WHY THESE ARMS DO NOT MOUNT ANYTHING. #7204 was a mount that failed with ESRCH because
# the birth `mkfs` set the ext4 `quota` feature and the target image has no `quota_v2`
# module to satisfy it. The obvious guard — "mkfs it and mount it in the test" — CANNOT
# go red for that reason, and this is measured, not assumed: a four-arm privileged probe
# (loop file -> luksFormat -> luksOpen -> mkfs -> mount) run 2026-08-03 on kernel
# 7.0.0-28-generic mounted ALL FOUR arms rc=0, including the unfixed `-O quota,project`.
# A container shares the host kernel, so on any runner whose kernel provides `quota_v2`
# the defective filesystem mounts perfectly. Worse, `request_module` reaches the loader via
# `call_usermodehelper`, which runs in the INIT NAMESPACE — so a container-side
# /etc/modprobe.d blacklist is never consulted and cannot simulate the target either.
# Simulating this needs a VM, not a container.
#
# So R1 asserts the PROPERTY THAT MADE THE BOOT FAIL — the created superblock's feature
# set — not the failure itself. That is kernel-independent by construction.
#
# ANYONE PROPOSING "just mount it and see" SHOULD BE SHOWN THE PARAGRAPH ABOVE.
#
# R2 (a real mount) is DELIBERATELY ABSENT. Disposition taken in this PR's Phase 0.7:
# this harness runs four plain `docker run --rm` and contains zero
# --privileged/--cap-add/--device, so `mount(2)` fails EPERM on the fixed AND the unfixed
# template — an arm that is green on neither, proving nothing about either. Promoting this
# rung to privileged would be an architectural change to the rung-1/rung-2 taxonomy that
# this file's own header declares, and rung 2 already mounts a real mapper on a real host.
# Do not add a mount arm here without revisiting that taxonomy first.

_r1_fix="$DIR/git-data-birth-fs-fingerprint.txt"
if [ -s "$TMP/luks-stage.sh" ] && [ -s "$_r1_fix" ]; then
  # Extract the mkfs invocation FROM THE RENDER (D5). Device path -> __DEV__ so the arms
  # can retarget it at a regular file. `assert len(...) == 1` mirrors every other
  # extraction here: a stage whose mkfs moved or duplicated must fail loudly.
  _r1_extract_rc=0
  python3 - "$TMP/luks-stage.sh" "$TMP" <<'PY' || _r1_extract_rc=$?
import re, sys
src = open(sys.argv[1]).read(); out = sys.argv[2]
lines = [l for l in src.splitlines() if re.match(r'^\s*mkfs\.ext4\b', l)]
assert len(lines) == 1, f"expected exactly 1 mkfs.ext4 invocation in the luks stage, found {len(lines)}"
cmd = lines[0].strip()
# Strip any trailing REDIRECT before touching the device operand. The shipped line ends in
# `2>>"$GIT_DATA_LUKS_DETAIL"` (the #7204 stderr capture), and that variable is unset in this
# harness — so treating it as the device produced a command that silently created no
# filesystem at all, and R1 reported "NOFEATURES" as though the template were broken.
# A guard, not a strip-and-hope: the device operand must still look like a path afterwards.
cmd = re.sub(r'\s+\d*>>?\s*\S+\s*$', '', cmd).strip()
assert re.search(r'/\S+$', cmd), f"mkfs line has no path-shaped device operand after stripping redirects: {cmd!r}"
# Replace the trailing device operand with a placeholder the container retargets.
cmd = re.sub(r'\S+$', '__DEV__', cmd)
open(f"{out}/r1-mkfs-shipped.txt", "w").write(cmd + "\n")
PY
  if [ "$_r1_extract_rc" -eq 0 ] && [ -s "$TMP/r1-mkfs-shipped.txt" ]; then pass; else
    fail "R1: could not extract exactly one mkfs.ext4 invocation from the rendered luks_open stage" \
         "A rename such as mkfs.ext4 -> mke2fs -t ext4 would red B16 while R1 silently failed to extract."; fi

  if [ "$_r1_extract_rc" -eq 0 ] && [ -s "$TMP/r1-mkfs-shipped.txt" ]; then
    _r1_shipped="$(cat "$TMP/r1-mkfs-shipped.txt")"
    # MUTANT: re-introduce the `quota` feature. Candidate-dependent by construction — if the
    # shipped line carries no -O at all, inject one. Asserted to have LANDED before it is
    # used, so a no-op sed reports "the mutation did not land" rather than the far more
    # misleading "the fingerprint held on the mutant" (the S1/T5 misattribution class).
    if printf '%s' "$_r1_shipped" | grep -qE -- '-O '; then
      _r1_mutant="$(printf '%s' "$_r1_shipped" | sed -E 's/-O ([^ ]+)/-O quota,\1/')"
    else
      _r1_mutant="$(printf '%s' "$_r1_shipped" | sed -E 's/^([[:space:]]*mkfs\.ext4)/\1 -O quota/')"
    fi
    _r1_mut_has_quota=$(printf '%s' "$_r1_mutant" | grep -cE -- '-O [^ ]*quota' || true)
    if [ "$_r1_mutant" != "$_r1_shipped" ] && [ "$_r1_mut_has_quota" -ge 1 ]; then pass; else
      fail "R1 MUTATION did not land: injecting 'quota' left the line unchanged or without a quota feature" \
           "shipped=[$_r1_shipped] mutant=[$_r1_mutant] — R1's green below would certify nothing."; fi

    # SECOND negative control (D7): the literal that shipped before #7204, executed directly.
    # Independent of the sed above, so a mutation that silently changes meaning still leaves
    # one control that reproduces the real defect.
    _r1_prefix='mkfs.ext4 -q -O quota,project __DEV__  # what shipped before #7204'

    printf '%s\n' "$_r1_shipped" > "$TMP/r1-arm-shipped.txt"
    printf '%s\n' "$_r1_mutant"  > "$TMP/r1-arm-mutant.txt"
    printf '%s\n' "$_r1_prefix"  > "$TMP/r1-arm-prefix.txt"

    cat > "$TMP/r1-drive.sh" <<'R1DRV'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq e2fsprogs >/dev/null 2>&1
for arm in shipped mutant prefix; do
  img="/tmp/$arm.img"
  # 10G sparse. Measured: a backing file under ~3MB falls into mke2fs's `floppy` bucket and
  # silently drops has_journal, which would make R1's non-vacuity probe fail for a reason
  # that has nothing to do with the template. 100M and 10G are identical; 10G also matches
  # var.git_data_luks_volume_size.
  truncate -s 10G "$img"
  # -F inserted immediately after the binary (never appended after the device operand,
  # where mke2fs would read it as a blocks-count).
  cmd="$(sed -e "s#__DEV__#$img#" -e 's#^\([[:space:]]*mkfs\.ext4\)#\1 -F#' "/work/r1-arm-$arm.txt")"
  sh -c "$cmd" >/dev/null 2>&1 || true
  feats="$(dumpe2fs -h "$img" 2>/dev/null | sed -n 's/^Filesystem features:[[:space:]]*//p')"
  printf 'ARM=%s FEATURES=%s\n' "$arm" "$feats" >> /out/r1-features.txt
done
R1DRV

    rm -rf "$TMP/r1out"; mkdir -p "$TMP/r1out"; : > "$TMP/r1out/r1-features.txt"
    docker run --rm \
      -v "$TMP/r1-arm-shipped.txt:/work/r1-arm-shipped.txt:ro" \
      -v "$TMP/r1-arm-mutant.txt:/work/r1-arm-mutant.txt:ro" \
      -v "$TMP/r1-arm-prefix.txt:/work/r1-arm-prefix.txt:ro" \
      -v "$TMP/r1-drive.sh:/work/r1-drive.sh:ro" \
      -v "$TMP/r1out:/out" \
      ubuntu:24.04 bash /work/r1-drive.sh >"$TMP/r1out/stdout" 2>&1 || true

    # Classify every arm against the committed allowlist. Three assertions with three
    # DISTINCT messages (D1): unclassified-feature, module-dep-present, non-vacuity.
    _r1_verdict="$(python3 - "$_r1_fix" "$TMP/r1out/r1-features.txt" <<'PY' 2>/dev/null || true
import sys
tbl = {}
for ln in open(sys.argv[1]):
    ln = ln.rstrip("\n")
    if not ln.strip() or ln.lstrip().startswith("#"):
        continue
    parts = ln.split("\t")
    if len(parts) >= 2:
        tbl[parts[0].strip()] = parts[1].strip()
arms = {}
for ln in open(sys.argv[2]):
    if ln.startswith("ARM="):
        head, _, feats = ln.strip().partition(" FEATURES=")
        arms[head[4:]] = feats.split()
def verdict(name):
    f = arms.get(name)
    if not f:
        return f"{name}:NOFEATURES"
    unclassified = [x for x in f if x not in tbl]
    moduledep = [x for x in f if tbl.get(x) == "module-dep"]
    return "%s:unclassified=%s:moduledep=%s:hasjournal=%s" % (
        name, ",".join(unclassified) or "-", ",".join(moduledep) or "-",
        "yes" if "has_journal" in f else "no")
print(" ".join(verdict(a) for a in ("shipped", "mutant", "prefix")))
PY
)"
    _r1_ship="$(printf '%s' "$_r1_verdict" | tr ' ' '\n' | grep '^shipped:' || true)"
    _r1_mut="$(printf '%s' "$_r1_verdict"  | tr ' ' '\n' | grep '^mutant:'  || true)"
    _r1_pre="$(printf '%s' "$_r1_verdict"  | tr ' ' '\n' | grep '^prefix:'  || true)"

    # (a) fail-closed against any FUTURE flag, not just the one that bit us.
    case "$_r1_ship" in
      *:unclassified=-:*) pass ;;
      "") fail "R1(a): no verdict for the shipped arm — the container produced no feature line" \
               "$(tail -5 "$TMP/r1out/stdout" 2>/dev/null)" ;;
      *) fail "R1(a): the birth filesystem carries feature(s) absent from the allowlist: ${_r1_ship#*unclassified=}" \
              "Classify each in $_r1_fix with its mount-time class before shipping. Do NOT 'refresh' the fixture wholesale — the point is the classification, not the diff. (mke2fs measured 1.47.0 in ubuntu:24.04 / 1.47.2 on the authoring host.)" ;;
    esac
    # (b) THE invariant, stated directly.
    case "$_r1_ship" in
      *:moduledep=-:*) pass ;;
      "") fail "R1(b): no verdict for the shipped arm" "$(tail -5 "$TMP/r1out/stdout" 2>/dev/null)" ;;
      *) fail "R1(b): the birth filesystem carries a module-dep feature: ${_r1_ship##*moduledep=}" \
              "This is the #7204 defect class: mounting it makes ext4 request a kernel module the target image does not ship, so the host boots dark with mount(8) rc=32. See $_r1_fix." ;;
    esac
    # (c) non-vacuity: also catches an accidentally-tiny backing file.
    case "$_r1_ship" in
      *:hasjournal=yes) pass ;;
      *) fail "R1(c): has_journal absent from the shipped arm — the probe is vacuous" \
              "Either mkfs did not run, or the backing file fell into mke2fs's floppy bucket (<~3MB). verdict=[$_r1_ship]" ;;
    esac
    # NEGATIVE CONTROL 1 — the in-test mutant MUST be rejected.
    case "$_r1_mut" in
      *:moduledep=-:*|"") fail "R1 MUTATION: injecting 'quota' did NOT trip the module-dep assertion" \
              "R1 cannot detect the very defect it exists for. verdict=[$_r1_mut]" ;;
      *) pass ;;
    esac
    # NEGATIVE CONTROL 2 — the committed pre-fix literal MUST be rejected.
    case "$_r1_pre" in
      *:moduledep=-:*|"") fail "R1 PRE-FIX CONTROL: the literal that shipped before #7204 did NOT trip the module-dep assertion" \
              "verdict=[$_r1_pre]. This control is independent of the sed mutation precisely so a mutation that silently changed meaning still leaves one arm reproducing the real defect." ;;
      *) pass ;;
    esac
  else
    # Identical cardinality to the success path (D9) minus the extraction assert already
    # emitted above, so a drifted extraction cannot satisfy the anti-vacuity floor by
    # emitting fewer assertions and burying the real cause.
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
    fail "R1: skipped (mkfs extraction failed)"; fail "R1: skipped (mkfs extraction failed)"
  fi
else
  fail "R1: could not extract the luks_open stage from the render, or the fingerprint fixture is missing ($_r1_fix)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
  fail "R1: skipped (precondition missing)"; fail "R1: skipped (precondition missing)"
fi

# R1-EXPIRY — its OWN labelled arm, deliberately OUT of R1's pass/fail path (D8). A CI
# failure triggered by a wall-clock date is unrepeatable and its message says nothing about
# the filesystem; worse, a stale date can mask or merge with real feature drift. The
# remediation is tied to the birth, not to an arbitrary +6 months: when the git-data host is
# actually born, re-measure the sibling baseline against the REAL image's e2fsprogs instead
# of the inferred one, then move the date.
_r1_exp="$(sed -n 's/^# expires_on:[[:space:]]*//p' "$_r1_fix" 2>/dev/null | head -1)"
if [ -n "$_r1_exp" ] && [ "$(date -u +%Y-%m-%d)" \< "$_r1_exp" ]; then pass; else
  fail "R1-EXPIRY: the birth-fs fingerprint's provenance is stale (expires_on=${_r1_exp:-<unparseable>})" \
       "Re-measure the sibling baseline (cloud-init-registry.yml / workspaces-cutover.sh mkfs) against the image's own e2fsprogs and move the date. This does not gate R1's feature assertions."; fi

# ── R3 — the detail SOURCE is a readable file, not a literal path ───────────────────
#
# NOT "the failure is diagnosable" — that name over-claimed. What this arm can observe in an
# unprivileged container is narrower and worth stating: `dmesg` is EPERM-blocked here and
# /var/log/cloud-init-output.log does not exist, so the "carries dmesg context" property is a
# DOCUMENTED LIMITATION of this rung, not an assertion. Rung 2 covers it.
#
# The defect being guarded: the emitter branches
#   [ -n "$DETAIL_SRC" ] && [ -r "$DETAIL_SRC" ]  ->  tail the file
#   else                                          ->  _san "$DETAIL_SRC"
# so a NON-EMPTY but UNREADABLE detail source ships THE LITERAL PATH STRING as the
# diagnostic. Measured on the shipped emitter 2026-08-03:
#   _san('/var/log/cloud-init-output.log') -> '/var/log/cloud-init-output.log'
# That is what #7204's fatal actually carried.
if [ -s "$TMP/luks-stage.sh" ]; then
  # (1) the stage passes a seeded detail file, not the cloud-init log, to the emitter.
  _r3_seed_ln=$(grep -n 'GIT_DATA_LUKS_DETAIL=' "$TMP/luks-stage.sh" | head -1 | cut -d: -f1)
  _r3_emit_ln=$(grep -n 'git-data-emit' "$TMP/luks-stage.sh" | head -1 | cut -d: -f1)
  if [ -n "$_r3_seed_ln" ]; then pass; else
    fail "R3(1): the luks_open stage does not seed a detail file (no GIT_DATA_LUKS_DETAIL= assignment)" \
         "Without it luks_err falls through to _san and emits the literal path string as the diagnostic."; fi
  # (2) ORDERING, not co-presence (L1). The seed must PRECEDE the first append and the trap.
  # A grep proving both lines exist is exactly the failure mode of
  # knowledge-base/project/learnings/2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md
  # — assertions sat ~120 lines above the heredocs creating the files they asserted on, and
  # the harness could not see it because it extracts bodies and runs them in isolation.
  _r3_first_append=$(grep -n '2>>"\?\$GIT_DATA_LUKS_DETAIL' "$TMP/luks-stage.sh" | head -1 | cut -d: -f1)
  if [ -n "$_r3_seed_ln" ] && [ -n "$_r3_first_append" ] && [ "$_r3_seed_ln" -lt "$_r3_first_append" ]; then pass; else
    fail "R3(2): the detail-file seed does not precede the first append (seed=${_r3_seed_ln:-none} first-append=${_r3_first_append:-none})" \
         "Co-presence is not ordering. A seed placed after an append leaves the trap's detail source unreadable on exactly the early failures it exists to explain."; fi
else
  fail "R3: skipped (luks stage not extracted)"; fail "R3: skipped (luks stage not extracted)"
fi

# ── R3(3) + R4 — drive the EXTRACTED emitter against the capture endpoint ────────────
#
# R4 is the arm that pins Phase 1's ordering decision. The emitter keeps
# `tail -n 20 "$DETAIL_SRC" | _devalue | _clean`, and `_clean` ENDS in `tail -c 180` — a
# DOUBLE truncation. Measured against the shipped _clean on 2026-08-03:
#   dmesg first, mount stderr last -> the 180-byte survivor ENDS with "No such process."
#   reversed (dmesg last)          -> the mount error is pushed out ENTIRELY
# Nothing pinned that before this arm. It is a one-character regression in the exact code
# path whose absence cost #7204 a hand-written Better Stack query to diagnose.
cat > "$TMP/r4-drive.sh" <<'R4DRV'
#!/bin/bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl python3 >/dev/null 2>&1
python3 /work/capture.py & sleep 1
cp /work/git-data-emit-src /work/git-data-emit
sed -i "s#^DSN='.*'#DSN='https://k@127.0.0.1:8099/1'#" /work/git-data-emit
python3 - <<'FIX'
p="/work/git-data-emit"; s=open(p).read()
s=s.replace('"https://${SHOST}/api/${PROJ}/store/"','"http://${SHOST}/api/${PROJ}/store/"')
open(p,"w").write(s)
FIX
chmod +x /work/git-data-emit

MOUNTERR='mount: /mnt/git-data-luks: mount(2) system call failed: No such process.'
mk_dmesg() { i=1; while [ "$i" -le 20 ]; do echo "[   12.3456$i] EXT4-fs (dm-0): mounting with quota feature but no quota format module line $i"; i=$((i+1)); done; }

# ORDER A — the shipped ordering: dmesg first, failing stderr last.
{ mk_dmesg; printf '%s\n' "$MOUNTERR"; } > /tmp/detail-a.txt
: > /out/capture.log
/work/git-data-emit "probe A" luks_open fatal /tmp/detail-a.txt "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-a.log

# ORDER B — the MUTATION: reversed, so dmesg is what survives the tail.
{ printf '%s\n' "$MOUNTERR"; mk_dmesg; } > /tmp/detail-b.txt
: > /out/capture.log
/work/git-data-emit "probe B" luks_open fatal /tmp/detail-b.txt "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-b.log

# ORDER C — R3(3): non-empty but UNREADABLE detail source. An ABSENT $4 would fall to
# _san "" and pass vacuously; only a non-empty-unreadable path exercises the literal leak.
: > /out/capture.log
/work/git-data-emit "probe C" luks_open fatal /nonexistent/xyzzy "rc=32" >/dev/null 2>&1 || true
cp /out/capture.log /out/capture-c.log
R4DRV

rm -rf "$TMP/r4out"; mkdir -p "$TMP/r4out"; : > "$TMP/r4out/capture.log"
docker run --rm \
  -v "$TMP/git-data-emit:/work/git-data-emit-src:ro" \
  -v "$TMP/capture.py:/work/capture.py:ro" \
  -v "$TMP/r4-drive.sh:/work/r4-drive.sh:ro" \
  -v "$TMP/r4out:/out" \
  ubuntu:24.04 bash /work/r4-drive.sh >"$TMP/r4out/stdout" 2>&1 || true

_r4_a=$(grep -c 'No such process' "$TMP/r4out/capture-a.log" 2>/dev/null || true)
_r4_b=$(grep -c 'No such process' "$TMP/r4out/capture-b.log" 2>/dev/null || true)
_r3_c=$(grep -c 'xyzzy' "$TMP/r4out/capture-c.log" 2>/dev/null || true)

if [ "${_r4_a:-0}" -ge 1 ]; then pass; else
  fail "R4: the mount error did NOT survive the emitter's tail -n 20 | tail -c 180 under the shipped ordering" \
       "Write dmesg FIRST and the failing command's stderr LAST. capture-a=[$(head -c 300 "$TMP/r4out/capture-a.log" 2>/dev/null)]"; fi
if [ "${_r4_b:-0}" -eq 0 ]; then pass; else
  fail "R4 MUTATION: reversing the ordering STILL delivered the mount error — R4 cannot detect an ordering regression" \
       "If the emitter's truncation changed, re-measure the budget before trusting R4's green above."; fi
# R3(3a) — POSITIVE CONTROL for the hazard, not a defect report. The emitter's
# `[ -n ] && [ -r ]` branch falls through to `_san "$DETAIL_SRC"`, so handing it a
# non-empty-but-unreadable path ships THE LITERAL PATH as the "cause". We deliberately do
# NOT change the emitter here — its redaction/truncation ordering is load-bearing and out of
# this PR's scope. Instead we PROVE the hazard is live, which is what makes the stage-side
# guard in R3(3b) load-bearing rather than decorative. If this control ever stops leaking,
# the emitter changed and R3(3b)'s rationale must be re-derived.
if [ "${_r3_c:-0}" -ge 1 ]; then pass; else
  fail "R3(3a) POSITIVE CONTROL: the emitter no longer leaks a literal path for an unreadable detail source" \
       "R3(3b) below guards a hazard that may no longer exist — re-derive it against the emitter's current branch. capture-c=[$(head -c 300 "$TMP/r4out/capture-c.log" 2>/dev/null)]"; fi

# R3(3b) — THE GUARD. The stage must never hand the emitter a path it has not proven
# readable. Pre-#7204 luks_err passed the BARE LITERAL /var/log/cloud-init-output.log, which
# does not exist in this container and is exactly how a fatal came to carry a filename
# instead of a cause. Assert the 4th argument is a VARIABLE and that a `[ -r ]` guard on it
# precedes the emit call.
if [ -s "$TMP/luks-stage.sh" ]; then
  _r3b="$(python3 - "$TMP/luks-stage.sh" <<'PY' 2>/dev/null || true
import re, sys, shlex
src = open(sys.argv[1]).read()
joined = re.sub(r'\\\n\s*', ' ', src)          # fold line continuations
m = [l for l in joined.splitlines() if 'git-data-emit' in l and 'fatal' in l]
if not m:
    print("NOEMIT"); raise SystemExit
line = m[0].strip()
try:
    toks = shlex.split(line, posix=False)
except ValueError:
    print("UNPARSEABLE"); raise SystemExit
# toks[0] is the emitter; args are 1..N. The detail source is arg 4.
arg4 = toks[4] if len(toks) > 4 else ""
isvar = "VAR" if arg4.lstrip('"').startswith("$") else "LITERAL"
name = arg4.strip('"')
guarded = "GUARDED" if re.search(r'\[\s+-r\s+"?' + re.escape(name), joined) else "UNGUARDED"
print(f"{isvar}:{guarded}:{arg4}")
PY
)"
  case "$_r3b" in
    VAR:GUARDED:*) pass ;;
    LITERAL:*) fail "R3(3b): luks_err passes a BARE PATH LITERAL as the emitter's detail source: ${_r3b#LITERAL:*:}" \
                    "That is the #7204 shape — when the literal is unreadable the fatal carries a filename instead of a cause. Pass a variable the stage has seeded and proven readable." ;;
    VAR:UNGUARDED:*) fail "R3(3b): luks_err's detail variable ${_r3b#VAR:UNGUARDED:} has no '[ -r ]' readability guard before the emit call" \
                    "An unwritable .final (disk full, read-only /run) would hand the emitter an unreadable path and re-open the literal-leak branch." ;;
    *) fail "R3(3b): could not locate a parseable git-data-emit fatal call in the luks_open stage (verdict=[${_r3b:-none}])" ;;
  esac
else
  fail "R3(3b): skipped (luks stage not extracted)"
fi

total=$((passes + fails))
# Floor = the ACTUAL assertion count (B1: 1, B2: 1, D1: 2, T5: 4 + 1 mutation, T17: 2 + 1
# mutation, S1: 3 + 4 mutation). Its job is to catch a silently-empty harness — an early
# `exit 0` from a skip guard, or a docker run that never produced output — not to be an
# aspirational target. S1 emits exactly 7 on ALL THREE of its paths (healthy, mutation-did-
# not-land, extraction-failed) so no short-circuit can satisfy the floor.
#
# RAISED 19 -> 33 WITH THE ARMS THAT MADE IT NECESSARY (#7204), itemised so the next author
# can check the sum rather than trust it:
#   R1        7  extraction, mutation-landed, (a) unclassified, (b) module-dep,
#                (c) non-vacuity, in-test mutation control, committed pre-fix control
#   R1-EXPIRY 1  fixture provenance, deliberately OUTSIDE R1's pass/fail path
#   R3        2  detail-file seed present, seed PRECEDES first append (ordering, not co-presence)
#   R3(3a)    1  positive control: the emitter's literal-path leak is still live
#   R3(3b)    1  the stage passes a readability-guarded VARIABLE, never a bare path literal
#   R4        2  mount error survives the double-truncation, + ordering-reversal mutation
#              = 14 new, 19 pre-existing, 33 total.
# R1 emits exactly 7 on all three of ITS paths (healthy, extraction-failed,
# precondition-missing) for the same reason S1 does. The floor must move with the suite or it
# only ever guards the work that predates it.
if [ "$total" -lt 33 ]; then
  echo "FAIL: ran only ${total} assertions (<33) — harness did not execute fully" >&2
  exit 1
fi
echo "git-data-runcmd-rehearsal: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
