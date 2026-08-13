#!/usr/bin/env bash
# Read-only preflight for the registry-host-replace dispatcher (#7555).
#
# ── THIS IS DELIBERATELY NOT scripts/registry-pull-path-health.sh ───────────────────────────
# That file is the D10 PRE-DESTROY authorization gate for `registry-luks-recut`. Do not "simplify"
# this by calling it. Three independent grounds, each measured rather than argued:
#
#   1. D10's A1/A2 authorize a destroy on "the store can be re-materialised from GHCR". That is
#      earned for a RECUT, where GHCR is the restore source. `registry-host-replace` PRESERVES the
#      volume (`store_destroyed==0`, enforced by registry_host_replace_gate in
#      apply-web-platform-infra.yml), so the restore source is the volume, not GHCR. Wiring A1/A2
#      would abort the deadline fix on a GHCR condition the replace does not depend on.
#   2. D10's A4 aborts on a measured-dead CF Access push credential. But `/etc/zot/htpasswd` is
#      baked at boot from Doppler by cloud-init-registry.yml, so a pre-replace credential
#      rejection means the running host's bake has diverged — and the remedy for that divergence
#      IS a host replace. It would block the recovery on the condition the recovery cures.
#   3. D10 renders its verdict by EXECUTING a restore rehearsal, i.e. by pushing images. A
#      precondition that mutates the registry it is about to replace is not a health check.
#
# The plan for #7555 said "reuse registry-pull-path-health.sh". The authority that plan CITES for
# the hazard — scheduled-zot-restart-loop.yml's remediation block — prescribes a read-only
# betterstack query instead, and does not mention that script. This file implements the cited
# mechanism. Decision + the three grounds: ADR-189 §"Why the replace pre-check is not the D10
# recut gate".
#
# ── WHAT IT CHECKS ─────────────────────────────────────────────────────────────────────────
#   P0  credentials/query readable ......... GATING, fail-closed
#   P1  no sustained local-cache pulls ..... GATING   (the #6400 hazard)
#   P2  ghcr-fallback event count .......... ADVISORY ONLY — MUST NOT GATE (see below)
#   P3  no in-progress release run ......... GATING
#   P4  live zot serving probe ............. DELIBERATELY ABSENT (see below)
#
# Output: a single `verdict=` line on stdout. Exit 0 = clear to dispatch, non-zero = do not.
#
# Usage: scripts/registry-replace-preflight.sh
# Env seams (tests only, one per external dependency):
#   REGISTRY_PREFLIGHT_QUERY_CMD   REGISTRY_PREFLIGHT_RUNS_CMD

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY_CMD="${REGISTRY_PREFLIGHT_QUERY_CMD:-${ROOT}/scripts/betterstack-query.sh}"
RUNS_CMD="${REGISTRY_PREFLIGHT_RUNS_CMD:-gh}"
WINDOW="${REGISTRY_PREFLIGHT_WINDOW:-24h}"

abort() { # $1 = predicate, rest = message
  local p="$1"; shift
  echo "::error::registry-replace-preflight: ${p} ABORT — $*" >&2
  echo "verdict=REFUSED predicate=${p}"
  exit 1
}

# ── P0 — the read itself must be trustworthy, or nothing below means anything. ──────────────
# FAIL-CLOSED. This is Phase 1 defect (b) one layer up: a query that could not run must never be
# read as "no events found". betterstack-query.sh exits 3 when the credentials are absent.
p0_err="$(mktemp)"
trap 'rm -f "$p0_err"' EXIT INT TERM

probe() { # $1 = --grep value; prints rows, sets PROBE_RC
  local marker="$1"
  PROBE_OUT="$("$QUERY_CMD" --since "$WINDOW" --grep "$marker" --limit 200 2>"$p0_err")"
  PROBE_RC=$?
}

