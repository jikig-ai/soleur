#!/bin/bash
# rung-2 SEED (#5274, ADR-239 amendment 2026-09-24). REHEARSAL-ONLY: rendered by
# rung2-rehearsal/rehearsal.tf when rehearsal_phase = "seed", and referenced from nowhere in
# modules/git-data-userdata/ or git-data.tf (git-data-rung2-rehearsal.test.sh pins both).
#
# WHAT IT REPRODUCES. The 2026-09-24 production state: a host destroyed while the retained
# plaintext volume was mounted read-write, so its ext4 journal is dirty. It mounts the rehearsal
# plaintext volume rw (no noload), writes, flushes, and powers the host off WITHOUT unmounting.
# The payload phase then replaces this host and boots the real payload against that volume.
#
# IT ASSERTS NOTHING ABOUT needs_recovery: that flag is set whenever an ext4 is mounted rw, so a
# seed-side check proves nothing. The proof is the payload's own boot_complete reading
# plaintext_journal=dirty, which the capture refuses PASS without (Guard 2).
#
# It touches ONLY the plaintext volume (never the LUKS volume). One fail-soft Better Stack line
# per step (stage=seed_<step>, host <rehearsal-host>-seed) makes a stalled seed diagnosable
# without SSH. Any failed step leaves the host RUNNING, so the workflow's bounded off-poll times
# out and the run FAILs rather than booting the payload against an undirtied volume.
#
# Rendered by templatefile(): shell braces are written $${...}; the ingest token is passed on
# curl's stdin (-K -), never argv, as the payload's own emitter does. No set -x, no curl -v/-k.
set -uo pipefail

DEV='/dev/disk/by-id/scsi-0HC_Volume_${volume_id}'
MNT=/mnt/rung2-seed
# The two rendered destinations are PINNED before any credentialed call: the token may reach only
# git-data's own Better Stack source, under a rehearsal seed host label. A render that named
# anything else ships the token nowhere and fails the seed (the off-poll then FAILs the run).
BS_URL='${betterstack_ingest_url}'
SEED_HOST='${host_name}'
readonly BS_URL_PINNED="https://s2734275.eu-central-1a.betterstackdata.com/"
if [ "$BS_URL" != "$BS_URL_PINNED" ] || [[ ! "$SEED_HOST" =~ ^soleur-git-data-rehearsal-[0-9]+-seed$ ]]; then
  echo "rung-2 seed: refusing — the rendered ingest URL or host label is not the pinned one" >&2
  exit 1
fi

emit() {
  printf 'header = "Authorization: Bearer %s"\n' '${betterstack_logs_token}' \
    | curl --disable --noproxy '*' --connect-timeout 5 -m 10 -sf -X POST "$BS_URL" \
        -K - \
        -H 'Content-Type: application/json' \
        --data-raw "{\"message\":\"rung-2 seed $1\",\"stage\":\"seed_$1\",\"level\":\"$2\",\"host_name\":\"$SEED_HOST\",\"detail\":\"$3\"}" \
        >/dev/null 2>&1 || true
}

emit start info "seed boot started"

for _i in $(seq 1 60); do
  [ -b "$DEV" ] && break
  sleep 5
done
if [ ! -b "$DEV" ]; then emit wait fatal "the plaintext volume never appeared"; exit 1; fi
emit wait info "the plaintext volume is attached"

mkdir -p "$MNT" || { emit mount fatal "mkdir failed"; exit 1; }
if ! mount -o rw "$DEV" "$MNT"; then emit mount fatal "rw mount failed"; exit 1; fi
emit mount info "mounted rw"

if ! { printf 'rung-2 seed %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MNT/rung2-seed-marker" \
       && mkdir -p "$MNT/repositories" \
       && mkdir "$MNT/repositories/seed-probe.git" \
       && rmdir "$MNT/repositories/seed-probe.git"; }; then
  emit write fatal "the seed writes failed"
  exit 1
fi
emit write info "marker written, repositories/ probe created and removed"

if ! sync -f "$MNT/rung2-seed-marker"; then emit sync fatal "sync -f failed"; exit 1; fi
emit poweroff info "powering off WITHOUT unmounting"

# Immediate power-off, no unmount, no remount-ro: the predecessor's state. Writing to
# /proc/sysrq-trigger as root works regardless of kernel.sysrq's mask.
echo o > /proc/sysrq-trigger
sleep 60
emit poweroff fatal "still running 60s after sysrq o"
exit 1
