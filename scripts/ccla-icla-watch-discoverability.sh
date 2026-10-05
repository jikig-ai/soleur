#!/usr/bin/env bash
# Discoverability probe for the CCLA representative ICLA watch (#7910 / #7922).
#
# WHY A WRAPPER EXISTS. Preflight Check 10 reaches PASS only on `rc == 0`, and
# the probe it checks NEVER exits 0 on any path -- 0 is the follow-through
# sweeper's close verb, and taking it would close a legal tracker for good. So
# the probe cannot be Check 10's command directly, and the plan's first attempt
# to square that used a `credentials_required:` declaration instead, which made
# Check 10 SKIP WITHOUT EXECUTING. That is how a plan claiming `exits 0` for a
# command that exits 2 reached review with the gate green: the gate never ran it.
#
# This wrapper inverts the contract exactly once, in one place, and asserts the
# invariant rather than waiving it: the probe must exit 2 (not 0, not 1, not 3)
# and must print one ISO-8601 UTC epoch. Both halves are load-bearing -- a probe
# that refused would also "not exit 0", so a bare rc check would pass on a
# derivation that could not run at all.
#
# Read-only. No network, no credential, no writes: `--print-epoch` derives the
# epoch from local git history and returns before any fetch.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/ccla-representative-icla-7922.sh"

[[ -r "$PROBE" ]] || { printf 'FAIL: probe not readable at %s\n' "$PROBE" >&2; exit 1; }

out="$(bash "$PROBE" --print-epoch 2>/dev/null)"; rc=$?

# The invariant this whole design rests on, asserted first and by value.
if [[ "$rc" == "0" || "$rc" == "1" ]]; then
  printf 'FAIL: the probe returned rc=%s. 0 is the sweeper CLOSE verb and 1 its REOPEN trigger; this probe must never take either.\n' "$rc" >&2
  exit 1
fi
if [[ "$rc" != "2" ]]; then
  printf 'FAIL: --print-epoch exited %s, expected 2. Output was: %s\n' "$rc" "${out:-<empty>}" >&2
  exit 1
fi
if [[ ! "$out" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\+00:00|Z)$ ]]; then
  printf 'FAIL: --print-epoch exited 2 but printed no ISO-8601 UTC epoch: %s\n' "${out:-<empty>}" >&2
  exit 1
fi

printf 'EPOCH-OK %s\n' "$out"
exit 0
