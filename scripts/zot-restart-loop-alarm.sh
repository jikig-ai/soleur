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
# SECOND STREAM — SOLEUR_PRIVATE_NIC (#6415). This script also watches the registry host's
# private-NIC self-report and emits an INDEPENDENT NIC_ALARM_VERDICT block
# (GREEN|FIRE|ADVISORY|SILENT|TRANSIENT) on EVERY exit path. It is deliberately NOT folded into
# the exit code: the workflow maps any exit outside {0,1,3} to a Sentry 'error', so a new exit 4
# would report a NIC fire as a PROBE FAULT — contradicting the "a FIRE is NOT a monitor error"
# doctrine. The NIC evaluation therefore runs BEFORE every zot leg, because those legs exit early
# on a probe fault / zero evidence (a zot isolation FATAL ⇒ zot_restarts=-1 ⇒ exit 2) and would
# otherwise skip the NIC check exactly when a correlated NIC fault is most likely.
#
# WHY A SECOND STREAM AT ALL: #6400 — the host booted without its private NIC, so the fleet's
# primary pull path was dead for ~14 days while everything here stayed GREEN. A NIC-less host
# keeps PUBLIC egress, so the disk heartbeat kept pinging and this alarm's own SOLEUR_ZOT_DISK
# rows kept flowing. Neither signal can be re-thresholded into covering it — hence a new one.
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

# --- Private-NIC stream (#6415) -----------------------------------------------------------
# A SECOND, INDEPENDENT verdict carried alongside the zot one. It is NOT folded into the exit
# code: the contract (0/1/2/3) is consumed by scheduled-zot-restart-loop.yml, whose Sentry
# status mapping treats any non-0/1/3 as 'error' — so a new exit 4 would report a NIC fire as a
# *probe fault*, contradicting that file's "a FIRE is NOT a monitor error" doctrine. Instead the
# NIC facts travel as their own NIC_ALARM_* output block, printed on EVERY exit path.
#
# This is what makes the NIC check survive the zot early-exits. The zot legs below exit at the
# first sign of a probe fault / zero evidence (a zot isolation FATAL yields zot_restarts=-1 =>
# zero-evidence => exit 2), and anything appended AFTER them would simply never run when zot is
# unhealthy — precisely when a correlated NIC fault is most likely.
NIC_VERDICT=""
NIC_CAUSE=""
NIC_DETAIL=""

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
  # The NIC block rides EVERY exit path — that is the whole point (see above).
  echo "NIC_ALARM_VERDICT=${NIC_VERDICT:-TRANSIENT}"
  [[ -n "$NIC_DETAIL" ]] && echo "NIC_ALARM_DETAIL=${NIC_DETAIL}"
  echo "NIC_ALARM_CAUSE=${NIC_CAUSE:-n/a}"
  echo "=============================="
  exit "$code"
}

