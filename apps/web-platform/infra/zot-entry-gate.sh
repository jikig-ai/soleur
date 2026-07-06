#!/usr/bin/env bash
# Phase-3 entry gate (#6122/ADR-096): assert that BOTH platform images' currently-deployed
# tags resolve in the self-hosted zot registry BEFORE the pull-site flip is relied on. This
# is the RUNTIME expression of the dark-launch gate — it can only PASS once the operator has
# provisioned (task 1.8) + backfilled (task 1.9) zot, which is exactly why the flip "trails
# dual-push by >= 1 release" (plan Phase 3). A non-zero exit BLOCKS the flip.
#
# Usage:  zot-entry-gate.sh <web-tag> <inngest-tag>
#   e.g.  zot-entry-gate.sh v1.2.3 v1.1.18
#
# Config: ZOT_REGISTRY_URL / ZOT_PULL_USER / ZOT_PULL_TOKEN read from the ambient env if set
# (tests), else from Doppler prd. Each image's manifest is probed via a plain-HTTP /v2/ HEAD
# with the pull cred — zot serves HTTP on the private net (cosign digest-pinning is the
# integrity guard, not TLS; Phase-0 spike).
#
# Exit: 0 = both resolve (the flip may proceed);
#       1 = one or both missing (BLOCK the flip — backfill first);
#       2 = zot unreachable / cred missing (TRANSIENT — cannot decide, do NOT flip).
set -uo pipefail

WEB_TAG="${1:?usage: zot-entry-gate.sh <web-tag> <inngest-tag>}"
INNGEST_TAG="${2:?usage: zot-entry-gate.sh <web-tag> <inngest-tag>}"

_doppler_get() {
  command -v doppler >/dev/null 2>&1 || return 0
  doppler secrets get "$1" --plain --project soleur --config prd 2>/dev/null || true
}
ZOT_URL="${ZOT_REGISTRY_URL:-$(_doppler_get ZOT_REGISTRY_URL)}"
ZOT_USER="${ZOT_PULL_USER:-$(_doppler_get ZOT_PULL_USER)}"
ZOT_TOKEN="${ZOT_PULL_TOKEN:-$(_doppler_get ZOT_PULL_TOKEN)}"

if [ -z "$ZOT_URL" ] || [ -z "$ZOT_USER" ] || [ -z "$ZOT_TOKEN" ]; then
  echo "zot-entry-gate: ZOT_REGISTRY_URL/PULL_USER/PULL_TOKEN not all present — cannot decide (TRANSIENT)" >&2
  exit 2
fi

# Reachability probe first, so a down registry is a TRANSIENT (exit 2), distinct from a
# reachable registry that is simply MISSING the tag (a real FAIL / exit 1). A live OCI
# registry answers /v2/ with 200 (open) or 401 (auth); an unreachable host yields non-zero.
if ! curl -s -o /dev/null --max-time 5 "http://$ZOT_URL/v2/"; then
  echo "zot-entry-gate: zot /v2/ unreachable at $ZOT_URL — cannot decide (TRANSIENT)" >&2
  exit 2
fi

_ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

# manifest_resolves <repo> <tag> → true iff a manifest HEAD returns HTTP 200.
manifest_resolves() {
  local repo="$1" tag="$2" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -u "$ZOT_USER:$ZOT_TOKEN" \
    -H "Accept: $_ACCEPT" -I "http://$ZOT_URL/v2/$repo/manifests/$tag" 2>/dev/null || echo 000)"
  [ "$code" = "200" ]
}

RC=0
for pair in "jikig-ai/soleur-web-platform:$WEB_TAG" "jikig-ai/soleur-inngest-bootstrap:$INNGEST_TAG"; do
  repo="${pair%:*}"; tag="${pair##*:}"
  if manifest_resolves "$repo" "$tag"; then
    echo "zot-entry-gate: OK   $repo:$tag resolves in zot"
  else
    echo "zot-entry-gate: MISS $repo:$tag does NOT resolve in zot — flip BLOCKED" >&2
    RC=1
  fi
done

if [ "$RC" -eq 0 ]; then
  echo "zot-entry-gate: PASS — both images resolve in zot; the pull-site flip may proceed."
else
  echo "zot-entry-gate: FAIL — backfill the missing image(s) (crane copy GHCR->zot) before flipping." >&2
fi
exit "$RC"
