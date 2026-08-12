#!/usr/bin/env bash
set -u
# --- #7228 Phase 1: inngest CONSUMER-perspective serviceability probe --------------------------
# Runs ON THE WEB HOST and verifies that the dedicated inngest host (10.0.1.40:8288) actually
# SERVES its function registry over the private NIC. On success it pings a dedicated Better Stack
# heartbeat; every other outcome SUPPRESSES the ping so that ABSENCE alarms.
#
# THE FAILURE THIS EXISTS FOR (#7228). The dedicated host booted 2026-07-30 and never bound :8288.
# Twelve days passed with every signal green, because the only monitor in the path pushes
# `curl "$INNGEST_HEARTBEAT_URL"` from a systemd timer — it proves A TIMER FIRED, never that the
# scheduler serves. No monitor anywhere asserted the bind. This probe is the one that does, and it
# does so from the CONSUMER's side: it has no dependency on the dedicated host's bootstrap having
# run, so unlike anything installed ON that host it works the day it merges, with no host replace.
# Direct sibling of web-zot-consumer-probe.sh (#6438 §1), whose header cites the same #6400 shape:
# "a silent-for-14-days degradation where every health signal stayed green".
#
# WHY THE HTTP CODE IS THE WRONG DISCRIMINATOR. :8288/v0/gql is a GraphQL endpoint, and a GraphQL
# server answers 200 with an `errors` envelope. Worse, a host can serve perfectly with an EMPTY
# registry — which during a cutover is the difference between "healthy" and "the scheduler owns
# nothing". So the classification is over the RESPONSE SHAPE, not the status line:
#   non-empty .data.functions -> PING     — serving AND holding the registry
#   EMPTY .data.functions     -> SUPPRESS — servable over a dead registry (#6400-inside-the-probe)
#   __FETCH_FAILED__          -> SUPPRESS — transport failure; THE CURRENT LIVE STATE (measured
#                                           2026-08-11: ~600 ECONNREFUSED rows/hour against .40)
#   errors[] envelope         -> SUPPRESS — the server answered but is wedged
#   any other shape           -> SUPPRESS — never go green over a response we did not understand
# Every suppressing arm exits 0: the heartbeat's ABSENCE is the alarm, and a non-zero exit would
# additionally red the unit without adding signal (the zot precedent reserves non-zero for a
# probe-side credential fault, which this probe has no equivalent of — it presents no auth).
#
# SINGLE SOURCE OF TRUTH, AND WHY IT IS SOURCED RATHER THAN EXECUTED. The GQL query, the endpoint
# default and the `__FETCH_FAILED__` envelope all belong to inngest-registry-probe.sh, which is
# the cutover's own pre-flight gate. Re-implementing them here would let this probe assert
# something the cutover gate does not. But EXECUTING it is not affordable: `inngest-registry-probe`
# is in vector.toml's Source-4 allowlist and emits 3 `logger` rows per run (PREFLIGHT_START +
# DONE/TIMEOUT + a summary), so a 60s wrapper would cost ~4,320 rows/day against a ~25k/day quota
# — reintroducing the ~1,440 rows/day cost #6617b removed, which vector.toml:145 names "a fresh
# quota decision". That script is BASH_SOURCE-guarded at :141 exactly so it can be sourced without
# running, and its fetch_functions() emits no markers. Sourcing buys both properties at once.
# inngest-consumer-probe.test.sh pins this with a drift block; do not inline a second query here.
#
# NO SOURCE-4 CANARY HERE, DELIBERATELY. web-zot-consumer-probe.sh carries the fleet's single
# journald->vector positive control, and its header states the reason a second one is wrong: "a
# dead agent kills ALL Source-4 tags, so a single canary proves the whole journald->vector path."
# Adding one here would double the beacon cost to certify the same fact.
#
# QUOTA. Silent on success, so the healthy steady state costs ZERO journald rows at any cadence.
# The fault classification is rate-limited on a /run marker (the _canary rate-limit precedent,
# web-zot-consumer-probe.sh:74-82) because the failure state is the expensive one and we are IN it
# for the whole deferral window: unlimited, a dark host would emit 1,440 identical lines/day. At
# ~30min that ceiling is ~48 rows/day. The line still matters — the heartbeat only says
# "suppressed", the journal line says WHY (unreachable vs empty registry vs wedged), and reading
# it must not require SSH (hr-no-ssh-fallback-in-runbooks).
#
# CONFIG IS ENV, delivered by server.tf into /etc/default/inngest-consumer-probe:
# INNGEST_REMOTE_GQL_URL (optional; the sourced default already points at 10.0.1.40) and
# INNGEST_CONSUMER_URL_KEY, whose named Doppler var the unit resolves by indirect expansion.
#
# TEST SEAMS (never set in production): INNGEST_PROBE_FUNCTIONS_FIXTURE is inherited from the
# sourced script; SOLEUR_INNGEST_CONSUMER_PING_LOG re-routes the heartbeat ping to a file;
# SOLEUR_INNGEST_CONSUMER_FAULT_MARKER / _FAULT_INTERVAL parameterise the rate-limit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Both scripts land in /usr/local/bin on the web host (inngest-registry-probe.sh via the
# infra-config push — infra-config-install.sh:74 — and this one via server.tf's provisioner), and
# they are siblings in-repo, so a sibling-relative resolve is correct in both. A missing peer is
# FATAL and LOUD: silently exiting 0 would suppress the ping AND the reason for it, which is the
# precise anti-pattern cq-silent-fallback-must-mirror-to-sentry names.
if [ ! -r "${SCRIPT_DIR}/inngest-registry-probe.sh" ]; then
  echo "[inngest-consumer-probe] FATAL: ${SCRIPT_DIR}/inngest-registry-probe.sh is missing or unreadable — cannot probe without the shared registry query. Is the infra-config push current?" >&2
  exit 1
