#!/usr/bin/env bash
# Follow-through for #6931 — is web-2 LIVE on a guest-side LUKS volume, and has it stayed that way for the
# soak? (ADR-143 R3; the soak-gated half of the issue's closure.)
#
# WHAT THE PR CAN AND CANNOT SHOW. The merge proves the CODE path (the provisioner, the birth gate, the
# marker writer). It cannot prove web-2 was actually reborn onto a LUKS volume, nor that it stayed there:
# that is a property of a host that does not exist until the post-merge rebirth dispatch, measured over
# time. Self-pulled from Better Stack and the Doppler API — no SSH, no dashboard (hr-no-ssh-fallback-in-
# runbooks, hr-no-dashboard-eyeball-pull-data).
#
# PASS needs ALL THREE, and each is read from a different place so one cannot vouch for another:
#   1. the LATEST web-2 luks-monitor probe row is a fresh (<=26h) OK row on crypto_LUKS /dev/mapper/
#      workspaces with escrow=ok  — scripts/lib/web2-luks-rows.sh, the SAME helper the daily verify leg uses;
#   2. WORKSPACES_LUKS_CUTOVER_AT exists in prd_workspaces_luks_marker and is at least 3 days old — the
#      marker is written once, at the FIRST green, and deleted on any red, so its age IS the unbroken soak;
#   3. no red probe row (a FAIL line or a malformed one) has appeared since the marker was written.
#
# Exit semantics (sweep-followthroughs.sh rc→word map):
#   0 = PASS              all three hold
#   1 = FAIL              the evidence says web-2 is NOT live on LUKS: the latest probe row is stale, non-LUKS,
#                         escrow-less or a FAIL line; or a red row exists since the marker
#   2 = NOT YET           no marker yet / marker younger than 3 days (the soak is still running), or a
#                         transient read fault (Better Stack or Doppler did not answer)
#   3 = CANNOT ESTABLISH  a credential is not injected, or the shared helper cannot be loaded
#
# Enrollment (the tracker body carries the directive; the tracker carries the `follow-through` label):
#   <!-- soleur:followthrough script=scripts/followthroughs/web2-luks-live-6931.sh earliest=<web-2 rebirth+3d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER -->
# All four names are bound in scheduled-followthrough-sweeper.yml's env: block. The Doppler token is the
# marker config's token (workspaces-luks-fresh-boot.tf); here it is used for ONE GET of ONE secret.
#
# Reading the marker goes through the Doppler HTTP API with curl rather than the CLI: the sweeper job
# installs no Doppler CLI and runs probes under `env -i`. The token reaches curl on STDIN as a config line
# (`-K -`), never as an argument, so it is not in any process listing.
set -uo pipefail

# Refuse to run under xtrace with a live credential set (#7797): tracing prints expanded commands.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}${DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause and bind it in scheduled-followthrough-sweeper.yml). Nothing was read.\n' "$v"
    exit 3
  fi
done
case "$DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER" in
  *[!A-Za-z0-9._-]*) printf 'CANNOT ESTABLISH: DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER carries characters a Doppler token never has; refusing to use it.\n'; exit 3 ;;
esac

# The shared helper — the query and the parse are defined once, in one place.
_w2l_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/web2-luks-rows.sh"
# shellcheck source=scripts/lib/web2-luks-rows.sh
if ! source "$_w2l_lib" || ! declare -F w2l_probe_verdict >/dev/null || ! declare -F w2l_reds_since >/dev/null; then
  printf 'CANNOT ESTABLISH: the shared helper could not be loaded (lib=%s). Nothing was measured.\n' "$_w2l_lib"
  exit 3
fi

SOAK_DAYS=3
SOAK_S=$(( SOAK_DAYS * 86400 ))
tmp="$(mktemp -d)" || { printf 'CANNOT ESTABLISH: mktemp failed.\n'; exit 3; }
trap 'rm -rf "$tmp"' EXIT

