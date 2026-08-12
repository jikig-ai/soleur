#!/usr/bin/env bash
# inngest-server-flip-guard.sh — the P1-5 arm-atomicity ExecStartPre guard for
# inngest-server.service on the dedicated Inngest host (#6178, ADR-100).
#
# Wired ONLY on the dedicated host (DOPPLER_PROJECT=soleur-inngest; inngest-bootstrap.sh
# gates the ExecStartPre line on that project so the co-located web host's inngest-server
# is never gated). Invoked via `doppler run --config prd` (the soleur-inngest project resolves
# from EnvironmentFile=/etc/default/inngest-server, #6555) so the env carries
# INNGEST_POSTGRES_URI + INNGEST_CUTOVER_FLIP.
#
# It BLOCKS the start (exit non-zero) when BOTH:
#   * INNGEST_POSTGRES_URI resolves to the PROD durable backend, AND
#   * the cutover flag is NOT in {armed, flipping, flushed, done}
# i.e. the prod URI has been armed into Doppler but the gated flip has not begun. Without
# this, a crash / OnBootSec / operator restart in that window would bring up a SECOND prod
# scheduler against the still-dirty dark Redis (the double-fire race). armed/flipping/flushed/done
# are the only states where a prod-URI start is legitimate (mid-flip, or post-cutover). `flushed`
# is included because the flip FSM itself starts the server AT flag=flushed (ADR-100; the flip
# oneshot's forward path and its flushed-RESUME arm both call `start_server` while flag=flushed,
# after asserting DBSIZE==0 on the dark Redis) — so without it the guard blocks the FSM's OWN
# controlled start, not just an unplanned restart.
#
# Prod detection: the prod backend is the dedicated Supabase project ref
# `pigsfuxruiopinouvjwy` (a NON-secret identifier, already in inngest.tf) — a stable
# substring of INNGEST_POSTGRES_URI. Override the marker via INNGEST_PROD_URI_MARKER.
# The URI itself is NEVER echoed (AC-NOBODY) — only the is_prod boolean + the flag.
#
# --- DIAGNOSTIC BOOT (#7228) ------------------------------------------------------------------
# The problem it solves. After the 2026-08-11 rollback the flag rests at `rollback`, which is
# OUTSIDE the allowlist below, so this guard refuses EVERY prod-URI start on the dedicated host.
# That is correct — but it also means a REPLACED host can never attempt a bind, so every
# hypothesis about why :8288 was never bound stays UNKNOWN forever and the replace teaches us
# nothing. The original boot trace is unrecoverable (Better Stack retention is ~3 days against a
# 12-day-old boot), so a boot that can actually try is the only remaining way to decide it.
#
# INNGEST_DIAGNOSTIC_BOOT=1 lets the host start against a NON-DURABLE backend, where a second
# prod scheduler is impossible, so it can bind :8288 and emit a discriminating `net-health` row.
#
# WHY THIS IS NOT A BYPASS OF THE DOUBLE-SCHEDULER GUARD. A flag that merely ASSERTS "I am not
# durable" would be exactly that — one stale Doppler value away from starting a second prod
# scheduler against a live queue. So the guard does not trust the flag: it VERIFIES the unit it
# is about to start, using the durable-detection sentinel the codebase already maintains for this
# purpose. `--postgres-max-open-conns` appears in the ExecStart argv IFF the backend is durable
# (inngest-bootstrap.sh keeps it FIRST in BACKEND_FLAGS and forbids promoting it to the shared
# prefix precisely so it stays a reliable discriminator). Absent sentinel ⇒ SQLite-only ⇒ the
# server cannot reach prod Postgres ⇒ no second scheduler is possible, whatever the flag says.
#
# The two failure directions are therefore both closed:
#   * diagnostic requested AND the unit is non-durable  -> ALLOW (the intended path)
#   * diagnostic requested BUT the unit IS durable      -> BLOCK, loudly. This means the bootstrap
#     did NOT apply diagnostic mode while something asked for it, i.e. the two halves disagree —
#     the one state in which allowing would start a real second prod scheduler.
#
# Fixture seams (CI has no doppler): GUARD_POSTGRES_URI, GUARD_FLIP_FLAG, GUARD_DIAGNOSTIC_BOOT,
# GUARD_UNIT_FILE.
set -euo pipefail