fi
# shellcheck source=./inngest-registry-probe.sh disable=SC1091
. "${SCRIPT_DIR}/inngest-registry-probe.sh"
# The sourced file sets `set -euo pipefail` for its own execution path. Inheriting -e here would
# abort this script on the very non-zero results it exists to CLASSIFY, and inheriting pipefail
# re-arms the `grep -q` SIGPIPE trap on any pipeline below. Restore this script's own contract
# (keep -u) immediately, before any classification runs.
set +e +o pipefail

URL="${INNGEST_CONSUMER_URL:-}"
FAULT_MARKER="${SOLEUR_INNGEST_CONSUMER_FAULT_MARKER:-/run/inngest-consumer-probe.fault}"
FAULT_INTERVAL="${SOLEUR_INNGEST_CONSUMER_FAULT_INTERVAL:-1800}"

_ping() {
  # Route to the test log if seamed; else fire the real heartbeat ping (two attempts, mirroring
  # web-zot-consumer-probe.sh:57 — a single transient egress blip must not read as a dark host).
  if [ -n "${SOLEUR_INNGEST_CONSUMER_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_INNGEST_CONSUMER_PING_LOG"
    return 0
  fi
  [ -n "$URL" ] || { echo "[inngest-consumer-probe] WARN: INNGEST_CONSUMER_URL unset — the registry is servable but the beat cannot be sent, so the monitor will alarm on a HEALTHY host. Check /etc/default/inngest-consumer-probe." >&2; return 0; }
  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null \
    || curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null \
    || echo "[inngest-consumer-probe] WARN: heartbeat ping FAILED (registry servable, url_present=yes) — the monitor will alarm on a healthy host." >&2
}

_fault() {
  # Rate-limited fault classification -> stderr -> journald (SyslogIdentifier=inngest-consumer-probe)
  # -> vector Source 4 -> Better Stack. See the QUOTA note in the header for why this is bounded.
  # The rate-limit governs the LINE only, never the ping decision, so a suppressed line can never
  # convert a dark host into a green one.
  local now last
  now=$(date +%s 2>/dev/null || echo 0)
  last=0
  [ -f "$FAULT_MARKER" ] && last=$(cat "$FAULT_MARKER" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -ge "$FAULT_INTERVAL" ]; then
    echo "[inngest-consumer-probe] $1" >&2
    printf '%s\n' "$now" > "$FAULT_MARKER" 2>/dev/null || true
  fi
}

# fetch_functions() comes from the sourced script: fixture-or-curl, and on a transport failure it
# yields the `__FETCH_FAILED__` error envelope rather than an empty string.
BODY="$(fetch_functions)"

# Count the registered entries, or "nan" for any shape that is not a well-formed array. jq indexes
# null as null (so an `{"errors":…,"data":null}` envelope yields type "null"), and hard-errors on a
# bare array — both land on "nan" and are classified below rather than being read as a count.
COUNT="nan"
if _parsed="$(printf '%s' "$BODY" | jq -r '(.data.functions // null) | if type == "array" then length else "nan" end' 2>/dev/null)"; then
  COUNT="$_parsed"
fi

case "$COUNT" in
  ''|*[!0-9]*)
    # Not a countable registry: discriminate the failure so the journal line says WHY.
    # Herestrings, not pipes: `producer | grep -q` takes SIGPIPE on an early match, which under a
    # re-armed pipefail would invert this classification (documented trap; pipefail is off above,
    # and this shape keeps it correct regardless).
    if grep -q '__FETCH_FAILED__' <<<"$BODY"; then
      _fault "SUPPRESS ping: UNREACHABLE — no TCP listener at ${GQL_URL} (connection refused/timeout). This is the #7228 signature: the dedicated inngest host is up but never bound :8288. Absence-of-ping will alarm."
    elif jq -e '((.errors // []) | length) > 0' <<<"$BODY" >/dev/null 2>&1; then
      _fault "SUPPRESS ping: WEDGED — ${GQL_URL} answered with a GraphQL error envelope rather than a registry. Absence-of-ping will alarm."
    else
      _fault "SUPPRESS ping: UNEXPECTED SHAPE from ${GQL_URL} — the response is neither a function array nor a GraphQL error envelope (a 5xx body or a proxy page would look like this). Refusing to go green over a response we did not understand. Absence-of-ping will alarm."
    fi
    exit 0
    ;;
esac

if [ "$COUNT" -gt 0 ]; then
  _ping "$URL"
  exit 0
fi

# A well-formed, EMPTY registry. The endpoint serves, so every reachability check passes — and the
# scheduler owns nothing. Suppressing here is what makes this probe an assertion about SERVICE
# rather than about liveness, and it is the arm inngest-consumer-probe.test.sh mutation-proves.
_fault "SUPPRESS ping: EMPTY REGISTRY — ${GQL_URL} served a well-formed but EMPTY function list. The endpoint is alive and owns no functions, so a reachability check would read this as healthy. Absence-of-ping will alarm."
exit 0
