#!/usr/bin/env bash
# Follow-through verification for #8281 (post-deploy confirmation of the
# SOLEUR_COMPOUND_PROMOTE_OUTCOME marker).
#
# #8281 made `cron-compound-promote`'s outcome observable: every terminal path
# now emits one WARN-level `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker. An
# on-demand run (via the manual-trigger event) proves the CODE emits it; it does
# NOT prove the weekly SCHEDULED path does, because the manual trigger enters
# through a different Inngest event. This probe closes that gap.
#
# The cron fires `0 0 * * 0` (Sunday 00:00 UTC), so the directive's `earliest=`
# must sit at least 8 days past the merge for one scheduled fire to have landed.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>=1 marker row in the window; sweeper closes #8281)
#   1 = FAIL       (zero rows -- still soaking, or the scheduled path is dark)
#   * = TRANSIENT  (Better Stack unreachable / auth failure; retry next sweep)
#
# Exit 1 carries the convention's "still soaking" meaning, matching
# workspaces-luks-soak-6604.sh: it is NOT an assertion that the feature is
# broken, and the sweeper leaves the issue open rather than reporting a defect.
#
# Required env (wired in scheduled-followthrough-sweeper.yml):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands after
# expansion, so a credential is printed the moment it is used. `${VAR:+x}` tests
# non-emptiness WITHOUT expanding the value.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (BETTERSTACK_QUERY_PASSWORD). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY_SH="$REPO_ROOT/scripts/betterstack-query.sh"

if [ ! -x "$QUERY_SH" ] && [ ! -f "$QUERY_SH" ]; then
  printf '[TRANSIENT] betterstack-query.sh not found at %s\n' "$QUERY_SH" >&2
  exit 75
fi

# 200h covers one weekly fire plus slack. --limit is explicit: the default caps
# at 100 rows and an enumerating probe that silently truncates reads as
# complete (the class recorded in the #8281 learning).
rows="$(bash "$QUERY_SH" --since 200h --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 50 2>/dev/null)"
rc=$?

if [ "$rc" -ne 0 ]; then
  printf '[TRANSIENT] betterstack-query.sh exited %s\n' "$rc" >&2
  exit 75
fi

count="$(printf '%s' "$rows" | grep -c 'SOLEUR_COMPOUND_PROMOTE_OUTCOME' || true)"

if [ "${count:-0}" -ge 1 ]; then
  printf '[PASS] %s SOLEUR_COMPOUND_PROMOTE_OUTCOME row(s) in the last 200h — the scheduled path emits.\n' "$count"
  exit 0
fi

printf '[FAIL] zero SOLEUR_COMPOUND_PROMOTE_OUTCOME rows in the last 200h — still soaking, or the scheduled fire is dark.\n' >&2
exit 1
