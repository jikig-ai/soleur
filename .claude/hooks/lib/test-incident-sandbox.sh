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

# FAIL LOUD, never open (#7853 / AC7). Both setup steps below used to `return 0` on failure, which
# left INCIDENTS_REPO_ROOT unset -- and an unset root is not a degraded sandbox, it is the
# OPERATOR'S REAL LEDGER. The failure direction of a write-boundary guard must be refusal, not
# silent restoration of the thing it guards. `mktemp` failing is also not hypothetical here: /tmp is
# a machine-global 4 GiB tmpfs shared by every parallel worktree.
#
# The empty-value case is called out separately because it is the one that reads as safe: an empty
# INCIDENTS_REPO_ROOT is indistinguishable from unset to `_incidents_repo_root()`, so exporting one
# would restore the real sink while every static check for the variable's NAME reported clean.
_soleur_test_incident_sandbox_init() {
  local d
  if ! d=$(mktemp -d -t soleur-inc-XXXXXX) || [ -z "$d" ]; then
    printf 'FATAL: test-incident-sandbox could not create a sandbox (mktemp failed or returned empty).\n' >&2
    printf '  Refusing to continue: an unset INCIDENTS_REPO_ROOT points telemetry at the\n' >&2
    printf '  operator real .claude/.rule-incidents.jsonl. Check free space on %s.\n' "${TMPDIR:-/tmp}" >&2
    exit 1
  fi
  if [ "${d#/}" = "$d" ]; then
    printf 'FATAL: test-incident-sandbox got a non-absolute sandbox path: %s\n' "$d" >&2
    exit 1
  fi
  if ! mkdir -p "$d/.claude" 2>/dev/null; then
    printf 'FATAL: test-incident-sandbox could not create %s/.claude\n' "$d" >&2
    printf '  Refusing to continue rather than falling back to the operator real ledger.\n' >&2
    exit 1
  fi
  export INCIDENTS_REPO_ROOT="$d"
  export SOLEUR_TEST_INCIDENT_ROOT="$d"

  # Compose with any EXIT trap the suite has ALREADY installed rather than
  # clobbering it. A suite that installs its own trap AFTER sourcing this will
  # still win — that only leaks one small tmpdir, never a real-ledger write,
  # so the failure direction is tidiness rather than correctness.
  # `trap -p` prints a RE-EXECUTABLE command whose body carries bash's OWN quoting, so an embedded
  # single quote returns as '\' . The previous form stripped the outer quotes with sed and
  # re-wrapped the rest in double quotes, which leaves those escapes unbalanced and makes the new
  # trap a SYNTAX ERROR. That is not only noise on exit: a trap that fails to parse never runs, so
  # the sandbox this function exists to remove is leaked. Measured on this machine: 971 stale
  # soleur-inc-* directories.
  #
  # Assigning bash's quoted form back through `eval` round-trips it exactly, and the trap strings
  # below are then FIXED text with nothing interpolated.
  local prior_raw prior_body="" s
  prior_raw="$(trap -p EXIT)"
  if [ -n "$prior_raw" ]; then
    s="${prior_raw#trap -- }"
    s="${s% EXIT}"
    eval "prior_body=$s"
  fi
  _SOLEUR_INC_SB_OWNED="$d"
  _soleur_inc_sb_cleanup() { [ -n "${_SOLEUR_INC_SB_OWNED:-}" ] && rm -rf "$_SOLEUR_INC_SB_OWNED"; return 0; }
  if [ -n "$prior_body" ]; then
    eval "_soleur_inc_prior_exit() { $prior_body
}"
    trap '_soleur_inc_prior_exit; _soleur_inc_sb_cleanup' EXIT
  else
    trap '_soleur_inc_sb_cleanup' EXIT
  fi
}
_soleur_test_incident_sandbox_init
