#!/usr/bin/env bash
# (#8296 PR-2, Guard 3) Does the ledger's encryption claim for the Inngest store agree with the
# device the store is measured on?
#
# NOTIFY-ONLY. This probe is enrolled on tracker #8285 (the retained plaintext backstop,
# hcloud_volume.inngest_redis) and never closes #8285: the sweeper closes a tracker on status 0 and
# reads 1 as its reopen trigger, so NO path through this file ends in either. Its job is to tell
# someone, every day, while the backstop exists, when the record and the disk disagree.
#
# THE PROPERTY. One equivalence, evaluated only over a usable, fresh newest probe row:
#
#   claims_luks     scripts/encryption-posture-ledger.json, row hcloud_volume.inngest_redis_luks,
#                   at_rest.mechanism == "luks"
#   on_luks_mapper  the newest host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row's
#                   data_mount_src == "/dev/mapper/" + that row's device_binding.mapper
#                   (exact string equality: no prefix, no glob)
#
# The mapper is READ FROM THE LEDGER, so this file holds no literal mapper name and no volume id.
#
# DECISION TABLE, in this order (the measurement first, the ledger second):
#   78 xtrace_refused     shell tracing is on while BETTERSTACK_QUERY_PASSWORD is set
#    3 clock_malformed    SOLEUR_FT_NOW is set but is not an ISO-8601 UTC instant
#    3 query_failed       the helper is missing, a credential is unset, the helper failed, or it
#                         answered lines of which none decode as warehouse rows; also the shared
#                         probe-row predicate (scripts/lib/inngest-probe-row.sh, or
#                         INNGEST_PROBE_ROW_LIB) cannot be loaded (reason=selector_unavailable,
#                         checked first, before usage) or its jq selection failed
#                         (reason=selector_failed)
#   64 usage              any argument was passed
#    3 no_rows            no row from the dedicated host (host=soleur-inngest,
#                         host_name=soleur-inngest-prd) that the shared predicate reads as a probe
#                         row (emitter inngest-server-probe AND a message STARTING with
#                         SOLEUR_INNGEST_SERVER_PROBE) and whose FIRST host_role= token is dedicated,
#                         in --since 26h
#    3 row_unusable       the newest such row (by dt, 'T' and ' ' normalised) has a dt that is not
#                         YYYY-MM-DD HH:MM:SS (field=dt) or lies more than 5 min in the future
#                         (field=dt_future)
#    3 producer_silent    the newest such row is older than 3 h (hourly cadence plus slack)
#    3 row_unusable       its data_mount_src is empty, n/a, __UNREADABLE__ or not under /dev/, or
#                         its data_mount_devid is not a scsi-0HC_Volume_<n> alias
#    3 ledger_unreadable  the ledger, the luks row (exactly one), its mechanism or its mapper cannot
#                         be read, or there is more than one backstop row
#    5 rollback_inversion claims luks, store NOT on the LUKS mapper -- the backstop is the live store
#    5 under_claim        does not claim luks, store on the LUKS mapper
#    3 ledger_unreadable  (agreeing state only) the backstop row's expires_on is not YYYY-MM-DD
#    5 backstop_expired   ONLY when claims luks AND on the mapper AND today is AFTER the backstop
#                         row's exception.expires_on AND that row still exists
#    2 agree              claims_luks == on_luks_mapper (a correct post-rollback revert lands here
#                         too, even past the expiry)
#    3 unreachable        the fall-through at the bottom of the file
#    3 trap_remapped      the EXIT trap caught a status outside {2,3,5,64,78}
#
# CLOCK. "Now" is SOLEUR_FT_NOW when set (ISO-8601 UTC, e.g. 2026-10-01T12:00:00Z), date -u
# otherwise. A set-but-malformed value is 3 clock_malformed, never a silent fallback.
#
# Secrets: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#
# Tracker directive (goes in the #8285 issue body, never #8296's):
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-property-8296.sh secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# RETIREMENT: coverage ends when #8285 closes, because the sweeper does nothing with 2, 3 or 5 on a
# closed issue. So retire it only AFTER the destroy apply has run and the Hetzner API shows
# hcloud_volume.inngest_redis gone -- never in the PR that merely removes the volume from
# Terraform. Then delete this file, its harness scripts/followthroughs/inngest-luks-property-8296.test.sh,
# the run_suite "scripts/inngest-luks-property-8296" line in scripts/test-all.sh and the #8285
# directive, and close #8285 explicitly (gh issue close 8285). The destroy PR's body must carry no
# closing keyword next to #8285.
#
# Harness: scripts/followthroughs/inngest-luks-property-8296.test.sh (a fixture ledger and a stubbed
# scripts/betterstack-query.sh in a fake tree; this file resolves its repo from its own location).
set -uo pipefail

