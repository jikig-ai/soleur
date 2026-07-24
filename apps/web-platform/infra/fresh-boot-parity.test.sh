#!/usr/bin/env bash
set -uo pipefail

# Fresh-boot parity guard for the Phase-2.2 SSH-only host-provisioner bakes (#6459).
#
# CONTEXT: a fresh cattle web host (web-2) never receives web-1's SSH provisioners, so the last
# SSH-only host config came up ABSENT — the #6459 silent-boot gap. Phase 2.2 bakes the 5 files
# (orphan-reaper.{sh,service,timer}, 99-bwrap-userns.conf, bwrap-userns-sysctl.service) into the
# image + installs them via soleur-host-bootstrap.sh + enables the units via cloud-init, so a
# fresh host self-configures them. The SSH provisioners (terraform_data.orphan_reaper_install +
# the sysctl half of docker_seccomp_config) are RETAINED for running-host rotation on the pet
# web-1 until Phase 5.
#
# The load-bearing guard is BYTE-IDENTITY: the baked unit bodies must equal the SSH-heredoc bodies
# in server.tf, so the two delivery paths cannot silently drift while both exist. Plus wiring
# assertions (baked in host_script_files + Dockerfile, installed in bootstrap, enabled in cloud-init).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRV="$DIR/server.tf"
BOOT="$DIR/soleur-host-bootstrap.sh"
CI="$DIR/cloud-init.yml"
DOCKERFILE="$DIR/../Dockerfile"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

BAKED_FILES="orphan-reaper.sh orphan-reaper.service orphan-reaper.timer 99-bwrap-userns.conf bwrap-userns-sysctl.service"

# ── 1. The 5 repo files exist ──
for f in $BAKED_FILES; do
  if [[ -s "$DIR/$f" ]]; then ok "1: repo file present: $f"; else no "1: missing repo file: $f"; fi
done

# ── 2. Each is baked: in host_script_files (server.tf) AND the Dockerfile COPY set ──
for f in $BAKED_FILES; do
  if grep -qE "^[[:space:]]*\"$f\",[[:space:]]*\$" "$SRV"; then
    ok "2a: $f is in server.tf host_script_files"
  else
    no "2a: $f missing from server.tf host_script_files"
  fi
  if grep -qE "^[[:space:]]*/app/infra/$f \\\\$" "$DOCKERFILE"; then
    ok "2b: $f is in the Dockerfile baked COPY"
  else
    no "2b: $f missing from the Dockerfile baked COPY"
  fi
done

# ── 3. Installed by soleur-host-bootstrap.sh ──
# orphan-reaper.sh in a 0755 /usr/local/bin install loop
if grep -qE 'orphan-reaper\.sh' "$BOOT"; then ok "3a: orphan-reaper.sh installed by bootstrap"; else no "3a: orphan-reaper.sh not installed by bootstrap"; fi
# the 3 units in a 0644 /etc/systemd/system install loop
for u in orphan-reaper.service orphan-reaper.timer bwrap-userns-sysctl.service; do
  if grep -qE "$u" "$BOOT"; then ok "3b: $u installed by bootstrap (systemd unit)"; else no "3b: $u not installed by bootstrap"; fi
done
# the sysctl.d drop-in installed to /etc/sysctl.d
if grep -qE 'install -D .*/etc/sysctl\.d/99-bwrap-userns\.conf' "$BOOT"; then
  ok "3c: 99-bwrap-userns.conf installed to /etc/sysctl.d by bootstrap"
else
  no "3c: 99-bwrap-userns.conf not installed to /etc/sysctl.d by bootstrap"
fi

# ── 4. Enabled by cloud-init (the timers/services) ──
if grep -qE 'systemctl enable --now orphan-reaper\.timer' "$CI"; then ok "4a: cloud-init enables orphan-reaper.timer"; else no "4a: cloud-init does not enable orphan-reaper.timer"; fi
if grep -qE 'systemctl enable --now bwrap-userns-sysctl\.service' "$CI"; then ok "4b: cloud-init enables bwrap-userns-sysctl.service"; else no "4b: cloud-init does not enable bwrap-userns-sysctl.service"; fi

# ── 5. BYTE-IDENTITY (the load-bearing guard): each baked unit body == its SSH-heredoc body ──
# Build the repo file as a single-line, literal-\n-joined string (matching the server.tf heredoc
# encoding `cat > <dest> << 'MARKER'\n<body>\nMARKER`), then grep server.tf for the exact match.
assert_byte_identical() { # $1=repo-file  $2=heredoc dest path  $3=marker
  local repo="$1" dest="$2" marker="$3"
  local escaped
  escaped="$(awk 'BEGIN{ORS="\\n"}1' "$DIR/$repo")"   # each line + literal \n; trailing \n included
  if grep -qF "<< '$marker'\\n${escaped}${marker}" "$SRV"; then
    ok "5: baked $repo is byte-identical to its SSH heredoc ($dest)"
  else
    no "5: baked $repo DRIFTED from its SSH heredoc ($dest) — dual-delivery divergence"
  fi
}
assert_byte_identical orphan-reaper.service /etc/systemd/system/orphan-reaper.service UNITEOF
assert_byte_identical orphan-reaper.timer   /etc/systemd/system/orphan-reaper.timer   TIMEREOF
assert_byte_identical bwrap-userns-sysctl.service /etc/systemd/system/bwrap-userns-sysctl.service UNITEOF
# the sysctl.d drop-in value must match the SSH provisioner's echo
if grep -qF "kernel.apparmor_restrict_unprivileged_userns=0" "$DIR/99-bwrap-userns.conf" \
   && grep -qF "echo 'kernel.apparmor_restrict_unprivileged_userns=0' > /etc/sysctl.d/99-bwrap-userns.conf" "$SRV"; then
  ok "5: 99-bwrap-userns.conf value matches the SSH provisioner's echo"
else
  no "5: 99-bwrap-userns.conf value drifted from the SSH provisioner"
fi

# ── 6. The SSH provisioners are RETAINED (Phase 2 adds fresh-boot coverage; Phase 5 removes SSH) ──
if grep -qE 'resource "terraform_data" "orphan_reaper_install"' "$SRV"; then
  ok "6: terraform_data.orphan_reaper_install retained (running-host rotation until Phase 5)"
else
  no "6: orphan_reaper_install SSH provisioner was removed — that is a Phase-5 change, not Phase 2"
fi

echo "=== fresh-boot-parity: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
