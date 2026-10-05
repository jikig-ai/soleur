#!/usr/bin/env bash
#
# Tests for alpha-metrics.sh — the checkpoint aggregate printer.
#
# Load-bearing contract: ABSENT/EMPTY markers must render as signals, never as
# a zero count. A tester who did nothing and a tester whose emit never ran are
# different worlds; the print must not conflate them.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/alpha-metrics.sh"
EMIT="$DIR/emit-decision.sh"

# trap BEFORE sourcing test-helpers.sh so the helpers' composed EXIT trap
# (<prior>; _soleur_sb_cleanup) stacks on ours instead of being clobbered by it.
TMP="$(mktemp -d -t alpham.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

passes=0
fails=0
CASES=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; return 0; }
assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then pass "$1"; else fail "$1" "${3:-$2}"; fi
}

printf '\n=== alpha-metrics.sh ===\n\n'
[[ -f "$SUT" ]] || { printf '\n[FATAL] SUT missing at %s\n' "$SUT" >&2; exit 1; }

new_repo() { # $1 = name
  local d="$TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email soleur-test@example.invalid
  git -C "$d" config user.name  "Soleur Test"
  git -C "$d" config commit.gpgsign false
  git -C "$d" commit -q --allow-empty -m "base"
  printf '%s' "$d"
}

# --- ABSENT: no log at all --------------------------------------------------

RA="$TMP/no-log"; new_repo no-log >/dev/null
out="$(cd "$RA" && bash "$SUT")"
assert "missing log -> SOLEUR_EMIT_ABSENT" "[[ '$out' == *SOLEUR_EMIT_ABSENT* ]]"
assert "absent never prints a zero count" "! printf '%s' '$out' | grep -q 'records:  *0'"

# --- EMPTY: log exists, zero records -----------------------------------------

RB="$TMP/empty-log"; new_repo empty-log >/dev/null
mkdir -p "$RB/.soleur"; touch "$RB/.soleur/decisions.jsonl"
out="$(cd "$RB" && bash "$SUT")"
assert "empty log -> SOLEUR_EMIT_EMPTY" "[[ '$out' == *SOLEUR_EMIT_EMPTY* ]]"
assert "empty never prints a zero count" "! printf '%s' '$out' | grep -q 'records:  *0'"

# --- POPULATED: real emits aggregate -----------------------------------------

RC="$TMP/pop"; new_repo pop >/dev/null
( cd "$RC"
  bash "$EMIT" --event route_decision --label work
  bash "$EMIT" --event route_decision --label brainstorm
  bash "$EMIT" --event route_decision --label work
  bash "$EMIT" --event tool_invocation --label flag-list --skill flag-list --agent_domain ops )
out="$(cd "$RC" && bash "$SUT")"
assert "counts 4 records" "printf '%s' '$out' | grep -q 'records:  *4'"
assert "per-event count present" "printf '%s' '$out' | grep -A3 'by event:' | grep -q 'route_decision'"
assert "per-label count shows work=2" "printf '%s' '$out' | grep -A5 'by label:' | grep -qE '^ *2 +work'"
assert "per-domain count shows ops=1" "printf '%s' '$out' | grep -A4 'by agent_domain:' | grep -q 'ops'"
assert "per-harness count is non-empty" "printf '%s' '$out' | grep -A3 'by harness:' | grep -qE '^ *[0-9]+ +[a-zA-Z]'"
assert "first/last timestamps printed" "printf '%s' '$out' | grep -q 'first:' && printf '%s' '$out' | grep -q 'last:'"
assert "KB-growth instruction printed" "printf '%s' '$out' | grep -q 'git log --since'"

# --- ROTATED: merged read ----------------------------------------------------

RD="$TMP/rot"; new_repo rot >/dev/null
( cd "$RD" && bash "$EMIT" --event route_decision --label one )
printf '{"v":1,"ts":"2026-01-01T00:00:00Z","event":"route_decision","label":"old","skill":"","agent_domain":"","harness":"claude","session_id":"s","plugin_sha":"x","repo_hash":"h"}\n' > "$RD/.soleur/decisions.jsonl.1"
out="$(cd "$RD" && bash "$SUT")"
assert "rotated lines merge into the count" "printf '%s' '$out' | grep -q 'records:  *2'"

# --- ORDERING: first/last carry VALUES, not just labels ----------------------

RE="$TMP/order"; new_repo order >/dev/null
mkdir -p "$RE/.soleur"
printf '%s\n' '{"v":1,"ts":"2026-03-05T00:00:00Z","event":"route_decision","label":"b","skill":"","agent_domain":"","harness":"x","session_id":"s","plugin_sha":"p","repo_hash":"h"}' \
  '{"v":1,"ts":"2026-03-01T00:00:00Z","event":"route_decision","label":"a","skill":"","agent_domain":"","harness":"x","session_id":"s","plugin_sha":"p","repo_hash":"h"}' \
  > "$RE/.soleur/decisions.jsonl"
out="$(cd "$RE" && bash "$SUT")"
assert "first: carries the EARLIEST ts (not just the label)" \
  "printf '%s' '$out' | grep -q 'first:    2026-03-01'"
assert "last: carries the LATEST ts" \
  "printf '%s' '$out' | grep -q 'last:     2026-03-05'"

# --- CORRUPTION: a malformed line is surfaced, not silently counted ----------

RF="$TMP/bad"; new_repo bad >/dev/null
mkdir -p "$RF/.soleur"
printf '%s\n' '{"v":1,"ts":"2026-03-01T00:00:00Z","event":"route_decision","label":"ok","skill":"","agent_domain":"","harness":"x","session_id":"s","plugin_sha":"p","repo_hash":"h"}' \
  'garbage-not-json' \
  > "$RF/.soleur/decisions.jsonl"
out="$(cd "$RF" && bash "$SUT")"
assert "malformed lines are reported, not silently dropped" \
  "printf '%s' '$out' | grep -q 'malformed: 1'"

printf '\n=== alpha-metrics: %d passed, %d failed (of %d) ===\n' "$passes" "$fails" "$CASES"
# Anti-vacuity floor (#7408 class): a suite that ran nothing must not exit green.
[[ "$fails" -eq 0 && "$CASES" -ge 15 ]]
