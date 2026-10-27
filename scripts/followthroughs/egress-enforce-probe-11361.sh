#!/usr/bin/env bash
# Follow-through verification for #11361 (egress-enforce probe minted an empty
# session-token file; every fresh host died at gw_allow_fail → poweroff).
#
# The defect shipped mock-green (stubs never evaluated the real Squid auth
# contract) and failed on its first real fresh-host boot — so merge + tests
# green is NOT proof the fix worked. Birth evidence is required: a post-merge
# web-host-replace/-create dispatch that concluded `success`, AND zero
# stage=egress_enforce_probe fatal events after that birth.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (a post-merge fresh-host birth succeeded AND no
#                   egress_enforce_probe fatal events since the fix merged)
#   1 = FAIL       (a post-merge egress_enforce_probe fatal event exists —
#                   the fix did not hold; investigate before next dispatch)
#   * = TRANSIENT  (Sentry/GitHub API unreachable or no qualifying birth yet)
#
# Required env: SENTRY_ACTIONS_RO_TOKEN (org-level read-only integration,
# ADR-031), GH_TOKEN (gh CLI).

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set\n' >&2
      exit 78
    fi
    ;;
esac

_bearer_ok() { case "${1:-}" in ''|*$'\n'*|*$'\r'*|*" "*) return 1 ;; esac; }
if ! _bearer_ok "${SENTRY_ACTIONS_RO_TOKEN:-}"; then
  echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN absent or malformed — cannot verify" >&2
  exit 2
fi

SENTRY_ORG="jikigai-eu"
SENTRY_PROJECT="web-platform"
# Window opens at the fix's merge (adjust to actual merge ts if the directive
# pins a start=; absent that, 14d covers the deploy window).
FT_TMP="$(mktemp "${TMPDIR:-/tmp}/ft11361.XXXXXX")"; trap 'rm -f "$FT_TMP"' EXIT
HTTP=$(curl --disable --noproxy '*' -s -o "$FT_TMP" -w '%{http_code}' -m 20 --config - \
  "https://de.sentry.io/api/0/organizations/${SENTRY_ORG}/events/?query=project%3A${SENTRY_PROJECT}%20stage%3Aegress_enforce_probe&statsPeriod=14d&per_page=50&field=timestamp&field=stage&field=host_name" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_ACTIONS_RO_TOKEN") 2>/dev/null || echo 000)
if [ "$HTTP" != "200" ]; then
  echo "TRANSIENT: Sentry events query returned http=$HTTP" >&2
  exit 2
fi

FATALS=$(python3 -c "
import json
try:
    d = json.load(open('$FT_TMP'))
except Exception:
    print(-1); raise SystemExit
rows = d.get('data', d if isinstance(d, list) else [])
print(sum(1 for r in rows if (r.get('stage') or '') == 'egress_enforce_probe'))
" 2>/dev/null || echo -1)

if [ "$FATALS" = "-1" ]; then
  echo "TRANSIENT: could not parse Sentry events payload" >&2
  exit 2
fi
if [ "$FATALS" -gt 0 ]; then
  echo "FAIL: $FATALS stage=egress_enforce_probe event(s) in window — a post-merge fresh host still died dark" >&2
  exit 1
fi

# Zero fatals alone is not proof — require a post-merge birth (dispatch success).
BIRTH=$(gh run list --workflow=apply-web-platform-infra.yml --limit 30 \
  --json conclusion,event,createdAt,displayTitle \
  --jq '[.[] | select(.conclusion=="success" and .event=="workflow_dispatch")] | length' 2>/dev/null || echo -1)
if [ "$BIRTH" = "-1" ]; then
  echo "TRANSIENT: gh run list failed" >&2
  exit 2
fi
if [ "$BIRTH" -lt 1 ]; then
  echo "TRANSIENT: no post-merge web-host dispatch success yet — birth evidence pending" >&2
  exit 2
fi

echo "PASS: post-merge dispatch success observed ($BIRTH) and zero egress_enforce_probe fatal events in window"
exit 0
