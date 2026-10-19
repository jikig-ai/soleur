#!/usr/bin/env bash
set -u
# Refuse to run under shell tracing while the pull credential is set: `set -x` would write the
# Basic-auth token into the journal that Vector ships off-box (#7797).
case "$-" in
  *x*)
    if [ -n "${ZOT_PULL_TOKEN:+x}${ZTOK:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
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
# `docker login`) and reads a REAL repository's tag list. Classification:
#   200 = servable                       -> ping the heartbeat (healthy)
#   404 = store empty / detached         -> the #6400-inside-the-probe case: SUPPRESS the ping so
#                                            absence alarms (a servable auth gate over a dead store)
#   401 = auth broke                     -> HARD failure (NOT "alive"): suppress AND exit non-zero,
#                                            because absence-of-ping alone cannot distinguish a
#                                            probe-auth misconfig from a genuinely down host
#   5xx = wedged                         -> suppress (absence alarms)
#   000 = unreachable (private net down) -> suppress (absence alarms — this is the L3 target signal)
#
# NO `curl -f`: -f makes curl exit non-zero and emit NOTHING on 4xx/5xx, collapsing every non-200
# into an empty CODE and destroying the classification. The `-w '%{http_code}'` capture is the whole
# point. The stdin `user =` config presents Basic auth; -m 10 bounds the probe; -o /dev/null discards the body.
#
# CONFIG IS ENV (delivered both by the SSH provisioner to web-1 AND baked into cloud-init for future
# hosts; web-1 gets the PINNED list, a host born later gets the BARE list, see the pin paragraph): ZOT_ENDPOINT + ZOT_PROBE_REPO from /etc/default/web-zot-consumer-probe;
# ZUSER/ZTOK/WEB_ZOT_CONSUMER_URL from the doppler-run env.
#
# ZOT_PROBE_REPO IS A COMMA-SEPARATED LIST (#7258). A host pulls MORE than one platform repository
# (the web image and the inngest bootstrap image), so a probe of one repo certifies only that repo.
# Each element is classified by the table above; the heartbeat is pinged ONLY when EVERY element is
# 200 (all-must-pass: a conjunction cannot mask a faulting repo, and one heartbeat per host is kept).
#   - empty elements are skipped (a trailing comma is permitted); a newline anywhere in the value, an
#     element outside the OCI repository-name alphabet (lowercase a-z 0-9 and . _ / -, and no path
#     component that starts or ends with a separator, which also refuses `..`, `a/./b` and `a/.`), or a list
#     with no non-empty element, is FATAL exit 1 before any curl, ping or marker (a newline would otherwise
#     let `read` drop every later element and silently shrink the conjunction; a `?`, `#`, `[`, `{` or a dot
#     segment would alter the request path rather than name a repository);
#   - a 401 on ANY element exits 3 (HARD), and the other elements are still probed, so no repo's
#     line is lost to an early exit;
#   - every fault line ends with repo=<path>; a rate-limited (30 min) SOLEUR_ZOT_PROBE_VERDICT marker
#     per repo (code, verdict, pin_verdict) proves a HEALTHY run per repo from telemetry, because a healthy probe
#     is otherwise silent. Fault lines are NOT rate-limited (one per faulting repo per 60 s run, at most
#     2880 rows/day on a full outage against 1440 for one repo; ADR-184 recorded ~19.9k of the 25k/day
#     Better Stack budget used in June 2026, so ~5.1k/day of headroom and a full outage takes about 56%);
#   - worst case is 10 s per request (curl -m 10): two bare repos is 20 s with no ping, 40 s to a ping (two
#     curl -m 10 attempts), both under the 60 s timer cadence (OnUnitActiveSec=60s in the timer unit).
#     See the pin paragraph for web-1's list.
#
# A PIN (#10004). An element may also be `<repo>@sha256:<64 lowercase hex>` (nothing else: no :tag, no other
# hash). tags/list answering 200 proves the repository is LISTABLE, not that the digest a fresh host pulls (the
# ZIREF pin in cloud-init) still resolves: zot retention keeps only the 5 most recent v.* tags with
# deleteUntagged, and measured against the pinned zot image (2026-10-11) an evicted tag leaves tags/list at 200
# while HEAD of its digest, and of the tag, is 404. So for an element that carries a digest AND whose tags/list
# answered 200, the probe sends ONE authenticated `HEAD /v2/<repo>/manifests/<digest>` (no Accept header
# needed: an OCI index digest answered 200 with none) and classifies it like tags/list: 200 pinned, 404
# pin-missing (SUPPRESS, the fault line says the pinned manifest is MISSING), 401 HARD (exit 3), 000 / 5xx /
# anything else suppress and name the code. A pin fault sets the SAME accumulators as a tags/list fault, so it
# is never cleared by a healthy neighbour. When tags/list was not 200 the pin is not HEADed (pin_verdict=skipped):
# that saves a second timeout and a duplicate fault line during an outage. The marker row ends with
# pin_verdict=<none|skipped|pinned|pin-missing|auth-broke|unreachable|wedged|unexpected> (none = a bare element).
# Worst case for web-1's list (the web repo bare, the bootstrap repo pinned): a 200 tag list then a hanging HEAD
# is 20 s for the pinned repo plus 10 s for the bare one = 30 s with no ping, 50 s to a ping (two curl -m 10
# ping attempts); every other host's bare list stays at 10 s per repo. Budget rule: each pinned repo costs up to
# 20 s and each bare repo 10 s, against 60 s minus the 20 s ping, so a third pinned element on one host would
# exceed the cadence. A pin fault REPLACES that repo's tags/list fault (the HEAD runs only when tags/list was
# 200), so the 2880 rows/day full-outage ceiling is unchanged and a chronic pin-missing state alone is 1440.
# Only web-1 carries a pin (web-probe.tf: local.zot_probe_repo_pinned feeds server.tf's two web-1 sites);
# born hosts keep the bare list because a pin
# baked into an env file at birth could never be updated. The web image has no committed digest (#10044), so
# its element stays bare and says pin_verdict=none. A manifest HEAD does not prove the blobs: the build
# workflow's `crane validate` is the only MIRROR-time blob check and it is a non-blocking dark-launch on the
# build's own tag, and the registry-restore engine validates blobs only at restore time, so nothing checks the
# blobs of the pinned digest in steady state.
#
# TEST SEAM: SOLEUR_ZOT_PROBE_STATUS_OVERRIDE injects a tags/list CODE (a comma list is positional over the
# NON-EMPTY repo elements in order; a missing position reads 000; pin HEADs are NOT seamed, the suite drives
# them through a mock registry and a stub curl) so the classification branches are
# unit-testable without a live registry; SOLEUR_ZOT_PROBE_PING_LOG re-routes the heartbeat ping to
# a file so a test can assert ping/no-ping; SOLEUR_PROBE_REFUSAL_MARKER relocates the heartbeat-URL refusal's own
# stamp (default /run/web-zot-consumer-probe.refusal, like this file's other marker seams). None is ever set in production. The auth/-f behavioral
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

# The heartbeat URL's PATH is the credential, so it must not ride curl's argument list (readable by every local
# user in /proc/<pid>/cmdline; ADR-280, #9757): it reaches curl on the stdin config (`--config -`), `--disable`
# (first, so no ~/.curlrc is read as root) and `--noproxy '*'` confine the transport (lint Rule D); `-g` stops a URL
# with [ ] or { } from printing itself in curl's glob-parse error. This host has no checkout, so this is the inline
# form of the library. The value is judged BEFORE any request, with no trimming: a scheme other than https://, an
# empty rest, or any byte outside [A-Za-z0-9._~:/?&=%+-] (a quote, backslash or newline would add directives to the
# config grammar) is refused, with zero requests, one value-free marker on stderr per hour (see _refused) and the
# same fail-soft exit as every other arm.
_hb_url_ok() {
  local LC_ALL=C
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|*[!A-Za-z0-9._~:/?\&=%+-]*) return 1 ;; esac
}
# One call = one attempt = one fresh process substitution (a substitution is consumed once, so a second attempt
# sharing the first one's would read EOF and send no URL).
_hb_curl() { curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - 2>/dev/null < <(printf 'url = "%s"\n' "$URL"); }

