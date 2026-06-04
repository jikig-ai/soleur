#!/usr/bin/env bash
# Drift-guard for the bwrap unprivileged-userns sysctl provisioning in server.tf.
#
# Context: the 2026-06-04 cron silent-producer incident (#4927/#4928). bwrap
# (the Claude Code Bash sandbox) needs kernel.apparmor_restrict_unprivileged_userns=0
# to create a user namespace and mount /proc; without it EVERY cron Bash tool
# call fails silently. The pre-fix provisioning had two drift holes this guard
# locks shut:
#   1. triggers_replace keyed ONLY on the seccomp-file hash — identical on a
#      replaced VM, so the userns sysctl was never asserted on a fresh host
#      (the terraform_data fresh-host trap). Fix: fold hcloud_server.web.id in.
#   2. A one-time `sysctl -w` lost on reboot. Fix: a boot-persistent oneshot
#      systemd unit (bwrap-userns-sysctl.service) that re-asserts on every boot.
#
# Each assertion is anchored on a token the PRE-FIX server.tf did not contain
# (provably non-vacuous).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"

PASS=0
FAIL=0

assert_grep() {
  local description="$1" pattern="$2"
  if grep -qE -- "$pattern" "$SERVER_TF"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (pattern not found: $pattern)"
  fi
}

echo "--- bwrap userns sysctl drift-guard (server.tf) ---"

# 1. Fresh-host coverage: docker_seccomp_config trigger is the MAP form keyed on
#    BOTH the seccomp hash and the server id. Anchored on `seccomp_profile =
#    sha256(` — a key that exists ONLY in the new map form (the pre-fix trigger
#    was a bare `triggers_replace = sha256(...)` with no key). `server_id =
#    hcloud_server.web.id` alone is vacuous: it also appears on the volume
#    attachment, so this anchors on the map restructure that introduces it.
assert_grep "docker_seccomp_config uses the map-form trigger (seccomp hash + server id)" \
  'seccomp_profile[[:space:]]*=[[:space:]]*sha256\(file\('

# 2. Boot-persistent unit exists (survives reboot, re-asserts every boot).
assert_grep "boot-persistent bwrap-userns-sysctl.service unit is installed" \
  '/etc/systemd/system/bwrap-userns-sysctl\.service'

# 3. The unit asserts the exact sysctl that gates bwrap userns/proc.
assert_grep "unit ExecStart asserts kernel.apparmor_restrict_unprivileged_userns=0" \
  'ExecStart=.*sysctl -w kernel\.apparmor_restrict_unprivileged_userns=0'

# 4. The unit is enabled so it runs on every boot, not just at provision time.
assert_grep "bwrap-userns-sysctl.service is enabled --now" \
  'systemctl enable --now bwrap-userns-sysctl\.service'

# 5. WantedBy=multi-user.target so the enable wires it into the boot target.
assert_grep "unit is WantedBy=multi-user.target" \
  'WantedBy=multi-user\.target'

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
