#!/usr/bin/env bash
# Mutation battery for web-host-provisioner-parity.test.sh (#7000).
#
# WHY THIS EXISTS. The guard is GREEN against the tree it ships with, as every drift guard is
# on the day it lands. Green says nothing about whether it CAN go red. This battery breaks
# each invariant on a SANDBOX COPY and requires the guard to fail -- and to fail for the RIGHT
# REASON.
#
# THE ATTRIBUTION RULE IS THE POINT. The first version of this battery credited any non-zero
# exit. Review proved that scored nine unrelated checks as covered (one mutation tripped a
# floor plus ten §2 failures, so neutering the check it was named for changed nothing), and
# scored a `UnicodeDecodeError` crash as a detection. Every case here therefore names the
# ANCHOR it expects in the guard's own failure text, and the RED is credited only if that
# anchor appears. A mutation whose label and anchor disagree is a mutation that proves nothing.
#
# Anti-vacuity properties this battery holds itself to:
#   1. It drives the REAL guard against a sandbox (via SOLEUR_INFRA_DIR), never a
#      re-declaration of its logic. A battery that tests a copy of the good idiom proves the
#      copy is good.
#   2. Every mutation is proven to have LANDED (mutated text must differ from PRISTINE) before
#      the RED is credited, so a no-op `str.replace` cannot masquerade as a result.
#   3. Every RED is attributed to a named check, and the anchor must appear ON A [FAIL] LINE.
#      Matching anywhere in combined output is weaker than it looks: a guard whose §2 emitted
#      its findings as plain prints while an unrelated floor supplied the exit code would still
#      satisfy a substring test. Both greps read a FILE (never a pipe into `grep -q` on the
#      producer), so the SIGPIPE-fails-open trap in the header does not apply.
#   4. TWO POSITIVE CONTROLS, in both directions: a benign edit stays GREEN, and a
#      legitimately dual-delivered NEW artifact stays GREEN. Without the second, a guard that
#      over-fires on any addition would score a clean run.
#   5. The sandboxed INPUT SET is DERIVED from the guard, not copied (#7014). A hand-kept copy
#      lets a newly-added, tolerantly-read input sit outside the sandbox, so every check over
#      it runs against an empty string and this battery scores a clean pass over a check that
#      never executed.
#   6. Anything the guard asserts that NO edit to those input files can reach is unproven no
#      matter how green the run looks. §5's ALLOWLIST hygiene was exactly that -- structurally
#      unreachable -- and is now driven through a guard-side probe (P1-P3) that can only ADD
#      failures, never suppress one.
#
# Assertion predicates read a FILE or use bash `[[ ]]`; none pipe into `grep -q`, whose
# SIGPIPE-on-early-match fails OPEN under `set -o pipefail`.

# shellcheck disable=SC2016
# ^ Every mutator below is a PYTHON program passed as a single-quoted bash string. Shell
#   expansion inside them would be a bug, not a feature: `$` and backticks belong to the
#   python source. File-scoped because all mutators share the shape.

set -uo pipefail

# Default TMPDIR to /var/tmp (disk-backed), mirroring scripts/test-all.sh and
# run-registered-suites.sh. Those two cover the CI path; a DIRECT invocation of this file --
# the documented inner loop while editing the guard -- inherited the bare /tmp default and so
# put its sandbox on the machine-global 4 GiB tmpfs that parallel worktrees share. At 94% full
# the sandbox copies start failing, and this battery's verdicts become a function of another
# session's disk usage. Respects an explicit caller value.
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(git rev-parse --show-toplevel)" || exit 2
REAL_INFRA="$ROOT/apps/web-platform/infra"
GUARD="$REAL_INFRA/web-host-provisioner-parity.test.sh"
[[ -f "$GUARD" ]] || { echo "FATAL: $GUARD not found" >&2; exit 2; }

# ── INPUTS: DERIVED from the guard, never copied (#7014 gap 4) ───────────────────────
# A hand-kept duplicate of the guard's input list is a silent-vacuity vector: if the guard
# gains a fifth input and reads it TOLERANTLY (`try/except FileNotFoundError: return ""` --
# the realistic shape for an optional input such as the Dockerfile COPY set), the sandbox
# never carries that file, every check over it sees an empty string, and this battery reports
# a full pass over a check that never executed. So the list is parsed out of the guard's own
# preflight loop and reconciled against what is written here; a divergence is FATAL, not a
# warning, because a battery running on the wrong file set proves nothing.
#
# EXPECTED_INPUTS is not redundant with the derivation, but the split of labour is narrower than
# it first looks and the first version of this comment overstated it. The derivation does NOT
# keep the battery correct under drift -- on any divergence the battery ABORTS. What the pair
# buys is that adding an input is a deliberate two-file edit whose omission is loud, rather than
# a silent widening of what the sandbox covers.
EXPECTED_INPUTS=(server.tf cloud-init.yml web-probe-envwrite.sh soleur-host-bootstrap.sh)

mapfile -t DERIVED_INPUTS < <(
  sed -n 's/^for f in \(.*\); do$/\1/p' "$GUARD" | head -1 | tr ' ' '\n' | sed '/^$/d'
)
if [[ "${DERIVED_INPUTS[*]-}" != "${EXPECTED_INPUTS[*]}" ]]; then
  echo "FATAL: the guard's preflight input list has drifted." >&2
  echo "  derived from $GUARD: ${DERIVED_INPUTS[*]-<none>}" >&2
  echo "  expected by this battery: ${EXPECTED_INPUTS[*]}" >&2
  echo "  Update EXPECTED_INPUTS and confirm every new input is genuinely mutated below." >&2
  exit 2
fi
INPUTS=("${DERIVED_INPUTS[@]}")

