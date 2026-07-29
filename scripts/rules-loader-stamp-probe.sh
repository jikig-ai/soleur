#!/usr/bin/env bash
# Discoverability probe for the SessionStart rules loader (ADR-151).
#
# Prints exactly one token:
#   OK        — the loader injected the WHOLE corpus (numerator == denominator, > 0)
#   MISMATCH  — partial, truncated, over-stripped, or fail-safe (blackout) load
#   NOSTAMP   — the loader emitted no `loaded: N of M rules` stamp at all
#
# Why this is a script and not a one-liner in the plan: `/soleur:preflight`
# Check 10 EXECUTES the plan's `discoverability_test.command` and refuses any
# command containing a shell-active token — pipes included. The probe needs a
# pipeline, so the pipeline lives here and the plan invokes a single command.
# A probe the verifier cannot run is a probe nobody runs.
#
# Deliberately does NOT hardcode the rule count: the denominator comes from the
# loader's own expected set, so this keeps working the day rule 102 lands.
# Asserting `101` here would turn a correct load into a false MISMATCH.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/session-rules-loader.sh"

if [[ ! -r "$HOOK" ]]; then
  echo "NOSTAMP"
  exit 1
fi

# The hook reads a JSON payload on stdin and resolves the corpus relative to cwd.
STAMP="$(printf '{"cwd":"%s"}' "$REPO_ROOT" | bash "$HOOK" 2>/dev/null \
         | sed -n 's/.*loaded: \([0-9][0-9]*\) of \([0-9][0-9]*\) rules.*/\1 \2/p' \
         | head -1)"

if [[ -z "$STAMP" ]]; then
  echo "NOSTAMP"
  exit 1
fi

read -r LOADED TOTAL <<<"$STAMP"

if [[ "$LOADED" -gt 0 && "$LOADED" -eq "$TOTAL" ]]; then
  echo "OK"
  exit 0
fi

echo "MISMATCH"
exit 1
