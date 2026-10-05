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
# One scratch root owns every mutation copy this suite makes; the EXIT trap removes it.
PAR_SCR="$(mktemp -d -t fbp.XXXXXXXX)"  # lint-trap-ownership: ok — single scratch root, removed by the EXIT trap on the next line
trap 'rm -rf "${PAR_SCR:?}"' EXIT

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

# ── 14c. The lists above are restated by hand, so a NEW baked LUKS file would be invisible to every section
# below: every workspaces-luks-*/luks-monitor script or unit in the directory (the test harness aside) must be
# named in LUKS_SCRIPTS / LUKS_UNITS.
luks_unlisted() { # <dir> -> the LUKS-family files in <dir> that are in neither list
  local d="$1" f b out=""
  for f in "$d"/workspaces-luks-*.sh "$d"/workspaces-luks-*.service "$d"/workspaces-luks-*.timer "$d"/luks-monitor.*; do
    [[ -e "$f" ]] || continue
    b="$(basename "$f")"
    case "$b" in workspaces-luks-harness.sh|*.test.sh) continue ;; esac
    case " $LUKS_SCRIPTS $LUKS_UNITS " in *" $b "*) : ;; *) out="$out $b" ;; esac
  done
  printf '%s' "$out"
}
unl="$(luks_unlisted "$DIR")"
if [[ -z "$unl" ]]; then ok "14c: every workspaces-luks-*/luks-monitor script and unit in the directory is in the baked lists"; else no "14c: LUKS-family file(s) in neither LUKS_SCRIPTS nor LUKS_UNITS (so never baked-checked):$unl"; fi
mkdir -p "$PAR_SCR/luksdir"; cp "$DIR"/workspaces-luks-reopen.sh "$PAR_SCR/luksdir/"; : > "$PAR_SCR/luksdir/workspaces-luks-newthing.sh"
if [[ "$(luks_unlisted "$PAR_SCR/luksdir")" == " workspaces-luks-newthing.sh" ]]; then ok "14c mutation: a tenth, unlisted LUKS file is seen (and the listed one is not)"; else no "14c mutation: an unlisted LUKS file SURVIVED the directory scan"; fi