# XTRACE REFUSAL (#7797). Tracing echoes a command after expansion, so under bash -x a credential
# reaches the transcript the moment it is bound. Any of the three refuses.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf 'inngest-luks-property[#8296]: verdict=xtrace_refused refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

marker() { # <verdict> [k=v …]
  printf 'inngest-luks-property[#8296]: verdict=%s %s\n' "$1" "${2:-}"
}

# NEVER 0, NEVER 1. Every status outside the contract -- a fall-off, an unset variable under
# set -u, a stray `$?` -- is rewritten to 3. Each allowed status is spelled out as a literal so the
# harness's static allowlist can read every one. Installed directly after the xtrace refusal (which
# can only exit 78), before any other statement; the harness also forbids exec, kill and a second
# trap.
on_exit() {
  local rc=$?
  case "$rc" in
    2) exit 2 ;;
    3) exit 3 ;;
    5) exit 5 ;;
    64) exit 64 ;;
    78) exit 78 ;;
  esac
  marker "trap_remapped" "rc=$rc"
  echo "CANNOT ESTABLISH: the probe ended on a status outside its contract; nothing was decided. This probe never closes #8285."
  exit 3
}
trap on_exit EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
LEDGER="$REPO_ROOT/scripts/encryption-posture-ledger.json"
LUKS_ROW="hcloud_volume.inngest_redis_luks"
BACKSTOP_ROW="hcloud_volume.inngest_redis"
PROBE_MARKER="SOLEUR_INNGEST_SERVER_PROBE"
WINDOW="26h"
# --limit is not optional: the helper's default of 100 silently narrows the window.
LIMIT="${SOLEUR_FT_LIMIT:-5000}"
STALE_SECS=10800
RUNBOOK="knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
# The dedicated Inngest host, as vector stamps it (inngest-luks-cutover-6894.sh pins the same pair).
# Every host writes into one Logs source, so a row is only this host's measurement if BOTH match.
HOST="soleur-inngest"
HOST_NAME="soleur-inngest-prd"
FUTURE_SLACK_SECS=300
# The ONE definition of a probe row (#8846): emitter AND anchored marker. Resolved from this file's
# repo root so a sandboxed copy reads its own tree; INNGEST_PROBE_ROW_LIB overrides it.
PROBE_ROW_LIB="${INNGEST_PROBE_ROW_LIB:-$REPO_ROOT/scripts/lib/inngest-probe-row.sh}"
# shellcheck source=scripts/lib/inngest-probe-row.sh
if ! source "$PROBE_ROW_LIB" 2>/dev/null || [[ -z "${INNGEST_PROBE_ROW_JQ:-}" ]]; then
  marker "query_failed" "reason=selector_unavailable"
  echo "CANNOT ESTABLISH: reason=selector_unavailable lib=$PROBE_ROW_LIB -- the shared probe-row predicate could not be loaded, so no row can be read as a measurement. This says nothing about the store or the producer."
  exit 3
fi

if [[ "$#" -ne 0 ]]; then
  marker "usage" "argc=$#"
  echo "usage: inngest-luks-property-8296.sh takes no arguments (clock: SOLEUR_FT_NOW)."
  exit 64
fi

