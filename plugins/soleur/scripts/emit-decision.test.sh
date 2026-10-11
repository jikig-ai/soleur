#!/usr/bin/env bash
#
# Tests for emit-decision.sh — the .soleur/decisions.jsonl writer.
#
# The SUT is fail-open by design (exit 0 is the only exit), so the suite
# asserts on FILE STATE, not exit codes: a missing line, a malformed line, or
# a line carrying off-allowlist text is the defect — never a nonzero rc.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/emit-decision.sh"

# trap BEFORE sourcing test-helpers.sh so the helpers' composed EXIT trap
# (<prior>; _soleur_sb_cleanup) stacks on ours instead of being clobbered by it.
TMP="$(mktemp -d -t emitdec.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

passes=0
fails=0
CASES=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then
    pass "$1"
  else
    fail "$1" "${3:-$2}"
  fi
}

printf '\n=== emit-decision.sh ===\n\n'

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

R1="$TMP/r1"; new_repo r1 >/dev/null
R2="$TMP/r2"; new_repo r2 >/dev/null

# --- T1: basic write produces exactly one valid JSON line -------------------

( cd "$R1" && bash "$SUT" --event route_decision --label work )

assert "writes decisions.jsonl" \
  "[[ -f '$R1/.soleur/decisions.jsonl' ]]"
assert "exactly one line" \
  "[[ \$(wc -l < '$R1/.soleur/decisions.jsonl' | tr -d ' ') == 1 ]]"
assert "line parses as JSON" \
  "cd '$R1' && python3 -c 'import json,sys; json.load(open(\".soleur/decisions.jsonl\"))' 2>/dev/null || node -e 'JSON.parse(require(\"fs\").readFileSync(\"$R1/.soleur/decisions.jsonl\",\"utf8\").trim())'"
assert "carries event+label+harness+repo_hash keys" \
  "grep -q '\"event\":\"route_decision\"' '$R1/.soleur/decisions.jsonl' && grep -q '\"label\":\"work\"' '$R1/.soleur/decisions.jsonl' && grep -q '\"repo_hash\":\"' '$R1/.soleur/decisions.jsonl'"
assert "creates .gitignore self-guard containing '*'" \
  "[[ \$(cat '$R1/.soleur/.gitignore') == '*' ]]"
assert ".soleur/ shows no git change" \
  "[[ -z \$(cd '$R1' && git status --porcelain -- .soleur) ]]"

# --- T2: kill switch ---------------------------------------------------------

( cd "$R1" && SOLEUR_DISABLE_DECISION_LOG=1 bash "$SUT" --event route_decision --label off )
assert "kill-switch writes nothing" \
  "[[ \$(wc -l < '$R1/.soleur/decisions.jsonl' | tr -d ' ') == 1 ]]"

# --- T3: NO-ECHO — off-allowlist content never reaches the line --------------

( cd "$R1" && bash "$SUT" --event route_decision --label 'evil"breakout' )
assert "quote-bearing label is redacted, not emitted raw" \
  "! grep -q 'evil\"' '$R1/.soleur/decisions.jsonl' && grep -q '__REDACTED__' '$R1/.soleur/decisions.jsonl'"
assert "all lines still valid JSON" \
  "node -e 'require(\"fs\").readFileSync(\"$R1/.soleur/decisions.jsonl\",\"utf8\").trim().split(\"\n\").forEach(l=>JSON.parse(l))'"

# --- T3b: control characters can never split a record -----------------------

lines_before="$(wc -l < "$R1/.soleur/decisions.jsonl" | tr -d ' ')"
( cd "$R1" && bash "$SUT" --event route_decision --label "$(printf 'a\nb')" )
assert "newline-bearing label is redacted, record stays one line" \
  "[[ \$(wc -l < '$R1/.soleur/decisions.jsonl' | tr -d ' ') == \$((lines_before + 1)) ]] && grep -q '__REDACTED__' '$R1/.soleur/decisions.jsonl'"
assert "every line still valid JSON after control-char attempt" \
  "node -e 'require(\"fs\").readFileSync(\"$R1/.soleur/decisions.jsonl\",\"utf8\").trim().split(\"\n\").forEach(l=>JSON.parse(l))'"

# --- T3c: the frozen event enum is enforced at the chokepoint ----------------

lines_before="$(wc -l < "$R1/.soleur/decisions.jsonl" | tr -d ' ')"
( cd "$R1" && bash "$SUT" --event not_a_real_event --label x )
assert "unknown --event writes nothing (enum enforced, fail-open)" \
  "[[ \$(wc -l < '$R1/.soleur/decisions.jsonl' | tr -d ' ') == \$lines_before ]]"

# --- T4: two concurrent writers each land one clean line ---------------------

( cd "$R2" && { bash "$SUT" --event route_decision --label a & bash "$SUT" --event route_decision --label b & wait; } )
assert "concurrent appends produce two lines" \
  "[[ \$(wc -l < '$R2/.soleur/decisions.jsonl' | tr -d ' ') == 2 ]]"
