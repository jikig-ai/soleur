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
# mechanism. Decision + the three grounds: ADR-190 §"Why the replace pre-check is not the D10
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

# THE TEST SEAMS ARE REFUSED ON THE PRODUCTION PATH (#7555 review). "tests only" was a comment,
# not a mechanism: `REGISTRY_PREFLIGHT_QUERY_CMD=/bin/true REGISTRY_PREFLIGHT_RUNS_CMD=/bin/true`
# makes every predicate pass and prints a verdict line BYTE-IDENTICAL to a real clean reading —
# on the sole gate in front of an irreversible production host replace. The sibling D10 gate
# already carries this refusal; it was the one thing worth copying from it.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  for _seam in REGISTRY_PREFLIGHT_QUERY_CMD REGISTRY_PREFLIGHT_RUNS_CMD REGISTRY_PREFLIGHT_WINDOW; do
    if [[ -n "${!_seam:-}" ]]; then
      echo "::error::registry-replace-preflight: ${_seam} is set inside GitHub Actions. A seam set on the production path can manufacture a CLEAR verdict. Refusing." >&2
      echo "verdict=REFUSED predicate=SEAM"
      exit 1
    fi
  done
fi

abort() { # $1 = predicate, rest = message
  local p="$1"; shift
  # Strip CR/LF and non-printables: `::error::` is LINE-ORIENTED, so an embedded newline in
  # captured vendor stderr terminates the annotation and emits the remainder as raw log lines —
  # including a forged `::add-mask::`. This repo flags that exact class in reusable-release.yml.
  local _m; _m="$(printf '%s' "$*" | tr -d '\n\r' | LC_ALL=C tr -cd '\40-\176')"
  echo "::error::registry-replace-preflight: ${p} ABORT — ${_m}" >&2
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
# `_try_local_cache_reload` (apps/web-platform/infra/ci-deploy.sh) fires when the pull path has
# already failed. CORRECTED (#7555 review): the earlier wording said "ONLY when BOTH registries
# have already failed", which is false at one of its two call sites — the ZOT_ACTIVE==0 branch is
# reached when zot is dark and never attempted, i.e. GHCR alone failed. So a hit does not entail
# "serving off the last tier"; it can mean zot was not configured this deploy. The direction is
# fail-closed (over-refusal), so this costs availability of the fix rather than safety, but the
# sentence was the entire justification for P1 being GATING and it did not hold as written. This is #6400 exactly: a degraded fallback is
# what turned a registry outage into a total deploy outage.
# P1 IS SKIPPED ON THE MANUAL RE-FIRE ARM (#7555 review). During a replace outage deploys fall
# back to local-cache, so P1 would abort for 24h — and the documented rollback for a failed or
# dark replace IS "re-fire the dispatcher". That is verbatim the anti-pattern this file's own
# header rejects for D10's A4: it would block the recovery on the condition the recovery cures.
# The `reason` input required by workflow_dispatch is the human judgement P1 stands in for.
# Counts over the RAW row. betterstack-query.sh's own header records the stronger rule (#6475):
# field-isolate from the decoded object, or a job that merely PRINTED a marker name counts. The
# marker survives double-encoding so this works today, but a row QUOTING the literal (an error
# tail spliced into a log line) would refuse the replace. Fail-closed, and noted rather than
# silently relied on.
lc_hits="$(printf '%s\n' "$PROBE_OUT" | { grep -c 'registry=local-cache' || true; })"
if [[ "${REGISTRY_PREFLIGHT_MANUAL:-0}" == "1" && "${lc_hits:-0}" -gt 0 ]]; then
  echo "NOTE: P1 observed ${lc_hits} local-cache event(s) but this is a MANUAL re-fire, which is the documented recovery path for a failed or dark replace. Not gating."
elif [[ "${lc_hits:-0}" -gt 0 ]]; then
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
# EVERY WORKFLOW THAT CRANE-COPIES INTO ZOT, not just the web release (#7555 review): the hazard
# is "a replace mid-push strands a partial manifest on the preserved volume", and three workflows
# can be pushing. Derived rather than remembered:
#   grep -rln 'crane copy' .github/workflows/
ZOT_WRITER_WORKFLOWS="${REGISTRY_PREFLIGHT_ZOT_WRITERS:-web-platform-release.yml build-inngest-config-bundle.yml build-inngest-bootstrap-image.yml}"
# `queued` COUNTS. Merging fires the release and this dispatcher on the SAME push, so at preflight
# time the release is very likely queued, not in_progress — and `--status` takes one value, so the
# old single-status filter reported 0 for exactly the case P3 exists to catch.
p3_err="$(mktemp)"
in_progress=0
runs_rc=0
for _wf in $ZOT_WRITER_WORKFLOWS; do
  _json="$("$RUNS_CMD" run list --workflow="$_wf" --limit 30 --json status 2>>"$p3_err")" || { runs_rc=$?; break; }
  _n="$(printf '%s' "$_json" | { grep -oE '"status":"(queued|in_progress|waiting|requested|pending)"' || true; } | grep -c . || true)"
  in_progress=$(( in_progress + _n ))
done
if (( runs_rc != 0 )); then
  abort P3 "could not list in-flight runs for the zot-writing workflows (gh exited ${runs_rc}): $(head -c 300 "$p3_err"). Refusing rather than replacing the registry host with an unknown number of pushes in flight."
fi
if [[ "${in_progress:-0}" -gt 0 ]]; then
  abort P3 "${in_progress} in-flight run(s) across the zot-writing workflows (queued or running). A replace mid-push strands a partial manifest on the preserved volume. Wait for them to finish, then re-dispatch."
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
