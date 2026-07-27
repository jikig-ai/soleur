#!/usr/bin/env bash
# Mutation battery for web-host-provisioner-parity.test.sh (#7000).
#
# WHY THIS EXISTS. web-host-provisioner-parity.test.sh is GREEN against the tree it ships
# with -- as every drift guard is on the day it lands. Green tells you nothing about
# whether it can go RED. This battery breaks each invariant it claims, one at a time, on a
# SANDBOX COPY, and requires the guard to fail for each. A guard that cannot fail is not a
# guard, and this repo has shipped that exact shape before (a rule that "paged nobody",
# a fail-open negative assert, a harness re-declaring the good idiom instead of driving
# the real file).
#
# Three anti-vacuity properties this battery holds itself to:
#   1. It drives the REAL guard script against a sandbox (via SOLEUR_INFRA_DIR), never a
#      re-declaration of its logic in a heredoc. A battery that tests a copy of the good
#      idiom proves the copy is good.
#   2. Every mutation is proven to have LANDED (the mutated text must differ from the
#      pristine text) before the RED is credited. A no-op `str.replace` that silently
#      matched nothing would otherwise read as "guard failed to catch it" OR, worse, the
#      guard's pass would be credited against an unmutated file.
#   3. A POSITIVE CONTROL (benign edit) must stay GREEN, so a guard that is simply
#      always-red cannot score a perfect run here.
#
# Assertion predicates read a FILE or use bash `[[ ]]`; none pipe into `grep -q`, whose
# SIGPIPE-on-early-match fails OPEN under `set -o pipefail` and would make every negative
# case pass vacuously.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
REAL_INFRA="$ROOT/apps/web-platform/infra"
GUARD="$REAL_INFRA/web-host-provisioner-parity.test.sh"
[[ -f "$GUARD" ]] || { echo "FATAL: $GUARD not found" >&2; exit 2; }

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

SANDBOX="$(mktemp -d -t provparity.XXXXXXXX)" || exit 2
PRISTINE="$(mktemp -d -t provparity-pristine.XXXXXXXX)" || exit 2
trap 'rm -rf "$SANDBOX" "$PRISTINE"' EXIT INT TERM HUP

for f in server.tf cloud-init.yml web-probe-envwrite.sh; do
  cp "$REAL_INFRA/$f" "$SANDBOX/$f" || exit 2
  cp "$REAL_INFRA/$f" "$PRISTINE/$f" || exit 2
done

run_guard() { SOLEUR_INFRA_DIR="$SANDBOX" bash "$GUARD" >/dev/null 2>&1; }

restore() { for f in server.tf cloud-init.yml web-probe-envwrite.sh; do cp "$PRISTINE/$f" "$SANDBOX/$f"; done; }

# apply <file> <python-expression-mutator>; proves the mutation changed the file.
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

# expect_red <label> <file> <mutator>
expect_red() {
  local label="$1" file="$2" script="$3"
  restore
  if ! apply_mutation "$file" "$script"; then
    no "$label: mutator itself errored (anchor missing?) -- the mutation never landed"
    restore
    return
  fi
  if cmp -s "$SANDBOX/$file" "$PRISTINE/$file"; then
    no "$label: mutation did NOT land ($file byte-identical to pristine) -- a no-op edit "
    restore
    return
  fi
  mutations_run=$((mutations_run + 1))
  if run_guard; then
    no "$label: guard still PASSED with the invariant broken -- it cannot detect this"
  else
    ok "$label: guard went RED"
  fi
  restore
}

# ── Baseline: the pristine sandbox must be GREEN ─────────────────────────────────────
restore
if run_guard; then
  ok "baseline: guard is GREEN against the unmutated tree"
else
  no "baseline: guard is RED against the UNMUTATED tree -- every 'RED' below would be "\
"meaningless. Fix the guard before trusting this battery."
  echo "=== provisioner-parity mutation: $pass passed, $fail failed ===" >&2
  exit 1
fi

# ── M1 §1 resource floor: delete an entire SSH provisioner ───────────────────────────
expect_red "M1 (§1 floor: orphan_reaper_install deleted)" server.tf '
import re
m = re.search(r"resource \"terraform_data\" \"orphan_reaper_install\" \{", s)
assert m, "anchor missing"
end = s.index("\nresource ", m.end())
s = s[:m.start()] + s[end+1:]
'

# ── M2 §1 pinning: fan a provisioner out over var.web_hosts ──────────────────────────
# The change #7000 originally asked for. It must trip the guard, because CI has no SSH
# route to web-2 and a bare -target hits every for_each instance.
expect_red "M2 (§1 pinning: disk_monitor fanned out over var.web_hosts)" server.tf '
old = "resource \"terraform_data\" \"disk_monitor_install\" {"
assert old in s, "anchor missing"
s = s.replace(old, old + "\n  for_each = var.web_hosts", 1)
s = s.replace(
  "    host        = hcloud_server.web[\"web-1\"].ipv4_address\n"
  "    user        = \"root\"\n"
  "    private_key = var.ci_ssh_private_key         # null in operator-local context\n"
  "    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI\n"
  "  }\n\n  provisioner \"file\" {\n"
  "    source      = \"${path.module}/disk-monitor.sh\"",
  "    host        = hcloud_server.web[each.key].ipv4_address\n"
  "    user        = \"root\"\n"
  "    private_key = var.ci_ssh_private_key\n"
  "    agent       = var.ci_ssh_private_key == null\n"
  "  }\n\n  provisioner \"file\" {\n"
  "    source      = \"${path.module}/disk-monitor.sh\"", 1)
