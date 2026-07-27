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

INPUTS=(server.tf cloud-init.yml web-probe-envwrite.sh soleur-host-bootstrap.sh)

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

expect_red "M10 (§2: bootstrap COMMENT does not count as delivery)" soleur-host-bootstrap.sh \
  "/etc/webhook/hooks.json is written by" '
out = []
for L in s.split("\n"):
    if "/etc/webhook/hooks.json" in L and not L.lstrip().startswith("#"):
        out.append(L.replace("/etc/webhook/hooks.json", "/etc/webhook/RENAMED.json"))
    else:
        out.append(L)
out.insert(3, "# historical: we used to write /etc/webhook/hooks.json here")
s = "\n".join(out)
'

# A CONSUMER reference (systemd ExecStart) is not a producer. The old guard credited exactly
# this as proof that cloud-init rendered hooks.json.
expect_red "M11 (§2: a systemd ExecStart consumer reference is not delivery)" soleur-host-bootstrap.sh \
  "/etc/webhook/hooks.json is written by" '
out = []
for L in s.split("\n"):
    if "/etc/webhook/hooks.json" in L and not L.lstrip().startswith("#") and "ExecStart" not in L:
        out.append(L.replace("/etc/webhook/hooks.json", "/etc/webhook/RENAMED.json"))
    else:
        out.append(L)
s = "\n".join(out)
assert "ExecStart" in s
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
FLOOR=27
if [[ "$mutations_run" -ge "$FLOOR" ]]; then
  ok "battery ran $mutations_run landed, attributed mutations (floor $FLOOR)"
else
  no "battery ran only $mutations_run landed mutations (floor $FLOOR) -- anchors drifted; the untested invariants are unproven"
fi

echo "=== provisioner-parity mutation: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
