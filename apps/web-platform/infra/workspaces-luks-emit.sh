#!/usr/bin/env bash
# #6604 — SSH-free discriminating Sentry emit for the /workspaces LUKS at-rest drift class.
#
# #6807 — this file is now the SHARED LEAF HELPER for the whole workspaces-luks feature, not solely
# the emitter. It additionally carries the bounded/classifying HTTP probe, the readyz classifier and
# the workspace-inventory counter, because it is already sourced by BOTH consumers
# (luks-monitor.sh:31, workspaces-cutover.sh) and is already in BOTH tar lists
# (workspaces-luks-verify.yml:94, workspaces-luks-cutover.yml:446). A new sibling script would add a
# second two-list sync obligation — the exact cross-file drift class that produced #6807.
#
# Mirrors cron-egress-enforce-probe.sh's emit boundary, with TWO deliberate #6604 corrections:
#
#  DP-9 (baked-DSN-first): cron-egress-enforce-probe.sh resolves the DSN via
#  `doppler secrets get` ONLY. Copying that verbatim reintroduces the exact circular trap this
#  emit exists to page on — the "Doppler unreachable ⇒ passphrase absent ⇒ mapper never opens"
#  mode would lose its DSN by the SAME cause and go dark. So this reads the BAKED DSN first
#  (/etc/default/luks-monitor, written root:root 0600 by cloud-init.yml), and only falls back to
#  Doppler if the bake is somehow empty. The bake survives a total Doppler outage.
#
#  DP-8 (feature+op tags): the Sentry drift PAGE depends ENTIRELY on the direct-curl envelope
#  matching the sentry_issue_alert filter (feature=workspaces-luks ∧ op IS_IN workspaces-luks-drift)
#  — Vector is Better-Stack-only and never reaches Sentry. cron-egress-enforce-probe.sh sets only
#  stage/host_id/probe_result, which would NOT match. This envelope carries feature/op (modelled on
#  the ghcr envelope, soleur-host-bootstrap.sh:185) PLUS the nine discriminating fields so the
#  competing failure modes are told apart in ONE event (§2.9.2 blind-surface).
#
# The nine discriminating fields (read from the WL_* environment the caller exports):
#   device_type mount_source mapper_present luks_open_result header_uuid_match
#   cryptsetup_unit_result doppler_reachable mountpoint_ok host reason
#
# Usage:  WL_REASON=<slug> WL_DEVICE_TYPE=... [WL_LEVEL=fatal|warning] \
#           bash workspaces-luks-emit.sh
#         (or `source` it and call `workspaces_luks_emit`). ALWAYS returns 0 — a paging emit must
#         never itself brick a boot or a cutover step (fail-open, like _sentry_emit).

# Strip `"` and `\` (JSON-structural) then any non-printable BEFORE interpolation into the Sentry
# body — host id is cloud-metadata, not attacker-controlled, but a stray backslash/newline would
# corrupt the envelope.
# shellcheck disable=SC1003  # '"\\' deletes " and \ (JSON-structural) — matches cron-egress-enforce-probe.sh
_wl_scrub() { printf '%s' "${1:-}" | tr -d '"\\' | tr -cd '[:print:]'; }

# ===========================================================================
# #6807 — shared bounded HTTP probe, readyz classifier, workspace counter
# ===========================================================================

# _wl_probe_bounds — resolve the retry knobs. Read at CALL time, not source time, so a harness can
# flip them between cases without re-sourcing the file.
#
# BOUNDED BY ATTEMPTS, NEVER BY WALL CLOCK. Under a stubbed no-op `sleep` (which is how these loops
# are tested) a wall-clock deadline spins hot for its entire duration; an attempt bound is
# deterministic in both worlds.
_wl_probe_bounds() {
  WL_ATTEMPTS_N="${WORKSPACES_CANARY_ATTEMPTS:-30}"
  WL_INTERVAL_N="${WORKSPACES_CANARY_INTERVAL_S:-3}"
  # `:-` substitutes only for UNSET-or-EMPTY. The real silent-disable hazards are `=0` (a
  # zero-iteration loop passes trivially — a canary that cannot fail) and a NON-NUMERIC value
  # (`[ abc -le n ]` errors and the loop never runs). `:-` catches neither, hence the explicit floor.
  [ "$WL_ATTEMPTS_N" -ge 1 ] 2>/dev/null || WL_ATTEMPTS_N=1
  [ "$WL_INTERVAL_N" -ge 0 ] 2>/dev/null || WL_INTERVAL_N=3
}

