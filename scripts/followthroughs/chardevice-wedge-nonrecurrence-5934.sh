#!/usr/bin/env bash
# Follow-through soak for #5934 (post-deploy non-recurrence of the char-device
# .git/config.lock worktree-creation wedge; AC10 of the durable-fix plan).
#
# WHAT IT PROVES. PR #5934 ships the durable substrate remediation: a privileged,
# host-side char-device sweep (git-lock-chardevice-sweep.sh, ADR-081) that clears
# any residual CHARACTER-DEVICE config.lock on /mnt/data/workspaces at each deploy,
# BEFORE the container's agents start. The sweep emits host-side markers routed to
# Better Stack (via journald → vector.toml host_scripts_journald):
#   - SOLEUR_CHARDEV_SWEEP_DONE   — one per run (liveness: the sweep executed)
#   - SOLEUR_CHARDEV_SWEEP_FAILED — a detected char-device node it could NOT clear
#     (umount/rm failed → the wedge will persist into a live session)
#
# SOUND non-recurrence signal = for the soak window: the sweep ran at least once
# (>=1 DONE) AND zero FAILED. Zero FAILED across a live window means every
# char-device residual that appeared was cleared at the substrate before any
# session hit it — the empirical test of the plan's "#5912 becomes dead-code
# insurance" claim.
#
# WHY Better Stack, not Sentry (corrected after review): the earlier draft queried
# Sentry for the IN-SANDBOX `SOLEUR_GIT_LOCK_UNREMOVABLE type=chardevice` line — but
# that line is emitted only to blind agent-sandbox stdout and is NOT mirrored to any
# queryable sink (this host's vector.toml has no Sentry sink at all), so that query
# could never return >0 and the gate would PASS vacuously and auto-close #5934 while
# blind. This version queries the HOST-side markers that ARE wired (Better Stack via
# scripts/betterstack-query.sh). Wiring the in-sandbox line to Sentry is separately
# tracked as an observability follow-up; until then the host FAILED marker is the
# sound, wired regression signal.
#
# FAIL-SAFE: any query/auth/config failure → TRANSIENT (exit 2), never PASS. If the
# BETTERSTACK_QUERY_* secrets are not (yet) wired into the sweeper, the probe stays
# TRANSIENT and #5934 stays open — it can NEVER false-close.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (sweep ran >=1x AND zero FAILED in window; sweeper closes #5934)
#   1 = FAIL       (>=1 SOLEUR_CHARDEV_SWEEP_FAILED; the wedge recurred post-fix)
#   2 = TRANSIENT  (query unreachable/unauth, OR no DONE marker yet — inconclusive)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (wired in
#   scheduled-followthrough-sweeper.yml). Optional: CHARDEVICE_SOAK_WINDOW (Nh/Nm/Nd,
#   default 7d).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BQ="$SCRIPT_DIR/../betterstack-query.sh"

WINDOW="${CHARDEVICE_SOAK_WINDOW:-7d}"
if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  echo "TRANSIENT: invalid CHARDEVICE_SOAK_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2
  exit 2
fi

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# count_marker <substr> — echo the number of Better Stack rows matching <substr> in
# the window; return non-zero (caller → TRANSIENT) on any query failure.
count_marker() {
  local grep_term="$1" out rc
  out="$("$BQ" --since "$WINDOW" --grep "$grep_term" --limit 1000 2>/dev/null)"; rc=$?
  [[ "$rc" -ne 0 ]] && return 1
  # JSONEachRow: one object per matching row. Empty output ⇒ 0.
  if [[ -z "$out" ]]; then echo 0; else printf '%s\n' "$out" | grep -c . ; fi
  return 0
}

done_count="$(count_marker SOLEUR_CHARDEV_SWEEP_DONE)" || {
  echo "TRANSIENT: Better Stack query failed (liveness/DONE) — auth/config/network" >&2; exit 2; }
failed_count="$(count_marker SOLEUR_CHARDEV_SWEEP_FAILED)" || {
  echo "TRANSIENT: Better Stack query failed (FAILED marker) — auth/config/network" >&2; exit 2; }

if [[ "$done_count" -eq 0 ]]; then
  echo "TRANSIENT: no SOLEUR_CHARDEV_SWEEP_DONE marker in ${WINDOW} — sweep not observed running yet (no deploys in window, or delivery not live); inconclusive" >&2
  exit 2
fi

if [[ "$failed_count" -eq 0 ]]; then
  echo "PASS: sweep ran ${done_count}x, zero SOLEUR_CHARDEV_SWEEP_FAILED in ${WINDOW} (durable char-device remediation #5934 holds)"
  exit 0
fi

echo "FAIL: ${failed_count} SOLEUR_CHARDEV_SWEEP_FAILED event(s) in ${WINDOW} — a char-device config.lock residual could not be cleared; the wedge recurred post-fix"
exit 1