# The preflight loop only proves which files the guard REQUIRES. What it READS is the second
# half, and a read that bypasses the loop reopens the same hole from the other side.
#
# The first version of this block asserted (a) exactly one `os.path.join(INFRA` and (b) every
# `read("<literal>")` site names a sandboxed input -- and TWO review agents independently drove
# a fifth, unsandboxed input straight past both, to a green 43/43, using the exact shape #7014
# gap 4 describes. Neither assertion constrains a read whose filename is NOT a literal at the
# call site (`read(_FIFTH)`), nor a helper that wraps `read` under a different name, nor a bare
# `open(f"{INFRA}/x")` which contains neither matched token.
#
# So the invariant is now stated positively and closed on all three: the guard opens files ONLY
# through `def read(n)`, and EVERY call site passes a string literal.
n_join=$(grep -cF 'os.path.join(INFRA' "$GUARD")
if [[ "$n_join" != "1" ]]; then
  echo "FATAL: expected exactly one 'os.path.join(INFRA' in the guard (the read() helper), found $n_join." >&2
  echo "  A second reader can take an input this battery never sandboxes. Route it through read()." >&2
  exit 2
fi

# No `open(` outside the read() helper. The helper's own line is the single permitted match.
n_open=$(grep -c 'open(' "$GUARD")
if [[ "$n_open" != "1" ]]; then
  echo "FATAL: expected exactly one 'open(' in the guard (inside def read), found $n_open." >&2
  echo "  A direct open() bypasses read() and can take an input this battery never sandboxes." >&2
  exit 2
fi

# Every `read(` call site passes a STRING LITERAL. `grep -c 'read('` counts the `def read(n)`
# line too, so the literal-site count must be exactly one fewer. A `read(SOME_VAR)` breaks this
# (6 vs 4) while leaving the two assertions above satisfied -- that is the bypass review drove.
n_read_call=$(grep -c 'read(' "$GUARD")
n_read_lit=$(grep -c 'read("' "$GUARD")
if [[ "$((n_read_call - 1))" != "$n_read_lit" ]]; then
  echo "FATAL: the guard has $((n_read_call - 1)) read() call sites but only $n_read_lit pass a" >&2
  echo "  string literal. A non-literal filename is invisible to the sandbox-membership check" >&2
  echo "  below, so this battery would run clean over a check that never executed." >&2
  exit 2
fi
# The two PRODUCTION ALLOWLIST wirings, asserted by presence rather than by behaviour -- and
# that weakness is the point of this comment, not something it hides.
#
# `ALLOWLIST` is deliberately empty, so `check_allowlist(ALLOWLIST, …)` iterates zero entries
# and `if dest in ALLOWLIST: continue` never fires. Neither produces any output a mutation could
# observe: review confirmed both lines can be deleted with the battery at 43/43. P1-P7 exercise
# `check_allowlist` through the PROBE call site, which proves the FUNCTION works and says
# nothing about whether it is still wired to the real list.
#
# The obvious way to make them observable -- letting the probe feed `ALLOWLIST` -- is exactly
# the fail-open P4 exists to forbid, so it is not available. A presence assertion pins spelling,
# not behaviour, which is a real limitation; it is chosen because it is the strongest instrument
# that does not reintroduce a suppression path.
while IFS= read -r wiring; do
  grep -qF -- "$wiring" "$GUARD" || {
    echo "FATAL: the guard no longer contains the production ALLOWLIST wiring:" >&2
    echo "  $wiring" >&2
    echo "  §5's hygiene checks and §2's allowlist consult are unobservable while ALLOWLIST is" >&2
    echo "  empty, so this presence check is the only thing standing between them and deletion." >&2
    exit 2
  }
done <<'WIRINGS'
check_allowlist(ALLOWLIST, "ALLOWLIST")
if dest in ALLOWLIST: continue
WIRINGS

n_reads=0
while IFS= read -r rf; do
  n_reads=$((n_reads + 1))
  case " ${INPUTS[*]} " in
    *" $rf "*) ;;
    *) echo "FATAL: the guard reads '$rf', which is not in the sandboxed input set." >&2; exit 2 ;;
  esac
done < <(grep -oE 'read\("[^"]+"\)' "$GUARD" | sed -e 's/^read("//' -e 's/")$//' | sort -u)
if [[ "$n_reads" -lt "${#INPUTS[@]}" ]]; then
  echo "FATAL: found only $n_reads read() call sites for ${#INPUTS[@]} declared inputs -- the" >&2
  echo "  read()-site extraction drifted, so this assertion is passing vacuously." >&2
  exit 2
fi

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

SANDBOX="$(mktemp -d -t provparity.XXXXXXXX)" || exit 2
PRISTINE="$(mktemp -d -t provparity-pristine.XXXXXXXX)" || exit 2
OUT="$(mktemp -t provparity-out.XXXXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX" "$PRISTINE" "$OUT"' EXIT INT TERM HUP

for f in "${INPUTS[@]}"; do
  cp "$REAL_INFRA/$f" "$SANDBOX/$f" || exit 2
  cp "$REAL_INFRA/$f" "$PRISTINE/$f" || exit 2
done

# Runs the real guard against the sandbox; combined output lands in $OUT for attribution.
run_guard() { SOLEUR_INFRA_DIR="$SANDBOX" bash "$GUARD" >"$OUT" 2>&1; }
# restore() FAILS LOUDLY. An unchecked `cp` here is a silent-corruption vector, not a tidiness
# nit: when it fails, the sandbox keeps the PREVIOUS case's mutation and every later case runs
# against a fixture nobody chose. The observable symptom is a case reporting "guard still PASSED
# with the invariant broken" or "mutator errored" -- i.e. a real-looking verdict about the guard,
# produced by a broken harness. Measured while /tmp sat at 94% under sibling test-all.sh runs:
# three different failure sets across three consecutive runs of an unchanged tree.
restore() {
  local f
  for f in "${INPUTS[@]}"; do
    cp "$PRISTINE/$f" "$SANDBOX/$f" || {
      echo "FATAL: could not restore $f into the sandbox (disk pressure? $TMPDIR)." >&2
      echo "  Every result after this point would be measured against the previous case's" >&2
      echo "  mutation, so the run is void rather than red." >&2
      exit 2
    }
  done
}

