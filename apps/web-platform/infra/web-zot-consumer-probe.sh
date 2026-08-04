#!/usr/bin/env bash
set -u
# --- #6438 §1: zot CONSUMER-perspective serviceability probe (the "L3" probe) -----------------
# Runs ON the web host and verifies it can actually SERVE an image from the zot registry
# (10.0.1.30:5000) over the private NIC — the gap L1/L2 (#6415/ADR-115) + #6540 (registry self-
# ping) structurally cannot see: "the private net is broken from a CONSUMER's perspective while the
# registry thinks its own NIC is fine." On success it pings a Better Stack heartbeat; absence
# alarms. The failure this prevents is #6400 — a silent-for-14-days degradation where every health
# signal stayed green.
#
# AUTHENTICATED SERVICEABILITY, not a liveness ping (Kieran P1 / P1-7). zot runs `defaultPolicy:[]`
# — an ANONYMOUS request gets 401 on EVERY path including a real repo path (auth is enforced before
# the repo lookup, cloud-init-registry.yml:341-345). So a bare `/v2/` 401-or-200 check proves only
# that the auth gate answers, NEVER that the store SERVES. This probe presents the on-host zot
# htpasswd Basic auth (ZUSER/ZTOK = ZOT_PULL_USER/ZOT_PULL_TOKEN, the same creds cloud-init uses for
# `docker login`) and reads EACH listed repository's tag list. ZOT_PROBE_REPO is a COMMA-separated
# LIST (#7144 task 5a); the per-repo classification is:
#   200 = servable                       -> this repo is OK
#   404 = store empty / detached         -> the #6400-inside-the-probe case (a servable auth gate
#                                            over a dead store)
#   401 = auth broke                     -> probe-auth misconfig; outranks every other fault
#   5xx = wedged
#   000 = unreachable (private net down) -> the L3 target signal
# and the RUN-LEVEL verdict aggregates them ALL-MUST-SERVE:
#   every repo 200            -> ping the heartbeat (healthy)
#   any repo 401              -> suppress AND exit 3 (HARD failure, NOT "alive"): absence-of-ping
#                                alone cannot distinguish a probe-auth misconfig from a down host
#   any other non-200         -> suppress the ping so absence alarms; the message NAMES the repo
#   list has no non-empty repo -> FATAL exit 1 (never a silent green)
# A 200 on one repo therefore pings NOTHING unless every repo is 200 — that is the point: an
# any-of rule would let a servable web repo mask an unservable bootstrap repo.
#
# NO `curl -f`: -f makes curl exit non-zero and emit NOTHING on 4xx/5xx, collapsing every non-200
# into an empty CODE and destroying the classification. The `-w '%{http_code}'` capture is the whole
# point. -u presents Basic auth; -m 10 bounds the probe; -o /dev/null discards the body.
#
# CONFIG IS ENV (delivered both by the SSH provisioner to web-1 AND baked verbatim into cloud-init
# for future hosts): ZOT_ENDPOINT + ZOT_PROBE_REPO (comma-separated) from
# /etc/default/web-zot-consumer-probe;
# ZUSER/ZTOK/WEB_ZOT_CONSUMER_URL from the doppler-run env.
#
# TEST SEAM: SOLEUR_ZOT_PROBE_STATUS_OVERRIDE injects a CODE (or a positional comma-list, one per
# repo; a single code broadcasts to all) so the classification branches are
# unit-testable without a live registry; SOLEUR_ZOT_PROBE_PING_LOG re-routes the heartbeat ping to
# a file so a test can assert ping/no-ping. Neither is ever set in production. The -u/-f behavioral
# properties are covered by a separate mock-HTTP-server test (web-zot-consumer-probe.test.sh).

ENDPOINT="${ZOT_ENDPOINT:-10.0.1.30:5000}"
REPO="${ZOT_PROBE_REPO:-}"
ZUSER="${ZUSER:-${ZOT_PULL_USER:-}}"
ZTOK="${ZTOK:-${ZOT_PULL_TOKEN:-}}"
URL="${WEB_ZOT_CONSUMER_URL:-}"
# Happy-path stderr is shipped off-box via Vector Source 4 (SyslogIdentifier=web-zot-consumer-probe);
# the heartbeat ping is the actual off-box liveness signal, so the "servable (200)" narration is
# redundant there and pure quota cost at 60s cadence. Gate it behind a debug flag (default OFF);
# fault classifications below always emit. Set SOLEUR_PROBE_VERBOSE=1 in /etc/default for on-host debug.
VERBOSE="${SOLEUR_PROBE_VERBOSE:-}"

