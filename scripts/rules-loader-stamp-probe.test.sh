#!/usr/bin/env bash
# Arms for scripts/rules-loader-stamp-probe.sh (ADR-150, #7012).
#
# The probe is the operator-facing answer to "did my session actually load the
# whole rule corpus?", so its NEGATIVE arms are the load-bearing ones: a probe
# that prints OK unconditionally is indistinguishable from a working one, and
# it fails in the direction that stops you looking.
#
# Every arm runs against a FIXTURE tree built in mktemp -d. The real repo tree
# is never mutated -- a test that truncated the live AGENTS.rules.md would be
# testing by breaking the thing under test.
#
# Arms T5 and T6 pin the two CLAIMS the probe exists to make, not just its
# behaviour: that it survives the corpus growing (no hardcoded count), and that
# preflight Check 10 can actually execute it (no shell-active token). Both were
# asserted in prose before they were asserted by a command.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/rules-loader-stamp-probe.sh"

PASS=0; FAIL=0

# One owning trap for every fixture this suite allocates (ADR-129 rule (c)).
# The per-arm `rm -rf` below is the happy path; this is what runs when an arm
# dies between mktemp and cleanup. Registered BEFORE the first allocation --
# a trap installed after mktemp does not own the window it exists to cover.
FIXTURE_DIRS=()
cleanup_fixtures() {
  local d
  for d in "${FIXTURE_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup_fixtures EXIT INT TERM

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

check() { # <name> <expected-token> <expected-rc> <actual-token> <actual-rc>
  if [[ "$4" == "$2" && "$5" == "$3" ]]; then ok "$1"; else
    bad "$1 — expected '$2'/rc=$3, got '$4'/rc=$5"
  fi
}

# Build a fixture tree carrying the probe, the loader hook, the index, and a
# corpus we control.
make_fixture() { # <corpus-line-count | "none">
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts" "$d/.claude/hooks"
  cp "$SUT" "$d/scripts/"
  cp "$REPO_ROOT/.claude/hooks/session-rules-loader.sh" "$d/.claude/hooks/"
  cp "$REPO_ROOT/AGENTS.md" "$d/AGENTS.md"
  if [[ "$1" != "none" ]]; then
    head -"$1" "$REPO_ROOT/AGENTS.rules.md" > "$d/AGENTS.rules.md"
  fi
  printf '%s' "$d"
}

run_probe() { # <fixture-dir> -> echoes "<token> <rc>"
  local out rc
  out="$(cd "$1" && bash scripts/rules-loader-stamp-probe.sh 2>/dev/null)"; rc=$?
  printf '%s %s' "$out" "$rc"
}

# --- T1: whole corpus -> OK ------------------------------------------------
d=$(make_fixture 100000); FIXTURE_DIRS+=("$d")
read -r tok rc <<<"$(run_probe "$d")"
check "T1 full corpus -> OK/0" "OK" "0" "$tok" "$rc"
rm -rf "$d"

# --- T2: truncated corpus -> MISMATCH --------------------------------------
# The arm that matters: a PARTIAL load is the governance-blackout mode. 12 lines
# keeps the frontmatter + first heading + a few rules, so the loader emits a
# real stamp with numerator < denominator (not a fail-safe).
d=$(make_fixture 12); FIXTURE_DIRS+=("$d")
read -r tok rc <<<"$(run_probe "$d")"
check "T2 truncated corpus -> MISMATCH/1" "MISMATCH" "1" "$tok" "$rc"
rm -rf "$d"

# --- T3: missing corpus -> MISMATCH ----------------------------------------
# The loader's fail-safe stamps `0 of N`, which the probe must reject rather
# than treat as "nothing to load, therefore fine".
d=$(make_fixture none); FIXTURE_DIRS+=("$d")
read -r tok rc <<<"$(run_probe "$d")"
check "T3 missing corpus -> MISMATCH/1" "MISMATCH" "1" "$tok" "$rc"
rm -rf "$d"

# --- T4: missing hook -> NOSTAMP -------------------------------------------
d=$(make_fixture 100000); FIXTURE_DIRS+=("$d")
rm -f "$d/.claude/hooks/session-rules-loader.sh"
read -r tok rc <<<"$(run_probe "$d")"
check "T4 missing loader hook -> NOSTAMP/1" "NOSTAMP" "1" "$tok" "$rc"
rm -rf "$d"

# --- T5: no hardcoded rule count -------------------------------------------
# The probe must derive the denominator from the loader. A literal count would
# turn a CORRECT load into a false MISMATCH the day rule 102 lands -- the exact
# failure the plan's own comment warned about for the grep-backreference form.
# Strip comment lines before grepping: the probe's own comment EXPLAINS why the
# count must not be hardcoded, so a naive grep matches the explanation and
# reports a defect that is actually the documentation of its absence. (Caught by
# this suite on its first run -- cq-assert-anchor-not-bare-token, verbatim.)
SUT_CODE=$(grep -vE '^[[:space:]]*#' "$SUT")
if printf '%s' "$SUT_CODE" | grep -qE '(^|[^0-9])101([^0-9]|$)'; then
  bad "T5 probe hardcodes the rule count 101 in executable code"
else
  ok "T5 probe derives the count (no hardcoded 101 outside comments)"
fi

# --- T6: runnable by preflight Check 10 ------------------------------------
# Pins the reason this probe is a script at all. If someone later "simplifies"
# it back to a pipeline in the plan, Check 10 silently stops verifying it.
PLAN="$REPO_ROOT/knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md"
if [[ -r "$PLAN" ]]; then
  CMD=$(awk '/^## Observability$/{i=1;next} /^## /{if(i)exit} i' "$PLAN" \
        | awk '/^[[:space:]]*command:/{sub(/^[[:space:]]*command:[[:space:]]*/,"");print;exit}')
  if [[ -z "$CMD" ]]; then
    bad "T6 could not parse discoverability_test.command from the plan"
  elif [[ "$CMD" =~ (\$\(|\`|\<\(|\>\(|\;|\&\&|\|\||\||\>|\<|\&|$'\n'|\$\{?[A-Za-z_]) ]]; then
    bad "T6 plan command contains a shell-active token — preflight Check 10 will refuse it: $CMD"
  else
    ok "T6 plan command clears Check 10's shell-active reject"
  fi
else
  bad "T6 plan file not readable at $PLAN"
fi

echo
echo "Total: $((PASS+FAIL))  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