'

# ── M3 §2: SSH-deliver a file that is not baked and not in cloud-init ────────────────
expect_red "M3 (§2: unbaked provisioner-file source added)" server.tf '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s, "anchor missing"
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/phantom-web1-only.sh"
    destination = "/usr/local/bin/phantom-web1-only.sh"
  }""", 1)
'

# ── M4 §3: heredoc-write a destination with no fresh-boot counterpart ────────────────
expect_red "M4 (§3: heredoc to a dest with no counterpart)" server.tf '
old = "      \"systemctl enable --now orphan-reaper.timer\","
assert old in s, "anchor missing"
s = s.replace(old,
  "      \"cat > /etc/systemd/system/phantom.service << \x27PHEOF\x27\\n[Unit]\\nDescription=Phantom\\nPHEOF\",\n" + old, 1)
'

# ── M5 §4: drift a dual-written unit body (server.tf side) ──────────────────────────
expect_red "M5 (§4: server.tf heredoc body drifts from cloud-init)" server.tf '
old = "Description=Disk space monitor"
assert old in s, "anchor missing"
s = s.replace(old, "Description=Disk space monitor DRIFTED", 1)
'

# ── M6 §4: drift the SAME body from the cloud-init side ─────────────────────────────
expect_red "M6 (§4: cloud-init write_files body drifts from server.tf)" cloud-init.yml '
old = "Description=Run disk monitor every 5 minutes"
assert old in s, "anchor missing"
s = s.replace(old, "Description=Run disk monitor every 4 minutes", 1)
'

# ── M7 §5: write a rendered env file absent from the COVERAGE table ─────────────────
expect_red "M7 (§5: rendered dest missing from COVERAGE)" server.tf '
old = "      \"chmod 600 /etc/default/disk-monitor\","
assert old in s, "anchor missing"
s = s.replace(old,
  "      \"printf \x27X=1\\\\n\x27 > /etc/default/phantom-env\",\n" + old, 1)
'

# ── M8 §5 stale row: stop writing a destination the COVERAGE table still claims ─────
expect_red "M8 (§5: stale COVERAGE row for a no-longer-written dest)" server.tf '
old = "    content     = local.docker_daemon_json\n    destination = \"/etc/docker/daemon.json\"\n"
assert old in s, "anchor missing"
s = s.replace(old, "    content     = local.docker_daemon_json\n    destination = \"/etc/docker/daemon-renamed.json\"\n", 1)
'

# ── M9 §0: break the bake set so the parse floor trips ──────────────────────────────
expect_red "M9 (§0: host_script_files truncated below the parse floor)" server.tf '
import re
m = re.search(r"host_script_files = \[(.*?)\n  \]", s, re.S)
assert m, "anchor missing"
s = s[:m.start(1)] + "\n    \"disk-monitor.sh\",\n" + s[m.end(1):]
'

# ── M10 §5 envwriter: unbake the env-writer the probes depend on ────────────────────
expect_red "M10 (§5: web-probe-envwrite.sh dropped from the bake set)" server.tf '
old = "    \"web-probe-envwrite.sh\",\n"
assert old in s, "anchor missing"
s = s.replace(old, "", 1)
'

# ── M11 §2 comment contamination: a COMMENT must not satisfy the bake requirement ────
# The cq-assert-anchor-not-bare-token case, and a defect this guard actually shipped with:
# server.tf's bake list carries 46 comment lines, one containing the literal
# `provisioner "file"`, so parsing the list raw counted `file` as a baked filename. Here an
# artifact is SSH-delivered while its ONLY claim to being baked is a COMMENT naming it. A
# guard that reads prose as configuration passes this; the real one must go RED.
expect_red "M11 (§2: bake claim backed only by a comment)" server.tf '
anchor = """  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }"""
assert anchor in s, "anchor missing"
s = s.replace(anchor, anchor + """

  provisioner "file" {
    source      = "${path.module}/comment-only-artifact.sh"
    destination = "/usr/local/bin/comment-only-artifact.sh"
  }""", 1)
old = "    \"web-probe-envwrite.sh\",\n"
assert old in s, "bake anchor missing"
s = s.replace(old, old + "    # \"comment-only-artifact.sh\",\n", 1)
'

# ── POSITIVE CONTROL: a benign edit must stay GREEN ─────────────────────────────────
# Without this, a guard that is unconditionally RED would score 10/10 above.
restore
apply_mutation server.tf '
old = "resource \"terraform_data\" \"disk_monitor_install\" {"
assert old in s, "anchor missing"
s = s.replace(old, "# benign comment added by the mutation battery positive control\n" + old, 1)
'
if cmp -s "$SANDBOX/server.tf" "$PRISTINE/server.tf"; then
  no "control: benign edit did not land -- the control proves nothing"
elif run_guard; then
  ok "control: benign comment-only edit keeps the guard GREEN (it is not always-red)"
else
  no "control: guard went RED on a benign comment-only edit -- it is over-sensitive"
fi
restore

# ── Non-vacuity floor on the battery itself ─────────────────────────────────────────
FLOOR=11
if [[ "$mutations_run" -ge "$FLOOR" ]]; then
  ok "battery ran $mutations_run landed mutations (floor $FLOOR)"
else
  no "battery ran only $mutations_run landed mutations (floor $FLOOR) -- anchors have "\
"drifted and the untested invariants are unproven"
fi

echo "=== provisioner-parity mutation: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