assert "both lines valid JSON (no interleave)" \
  "node -e 'require(\"fs\").readFileSync(\"$R2/.soleur/decisions.jsonl\",\"utf8\").trim().split(\"\n\").forEach(l=>JSON.parse(l))'"

# --- T5: rotation ------------------------------------------------------------

big="$TMP/big-repo"; mkdir -p "$big/.soleur"; ( cd "$big" && git init -q -b main && git config user.email t@t && git config user.name t && git config commit.gpgsign false && git commit -q --allow-empty -m b )
head -c 5300000 /dev/zero | tr '\0' 'x' > "$big/.soleur/decisions.jsonl"
( cd "$big" && bash "$SUT" --event route_decision --label rot )
assert "oversize log rotates to .1" \
  "[[ -f '$big/.soleur/decisions.jsonl.1' ]] && [[ \$(wc -l < '$big/.soleur/decisions.jsonl' | tr -d ' ') == 1 ]]"

# --- T6: selfcheck ------------------------------------------------------------

out="$(cd "$R1" && bash "$SUT" --selfcheck)"
assert "--selfcheck prints SOLEUR_EMIT_OK" \
  "[[ '$out' == *SOLEUR_EMIT_OK* ]]"

# --- T7: outside a git repo is a silent no-op --------------------------------

NG="$TMP/not-a-repo"; mkdir -p "$NG"
( cd "$NG" && bash "$SUT" --event route_decision --label ng )
assert "non-repo write is a no-op" \
  "[[ ! -e '$NG/.soleur' ]]"

out="$(cd "$NG" && bash "$SUT" --selfcheck)"
assert "--selfcheck works OUTSIDE a repo (probe is repo-independent)" \
  "[[ '$out' == *SOLEUR_EMIT_OK* ]]"

# --- T8: Guard 4 — CURSOR_INVOKED_AS after the four arms ----------------------

R3="$TMP/r3"; new_repo r3 >/dev/null
( cd "$R3" && env -u CLAUDECODE -u GROK_HOME -u GROK_AGENT -u GROK_DEFAULT_MODEL -u GROK_SUBAGENTS -u CODEX_THREAD_ID -u DEVIN -u DEVIN_HOME -u CURSOR_AGENT CURSOR_INVOKED_AS=cursor-agent bash "$SUT" --event route_decision --label cursor-only )
assert "CURSOR_INVOKED_AS alone records harness cursor" \
  "grep -q '\"harness\":\"cursor\"' '$R3/.soleur/decisions.jsonl'"

R4="$TMP/r4"; new_repo r4 >/dev/null
( cd "$R4" && env -u GROK_HOME -u GROK_AGENT -u GROK_DEFAULT_MODEL -u GROK_SUBAGENTS -u CODEX_THREAD_ID -u DEVIN -u DEVIN_HOME -u CURSOR_AGENT CLAUDECODE=1 CURSOR_INVOKED_AS=cursor-agent bash "$SUT" --event route_decision --label claude-wins )
assert "CLAUDECODE plus CURSOR_INVOKED_AS stays claude" \
  "grep -q '\"harness\":\"claude\"' '$R4/.soleur/decisions.jsonl' && ! grep -q '\"harness\":\"cursor\"' '$R4/.soleur/decisions.jsonl'"

R5="$TMP/r5"; new_repo r5 >/dev/null
( cd "$R5" && env -u CLAUDECODE -u GROK_HOME -u GROK_AGENT -u GROK_DEFAULT_MODEL -u GROK_SUBAGENTS -u CODEX_THREAD_ID -u DEVIN -u DEVIN_HOME -u CURSOR_INVOKED_AS CURSOR_AGENT=1 bash "$SUT" --event route_decision --label agent-not-marker )
assert "CURSOR_AGENT alone stays unknown" \
  "grep -q '\"harness\":\"unknown\"' '$R5/.soleur/decisions.jsonl'"

R6="$TMP/r6"; new_repo r6 >/dev/null
( cd "$R6" && env -u CLAUDECODE -u GROK_HOME -u GROK_AGENT -u GROK_DEFAULT_MODEL -u GROK_SUBAGENTS -u CODEX_THREAD_ID -u DEVIN -u DEVIN_HOME -u CURSOR_AGENT CURSOR_INVOKED_AS= bash "$SUT" --event route_decision --label empty-marker )
assert "empty CURSOR_INVOKED_AS stays unknown" \
  "grep -q '\"harness\":\"unknown\"' '$R6/.soleur/decisions.jsonl'"

printf '\n=== emit-decision: %d passed, %d failed (of %d) ===\n' "$passes" "$fails" "$CASES"
# Anti-vacuity floor (#7408 class): a suite that ran nothing must not exit green.
[[ "$fails" -eq 0 && "$CASES" -ge 22 ]]
