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
#   1 = FAIL       the producer IS delivered (boot_id moved past the recorded baseline) and
#                  tier-4 rows STILL carry header content -- the redaction shipped and does not
#                  work. Emitted ONLY in that branch: a host that has not been replaced yet is a
#                  not-yet, never a failure.
#
# WHY 1 IS NARROW. `exit 1` means "this must not close". A host that has not been replaced yet
# is a NOT-YET, not a defect, and a daily red for however long the replace takes trains everyone
# to walk past it. But an earlier revision emitted 1 in NO branch at all, which meant the one
# outcome that genuinely must not close — delivered and STILL leaking — was unreportable.
# Delivery is now established independently (boot_id), so FAIL is reachable exactly there.
#
# There is no automatic escalation for a long-running exit 2: sweep-followthroughs.sh comments
# TRANSIENT and does not escalate open issues. An earlier revision of this header deferred to an
# "escalation horizon" that does not exist — that was an unmeasured claim about a mechanism.
# The daily comments land on a PUBLIC issue and state which control is not yet in force; that is
# a deliberate trade, recorded here rather than discovered later.
#
# Whether the redaction is CORRECT when it arrives is settled pre-merge by
# `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` (29 assertions, 14 measured RED
# first). This probe answers DELIVERY, and says so rather than implying it graded both.
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
#
# The merge-time boot_id is baked in as BASELINE_AT_MERGE (see the comment at that assignment for
# why it cannot be passed through the environment). SOLEUR_FT_BASELINE_BOOT still overrides it.
# With neither, the probe reports delivery state UNKNOWN rather than asserting a state it cannot
# measure -- and the delivered-and-leaking FAIL branch is unreachable.

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
TIER4_ROWS="$(printf '%s\n' "$DECODED" | grep -E 'zot_last_err_src=fallback( |$)' || true)"
TOTAL_ROWS="$(printf '%s\n' "$DECODED" | grep -cF 'SOLEUR_ZOT_DISK' || true)"
[[ -n "$TOTAL_ROWS" ]] || TOTAL_ROWS=0

# Guard 1: the subject must have run. EXACT match on the field value, not a substring --
# `zot_last_err_src=fallback` would also match a future qualified form by prefix.
if [[ -z "$TIER4_ROWS" ]]; then
  echo "TRANSIENT: $TOTAL_ROWS SOLEUR_ZOT_DISK row(s) in $WINDOW, but NONE at tier 4" >&2
  echo "           (zot_last_err_src=fallback). Tier 4 is the only tier the gate changes, so" >&2
  echo "           this window cannot grade it. Not a pass." >&2
  exit 2
fi

TIER4_N="$(printf '%s\n' "$TIER4_ROWS" | grep -c . || true)"
[[ -n "$TIER4_N" ]] || TIER4_N=0

LEAKY="$(printf '%s\n' "$TIER4_ROWS" | sed -n 's/.* zot_last_err=//p' | grep -cE 'headers|clientIP' || true)"
[[ -n "$LEAKY" ]] || LEAKY=0

# DELIVERY IS ITS OWN QUESTION, and conflating it with the leak check is the #7455 defect with
# the operands swapped. Three states collapse into one reading unless delivery is established
# independently:
#
#   (a) the replace has not fired                          -> genuinely not yet
#   (b) it fired and tier 4 did not occur in this window   -> ungraded, NOT "not delivered"
#   (c) it fired and the gate WORKED                       -> also produces no leaky tier-4 row
#
# (c) is the dangerous one: the tier gate's whole job is to stop emitting the row this probe
# looks for, so Guard 1's own success is indistinguishable from non-delivery unless something
# else says the new producer is running. `boot_id` is that something -- it is on every row, and
# a replace necessarily produces a new one.
#
# The merge-time boot_id decides delivery. It is baked in below rather than read from the
# environment; with neither it nor an override present the probe reports an UNKNOWN delivery state
# rather than asserting "NOT YET DELIVERED", because asserting a delivery state it cannot measure
# is exactly the unmeasured claim this whole change removes.
# TRUSTED REGION. boot_id decides DELIVERY, so a crafted tail carrying ` boot_id=FORGED`
# would otherwise win the greedy match, select the delivered branch, and close this tracker
# while Phase B had never been applied -- asserting a control is live on a host never replaced.
# The tail is cut first, exactly as zot_trusted_region does. LEAKY below still reads the tail,
# which is correct: that is the untrusted content it exists to measure.
NEWEST_BOOT="$(printf '%s\n' "$DECODED" | sed 's/ zot_last_err=.*//' | sed -n 's/.* boot_id=\([^ ]*\).*/\1/p' | tail -1)"
# BAKED IN, not passed. sweep-followthroughs.sh runs every probe under `env -i` with only the
# names declared in the directive's `secrets=`, so an exported SOLEUR_FT_BASELINE_BOOT is stripped
# before this script starts. Reading it from the environment alone therefore left BASELINE empty on
# every scheduled run, which made the delivered-and-leaking FAIL branch above unreachable -- a
# guard that could not fire. The constant is the boot_id measured on the live host immediately
# before merge (2026-09-08: 100 of 100 SOLEUR_ZOT_DISK rows in a 24h window carried this single
# value, read from the trusted region). The env var is still honoured first so an operator can
# override it without editing this file.
BASELINE_AT_MERGE=d0107f1f-834b-4acc-bd5a-00e53b61d835
BASELINE="${SOLEUR_FT_BASELINE_BOOT:-$BASELINE_AT_MERGE}"

