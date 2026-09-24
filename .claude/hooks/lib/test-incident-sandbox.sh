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
  # REAP THE ABANDONED SANDBOXES OF PRIOR RUNS, BEFORE CREATING ANOTHER.
  #
  # The EXIT trap installed below is the normal cleanup and it is sufficient for a normal exit. It
  # cannot run on SIGKILL, and SIGKILL is not the rare case here: this repository runs several
  # full-gate batteries in parallel worktrees on a shared machine, and the kernel's OOM reaper takes
  # whichever suite is resident when memory runs short. Every such kill strands one sandbox forever,
  # because nothing else ever looks at them.
  #
  # Measured 2026-09-20 on this machine: 5446 stranded `soleur-inc-*` directories, several hundred of
  # them holding real incident ledgers, and the sweep below removed 5112 of them on its first run.
  #
  # TWO THINGS THIS LEAK IS NOT, both stated because the first draft of this comment asserted them and
  # both are false on measurement. It is not large: all 337 surviving sandboxes together are 892 KB,
  # and /var/tmp's 7.8 GB is other tooling's — foreign review-agent clones at 964 MB, 592 MB, 515 MB
  # and so on. And it is not a memory-pressure cause: /var/tmp here is btrfs (150 GB, 80 GB free),
  # not a tmpfs, so these directories occupy disk and never RAM. An earlier version of this comment
  # built a tidy self-reinforcing story — leak fills tmpfs, tmpfs exhaustion triggers the OOM kill,
  # the kill strands another sandbox — and that story is wrong at both joints.
  #
  # What the leak actually costs is inode and directory-entry pressure on a shared path, plus several
  # hundred abandoned incident ledgers that any future audit of that telemetry has to distinguish from
  # real rows. That is worth fixing on its own terms, and the reason to fix it HERE rather than in the
  # trap is simply that a trap cannot run on SIGKILL while the create path always runs.
  #
  # Bounded and conservative, in this order for a reason:
  #   -maxdepth 1 -type d           — only the sandbox roots, never anything nested
  #   -name 'soleur-inc-*'          — only this helper's own artifacts
  #   -mmin +180                    — older than three hours. No live suite runs that long; the
  #                                   longest measured battery here is well under an hour, and the
  #                                   margin is deliberately several times that so a slow run on a
  #                                   contended box is never reaped out from under itself.
  #   2>/dev/null || true           — a concurrent reaper removing the same directory is the expected
  #                                   race, not an error, and this must never fail the suite that is
  #                                   merely trying to start.
  # It does NOT use the `-delete` action: that implies `-depth` and would descend, which is a wider
  # blast radius than intended for a sweep running unattended before every hook suite.
  # Base-pinned under the #7004 allocator: when a session root redirected TMPDIR
  # the enumeration must still scan the BASE, not the root (or it no-ops forever).
  find "${SOLEUR_SCRATCH_BASE:-${TMPDIR:-/tmp}}" -maxdepth 1 -type d -name 'soleur-inc-*' -mmin +180 \
    -exec rm -rf -- {} + 2>/dev/null || true

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
  # `trap -p` prints a RE-EXECUTABLE command whose body carries bash's OWN quoting: the body is
  # single-quoted, and a literal single quote inside it is emitted as the four-character sequence
  # '\'' . The previous form stripped the outer quotes with sed and re-wrapped the remainder in
  # double quotes, which leaves those escapes unbalanced and makes the composed trap a SYNTAX
  # ERROR. A trap that fails to parse never runs, so the sandbox this function exists to remove is
  # leaked.
  #
  # UNESCAPED WITH PARAMETER EXPANSION, NOT `eval`. ADR-156 forbids `eval` anywhere under
  # .claude/hooks — hook stdin is untrusted and hook-input-contract.test.sh arm A1 enforces it
  # across the whole tree, this lib included. An earlier revision of this fix used `eval` to
  # round-trip the quoting and A1 caught it (2 offenders). The allow-list there covers exactly one
  # fd-close idiom in session-state.sh and widening it for convenience would be the wrong trade.
  #
  # `trap "<text>"` is still how the composed trap is installed, which is what the ORIGINAL code
  # did and what keeps `$VAR` inside the prior body expanding at FIRE time rather than now.
  local prior_raw prior_body="" s
  prior_raw="$(trap -p EXIT)"
  if [ -n "$prior_raw" ]; then
    s="${prior_raw#trap -- }"
    s="${s% EXIT}"
    s="${s#\'}"
    s="${s%\'}"
    prior_body="${s//\'\\\'\'/\'}"
  fi
  _SOLEUR_INC_SB_OWNED="$d"
  _soleur_inc_sb_cleanup() { [ -n "${_SOLEUR_INC_SB_OWNED:-}" ] && rm -rf "$_SOLEUR_INC_SB_OWNED"; return 0; }
  # shellcheck disable=SC2064
  trap "${prior_body:+$prior_body; }_soleur_inc_sb_cleanup" EXIT
}
_soleur_test_incident_sandbox_init