apply_mutation() {
  local file="$1" script="$2"
  python3 - "$SANDBOX/$file" <<PYEOF
import sys
p = sys.argv[1]
s = open(p).read()
$script
open(p, 'w').write(s)
PYEOF
}

mutations_run=0

# expect_red <label> <file> <expected-anchor> <mutator>
expect_red() {
  local label="$1" file="$2" anchor="$3" script="$4"
  restore
  if ! apply_mutation "$file" "$script"; then
    no "$label: mutator errored (anchor drifted?) -- the mutation never landed"; restore; return
  fi
  if cmp -s "$SANDBOX/$file" "$PRISTINE/$file"; then
    no "$label: mutation did NOT land ($file byte-identical to pristine)"; restore; return
  fi
  mutations_run=$((mutations_run + 1))
  if run_guard; then
    no "$label: guard still PASSED with the invariant broken -- it cannot detect this"
  elif grep -F "[FAIL]" "$OUT" | grep -qF -- "$anchor"; then
    ok "$label: guard went RED on '$anchor'"
  else
    no "$label: guard went red but NOT via '$anchor'. Either it failed for an unrelated reason
      (so this mutation proves nothing about the check it is named for), or a count baked into
      the anchor drifted because the infra files legitimately changed -- several anchors below
      encode a baseline-derived number. Compare against the output. Output: $(<"$OUT")"
  fi
  restore
}

# expect_green <label> <file> <mutator> -- direction control
expect_green() {
  local label="$1" file="$2" script="$3"
  restore
  if ! apply_mutation "$file" "$script"; then no "$label: mutator errored"; restore; return; fi
  if cmp -s "$SANDBOX/$file" "$PRISTINE/$file"; then
    no "$label: control edit did not land -- it proves nothing"; restore; return
  fi
  if run_guard; then ok "$label: guard stayed GREEN (no over-fire)"
  else no "$label: guard went RED on a legitimate edit -- it over-fires. Output: $(<"$OUT")"; fi
  restore
}

# ── Baseline ─────────────────────────────────────────────────────────────────────────
restore
if run_guard; then
  ok "baseline: guard is GREEN against the unmutated tree"
else
  no "baseline: guard is RED against the UNMUTATED tree; every RED below is meaningless"
  echo "=== provisioner-parity mutation: $pass passed, $fail failed ===" >&2
  exit 1
fi

# ── §1: resource enumeration and host-pinning ────────────────────────────────────────
expect_red "M1 (§1 floor: a provisioner deleted)" server.tf \
  "1: swept only 14 SSH-connected" '
import re
m = re.search(r"resource \"terraform_data\" \"orphan_reaper_install\" \{", s)
assert m, "anchor missing"
end = s.index("\nresource ", m.end())
s = s[:m.start()] + s[end+1:]
'

expect_red "M2 (§1: fanned out over var.web_hosts -- the #7000 change)" server.tf \
  "for_each'd=['disk_monitor_install']" '
old = "resource \"terraform_data\" \"disk_monitor_install\" {"
assert old in s
s = s.replace(old, old + "\n  for_each = var.web_hosts", 1)
'

# §1 has TWO clauses -- `fanned` (M2) and `unpinned`. Nothing covered `unpinned`, so it was
# deletable. This is the shape it exists for: the host is repointed away from web-1 WITHOUT a
# for_each, so the fan-out check does not fire and only the pin check can catch it.
expect_red "M3 (§1: host repointed off web-1 without for_each)" server.tf \
  "not-web-1-pinned=" '
old = "    host        = hcloud_server.web[\"web-1\"].ipv4_address\n    user        = \"root\"\n    private_key = var.ci_ssh_private_key         # null in operator-local context"
assert old in s
s = s.replace(old, "    host        = local.web1_ip\n    user        = \"root\"\n    private_key = var.ci_ssh_private_key         # null in operator-local context", 1)
'

# Terraform identifiers legally contain uppercase and hyphens. v1 matched `[a-z_0-9]+`, so such
# a resource was skipped by every section at once -- and because all floors are `>=`, invisibly.
# This is a GREEN control: after the rename the resource must still be swept (count unchanged).
expect_green "control-C (uppercase/hyphen resource name is still swept)" server.tf '
old = "resource \"terraform_data\" \"cosign_trusted_root\" {"
assert old in s
s = s.replace(old, "resource \"terraform_data\" \"Cosign-Trusted_Root\" {", 1)
'

