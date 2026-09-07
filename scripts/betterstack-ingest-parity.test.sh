#!/usr/bin/env bash
# (#7873) The Better Stack ingest destination is declared in SIX places. This
# suite asserts they all name the same host.
#
# WHY SIX AND NOT THREE. The obvious parity assertion names the sites a reader
# thinks of -- the two shell scripts and the Terraform local. Measured, there are
# six, and an assertion over three of them goes GREEN with the fleet split across
# two destinations: the three unnamed declarations are exactly the ones nobody
# re-reads (a cloud-init heredoc, a vector sink uri, a userdata budget renderer).
# A parity guard whose population is smaller than the real one is worse than none,
# because it reports agreement it never checked.
#
# This is a PARITY assertion, not a pin: it does not care WHICH host is declared,
# only that one answer is given six times. That keeps a legitimate migration to a
# single edit-and-update rather than something this guard forbids.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { printf '[FATAL] cannot cd to repo root\n' >&2; exit 2; }

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# Positive control (ADR-193): drive both helpers once and refuse to continue
# unless both counters move. Reported with printf + exit, never through the
# helpers it backstops.
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2
  exit 1
fi
PASS=$_p; FAIL=$_f

# file:regex -- the regex must capture the host in \1.
SITES=(
  "apps/web-platform/infra/zot-registry.tf"
  "apps/web-platform/infra/cloud-init-inngest.yml"
  "apps/web-platform/infra/vector.toml"
  "apps/web-platform/infra/registry-userdata-budget.sh"
  "scripts/zot-inventory.sh"
  "scripts/betterstack-ingest-probe.sh"
)

EXPECTED_SITES=6
if [ "${#SITES[@]}" -ne "$EXPECTED_SITES" ]; then
  printf '[FATAL] site list is %s, expected %s -- update the count deliberately\n' \
    "${#SITES[@]}" "$EXPECTED_SITES" >&2
  exit 1
fi

hosts=""
missing=0
for f in "${SITES[@]}"; do
  if [ ! -f "$f" ]; then
    fail "declaration site is missing from the tree: $f"
    missing=$((missing + 1))
    continue
  fi
  # Extract every betterstackdata host this file names, ignoring comments.
  h="$(grep -vE '^[[:space:]]*#' "$f" \
        | grep -oE 's[0-9]+\.[a-z0-9-]+\.betterstackdata\.com' \
        | sort -u || true)"
  if [ -z "$h" ]; then
    fail "$f declares no Better Stack ingest host -- the parity population has drifted"
    missing=$((missing + 1))
    continue
  fi
  n="$(printf '%s\n' "$h" | grep -c .)"
  if [ "$n" -ne 1 ]; then
    fail "$f names $n distinct ingest hosts: $(printf '%s' "$h" | tr '\n' ' ')"
    continue
  fi
  pass "$f declares $h"
  hosts="${hosts}${h}
"
done

# A run that inspected nothing must not report agreement.
inspected="$(printf '%s' "$hosts" | grep -c . || true)"
if [ "$inspected" -lt "$EXPECTED_SITES" ]; then
  fail "only $inspected/$EXPECTED_SITES declarations were readable -- refusing to certify parity over a partial population"
else
  distinct="$(printf '%s' "$hosts" | sort -u | grep -c . || true)"
  if [ "$distinct" -eq 1 ]; then
    pass "all $EXPECTED_SITES declarations agree on $(printf '%s' "$hosts" | sort -u | head -1)"
  else
    fail "the fleet is split across $distinct ingest destinations: $(printf '%s' "$hosts" | sort -u | tr '\n' ' ')"
  fi
fi

printf 'betterstack-ingest-parity: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
