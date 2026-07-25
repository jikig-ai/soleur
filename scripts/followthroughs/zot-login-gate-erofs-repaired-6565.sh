#!/usr/bin/env bash
# Follow-through verification for #6565 (post-deploy confirmation of the EROFS repair).
#
# SIBLING to the instrument soak zot-login-gate-names-failure-6497.sh, reusing the same
# Better Stack query helper. The two soaks assert DIFFERENT invariants on DIFFERENT issues:
#
#   instrument soak (#6497): every FAILED login line NAMES its failure (carries the hatch).
#                            PASSES on a still-broken world — its job was to buy the datum.
#   repair soak    (#6565): the failures STOPPED. This is the repair's close criterion, and
#                            it is a POST-DEPLOY SOAK — the fix (relocating the deploy-user
#                            DOCKER_CONFIG off the ProtectHome=read-only /home mount onto
#                            /mnt/data) only takes effect once a real deploy RUNS the relocated
#                            `ci-deploy.sh` on a host. File delivery alone emits no telemetry.
#
# THE REPAIR INVARIANT: on each web host that exercised the deploy-user login path in the
# window, `docker login` now SUCCEEDS — a positive `… ok` line — and emits ZERO cred_store /
# EROFS failures. "Absence of failures" is NOT proof of repair (a silent host emits nothing);
# each host must POSITIVELY emit an OK line.
#
# PER-HOST KEY — why `_MACHINE_ID`, not host_id or host_name:
#   - host_id (hetzner-<instance-id>) is emitted ONLY to Sentry (ci-deploy.sh zot_gate_degraded_
#     event tag), NOT into the journald ZOT_GATE/PRELUDE lines this query plane reads.
#   - host_name is Vector-computed and MISLABELED (#6616 — uniformly "soleur-inngest-prd" on
#     both web hosts), so it cannot distinguish web-1 from web-2.
#   - `_MACHINE_ID` is the journald-native /etc/machine-id, present verbatim in every Better
#     Stack record, distinct per host, and mints FRESH on a web-2 `-replace` recreate (so a
#     recreated host reads as a new host, which is correct for fleet-coverage). It is the only
#     reliable per-host discriminator in this no-SSH plane today.
#   (Plan named "host_id beacon"; corrected to _MACHINE_ID after measuring that host_id never
#    reaches Better Stack. Recorded in the branch decision-challenges.md.)
#
# FLEET COVERAGE (spec-flow F1/F3/F8): require >=2 distinct _MACHINE_ID, EACH with a positive
# OK line and zero EROFS/cred_store failures. A fleet-global ">=1 OK + zero FAILED" false-PASSes
# when web-2 is silent (web-1's OK + web-2's absence). Phase 4 of the plan forces a deploy on
# BOTH hosts inside the window so >=2 machine-ids is reachable rather than permanently TRANSIENT.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>=2 hosts, each OK + zero EROFS/cred_store; sweeper closes #6565)
#   1 = FAIL       (>=1 host still emits a class=cred_store / kw=erofs FAILED line — unrepaired)
#   * = TRANSIENT  (Better Stack unreachable/auth failure; <2 hosts observed; or a host with no
#                   login lines in the window — no deploy exercised the relocated path on it.
#                   Absence of data is NOT proof of repair; retry next sweep.)
#
# Required env: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}
#   (wired in scheduled-followthrough-sweeper.yml; mirrors Doppler soleur/prd_terraform)
#
# Window is 90m to match the instrument soak verbatim: at 6-12 deploys/day the mean inter-deploy
# gap is 2-4h, so a 60m window legitimately returns zero rows and would misread as failure.