# ── §2: the destination sweep (the load-bearing invariant) ───────────────────────────
expect_red "M5 (§2: provisioner-file destination with no fresh-boot writer)" server.tf \
  "/etc/soleur/phantom-file.conf is written by" '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/etc/soleur/phantom-file.conf"
  }""", 1)
'

# The FIFTH CHANNEL. `echo >` existed in server.tf already and the channel-keyed guard was
# blind to it; destination-keying makes the verb irrelevant.
expect_red "M6 (§2: echo-redirect -- the fifth channel)" server.tf \
  "/etc/default/phantom-echo-env is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"echo AUTH_TOKEN=xyz > /etc/default/phantom-echo-env\",\n" + old, 1)
'

expect_red "M7 (§2: install-redirect -- also previously invisible)" server.tf \
  "/etc/soleur/phantom-installed.conf is written by" '
old = "      \"chmod 600 /etc/default/resource-monitor\","
assert old in s
s = s.replace(old, "      \"install -m 0644 /tmp/x /etc/soleur/phantom-installed.conf\",\n" + old, 1)
'

expect_red "M8 (§2: tee -- another verb the channel model never enumerated)" server.tf \
  "/etc/soleur/phantom-teed.conf is written by" '
old = "      \"chmod 600 /etc/default/container-restart-monitor\","
assert old in s
s = s.replace(old, "      \"cat /tmp/x | tee /etc/soleur/phantom-teed.conf\",\n" + old, 1)
'

# Prose must NOT satisfy delivery. These are the holes review demonstrated on the old guard:
# a comment in cloud-init / the bootstrap justified an artifact and the guard went green.
# Targets /etc/docker/daemon.json specifically because cloud-init is its ONLY fresh-boot
# writer (cloud-init.yml says so in-line: "the ONLY daemon.json write for FRESH hosts").
# A destination with a second real writer would stay green for a legitimate reason and the
# case would prove nothing about comment-handling.
expect_red "M9 (§2: cloud-init COMMENT does not count as delivery)" cloud-init.yml \
  "/etc/docker/daemon.json is written by" '
out = []
for L in s.split("\n"):
    if "/etc/docker/daemon.json" in L and not L.lstrip().startswith("#"):
        out.append(L.replace("/etc/docker/daemon.json", "/etc/docker/RENAMED.json"))
    else:
        out.append(L)
out.insert(5, "  # historical: this host once wrote /etc/docker/daemon.json at boot")
s = "\n".join(out)
'

# M10 and M11 test genuinely different properties -- a stripped COMMENT, and a systemd
# ExecStart CONSUMER reference -- but both used to anchor on /etc/webhook/hooks.json, so each
# credited the other: neutering the check either was named for left the other's RED in place
# and the battery still scored both (#7014 gap 5). They now use DIFFERENT destinations, which
# is what makes the two anchors discriminating. M10 takes an install-loop artifact whose only
# remaining mention is prose; M11 keeps hooks.json, whose ExecStart consumer lives in
# cloud-init.yml and is deliberately left intact.
# M10 REQUIRES a brand-new artifact on the SSH path and then "delivers" it ONLY through a
# TRAILING comment in the bootstrap. That makes the comment LOAD-BEARING, which the previous
# version was not: it renamed the real install and merely inserted a comment alongside, so the
# RED came from the rename and the comment was inert -- review proved the anchor still fired
# with the comment deleted AND with strip_comments reduced to `return text`, i.e. the case was
# a duplicate of M25 wearing a comment-handling label while `strip_comments` had NO coverage at
# all. Reverting comment stripping to its v1 behaviour is a LIVE fail-open (measured: this
# fixture goes GREEN against a v1 guard, RED against the shipped one), and nothing pinned it.
expect_red "M10 (§2: a trailing COMMENT is not delivery -- pins strip_comments)" soleur-host-bootstrap.sh \
  "/etc/soleur/comment-covered.conf is written by" '
import os
sp = os.path.join(os.path.dirname(p), "server.tf")
t = open(sp).read()
blk = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert blk in t
add = """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/etc/soleur/comment-covered.conf"
  }"""
open(sp, "w").write(t.replace(blk, blk + add, 1))
o = "install -D -m 0644 -o root -g root " + chr(34) + "$SEED/journald-soleur.conf" + chr(34) + " /etc/systemd/journald.conf.d/00-soleur.conf"
assert o in s
c = "   # install -D -m 0644 " + chr(34) + "$SEED/disk-monitor.sh" + chr(34) + " " + chr(34) + "/etc/soleur/comment-covered.conf" + chr(34)
s = s.replace(o, o + c, 1)
'

# A CONSUMER reference (systemd ExecStart) is not a producer. The old guard credited exactly
# this as proof that cloud-init rendered hooks.json. Every bootstrap mention is renamed --
# comments included -- so the ONLY surviving fresh-boot reference is cloud-init.yml s
# `ExecStart=/usr/local/bin/webhook ... -hooks /etc/webhook/hooks.json`. The precondition is
# asserted rather than assumed: if that consumer line ever moves, this case must fail as a
# FIXTURE error, not pass as a phantom detection.
expect_red "M11 (§2: a systemd ExecStart consumer reference is not delivery)" soleur-host-bootstrap.sh \
  "/etc/webhook/hooks.json is written by" '
import os
cip = os.path.join(os.path.dirname(p), "cloud-init.yml")
ci = open(cip).read()
assert "ExecStart=/usr/local/bin/webhook" in ci
assert "/etc/webhook/hooks.json" in ci
assert "/etc/webhook/hooks.json" in s
s = s.replace("/etc/webhook/hooks.json", "/etc/webhook/RENAMED.json")
'

# ── §3: installed-but-not-baked (the other direction from §2) ────────────────────────
expect_red "M12 (§3: bootstrap installs a seed file that is not baked)" server.tf \
  "3: soleur-host-bootstrap.sh installs from" '
old = "    \"orphan-reaper.sh\",\n"
assert old in s
s = s.replace(old, "", 1)
'

# ── §4: byte-identity of dual-written unit bodies ────────────────────────────────────
expect_red "M13 (§4: heredoc body drifts, server.tf side)" server.tf \
  "4: /etc/systemd/system/disk-monitor.service DRIFTED" '
old = "Description=Disk space monitor"
assert old in s
s = s.replace(old, "Description=Disk space monitor DRIFTED", 1)
'

expect_red "M14 (§4: same body drifts from the cloud-init side)" cloud-init.yml \
  "4: /etc/systemd/system/disk-monitor.timer DRIFTED" '
old = "Description=Run disk monitor every 5 minutes"
assert old in s
s = s.replace(old, "Description=Run disk monitor every 4 minutes", 1)
'

# A write_files entry whose body does not parse must be a §4 FAILURE, not a silent skip --
# otherwise `content: |-` / `encoding: b64` makes a dual-written unit uncomparable and green.
expect_red "M15 (§4: unparseable write_files body is not a free pass)" cloud-init.yml \
  "with no parseable" '
old = "  - path: /etc/systemd/system/disk-monitor.service\n"
assert old in s
i = s.index(old)
j = s.index("  - path:", i + len(old))
s = s[:i] + old + "    owner: root:root\n    permissions: \"0644\"\n" + s[j:]
'

# ── §0: the parse floors themselves ──────────────────────────────────────────────────
expect_red "M16 (§0: bake list truncated below its floor)" server.tf \
  "0: local.host_script_files parsed to only" '
import re
m = re.search(r"host_script_files = \[(.*?)\n  \]", s, re.S)
assert m
s = s[:m.start(1)] + "\n    \"disk-monitor.sh\",\n" + s[m.end(1):]
'

expect_red "M17 (§0: bootstrap install-loop parse broken)" soleur-host-bootstrap.sh \
  "0: soleur-host-bootstrap.sh parsed to only" '
s = s.replace("install -D -m 0755 -o root -g root \"$SEED/$f\"", "cp \"$SEED/$f\"")
s = s.replace("install -D -m 0644 -o root -g root \"$SEED/$f\"", "cp \"$SEED/$f\"")
'


# ── Review round 2: the 12 hostile mutations that defeated the v2 destination-keyed guard ──
# Every one was GREEN against v2 and is pinned here so the fix cannot silently regress.
# M18-M24 are EXTRACTION misses: v2 enumerated write VERBS, so an unlisted verb meant the
# destination never entered the set at all -- a SILENT fail-open (a channel-keyed miss at
# least failed loudly). M25-M28 are over-CREDITS on the coverage side.

expect_red "M18 (§2 extraction: QUOTED redirect target)" server.tf \
  "/etc/soleur/quoted-artifact.conf is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"printf %s hello > \\\"/etc/soleur/quoted-artifact.conf\\\"\"," + chr(10) + old, 1)
'

expect_red "M19 (§2 extraction: install to a new destination)" server.tf \
  "/etc/soleur/install-artifact.conf is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"install -m 0644 /tmp/staged.conf /etc/soleur/install-artifact.conf\"," + chr(10) + old, 1)
'

expect_red "M20 (§2 extraction: mv -- the atomic-rename idiom)" server.tf \
  "/etc/soleur/moved-artifact.conf is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"mv /tmp/staged.conf /etc/soleur/moved-artifact.conf\"," + chr(10) + old, 1)
'

expect_red "M21 (§2 extraction: dd of=)" server.tf \
  "/etc/soleur/dd-artifact.conf is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"dd if=/tmp/staged.conf of=/etc/soleur/dd-artifact.conf\"," + chr(10) + old, 1)
'

expect_red "M22 (§2 extraction: curl -o)" server.tf \
  "/etc/soleur/curl-artifact.conf is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"curl -fsSL https://example.com/x -o /etc/soleur/curl-artifact.conf\"," + chr(10) + old, 1)
'

expect_red "M23 (§2 extraction: python3 - /path (the bootstrap's own hooks.json idiom))" server.tf \
  "/etc/soleur/py-artifact.json is written by" '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s
s = s.replace(old, "      \"python3 - /etc/soleur/py-artifact.json < /dev/null\"," + chr(10) + old, 1)
'

expect_red "M24 (§2: an INTERPOLATED destination is unprovable, not skippable)" server.tf \
  "an INTERPOLATED destination this guard cannot" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "${local.soleur_etc}/interp.conf"
  }""", 1)
