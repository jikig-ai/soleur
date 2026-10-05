#!/usr/bin/env bash
# Readiness poll for the single-use web-2 volume rebirth (#9372): wait for a SOLEUR_FRESH_BOOT_READY row for host=soleur-web-2
# that is NEWER than the run anchor and carries luks=1 luks_arm=formatted escrow=ok. Read-only (Better Stack only): the
# soak-marker census in workspaces-luks-verify-workflow.test.sh allow-lists this file as a READER, so it must carry no write
# verb. Exit 0 on a fresh GREEN row; 1 otherwise (a RED fresh row ends the poll at once: the host stays dark and the marker withheld).
#
# usage: web2-rebirth-ready-poll.sh <run-anchor-epoch>
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to trace: Better Stack credentials are in scope\n' >&2; exit 78 ;;
esac
_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLL_INTERVAL_S="${WEB2_REBIRTH_POLL_INTERVAL_S:-60}"
fail() {
  local m="$*"
  m="${m//%/%25}"; m="${m//$'\r'/%0D}"; m="${m//$'\n'/%0A}"
  echo "::error::$m"
  exit 1
}
anchor="${1:?anchor epoch required}"
[[ "$anchor" =~ ^[0-9]+$ ]] || fail "ready-poll: the run anchor must be an epoch"
# shellcheck source=scripts/lib/web2-luks-rows.sh
source "${_ROOT}/scripts/lib/web2-luks-rows.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# The lookback below is 4 days: a resume is offered up to 72 h after the rebirth, and the once-per-instance readiness row is that old by then.
for i in $(seq 1 "${WEB2_REBIRTH_POLL_ATTEMPTS:-24}"); do
  if w2l_fetch_ready "$tmp/ready.jsonl" 4 20; then
    verdict="$(w2l_ready_verdict "$tmp/ready.jsonl")"
    if [[ "$verdict" == GREEN* ]]; then
      age="${verdict##* age_s=}"; now="$(date -u +%s)"
      row_arm="$(jq -r -s --arg host "$W2L_HOST_NAME" "${_W2L_JQ_DEFS}"'[ .[] | classify_ready ] | sort_by(.age) | (.[0].f.luks_arm // "none")' "$tmp/ready.jsonl" 2>/dev/null || echo none)"
      if [[ "$age" =~ ^[0-9]+$ ]] && (( age < now - anchor )); then
        [[ "$row_arm" == formatted ]] || fail "ready-poll: the fresh readiness row reports luks_arm=${row_arm}, not formatted: the volume was not freshly formatted by this birth"
        echo "ready: ${verdict} luks_arm=formatted (the row is newer than the run anchor)"; exit 0
      fi
      echo "attempt ${i}: the newest GREEN readiness row (age ${age}s) predates this run; waiting"
    else
      echo "attempt ${i}: ${verdict}"
      case "$verdict" in RED\ reason=ready_escrow*|RED\ reason=ready_not_luks*|RED\ reason=ready_luks_arm*)
        # a row exists and is newer than the anchor only if its age is below the elapsed time: do not wait on a verdict row from before the run
        age="$(w2l_ready_newest_age "$tmp/ready.jsonl")"; now="$(date -u +%s)"
        if [[ "$age" =~ ^[0-9]+$ ]] && (( age < now - anchor )); then fail "ready-poll: the fresh readiness row is RED (${verdict}); the host stays dark (the marker is withheld) and the run is RED"; fi ;; esac
    fi
  else
    echo "attempt ${i}: the Better Stack read did not answer"
  fi
  sleep "$POLL_INTERVAL_S"
done
fail "ready-poll: no fresh GREEN readiness row appeared within the boot window"