_ping() {
  # Route to the test log if seamed; else fire the real heartbeat ping (two attempts).
  if [ -n "${SOLEUR_ZOT_PROBE_PING_LOG:-}" ]; then
    printf 'PING %s\n' "$1" >> "$SOLEUR_ZOT_PROBE_PING_LOG"
    return 0
  fi
  [ -n "$URL" ] || { echo "[zot-probe] WARN: WEB_ZOT_CONSUMER_URL unset — servable but cannot ping." >&2; return 0; }
  if ! _hb_url_ok "$URL"; then
    _refused
    return 0
  fi
  _hb_curl || _hb_curl || echo "[zot-probe] WARN: heartbeat ping FAILED (servable=200, url_present=yes)" >&2
}

# A refused heartbeat URL (#9757): fail-soft, never an argv fallback (no ping, the caller's exit status is
# unchanged), and loud but bounded. Ruled (ADR-280 PR C follow-up): the refusal has its OWN stamp (never the
# canary's or the per-repo marker's, which a healthy tick refreshes), a 3600 s window, and fails OPEN when the
# stamp cannot be written (emit on every tick: loud, never silent). The marker and the WARN both sit inside the
# limiter. The reason is control_char when the value holds a control character, else token_shape; the value is
# never echoed.
_refused() {
  local LC_ALL=C
  local m="${SOLEUR_PROBE_REFUSAL_MARKER:-/run/web-zot-consumer-probe.refusal}" now reason
  _window_open "$m" 3600 || return 0
  now=$(date +%s 2>/dev/null || echo 0)
  reason=token_shape
  case "$URL" in *[[:cntrl:]]*) reason=control_char ;; esac
  echo "SOLEUR_CREDENTIAL_REFUSED script=web-zot-consumer-probe reason=$reason var=WEB_ZOT_CONSUMER_URL" >&2
  echo "[zot-probe] WARN: heartbeat URL refused (servable, no ping sent)" >&2
  _stamp "$m" "$now"
}

