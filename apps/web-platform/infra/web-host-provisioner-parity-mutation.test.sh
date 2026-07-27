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
#   3. Every RED is attributed to a named check (above).
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
  elif [[ "$(<"$OUT")" == *"$anchor"* ]]; then
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

# The case a presence-check misses: fanned out, but a web-1 literal survives elsewhere in the
# block (a nested per-provisioner connection is the standard HCL idiom for retargeting one
# provisioner). The old guard passed this; asserting ABSENCE of for_each is what catches it.
expect_red "M3 (§1: for_each + surviving web-1 literal in a nested connection)" server.tf \
  "for_each'd=['orphan_reaper_install']" '
old = "resource \"terraform_data\" \"orphan_reaper_install\" {"
assert old in s
s = s.replace(old, old + "\n  for_each = var.web_hosts", 1)
'

expect_red "M4 (§1: resource renamed with uppercase/hyphen still swept, then deleted)" server.tf \
  "1: swept only 14 SSH-connected" '
import re
m = re.search(r"resource \"terraform_data\" \"cosign_trusted_root\" \{", s)
assert m
end = s.index("\nresource ", m.end())
s = s[:m.start()] + s[end+1:]
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

# ── POSITIVE CONTROLS: both directions ───────────────────────────────────────────────
expect_green "control-A (benign comment-only edit)" server.tf '
old = "resource \"terraform_data\" \"disk_monitor_install\" {"
assert old in s
s = s.replace(old, "# benign comment added by the mutation battery\n" + old, 1)
'

# The direction the old battery never tested: an ADDITION that IS legitimately dual-delivered
# must stay green. Without this, a guard that reddens on any new destination scores perfectly.
expect_green "control-B (new destination WITH a real fresh-boot writer)" server.tf '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/orphan-reaper.sh"
    destination = "/usr/local/bin/orphan-reaper.sh"
  }""", 1)
'

# ── Non-vacuity floor on the battery itself ─────────────────────────────────────────
FLOOR=17
if [[ "$mutations_run" -ge "$FLOOR" ]]; then
  ok "battery ran $mutations_run landed, attributed mutations (floor $FLOOR)"
else
  no "battery ran only $mutations_run landed mutations (floor $FLOOR) -- anchors drifted; the untested invariants are unproven"
fi

echo "=== provisioner-parity mutation: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