if [ -z "$REPO" ]; then
  echo "[zot-probe] FATAL: ZOT_PROBE_REPO unset (source /etc/default/web-zot-consumer-probe) — cannot probe serviceability without a real repository path." >&2
  exit 1
fi
if [ -z "$ZUSER" ] || [ -z "$ZTOK" ]; then
  echo "[zot-probe] FATAL: ZOT_PULL_USER/ZOT_PULL_TOKEN unset (run under 'doppler run --project soleur --config prd') — an anonymous probe gets 401 on every path and proves nothing." >&2
  exit 1
fi

_ping() {
  # Route to the test log if seamed; else fire the real heartbeat ping (two attempts).
  if [ -n "${SOLEUR_ZOT_PROBE_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_ZOT_PROBE_PING_LOG"
    return 0
  fi
  [ -n "$URL" ] || { echo "[zot-probe] WARN: WEB_ZOT_CONSUMER_URL unset — servable but cannot ping." >&2; return 0; }
  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || echo "[zot-probe] WARN: heartbeat ping FAILED (servable=200, url_present=yes)" >&2
}

_canary() {
  # Positive-control canary for vector Source 4 (journald→Better Stack) liveness (#6438/#6548,
  # luks-#6604 pattern). The probes are otherwise SILENT-ON-SUCCESS, and the heartbeats + the NIC
  # guard's SOLEUR_PRIVATE_NIC line ship by DIRECT curl (independent of vector) — so a dead vector
  # agent on web-1 (the exact gap this fix repairs) would be INVISIBLE. This emits a benign tagged
  # stderr row on EVERY run (called before the HTTP-code classification), which journald ships under
  # SyslogIdentifier=web-zot-consumer-probe via Source 4 — making Source-4 liveness a STEADY-STATE
  # signal (its ABSENCE = the recurrence). It is deliberately INDEPENDENT of zot serviceability: a
  # true positive control must not vanish when the thing it monitors alongside (zot) is itself down,
  # or a zot outage would misread as a Source-4 death. One probe carries it: a dead agent kills ALL
  # Source-4 tags, so a single canary proves the whole journald→vector path. Rate-limited to ~30min
  # (marker in /run tmpfs, resets on reboot) — half the discoverability query window so ≥1 canary is
  # always in a 1h `--since` window (no boundary dead-zone), while still well under the 60s timer
  # cadence's quota the VERBOSE gate deliberately avoids.
  local m="${SOLEUR_PROBE_CANARY_MARKER:-/run/web-zot-consumer-probe.canary}" now last
  now=$(date +%s 2>/dev/null || echo 0)
  last=0
  [ -f "$m" ] && last=$(cat "$m" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -ge 1800 ]; then
    echo "[zot-probe] SOLEUR_PROBE_CANARY web-zot-consumer-probe source4_live=1 ts=$now — vector Source 4 reachable (positive control; independent of zot serviceability)." >&2
    printf '%s\n' "$now" > "$m" 2>/dev/null || true
  fi
}

# Source-4 liveness beacon — fires on EVERY run (rate-limited), independent of the zot verdict below,
# so a zot outage is never misread as a dead vector agent. See _canary().
_canary

# --- Per-repo probe + CONSERVATIVE aggregation (#7144 task 5a) --------------------------------
# ZOT_PROBE_REPO is a COMMA-separated list; a single repo (no comma) behaves exactly as before.
# Comma is the separator precisely because it cannot occur in an OCI repository name, so no
# quoting/whitespace question arises in the systemd EnvironmentFile that carries this value.
#
# Aggregation is deliberately ALL-MUST-SERVE, not any-of: the whole point of adding the bootstrap
# repo is that a digest zot cannot serve the HOST is a fatal fresh boot. An any-of rule would let a
# servable web repo mask an unservable bootstrap repo — reproducing the #6400 "every signal green
# while the thing is broken" failure this probe family exists to end.
IFS=',' read -r -a _REPOS <<< "$REPO"
_OVERRIDES=()
[ -n "${SOLEUR_ZOT_PROBE_STATUS_OVERRIDE:-}" ] && IFS=',' read -r -a _OVERRIDES <<< "$SOLEUR_ZOT_PROBE_STATUS_OVERRIDE"

auth_broke=""
unservable=""
probed=0

for _i in "${!_REPOS[@]}"; do
  r="${_REPOS[$_i]}"
  [ -n "$r" ] || continue
  probed=$((probed + 1))
  if [ "${#_OVERRIDES[@]}" -gt 0 ]; then
    # A single injected code applies to EVERY repo (preserves the pre-#7144 single-repo seam);
    # a comma-list injects per-repo codes positionally so mixed outcomes are testable offline.
    if [ "${#_OVERRIDES[@]}" -eq 1 ]; then CODE="${_OVERRIDES[0]}"; else CODE="${_OVERRIDES[$_i]:-000}"; fi
  else
    # NO -f (see header). -u presents Basic auth; -w captures the HTTP code; -m bounds it; a
    # transport failure (unreachable private net) yields the curl default 000.
    CODE=$(curl -s -u "$ZUSER:$ZTOK" -o /dev/null -w '%{http_code}' -m 10 "http://${ENDPOINT}/v2/${r}/tags/list" 2>/dev/null || echo 000)
    [ -n "$CODE" ] || CODE=000
    # On a TRANSPORT failure curl writes 000 via -w AND exits non-zero, so the `|| echo 000` above
    # appends a SECOND one and CODE becomes 000000 — which misses the 000) arm and lands in the
    # catch-all. Not hypothetical: Better Stack carries live `unexpected code 000000` rows from
    # BOTH web hosts, i.e. the documented L3 target-signal branch has never once executed in
    # production. Normalising here rather than dropping the `|| echo 000` deliberately: the
    # fallback is what the (c) -f mutation test uses to prove the absence of `curl -f` is
    # load-bearing, and that coupling should not be broken as a side effect of this fix.
    [ "$CODE" = "000000" ] && CODE=000
  fi

  case "$CODE" in
    200)
      [ -n "$VERBOSE" ] && echo "[zot-probe] servable (200): ${ENDPOINT}/v2/${r}/tags/list" >&2
      ;;
    401)
      auth_broke="${auth_broke}${r}(401) "
      ;;
    404)
      unservable="${unservable}${r}(404 EMPTY/DETACHED) "
      ;;
    000)
      unservable="${unservable}${r}(000 UNREACHABLE) "
      ;;
    5??)
      unservable="${unservable}${r}(${CODE} WEDGED) "
      ;;
    *)
      # Phrase pinned: web-zot-consumer-probe.test.sh (c) greps the literal "unexpected code" to
      # prove a corrupted capture (the -f mutant) lands in this catch-all rather than a clean branch.
      unservable="${unservable}${r}(unexpected code ${CODE}) "
      ;;
  esac
done

if [ "$probed" -eq 0 ]; then
  echo "[zot-probe] FATAL: ZOT_PROBE_REPO contained no non-empty repository path — cannot probe serviceability." >&2
  exit 1
fi

# 401 outranks every other fault: absence-of-ping alone cannot distinguish a probe-auth misconfig
# from a genuinely down host, so it must fail LOUD rather than merely suppress.
if [ -n "$auth_broke" ]; then
  echo "[zot-probe] HARD FAILURE: 401 — the probe's Basic auth (ZOT_PULL_USER/ZOT_PULL_TOKEN) BROKE for: ${auth_broke%% }. This is NOT 'alive'; suppressing ping AND failing loud so it is not read as a down host." >&2
  exit 3
fi

if [ -n "$unservable" ]; then
  echo "[zot-probe] SUPPRESS ping: ${probed} repo(s) probed, NOT ALL servable — ${unservable%% }. Absence-of-ping will alarm." >&2
  exit 0
fi

_ping "$URL"
[ -n "$VERBOSE" ] && echo "[zot-probe] all ${probed} repo(s) servable — pinged heartbeat." >&2
exit 0