# ── 15. Installed by the bootstrap (scripts 0755 /usr/local/bin — luks-monitor WITHOUT the suffix — units 0644) ──
# The install loops are PARSED (the `for f in <words>; do` list whose body installs at that mode), never
# grepped for a bare name: a name that only survives in a comment, or in the wrong loop, installs nothing.
install_words() { # <file> <body-ERE> -> one word per line of the matching `for f in ...; do` list
  BODY="$2" awk '
    /^[[:space:]]*#/ { next }
    /^for f in / { buf = ""; inl = 1 }
    inl { l = $0; sub(/[[:space:]]+#.*$/, "", l); sub(/\\$/, "", l); buf = buf " " l
          if (l ~ /; do[[:space:]]*$/) { inl = 0; if ((getline b) > 0 && b ~ ENVIRON["BODY"]) print buf } }
  ' "$1" | sed -e 's/^ *for f in //' -e 's/; do *$//' | tr -s ' ' '\n' | grep -v '^$' || true
}
SCRIPT_LOOP_BODY='install -D -m 0755 -o root -g root "\$SEED/\$f" "/usr/local/bin/\$f"'
UNIT_LOOP_BODY='install -D -m 0644 -o root -g root "\$SEED/\$f" "/etc/systemd/system/\$f"'
# install_missing <bootstrap-file> -> the LUKS names NOT installed by the right loop (empty == all installed)
install_missing() {
  local f="$1" sw uw n out=""
  sw="$(install_words "$f" "$SCRIPT_LOOP_BODY")"; uw="$(install_words "$f" "$UNIT_LOOP_BODY")"
  for n in workspaces-luks-provision.sh workspaces-luks-reopen.sh workspaces-luks-emit.sh; do
    printf '%s\n' "$sw" | grep -qxF -- "$n" || out="$out $n"
  done
  for n in $LUKS_UNITS; do printf '%s\n' "$uw" | grep -qxF -- "$n" || out="$out $n"; done
  printf '%s' "$out"
}
miss="$(install_missing "$BOOT")"
if [[ -z "$miss" ]]; then ok "15a/15c: every LUKS script and unit sits in the bootstrap's matching install loop (parsed word lists)"; else no "15a/15c: not installed by the right loop:$miss"; fi
if grep -qE 'install -D -m 0755 -o root -g root "\$SEED/luks-monitor\.sh" /usr/local/bin/luks-monitor$' "$BOOT"; then
  ok "15b: luks-monitor.sh installs as /usr/local/bin/luks-monitor (no suffix, as luks-monitor.service names it)"
else
  no "15b: luks-monitor.sh must install as /usr/local/bin/luks-monitor"
fi
# MUTATION rows for the parsed install check (each on a copy of the bootstrap; the harmless variant stays green).
boot_mut() { # <name> <sed-expr> <expect-missing-nonempty|empty>
  local name="$1" expr="$2" want="$3" m="$PAR_SCR/boot.mut" got
  sed -E "$expr" "$BOOT" > "$m"
  if cmp -s "$BOOT" "$m"; then no "15 mutation: $name — the mutation did not land"; return; fi
  got="$(install_missing "$m")"
  if [[ "$want" == nonempty && -n "$got" ]] || [[ "$want" == empty && -z "$got" ]]; then ok "15 mutation: $name -> ${got:-still green}"; else no "15 mutation: $name -> expected $want, got '${got:-}'"; fi
}
boot_mut "emit script dropped from the script loop, name kept in a trailing comment" 's/workspaces-luks-reopen\.sh workspaces-luks-emit\.sh; do/workspaces-luks-reopen.sh; do # workspaces-luks-emit.sh/' nonempty
boot_mut "luks-monitor.timer dropped from the unit loop, name kept in a trailing comment" 's/luks-monitor\.service luks-monitor\.timer; do/luks-monitor.service; do # luks-monitor.timer/' nonempty
boot_mut "units moved to the 0755 script mode" 's#(install -D -m )0644( -o root -g root "\$SEED/\$f" "/etc/systemd/system/\$f")#\10755\2#' nonempty
boot_mut "provisioner dropped from the script loop" 's/ workspaces-luks-provision\.sh//' nonempty
boot_mut "HARMLESS: two script names swapped inside the loop" 's/workspaces-luks-reopen\.sh workspaces-luks-emit\.sh; do/workspaces-luks-emit.sh workspaces-luks-reopen.sh; do/' empty

# NOTE (SIGPIPE): the checks below read the ~40 KB comment-stripped template with here-strings, never
# `printf "$CIC" | grep -q`: grep -q exits on its first match, printf is still writing, and pipefail turns the
# resulting SIGPIPE into a false "not found" (a flake that surfaces one run in a few).
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
if grep -qE 'poweroff -f' <<<"$CIC" && grep -E 'workspaces_luks_not_mounted' <<<"$CIC" | grep -q 'poweroff -f'; then ok "16c: a failed gate powers the host off (fail closed), it does not fall through"; else no "16c: the workspaces_luks_not_mounted gate must poweroff -f"; fi
# #9377: the web-class boot env file names the WEB-CLASS config. The pin is END-ANCHORED on the name (a bare prefix
# `prd_workspaces_luks` would also match `prd_workspaces_luks_web` and so could not tell the two apart) and 17d keeps
# pinning web-1's SSH installer to the un-suffixed name.
if grep -q "WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s" <<<"$CIC" && grep -qE 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web\\n' <<<"$CIC" && ! grep -qE 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks(\\n|[^_A-Za-z0-9]|$)' <<<"$CIC"; then
  ok "16d: cloud-init writes the same two env-file keys the SSH installer writes, with the web-class config name"
else
  no "16d: cloud-init must write WORKSPACES_LUKS_DEV (by-id) and WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web (never web-1's prd_workspaces_luks)"
fi
if grep -qF "workspaces_luks_fresh_boot_token" <<<"$CIC" && grep -qF 'LUKS_MONITOR_PROFILE=standby' <<<"$CIC" && grep -qF 'install -m 600 -o root -g root /dev/null /etc/default/luks-monitor' <<<"$CIC"; then
  ok "16e: /etc/default/luks-monitor is created 0600, carries the fresh-host token and the standby profile"
else
  no "16e: cloud-init must create /etc/default/luks-monitor 0600 with the fresh-host token + LUKS_MONITOR_PROFILE=standby"
fi
if ! grep -qE "fstab|mount /mnt/data|mount /dev/disk/by-id" <<<"$CIC"; then ok "16f: cloud-init no longer appends fstab or mounts /mnt/data itself (the provisioner owns both)"; else no "16f: cloud-init still writes fstab / mounts /mnt/data directly"; fi
if grep -qF 'workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot_web.key' "$SRV"; then ok "16g: server.tf passes the web-class fresh-host token into the user_data map"; else no "16g: server.tf must pass workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot_web.key"; fi

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

# The daily-probe family is delivered to web-1 from the SAME repo files (provisioner source = ... blocks),
# so what 14/15 bake is what the SSH installer ships.
luks_src_ok() { # <tf-file> <name>
  grep -qE "^[[:space:]]*source[[:space:]]*=[[:space:]]*\"\\\$\{path\.module\}/$2\"" "$1"
}
for f in luks-monitor.sh workspaces-luks-emit.sh luks-monitor.service luks-monitor.timer; do
  if luks_src_ok "$LUKSTF" "$f"; then ok "17f: the SSH installer sources $f from the same repo file the image bakes"; else no "17f: SSH installer does not source $f from the repo file"; fi
done
sed -E 's#(source[[:space:]]*=[[:space:]]*"\$\{path\.module\}/)luks-monitor\.timer"#\1luks-monitor-other.timer"#' "$LUKSTF" > "$PAR_SCR/luks.tf.mut"
if ! cmp -s "$LUKSTF" "$PAR_SCR/luks.tf.mut" && ! luks_src_ok "$PAR_SCR/luks.tf.mut" luks-monitor.timer; then ok "17f mutation: a re-pointed SSH-installer source is caught"; else no "17f mutation: a re-pointed SSH-installer source SURVIVED (or did not land)"; fi

# ── 18. Guard 1 static scope: no destructive verb outside the provisioner's chokepoints ──
# Only workspaces-luks-provision.sh may format or wipe; the reopen script's `cryptsetup isLuks` is the
# read-only header refusal (the opposite polarity) and is the one allowed isLuks outside the provisioner.
DESTRUCT_ERE='luksFormat|mkfs|mke2fs|wipefs|sgdisk|blkdiscard'
destruct_hits() { # <file> [allow-isLuks] -> count of comment-stripped code lines naming a destructive verb
  local ere="$DESTRUCT_ERE"; [[ "${2:-}" == allow-isLuks ]] || ere="$ere|isLuks"
  awk '$0 !~ /^[[:space:]]*#/' "$1" | grep -cE "$ere" || true
}
for f in "$CI" "$BOOT" "$DIR/workspaces-luks-emit.sh" "$DIR/luks-monitor.sh"; do
  if [[ "$(destruct_hits "$f")" == 0 ]]; then ok "18: $(basename "$f") names no isLuks/luksFormat/mkfs/mke2fs/wipefs/sgdisk/blkdiscard"; else no "18: $(basename "$f") names a destructive verb (only the provisioner may; reopen's isLuks is read-only)"; fi
done
if [[ "$(destruct_hits "$DIR/workspaces-luks-reopen.sh" allow-isLuks)" == 0 ]]; then ok "18: workspaces-luks-reopen.sh names no destructive verb (its isLuks is the read-only refusal)"; else no "18: workspaces-luks-reopen.sh names a destructive verb"; fi
if grep -qF 'by-label/workspaces_luks' "$BOOT"; then no "18: the bootstrap still writes the foreign by-label crypttab line (it would collide with the canonical one)"; else ok "18: the bootstrap no longer writes a foreign crypttab line"; fi
# MUTATION rows: the spellings a deny-list of exact phrases missed (options between the verb and its operand).
destr_mut() { # <name> <appended-line> <victim-file>
  local m="$PAR_SCR/destr.mut"
  cp "$3" "$m"; printf '%s\n' "$2" >> "$m"
  if [[ "$(destruct_hits "$m")" -ge 1 ]]; then ok "18 mutation: $1 is seen"; else no "18 mutation: $1 SURVIVED the static scan"; fi
}
destr_mut "cryptsetup --batch-mode luksFormat" '  - cryptsetup --batch-mode luksFormat /dev/x' "$CI"
destr_mut "mke2fs -t ext4" '  - mke2fs -t ext4 /dev/x' "$CI"
destr_mut "wipefs -a" 'wipefs -a /dev/x' "$BOOT"
destr_mut "sgdisk --zap-all" 'sgdisk --zap-all /dev/x' "$DIR/luks-monitor.sh"
destr_mut "blkdiscard" 'blkdiscard /dev/x' "$DIR/workspaces-luks-emit.sh"

# ── 19. The raw-at-birth volume: no `format`, and `ignore_changes = [format]` beside `prevent_destroy` ──
VOLBLK="$(awk '/^resource "hcloud_volume" "workspaces" \{/{f=1} f{print} f&&/^\}/{exit}' "$SRV" | awk '$0 !~ /^[[:space:]]*#/')"
if [[ -n "$VOLBLK" ]] && ! grep -qE '^[[:space:]]*format[[:space:]]*=' <<<"$VOLBLK"; then ok "19a: hcloud_volume.workspaces declares no format (a volume is born raw)"; else no "19a: hcloud_volume.workspaces must not declare format"; fi
if grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[format\]' <<<"$VOLBLK" && grep -qE '^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true' <<<"$VOLBLK"; then ok "19b: ignore_changes = [format] sits beside prevent_destroy = true (a no-op merge for the live volumes)"; else no "19b: hcloud_volume.workspaces must carry ignore_changes = [format] AND prevent_destroy = true (neither half may be dropped alone)"; fi

# ── 20. THE HARD GATE, EXECUTED. cloud-init's `mountpoint ... || { soleur-boot-emit ...; poweroff -f; }` item is
# the last line against "plaintext /mnt/data on the root disk"; 16a-16c pin only its position and its tail,
# which a flipped `&&`, an inverted compare or a wrong device all preserve. So the item (and the boot-env
# writer + chmod, and the bare provisioner call) is EXTRACTED from the template and RUN under stubs.
ci_item() { # <file> <fixed-substring> -> the runcmd list item(s) containing it, without the "  - " marker
  grep -F -- "$2" "$1" | grep -E '^[[:space:]]+- ' | sed -E 's/^[[:space:]]+- //' || true
}
gate_battery() { # <cloud-init-file> -> the number of FAILED checks (0 == the gate behaves in all five cases)
  local f="$1" gate prov_line prov_cmd envw chm bad=0 n
  local sb="$PAR_SCR/gate"
  rm -rf "${sb:?}"; mkdir -p "$sb/bin" "$sb/etc-default"
  gate="$(ci_item "$f" 'workspaces_luks_not_mounted fatal')"
  [[ "$(printf '%s\n' "$gate" | grep -c .)" == 1 ]] || { echo 99; return; }
  # The provisioner is invoked BARE: a trailing `|| true` would hide its failure from any errexit regime.
  prov_line="$(grep -E '^[[:space:]]+- /usr/local/bin/workspaces-luks-provision\.sh([[:space:]]|$)' "$f" || true)"
  [[ "$prov_line" == '  - /usr/local/bin/workspaces-luks-provision.sh' ]] || bad=$((bad + 1))
  prov_cmd="$sb/bin/workspaces-luks-provision.sh"
  printf '#!/bin/sh\nexit "${GB_PROV_RC:-0}"\n' > "$prov_cmd"
  cat > "$sb/bin/mountpoint" <<'STUB'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = "-q" ] && [ "$2" = "/mnt/data" ] || { echo "REFUSED mountpoint $*" >> "$GB_LOG"; exit 64; }
[ "${GB_MP:-1}" = 0 ]
STUB
  cat > "$sb/bin/findmnt" <<'STUB'
#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = "-no" ] && [ "$2" = "SOURCE" ] && [ "$3" = "/mnt/data" ] || { echo "REFUSED findmnt $*" >> "$GB_LOG"; exit 64; }
printf '%s\n' "${GB_SRC:-}"
STUB
  cat > "$sb/bin/poweroff" <<'STUB'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = "-f" ] || { echo "REFUSED poweroff $*" >> "$GB_LOG"; exit 64; }