# wl_http_class <code> — three-way classification.
#
# The STRUCTURAL set is ENUMERATED and everything else is retryable, deliberately inverted from the
# obvious "enumerate the transient codes" shape. This path traverses the Cloudflare edge, so the
# unknown-code population is dominated by CF-origin codes; failing SAFE on an unknown means retrying
# it. Classifying `530` (CF 1033, "tunnel connector not connected" — the code this stack most likely
# emits during a container restart window) as structural would reintroduce #6807's Bug B in a new coat.
wl_http_class() {
  case "${1:-}" in
    200)                         printf 'success' ;;
    307|401|403|404|405|525|526) printf 'structural' ;;
    *)                           printf 'retryable' ;;
  esac
}

# wl_probe_http <url> — retry a liveness probe to an attempt bound.
#
# LOOP SHAPE IS PINNED (plan task 5.1): NO sleep after the FINAL attempt. A trailing sleep buys
# nothing (no probe follows it), costs one interval of dead-man budget, and would make the observed
# sleep count equal the attempt count instead of attempts-1 — the ACs derive from this choice.
#
# Sets WL_PROBE_LAST_CODE / _ATTEMPTS / _ELAPSED_S / _CLASS (exported for the emit envelope).
# Returns 0 on 200, 1 on a structural code (immediately, no retry burn), 2 on budget exhaustion.
wl_probe_http() {
  local url="$1" i code cls started now
  _wl_probe_bounds
  started="$(date +%s 2>/dev/null || echo 0)"
  WL_PROBE_LAST_CODE=000; WL_PROBE_ATTEMPTS=0; WL_PROBE_ELAPSED_S=0; WL_PROBE_CLASS=unknown
  i=1
  while [ "$i" -le "$WL_ATTEMPTS_N" ]; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo 000)"
    cls="$(wl_http_class "$code")"
    now="$(date +%s 2>/dev/null || echo 0)"
    WL_PROBE_LAST_CODE="$code"; WL_PROBE_ATTEMPTS="$i"; WL_PROBE_CLASS="$cls"
    WL_PROBE_ELAPSED_S="$((now - started))"
    export WL_PROBE_LAST_CODE WL_PROBE_ATTEMPTS WL_PROBE_ELAPSED_S WL_PROBE_CLASS
    if [ "$cls" = "success" ]; then return 0; fi
    if [ "$cls" = "structural" ]; then return 1; fi
    echo "[workspaces-luks] $url -> $code (attempt $i/$WL_ATTEMPTS_N)" >&2
    if [ "$i" -lt "$WL_ATTEMPTS_N" ]; then sleep "$WL_INTERVAL_N"; fi
    i=$((i + 1))
  done
  WL_PROBE_CLASS=deadline; export WL_PROBE_CLASS
  return 2
}