'

# Break the ONLY real writer of /opt/soleur/vector.toml. v2 stayed GREEN because the NEXT
# line names that path as the SOURCE argument of an install, which made the entire vector
# delivery chain unfalsifiable -- the very chain the guard's variable resolver exists for.
expect_red "M25 (§2 coverage: a SOURCE argument is not a write)" soleur-host-bootstrap.sh \
  "/opt/soleur/vector.toml is written by" '
old = "> /opt/soleur/vector.toml"
assert s.count(old) == 1
s = s.replace(old, "> /opt/soleur/vector-TYPO.toml", 1)
'

expect_red "M26 (§2 coverage: install -d creates a DIRECTORY, not an artifact)" server.tf \
  "/etc/soleur/dironly is written by" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/etc/soleur/dironly"
  }""", 1)
'

expect_red "M27 (§2 coverage: a stray VAR= assignment must not credit a destination)" server.tf \
  "/etc/soleur/brand-new-thing.conf is written by" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/etc/soleur/brand-new-thing.conf"
  }""", 1)
'

# A write inside a heredoc body that authors a script NOBODY RUNS. Dead code certifying
# coverage -- structurally the same defect as v1's ExecStart-as-producer row.
expect_red "M28 (§2 coverage: dead-code heredoc body is not delivery)" soleur-host-bootstrap.sh \
  "/etc/soleur/deadcode-artifact.conf is written by" '
import os
# Two-file mutation: the artifact must be REQUIRED (a server.tf destination) before the
# dead-code "delivery" can be tested. Mutating only the bootstrap would be vacuous -- there
# would be nothing for the guard to check, and the green would prove nothing.
sp = os.path.join(os.path.dirname(p), "server.tf")
t = open(sp).read()
a = chr(34) * 3
blk = "  provisioner " + chr(34) + "file" + chr(34) + " {" + chr(10) \
    + "    source      = " + chr(34) + "${path.module}/disk-monitor.sh" + chr(34) + chr(10) \
    + "    destination = " + chr(34) + "/usr/local/bin/disk-monitor.sh" + chr(34) + chr(10) + "  }"
