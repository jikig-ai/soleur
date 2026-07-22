#!/usr/bin/env bash
set -u
# --- #6548: git-data CONSUMER-perspective reachability probe ---------------------------------
# Runs ON the web host and verifies it can reach git-data (10.0.1.20:22, ED25519 SSH transport,
# git-data.tf:29-40) over the private NIC; pings GIT_DATA_HEARTBEAT_URL on success. A fail-soft
# overlay: git-data is "an OVERLAY, not a hard dependency" (ensure-workspace-repo.ts:332), so a
# single transient blip must NOT page — the git_data_prd heartbeat's grace is relaxed to 180s
# (git-data.tf) so paging fires only on a SUSTAINED break.
#
# SERVICEABILITY ASYMMETRY (Kieran P2, C1b — named, not hidden): a bounded TCP connect-and-close to
# :22 proves the port is OPEN, not that git transport SERVES — the same reachability-vs-service-
# ability gap this bundle REJECTS for zot (where it presents auth + reads a real repo). git-data is
# fail-soft, so connect-and-close is an ACCEPTED v1 tradeoff; the git-data.tf:270-273 TODO
# prescribes `git ls-remote` (a real transport check) as the upgrade if a port-open-but-wedged
# git-data is ever observed.
#
# CONFIG IS ENV: GIT_DATA_ENDPOINT (host:port) from /etc/default/web-git-data-probe;
# GIT_DATA_HEARTBEAT_URL from the doppler-run env.
#
# TEST SEAM: SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE (reachable|unreachable) injects the connect result
# so the branch logic is unit-testable; SOLEUR_GIT_DATA_PROBE_PING_LOG re-routes the ping to a file.
# Neither is ever set in production.

ENDPOINT="${GIT_DATA_ENDPOINT:-10.0.1.20:22}"
HOST="${ENDPOINT%%:*}"
PORT="${ENDPOINT##*:}"
URL="${GIT_DATA_HEARTBEAT_URL:-}"
# Happy-path stderr is shipped off-box via Vector Source 4 (SyslogIdentifier=web-git-data-probe);
# the heartbeat ping is the off-box liveness signal, so the "reachable ... pinged" narration is
# redundant there and pure quota cost at 60s cadence. Gate it behind a debug flag (default OFF);
# the fail-soft SUPPRESS classification below always emits. Set SOLEUR_PROBE_VERBOSE=1 for on-host debug.
VERBOSE="${SOLEUR_PROBE_VERBOSE:-}"

_ping() {
  if [ -n "${SOLEUR_GIT_DATA_PROBE_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_GIT_DATA_PROBE_PING_LOG"
    return 0
  fi
  [ -n "$URL" ] || { echo "[git-data-probe] WARN: GIT_DATA_HEARTBEAT_URL unset — reachable but cannot ping." >&2; return 0; }
  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || echo "[git-data-probe] WARN: heartbeat ping FAILED (reachable, url_present=yes)" >&2
}

_reachable() {
  # Bounded, no-auth connect-and-close. Prefer nc -z; fall back to bash /dev/tcp (always available
  # in bash). Both are bounded so a hung SSH banner can never stack ticks.
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 5 "$HOST" "$PORT" >/dev/null 2>&1
    return $?
  fi
  timeout 5 bash -c "exec 3<>/dev/tcp/${HOST}/${PORT}" >/dev/null 2>&1
}

REACH="${SOLEUR_GIT_DATA_PROBE_REACH_OVERRIDE:-}"
if [ -z "$REACH" ]; then
  if _reachable; then REACH=reachable; else REACH=unreachable; fi
fi

if [ "$REACH" = reachable ]; then
  _ping "$URL"
  [ -n "$VERBOSE" ] && echo "[git-data-probe] reachable: ${ENDPOINT} accepted a bounded TCP connect — pinged heartbeat." >&2
  exit 0
else
  echo "[git-data-probe] SUPPRESS ping: ${ENDPOINT} UNREACHABLE over the private net. Fail-soft — pages only on a SUSTAINED break (grace 180s)." >&2
  exit 0
fi
