#!/usr/bin/env bash
# Standing zot registry restart-loop RECURRENCE alarm (#6291).
#
# WHAT IT WATCHES. The self-hosted zot registry (ADR-096, one deny-all / no-SSH Hetzner host)
# can crash-loop in a way the existing disk-absence heartbeat (`soleur-registry-disk-prd`) is
# structurally blind to: that heartbeat pings ONLY while `/var/lib/zot < 85%`, so a
# disk-independent OOM restart-loop (the #6288 failure mode — zot OOM-restart-looping ~4/min
# during the boot scan of the ~35 GB store) leaves the heartbeat GREEN throughout. This checker
# stands watch on the enriched `SOLEUR_ZOT_DISK` self-report (#6288/#6296) in Better Stack Logs
# (source 2457081), scoped to the NEWEST boot_id (the immutable host-replace REUSES the terraform
# hostname, so boot_id — not host — separates old-host from new-host events).
#
# DISTINCT FROM the #6288 soak probe (scripts/followthroughs/zot-restart-plateau-6288.sh): this is
# CONTINUOUS (no soak gate — no MIN_EVENTS / MIN_SPAN), it NEVER closes #6288, and it fires on a
# consecutive-CLIMB (a crash-loop in progress), not a soak-window max-min plateau. Both source the
# SAME trusted-region parse (scripts/lib/zot-telemetry-parse.sh) so the spoof-resistance invariant
# has ONE home.
#
# FIRING CONDITIONS — on the newest boot_id, ANY of:
#   (A) a row has exit_code=137            (an OOM exit)
#   (B) zot_restarts (non-'-1' samples) STRICTLY INCREASES across >= CLIMB_N consecutive events
#       (the crash-loop signature — a CLIMB, not a bare max-min delta: a single legitimate restart
#        bumps the counter once and does NOT trip this)
#   (C) a row has oom_kills_5m > 0         (journald kernel-OOM backstop)
#
# EXIT CONTRACT (consumed by .github/workflows/scheduled-zot-restart-loop.yml):
#   0 GREEN            — newest boot flat/absent climb, no 137, oom_kills_5m==0 (auto-close issues)
#   1 FIRE            — condition A|B|C on the newest boot (open/update [ci/zot-restart-loop])
#   2 TRANSIENT       — probe fault (query fail/creds unset) OR the control-marker query is ALSO
#                       empty (Better Stack unreachable) OR zero valid evidence (all-'-1' sentinels
#                       with no 137/oom). NO GitHub issue — the workflow emits an ERRORED Sentry
#                       check-in so persistent probe-death surfaces as a monitor problem.
#   3 PRODUCER-SILENT — the control marker returns rows (BS reachable + creds valid) AND a 24h
#                       lookback has SOLEUR_ZOT_DISK rows (reporter WAS alive) BUT the recent WINDOW
#                       is empty → the token-gated reporter went dark while the token-free disk
#                       heartbeat + Sentry monitor stay GREEN (open/update [ci/zot-telemetry-silent]).
#
# FAIL-SAFE: NEVER FIRE on zero valid evidence. A standing alarm that pages on its own query fault
# trains the operator to ignore it (Sharp Edges). COVERAGE SEAM (deliberate trade): a *non-OOM*
# crash severe enough that `docker inspect` returns only -1 sentinels — with no exit_code=137 and
# oom_kills_5m==0 — degrades to TRANSIENT, not FIRE. This buys ZERO false-positives at the cost of a
# narrow non-OOM false-negative; the #6288 OOM mode is still caught by (A)+(C), and TRANSIENT is
# loud in the Actions log + errored Sentry check-in.
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (already
# exported by the workflow from secrets, or injected via `doppler run -p soleur -c prd_terraform`
# for a local dry-run). Only ZOT_BQ_OVERRIDE (the test seam) is env-exposed — WINDOW/CLIMB_N are
# named constants below, NOT overridable, so the cadence/window coupling cannot drift at runtime.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/zot-telemetry-parse.sh
source "$SCRIPT_DIR/lib/zot-telemetry-parse.sh"

BQ="${ZOT_BQ_OVERRIDE:-$SCRIPT_DIR/betterstack-query.sh}"

# --- Named constants (NOT env overrides) -------------------------------------------------
# WINDOW is the recent evaluation window. It MUST stay >= CLIMB_N x the reporter's emit interval
# (5 min) so >= CLIMB_N consecutive samples are always present within it: 3h / 5min ~= 36 events
# per boot >> CLIMB_N. Detection is WINDOW-bound, NOT poll-bound — the workflow's 30-min cadence
# only governs MTTD, never whether a loop is caught. Do NOT shrink WINDOW below CLIMB_N x 5min.
WINDOW="3h"
# LOOKBACK discriminates PRODUCER-SILENT (reporter recently alive, now dark) from a fresh
# never-installed host (no rows ever). 24h >> the 5-min emit + any plausible reboot window.
LOOKBACK="24h"
# CLIMB_N = the number of consecutive strictly-increasing zot_restarts samples that constitutes a
# crash-loop. 3 consecutive climbing events (2 increments in a row) is the loop signature; a lone
# legitimate restart (one increment, then flat) never reaches it. Referenced by the tests + the
# cadence sharp-edge.
CLIMB_N=3

VERDICT=""
CAUSE=""
DETAIL=""

emit_and_exit() {
  # $1 = exit code. Prints the machine-readable verdict block (the workflow greps
  # ZOT_ALARM_VERDICT= + ZOT_ALARM_CAUSE=) then exits with the contract code.
  local code="$1"
  echo "=== ZOT RESTART-LOOP ALARM ==="
  echo "ZOT_ALARM_VERDICT=${VERDICT}"
  echo "ZOT_ALARM_EXIT=${code}"
  echo "ZOT_ALARM_WINDOW=${WINDOW}"
  echo "ZOT_ALARM_CLIMB_N=${CLIMB_N}"
  [[ -n "$DETAIL" ]] && echo "ZOT_ALARM_DETAIL=${DETAIL}"
  echo "ZOT_ALARM_CAUSE=${CAUSE:-n/a}"
  echo "=============================="
  exit "$code"
}

if [[ ! -x "$BQ" ]]; then
  VERDICT="TRANSIENT"; DETAIL="betterstack-query.sh not found/executable at $BQ"
  emit_and_exit 2
fi

# --- Recent-window main query ------------------------------------------------------------
MAIN="$("$BQ" --since "$WINDOW" --grep SOLEUR_ZOT_DISK --limit 5000 2>/dev/null)"; main_rc=$?

if [[ "$main_rc" -ne 0 ]]; then
  # The probe itself failed (auth/network/creds-unset) — a probe fault is TRANSIENT, never a page.
  VERDICT="TRANSIENT"; DETAIL="Better Stack query failed (rc=${main_rc}) — auth/config/network probe fault"
  emit_and_exit 2
fi

if [[ -z "$MAIN" ]]; then
  # No SOLEUR_ZOT_DISK rows in the recent window. Discriminate probe-fault / fresh-host / silence
  # via a bare control-marker query (proves BS reachability + valid creds) + a 24h lookback.
  CONTROL="$("$BQ" --since "$WINDOW" --limit 1 2>/dev/null)"; control_rc=$?
  if [[ "$control_rc" -ne 0 || -z "$CONTROL" ]]; then
    VERDICT="TRANSIENT"; DETAIL="recent ${WINDOW} empty AND control-marker query empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
    emit_and_exit 2
  fi
  # Better Stack is reachable. Was the reporter alive within the last 24h?
  LOOK="$("$BQ" --since "$LOOKBACK" --grep SOLEUR_ZOT_DISK --limit 1 2>/dev/null)"; look_rc=$?
  if [[ "$look_rc" -eq 0 && -n "$LOOK" ]]; then
    VERDICT="PRODUCER_SILENT"
    DETAIL="SOLEUR_ZOT_DISK present in the last ${LOOKBACK} but ABSENT in the recent ${WINDOW} — the token-gated reporter went dark while the disk heartbeat + Sentry monitor stay GREEN"
    CAUSE="reporter dark: check BETTERSTACK_LOGS_TOKEN (soleur-registry/prd) rotation / ingest outage; the token-free disk heartbeat cannot backstop this (cloud-init-registry.yml)"
    emit_and_exit 3
  fi
  VERDICT="TRANSIENT"; DETAIL="no SOLEUR_ZOT_DISK in the recent ${WINDOW} OR the last ${LOOKBACK} and Better Stack is reachable — fresh / never-installed host (not producer-silence)"
  emit_and_exit 2
fi

# --- Trusted-region parse + newest-boot scoping (shared helper) ---------------------------
TRUSTED="$(printf '%s\n' "$MAIN" | zot_trusted_region)"
NEWEST_BOOT="$(printf '%s\n' "$TRUSTED" | zot_newest_boot)"
if [[ -z "$NEWEST_BOOT" ]]; then
  VERDICT="TRANSIENT"; DETAIL="SOLEUR_ZOT_DISK rows present but no usable boot_id (pre-#6288 reporter, or all-unknown) — cannot scope to the newest host"
  emit_and_exit 2
fi
SCOPED="$(printf '%s\n' "$TRUSTED" | zot_scope_to_boot "$NEWEST_BOOT")"

# --- Evidence extraction (newest boot only) ----------------------------------------------
# Condition A — any OOM exit.
has_137=false
if printf '%s\n' "$SCOPED" | grep -qE 'exit_code=137'; then has_137=true; fi

# Condition C — journald kernel-OOM window backstop peak.
max_oom5m="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values oom_kills_5m | sort -n | tail -1)"
[[ -n "$max_oom5m" ]] || max_oom5m=0

# oom_killed=true on any newest-boot row (cgroup-cap-contained OOM, for cause attribution).
oom_killed_true=false
if printf '%s\n' "$SCOPED" | grep -qE 'oom_killed=true'; then oom_killed_true=true; fi

# zot_restarts non-sentinel samples, in chronological (row) order — the climb evidence.
restarts="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values zot_restarts)"

# --- Fail-safe: never FIRE on zero valid evidence ----------------------------------------
# If every zot_restarts is a -1 inspect-miss sentinel AND there is no 137 and no kernel OOM, the
# newest boot carries no usable container data (daemon fault / inspect-format drift). Refuse to
# FIRE or PASS on zero evidence → TRANSIENT (the documented non-OOM coverage seam).
if [[ -z "$restarts" && "$has_137" == false && "$max_oom5m" -eq 0 ]]; then
  VERDICT="TRANSIENT"
  DETAIL="newest boot_id=${NEWEST_BOOT}: every zot_restarts is a -1 inspect-miss sentinel and no exit_code=137 / oom_kills_5m>0 — zero valid evidence (non-OOM coverage seam), cannot confirm a loop"
  emit_and_exit 2
fi

# --- Condition B: strictly-increasing climb across >= CLIMB_N consecutive events ----------
max_run=0; climb_run=0; prev=""
while IFS= read -r v; do
  [[ -z "$v" ]] && continue
  if [[ -n "$prev" && "$v" -gt "$prev" ]]; then
    climb_run=$((climb_run + 1))
  else
    climb_run=1
  fi
  [[ "$climb_run" -gt "$max_run" ]] && max_run="$climb_run"
  prev="$v"
done <<< "$restarts"
climb_fire=false
if [[ "$max_run" -ge "$CLIMB_N" ]]; then climb_fire=true; fi

# --- Verdict -----------------------------------------------------------------------------
if [[ "$has_137" == true || "$climb_fire" == true || "$max_oom5m" -gt 0 ]]; then
  VERDICT="FIRE"
  # Decoded cause (decode table from the #6288 reporter).
  if [[ "$has_137" == true && "$max_oom5m" -gt 0 ]]; then
    CAUSE="host/kernel OOM — exit_code=137 AND oom_kills_5m=${max_oom5m} (the box ran out of memory)"
  elif [[ "$oom_killed_true" == true ]]; then
    CAUSE="cgroup --memory cap contained the OOM — oom_killed=true (container-scoped OOM)"
  elif [[ "$has_137" == true ]]; then
    CAUSE="OOM exit — exit_code=137 without an in-window journald kernel-OOM (cgroup/host memory pressure)"
  elif [[ "$max_oom5m" -gt 0 ]]; then
    CAUSE="kernel OOM-killer fired in-window — oom_kills_5m=${max_oom5m}"
  else
    # Pure condition-B climb, no OOM signal → non-OOM crash-loop; surface the redacted log tail.
    last_err="$(printf '%s\n' "$MAIN" | grep -F "boot_id=$NEWEST_BOOT" | tail -1 | sed -n 's/.* zot_last_err=//p' | sed 's/"}$//')"
    CAUSE="non-OOM crash-loop — zot_restarts climbed across >= ${CLIMB_N} consecutive events; zot_last_err tail: ${last_err:-none}"
  fi
  DETAIL="newest boot_id=${NEWEST_BOOT}: 137=${has_137} climb_run=${max_run}(>=${CLIMB_N}?${climb_fire}) oom_kills_5m_peak=${max_oom5m}"
  emit_and_exit 1
fi

VERDICT="GREEN"
DETAIL="newest boot_id=${NEWEST_BOOT}: no exit_code=137, longest restart climb ${max_run} < CLIMB_N=${CLIMB_N}, oom_kills_5m=0 — registry serving healthy"
emit_and_exit 0