# ── CLOCK ────────────────────────────────────────────────────────────────────────────────────
if [[ -n "${SOLEUR_FT_NOW+x}" ]]; then
  NOW_ISO="$SOLEUR_FT_NOW"
  NOW_EPOCH=""
  if [[ "$NOW_ISO" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    NOW_EPOCH="$(date -u -d "$NOW_ISO" +%s 2>/dev/null)" || NOW_EPOCH=""
  fi
  if [[ -z "$NOW_EPOCH" ]]; then
    marker "clock_malformed" "SOLEUR_FT_NOW=$(printf '%s' "$NOW_ISO" | tr -c 'A-Za-z0-9:.-' '?' | head -c 40)"
    echo "CANNOT ESTABLISH: SOLEUR_FT_NOW is set but is not an ISO-8601 UTC instant (YYYY-MM-DDTHH:MM:SSZ). No fallback to the wall clock is taken."
    exit 3
  fi
else
  NOW_EPOCH="$(date -u +%s)"
fi
NOW_DAY="$(date -u -d "@$NOW_EPOCH" +%Y-%m-%d)"

# ── MEASUREMENT (chokepoint 1) ───────────────────────────────────────────────────────────────
# The helper's stdout is captured and its stderr discarded; neither is ever reproduced: the
# credential is bound in that child and this text lands on a public issue.
measure() {
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ -z "${!v:-}" ]]; then
      marker "query_failed" "reason=secret_unset secret=$v"
      echo "CANNOT ESTABLISH: $v is not set, so the Logs warehouse cannot be read. This says nothing about the store."
      exit 3
    fi
  done
  if [[ ! -x "$QUERY" ]]; then
    marker "query_failed" "reason=helper_missing"
    echo "CANNOT ESTABLISH: scripts/betterstack-query.sh is missing or not executable."
    exit 3
  fi

  local raw qrc
  raw="$("$QUERY" --since "$WINDOW" --grep "$PROBE_MARKER" --limit "$LIMIT" 2>/dev/null)"
  qrc=$?
  if [[ "$qrc" -ne 0 ]]; then
    marker "query_failed" "reason=helper_status status=$qrc"
    echo "CANNOT ESTABLISH: betterstack-query.sh failed (status $qrc). Its output is withheld on purpose: the credential is bound in that process. Read it from the workflow log."
    exit 3
  fi

  local nonempty parsed
  nonempty="$(printf '%s\n' "$raw" | grep -c '[^[:space:]]' || true)"
  if [[ "$nonempty" -eq 0 ]]; then
    marker "no_rows" "window=$WINDOW"
    echo "CANNOT ESTABLISH: zero $PROBE_MARKER rows in $WINDOW. The producer or the warehouse is dark; that is not evidence about the store."
    exit 3
  fi
  # Bytes arrived but none decoded as a warehouse row: an instrument fault (an error page, a
  # ClickHouse error body with a zero status), not an empty window.
  parsed="$(printf '%s\n' "$raw" | jq -R -r '
      fromjson? | select(type == "object" and (.raw | type) == "string")
      | (.raw | fromjson?) | select(type == "object") | "1"' 2>/dev/null | grep -c '^1$' || true)"
  if [[ "$parsed" -eq 0 ]]; then
    marker "query_failed" "reason=malformed lines=$nonempty"
    echo "CANNOT ESTABLISH: betterstack-query.sh answered $nonempty line(s) and none decoded as a warehouse row."
    exit 3
  fi

  # ANCHORED, NOT A BARE TOKEN: the row must come from the dedicated host (every host writes into
  # one Logs source), it must be a probe row by the shared predicate -- the probe's own emitter AND
  # a message that STARTS with the marker (the inngest event log is shipped as `doppler` on the
  # same host and quotes the marker whenever an issue about the probe is webhooked in) -- and the
  # role is the FIRST host_role= token, the same first-wins rule the field reader applies. The
  # helper's --grep is an unanchored LIKE, so this filter is the probe's own, never the query's.
  # dt is normalised ('T' -> ' ') so the sort compares like with like. jq's status is captured
  # BEFORE the sort: a failed selection is an instrument fault, never an empty window.
  local sel jrc rows
  sel="$(printf '%s\n' "$raw" | jq -R -r --arg h "$HOST" --arg hn "$HOST_NAME" "$INNGEST_PROBE_ROW_JQ"'
      fromjson? | select(type == "object") | . as $o
      | ((.raw // "") | fromjson?) | select(type == "object")
      | select(.host == $h and .host_name == $hn)
      | select(inngest_probe_row)
      | .message
      | select(((capture("(?:^| )host_role=(?<r>[^ ]*)")? // {r: ""}).r) == "dedicated")
      | [(($o.dt // "") | tostring | sub("T"; " ")), .] | @tsv' 2>/dev/null)"
  jrc=$?
  if [[ "$jrc" -ne 0 ]]; then
    marker "query_failed" "reason=selector_failed status=$jrc"
    echo "CANNOT ESTABLISH: the probe-row selection (jq over the shared predicate) failed with status $jrc, so no row was graded. This says nothing about the store."
    exit 3
  fi
  rows="$(printf '%s\n' "$sel" | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1)"
  if [[ -z "$rows" ]]; then
    marker "no_rows" "window=$WINDOW role=dedicated"
    echo "CANNOT ESTABLISH: no host_role=dedicated $PROBE_MARKER row in $WINDOW (rows from other roles, from another emitter or quoting content were set aside)."
    exit 3
  fi

  # Newest by dt: the sort is stable, so ties keep the helper's ascending order and the last line
  # wins either way.
  local newest dt dt_epoch age
  newest="$(printf '%s\n' "$rows" | tail -1)"
  dt="${newest%%$'\t'*}"
  ROW_MSG="${newest#*$'\t'}"
  dt_epoch=""
  if [[ "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
    dt_epoch="$(date -u -d "${dt:0:19}" +%s 2>/dev/null)" || dt_epoch=""
  fi
  if [[ -z "$dt_epoch" ]]; then
    marker "row_unusable" "field=dt"
    echo "CANNOT ESTABLISH: the newest probe row carries no readable YYYY-MM-DD HH:MM:SS timestamp."
    exit 3
  fi
  age=$(( NOW_EPOCH - dt_epoch ))
  if (( age < -FUTURE_SLACK_SECS )); then
    marker "row_unusable" "field=dt_future age_s=$age"
    echo "CANNOT ESTABLISH: the newest probe row is dated in the future. A row that never goes stale must not decide the verdict."
    exit 3
  fi
  if (( age > STALE_SECS )); then
    marker "producer_silent" "age_s=$age limit_s=$STALE_SECS"
    echo "CANNOT ESTABLISH: the newest dedicated probe row is ${age}s old (limit ${STALE_SECS}s). A silent producer must never read as a healthy store."
    exit 3
  fi

  SRC="$(field data_mount_src)"
  DEVID="$(field data_mount_devid)"
  local src_ok=0
  case "$SRC" in
    ""|n/a|__UNREADABLE__|__ABSENT__) src_ok=0 ;;
    /dev/*) src_ok=1 ;;
    *) src_ok=0 ;;
  esac
  if (( ! src_ok )) || [[ ! "$DEVID" =~ ^scsi-0HC_Volume_[0-9]+$ ]]; then
    marker "row_unusable" "data_mount_src=$(safe "$SRC") devid_pinned=$( [[ "$DEVID" =~ ^scsi-0HC_Volume_[0-9]+$ ]] && echo yes || echo no )"
    echo "CANNOT ESTABLISH: the newest dedicated probe row does not resolve the store's device. An unresolved device is not evidence of anything, so no alarm is raised on #8285."
    exit 3
  fi
  ROW_AGE="$age"
}

# First-wins field read over the whitespace-split message: the emitter writes each key once, so
# first-wins is lossless, and an appended tail cannot override a measured field. read -a does not
# glob, which matters because redis_key_patterns carries `*`.
field() { # <key> -> value, or __ABSENT__
  local k="$1" tok
  local -a toks
  read -r -a toks <<<"$ROW_MSG"
  for tok in "${toks[@]}"; do
    if [[ "$tok" == "$k="* ]]; then
      printf '%s' "${tok#"$k="}"
      return 0
    fi
  done
  printf '%s' "__ABSENT__"
}
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9/_.:-' '?' | head -c 64; }

# ── LEDGER (chokepoints 2 and 3) ─────────────────────────────────────────────────────────────
ledger_q() { # <jq filter over the stores array> -> string, empty on any failure
  jq -r --arg l "$LUKS_ROW" --arg b "$BACKSTOP_ROW" "$1" "$LEDGER" 2>/dev/null || true
}
read_ledger() {
  if [[ ! -r "$LEDGER" ]] || ! jq -e 'type == "object"' "$LEDGER" >/dev/null 2>&1; then
    marker "ledger_unreadable" "reason=unparseable"
    echo "CANNOT ESTABLISH: scripts/encryption-posture-ledger.json is missing or is not a JSON object."
    exit 3
  fi
  local n
  n="$(ledger_q '[.stores[]? | select(.store == $l)] | length')"
  if [[ "$n" != "1" ]]; then
    marker "ledger_unreadable" "reason=luks_row_count count=${n:-none}"
    echo "CANNOT ESTABLISH: the ledger holds ${n:-no} $LUKS_ROW row(s); exactly one is required."
    exit 3
  fi
  MECH="$(ledger_q '.stores[] | select(.store == $l) | .at_rest.mechanism | select(type == "string")')"
  MAPPER="$(ledger_q '.stores[] | select(.store == $l) | .device_binding.mapper | select(type == "string")')"
  if [[ -z "$MECH" ]]; then
    marker "ledger_unreadable" "reason=mechanism_missing"
    echo "CANNOT ESTABLISH: $LUKS_ROW has no at_rest.mechanism."
    exit 3
  fi
  if [[ ! "$MAPPER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    marker "ledger_unreadable" "reason=mapper_missing"
    echo "CANNOT ESTABLISH: $LUKS_ROW has no usable device_binding.mapper, so there is nothing to compare the store against."
    exit 3
  fi
  BACKSTOP_N="$(ledger_q '[.stores[]? | select(.store == $b)] | length')"
  if [[ "$BACKSTOP_N" != "0" && "$BACKSTOP_N" != "1" ]]; then
    marker "ledger_unreadable" "reason=backstop_row_count count=${BACKSTOP_N:-none}"
    echo "CANNOT ESTABLISH: the ledger holds ${BACKSTOP_N:-an unreadable number of} $BACKSTOP_ROW row(s); at most one is allowed."
    exit 3
  fi
  BACKSTOP_EXPIRES="$(ledger_q '[.stores[]? | select(.store == $b)] | first // {} | (.at_rest.exception.expires_on // .exception.expires_on // "") | select(type == "string")')"
}

# ── DECISION ─────────────────────────────────────────────────────────────────────────────────
decide() {
  local claims=0 on=0
  [[ "$MECH" == "luks" ]] && claims=1
  [[ "$SRC" == "/dev/mapper/$MAPPER" ]] && on=1

  if (( claims && ! on )); then
    marker "rollback_inversion" "claim=$MECH store=$(safe "$SRC") mapper=$MAPPER age_s=$ROW_AGE"
    echo "ACTION REQUIRED: backstop is the LIVE store — do NOT destroy hcloud_volume.inngest_redis. The ledger claims $LUKS_ROW is LUKS-encrypted, but the store is measured OFF /dev/mapper/$MAPPER, so the record is false. If this follows a sanctioned op=luks-rollback, revert the record per $RUNBOOK section 5a. If no rollback was run, investigate the mount first (the wrong-volume alert should also have paged)."
    exit 5
  fi
  if (( ! claims && on )); then
    marker "under_claim" "claim=$MECH store=$(safe "$SRC") mapper=$MAPPER age_s=$ROW_AGE"
    echo "ACTION REQUIRED: the store is measured ON /dev/mapper/$MAPPER, but the ledger claims '$MECH' for $LUKS_ROW. The record under-states the encryption: re-apply the luks row (the #8296 PR-2 flip) in a PR, see $RUNBOOK section 5a."
    exit 5
  fi
  # ARM-BEGIN backstop_expired
  if (( claims && on )) && [[ "${BACKSTOP_N:-0}" != "0" ]]; then
    if [[ ! "$BACKSTOP_EXPIRES" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -u -d "$BACKSTOP_EXPIRES" +%s >/dev/null 2>&1; then
      marker "ledger_unreadable" "reason=backstop_expires_on expires_on=$(safe "$BACKSTOP_EXPIRES")"
      echo "CANNOT ESTABLISH: the $BACKSTOP_ROW row exists but its exception.expires_on is not a YYYY-MM-DD date."
      exit 3
    fi
    # Epoch-second integers, not a lexicographic [[ ]] compare: both dates were validated above.
    NOW_DAY_S=$(date -u -d "$NOW_DAY" +%s 2>/dev/null || echo 0)
    EXPIRES_S=$(date -u -d "$BACKSTOP_EXPIRES" +%s 2>/dev/null || echo 0)
    if (( NOW_DAY_S > EXPIRES_S && EXPIRES_S > 0 )); then
      marker "backstop_expired" "expires_on=$BACKSTOP_EXPIRES now=$NOW_DAY"
      echo "ACTION REQUIRED: the store is on the LUKS mapper and the ledger agrees, and the plaintext backstop $BACKSTOP_ROW is past its expires_on ($BACKSTOP_EXPIRES). Destroy the backstop under #8285, then retire this probe as its RETIREMENT header says."
      exit 5
    fi
  fi
  # ARM-END backstop_expired
  if (( claims == on )); then
    marker "agree" "claim=$MECH store=$(safe "$SRC") mapper=$MAPPER age_s=$ROW_AGE"
    echo "healthy: nothing to do; this probe never closes #8285."
    exit 2
  fi
}

# ── MAIN
measure
read_ledger
decide
marker "unreachable"
echo "CANNOT ESTABLISH: the decision table fell through without a verdict. This is a probe bug; nothing was decided."
exit 3