probe 'registry=local-cache'
if (( PROBE_RC != 0 )); then
  if [[ "$PROBE_RC" == "3" ]]; then
    abort P0 "betterstack-query.sh exited 3 — BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} unset or EMPTY. A failed read is not a clean reading, so this refuses rather than dispatching a production host replace on an unmeasured pull path."
  fi
  abort P0 "betterstack-query.sh exited ${PROBE_RC}: $(head -c 300 "$p0_err"). Not evidence about the pull path."
fi

# ── P1 — GATING. The #6400 hazard, stated in the mechanism that actually detects it. ─────────
# `_try_local_cache_reload` (apps/web-platform/infra/ci-deploy.sh) fires ONLY when BOTH registries
# have already failed. A hit therefore means the fleet is serving off its last tier — and darking
# zot for a replace removes the last source it has. This is #6400 exactly: a degraded fallback is
# what turned a registry outage into a total deploy outage.
lc_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=local-cache' || true; })"
if [[ "${lc_hits:-0}" -gt 0 ]]; then
  abort P1 "${lc_hits} local-cache pull event(s) in the last ${WINDOW}. The fleet is already falling back to its LAST tier, so replacing the registry host now would remove the only remaining pull source. Resolve the pull path first, then re-dispatch."
fi

# ── P2 — ADVISORY ONLY. THIS MUST NEVER BECOME A GATE. ─────────────────────────────────────
# `registry=ghcr-fallback` is emitted only INSIDE the success branch of a GHCR pull
# (`if _ghcr_pull_or_recover "$perr"` in ci-deploy.sh). Per #7071 the host->GHCR read PAT is
# revoked (401) and the minter is disabled (403 DENIED), so that branch CANNOT succeed and the
# event CANNOT fire. A gate keyed on this operand reads CLEAN whether the fleet is healthy or the
# fallback is destroyed — it is a dark operand, which is the exact defect class the D10 rewrite
# existed to remove. ZERO HERE IS NOT EVIDENCE OF ANYTHING. Reported for the record only.
probe 'registry=ghcr-fallback'
if (( PROBE_RC == 0 )); then
  gf_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=ghcr-fallback' || true; })"
else
  gf_hits="unreadable"
fi

# ── P3 — GATING. Do not replace the host out from under an in-flight push. ──────────────────
# Replacing mid-push strands a partially-uploaded manifest on the PRESERVED volume. Directly
# on-point for #7555, whose motivating failure mode is large-layer pushes.
runs_json="$("$RUNS_CMD" run list --workflow=web-platform-release.yml --status=in_progress --limit 20 --json databaseId 2>/dev/null)"
runs_rc=$?
if (( runs_rc != 0 )); then
  abort P3 "could not list in-progress release runs (gh exited ${runs_rc}). Refusing rather than replacing the registry host with an unknown number of pushes in flight."
fi
in_progress="$(printf '%s' "$runs_json" | { grep -o 'databaseId' || true; } | grep -c . || true)"
if [[ "${in_progress:-0}" -gt 0 ]]; then
  abort P3 "${in_progress} release run(s) in progress. A replace mid-push strands a partial manifest on the preserved volume. Wait for them to finish, then re-dispatch."
fi

# ── P4 — DELIBERATELY ABSENT: no live zot serving probe. ────────────────────────────────────
# Do not add one. On this transport a bad handshake does not distinguish an edge refusal from an
# origin that is down or restarting — measured in #7242/ADR-166, where CF Access admitted every
# request while zot was crash-looping. It is worse here than for the recut: #7555's MOTIVATING
# SYMPTOM is a degraded zot, so a serving predicate would refuse precisely when the fix is most
# needed. The same reasoning removed D10's A5 (ADR-169 ground 2).

echo "verdict=CLEAR local_cache_hits=0 ghcr_fallback_hits=${gf_hits} in_progress_releases=0 window=${WINDOW}"
echo "NOTE: ghcr_fallback_hits is ADVISORY. Its emitter is unreachable since #7071, so a zero says nothing about fallback health."
exit 0
