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

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Phase 2.2 PART 2 — the 3 SSH-only probes (#6438/#6548): private-NIC guard, zot-consumer,
# git-data reachability. Unlike Part 1's orphan-reaper (heredoc units), the probes deliver their
# .sh + .service + .timer via `provisioner "file"` from the SAME repo files, so the units are
# byte-identical across both paths BY CONSTRUCTION (no heredoc-drift risk). What DOES diverge is
# the per-host env file (/etc/default/web-<probe>): the SSH path writes it via a remote-exec
# `printf`, the fresh-boot path writes it via the baked `web-probe-envwrite.sh` invoked by
# cloud-init. The env-content parity guard (section 12) pins the KEY SET of the two writers equal.
PROBE_SCRIPTS="web-private-nic-guard.sh web-zot-consumer-probe.sh web-git-data-probe.sh web-probe-envwrite.sh"
PROBE_UNITS="web-private-nic-guard.service web-private-nic-guard.timer \
             web-zot-consumer-probe.service web-zot-consumer-probe.timer \
             web-git-data-probe.service web-git-data-probe.timer"
PROBE_DESTS="web-private-nic-guard web-zot-consumer-probe web-git-data-probe"

# ── 7. Repo files exist (3 probe scripts + the new baked env-writer + 6 units) ──
for f in $PROBE_SCRIPTS $PROBE_UNITS; do
  if [[ -s "$DIR/$f" ]]; then ok "7: repo file present: $f"; else no "7: missing repo file: $f"; fi
done

# ── 8. Each baked: in host_script_files (server.tf) AND the Dockerfile COPY set ──
for f in $PROBE_SCRIPTS $PROBE_UNITS; do
  if grep -qE "^[[:space:]]*\"$f\",[[:space:]]*\$" "$SRV"; then
    ok "8a: $f is in server.tf host_script_files"
  else
    no "8a: $f missing from server.tf host_script_files"
  fi
  if grep -qE "^[[:space:]]*/app/infra/$f \\\\$" "$DOCKERFILE"; then
    ok "8b: $f is in the Dockerfile baked COPY"
  else
    no "8b: $f missing from the Dockerfile baked COPY"
  fi
done

# ── 9. Installed by soleur-host-bootstrap.sh (scripts 0755 /usr/local/bin, units 0644 systemd) ──
for s in $PROBE_SCRIPTS; do
  if grep -qE "$s" "$BOOT"; then ok "9a: $s installed by bootstrap (script)"; else no "9a: $s not installed by bootstrap"; fi
done
for u in $PROBE_UNITS; do
  if grep -qE "$u" "$BOOT"; then ok "9b: $u installed by bootstrap (systemd unit)"; else no "9b: $u not installed by bootstrap"; fi
done

# ── 10. cloud-init invokes the baked env-writer BEFORE enabling the probe timers ──
if grep -qE 'web-probe-envwrite\.sh' "$CI"; then
  ok "10: cloud-init invokes web-probe-envwrite.sh"
else
  no "10: cloud-init does not invoke web-probe-envwrite.sh (env files would be absent on fresh boot)"
fi

# ── 11. cloud-init enables the 3 probe timers ──
for d in $PROBE_DESTS; do
  if grep -qE "systemctl enable --now $d\.timer" "$CI"; then
    ok "11: cloud-init enables $d.timer"
  else
    no "11: cloud-init does not enable $d.timer"
  fi
done

# ── 12. ENV-CONTENT PARITY (load-bearing): the baked env-writer emits the SAME key set for each
#        /etc/default/web-<probe> as the retained SSH remote-exec printf — encoding-agnostic
#        (server.tf HCL uses `\\n`, the bash env-writer uses `\n`, so compare KEYS not raw bytes). ──
env_keys_from() { # $1=file  $2=dest-basename → sorted-unique KEY= tokens on the printf line writing that dest
  grep -F "/etc/default/$2" "$1" | grep -oE "printf '[^']*'" | grep -oE '[A-Za-z_][A-Za-z_0-9]*=' | sort -u
}
for d in $PROBE_DESTS; do
  ssh_keys="$(env_keys_from "$SRV" "$d")"
  bake_keys="$(env_keys_from "$DIR/web-probe-envwrite.sh" "$d")"
  if [[ -n "$ssh_keys" && "$ssh_keys" == "$bake_keys" ]]; then
    ok "12: /etc/default/$d key set matches across SSH remote-exec and baked env-writer"
  else
    no "12: /etc/default/$d key set DRIFTED (ssh=[$(echo $ssh_keys)] bake=[$(echo $bake_keys)])"
  fi
done

# ── 13. The 3 probe SSH provisioners are RETAINED (Phase 2 adds coverage; Phase 5 removes SSH) ──
for r in private_nic_guard_install zot_consumer_probe_install git_data_probe_install; do
  if grep -qE "resource \"terraform_data\" \"$r\"" "$SRV"; then
    ok "13: terraform_data.$r retained (web-1 running-host rotation until Phase 5)"
  else
    no "13: $r SSH provisioner was removed — that is a Phase-5 change, not Phase 2"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────────────────────
# #6931 PART 3 — guest-side fresh-boot LUKS (ADR-263). A fresh cattle host never receives web-1's SSH
# installers (terraform_data.workspaces_boot_unlock_install / luks_monitor_install), so the LUKS
# provisioner, the reopen family and the daily probe are BAKED, installed by the bootstrap, and driven
# by cloud-init. The two delivery paths take the SAME repo files as source (byte-identical by
# construction); what is written by CODE on each path — the crypttab / fstab / drop-in / env-file lines —
# is pinned equal to local.workspaces_boot_unlock_* here.
LUKS_SCRIPTS="workspaces-luks-provision.sh workspaces-luks-reopen.sh workspaces-luks-emit.sh luks-monitor.sh"
LUKS_UNITS="workspaces-luks-reopen.service workspaces-luks-reopen.timer workspaces-luks-reopen-failure.service luks-monitor.service luks-monitor.timer"
LUKSTF="$DIR/workspaces-luks.tf"
PROV="$DIR/workspaces-luks-provision.sh"

line_of() { { grep -nF -- "$2" "$1" 2>/dev/null | sed -n '1p' | cut -d: -f1; } || true; }

# ── 14. Repo files exist; each is baked (host_script_files + Dockerfile COPY) ──
for f in $LUKS_SCRIPTS $LUKS_UNITS; do
  if [[ -s "$DIR/$f" ]]; then ok "14: repo file present: $f"; else no "14: missing repo file: $f"; fi
  if grep -qE "^[[:space:]]*\"$f\",[[:space:]]*\$" "$SRV"; then ok "14a: $f is in server.tf host_script_files"; else no "14a: $f missing from server.tf host_script_files"; fi
  if grep -qE "^[[:space:]]*/app/infra/$f \\\\$" "$DOCKERFILE"; then ok "14b: $f is in the Dockerfile baked COPY"; else no "14b: $f missing from the Dockerfile baked COPY"; fi
done

# ── 15. Installed by the bootstrap (scripts 0755 /usr/local/bin — luks-monitor WITHOUT the suffix — units 0644) ──
for f in workspaces-luks-provision.sh workspaces-luks-reopen.sh workspaces-luks-emit.sh; do
  if grep -qE "^[[:space:]]+(.*[[:space:]])?$f[[:space:]\\\;]" "$BOOT"; then ok "15a: $f installed by bootstrap (script)"; else no "15a: $f not installed by bootstrap"; fi
done
if grep -qE 'install -D -m 0755 -o root -g root "\$SEED/luks-monitor\.sh" /usr/local/bin/luks-monitor$' "$BOOT"; then
  ok "15b: luks-monitor.sh installs as /usr/local/bin/luks-monitor (no suffix, as luks-monitor.service names it)"
else
  no "15b: luks-monitor.sh must install as /usr/local/bin/luks-monitor"
fi
for u in $LUKS_UNITS; do
  if grep -qE "$u" "$BOOT"; then ok "15c: $u installed by bootstrap (systemd unit)"; else no "15c: $u not installed by bootstrap"; fi
done

# ── 16. cloud-init: env file, ONE provisioner call, and a hard gate BEFORE anything writes under /mnt/data ──
CIC="$(awk '$0 !~ /^[[:space:]]*#/' "$CI")"
ln_prov="$(line_of "$CI" '/usr/local/bin/workspaces-luks-provision.sh')"
ln_gate="$(line_of "$CI" 'workspaces_luks_not_mounted')"
ln_mk="$(line_of "$CI" 'mkdir -p /mnt/data/workspaces')"
ln_seed="$(line_of "$CI" 'docker cp soleur-plugin-seed')"
if [[ -n "$ln_prov" && -n "$ln_gate" && -n "$ln_mk" && "$ln_prov" -lt "$ln_gate" && "$ln_gate" -lt "$ln_mk" ]]; then
  ok "16a: cloud-init runs the provisioner (line $ln_prov), then the hard gate ($ln_gate), BEFORE mkdir /mnt/data/workspaces ($ln_mk)"
else
  no "16a: provisioner/gate/mkdir order wrong (prov=$ln_prov gate=$ln_gate mkdir=$ln_mk)"
fi
if [[ -n "$ln_gate" && -n "$ln_seed" && "$ln_gate" -lt "$ln_seed" ]]; then ok "16b: the hard gate precedes the plugin-seed block that also writes under /mnt/data"; else no "16b: the gate must precede the plugin-seed docker cp (gate=$ln_gate seed=$ln_seed)"; fi
if printf '%s\n' "$CIC" | grep -qE 'poweroff -f' && printf '%s\n' "$CIC" | grep -E 'workspaces_luks_not_mounted' | grep -q 'poweroff -f'; then ok "16c: a failed gate powers the host off (fail closed), it does not fall through"; else no "16c: the workspaces_luks_not_mounted gate must poweroff -f"; fi
if printf '%s\n' "$CIC" | grep -q "WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s" && printf '%s\n' "$CIC" | grep -q 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks'; then
  ok "16d: cloud-init writes the same two env-file keys the SSH installer writes"
else
  no "16d: cloud-init must write WORKSPACES_LUKS_DEV (by-id) and WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks"
fi
if printf '%s\n' "$CIC" | grep -qF "workspaces_luks_fresh_boot_token" && printf '%s\n' "$CIC" | grep -qF 'LUKS_MONITOR_PROFILE=standby' && printf '%s\n' "$CIC" | grep -qF 'install -m 600 -o root -g root /dev/null /etc/default/luks-monitor'; then
  ok "16e: /etc/default/luks-monitor is created 0600, carries the fresh-host token and the standby profile"
else
  no "16e: cloud-init must create /etc/default/luks-monitor 0600 with the fresh-host token + LUKS_MONITOR_PROFILE=standby"
fi
if ! printf '%s\n' "$CIC" | grep -qE "fstab|mount /mnt/data|mount /dev/disk/by-id"; then ok "16f: cloud-init no longer appends fstab or mounts /mnt/data itself (the provisioner owns both)"; else no "16f: cloud-init still writes fstab / mounts /mnt/data directly"; fi
if grep -qF 'workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot.key' "$SRV"; then ok "16g: server.tf passes the fresh-host token into the user_data map"; else no "16g: server.tf must pass workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot.key"; fi

# ── 17. CANONICAL-LINES PARITY (load-bearing): what the provisioner WRITES == what the web-1 installer writes ──
# crypttab: the HCL line with the volume id folded into $DEV equals the provisioner's CRYPTTAB_LINE.
tf_crypt="$(sed -n "s/^[[:space:]]*\"LINE='\\(workspaces [^']*\\)'\",\$/\\1/p" "$LUKSTF" | sed -n '1p' | sed 's|/dev/disk/by-id/scsi-0HC_Volume_\${hcloud_volume.workspaces_luks.id}|$DEV|')"
prov_crypt="$(sed -n 's/^CRYPTTAB_LINE="\(.*\)"$/\1/p' "$PROV" | sed -n '1p' | sed 's/\$MAPPER_NAME/workspaces/')"
if [[ -n "$tf_crypt" && "$tf_crypt" == "$prov_crypt" ]]; then ok "17a: crypttab line is byte-identical across the SSH installer and the provisioner ($tf_crypt)"; else no "17a: crypttab line DRIFTED (tf='$tf_crypt' provisioner='$prov_crypt')"; fi
# fstab: the one canonical mapper line.
tf_fstab="$(sed -n "s/.*printf '%s\\\\\\\\n' '\\(\\/dev\\/mapper\\/workspaces \\/mnt\\/data [^']*\\)' >> .*/\\1/p" "$LUKSTF" | sed -n '1p')"
prov_fstab="$(sed -n "s/^FSTAB_LINE='\\(.*\\)'\$/\\1/p" "$PROV" | sed -n '1p')"
if [[ -n "$tf_fstab" && "$tf_fstab" == "$prov_fstab" ]]; then ok "17b: fstab line is byte-identical across the two paths ($tf_fstab)"; else no "17b: fstab line DRIFTED (tf='$tf_fstab' provisioner='$prov_fstab')"; fi
# docker drop-in: three lines.
prov_drop="$(awk '/^DROPIN_BODY=/{f=1; sub(/^DROPIN_BODY=.\x27?/,""); if ($0 != "") printf "%s\\\\n", $0; next} f && /^\x27$/{f=0} f{printf "%s\\\\n", $0}' "$PROV")"
prov_drop="[Unit]${prov_drop#\[Unit\]}"
if [[ "$prov_drop" == '[Unit]\\nRequiresMountsFor=/mnt/data\\nAfter=workspaces-luks-reopen.service\\n' ]] && grep -qF "printf '$prov_drop' > " "$LUKSTF"; then
  ok "17c: docker.service.d drop-in body is byte-identical across the two paths"