echo POWEROFF >> "$GB_LOG"
STUB
  cat > "$sb/bin/soleur-boot-emit" <<'STUB'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = "workspaces_luks_not_mounted" ] && [ "$2" = "fatal" ] || { echo "REFUSED soleur-boot-emit $*" >> "$GB_LOG"; exit 64; }
echo EMIT >> "$GB_LOG"
STUB
  chmod +x "$sb/bin/"*
  # case <name> <GB_MP 0=mountpoint> <GB_SRC> <GB_PROV_RC> <expect: pass|poweroff>
  gate_case() {
    local want="$5" log="$sb/log" got
    : > "$log"
    PATH="$sb/bin:$PATH" GB_LOG="$log" GB_MP="$2" GB_SRC="$3" GB_PROV_RC="$4" \
      sh -c "$(printf '%s' "$prov_line" | sed -E 's#^[[:space:]]+- ##; s#^/usr/local/bin/#'"$sb"'/bin/#')
$gate" >/dev/null 2>&1
    got="$(paste -sd' ' "$log")"
    if [[ "$want" == pass ]]; then [[ -z "$got" ]]; else [[ "$got" == "EMIT POWEROFF" ]]; fi
  }
  gate_case mapper-mounted 0 /dev/mapper/workspaces 0 pass || bad=$((bad + 1))
  gate_case plaintext-mounted 0 /dev/sdb 0 poweroff || bad=$((bad + 1))
  gate_case not-a-mountpoint-but-findmnt-says-mapper 1 /dev/mapper/workspaces 0 poweroff || bad=$((bad + 1))
  gate_case not-a-mountpoint 1 '' 0 poweroff || bad=$((bad + 1))
  gate_case provisioner-nonzero 1 '' 14 poweroff || bad=$((bad + 1))
  # The boot-env file is written 0600 BEFORE the provisioner runs (its _secure_file refuses 0644 with rc 10).
  envw="$(ci_item "$f" 'WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s')"
  chm="$(ci_item "$f" 'chmod 600 /etc/default/workspaces-luks-boot')"
  [[ -n "$envw" ]] || bad=$((bad + 1))
  ( umask 022
    sh -c "$(printf '%s\n%s\n' "$envw" "$chm" | sed -e "s#/etc/default/#$sb/etc-default/#g" -e "s#\\\${workspaces_volume_id}#vol123#g")" >/dev/null 2>&1 )
  n="$sb/etc-default/workspaces-luks-boot"
  [[ "$(stat -c %a "$n" 2>/dev/null)" == 600 ]] || bad=$((bad + 1))
  grep -qxF 'WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_vol123' "$n" 2>/dev/null || bad=$((bad + 1))
  grep -qxF 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web' "$n" 2>/dev/null || bad=$((bad + 1))
  echo "$bad"
}
g0="$(gate_battery "$CI")"
if [[ "$g0" == 0 ]]; then ok "20a: the gate, the boot-env writer and the bare provisioner call behave in all five executed cases"; else no "20a: the executed gate battery failed $g0 check(s) on the real cloud-init.yml"; fi
gate_mut() { # <name> <sed-expr> <expect: red|green>
  local name="$1" expr="$2" want="$3" m="$PAR_SCR/ci.mut" got
  sed -E "$expr" "$CI" > "$m"
  if cmp -s "$CI" "$m"; then no "20 mutation: $name — the mutation did not land"; return; fi
  got="$(gate_battery "$m")"
  if [[ "$want" == red && "$got" != 0 ]] || [[ "$want" == green && "$got" == 0 ]]; then ok "20 mutation: $name -> $want ($got failed check(s))"; else no "20 mutation: $name -> expected $want, got $got failed check(s)"; fi
}
GATE_LN='/workspaces_luks_not_mounted fatal/'
gate_mut "&& flipped to || (a plaintext mount now passes)" "$GATE_LN s/ && \\[ / || [ /" red
gate_mut "compare inverted (!=)" "$GATE_LN s# = /dev/mapper/workspaces \\]# != /dev/mapper/workspaces ]#" red
gate_mut "compare against the wrong device" "$GATE_LN s# = /dev/mapper/workspaces \\]# = /dev/sdb ]#" red
gate_mut "mountpoint half dropped" "$GATE_LN s#mountpoint -q /mnt/data && ##" red
gate_mut "poweroff loses -f" "$GATE_LN s#poweroff -f#poweroff#" red
gate_mut "the emit loses its stage" "$GATE_LN s#soleur-boot-emit workspaces_luks_not_mounted fatal; ##" red
gate_mut "the whole gate item removed" "$GATE_LN d" red
gate_mut "|| true on the provisioner call" 's#^([[:space:]]+- /usr/local/bin/workspaces-luks-provision\.sh)$#\1 || true#' red
gate_mut "chmod 600 of the boot env file removed" '/chmod 600 \/etc\/default\/workspaces-luks-boot/d' red
# #9377 / Guard 3 row 1: a revert of the boot-env printf to web-1's config name must flip the executed battery red.
gate_mut "the boot-env printf reverts to web-1's prd_workspaces_luks (Guard 3)" 's#(WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks)_web#\1#' red
gate_mut "HARMLESS: doubled spaces inside the gate item" "$GATE_LN s#mountpoint -q /mnt/data#mountpoint  -q  /mnt/data#" green

