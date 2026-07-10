#!/usr/bin/env bash
# Follow-through soak for #6288 (post-deploy plateau of the zot registry restart-loop).
#
# WHAT IT PROVES. PR #6288 ships two slices in one immutable registry-host-replace:
#   Slice 1 — enriches the SOLEUR_ZOT_DISK reporter (cloud-init-registry.yml) with
#     zot_restarts / state_status / oom_killed / exit_code / oom_kills_5m / zot_anon_mb /
#     mem_total_mb / boot_id so a crash self-reports OOM-vs-not from Better Stack with NO SSH.
#   Slice 2 — bumps the host cx23(4 GB)->cx33(8 GB) + adds an ADR-062 --memory=7168m cap so
#     zot's ~35 GB store boot scan cannot host-OOM restart-loop the box.
#
# SOUND plateau signal = across a soak window that spans the full startup scan + first
# gcInterval(1h) + retention.delay(2h), for the NEWEST boot_id (the immutable replace REUSES
# the terraform hostname, so boot_id — not host — separates old-host from new-host events):
#   - zot_restarts is FLAT (max-min <= PLATEAU_TOL; the pre-fix loop climbed 88->261 in ~45 min)
#   - NO exit_code=137 (any 137 => an OOM exit; the current-host tell)
#   - oom_kills_5m == 0 across the window (journald kernel-OOM backstop)
#   - zot_anon_mb sits comfortably below the --memory cap (near-cap = the fix under-sized)
#
# WHY zot_anon_mb, not host used-memory (fable Change 1): a ~35 GB store scan pins page cache,
# so host used-memory fills to near-total regardless of whether zot's ANONYMOUS memory ever
# starved — gating on it would rubber-stamp PASS. zot_anon_mb (container cgroup anon RSS,
# page-cache-free) is the real pressure signal. (The host mem_used_mb field was dropped #6292 —
# same page-cache-confounding reason; the reporter now emits mem_total_mb only.)
#
# FAIL-SAFE: any query/auth/config failure, OR not-enough-soak-yet (a fresh host reads
# zot_restarts=0 before the scan/gc even happen — the decision rule is slope-over-a->=2h-window,
# NOT a single post-boot row), => TRANSIENT (exit 2), never PASS. #6288 can NEVER false-close on
# an immediate post-boot check.
#
# Exit semantics (per the sweep-followthroughs.sh contract):
#   0 = PASS       (plateau holds across the soak window; the sweeper closes #6288)
#   1 = FAIL       (still climbing / exit_code=137 / oom_kills_5m>0 / zot_anon_mb near cap)
#   2 = TRANSIENT  (query unreachable/unauth, no telemetry yet, or soak window not yet filled)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (already exported by
#   scheduled-followthrough-sweeper.yml). Optional overrides:
#   ZOT_RESTART_SOAK_WINDOW (Nh/Nm/Nd, default 6h), ZOT_MEMORY_CAP_MB (default 7168),
#   ZOT_RESTART_PLATEAU_TOL (default 3), ZOT_ANON_HEADROOM_MB (default 1024),
#   ZOT_MIN_SOAK_EVENTS (default 20), ZOT_MIN_SOAK_SPAN_SEC (default 7200 = 2h).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Shared trusted-region parse + newest-boot scoping (single source of truth with the #6291
# standing restart-loop alarm — the spoof-resistance invariant lives in ONE file, sourced here).
# shellcheck source=scripts/lib/zot-telemetry-parse.sh
source "$SCRIPT_DIR/../lib/zot-telemetry-parse.sh"
BQ="${ZOT_BQ_OVERRIDE:-$SCRIPT_DIR/../betterstack-query.sh}"

WINDOW="${ZOT_RESTART_SOAK_WINDOW:-6h}"
CAP_MB="${ZOT_MEMORY_CAP_MB:-7168}"
PLATEAU_TOL="${ZOT_RESTART_PLATEAU_TOL:-3}"
ANON_HEADROOM_MB="${ZOT_ANON_HEADROOM_MB:-1024}"
MIN_EVENTS="${ZOT_MIN_SOAK_EVENTS:-20}"
MIN_SPAN_SEC="${ZOT_MIN_SOAK_SPAN_SEC:-7200}"

if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  echo "TRANSIENT: invalid ZOT_RESTART_SOAK_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2; exit 2
fi
if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2; exit 2
fi

OUT="$("$BQ" --since "$WINDOW" --grep SOLEUR_ZOT_DISK --limit 5000 2>/dev/null)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (auth/config/network)" >&2; exit 2
fi
if [[ -z "$OUT" ]]; then
  echo "TRANSIENT: no SOLEUR_ZOT_DISK rows in ${WINDOW} — telemetry not observed yet (no deploy in window, or delivery not live)" >&2; exit 2
fi

# Trusted-region parse + newest-boot scoping via the shared helper (scripts/lib/zot-telemetry-parse.sh):
# lexical `sort` orders rows chronologically REGARDLESS of the query's ORDER BY (#6251-spirit); the
# free-text `zot_last_err=` tail (emitted LAST) is stripped BEFORE any key=value parse so a crafted
# zot log line (containing e.g. `boot_id=`/`exit_code=137`) cannot spoof the verdict fields.
TRUSTED="$(printf '%s\n' "$OUT" | zot_trusted_region)"

# Newest boot_id = the last (newest, post-sort) row carrying a real boot_id.
NEWEST_BOOT="$(printf '%s\n' "$TRUSTED" | zot_newest_boot)"
if [[ -z "$NEWEST_BOOT" ]]; then
  echo "TRANSIENT: no usable boot_id in window (pre-#6288 reporter, or all-sentinel rows) — cannot scope to the newest host" >&2; exit 2
fi