else
  no "17c: drop-in DRIFTED (provisioner body='$prov_drop' not found verbatim in the SSH installer's printf)"
fi
# env-file keys.
if grep -qF "WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s" "$LUKSTF" && grep -qF "WORKSPACES_DOPPLER_CONFIG=%s" "$LUKSTF" && grep -qE "'prd_workspaces_luks'" "$LUKSTF"; then ok "17d: the SSH installer writes the env-file keys the provisioner reads"; else no "17d: SSH installer env-file keys drifted from the provisioner's reads"; fi
# Both baked reopen files are the SAME source files the SSH installer ships.
for f in workspaces-luks-reopen.sh workspaces-luks-reopen.service workspaces-luks-reopen.timer workspaces-luks-reopen-failure.service; do
  if grep -qE "\\\$\{path\.module\}/$f" "$LUKSTF"; then ok "17e: the SSH installer sources $f from the same repo file the image bakes"; else no "17e: SSH installer does not source $f from the repo file"; fi
done

# ── 18. Guard 1 static scope: no isLuks / luksFormat / mkfs outside the provisioner's chokepoints ──
for f in "$CI" "$BOOT"; do
  code="$(awk '$0 !~ /^[[:space:]]*#/' "$f")"
  if printf '%s\n' "$code" | grep -qE 'cryptsetup[[:space:]]+(isLuks|luksFormat)|mkfs(\.|[[:space:]])'; then no "18: $(basename "$f") contains isLuks/luksFormat/mkfs (only the provisioner may)"; else ok "18: $(basename "$f") contains no isLuks/luksFormat/mkfs"; fi
