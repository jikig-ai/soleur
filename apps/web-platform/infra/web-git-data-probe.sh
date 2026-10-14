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

# The heartbeat URL's PATH is the credential, so it must not ride curl's argument list (readable by every
# local user in /proc/<pid>/cmdline; ADR-280, #9757): it reaches curl on the stdin config (`--config -`),
# `--disable` (first, so no ~/.curlrc is read as root) and `--noproxy '*'` confine the transport (lint Rule D); `-g` is new here (a URL with [ ] or
# { } would otherwise print itself in curl's glob-parse error). This host has no checkout, so this is the
# inline form of the library. The value is judged BEFORE any request, with no trimming: a scheme other
# than https://, an empty rest, or any byte outside [A-Za-z0-9._~:/?&=%+-] (a quote, backslash or newline
# would add directives to the config grammar) is refused, with zero requests, one value-free marker on
# stderr (the unit's SyslogIdentifier ships it) and the same fail-soft exit as the other arms.
_hb_url_ok() {
  local LC_ALL=C
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|*[!A-Za-z0-9._~:/?\&=%+-]*) return 1 ;; esac
}
# One call = one attempt = one fresh process substitution (a substitution is consumed once, so a second
# attempt sharing the first one's would read EOF and send no URL).
_hb_curl() { curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL"); }

_ping() {
  if [ -n "${SOLEUR_GIT_DATA_PROBE_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_GIT_DATA_PROBE_PING_LOG"
    return 0
  fi
  [ -n "$URL" ] || { echo "[git-data-probe] WARN: GIT_DATA_HEARTBEAT_URL unset — reachable but cannot ping." >&2; return 0; }
  if ! _hb_url_ok "$URL"; then
    echo "SOLEUR_CREDENTIAL_REFUSED script=web-git-data-probe reason=$(case "$URL" in *[[:cntrl:]]*) echo control_char ;; *) echo token_shape ;; esac) var=GIT_DATA_HEARTBEAT_URL" >&2
    echo "[git-data-probe] WARN: heartbeat URL refused (reachable, no ping sent)" >&2
    return 0
  fi
  _hb_curl || _hb_curl || echo "[git-data-probe] WARN: heartbeat ping FAILED (reachable, url_present=yes)" >&2
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
