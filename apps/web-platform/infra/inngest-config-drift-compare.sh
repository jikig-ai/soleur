#!/usr/bin/env bash
#
# inngest-config-drift-compare.sh — the off-box drift comparator core for the ADR-133
# config-refresh channel (#6780, HARD-8 / AC19). Single-shot verdict: given the promoted
# INNGEST_CONFIG_DIGEST pointer and the LATEST off-box `SOLEUR_INFRA_PULL_APPLIED` marker
# (queried from Better Stack by the scheduled-inngest-config-drift.yml executor), decide whether
# the host's applied digest matches the promoted pointer.
#
# This is the tested, hermetic CORE; the GHA executor wires Better Stack + the Doppler pointer to
# it and applies the N-consecutive-windows tolerance before alarming. No network, no LLM here.
#
# USAGE:
#   inngest-config-drift-compare.sh --pointer <digest-or-empty> --marker '<latest-marker-line>'
#
#   --pointer : the promoted INNGEST_CONFIG_DIGEST (with or without a leading "sha256:"). EMPTY
#               pre-cutover / pre-promotion (the pointer TF applies at the #6178 cutover).
#   --marker  : the latest SOLEUR_INFRA_PULL_APPLIED marker line, e.g.
#               'SOLEUR_INFRA_PULL_APPLIED version=7 sha256=<digest> verify=ok'
#               The boot-floor marker carries `version=floor` (distinguishable — HARD-8). EMPTY
#               when no marker exists in the query window.
#
# VERDICTS (printed to stdout as `<VERDICT> <detail>`):
#   PENDING   (exit 0) — no pointer promoted yet: channel not live / nothing to compare (HARD-11).
#   OK        (exit 0) — applied sha256 == pointer.
#   DIVERGED  (exit 2) — pointer promoted but the latest applied digest does not match it: a dead
#                        timer (no marker), a stuck delta (only `version=floor` booted while the
#                        pointer names a higher digest), or an applied≠pointer mismatch.
#   The executor treats exit 2 as the alarm signal (after its N-windows tolerance).

set -euo pipefail

POINTER=""
MARKER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pointer) POINTER="${2:-}"; shift 2 ;;
    --marker)  MARKER="${2:-}";  shift 2 ;;
    *) echo "compare: unknown arg: $1" >&2; exit 64 ;;
  esac
done

# Normalize the pointer: strip an optional "sha256:" prefix and surrounding whitespace.
POINTER="${POINTER#sha256:}"
POINTER="${POINTER//[[:space:]]/}"

# No pointer promoted → nothing to compare. Pre-cutover this is the steady state (the pointer TF
# rides #6178); post-cutover a missing pointer means no promotion has happened. Either way it is
# NOT a divergence — do not alarm (HARD-11: the channel is not live until a pointer is promoted).
if [[ -z "$POINTER" ]]; then
  echo "PENDING nothing-promoted (pointer empty — channel not live / no promotion)"
  exit 0
fi

# A pointer is promoted. Extract version + sha256 from the latest marker (if any). We parse only
# the two fields we trust; the marker is off-box observability, not an authority for the digest.
applied_version=""
applied_sha=""
if [[ -n "$MARKER" ]]; then
  # `version=<token>` and `sha256=<hex>` in any order; tolerate extra fields.
  if [[ "$MARKER" =~ version=([A-Za-z0-9]+) ]]; then applied_version="${BASH_REMATCH[1]}"; fi
  if [[ "$MARKER" =~ sha256=(sha256:)?([0-9a-fA-F]+) ]]; then applied_sha="${BASH_REMATCH[2]}"; fi
fi

# Dead timer / never pulled: pointer promoted but NO applied marker in the window.
if [[ -z "$applied_sha" ]]; then
  echo "DIVERGED no-applied-marker (pointer=${POINTER} promoted but no SOLEUR_INFRA_PULL_APPLIED marker in window — dead timer or never pulled)"
  exit 2
fi

# Authoritative check: the applied digest must equal the promoted pointer.
if [[ "$applied_sha" == "$POINTER" ]]; then
  echo "OK applied==pointer version=${applied_version:-?} sha256=${applied_sha}"
  exit 0
fi

# Mismatch. Distinguish the boot-floor-only stuck-delta (HARD-8: the version=floor marker must NOT
# mask a promoted-but-never-applied delta) from a generic applied≠pointer mismatch.
if [[ "$applied_version" == "floor" ]]; then
  echo "DIVERGED floor-only-stuck-delta (only the baked floor booted [version=floor sha256=${applied_sha}] while pointer=${POINTER} names a higher digest — the delta never pulled)"
  exit 2
fi

echo "DIVERGED applied!=pointer (applied version=${applied_version:-?} sha256=${applied_sha} != pointer=${POINTER})"
exit 2