_canary() {
  # Positive-control canary for vector Source 4 (journald→Better Stack) liveness (#6438/#6548,
  # luks-#6604 pattern). The probes are otherwise SILENT-ON-SUCCESS, and the heartbeats + the NIC
  # guard's SOLEUR_PRIVATE_NIC line ship by DIRECT curl (independent of vector) — so a dead vector
  # agent on web-1 (the exact gap this fix repairs) would be INVISIBLE. This emits a benign tagged
  # stderr row on EVERY run (after the fault lines and before the exit decision; also the first and only
  # row of --canary-only), which journald ships under
  # SyslogIdentifier=web-zot-consumer-probe via Source 4 — making Source-4 liveness a STEADY-STATE
  # signal (its ABSENCE = the recurrence). It is deliberately INDEPENDENT of zot serviceability: a
  # true positive control must not vanish when the thing it monitors alongside (zot) is itself down,
  # or a zot outage would misread as a Source-4 death. One probe carries it: a dead agent kills ALL
  # Source-4 tags, so a single canary proves the whole journald→vector path. Rate-limited to ~30min
  # (marker in /run tmpfs, resets on reboot) — half the discoverability query window so ≥1 canary is
  # always in a 1h `--since` window (no boundary dead-zone), while still well under the 60s timer
  # cadence's quota the VERBOSE gate deliberately avoids.
  local m="${SOLEUR_PROBE_CANARY_MARKER:-/run/web-zot-consumer-probe.canary}" now
  _window_open "$m" || return 0
  now=$(date +%s 2>/dev/null || echo 0)
  echo "[zot-probe] SOLEUR_PROBE_CANARY web-zot-consumer-probe source4_live=1 ts=$now — vector Source 4 reachable (positive control; independent of zot serviceability)." >&2
  _stamp "$m" "$now"
}