# --- 2 (first, it sets the window): the marker's age -----------------------------------------------------
url="https://api.doppler.com/v3/configs/config/secret?project=${W2L_MARKER_PROJECT}&config=${W2L_MARKER_CONFIG}&name=${W2L_MARKER_NAME}"
code="$(printf 'header = "Authorization: Bearer %s"\n' "$DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER" \
  | curl --disable --noproxy '*' -sS --max-time 30 -K - -o "$tmp/marker.json" -w '%{http_code}' "$url" 2>"$tmp/marker.err")" || code="000"
case "$code" in
  200) : ;;
  404) printf 'NOT YET: %s is absent in %s — web-2 has not produced a first green yet, or a red row reset the soak. Nothing to grade.\n' "$W2L_MARKER_NAME" "$W2L_MARKER_CONFIG"; exit 2 ;;
  *)   printf 'NOT YET: the Doppler API answered HTTP %s reading the marker — a read fault, not a verdict. Retry next sweep.\n' "$code"; exit 2 ;;
esac
marker="$(jq -r '(.value.computed // .value.raw // empty)' "$tmp/marker.json" 2>/dev/null)" || marker=""
iso_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [[ ! "$marker" =~ $iso_re ]]; then
  printf 'NOT YET: the marker value is not an ISO-8601 UTC timestamp. The next verify run rewrites or removes it; nothing is graded from a hand-written value.\n'
  exit 2
fi
marker_epoch="$(date -u -d "$marker" +%s 2>/dev/null)" || marker_epoch=""
now_epoch="$(date -u +%s)"
if [[ ! "$marker_epoch" =~ ^[0-9]+$ ]] || (( marker_epoch > now_epoch )); then
  printf 'NOT YET: the marker (%s) is unparseable or in the future. Nothing is graded from it.\n' "$marker"
  exit 2
fi
age_s=$(( now_epoch - marker_epoch ))
if (( age_s < SOAK_S )); then
  printf 'NOT YET: the soak has run %s of %s hours (marker %s). The marker is written at the first green and deleted on any red, so this is an unbroken run so far.\n' \
    "$(( age_s / 3600 ))" "$(( SOAK_S / 3600 ))" "$marker"
  exit 2
fi

# --- 1 + 3: the latest probe row and every verdict row since the marker ------------------------------------
# Lookback = the marker's age plus slack, capped; the limit covers two journal copies per daily run with room.
hours=$(( age_s / 3600 + 2 ))
(( hours > 504 )) && hours=504
if ! w2l_fetch_probe "$tmp/probe.jsonl" "$hours" 2000; then
  printf 'NOT YET: the Better Stack read did not answer (see stderr). A read fault is not a verdict; retry next sweep.\n'
  exit 2
fi

verdict="$(w2l_probe_verdict "$tmp/probe.jsonl")"
if [[ "$verdict" != GREEN* ]]; then
  printf 'FAIL: the latest web-2 probe row is not a fresh LUKS-backed OK row (%s). The soak marker (%s) is stale evidence; the verify leg removes it on its next run.\n' "$verdict" "$marker"
  exit 1
fi
reds="$(w2l_reds_since "$tmp/probe.jsonl" "$age_s")" || reds=""
if [[ ! "$reds" =~ ^[0-9]+$ ]]; then
  printf 'NOT YET: the probe rows could not be parsed for the red-row scan. Retry next sweep.\n'
  exit 2
fi
if (( reds > 0 )); then
  printf 'FAIL: %s red probe row(s) (a FAIL line or a malformed one) landed since the marker was written (%s). The soak is not unbroken.\n' "$reds" "$marker"
  exit 1
fi

printf 'PASS: web-2 is live on a LUKS-backed /workspaces — the latest probe row is fresh (%s), the soak marker is %s days old (%s) and no red probe row has landed since. (#6931 soak-gated closure)\n' \
  "${verdict#GREEN }" "$(( age_s / 86400 ))" "$marker"
exit 0
