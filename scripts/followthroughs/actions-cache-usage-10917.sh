#!/usr/bin/env bash
# Follow-through verification for #10917: the repository's Actions cache is back under its cap.
#
# The release workflow stopped exporting its BuildKit cache to the Actions cache (ADR-299). Entries
# the old export wrote are not deleted; GitHub evicts unused ones after 7 days, so this probe is
# enrolled with `earliest` = merge date + 8 days.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       active_caches_size_in_bytes is under the 8 GB threshold (the issue's own
#                  re-evaluation criterion; the hard cap is 10 GB)
#   1 = FAIL       still over the threshold: another writer, or entries have not aged out yet.
#                  The next step is the explicit-authorization prune option recorded on #10917;
#                  this probe never deletes anything.
#   2 = TRANSIENT  gh unreachable, auth failure, or an unreadable response
#
# Required env: GH_TOKEN with actions:read (declared via the directive's secrets= clause).
set -uo pipefail

# Refuse to run traced with a live credential: `set -x` would expand the gh call, token included,
# into a public Actions log (same guard as the sibling probes, #7797).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
THRESHOLD_BYTES=8000000000

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "TRANSIENT: GH_TOKEN not set" >&2
  exit 2
fi

usage_rc=0
usage=$(gh api "repos/${REPO}/actions/cache/usage" 2>/dev/null) || usage_rc=$?
if [[ "$usage_rc" -ne 0 ]]; then
  echo "TRANSIENT: gh api actions/cache/usage failed (rc ${usage_rc})" >&2
  exit 2
fi

bytes=$(jq -r '.active_caches_size_in_bytes' <<<"$usage" 2>/dev/null) || bytes=""
count=$(jq -r '.active_caches_count' <<<"$usage" 2>/dev/null) || count=""
if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: actions/cache/usage returned no numeric active_caches_size_in_bytes" >&2
  exit 2
fi

if [[ "$bytes" -lt "$THRESHOLD_BYTES" ]]; then
  echo "PASS: Actions cache usage is ${bytes} bytes across ${count:-?} entries, under the ${THRESHOLD_BYTES}-byte threshold"
  exit 0
fi

echo "FAIL: Actions cache usage is ${bytes} bytes across ${count:-?} entries, not under the ${THRESHOLD_BYTES}-byte threshold" >&2
echo "      Either entries written by the old gha export have not aged out (7 days unused) or another" >&2
echo "      workflow is writing large entries; read gh api repos/${REPO}/actions/caches before acting." >&2
exit 1