# The ONE write of a rate-limit marker (canary, per-repo and refusal markers share it). Best-effort: a /run that
# cannot be written must never fail the probe, and the unwritten marker only makes the next run emit again.
_stamp() {  # <marker-file> <epoch>
  printf '%s\n' "$2" > "$1" 2>/dev/null || true
}

# One rate-limit helper shared by the canary, the per-repo markers (#7258) and the heartbeat-URL refusal: true (return 0) when a
# new emit is due, i.e. the marker file is missing, empty, non-numeric, wider than 10 digits (not a
# plausible epoch, and a guard against integer overflow), DATED IN THE FUTURE, or older than the window
# (1800 s unless the caller passes a second argument; the heartbeat refusal passes 3600), or
# the clock is unreadable. Every doubtful state fails toward EMITTING. The future-dated case is a
# deliberate change from the canary's old inline test, where `now - last` went negative and the canary
# stayed silent until the clock caught up (a latent silent-canary defect; the sibling
# inngest-consumer-probe.sh `_fault` still has that shape and is a separate script on a separate host,
# deliberately not touched here). The marker lives in /run (tmpfs), so a reboot resets it, which is
# intended.
_window_open() {  # <marker-file> [window seconds, default 1800]
  local m="$1" now last
  now=$(date +%s 2>/dev/null || echo 0)
  [ "$now" -gt 0 ] 2>/dev/null || return 0
  last=0
  [ -f "$m" ] && last=$(cat "$m" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) return 0 ;; esac
  [ "${#last}" -le 10 ] || return 0
  last=$((10#$last))
  [ "$last" -gt "$now" ] && return 0
  [ $((now - last)) -ge "${2:-1800}" ]
}

# Per-repo marker: one row per repo per window, whatever the verdict, so "both repos healthy" is a
# positive observation rather than the absence of a fault line. Reads the R_NAME/R_CODE/R_VERDICT/R_PINV
# arrays the probe loop fills, and runs BEFORE the exit decision so the 401 path emits it too.
_repo_markers() {
  local m="${SOLEUR_PROBE_REPOS_MARKER:-/run/web-zot-consumer-probe.repos}" now i
  _window_open "$m" || return 0
  now=$(date +%s 2>/dev/null || echo 0)
  for i in "${!R_NAME[@]}"; do
    echo "[zot-probe] SOLEUR_ZOT_PROBE_VERDICT repo=${R_NAME[$i]} code=${R_CODE[$i]} verdict=${R_VERDICT[$i]} ts=$now pin_verdict=${R_PINV[$i]}" >&2
  done
  _stamp "$m" "$now"
}

# --- #7103 R3 4.3: the canary must not depend on the credential it certifies ---------------
# `--canary-only` emits the beacon and exits, so the unit can invoke it from an ExecStartPre
# that runs OUTSIDE the `doppler run` wrapper.
#
# THE DEFECT THIS CLOSES. The unit's ExecStart is
#   doppler run --project soleur --config prd -- bash -c '... exec web-zot-consumer-probe.sh'
# so on a dead prd token `doppler run` exits before the inner bash ever execs and the canary is
# never emitted. The positive control for "is vector shipping?" was therefore gated behind
# exactly the credential whose failure it is used to certify — and its absence reads as
# "vector is dead" rather than "the token is dead". That is the reading that made #7095's
# telemetry unfalsifiable.
#
# It sits BEFORE the FATAL guards below because those require the credentials this mode exists
# to run without. The guards moved down rather than the check moving up so that a canary-only
# invocation cannot be turned into a silent no-op by a future guard added above it.
if [ "${1:-}" = "--canary-only" ]; then
  _canary
  exit 0
fi

if [ -z "$REPO" ]; then
  echo "[zot-probe] FATAL: ZOT_PROBE_REPO unset (source /etc/default/web-zot-consumer-probe) — cannot probe serviceability without a real repository path." >&2
  exit 1
fi
# Split the list. Empty elements are skipped. A newline in the value, an element that holds whitespace or
# falls outside the repository-name alphabet, and a list with nothing in it are all FATAL here, before
# any curl, ping or marker.
R_NAME=(); R_DIG=(); R_CODE=(); R_VERDICT=(); R_PINV=()
# `read` takes only the first line: a newline in the value would drop every later element and silently
# shrink the all-must-pass conjunction, so refuse it before the split.
case "$REPO" in
  *$'\n'*)
    echo "[zot-probe] FATAL: ZOT_PROBE_REPO contains a newline — a later repository would be silently dropped from the probe; probe NOT run." >&2
    exit 1
    ;;
esac
IFS=',' read -r -a _RAW <<<"$REPO"
# The ONE digest-ref shape (#10004): `<repo>@sha256:<64 lowercase hex>`, held in a variable so the match is
# the regex, not a glob, and run under LC_ALL=C so [0-9a-f] is the ASCII range.
_DIGEST_RE='^sha256:[0-9a-f]{64}$'
_digest_ok() { local LC_ALL=C; [[ ${1:-} =~ $_DIGEST_RE ]]; }
for _e in "${_RAW[@]}"; do
  [ -n "$_e" ] || continue
  case "$_e" in
    *[[:space:]]*)
      echo "[zot-probe] FATAL: ZOT_PROBE_REPO element contains whitespace — refusing to build a URL from it; probe NOT run." >&2
      exit 1
      ;;
  esac
  # Split a digest ref off the element. Branch on `*@*` first: `${_e#*@}` returns the WHOLE string when there is
  # no `@`. A second `@` stays in the remainder and fails the digest match; an empty remainder (`repo@`) fails
  # it too. A `:tag` is outside the repository alphabet below, so `repo:tag@sha256:...` is refused as a name.
  _r="$_e"; _d=""
  if [[ $_e == *@* ]]; then
    _r="${_e%%@*}"; _d="${_e#*@}"
    if ! _digest_ok "$_d"; then
      echo "[zot-probe] FATAL: ZOT_PROBE_REPO element is not a valid repository name or digest ref (<repo> or <repo>@sha256:<64 lowercase hex> only) — refusing to build a URL from it; probe NOT run." >&2
      exit 1
    fi
  fi
  case "$_r" in
    # OCI repository-name alphabet only (the web element derives from var.image_name, an operator value):
    # a `?`, `#`, `[`, `{` or a dot segment would change the request path or make curl glob, not name a
    # repository. OCI components start and end alphanumeric, so no component may start or end with . _ -.
    # The empty repository (`@sha256:...`) is refused here too.
    ''|*[!a-z0-9._/-]*|*..*|/*|*/|*//*|[._-]*|*[._-]|*/[._-]*|*[._-]/*)
      echo "[zot-probe] FATAL: ZOT_PROBE_REPO element is not a valid repository name or digest ref (lowercase a-z 0-9 . _ / - only, then an optional @sha256:<64 hex>) — refusing to build a URL from it; probe NOT run." >&2
      exit 1
      ;;
  esac
  R_NAME+=("$_r"); R_DIG+=("$_d")