# wl_probe_readyz <url> — probe /internal/readyz and classify into ONE reason code.
#
# HTTP STATUS IS CLASSIFIED BEFORE BODY SHAPE. A loopback-gate regression answers
# `403 {"error":"forbidden"}` — valid JSON that simply is not `"ready":true`. Body-first
# classification lands it in the not-ready arm, which pages "the container is serving an EMPTY
# /workspaces": a confidently-wrong sole-copy DATA-LOSS verdict for what is actually a routing bug.
#
# #6807 CORRECTION vs the plan's classifier table, verified against server/readiness.ts:119
# (`res.writeHead(readiness.ready ? 200 : 503)`): a NOT-ready host answers **503**, not
# `200 + ready:false`. 503 sits in wl_http_class's generic retryable set — correct for /health (a
# booting container) and WRONG here, because for readyz it is a DETERMINATE answer. Retrying it
# would burn the entire budget and then report `readyz_unreachable`/deadline for a host that told us
# plainly it is not ready — converting a real data-loss signal into a timeout, which is the same
# class of confidently-wrong verdict this function exists to prevent. So readyz retries ONLY while
# the response is UNCLASSIFIABLE (no response at all — the container is still coming up); any
# parseable answer, at either status, is terminal.
#
# Sets WL_READYZ_REASON (empty on success) + WL_READYZ_WRITABLE / _POPULATED. Returns 0 / 1.
wl_probe_readyz() {
  local url="$1" i code body tmp rc
  _wl_probe_bounds
  tmp="$(mktemp 2>/dev/null || printf '/tmp/wl-readyz.%s' "$$")"
  WL_READYZ_REASON=""; WL_READYZ_WRITABLE=unknown; WL_READYZ_POPULATED=unknown
  WL_PROBE_LAST_CODE=000; WL_PROBE_ATTEMPTS=0
  rc=1
  i=1
  while [ "$i" -le "$WL_ATTEMPTS_N" ]; do
    : > "$tmp"
    code="$(curl -sS -o "$tmp" -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo 000)"
    body="$(cat "$tmp" 2>/dev/null || true)"
    WL_PROBE_LAST_CODE="$code"; WL_PROBE_ATTEMPTS="$i"
    # Sub-signals are read whenever present, so a not-ready emission can say WHICH check failed.
    case "$body" in
      *'"workspaces_writable":true'*)  WL_READYZ_WRITABLE=true ;;
      *'"workspaces_writable":false'*) WL_READYZ_WRITABLE=false ;;
    esac
    case "$body" in
      *'"workspaces_populated":true'*)  WL_READYZ_POPULATED=true ;;
      *'"workspaces_populated":false'*) WL_READYZ_POPULATED=false ;;
    esac
    case "$code" in
      403|404|405)
        WL_READYZ_REASON=readyz_gate_regression; rc=1; break ;;
      200|503)
        case "$body" in
          *'"ready":true'*)  WL_READYZ_REASON=""; rc=0 ;;
          *'"ready":false'*) WL_READYZ_REASON=readyz_not_ready; rc=1 ;;
          *)                 WL_READYZ_REASON=readyz_unparseable; rc=1 ;;
        esac
        break ;;
      *)
        WL_READYZ_REASON=readyz_unreachable; rc=1 ;;
    esac
    echo "[workspaces-luks] readyz -> $code (attempt $i/$WL_ATTEMPTS_N)" >&2
    if [ "$i" -lt "$WL_ATTEMPTS_N" ]; then sleep "$WL_INTERVAL_N"; fi
    i=$((i + 1))
  done
  rm -f "$tmp" 2>/dev/null || true
  export WL_READYZ_REASON WL_READYZ_WRITABLE WL_READYZ_POPULATED WL_PROBE_LAST_CODE WL_PROBE_ATTEMPTS
  return "$rc"
}

# wl_count_workspace_dirs <root> — the host-side workspace INVENTORY count.
#
# PARITY IS LOAD-BEARING. server/session-metrics.ts:19-41 (countWorkspaceDirsAt) excludes FOUR
# things: `.orphaned-*` prefixes, the `.cron` ephemeral clone subdir, `lost+found`, and any
# non-directory. An unfiltered shell count INFLATES — 7 surviving workspaces plus `lost+found` and
# `.cron` reads as 9 >= 8 and certifies a real shrink green, which is precisely the class of
# green-probe-that-cannot-fail #6807 is about. Keep these four in lockstep with session-metrics.ts.
#
# ONE function, used by BOTH the assertion (luks-monitor.sh) and the baseline persist
# (workspaces-cutover.sh), so the compared value and the stored value cannot be computed differently.
# Prints an integer on stdout and NOTHING else; returns non-zero if the root is unreadable, so the
# caller can fail closed rather than treating an error as a count of zero.
wl_count_workspace_dirs() {
  local root="${1:-}" name n=0
  [ -n "$root" ] && [ -d "$root" ] || return 1
  for name in "$root"/*/ "$root"/.*/; do
    [ -d "$name" ] || continue
    name="$(basename "${name%/}")"
    case "$name" in
      .|..|.cron|lost+found) continue ;;
      .orphaned-*)           continue ;;
    esac
    n=$((n + 1))
  done
  printf '%s' "$n"
}