set -uo pipefail

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_HOST not set" >&2; exit 2; fi
if [[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_USERNAME not set" >&2; exit 2; fi
if [[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_PASSWORD not set" >&2; exit 2; fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '.')"
QUERY="${REPO_ROOT}/scripts/betterstack-query.sh"

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: ${QUERY} not found or not executable" >&2
  exit 2
fi

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT INT TERM

# --since 90m matches the instrument soak's own regex (^([0-9]+)([hmd])$); --grep is repeatable
# and OR-combined, so this sees BOTH the ZOT_GATE and the PRELUDE halves.
if ! bash "$QUERY" --since 90m --grep ZOT_GATE --grep PRELUDE > "$OUT" 2>&1; then
  echo "TRANSIENT: betterstack-query.sh failed:" >&2
  tail -5 "$OUT" >&2
  exit 2
fi

# Any ZOT_GATE/PRELUDE lines at all? Absence proves nothing (no deploy in the window).
ANY_LINES="$(grep -cE 'ZOT_GATE|PRELUDE' "$OUT" || true)"
if [[ "${ANY_LINES:-0}" -eq 0 ]]; then
  echo "TRANSIENT: no ZOT_GATE/PRELUDE lines in the last 90m — no deploy exercised the relocated" >&2
  echo "           deploy-user login path. Absence of data is not proof of repair. Retry next sweep." >&2
  exit 2
fi

# Per-record (NDJSON, one journald record per line): extract _MACHINE_ID and classify the message.
# Both fields live in the same record line, so no jq dependency is needed (mirrors the instrument
# soak's no-jq discipline). A record is:
#   OK      — `PRELUDE: docker login ghcr.io ok…` OR `ZOT_GATE: active — docker login … ok…`
#   EROFS   — a `… FAILED …` login line carrying class=cred_store OR kw=…erofs (the repair target)
# ZOT_GATE_DEGRADED reason lines and non-login states are neither and are ignored for coverage.
declare -A HOST_OK=()      # machine_id -> count of OK lines
declare -A HOST_EROFS=()   # machine_id -> count of cred_store/erofs FAILED lines
declare -A HOST_SEEN=()    # machine_id -> any login-outcome line seen
FAIL_KWS=""                # distinct kw= values observed on the failing lines (for the FAIL msg)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # journald machine-id appears double-escaped inside .raw: _MACHINE_ID\":\"<hex>
  # journald machine-id is EXACTLY 32 lowercase hex; pin the length + bound the non-hex bridge
  # so an empty `_MACHINE_ID\":\"\"` value cannot make a greedy `[^0-9a-f]*` cross into the next
  # field (e.g. _BOOT_ID) and mis-extract its hex as the machine id.
  mid="$(printf '%s' "$line" | grep -oE '_MACHINE_ID[^0-9a-f]{1,8}[0-9a-f]{32}' | grep -oE '[0-9a-f]{32}' | head -1)"
  [[ -z "$mid" ]] && continue

  is_ok=0 is_erofs=0
  # OK: an authenticated login. Anchor on the outcome phrase, not a bare "ok".
  if printf '%s' "$line" | grep -qE 'PRELUDE: docker login ghcr\.io ok|ZOT_GATE: active .* docker login .* ok'; then
    is_ok=1
  fi
  # EROFS/cred_store FAILURE: a FAILED login line still carrying the repair-target signature.
  if printf '%s' "$line" | grep -qE '(ZOT_GATE|PRELUDE): docker login .* FAILED' \
     && printf '%s' "$line" | grep -qE 'class=cred_store|kw=[a-z,]*erofs'; then
    is_erofs=1
    # Record the actual kw= so the FAIL message names the real fault (erofs vs a mkdir-failed
    # enoent) instead of hard-coding "erofs".
    _kw="$(printf '%s' "$line" | grep -oE 'kw=[a-z,]*' | head -1)"
    [[ -n "$_kw" && "$FAIL_KWS" != *"$_kw"* ]] && FAIL_KWS="${FAIL_KWS} ${_kw}"
  fi

  if [[ "$is_ok" -eq 1 || "$is_erofs" -eq 1 ]]; then
    HOST_SEEN["$mid"]=1
    [[ "$is_ok" -eq 1 ]]    && HOST_OK["$mid"]=$(( ${HOST_OK["$mid"]:-0} + 1 ))
    [[ "$is_erofs" -eq 1 ]] && HOST_EROFS["$mid"]=$(( ${HOST_EROFS["$mid"]:-0} + 1 ))
  fi
done < "$OUT"

HOSTS_TOTAL="${#HOST_SEEN[@]}"

# FAIL takes precedence: any host still emitting a cred_store/erofs FAILED line means unrepaired.
FAILED_HOSTS=""
for mid in "${!HOST_EROFS[@]}"; do
  [[ "${HOST_EROFS[$mid]:-0}" -gt 0 ]] && FAILED_HOSTS="${FAILED_HOSTS} ${mid}(${HOST_EROFS[$mid]})"
done
if [[ -n "$FAILED_HOSTS" ]]; then
  echo "FAIL: docker login still fails class=cred_store (observed${FAIL_KWS:- kw=<none>}) on host(s):${FAILED_HOSTS}." >&2
  echo "      A kw=…erofs class means the ProtectHome relocation is not in effect; a kw=…enoent" >&2
  echo "      class means the /mnt/data config dir could not be created (mount/perm). Either way," >&2
  echo "      the credential-persist path is broken — do NOT close #6565." >&2
  exit 1
fi

# Coverage: need >=2 distinct hosts, EACH with >=1 positive OK line.
if [[ "$HOSTS_TOTAL" -lt 2 ]]; then
  echo "TRANSIENT: only ${HOSTS_TOTAL} host(s) emitted a login outcome in the window; need >=2 for" >&2
  echo "           fleet coverage (a silent host is not a repaired host). Force a deploy on each" >&2
  echo "           host (plan Phase 4) and retry next sweep." >&2
  exit 2
fi

SILENT_HOSTS=""
for mid in "${!HOST_SEEN[@]}"; do
  [[ "${HOST_OK[$mid]:-0}" -lt 1 ]] && SILENT_HOSTS="${SILENT_HOSTS} ${mid}"
done
if [[ -n "$SILENT_HOSTS" ]]; then
  echo "TRANSIENT: host(s)${SILENT_HOSTS} emitted a login-outcome line but no positive OK line" >&2
  echo "           in the window. Absence of failure is not proof of success. Retry next sweep." >&2
  exit 2
fi

echo "PASS: ${HOSTS_TOTAL} distinct hosts each emitted >=1 authenticated 'docker login … ok'" \
     "line and ZERO class=cred_store/kw=erofs failures in the last 90m — the EROFS credential-"\
     "persist bug is repaired fleet-wide (per-host, not fleet-global). Close #6565."
for mid in "${!HOST_SEEN[@]}"; do
  echo "  host ${mid}: ok=${HOST_OK[$mid]:-0} erofs_failed=${HOST_EROFS[$mid]:-0}"
done
exit 0
