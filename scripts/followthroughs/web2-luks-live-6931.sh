#!/usr/bin/env bash
# Follow-through for #6931 — is web-2 LIVE on a guest-side LUKS volume, and has it stayed that way for the
# soak? (ADR-143 R3; the soak-gated half of the issue's closure.)
#
# WHAT THE PR CAN AND CANNOT SHOW. The merge proves the CODE path (the provisioner, the birth gate, the
# marker writer). It cannot prove web-2 was actually reborn onto a LUKS volume, nor that it stayed there:
# that is a property of a host that does not exist until the post-merge rebirth dispatch (#9372), measured
# over time. Self-pulled from Better Stack — no SSH, no dashboard (hr-no-ssh-fallback-in-runbooks,
# hr-no-dashboard-eyeball-pull-data).
#
# GRADED FROM ROWS ALONE. This probe reads Better Stack and nothing else: it does NOT read the soak marker
# WORKSPACES_LUKS_CUTOVER_AT, so it holds no Doppler credential (the marker's write token stays with the one
# job that writes it). The soak is re-derived from the same rows the marker writer judges, through the same
# helper (scripts/lib/web2-luks-rows.sh, which also defines the row contract). PASS needs ALL of:
#   1. the newest web-2 readiness row (emitted once per instance) is GREEN and at least SOAK_DAYS old;
#   2. probe rows are GREEN (crypto_LUKS on /dev/mapper/workspaces, escrow ok) in at least SOAK_DAYS distinct
#      24 h buckets counted from that readiness row, and the NEWEST probe row is GREEN and fresh (<= 26 h);
#   3. no non-green probe row (a FAIL line, a malformed one, a non-LUKS OK) at or after that readiness row.
#
# Exit semantics (sweep-followthroughs.sh rc→word map):
#   0 = PASS              the soak is met
#   1 = FAIL              (a) a non-green probe row landed after the readiness row: the soak of this instance
#                         is spoiled; or (b) the soak window is CLOSED and the soak is still not met —
#                         SOLEUR_FT_EARLIEST + (SOAK_DAYS + 1) days has passed. (b) is what stops a web-2 whose
#                         probe never came up from sitting at NOT YET forever
#   2 = NOT YET           the soak is still running / not yet evidenced and the window is open, or a read
#                         fault (Better Stack did not answer or answered an unparseable body: a fault is not
#                         a verdict, and a fault never FAILs)
#   3 = CANNOT ESTABLISH  a Better Stack credential is not injected, or the shared helper cannot be loaded
#   78                    refused to run under xtrace with a live credential
#
# Enrollment (the tracker body carries the directive; the tracker carries the `follow-through` label):
#   <!-- soleur:followthrough script=scripts/followthroughs/web2-luks-live-6931.sh earliest=<web-2 rebirth+3d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
# All three names are bound in scheduled-followthrough-sweeper.yml's env: block (shared with #5934/#5110).
# `earliest` reaches this script as SOLEUR_FT_EARLIEST (the sweeper's own clock; an empty or unparseable value
# means "no clock", and then nothing here ever FAILs on the window).
set -uo pipefail

# Refuse to run under xtrace with a live credential set (#7797): tracing prints expanded commands.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause and bind it in scheduled-followthrough-sweeper.yml). Nothing was read.\n' "$v"
    exit 3
  fi
done

# The shared helper — the query and the parse are defined once, in one place.
_w2l_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/web2-luks-rows.sh"
# shellcheck source=scripts/lib/web2-luks-rows.sh
if ! source "$_w2l_lib" || ! declare -F w2l_probe_verdict >/dev/null || ! declare -F w2l_ready_verdict >/dev/null \
   || ! declare -F w2l_soak_scan >/dev/null; then
  printf 'CANNOT ESTABLISH: the shared helper could not be loaded (lib=%s). Nothing was measured.\n' "$_w2l_lib"
  exit 3
fi

# 3 days: the same soak the traffic-weight gate defaults to (lb-weight-gate.sh WS_SOAK_DAYS).
SOAK_DAYS=3
SOAK_S=$(( SOAK_DAYS * 86400 ))
tmp="$(mktemp -d)" || { printf 'CANNOT ESTABLISH: mktemp failed.\n'; exit 3; }
trap 'rm -rf "$tmp"' EXIT

