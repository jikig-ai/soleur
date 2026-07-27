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
#
# Assertion predicates read a FILE or use bash `[[ ]]`; none pipe into `grep -q`, whose
# SIGPIPE-on-early-match fails OPEN under `set -o pipefail`.

# shellcheck disable=SC2016
# ^ Every mutator below is a PYTHON program passed as a single-quoted bash string. Shell
#   expansion inside them would be a bug, not a feature: `$` and backticks belong to the
#   python source. File-scoped because all mutators share the shape.

set -uo pipefail

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
# EXPECTED_INPUTS is not redundant with the derivation. The derivation keeps the battery
# CORRECT under drift; the reconciliation makes the drift VISIBLE, so adding an input is a
# deliberate two-file edit rather than a silent widening of what the sandbox covers.
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
# half, and a read that bypasses the loop would reopen the same hole from the other side. The
# guard funnels every read through one helper (`def read(n)`), so assert (a) that helper is
# still the single reader -- exactly one `os.path.join(INFRA` in the file -- and (b) every
# `read("<name>")` call site names a file this battery actually copies into the sandbox.
n_join=$(grep -cF 'os.path.join(INFRA' "$GUARD")
if [[ "$n_join" != "1" ]]; then
  echo "FATAL: expected exactly one 'os.path.join(INFRA' in the guard (the read() helper), found $n_join." >&2
  echo "  A second reader can take an input this battery never sandboxes. Route it through read()." >&2
  exit 2
fi
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
restore()   { for f in "${INPUTS[@]}"; do cp "$PRISTINE/$f" "$SANDBOX/$f"; done; }

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
    no "$label: guard went red but NOT via '$anchor' -- it failed for an unrelated reason, so
      this mutation proves nothing about the check it is named for"
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
expect_red "M10 (§2: a COMMENT naming the path does not count as delivery)" soleur-host-bootstrap.sh \
  "/usr/local/bin/orphan-reaper.sh is written by" '
out = []
for L in s.split("\n"):
    if "orphan-reaper.sh" in L and not L.lstrip().startswith("#"):
        out.append(L.replace("orphan-reaper.sh", "orphan-reaper-RENAMED.sh"))
    else:
        out.append(L)
out.insert(3, "# historical: this bootstrap used to install /usr/local/bin/orphan-reaper.sh")
s = "\n".join(out)
assert "/usr/local/bin/orphan-reaper.sh" in "\n".join(out)
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
expect_red "M29 (§2 extraction: a non-literal destination must not vanish silently)" server.tf \
  "an HCL REFERENCE rather than a string literal" '
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

# FLOOR_DESTS itself. Deleting ONE delivered artifact is the realistic erosion; it now fires
# because the floor is pinned at the exact baseline. Nothing else moves: the destination leaves
# both sides of the comparison, so §2 reports no uncovered entry and §3 stays above its floor.
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

expect_probe_red() {
  local label="$1" anchor="$2" probe="$3"
  restore
  probes_run=$((probes_run + 1))
  if SOLEUR_INFRA_DIR="$SANDBOX" SOLEUR_PARITY_ALLOWLIST_PROBE="$probe" bash "$GUARD" >"$OUT" 2>&1; then
    no "$label: guard still PASSED with the hygiene rule broken -- the check asserts nothing"
  elif grep -F "[FAIL]" "$OUT" | grep -qF -- "$anchor"; then
    ok "$label: guard went RED on '$anchor'"
  else
    no "$label: guard went red but NOT via '$anchor' -- it failed for an unrelated reason"
  fi
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
FLOOR=34
if [[ "$mutations_run" -ge "$FLOOR" ]]; then
  ok "battery ran $mutations_run landed, attributed mutations (floor $FLOOR)"
else
  no "battery ran only $mutations_run landed mutations (floor $FLOOR) -- anchors drifted; the untested invariants are unproven"
fi

# The probes are counted separately: they never touch a file, so `mutations_run`'s
# landed-vs-pristine proof does not apply to them and folding them in would weaken it.
PROBE_FLOOR=3
if [[ "$probes_run" -ge "$PROBE_FLOOR" ]]; then
  ok "battery ran $probes_run ALLOWLIST hygiene probes (floor $PROBE_FLOOR)"
else
  no "battery ran only $probes_run ALLOWLIST hygiene probes (floor $PROBE_FLOOR) -- §5 is unproven"
fi

echo "=== provisioner-parity mutation: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
