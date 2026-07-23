#!/usr/bin/env bash
# Follow-through verification for #5274 Phase 3 GA soak (post-cutover, Sub-PR 3.D).
#
# The git-data LUKS cutover (git-data-cutover.yml) flips GIT_DATA_STORE_ENABLED on
# both web hosts. ADR-068 flips `adopting`→`accepted` and the #5274 Phase-3
# milestone closes ONLY after a >=7-day soak in which the multi-host routing +
# shared-git-data + fence path stays clean under real two-host contention. This
# script is that soak gate: it PASSES only when, over the window from just-after
# cutover to now, Sentry shows ZERO of the three GA-gating failure classes:
#   1. fence false-rejects        — worktree_lease reject events (non-monotonic
#                                    gen rejected a legitimate push after cutover);
#   2. cross-tenant git-data denials — git-data events with member:false (a
#                                    non-member fetch/write reached the authz layer);
#   3. control_plane_route failures — the co-located router failed to place/proxy
#                                    a session to its owning host.
# When all three hold at ~0 for the window, this issue closes and ADR-068 is
# considered accepted (adopting → accepted); the milestone closes.
#
# Asserts ZERO Sentry error-level events matching those ops/tags in the window
# from just-after the cutover (START, pinned by the operator post-flip) to now.
# The directive's `earliest=` gates the first real check to >=7 days post-cutover,
# and the explicit `START=` pins the window strictly after the flip so any
# pre-cutover dark-launch events cannot contaminate the verdict.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (zero matching error events; sweeper closes #5274's soak tracker)
#   1 = FAIL       (>=1 event in window; a GA-gating regression fired — leave open, investigate)
#   * = TRANSIENT  (Sentry API unreachable / auth / parse failure; retry next sweep)
#
# Required env: SENTRY_AUTH_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_IAC_AUTH_TOKEN). Mirrors ac8-founder-ambiguous-soak-5673.sh.

set -uo pipefail

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# The three GA-gating failure classes as a single Sentry query. `op:` tags are set
# by the routing/fence/git-data surfaces (feature tags control_plane_route,
# worktree_lease, git-data per plan §Observability). worktree_lease events are
# scoped to reject-outcomes; git-data events to member:false denials. level:error
# excludes info-level breadcrumbs.
# The three GA-gating classes are emitted as the `feature` tag (op is a sub-op),
# so key on `feature:`, NOT `op:` (reportSilentFallback maps feature->tag feature,
# op->tag op; observability.ts). The cross-tenant denial is warnSilentFallback
# (level:warning, not error) and carries `cross_tenant:true` as a searchable tag
# (`member:false` lives in non-searchable `extra`). Mis-keying any of these makes
# the gate blind → always-PASS → false ADR-068 accept (#5274 review, detector-mismatch).
QUERY='(level:error OR level:warning) (feature:worktree_lease OR feature:control_plane_route OR (feature:git-data-authz cross_tenant:true))'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)

# Absolute window start — PIN THIS just after the cutover flip (the same UTC the
# operator records in the runbook). Placeholder until pinned; the earliest= gate
# in the issue directive still defers the first check to >=7 days after this.
START="<POST_CUTOVER_UTC>"
END=$(date -u +%Y-%m-%dT%H:%M:%S)

URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&start=${START}&end=${END}&per_page=10&field=title&field=timestamp&field=level"

RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

EVENT_COUNT=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)

if ! [[ "$EVENT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not parse event count from response" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  echo "PASS: 0 fence-false-reject / cross-tenant-denial / control_plane_route error events since cutover ($START..$END) — #5274 Phase-3 GA soak holds; ADR-068 accepted, milestone closes."
  exit 0
fi

echo "FAIL: $EVENT_COUNT GA-gating error event(s) since $START — a fence false-reject, cross-tenant git-data denial, or control_plane_route failure fired; investigate before this can close."
printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp) (id=\(.id))"' | head -10
exit 1