done
if [ "${#R_NAME[@]}" -eq 0 ]; then
  echo "[zot-probe] FATAL: ZOT_PROBE_REPO has no non-empty element — nothing to probe; probe NOT run." >&2
  exit 1
fi
if [ -z "$ZUSER" ] || [ -z "$ZTOK" ]; then
  echo "[zot-probe] FATAL: ZOT_PULL_USER/ZOT_PULL_TOKEN unset (run under 'doppler run --project soleur --config prd') — an anonymous probe gets 401 on every path and proves nothing." >&2
  exit 1
fi
# The credential reaches curl as a `user = "<user>:<token>"` line on stdin (`--config -`), never on argv
# (/proc/<pid>/cmdline is readable by every local user). A value that could close the quoted string or
# start a new config directive (a quote, a backslash, any control char incl. newline) cannot be carried
# safely, so it takes the same FATAL exit-1 channel as an unset credential (value never printed).
_cfg_ok() { local LC_ALL=C; case "${1:-}" in ''|*'"'*|*\\*|*[[:cntrl:]]*) return 1 ;; esac; }
if ! _cfg_ok "$ZUSER" || ! _cfg_ok "$ZTOK"; then
  echo "[zot-probe] FATAL: ZOT_PULL_USER/ZOT_PULL_TOKEN contains a character that cannot be sent safely (double quote, backslash or control char) — refusing to build the curl config; probe NOT run." >&2
  exit 1
