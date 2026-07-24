#!/usr/bin/env bash
# D10 — PRE-DESTROY pull-path health gate for the registry-luks-recut dispatch (#6929).
#
# WHY: the recut destroys the zot store. That is only an acceptable trade because the store is a
# DISPOSABLE GHCR MIRROR — pulls fall through to GHCR while it re-fills. If the GHCR fallback
# path is ALREADY degraded when the recut fires, that assumption is false and the dispatch would
# create the #6400 total-deploy-outage rather than merely tolerating an empty-store window.
# So: refuse to destroy the store while the very path that covers its absence is unhealthy.
#
# ZERO-TOLERANCE THRESHOLD. A healthy fleet emits ONLY `registry=zot`
# (apps/web-platform/infra/ci-deploy.sh registry_pull_event); `ghcr-fallback` and `local-cache`
# are both level=warning precisely because they are never expected. So ">=1 event ⇒ ABORT" has
# no false-abort surface and is a real number, not a hand-wave like "sustained hits".
#
# ── WHY SENTRY AND NOT BETTER STACK (measured, #6929 Phase 0.2) ─────────────────────────────
# The plan for this gate specified `betterstack-query.sh --grep ghcr-fallback --grep local-cache`.
# That query CANNOT EVER RETURN A ROW, and a gate that can only ever be green is worse than no
# gate because it is read as evidence:
#
#   * `registry_pull_event` emits to (a) the Sentry store API and (b) local journald on the WEB
#     host, via `logger`.
#   * Better Stack's only ingested source in this repo is the INNGEST vector journald feed
#     (table t520508_soleur_inngest_vector_prd_3_logs, the default in betterstack-query.sh).
#     There is no web-host table.
#
# So the marker is structurally absent from the queried warehouse. Verified by measurement, not
# inference: `--since 720h --grep ghcr-fallback` and `--grep registry_pull_event` both returned
# zero rows while an ungrepped query over the same window returned rows normally.
#
# Sentry IS the source of truth for this signal, and scripts/followthroughs/zot-soak-6122.sh
# already queries exactly these tags with a hardened helper. This script reuses that idiom,
# including its fail-closed TRANSIENT semantics.
#
# FAIL-CLOSED. An unreachable API, a bad token, or an unexpected payload shape ABORTS. The gate
# protects an irreversible destroy; "I could not check" must never read as "it is fine".
#
# Usage:
#   scripts/registry-pull-path-health.sh [--since-hours N]
#
# Env:
#   SENTRY_AUTH_TOKEN  (required) — read scope on the org's events. In CI, from Doppler
#                      prd_terraform (the same config the dispatch already reads).
#   SENTRY_ORG         (default jikigai-eu)
#   REGISTRY_PULL_HEALTH_QUERY_CMD (test seam) — invoked with the Sentry query string; must echo
#                      an integer event count, or a non-numeric token to signal a failed query.

set -uo pipefail

SINCE_HOURS=24
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since-hours) SINCE_HOURS="${2-}"; shift 2 ;;
    *) echo "::error::registry-pull-path-health: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