readonly LOG_TAG="inngest-server-flip-guard"
readonly PROD_MARKER="${INNGEST_PROD_URI_MARKER:-pigsfuxruiopinouvjwy}"
# The argv token that is present IFF the backend is durable. Kept in lockstep with
# inngest-bootstrap.sh's BACKEND_FLAGS by inngest-server-flip-guard.test.sh.
readonly DURABLE_SENTINEL="--postgres-max-open-conns"
readonly UNIT_FILE="${GUARD_UNIT_FILE:-/etc/systemd/system/inngest-server.service}"

# Seam-or-env, with whitespace trimmed off the flag.
POSTGRES_URI="${GUARD_POSTGRES_URI-${INNGEST_POSTGRES_URI:-}}"
FLIP_FLAG="$(printf '%s' "${GUARD_FLIP_FLAG-${INNGEST_CUTOVER_FLIP:-}}" | tr -d '[:space:]')"
DIAGNOSTIC="$(printf '%s' "${GUARD_DIAGNOSTIC_BOOT-${INNGEST_DIAGNOSTIC_BOOT:-}}" | tr -d '[:space:]')"

is_prod=false
if [[ -n "$POSTGRES_URI" && "$POSTGRES_URI" == *"$PROD_MARKER"* ]]; then
  is_prod=true
fi

diagnostic_requested=false
case "$DIAGNOSTIC" in
  1 | true | TRUE | yes | YES) diagnostic_requested=true ;;
esac

if [[ "$diagnostic_requested" == true ]]; then
  # Read the unit rather than believing the flag. A missing unit file is treated as DURABLE
  # (fail closed): if we cannot prove the backend is non-durable, we must not relax the guard.
  unit_is_durable=true
  if [[ -r "$UNIT_FILE" ]] && ! grep -qF -- "$DURABLE_SENTINEL" "$UNIT_FILE"; then
    unit_is_durable=false
  fi
  if [[ "$unit_is_durable" == true ]]; then
    logger -t "$LOG_TAG" "BLOCK: INNGEST_DIAGNOSTIC_BOOT is set but the installed unit still carries the durable sentinel — refusing (the two halves disagree; allowing would start a SECOND prod scheduler)" 2>/dev/null || true
    echo "ERROR: refusing inngest-server start — INNGEST_DIAGNOSTIC_BOOT is set, but ${UNIT_FILE} still carries ${DURABLE_SENTINEL} (or is unreadable), so the backend is durable or unprovable. Diagnostic boot requires the SQLite-only ExecStart form; re-run inngest-bootstrap.sh with INNGEST_DIAGNOSTIC_BOOT=1 so the two halves agree." >&2
    exit 1
  fi
  # Proven non-durable: prod is unreachable by construction, so a prod-flagged URI cannot
  # produce a second scheduler and the flag allowlist below need not gate this start.
  logger -t "$LOG_TAG" "DIAGNOSTIC: unit is SQLite-only (no ${DURABLE_SENTINEL}) — treating as non-prod so the host can bind :8288 and emit net-health. flag='${FLIP_FLAG:-unset}'" 2>/dev/null || true
  is_prod=false
fi

flag_ok=false
case "$FLIP_FLAG" in
  armed | flipping | flushed | done) flag_ok=true ;;
esac

if [[ "$is_prod" == true && "$flag_ok" == false ]]; then
  logger -t "$LOG_TAG" "BLOCK: prod Postgres URI with cutover flag='${FLIP_FLAG:-unset}' not in {armed,flipping,flushed,done} — refusing inngest-server start (P1-5)" 2>/dev/null || true
  echo "ERROR: refusing inngest-server start — prod Postgres URI with cutover flag '${FLIP_FLAG:-unset}' is not in {armed,flipping,flushed,done} (P1-5 arm-atomicity guard; would start a second prod scheduler)" >&2
  exit 1