workspaces_luks_emit() {
  ( set +e
    local level dsn key shost proj host body
    level="$(_wl_scrub "${WL_LEVEL:-fatal}")"
    [ -n "$level" ] || level=fatal

    # DP-9: BAKED DSN first (survives a Doppler outage — the exact mode this pages on), Doppler last.
    dsn=""
    if [ -r /etc/default/luks-monitor ]; then
      # shellcheck disable=SC1091
      . /etc/default/luks-monitor 2>/dev/null || true
      dsn="${SOLEUR_SENTRY_DSN:-}"
    fi
    if [ -z "$dsn" ]; then
      dsn=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
            || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
            || true)
    fi
    [ -n "$dsn" ] || return 0

    key=$(printf '%s' "$dsn" | sed -E 's#https://([^@]+)@.*#\1#')
    shost=$(printf '%s' "$dsn" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
    proj=$(printf '%s' "$dsn" | sed -E 's#.*/([0-9]+)$#\1#')
    host="$(_wl_scrub "${WL_HOST:-$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) )}")"

    # feature/op are the sentry_issue_alert filter keys (DP-8). The nine fields discriminate the
    # failure modes; every value is scrubbed of JSON-structural bytes.
    # #6807 adds nine READINESS/PROBE fields after the original nine. Additive and defaulted, so an
    # existing caller that sets none of them emits `unknown` and its envelope shape is unchanged.
    # The `op` is NOT parameterized: sentry_issue_alert.workspaces_luks_drift
    # (issue-alerts.tf:1704-1740) matches `filter_match="all"` on op EQUAL workspaces-luks-drift and
    # is the SOLE PAGING op of the nine this feature emits. A distinct readiness op would page
    # nobody and would be invisible to the wipe gate (workspaces-luks-soak-6604.sh). De-conflation
    # lives in `reason` + these fields + the exit code, never in a new op.
    # Integers only for the counts — workspace directory NAMES are user-identifying.
    body=$(printf '{"message":"workspaces LUKS at-rest drift","level":"%s","logger":"luks-monitor","tags":{"feature":"workspaces-luks","op":"workspaces-luks-drift","device_type":"%s","mount_source":"%s","mapper_present":"%s","luks_open_result":"%s","header_uuid_match":"%s","cryptsetup_unit_result":"%s","doppler_reachable":"%s","mountpoint_ok":"%s","host":"%s","reason":"%s","readyz_writable":"%s","readyz_populated":"%s","readyz_capacity":"%s","workspace_count":"%s","workspace_count_expected":"%s","probe_last_code":"%s","probe_attempts":"%s","probe_elapsed_s":"%s","probe_class":"%s"}}' \
      "$level" \
      "$(_wl_scrub "${WL_DEVICE_TYPE:-unknown}")" \
      "$(_wl_scrub "${WL_MOUNT_SOURCE:-unknown}")" \
      "$(_wl_scrub "${WL_MAPPER_PRESENT:-unknown}")" \
      "$(_wl_scrub "${WL_LUKS_OPEN_RESULT:-unknown}")" \
      "$(_wl_scrub "${WL_HEADER_UUID_MATCH:-unknown}")" \
      "$(_wl_scrub "${WL_CRYPTSETUP_UNIT_RESULT:-unknown}")" \
      "$(_wl_scrub "${WL_DOPPLER_REACHABLE:-unknown}")" \
      "$(_wl_scrub "${WL_MOUNTPOINT_OK:-unknown}")" \
      "$host" \
      "$(_wl_scrub "${WL_REASON:-unspecified}")" \
      "$(_wl_scrub "${WL_READYZ_WRITABLE:-unknown}")" \
      "$(_wl_scrub "${WL_READYZ_POPULATED:-unknown}")" \
      "$(_wl_scrub "${WL_READYZ_CAPACITY:-unknown}")" \
      "$(_wl_scrub "${WL_WORKSPACE_COUNT:-unknown}")" \
      "$(_wl_scrub "${WL_WORKSPACE_COUNT_EXPECTED:-unknown}")" \
      "$(_wl_scrub "${WL_PROBE_LAST_CODE:-unknown}")" \
      "$(_wl_scrub "${WL_PROBE_ATTEMPTS:-unknown}")" \
      "$(_wl_scrub "${WL_PROBE_ELAPSED_S:-unknown}")" \
      "$(_wl_scrub "${WL_PROBE_CLASS:-unknown}")")

    curl -m 10 --retry 3 -sf -X POST "https://$shost/api/$proj/store/" \
      -H 'Content-Type: application/json' \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$key" \
      -d "$body" >/dev/null 2>&1 || true
  ) || true
  return 0
}

# Direct-exec entrypoint (the sourced form calls workspaces_luks_emit directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  workspaces_luks_emit
fi
