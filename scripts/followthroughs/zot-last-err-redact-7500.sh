#!/usr/bin/env bash
# Follow-through verification for #7500 Phase B — producer-side redaction of `zot_last_err`.
#
# WHY THIS IS A SOAK AND NOT A PRE-MERGE AC.
#
# Phase B lands in `cloud-init-registry.yml`. The registry host is cloud-init-only (ADR-096), so
# merging applies NOTHING: the change is inert until the next `registry-host-replace`, and this
# PR schedules no replace. A pre-merge AC asserting "the sample is redacted in the warehouse"
# would therefore be asserting a property of a host that does not yet run the code — which is
# the un-runnable-AC class, not a gate.
#
# REPLACE-GATED, NOT DATE-GATED. `earliest=` is a floor on when this probe first RUNS; it is
# never the condition. The condition is the OBSERVED SHAPE of tier-4 rows in the warehouse.
#
# EXIT CONTRACT (the sweeper lists `--state open`; its reopen path fires only on exit 1)
#   0 = PASS       tier-4 rows were observed in the window AND none carries header content
#   2 = TRANSIENT  not yet delivered, no tier-4 row in the window, or ANY auth/query/decode
#                  failure
#   1 = FAIL       *** NEVER EMITTED BY THIS PROBE ***
#
# WHY 1 IS NEVER EMITTED. In this contract `exit 1` means "this must not close". A host that has
# not been replaced yet is a NOT-YET, not a defect — and a FAIL would post a comment every day
# for however long the replace takes, which could be months. The failure mode this probe exists
# to catch is "the change never arrived", and that is what the tracker's escalation horizon is
# for, not a daily red. Whether the redaction is CORRECT when it does arrive is settled
# pre-merge by `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` (26 assertions,
# 14 of them measured RED first) — this probe answers delivery, and says so rather than
# implying it graded correctness.
#
# THREE GUARDS, each closing a way this probe could PASS while proving nothing:
#
#   1. SUBJECT-MUST-HAVE-RUN. Requires at least one row whose `zot_last_err_src=fallback` —
#      i.e. tier 4 actually occurred in the window. Tier 4 is the ONLY tier the gate changes,
#      so a window containing none makes "no header content" trivially true: every other tier
#      is a matched diagnostic line that rarely carries a headers object anyway. Without this
#      guard the probe would PASS on a quiet week and close the issue having graded nothing.
#
#   2. A DARK CHANNEL IS NOT A CLEAN ONE. Zero rows of ANY kind means the reporter or the
#      warehouse is dark, which is indistinguishable from "clean" by absence alone. Reported
#      as `channel_dark` and exit 2, never as evidence of redaction.
#
#   3. DECODE BEFORE MATCHING. `betterstack-query.sh` emits JSONEachRow whose `raw` is an
#      escaped JSON string; matching the marker against the undecoded envelope silently returns
#      nothing — a probe that can never PASS, indistinguishable from a clean result.
#
# Secrets: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#
# Tracker directive (goes in the issue body):
#   <!-- soleur:followthrough script=scripts/followthroughs/zot-last-err-redact-7500.sh earliest=2026-09-09T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
WINDOW="${SOLEUR_FT_WINDOW:-24h}"

# An unprovisioned secret must be TRANSIENT, never FAIL: `set -u` on a missing variable would
# abort with a non-zero status that this contract reads as FAIL, posting a daily false red.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query the Logs warehouse. This is a provisioning" >&2
    echo "           gap, not evidence about the redaction." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable — the probe could not run." >&2
  exit 2
fi

RAWOUT="$("$QUERY" --since "$WINDOW" --grep 'SOLEUR_ZOT_DISK' 2>/dev/null)" || {
  echo "TRANSIENT: betterstack-query.sh exited non-zero — channel_dark or auth failure." >&2
  exit 2
}

if [[ -z "$RAWOUT" ]]; then
  echo "TRANSIENT: channel_dark — zero SOLEUR_ZOT_DISK rows in $WINDOW. Absence of rows is not" >&2
  echo "           evidence of redaction; it is evidence the reporter or the warehouse is dark." >&2
  exit 2
fi

# DECODE the escaped `raw` envelope before matching anything (guard 3). A jq failure here is a
# decode failure, not a clean result.
DECODED="$(printf '%s\n' "$RAWOUT" | jq -r '.raw // empty' 2>/dev/null)" || DECODED=""
if [[ -z "$DECODED" ]]; then
  echo "TRANSIENT: could not decode the JSONEachRow envelope — matching the undecoded form" >&2
  echo "           would silently match nothing, which reads exactly like a clean result." >&2
  exit 2
fi

# Bound the trusted region the way scripts/lib/zot-telemetry-parse.sh does: `zot_last_err` is
# emitted LAST and is free text, so a crafted log line could otherwise spoof a field a verdict
# keys on. Here we WANT the tail, so cut the other direction and keep it explicit.
TIER4_ROWS="$(printf '%s\n' "$DECODED" | grep -F 'zot_last_err_src=fallback' || true)"
TOTAL_ROWS="$(printf '%s\n' "$DECODED" | grep -cF 'SOLEUR_ZOT_DISK' || true)"
[[ -n "$TOTAL_ROWS" ]] || TOTAL_ROWS=0

# Guard 1: the subject must have run.
if [[ -z "$TIER4_ROWS" ]]; then
  echo "TRANSIENT: $TOTAL_ROWS SOLEUR_ZOT_DISK row(s) in $WINDOW, but NONE at tier 4" >&2
  echo "           (zot_last_err_src=fallback). Tier 4 is the only tier the gate changes, so" >&2
  echo "           this window cannot grade it. Not a pass." >&2
  exit 2
fi

TIER4_N="$(printf '%s\n' "$TIER4_ROWS" | grep -c . || true)"
[[ -n "$TIER4_N" ]] || TIER4_N=0

# The assertion. After Phase B a tier-4 sample is the parsed `message` only, so a `headers`
# substring in the tail means the gate is not on this host yet.
LEAKY="$(printf '%s\n' "$TIER4_ROWS" | sed -n 's/.* zot_last_err=//p' | grep -cE 'headers|clientIP' || true)"
[[ -n "$LEAKY" ]] || LEAKY=0

if [[ "$LEAKY" -gt 0 ]]; then
  echo "TRANSIENT: NOT YET DELIVERED — $LEAKY of $TIER4_N tier-4 row(s) still carry header" >&2
  echo "           content in zot_last_err. Phase B is inert until the next" >&2
  echo "           registry-host-replace (ADR-096: the host is cloud-init-only), so this is the" >&2
  echo "           expected reading until a replace fires. The sink-side scrub (ADR-211 layer 2)" >&2
  echo "           is in force meanwhile and covers the PUBLIC egress, which is the worse one." >&2
  exit 2
fi

echo "PASS: $TIER4_N tier-4 row(s) in $WINDOW, none carrying header content."
echo "      Phase B is delivered on this host and the tier gate is in force."
echo "      Scope: this grades DELIVERY. Correctness is graded pre-merge by"
echo "      apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh."
exit 0