fi

# --- #7228 (3.7): a `done` INHERITED from a different host must not authorize a prod start ----
# THE HAZARD THE ALLOWLIST ALONE CANNOT SEE. The cutover flag lives in Doppler, which OUTLIVES
# THE HOST. `done` means "the flip completed" — but on WHICH machine? The 2026-07-30 host recorded
# `done`, never bound :8288, and the flag stayed `done` for twelve days. A REPLACED host therefore
# boots and inherits a `done` it never earned, the allowlist above says ALLOW, and if the
# co-located scheduler is still serving the registry that is precisely the double-fire race
# ADR-100's P1-5 guard exists to prevent — reached through the guard rather than around it.
#
# The stamp lives in its OWN Doppler key, never appended to the flag value: `done@hetzner-123`
# would fall through the exact `case` match above and block a legitimately-completed host on
# every reboot, and would break this file's own lockstep test, which parses `flag_set` literals.
#
# SCOPED TO `done`, deliberately. The other allowlisted states are transient and belong to a flip
# that is actively in progress on THIS host; only `done` is terminal and therefore inheritable.
# Gating the transient states on a stamp the FSM has not written yet would deadlock the cutover.
#
# FAIL CLOSED on an unresolvable identity, but only when it CHANGES the verdict: if this host
# cannot learn its own instance id it cannot prove the `done` is its own. The FSM refuses to
# write an unstamped `done` for the same reason, so an absent stamp against a `done` flag means
# either a pre-#7228 completion or an inherited one — neither is provably this host's.
INSTANCE_STAMP="$(printf '%s' "${GUARD_DONE_INSTANCE-${INNGEST_CUTOVER_DONE_INSTANCE:-}}" | tr -d '[:space:]')"

if [[ "$is_prod" == true && "$FLIP_FLAG" == "done" ]]; then
  self_id="$(printf '%s' "${GUARD_INSTANCE_ID-}" | tr -d '[:space:]')"
  if [[ -z "$self_id" ]]; then
    # Hetzner IMDS only — matching the FSM's and the probe's resolution. /etc/machine-id is
    # confidential per machine-id(5) and this value reaches a journald row.
    imds_id="$(curl -sf --max-time 3 http://169.254.169.254/hetzner/v1/metadata/instance-id 2>/dev/null || true)"
    case "$imds_id" in
      '' | *[!0-9]*) self_id="" ;;
      *) self_id="hetzner-$imds_id" ;;
    esac
  fi
  if [[ -z "$INSTANCE_STAMP" || -z "$self_id" || "$INSTANCE_STAMP" != "$self_id" ]]; then
    logger -t "$LOG_TAG" "BLOCK: cutover flag='done' but its instance stamp does not identify THIS host (stamp='${INSTANCE_STAMP:-unset}' self='${self_id:-unresolvable}') — refusing a prod start on an INHERITED done (#7228)" 2>/dev/null || true
    echo "ERROR: refusing inngest-server start — the cutover flag is 'done' but ${INSTANCE_STAMP:+its instance stamp '${INSTANCE_STAMP}' }does not match this host${self_id:+ ('${self_id}')}. The flag outlives the host, so a replaced machine inherits a 'done' it never earned; starting here could run a SECOND prod scheduler. Re-run the cutover on this host (it will re-stamp ${INSTANCE_STAMP:+INNGEST_CUTOVER_DONE_INSTANCE}), or start diagnostically with INNGEST_DIAGNOSTIC_BOOT=1." >&2
    exit 1
  fi
fi

logger -t "$LOG_TAG" "ALLOW: is_prod=$is_prod flag='${FLIP_FLAG:-unset}'" 2>/dev/null || true
exit 0