fi

# The override seam is positional over the non-empty repo elements, in order; a missing or empty
# position reads 000. A single code is therefore the one-repo case, unchanged.
_OVR=()
[ -z "${SOLEUR_ZOT_PROBE_STATUS_OVERRIDE:-}" ] || IFS=',' read -r -a _OVR <<<"$SOLEUR_ZOT_PROBE_STATUS_OVERRIDE"

unservable=0
auth_broke=0

# The ONE request site (#10004), used by tags/list (GET) and by the pinned-manifest HEAD (-I).
# NO -f (see header), NO --retry (a probe whose absence is the alarm must not retry its way to green).
# `user = ...` on the stdin config presents Basic auth (the -u equivalent, kept off argv); -w captures the HTTP
# code; -m bounds it; a transport failure (unreachable private net) yields the curl default 000.
# Do NOT forward $@ / $1 inside the curl line: the credential-trace lint (Rule D) would then splice the call
# sites as wrapper commands and judge the unpinned ${ENDPOINT} (#7873), which main's masked `$(...)` curl never
# was. The arguments are read into locals on the line above it instead.
_fetch() {  # <path under /v2/> [-I]  -> sets CODE
  local _p="$1" _flag="${2:-}"
  CODE=$(curl --disable --noproxy '*' ${_flag:+-I} -s -o /dev/null -w '%{http_code}' -m 10 --config - "http://${ENDPOINT}/v2/${_p}" \
    < <(printf 'user = "%s:%s"\n' "$ZUSER" "$ZTOK") 2>/dev/null || echo 000)
  [ -n "$CODE" ] || CODE=000
  # (#7262) On a transport failure curl prints `000` via -w AND exits non-zero, so the `|| echo 000` above
  # appends a second one and CODE is `000000`, which would miss the `000)` arm in _classify. Normalize ONLY
  # that exact value: an HTTP code followed by a curl failure (e.g. `404000` when -f is injected) must stay
  # in the catch-all, because zot did answer.
  case "$CODE" in 000000) CODE=000 ;; esac
}