# ── 21. Cross-artifact literals that every unit test overrides (#6931): the provisioner's journald tag must be
# in the exact-match Vector Source 4 allowlist, and the stage-detail directory the provisioner writes must equal
# the one soleur-boot-emit reads (a drifted default ships every Sentry page with an empty detail).
VECTOR="$DIR/vector.toml"
PROV_TAG="$(sed -n 's/^[[:space:]]*logger -t \([a-z0-9-]*\) .*/\1/p' "$PROV" | sed -n '1p')"
vec_pin_bad() { # <vector.toml> <provisioner> -> 0 when the logger tag is in the allowlist exactly once
  local tag block n
  tag="$(sed -n 's/^[[:space:]]*logger -t \([a-z0-9-]*\) .*/\1/p' "$2" | sed -n '1p')"
  [[ -n "$tag" ]] || { echo 1; return; }
  block="$(awk '/^\[sources\.host_scripts_journald\]/{f=1} f&&/^include_matches\.SYSLOG_IDENTIFIER/{l=1} l{print} l&&/^\]/{exit}' "$1")"
  n="$(printf '%s\n' "$block" | grep -cE "^[[:space:]]*\"$tag\",[[:space:]]*\$" || true)"
  [[ "$n" == 1 ]] && echo 0 || echo 1
}
ddir_bad() { # <provisioner> <bootstrap> -> 0 when the provisioner's detail-dir default equals every emitter default
  local p e
  p="$(sed -n 's|^DETAIL_DIR="\${SOLEUR_STAGE_DETAIL_DIR:-\${ROOT}\(/[^}]*\)}"$|\1|p' "$1" | sed -n '1p')"
  e="$(sed -n 's|.*DDIR="\${SOLEUR_STAGE_DETAIL_DIR:-\(/[^}]*\)}".*|\1|p' "$2" | sort -u)"
  [[ -n "$p" && "$p" == "$e" ]] && echo 0 || echo 1
}
if [[ "$(vec_pin_bad "$VECTOR" "$PROV")" == 0 ]]; then ok "21a: the provisioner's logger tag is in vector.toml Source 4 exactly once"; else no "21a: the provisioner's logger -t tag ('${PROV_TAG:-?}') is not in the vector.toml host_scripts_journald allowlist exactly once (its SOLEUR_WORKSPACES_LUKS_PROVISION row never reaches Better Stack; vector.toml is an inngest-image carrier, so reuse an allowlisted tag rather than add one)"; fi
if [[ "$(ddir_bad "$PROV" "$BOOT")" == 0 ]]; then ok "21b: the provisioner and soleur-boot-emit share one stage-detail directory default"; else no "21b: the stage-detail directory default DRIFTED between the provisioner and the emitters"; fi
mut_vec() { # <name> <file-to-mutate: vector|prov> <sed-expr>
  local vt="$VECTOR" pv="$PROV" m="$PAR_SCR/vec.mut"
  if [[ "$2" == vector ]]; then sed -E "$3" "$VECTOR" > "$m"; vt="$m"; cmp -s "$VECTOR" "$m" && { no "21 mutation: $1 — did not land"; return; }
  else sed -E "$3" "$PROV" > "$m"; pv="$m"; cmp -s "$PROV" "$m" && { no "21 mutation: $1 — did not land"; return; }; fi
  if [[ "$(vec_pin_bad "$vt" "$pv")" == 1 ]]; then ok "21 mutation: $1 is caught"; else no "21 mutation: $1 SURVIVED"; fi
}
mut_vec "the tag dropped from the Vector allowlist" vector "/^  \"$PROV_TAG\",\$/d"
mut_vec "the tag listed twice" vector "s/^  \"$PROV_TAG\",\$/&\n  \"$PROV_TAG\",/"
mut_vec "the provisioner's logger tag renamed" prov "s/logger -t $PROV_TAG /logger -t ${PROV_TAG}-renamed /"
mut_vec "the tag moved into a comment" vector "s/^  \"$PROV_TAG\",\$/  # \"$PROV_TAG\",/"
mut_ddir() { # <name> <which: prov|boot> <sed-expr>
  local m="$PAR_SCR/ddir.mut" pv="$PROV" bt="$BOOT"
  if [[ "$2" == prov ]]; then sed -E "$3" "$PROV" > "$m"; pv="$m"; cmp -s "$PROV" "$m" && { no "21 mutation: $1 — did not land"; return; }
  else sed -E "$3" "$BOOT" > "$m"; bt="$m"; cmp -s "$BOOT" "$m" && { no "21 mutation: $1 — did not land"; return; }; fi
  if [[ "$(ddir_bad "$pv" "$bt")" == 1 ]]; then ok "21 mutation: $1 is caught"; else no "21 mutation: $1 SURVIVED"; fi
}
mut_ddir "the provisioner's detail dir default drifted" prov 's#(DETAIL_DIR=.*)/run/soleur-stage-detail\.d#\1/run/soleur-stage-detail2.d#'
mut_ddir "ONE emitter's detail dir default drifted" boot '0,/DDIR="\$\{SOLEUR_STAGE_DETAIL_DIR:-\/run\/soleur-stage-detail\.d\}"/s##DDIR="${SOLEUR_STAGE_DETAIL_DIR:-/run/soleur-stage-detail2.d}"#'

# ── Anti-vacuity: an exact assertion count (deleting sections 14-21 leaves a lower one) ──
EXPECTED_ASSERTIONS=166
if [[ "$((pass + fail))" -ne "$EXPECTED_ASSERTIONS" ]]; then no "floor: ran $((pass + fail)) assertions, expected exactly $EXPECTED_ASSERTIONS (a section was deleted or added without moving the floor)"; fi

echo "=== fresh-boot-parity: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