assert blk in t
add = chr(10) + chr(10) + "  provisioner " + chr(34) + "file" + chr(34) + " {" + chr(10) \
    + "    source      = " + chr(34) + "${path.module}/disk-monitor.sh" + chr(34) + chr(10) \
    + "    destination = " + chr(34) + "/etc/soleur/deadcode-artifact.conf" + chr(34) + chr(10) + "  }"
open(sp, "w").write(t.replace(blk, blk + add, 1))
s += chr(10) + "cat > /usr/local/bin/never-invoked.sh <<" + chr(39) + "DEADEOF" + chr(39) + chr(10)
s += "install -m 0644 /opt/x /etc/soleur/deadcode-artifact.conf" + chr(10) + "DEADEOF" + chr(10)
'

# ── Review round 3 (#7014): the assertion sites that were DELETABLE with a green battery ──
# Round 2 proved the guard detects every hostile mutation aimed at it. Round 3 asked the other
# question -- which of the guard's OWN assertion sites could be neutered without this battery
# noticing -- and found five. None was a fail-open at the time; each was a future erosion that
# would have gone uncaught. Every case below was verified by deleting the named assertion from
# the guard and watching this battery go red on the missing anchor.

# The FLOOR_DESTS erosion window, from the other side. Converting `destination = "/abs"` to
# `destination = local.dest_N` is an ordinary HCL refactor, and a bare HCL reference is not a
# quoted string, so the destination did not become a finding -- it LEFT THE SWEEP. Two such
# conversions fitted inside the old floor's slack. This adds one rather than converting one, so
# the case isolates the new extraction branch instead of also moving the sweep count.
#
# THREE members, not one. The property quantifies over "every non-string-literal HCL expression",
# and a single `local.`-shaped fixture is a sample, not a proof: review narrowed the branch to
# `destination\s*=\s*(local\.\S*)` and the battery stayed fully green while `var.x`, `each.value`,
# `module.a.b` and every function call remained silently droppable. Each case anchors on its own
# expression text so they cannot credit one another.
expect_red "M29a (§2 extraction: a local.* reference must not vanish silently)" server.tf \
  "sets destination = local.phantom_dest" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = local.phantom_dest
  }""", 1)
'

# The EMPTY destination. `destination = ""` satisfies neither a 1+-char quoted capture nor the
# non-quote-initial pattern, so before the quoted branch was widened to `([^"]*)` it evaded BOTH
# and left the sweep in silence. The guard fix shipped without this case and the neuter matrix
# scored the widened capture UNCOVERED -- a fix with nothing behind it, which is the shape this
# whole PR exists to remove.
expect_red "M29d (§2 extraction: an EMPTY destination must not vanish silently)" server.tf \
  "delivers to '', an INTERPOLATED" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = ""
  }""", 1)
'

expect_red "M29b (§2 extraction: a var.* reference must not vanish silently)" server.tf \
  "sets destination = var.phantom_dest" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = var.phantom_dest
  }""", 1)
'

expect_red "M29c (§2 extraction: a FUNCTION CALL must not vanish silently)" server.tf \
  "sets destination = trimsuffix(" '
a = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert a in s
s = s.replace(a, a + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = trimsuffix(local.etc, "/")
  }""", 1)
'

# FLOOR_DESTS itself. Deleting ONE delivered artifact is the realistic erosion; it fires because
# the floor is pinned at the exact baseline. §2 reports no UNCOVERED entry (the destination
# leaves both sides of the comparison), but §3's floor co-fires: FLOOR_SEEDED is pinned at its
# own exact baseline too, so removing a bootstrap-installed destination moves the intersection.
# Measured: 2 [FAIL] lines. That is the deliberate cost of margin-zero floors on overlapping
# sweeps -- the anchor still attributes this case to FLOOR_DESTS, which is what the rule requires.
expect_red "M30 (§2 floor: one delivered artifact removed)" server.tf \
  "2: swept only 51 destinations" '
blk = """  provisioner "file" {
    source      = "${path.module}/cron-egress-alarm@.service"
    destination = "/etc/systemd/system/cron-egress-alarm@.service"
  }

"""
assert blk in s
s = s.replace(blk, "", 1)
'

# FLOOR_IDENTITY had margin ZERO and no mutation, so the floor line was deletable. A whitespace
# reformat of the heredoc opener is enough: §4 stops recognising the construct, byte-identity
# quietly covers 3 units instead of 4, and §2 still extracts the destination from the surviving
# `>` redirect -- so ONLY the floor can catch it.
expect_red "M31 (§4 floor: heredoc opener reformatted out of the identity check)" server.tf \
  "4: byte-identity checked on only 3 bodies" '
q = chr(39)
old = "cat > /etc/systemd/system/disk-monitor.timer << " + q + "TIMEREOF" + q
assert old in s
s = s.replace(old, "cat >/etc/systemd/system/disk-monitor.timer <<" + q + "TIMEREOF" + q, 1)
'

# The cloud-init write_files floor. `- path:` must be the FIRST key of the list item for the
# extraction to see it, but cloud-init accepts keys in any order -- so a reordering refactor
# silently shrinks the parsed path set. The four entries chosen are the only write_files paths
# that are NOT also SSH destinations, so the floor fires alone.
expect_red "M32 (§0 floor: write_files key order hides paths from the extraction)" cloud-init.yml \
  "0: cloud-init write_files parsed to only 9 paths" '
for tgt in ["/etc/ssh/sshd_config.d/01-hardening.conf",
            "/etc/sudoers.d/deploy-chown",
            "/etc/systemd/system/webhook.service",
            "/etc/apt/sources.list.d/cloudflare-main.list"]:
    old = "  - path: " + tgt + "\n"
    assert old in s, tgt
    s = s.replace(old, "  - defer: false\n    path: " + tgt + "\n", 1)