# unmet <why> — the soak is not met and nothing spoiled it: NOT YET inside the window, FAIL once it has closed.
unmet() {
  local earliest_epoch now_epoch
  # `date -d ""` is midnight today, not an error, so an empty clock must be refused before it is parsed.
  earliest_epoch=""
  [[ -z "${SOLEUR_FT_EARLIEST:-}" ]] || earliest_epoch="$(date -u -d "$SOLEUR_FT_EARLIEST" +%s 2>/dev/null)" || earliest_epoch=""
  now_epoch="$(date -u +%s)"
  if [[ "$earliest_epoch" =~ ^[0-9]+$ ]] && (( now_epoch >= earliest_epoch + (SOAK_DAYS + 1) * 86400 )); then
    printf 'FAIL: the soak is not met and its window has closed (SOLEUR_FT_EARLIEST %s + %s days): %s\n' "$SOLEUR_FT_EARLIEST" "$(( SOAK_DAYS + 1 ))" "$1"
    exit 1
  fi
  printf 'NOT YET: %s\n' "$1"
  exit 2
}

# --- the readiness row opens the soak ---------------------------------------------------------------------
if ! w2l_fetch_ready "$tmp/ready.jsonl"; then
  printf 'NOT YET: the Better Stack read of the readiness row did not answer (see stderr). A read fault is not a verdict; retry next sweep.\n'
  exit 2
fi
rverdict="$(w2l_ready_verdict "$tmp/ready.jsonl")"
if [[ "$rverdict" != GREEN* ]]; then
  unmet "no GREEN web-2 readiness row opens the soak (${rverdict}); web-2 has not been (re)born onto LUKS, or its probe/readiness telemetry is dark."
fi
ready_age="${rverdict##* age_s=}"
if [[ ! "$ready_age" =~ ^[0-9]+$ ]]; then
  printf 'NOT YET: the readiness verdict carried no parseable age (%s). Retry next sweep.\n' "$rverdict"
  exit 2
fi
if (( ready_age < SOAK_S )); then
  unmet "the newest readiness row is $(( ready_age / 3600 )) h old; the soak needs $(( SOAK_S / 3600 )) h of probe rows after it."
fi

# --- the probe rows since then ------------------------------------------------------------------------------
# Lookback = the readiness row's age plus slack, capped; the limit covers the daily rows with room to spare.
hours=$(( ready_age / 3600 + 2 ))
(( hours > 504 )) && hours=504
if ! w2l_fetch_probe "$tmp/probe.jsonl" "$hours" 2000; then
  printf 'NOT YET: the Better Stack read of the probe rows did not answer (see stderr). A read fault is not a verdict; retry next sweep.\n'
  exit 2
fi
scan="$(w2l_soak_scan "$tmp/probe.jsonl" "$ready_age")" || scan=""
if [[ ! "$scan" =~ ^[0-9]+\ [0-9]+$ ]]; then
  printf 'NOT YET: the probe rows could not be parsed for the soak scan. Retry next sweep.\n'
  exit 2
fi
green_days="${scan% *}"
reds="${scan#* }"

if (( reds > 0 )); then
  printf 'FAIL: %s non-green probe row(s) (a FAIL line, a malformed one, or an OK line that is not LUKS) landed after the readiness row. The soak of this instance is spoiled.\n' "$reds"
  exit 1
fi
verdict="$(w2l_probe_verdict "$tmp/probe.jsonl")"
if [[ "$verdict" != GREEN* ]]; then
  unmet "the newest web-2 probe row is not a fresh LUKS-backed OK row (${verdict})."
fi
if (( green_days < SOAK_DAYS )); then
  unmet "${green_days} of ${SOAK_DAYS} distinct days of GREEN probe rows since the readiness row."
fi

printf 'PASS: web-2 is live on a LUKS-backed /workspaces — %s distinct days of GREEN probe rows since the readiness row (%s h ago), no non-green row, and the newest probe row is fresh (%s). (#6931 soak-gated closure)\n' \
  "$green_days" "$(( ready_age / 3600 ))" "${verdict#GREEN }"
exit 0