done
if grep -qF 'by-label/workspaces_luks' "$BOOT"; then no "18: the bootstrap still writes the foreign by-label crypttab line (it would collide with the canonical one)"; else ok "18: the bootstrap no longer writes a foreign crypttab line"; fi

# ── 19. The raw-at-birth volume: no `format`, and `ignore_changes = [format]` beside `prevent_destroy` ──
VOLBLK="$(awk '/^resource "hcloud_volume" "workspaces" \{/{f=1} f{print} f&&/^\}/{exit}' "$SRV" | awk '$0 !~ /^[[:space:]]*#/')"
if [[ -n "$VOLBLK" ]] && ! printf '%s\n' "$VOLBLK" | grep -qE '^[[:space:]]*format[[:space:]]*='; then ok "19a: hcloud_volume.workspaces declares no format (a volume is born raw)"; else no "19a: hcloud_volume.workspaces must not declare format"; fi
if printf '%s\n' "$VOLBLK" | grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[format\]' && printf '%s\n' "$VOLBLK" | grep -qE '^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true'; then ok "19b: ignore_changes = [format] sits beside prevent_destroy = true (a no-op merge for the live volumes)"; else no "19b: hcloud_volume.workspaces must carry ignore_changes = [format] AND prevent_destroy = true (neither half may be dropped alone)"; fi

echo "=== fresh-boot-parity: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