'

# §0 early-exit. The bake-list extraction failing is the one condition under which the guard
# abandons the run rather than reporting a clean sweep, and nothing exercised that branch.
expect_red "M33 (§0 early exit: the bake-list opener is renamed away)" server.tf \
  "0: could not parse local.host_script_files" '
old = "host_script_files = ["
assert old in s
s = s.replace(old, "host_script_files_v2 = [", 1)
'

# M33 pins the MESSAGE, not the EXIT. M33b pins the exit -- but NOT via the summary line, which
# was the first attempt and was measured NOT load-bearing: `print(summary)` runs BEFORE
# `sys.exit(1)`, so neutering the exit alone still emits "0 passed, 1 failed" and the assertion
# passed with the site removed.
#
# What the early exit actually buys is a CLEAN named failure. Without it the next statement
# dereferences the None match and the run dies on an AttributeError traceback -- still non-zero,
# still carrying M33's anchor, but the operator now reads a Python stack trace instead of the
# sentence the guard wrote for exactly this case. So the discriminating assertion is the ABSENCE
# of a traceback alongside the presence of the summary.
restore
if apply_mutation server.tf '
old = "host_script_files = ["
assert old in s
s = s.replace(old, "host_script_files_v2 = [", 1)
' && ! cmp -s "$SANDBOX/server.tf" "$PRISTINE/server.tf"; then
  mutations_run=$((mutations_run + 1))
  run_guard
  if grep -qF "Traceback (most recent call last)" "$OUT"; then
    no "M33b (§0 early exit ABORTS cleanly): the guard continued past an unparseable bake list
      and died on a traceback instead of the named failure it had already composed.
      Output: $(<"$OUT")"
  elif grep -qF "0 passed, 1 failed" "$OUT"; then
    ok "M33b (§0 early exit ABORTS cleanly): guard stopped at §0, no traceback"
  else
    no "M33b (§0 early exit ABORTS cleanly): unexpected output. Output: $(<"$OUT")"
  fi
else
  no "M33b: mutation did not land"
fi
restore

# §4 extraction failure. Adds a FIFTH dual-written heredoc whose body cannot be extracted (a
# trailing newline before the closing quote), so the four real identity checks still pass and
# the floor stays satisfied -- the extraction-failure branch is the only thing that can fire.
expect_red "M34 (§4: an unextractable heredoc body is a finding, not a skip)" server.tf \
  "4: could not extract the /etc/default/disk-monitor heredoc body" '
bs = chr(92); dq = chr(34); sq = chr(39)
old = "      " + dq + "chmod 600 /etc/default/disk-monitor" + dq + ","
assert old in s
ins = ("      " + dq + "cat > /etc/default/disk-monitor << " + sq + "ENVEOF" + sq
       + bs + "nRESEND_API_KEY=x" + bs + "nENVEOF" + bs + "n" + dq + "," + chr(10))
s = s.replace(old, ins + old, 1)
'

# §3 non-vacuity floor. Relabelling the install loop destination directory keeps bs_installs at
# full size (so §0 stays green) while emptying most of its overlap with what the SSH path writes
# -- the exact "clean sweep of nothing" the new floor exists to name. §2 co-fires with fifteen
# uncovered destinations, which is inherent: §3 quantifies over an intersection §2 also owns.
expect_red "M35 (§3 floor: the seed-baked check quietly stops checking anything)" soleur-host-bootstrap.sh \
  "3: the seed-baked check ran over only 21" '
old = "install -D -m 0644 -o root -g root \"$SEED/$f\" \"/etc/systemd/system/$f\""
assert old in s
s = s.replace(old, "install -D -m 0644 -o root -g root \"$SEED/$f\" \"/etc/systemd/units.d/$f\"", 1)
'

# ── §5 ALLOWLIST hygiene: reachable only through the guard-side probe (#7014 gap 2) ──
# ALLOWLIST is empty, so no edit to the four input FILES can produce an entry and both hygiene
# checks asserted nothing. The probe feeds a synthetic entry set through the same function.
# It can only ADD failures -- it is never merged into the ALLOWLIST §2 consults -- so this hook
# cannot be turned into a way to silence a real finding.
probes_run=0
probe_reds=0

# expect_probe_red <label> <anchor> <json> [mutator-file] [mutator-script]
# The optional mutation runs FIRST, so a case can require the guard to reach a §2 verdict and
# THEN check what the probe did or did not do to it (P4).
expect_probe_red() {
  local label="$1" anchor="$2" probe="$3" mfile="${4:-}" mscript="${5:-}"
  restore
  if [[ -n "$mfile" ]]; then
    if ! apply_mutation "$mfile" "$mscript"; then
      no "$label: mutator errored -- the mutation never landed"; restore; return
    fi
    if cmp -s "$SANDBOX/$mfile" "$PRISTINE/$mfile"; then
      no "$label: mutation did NOT land ($mfile byte-identical to pristine)"; restore; return
    fi
  fi
  probes_run=$((probes_run + 1))
  probe_reds=$((probe_reds + 1))
  if SOLEUR_INFRA_DIR="$SANDBOX" SOLEUR_PARITY_ALLOWLIST_PROBE="$probe" bash "$GUARD" >"$OUT" 2>&1; then
    no "$label: guard still PASSED with the hygiene rule broken -- the check asserts nothing"
  elif grep -F "[FAIL]" "$OUT" | grep -qF -- "$anchor"; then
    ok "$label: guard went RED on '$anchor'"
  else
    no "$label: guard went red but NOT via '$anchor' -- unrelated reason. Output: $(<"$OUT")"
  fi
  restore
}

