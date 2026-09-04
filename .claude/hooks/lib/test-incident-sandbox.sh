#!/usr/bin/env bash
# Source this FIRST in any hook suite whose hook can emit an incident.
#
# WHY THIS EXISTS. `emit_incident` resolves its sink through
# `_incidents_repo_root()`, which reads `INCIDENTS_REPO_ROOT` and otherwise
# walks up from `lib/` to the REAL repo. So a suite that does not redirect it
# writes its fixtures into the operator's live `.claude/.rule-incidents.jsonl`
# — the same file `compound` Phase 1.5 reads as deviation evidence, and
# `rule-metrics-aggregate.sh` keys its counters on.
#
# WHY PER-SUITE AND NOT PER-INVOCATION. Every polluting suite measured on
# 2026-09-03 already knew about the variable: they set it inline on SOME hook
# calls (`INCIDENTS_REPO_ROOT=… bash "$HOOK"`) and missed others. Partial
# isolation greps identically to full isolation, which is exactly why the gap
# survived — a static check for the variable's NAME reported those suites clean
# while they wrote 396 rows between them. Exporting once, before any case runs,
# has no such failure mode: a call site cannot forget what it never had to say.
#
# Measured that day: 12 suites, 396 rows in one sweep, 316 from
# iac-plan-write-guard.test.sh alone.
#
# ONLY `INCIDENTS_REPO_ROOT` is exported, deliberately. `_incidents_repo_root()`
# reads that variable and nothing else, so it is sufficient for the sink. An
# earlier revision also exported `CLAUDE_PROJECT_DIR` on the assumption that
# hooks need it redirected too — that assumption was wrong and measurably
# harmful: hooks use it for repo-relative logic, and pointing it at an empty
# temp dir made new-scheduled-cron-prefer-inngest.sh unable to see that a file
# existed on origin/main, flipping an allow case to deny. Redirect the telemetry
# sink, not the repo.
#
# The sandbox path is exported as SOLEUR_TEST_INCIDENT_ROOT so a suite can read
# back the rows its hook emitted (assert on telemetry) without knowing this
# file's internals.

_soleur_test_incident_sandbox_init() {
  local d
  d=$(mktemp -d -t soleur-inc-XXXXXX) || return 0
  mkdir -p "$d/.claude" 2>/dev/null || return 0
  export INCIDENTS_REPO_ROOT="$d"
  export SOLEUR_TEST_INCIDENT_ROOT="$d"

  # Compose with any EXIT trap the suite has ALREADY installed rather than
  # clobbering it. A suite that installs its own trap AFTER sourcing this will
  # still win — that only leaks one small tmpdir, never a real-ledger write,
  # so the failure direction is tidiness rather than correctness.
  local prior
  prior=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")
  if [ -n "$prior" ] && [ "$prior" != "$(trap -p EXIT)" ]; then
    # shellcheck disable=SC2064
    trap "$prior; rm -rf '$d'" EXIT
  else
    # shellcheck disable=SC2064
    trap "rm -rf '$d'" EXIT
  fi
}
_soleur_test_incident_sandbox_init