# evaluate_nic: sets NIC_VERDICT / NIC_CAUSE / NIC_DETAIL from the SOLEUR_PRIVATE_NIC stream.
#   GREEN     — newest boot has nic_ok=true, converged_by=already, no reboots
#   FIRE      — newest boot has nic_ok=false (the terminal state; the guard could not converge)
#   ADVISORY  — the NIC was absent and the guard self-healed it (nic_ok=true, so FIRE does NOT
#               cover it). Without this the race would self-heal silently forever — a LOST
#               ceiling, since today it at least surfaces eventually as an outage.
#   SILENT    — the guard went dark (absence), proven against a control marker + 24h lookback
#   TRANSIENT — probe fault / fresh host / no usable boot_id
evaluate_nic() {
  local main main_rc control control_rc look look_rc trusted newest scoped
  local conv rc nets max_rb

  main="$("$BQ" --since "$WINDOW" --grep SOLEUR_PRIVATE_NIC --limit 5000 2>/dev/null)"; main_rc=$?
  if [[ "$main_rc" -ne 0 ]]; then
    NIC_VERDICT="TRANSIENT"
    NIC_DETAIL="SOLEUR_PRIVATE_NIC query failed (rc=${main_rc}) — auth/config/network probe fault"
    return
  fi

  if [[ -z "$main" ]]; then
    # INDEPENDENT absence probe. Deliberately NOT the zot PRODUCER_SILENT branch above: that one
    # is computed only when $MAIN (SOLEUR_ZOT_DISK) is empty, so a dead NIC guard sitting beside
    # a live disk heartbeat would sail straight past it and read GREEN. Two producers, two
    # absence checks. Reuses the same control-marker -> LOOKBACK ladder.
    control="$("$BQ" --since "$WINDOW" --limit 1 2>/dev/null)"; control_rc=$?
    if [[ "$control_rc" -ne 0 || -z "$control" ]]; then
      NIC_VERDICT="TRANSIENT"
      NIC_DETAIL="recent ${WINDOW} empty for SOLEUR_PRIVATE_NIC AND the control-marker query is empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
      return
    fi
    look="$("$BQ" --since "$LOOKBACK" --grep SOLEUR_PRIVATE_NIC --limit 1 2>/dev/null)"; look_rc=$?
    if [[ "$look_rc" -eq 0 && -n "$look" ]]; then
      NIC_VERDICT="SILENT"
      NIC_DETAIL="SOLEUR_PRIVATE_NIC present in the last ${LOOKBACK} but ABSENT in the recent ${WINDOW} — the private-NIC guard went dark"
      NIC_CAUSE="nic guard dark: its 5-min cron or the 'doppler run --project soleur-registry --config prd' wrapper stopped (cloud-init-registry.yml). The disk heartbeat CANNOT backstop this — it is a different producer on a different token path."
      return
    fi
    NIC_VERDICT="TRANSIENT"
    NIC_DETAIL="no SOLEUR_PRIVATE_NIC in the recent ${WINDOW} or the last ${LOOKBACK} — fresh host, or the guard is not deployed yet (pre-#6415 host)"
    return
  fi

  trusted="$(printf '%s\n' "$main" | zot_trusted_region)"
  newest="$(printf '%s\n' "$trusted" | zot_newest_boot)"
  if [[ -z "$newest" ]]; then
    NIC_VERDICT="TRANSIENT"
    NIC_DETAIL="SOLEUR_PRIVATE_NIC rows present but no usable boot_id — cannot scope to the newest host"
    return
  fi
  # Scope to the NEWEST boot. An any-in-window read would fire for up to WINDOW (3h) after every
  # successful self-heal — i.e. page on the happy path.
  scoped="$(printf '%s\n' "$trusted" | zot_scope_to_boot "$newest")"

  conv="$(printf '%s\n' "$scoped" | grep -oE 'converged_by=[a-z]+' | tail -1 | cut -d= -f2)"
  rc="$(printf '%s\n' "$scoped" | grep -oE 'imds_rc=[0-9]+' | tail -1 | cut -d= -f2)"
  nets="$(printf '%s\n' "$scoped" | grep -oE 'imds_nets=[0-9]+' | tail -1 | cut -d= -f2)"
  max_rb="$(printf '%s\n' "$scoped" | grep -oE 'reboot_count=[0-9]+' | cut -d= -f2 | sort -n | tail -1)"
  [[ -n "$max_rb" ]] || max_rb=0

  if printf '%s\n' "$scoped" | grep -qE 'nic_ok=false'; then
    NIC_VERDICT="FIRE"
    # The decode the 9-field emit exists to make possible.
    if [[ "${rc:-0}" != "0" ]]; then
      NIC_CAUSE="H1 — the metadata service was unreachable (imds_rc=${rc}). The guard will NOT reboot without corroboration, so this is terminal until IMDS recovers or an operator re-dispatches registry-host-replace."
    elif [[ "${nets:-0}" == "0" ]]; then
      NIC_CAUSE="H2 — IMDS answered but reports NO private network attached (imds_rc=0, imds_nets=0): the hcloud_server_network additive online-attach had not landed. Expect a later tick to self-heal; if it persists, the attach itself failed."
    else
      NIC_CAUSE="third mode — the attach LANDED (imds_nets=${nets}) but the guest never configured the address; converged_by=${conv:-none}, reboot_count=${max_rb}/2. If reboot_count is at the cap the guard is out of budget and this is terminal."
    fi
    NIC_DETAIL="newest boot_id=${newest}: nic_ok=false converged_by=${conv:-none} imds_rc=${rc:-?} imds_nets=${nets:-?} reboot_count=${max_rb}"
    return
  fi

  # A SUCCESSFUL self-heal emits nic_ok=true, so the FIRE branch above cannot see it. The durable
  # signal is reboot_count>0 on the newest boot: the guard reboots, the host comes up under a NEW
  # boot_id, and the root-disk counter carries the fact across. (converged_by=reboot lives on the
  # PREVIOUS boot_id, so keying on it alone would miss the post-reboot steady state.)
  if [[ "$max_rb" -gt 0 ]] || printf '%s\n' "$scoped" | grep -qE 'converged_by=reboot'; then
    NIC_VERDICT="ADVISORY"
    NIC_DETAIL="newest boot_id=${newest}: nic_ok=true but reboot_count=${max_rb} — the private NIC was ABSENT at boot and the guard converged it by rebooting"
    NIC_CAUSE="the boot race is REAL on this host and the guard healed it — H2 confirmed empirically. Not an outage: serving is fine. This is the standing signal that the race recurs (without it, a silently-self-healing race is never reported)."
    return
  fi

  NIC_VERDICT="GREEN"
  NIC_DETAIL="newest boot_id=${newest}: nic_ok=true converged_by=${conv:-already} imds_nets=${nets:-?} reboot_count=0 — the private NIC came up at boot with no intervention"
}

if [[ ! -x "$BQ" ]]; then
  VERDICT="TRANSIENT"; DETAIL="betterstack-query.sh not found/executable at $BQ"
  NIC_VERDICT="TRANSIENT"; NIC_DETAIL="betterstack-query.sh not found/executable at $BQ"
  emit_and_exit 2
fi

# Evaluate the NIC stream FIRST — before any zot leg can early-exit.
evaluate_nic

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