# One classification for both requests. Args: <code> <what: tags|pin> <repo> <ref|empty>. Sets VERDICT and the
# SAME unservable/auth_broke accumulators for either request, so a pin fault can never be a parallel flag the
# aggregation does not read. The tags wording is unchanged (ci-deploy.sh and the runbook cite it); a pin fault
# line adds ref= BEFORE the trailing repo=.
_classify() {
  local code="$1" what="$2" r="$3" ref="$4" tail path
  if [ "$what" = pin ]; then tail="ref=${ref} repo=${r}"; path="manifests/${ref#*@}"; else tail="repo=${r}"; path="tags/list"; fi
  case "$code" in
    200)
      VERDICT=servable; [ "$what" = pin ] && VERDICT=pinned
      [ -n "$VERBOSE" ] && echo "[zot-probe] ${VERDICT} (200): ${ENDPOINT}/v2/${r}/${path}" >&2
      ;;
    404)
      unservable=1
      if [ "$what" = pin ]; then
        VERDICT=pin-missing
        echo "[zot-probe] SUPPRESS ping: 404 — pinned manifest ${ref} is MISSING from zot while tags/list still answered 200 (the pinned digest was evicted, never mirrored, or garbage-collected; a fresh host pull of it would fail). Absence-of-ping will alarm. ${tail}" >&2
      else
        VERDICT=empty
        echo "[zot-probe] SUPPRESS ping: 404 — zot answered auth but the store is EMPTY/DETACHED for ${r} (the #6400-inside-the-probe case). Absence-of-ping will alarm. ${tail}" >&2
      fi
      ;;
    401)
      VERDICT=auth-broke; auth_broke=1
      echo "[zot-probe] HARD FAILURE: 401 — the probe's Basic auth (ZOT_PULL_USER/ZOT_PULL_TOKEN) BROKE. This is NOT 'alive'; suppressing ping AND failing loud so it is not read as a down host. ${tail}" >&2
      ;;
    000)
      VERDICT=unreachable; unservable=1
      echo "[zot-probe] SUPPRESS ping: 000 — ${ENDPOINT} UNREACHABLE (private-net path to zot down — the L3 target signal). Absence-of-ping will alarm. ${tail}" >&2
      ;;
    5??)
      VERDICT=wedged; unservable=1
      echo "[zot-probe] SUPPRESS ping: ${code} — zot WEDGED. Absence-of-ping will alarm. ${tail}" >&2
      ;;
    *)
      VERDICT=unexpected; unservable=1
      echo "[zot-probe] SUPPRESS ping: unexpected code ${code} for ${ENDPOINT}/v2/${r}/${path}. Absence-of-ping will alarm. ${tail}" >&2
      ;;
  esac
}

for _i in "${!R_NAME[@]}"; do
  r="${R_NAME[$_i]}"
  if [ -n "${SOLEUR_ZOT_PROBE_STATUS_OVERRIDE:-}" ]; then
    CODE="${_OVR[$_i]:-000}"
    [ -n "$CODE" ] || CODE=000
  else
    _fetch "${r}/tags/list"
  fi
  R_CODE+=("$CODE")

  # No early exit in this loop: every repo's line is emitted, so one repo's fault never hides another's.
  _classify "$CODE" tags "$r" ""
  R_VERDICT+=("$VERDICT")

  # The pinned-manifest HEAD (#10004): only for an element that carries a digest AND whose tag list answered
  # 200 (during an outage a second request would only add a timeout and a duplicate fault line for the same
  # repository). Every path appends to R_PINV so the marker emitter never reads an unset index.
  _dig="${R_DIG[$_i]}"
  if [ -z "$_dig" ]; then
    R_PINV+=(none)
  elif [ "$CODE" != 200 ]; then
    R_PINV+=(skipped)
  else
    _fetch "${r}/manifests/${_dig}" -I
    _classify "$CODE" pin "$r" "${r}@${_dig}"
    R_PINV+=("$VERDICT")
  fi
done

# Source-4 liveness beacon — fires on EVERY run (rate-limited), independent of the zot verdicts above,
# so a zot outage is never misread as a dead vector agent. See _canary().
_canary
# Per-repo markers BEFORE the exit decision, so the 401 path emits them too. See _repo_markers().
_repo_markers

# Aggregation — the ONLY ping site. A 401 on any repo is HARD (exit 3); otherwise any fault suppresses
# the ping; only an all-200 run pings.
if [ "$auth_broke" -eq 1 ]; then
  exit 3
fi
if [ "$unservable" -eq 1 ]; then
  exit 0
fi
_ping "$URL"
[ -n "$VERBOSE" ] && echo "[zot-probe] all ${#R_NAME[@]} repositories servable (200) — pinged heartbeat." >&2
exit 0