if [[ ! "$SINCE_HOURS" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::registry-pull-path-health: --since-hours must be a positive integer (got '${SINCE_HOURS}')." >&2
  exit 1
fi

ORG="${SENTRY_ORG:-jikigai-eu}"
API="${SENTRY_API_BASE:-https://sentry.io/api/0}"

# The watched signals. Both are level=warning in ci-deploy.sh and both mean "zot did not serve":
#   ghcr-fallback — zot WAS attempted and the pull failed (the pull path is degraded).
#   local-cache   — BOTH registries failed and an already-running image was reloaded. Strictly
#                   worse than ghcr-fallback: it means the GHCR cover this recut depends on was
#                   ITSELF unavailable.
# Declared as an array so "declared but never counted" is unrepresentable in source, with a
# runtime cardinality floor below so an emptied array cannot silently yield a PASS.
declare -A WATCHED=(
  [ghcr-fallback]='feature:supply-chain op:image-pull registry:"ghcr-fallback"'
  [local-cache]='feature:supply-chain op:image-pull registry:"local-cache"'
)

if (( ${#WATCHED[@]} != 2 )); then
  echo "::error::registry-pull-path-health: WATCHED has ${#WATCHED[@]} entries, expected 2 — refusing to report a verdict on a partial signal set." >&2
  exit 1
fi

if [[ -z "${REGISTRY_PULL_HEALTH_QUERY_CMD:-}" && -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::error::registry-pull-path-health: SENTRY_AUTH_TOKEN unset — cannot verify the GHCR fallback path is healthy. Refusing to authorize a store destroy against an unverifiable pull path." >&2
  exit 1
fi
[[ -n "${SENTRY_AUTH_TOKEN:-}" ]] && echo "::add-mask::${SENTRY_AUTH_TOKEN}"

START=$(date -u -d "-${SINCE_HOURS} hours" +%Y-%m-%dT%H:%M:%S 2>/dev/null) || {
  echo "::error::registry-pull-path-health: could not compute the window start." >&2; exit 1; }
END=$(date -u +%Y-%m-%dT%H:%M:%S)

# sentry_count <query> → echoes the event count, or a non-numeric token on any failure.
sentry_count() {
  if [[ -n "${REGISTRY_PULL_HEALTH_QUERY_CMD:-}" ]]; then
    $REGISTRY_PULL_HEALTH_QUERY_CMD "$1"
    return
  fi
  local enc url resp status body n
  enc=$(printf '%s' "$1" | jq -sRr @uri)
  url="${API}/organizations/${ORG}/events/?query=${enc}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp"
  resp=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" -H "Accept: application/json" "$url" 2>/dev/null)
  status=$(printf '%s' "$resp" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$status" != "200" ]]; then echo "QUERY_FAILED"; return; fi
  # Require .data to BE an array. Taking `length` with a zero default would turn an error object
  # (no .data → null → 0) into a COUNTED ZERO — a false-PASS on the one gate protecting an
  # irreversible destroy. On a shape mismatch jq errors → empty → QUERY_FAILED.
  n=$(printf '%s' "$body" | jq -r 'if (.data | type) == "array" then (.data | length) else error("no data array") end' 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo "QUERY_FAILED"
}

echo "registry-pull-path-health: window ${START}..${END} (${SINCE_HOURS}h), org=${ORG}"

total=0
declare -A COUNTS
for k in $(printf '%s\n' "${!WATCHED[@]}" | sort); do
  n=$(sentry_count "${WATCHED[$k]}")
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    echo "::error::registry-pull-path-health: Sentry query for '${k}' failed (window ${START}..${END}). FAIL-CLOSED: the recut destroys the zot store and this gate is what proves the GHCR fallback can cover its absence. Re-run once Sentry is reachable — do NOT proceed on an unverified pull path." >&2
    exit 1
  fi
  COUNTS[$k]=$n
  total=$(( total + n ))
done

echo "pull_path ghcr_fallback=${COUNTS[ghcr-fallback]} local_cache=${COUNTS[local-cache]} total=${total} threshold=0"

if (( total > 0 )); then
  cat >&2 <<EOF
::error::registry-pull-path-health: ABORT — ${total} degraded pull event(s) in the last ${SINCE_HOURS}h (ghcr-fallback=${COUNTS[ghcr-fallback]} local-cache=${COUNTS[local-cache]}). A healthy fleet emits ONLY registry=zot, so ANY of these means the GHCR fallback path is already degraded.

This recut DESTROYS the zot store and depends on GHCR covering the empty-store window. Firing it now would turn a tolerable window into a total-deploy outage (#6400).

EXIT: the degradation must clear first — check the zot_mirror_fallback_rate alert state, then re-fire. If the degradation IS the reason you want to recut, that is an INCIDENT path, not a recut: fix the pull path first.
EOF
  exit 1
fi

echo "registry-pull-path-health: PASS — zero degraded pull events in ${SINCE_HOURS}h; the GHCR fallback path can cover the empty-store window."
exit 0