if [[ -n "$BASELINE" && -n "$NEWEST_BOOT" && "$NEWEST_BOOT" != "$BASELINE" ]]; then
  # DELIVERED: the host has been replaced since merge. Now the leak check is a real verdict,
  # and a leak here is a genuine FAIL -- the redaction shipped and did not work. This is the
  # branch the previous revision could not express at all.
  if [[ "$LEAKY" -gt 0 ]]; then
    echo "FAIL: the producer IS delivered (boot_id $NEWEST_BOOT != baseline $BASELINE) and" >&2
    echo "      $LEAKY of $TIER4_N tier-4 row(s) STILL carry header content. The redaction" >&2
    echo "      shipped and is not working. This must not close." >&2
    exit 1
  fi
  echo "PASS: producer delivered (boot_id $NEWEST_BOOT != baseline $BASELINE);"
  echo "      $TIER4_N tier-4 row(s) in $WINDOW, none carrying header content."
  exit 0
fi

if [[ "$LEAKY" -gt 0 ]]; then
  echo "TRANSIENT: NOT YET DELIVERED — $LEAKY of $TIER4_N tier-4 row(s) still carry header" >&2
  echo "           content in zot_last_err. Phase B is inert until the next" >&2
  echo "           registry-host-replace (ADR-096: the host is cloud-init-only), so this is the" >&2
  echo "           expected reading until a replace fires. The sink-side scrub (ADR-211 Layer 2)" >&2
  echo "           is in force meanwhile and covers the PUBLIC egress, which is the worse one." >&2
  exit 2
fi

# Reachable only if BASELINE_AT_MERGE is ever blanked (`:-` already treats an empty override as
# unset, so the override alone cannot produce this state). Kept deliberately: the failure it
# guards against is a future edit emptying the constant, which would otherwise send every run
# down the NOT-YET-DELIVERED branch above and assert a delivery state with nothing measuring it.
if [[ -z "$BASELINE" ]]; then
  echo "TRANSIENT: delivery state UNKNOWN — $TIER4_N tier-4 row(s) carry no header content," >&2
  echo "           which is what BOTH a delivered-and-working gate and a quiet pre-delivery" >&2
  echo "           window look like. BASELINE_AT_MERGE is empty and no SOLEUR_FT_BASELINE_BOOT" >&2
  echo "           override was given; restore the merge-time boot_id (it is on every" >&2
  echo "           SOLEUR_ZOT_DISK row) to make this gradeable. Reporting UNKNOWN rather than" >&2
  echo "           asserting a delivery state this probe cannot measure." >&2
  exit 2
fi

# BASELINE is set and the boot_id has NOT moved: the host was never replaced, so Phase B
# cannot be in force. This was previously the fall-through to the terminal PASS below, which
# reported "producer delivered ... the tier gate is in force" for an un-replaced host whose
# window merely happened to be clean -- the exact false-close this probe exists to prevent.
if [[ -n "$BASELINE" && "$NEWEST_BOOT" == "$BASELINE" ]]; then
  echo "TRANSIENT: NOT YET DELIVERED — boot_id is still the merge-time baseline ($BASELINE)," >&2
  echo "           so no registry-host-replace has fired and Phase B cannot be in force." >&2
  echo "           $TIER4_N tier-4 row(s) carried no header content, which is the expected" >&2
  echo "           reading for a quiet window and is NOT evidence of delivery." >&2
  exit 2
fi

echo "PASS: $TIER4_N tier-4 row(s) in $WINDOW, none carrying header content."
echo "      Phase B is delivered on this host and the tier gate is in force."
echo "      Scope: this grades DELIVERY. Correctness is graded pre-merge by"
echo "      apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh."
exit 0