expect_probe_green() {
  local label="$1" probe="$2"
  restore
  probes_run=$((probes_run + 1))
  if SOLEUR_INFRA_DIR="$SANDBOX" SOLEUR_PARITY_ALLOWLIST_PROBE="$probe" bash "$GUARD" >"$OUT" 2>&1; then
    ok "$label: guard stayed GREEN on a well-formed entry"
  else
    no "$label: guard went RED on a WELL-FORMED probe entry, so the two REDs above prove only
      that ANY probe reddens -- not that the hygiene rules discriminate. Output: $(<"$OUT")"
  fi
}

expect_probe_red "P1 (§5: an entry with a blank reason)" \
  "ALLOWLIST probe entry '/usr/local/bin/disk-monitor.sh' has no stated reason" \
  '{"/usr/local/bin/disk-monitor.sh": "   "}'

expect_probe_red "P2 (§5: an entry naming a path nothing writes)" \
  "ALLOWLIST probe names /etc/soleur/never-written.conf but no SSH provisioner writes it" \
  '{"/etc/soleur/never-written.conf": "documented reason"}'

expect_probe_green "P3 (§5 control: a well-formed entry is accepted)" \
  '{"/usr/local/bin/disk-monitor.sh": "parity verified by fresh-boot-parity.test.sh"}'

# P4 is the NEGATIVE CONTROL for the whole probe design, and the only case here that can catch
# the probe becoming a fail-open switch. The guard claims twice, in prose, that the probe "can
# only ADD failures, never suppress one". Review demonstrated that claim was verified by nothing:
# adding a single line that merges the probe into the real ALLOWLIST made an uncovered
# destination disappear, and P1/P2/P3 all still scored 3/3. So: break §2 for real (M5's phantom
# destination), then hand the probe an entry naming that exact path. The §2 finding must survive.
expect_probe_red "P4 (§5 negative control: the probe cannot SUPPRESS a §2 finding)" \
  "/etc/soleur/phantom-file.conf is written by" \
  '{"/etc/soleur/phantom-file.conf": "try to suppress me"}' \
  server.tf '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/etc/soleur/phantom-file.conf"
  }""", 1)
'

# P5/P6 reach the two input-validation branches. Commit 1d19bcb73 added the shape check and
# review found NO case reached it -- P1-P3 all pass well-formed JSON objects, so both the
# isinstance guard and the except-branch were deletable with the battery at 43/43.
expect_probe_red "P5 (§5: a non-object probe is named, not a traceback)" \
  "must be a JSON object" '["/usr/local/bin/disk-monitor.sh"]'

expect_probe_red "P6 (§5: unparseable JSON is named, not a traceback)" \
  "is not parseable JSON" '{oops'

# A non-string VALUE reaches `reason.strip()`. Before the value-type check this raised
# AttributeError -- non-zero exit, zero [FAIL] lines, i.e. exactly the unexplained failure the
# shape check exists to replace.
expect_probe_red "P7 (§5: a non-string reason is named, not a traceback)" \
  "must be a JSON object" '{"/usr/local/bin/disk-monitor.sh": null}'

# ── POSITIVE CONTROLS: both directions ───────────────────────────────────────────────
expect_green "control-A (benign comment-only edit)" server.tf '
old = "resource \"terraform_data\" \"disk_monitor_install\" {"
assert old in s
s = s.replace(old, "# benign comment added by the mutation battery\n" + old, 1)
'

# An ADDITION that IS legitimately dual-delivered must stay green, or a guard that reddens on
# any new destination scores a perfect run. It must also MOVE a number the guard prints --
# /usr/local/bin/orphan-reaper.sh was the obvious pick and is useless, because it is ALREADY an
# SSH destination, so the sweep iterated the identical key set and the control asserted nothing.
# cat-deploy-state.sh is bootstrap-installed but NOT currently SSH-written, so this genuinely
# takes the sweep 52 -> 53 and still resolves.
expect_green "control-B (new destination WITH a real fresh-boot writer)" server.tf '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/cat-deploy-state.sh"
    destination = "/usr/local/bin/cat-deploy-state.sh"
  }""", 1)
'

# ── Non-vacuity floor on the battery itself ─────────────────────────────────────────
FLOOR=38
if [[ "$mutations_run" -ge "$FLOOR" ]]; then
  ok "battery ran $mutations_run landed, attributed mutations (floor $FLOOR)"
else
  no "battery ran only $mutations_run landed mutations (floor $FLOOR) -- anchors drifted; the untested invariants are unproven"
fi

# The probes are counted separately: they never touch a file, so `mutations_run`'s
# landed-vs-pristine proof does not apply to them and folding them in would weaken it.
#
# RED probes are counted separately AGAIN. The first version floored `probes_run`, which
# `expect_probe_green` also increments -- so three GREEN controls would have satisfied a floor
# whose failure text claims the RED arms ran. A floor that a passing control can satisfy is not
# a floor on the thing it names.
PROBE_FLOOR=7
PROBE_RED_FLOOR=6
if [[ "$probes_run" -ge "$PROBE_FLOOR" ]]; then
  ok "battery ran $probes_run ALLOWLIST hygiene probes (floor $PROBE_FLOOR)"
else
  no "battery ran only $probes_run ALLOWLIST hygiene probes (floor $PROBE_FLOOR) -- §5 is unproven"
fi
if [[ "$probe_reds" -ge "$PROBE_RED_FLOOR" ]]; then
  ok "battery ran $probe_reds RED-arm probes (floor $PROBE_RED_FLOOR)"
else
  no "battery ran only $probe_reds RED-arm probes (floor $PROBE_RED_FLOOR) -- the green controls
    cannot stand in for them; §5's failure arms are unproven"
fi

echo "=== provisioner-parity mutation: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