# Scope to the newest boot_id, chronological order.
SCOPED="$(printf '%s\n' "$TRUSTED" | zot_scope_to_boot "$NEWEST_BOOT")"
n_events="$(printf '%s\n' "$SCOPED" | grep -c . || true)"

# Soak-gate: enough events AND a wide-enough span. A fresh host reads zot_restarts=0 before the
# scan/gc happen; closing on that would be the "do not close on the immediate post-boot" trap.
first_dt="$(printf '%s\n' "$SCOPED" | head -1 | grep -oE '"dt":"[^"]+"' | head -1 | sed 's/.*"dt":"//; s/"$//')"
last_dt="$(printf '%s\n' "$SCOPED" | tail -1 | grep -oE '"dt":"[^"]+"' | head -1 | sed 's/.*"dt":"//; s/"$//')"
first_s="$(date -d "$first_dt" +%s 2>/dev/null || echo '')"
last_s="$(date -d "$last_dt" +%s 2>/dev/null || echo '')"
if [[ -z "$first_s" || -z "$last_s" ]]; then
  echo "TRANSIENT: could not parse event timestamps ('$first_dt'..'$last_dt') — inconclusive" >&2; exit 2
fi
span=$(( last_s - first_s ))
if [[ "$span" -lt 0 ]]; then
  echo "TRANSIENT: negative span (${span}s) after chronological sort — unexpected row shape; refusing to evaluate" >&2; exit 2
fi
if [[ "$n_events" -lt "$MIN_EVENTS" || "$span" -lt "$MIN_SPAN_SEC" ]]; then
  echo "TRANSIENT: soak not yet filled for boot_id=$NEWEST_BOOT (${n_events} events over ${span}s; need >=${MIN_EVENTS} events and >=${MIN_SPAN_SEC}s) — slope-over-a-window rule, not a single post-boot row" >&2; exit 2
fi

# Require >=1 NON-sentinel zot_restarts sample before ANY verdict. If docker inspect returned empty
# for the whole window (daemon fault, container never created, inspect-format drift), every row is
# zot_restarts=-1; every FAIL check below no-ops on sentinels and the probe would PASS on ZERO valid
# evidence — a vacuous close of #6288 while zot is actually DOWN. Treat "soak filled but no usable
# container data" as TRANSIENT, never PASS. (observability + test-design + pattern-recognition all
# converged on this false-PASS path.)
restarts="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values zot_restarts)"
if [[ -z "$restarts" ]]; then
  echo "TRANSIENT: soak filled (${n_events} events / ${span}s) but every zot_restarts is a -1 inspect-miss sentinel for boot_id=$NEWEST_BOOT — zot may be down/absent; cannot confirm a plateau on zero valid container samples" >&2; exit 2
fi

FAILS=()

# (1) restart plateau: max-min across the newest boot_id (sentinels already filtered above).
rmin="$(printf '%s\n' "$restarts" | sort -n | head -1)"
rmax="$(printf '%s\n' "$restarts" | sort -n | tail -1)"
rdelta=$(( rmax - rmin ))
if [[ "$rdelta" -gt "$PLATEAU_TOL" ]]; then
  FAILS+=("zot_restarts climbed ${rmin}->${rmax} (delta ${rdelta} > tol ${PLATEAU_TOL}) — the loop did NOT plateau")
fi

# (2) any OOM exit.
if printf '%s\n' "$SCOPED" | grep -qE 'exit_code=137'; then
  FAILS+=("exit_code=137 seen — an OOM exit; the host is still starving zot")
fi

# (3) container-cgroup OOM-kill counter (MONOTONIC memory.events oom_kill; survives the point-
# sampling race, unlike the zot_anon_mb gauge — the real cgroup-OOM confirmation). Any nonzero on
# the newest boot = the cgroup OOM-killed zot at least once.
maxoomk="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values zot_oom_kills | sort -n | tail -1)"
if [[ -n "$maxoomk" && "$maxoomk" -gt 0 ]]; then
  FAILS+=("zot_oom_kills reached ${maxoomk} — the container cgroup OOM-killed zot (monotonic memory.events counter)")
fi

# (4) journald kernel-OOM window backstop.
maxoom="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values oom_kills_5m | sort -n | tail -1)"
if [[ -n "$maxoom" && "$maxoom" -gt 0 ]]; then
  FAILS+=("oom_kills_5m peaked at ${maxoom} — the kernel OOM-killer fired in-window")
fi

# (5) anon RSS pressure near the --memory cap (context signal, backs up the monotonic counter).
threshold=$(( CAP_MB - ANON_HEADROOM_MB ))
maxanon="$(printf '%s\n' "$SCOPED" | zot_nonsentinel_values zot_anon_mb | sort -n | tail -1)"
if [[ -n "$maxanon" && "$maxanon" -gt "$threshold" ]]; then
  FAILS+=("zot_anon_mb peaked at ${maxanon} MB (> cap ${CAP_MB} - headroom ${ANON_HEADROOM_MB} = ${threshold}) — the --memory cap is under-sized")
fi

if [[ "${#FAILS[@]}" -gt 0 ]]; then
  echo "FAIL: zot restart-loop NOT resolved for boot_id=$NEWEST_BOOT over ${span}s / ${n_events} events:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  echo "Read the OOM decode table + zot_last_err in the #6288 PR body; escalate host size or route off the OOM hypothesis."
  exit 1
fi

echo "PASS: zot restart-loop plateaued for boot_id=$NEWEST_BOOT over ${span}s / ${n_events} events (>=1 valid container sample) — restarts flat (delta<=${PLATEAU_TOL}), no exit_code=137, zot_oom_kills=0, oom_kills_5m=0, zot_anon_mb below the ${CAP_MB}m cap. #6288 remediation holds."
exit 0
