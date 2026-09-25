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

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

TMP="$(mktemp -d -t alpham.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

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
assert "per-harness count present" "printf '%s' '$out' | grep -A3 'by harness:' | grep -q 'unknown\|devin\|claude'"
assert "first/last timestamps printed" "printf '%s' '$out' | grep -q 'first:' && printf '%s' '$out' | grep -q 'last:'"
assert "KB-growth instruction printed" "printf '%s' '$out' | grep -q 'git log --since'"

# --- ROTATED: merged read ----------------------------------------------------

RD="$TMP/rot"; new_repo rot >/dev/null
( cd "$RD" && bash "$EMIT" --event route_decision --label one )
printf '{"v":1,"ts":"2026-01-01T00:00:00Z","event":"route_decision","label":"old","skill":"","agent_domain":"","harness":"claude","session_id":"s","plugin_sha":"x","repo_hash":"h"}\n' > "$RD/.soleur/decisions.jsonl.1"
out="$(cd "$RD" && bash "$SUT")"
assert "rotated lines merge into the count" "printf '%s' '$out' | grep -q 'records:  *2'"

printf '\n=== alpha-metrics: %d passed, %d failed (of %d) ===\n' "$passes" "$fails" "$CASES"
[[ "$fails" -eq 0 ]]
