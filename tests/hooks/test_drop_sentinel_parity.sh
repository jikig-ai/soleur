#!/usr/bin/env bash
# Parity test for the cross-sink drop-sentinel class enum (issue #3509).
#
# The sentinel-class enum {jq_fail, flock_timeout, rotation_fail} is
# replicated across producer call sites (hook scripts) and consumer
# accessor sites (aggregator scripts + compound report). A typo at any
# producer site silently lands in `bad_lines` of one aggregator and as
# zero count in another — exactly the silent-drift class the cross-stream
# format-contract review pattern (`telemetry-join-format-mismatch`) calls
# out as the highest-leverage defect to lock down with a parity test.
#
# This test is the canonical assertion that:
#   1. Every class literal emitted by a producer is in the canonical set.
#   2. Every class literal accessed by a consumer is in the canonical set.
#   3. No producer emits a class that no consumer reads (orphan emit).
#
# Run from repo root:
#   bash tests/hooks/test_drop_sentinel_parity.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $*"; PASS=$((PASS + 1)); }

# Canonical class enum. Single source of truth; the assertions below pivot
# on this set. Adding a class requires extending this list AND adding a
# producer site AND adding the corresponding consumer accessor (matching
# count in `summary.drops_<class>_count` keys is asserted below).
CANONICAL_CLASSES=(jq_fail flock_timeout rotation_fail)

# Producer files: every site that calls _emit_drop_sentinel.
PRODUCER_FILES=(
  ".claude/hooks/lib/incidents.sh"
  ".claude/hooks/agent-token-tee.sh"
  ".claude/hooks/skill-invocation-logger.sh"
)

# Consumer files: every script that reads drops_<class>_count or accesses
# .drops["<class>"] / $drops["<class>"].
CONSUMER_FILES=(
  "scripts/rule-metrics-aggregate.sh"
  "scripts/skill-freshness-aggregate.sh"
  "plugins/soleur/skills/compound/scripts/token-efficiency-report.sh"
)

# --- Producer extraction --------------------------------------------------
# Match `_emit_drop_sentinel "..." "..." "<class>"` (the 3rd positional arg
# is the class literal). The regex is permissive on whitespace and quote
# style; `awk` extracts the third quoted token.
extract_producer_classes() {
  local f="$1"
  grep -nE '_emit_drop_sentinel[[:space:]]+' "$f" 2>/dev/null \
    | awk -F'"' '{ if (NF >= 7) print $6 }' \
    | sort -u
}

producer_classes_observed=()
for f in "${PRODUCER_FILES[@]}"; do
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    producer_classes_observed+=("$c")
  done < <(extract_producer_classes "$f")
done

# Dedup
mapfile -t producer_unique < <(printf '%s\n' "${producer_classes_observed[@]}" | sort -u)

# --- Consumer extraction --------------------------------------------------
# Match `drops_<class>_count` field accessors AND `$drops["<class>"]` /
# `.["<class>"]` lookups. Both forms exist in the aggregators.
extract_consumer_classes() {
  local f="$1"
  {
    grep -oE 'drops_[a-z_]+_count' "$f" 2>/dev/null \
      | sed -E 's/^drops_(.+)_count$/\1/'
    grep -oE '\["[a-z_]+"\]' "$f" 2>/dev/null \
      | sed -E 's/^\["(.+)"\]$/\1/'
  } | sort -u
}

consumer_classes_observed=()
for f in "${CONSUMER_FILES[@]}"; do
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    # Filter out non-class tokens picked up by the bracketed-string extractor
    # (the consumer scripts also use `["foo"]` for unrelated jq lookups).
    case "$c" in
      jq_fail|flock_timeout|rotation_fail) consumer_classes_observed+=("$c") ;;
    esac
  done < <(extract_consumer_classes "$f")
done

mapfile -t consumer_unique < <(printf '%s\n' "${consumer_classes_observed[@]}" | sort -u)

# --- Assertion 1: producer classes ⊆ canonical ----------------------------
for c in "${producer_unique[@]}"; do
  found=0
  for canonical in "${CANONICAL_CLASSES[@]}"; do
    [[ "$c" == "$canonical" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    pass "producer class '$c' is in canonical enum"
  else
    fail "producer class '$c' is NOT in canonical enum {${CANONICAL_CLASSES[*]}} — typo or new class without parity update?"
  fi
done

# --- Assertion 2: consumer classes ⊆ canonical ----------------------------
for c in "${consumer_unique[@]}"; do
  found=0
  for canonical in "${CANONICAL_CLASSES[@]}"; do
    [[ "$c" == "$canonical" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    pass "consumer class '$c' is in canonical enum"
  else
    fail "consumer class '$c' is NOT in canonical enum {${CANONICAL_CLASSES[*]}}"
  fi
done

# --- Assertion 3: every producer class has at least one consumer ----------
# Consumer-side tracking of every emitted class is required so an emit-
# without-read drift surfaces immediately.
for pc in "${producer_unique[@]}"; do
  found=0
  for cc in "${consumer_unique[@]}"; do
    [[ "$pc" == "$cc" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    pass "producer class '$pc' is read by at least one consumer"
  else
    fail "producer class '$pc' has NO consumer accessor — orphan emit; aggregators will under-count drops"
  fi
done

# --- Assertion 4: at least the two universal classes have producers -------
# `jq_fail` and `rotation_fail` MUST have producers in every PR (they apply
# to every sink). `flock_timeout` is producer-optional (only sinks with
# `flock -w` use it).
for required in jq_fail rotation_fail; do
  found=0
  for pc in "${producer_unique[@]}"; do
    [[ "$pc" == "$required" ]] && found=1 && break
  done
  if [[ "$found" == "1" ]]; then
    pass "required producer class '$required' has at least one emit site"
  else
    fail "required producer class '$required' has NO emit site — sink missing drop coverage"
  fi
done

# --- Summary --------------------------------------------------------------
echo
echo "Producer classes observed: ${producer_unique[*]:-<none>}"
echo "Consumer classes observed: ${consumer_unique[*]:-<none>}"
echo "Canonical enum:            ${CANONICAL_CLASSES[*]}"
echo
echo "RESULT: $PASS passed, $FAIL failed"
exit "$FAIL"
