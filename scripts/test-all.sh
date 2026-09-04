#!/usr/bin/env bash
set -euo pipefail

# EXIT CONTRACT (#7424)
#   0  every registered suite passed
#   1  >= 1 suite FAILED (an assertion verdict) — failure dominates when both are present
#      ALSO 1: a suite WROTE TO THE LIVE REPOSITORY. Counted into `failed` rather than given a
#      new code, because every consumer of this runner is binary on non-zero and a fifth code
#      buys nothing; the [FATAL] line above the summary names it unambiguously. See the
#      REPO WRITE BOUNDARY blocks (#7553/#7652).
#      NOT 1: the REPORT class — an observation, never a verdict. A ref belonging to a branch
#      that `git worktree list` says is checked out in ANOTHER worktree moved during this run.
#      That is a sibling session doing its own work, not this run corrupting anything, so a
#      REPORT class increments nothing and changes no exit code — it is printed, and that is
#      the whole of its effect. It is
#      documented here because a result class the runner can produce but its own contract does
#      not describe is the same claim/check drift this boundary exists to fix (#7652).
#   3  0 failures and >= 1 suite KILLED — UNRESOLVED, not measured, and NOT green
#      3 is a TOP-LEVEL contract only: a nested runner returning 3 into run_suite classifies
#      as a plain FAIL, because rc=3 is not signal-shaped. Do not adopt 3 in a nested runner
#      without revisiting this.
#      NOT 1 either: the UNMEASURABLE class. A boundary dimension was captured at one end of the
#      run and not the other, so its delta is meaningless — neither clean nor dirty. It is printed,
#      counted into the breakdown, and changes no exit code, because a run that could not measure
#      something must not report a verdict about it.
#   2  usage error — TEST_GROUP took an unsupported value (predates the above), OR the
#      relevance-predicate data file is missing, OR scripts/lib/repo-write-boundary.sh is missing
#      or stale (added #7652 — a gate whose boundary is undefined refuses rather than running at
#      reduced meaning). Both are "this runner cannot run", not a
#      verdict about any suite; ADR-181 declined a separate code because every consumer is
#      binary and a second usage-shaped code buys nothing.
#   4  REFUSED before anything ran. TWO producers, both overridden by SOLEUR_ALLOW_FULL_GATE=1:
#        (a) SOLEUR_SUBAGENT=1 is set — a DECLARED spawned agent;
#        (b) a sibling full-gate run is already in flight — a MEASURED condition (#7553).
#        (b) is the reachable one: nothing in this repo sets SOLEUR_SUBAGENT, so (a)'s
#        antecedent only holds when someone exports it deliberately.
#      (ADR-181). Distinct from 3 on purpose: 3 says a suite was terminated and its coverage
#      is unresolved; 4 says nothing ran, by design, and nothing is unresolved. Sharing 3
#      would make a refused run read as a killed suite.
#
# Every consumer was binary zero/non-zero BEFORE this change (lefthook, the three ci.yml
# shards, package.json, main-health-monitor.yml) and still blocks on any non-zero, so 3 is
# safe for all of them; exiting 0 on a killed suite would silently green every one.
# grok-pre-push-gate.sh is the exception THIS change creates: it now reads 3, renders
# [UNRESOLVED] instead of [FAIL], and forwards 3 — its own consumer (ship Phase 6) is binary. Note that ci.yml's
# aggregate `test` job reads `needs.<shard>.result`, whose domain is
# {success,failure,cancelled,skipped} — so the REQUIRED context cannot carry 3. CI collapses
# killed into failure, and the distinction survives in the shard log and the [KILLED] lines.

# --- Auto-discovered suite globs (the ONLY declaration; see --print-suite-globs) ---------
#
# These are the patterns the glob loop further down expands. They live HERE, in an array with
# a machine-readable accessor, for one reason: scripts/lint-orphan-test-suites.sh must diff
# `git ls-files '*.test.sh'` against what this runner actually registers, and the only safe way
# for it to know these patterns is to ASK. A second copy of the list inside the linter would
# make the linter blind to the one mutation it exists to catch — delete a pattern here and the
# suites it covered stop running while the linter, reading its own stale copy, still reports
# `orphan test suites: none` (Guard 1 row M5). Deriving turns a duplicated list into a contract.
#
# QUOTED, individually. An unquoted array literal is pathname-expanded AT ASSIGNMENT, which
# would freeze today's matches into the array and silently stop registering files added later.
#
# `plugins/soleur/skills/*/scripts/*.test.sh` is deliberately NOT here: measured, it matches
# zero tracked files (the four linear-fetch suites #7402 recorded under `scripts/` were
# `git mv`d to `.../test/` by #7482 and are covered by the `skills/*/test/` entry above it).
# A glob matching nothing is not coverage — it is a line that makes a future suite
# auto-register without anyone deciding to. The linter's orphan report is that decision point.
SUITE_GLOBS=(
  'plugins/soleur/test/*.test.sh'
  'plugins/soleur/skills/*/test/*.test.sh'
  'plugins/soleur/scripts/*.test.sh'
  '.claude/hooks/*.test.sh'
  # `.claude/hooks/lib/*.test.sh` is a separate entry because shell globs do not cross `/`:
  # the `.claude/hooks/*.test.sh` entry above never reached the lib/ subdirectory and
  # freeze-lock.test.sh had never gated CI (#7409).
  '.claude/hooks/lib/*.test.sh'
  'apps/cla-evidence/scripts/*.test.sh'
  'apps/web-platform/scripts/*.test.sh'
  'apps/web-platform/scripts/lib/*.test.sh'
  'scripts/lib/*.test.sh'
)

# Answer the linter's question and exit, BEFORE anything with a side effect: no TMPDIR export,
# no bare-repo guard, no TEST_GROUP validation (which would reject this argv as a group name and
# exit 2), no tc_acquire — the linter runs INSIDE the advisory lock this runner holds, so a code
# path that blocks on it would deadlock the gate on itself.
if [[ "${1:-}" == "--print-suite-globs" ]]; then
  printf '%s\n' "${SUITE_GLOBS[@]}"
  exit 0
fi

# Answer "can this box absorb another full gate?" and exit, under the SAME
# discipline as --print-suite-globs above: BEFORE anything with a side effect —
# no TMPDIR export, no bare-repo guard, no TEST_GROUP validation, and above all
# no tc_acquire, since a pre-launch probe that blocked on the lock would queue
# behind the very run the caller is asking whether to start (#7545).
#
# THIS IS THE DELIVERABLE FOR THE ISSUE'S TITLE. "A session cannot tell before
# launching whether the box can absorb another full gate" — it can now, in under
# a second, without running a suite or taking the lock.
#
# IT ALWAYS EXITS 0, including on a contended box. The verdict is a STATEMENT:
# it reports and the caller decides. An `exit 1` here would make every consumer
# a gate — lefthook's pre-commit hook runs this runner, so a non-zero would
# block `git commit` — and that decline was cut on measured evidence (see
# tc_capacity_line's header and the ADR-133 addendum).
#
# Sources the lib INDEPENDENTLY, because the normal source site sits below the
# bare-repo guard this branch deliberately precedes. Same defensive shape: a
# missing lib degrades to a named CAPACITY_UNKNOWN rather than to silence, so
# the answer can never simply vanish.
if [[ "${1:-}" == "--capacity" ]]; then
  # Mirrors the pin below: the contention lib observes the /tmp TMPFS, not
  # whatever TMPDIR the caller happens to carry.
  export TC_TMPDIR="${TC_TMPDIR:-/tmp}"
  _cap_lib="$(dirname "${BASH_SOURCE[0]}")/lib/test-contention.sh"
  if [[ -f "$_cap_lib" ]]; then
    # shellcheck source=scripts/lib/test-contention.sh
    source "$_cap_lib" || true
  fi
  if declare -F tc_capacity_line >/dev/null 2>&1 && declare -F tc_preamble >/dev/null 2>&1; then
    # tc_preamble is what performs the single /proc walk and promotes its
    # readings; its own output is not wanted here, only the verdict built from
    # them. One walk, one source of truth.
    tc_preamble >/dev/null 2>&1 || true
    tc_capacity_line
    # The per-sibling detail is what makes the verdict ACTIONABLE: "contended"
    # tells you to wait, "pid 2266786 in .worktrees/feat-x, 1214s in" tells you
    # what you are waiting for.
    # The rows tc_preamble ALREADY resolved on the walk above. Calling
    # tc_siblings here was a SECOND non-atomic walk, and it produced exactly the
    # contradiction the promotion exists to prevent — reproduced on this box:
    #   CAPACITY_OK measured_siblings=0
    #     -> pid 1497146 in .../feat-one-shot-7545... (running 3s)
    #     -> pid 1497376 ...
    #     -> pid 1503142 ...
    # a verdict of "idle" printed directly above three enumerated siblings,
    # because the count came from walk #1 and the rows from walk #2 six seconds
    # later. It also doubled this branch's latency.
    _cap_rows="${TC_LAST_SIB_ROWS:-}"
    if [[ -n "${_cap_rows//[[:space:]]/}" ]]; then
      while IFS=$'\t' read -r _cp _cc _ce; do
        [[ -n "$_cp" ]] || continue
        printf '[contention]   -> pid %s in %s (running %ss)\n' "$_cp" "$_cc" "$_ce"
      done <<< "$_cap_rows"
    fi
  else
    echo '[contention] BANNER CAPACITY_UNKNOWN reason=lib_unavailable'
  fi
  exit 0
fi

# Default TMPDIR to /var/tmp (disk-backed) rather than /tmp.
#
# /tmp on this machine class is a ~4 GiB SHARED tmpfs, and parallel worktrees are this
# repo's documented workflow — so two concurrent runs compete for the same RAM-backed
# capacity. The observed failure is a suite TIMEOUT that reads exactly like a real
# regression (documented in-repo for skill-security-scan #4096 and vitest.config.ts
# #3817/#4128), plus abandoned sibling scratch dirs that produced a false RED and a
# blocked tool-output failure. Six separate places in the repo currently DOCUMENT the
# workaround "run with TMPDIR=/var/tmp"; setting it here removes the footgun instead of
# documenting it a seventh time.
#
# Respects an explicit caller value — CI or an operator pinning TMPDIR keeps it.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Pin the #6789 contention instrumentation to /tmp, INDEPENDENTLY of TMPDIR above.
#
# test-contention.sh binds `TC_TMPDIR="${TC_TMPDIR:-${TMPDIR:-/tmp}}"` at SOURCE time, so
# without this line the TMPDIR default above silently repoints it at /var/tmp. That is
# fail-open in the worst way: the lib exists to observe headroom on the /tmp TMPFS, and
# /var/tmp is disk-backed with hundreds of GB free, so every reading would come back
# healthy while the mount it was built to watch went unobserved. Instrumentation aimed at
# the wrong mount is indistinguishable from a healthy mount.
#
# The two settings are deliberately separate and must stay that way (see the
# "RELATIONSHIP TO test-contention.sh" section of scripts/lib/scratch-root.sh): suites get
# a disk-backed scratch dir, the janitor keeps watching the tmpfs.
export TC_TMPDIR="${TC_TMPDIR:-/tmp}"

# Sequential test runner that isolates test suites to avoid Bun's FPE crash
# when running all tests via recursive directory discovery.
# See: knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md
#
# Per-suite timing: when TEST_TIMING_LOG is set to a writable path, each
# run_suite() invocation appends "<label>\t<elapsed_ms>[\tFAIL|\tKILLED]" to that
# path. Field 3 carries the result class for any non-passing suite; KILLED means
# signal-shaped and UNRESOLVED, not failed (#7424).
# Elapsed time uses bash 5.0+ EPOCHREALTIME (microsecond precision, no
# coreutils dependency, portable across Linux + Homebrew bash on macOS).
# CI runs ubuntu-latest (bash 5.x). macOS default /bin/bash is 3.2 — install
# bash 5 from Homebrew if you need timing locally; otherwise EPOCHREALTIME is
# unset and elapsed_ms computes 0 silently.
#
# Both reads below are `${EPOCHREALTIME:-}`, never bare. This file runs under
# `set -euo pipefail` (line 2), so a BARE read on a shell without the variable
# is an unbound-variable ABORT in run_suite — the runner would die on its FIRST
# suite with no summary, no rc file and no [FAIL], which is exactly the shape
# work/SKILL.md's triage table attributes to a harness REAP, sending the
# operator into a relaunch loop that reproduces it forever. The `*.*` guard
# below only works if the read reaches it. (#7484 review; the same class was
# found and fixed in scripts/lib/test-contention.sh.)

# --- Version Check ---
# Gated on bun being installed so the script runs cleanly in a bun-free
# environment (TEST_GROUP=scripts in CI omits setup-bun by design — the
# scripts shard needs no bun and no node *version pin*: it uses stock
# ubuntu-latest node, unpinned, for the one `node --test` suite below).
if [[ -f .bun-version ]] && command -v bun >/dev/null 2>&1; then
  expected=$(tr -d '[:space:]' < .bun-version)
  actual=$(bun --version)
  if [[ "$actual" != "$expected" ]]; then
    echo "WARNING: Bun $actual installed, expected $expected (from .bun-version)" >&2
    echo "Run: bun upgrade" >&2
  fi
fi

# --- Git Hook Isolation ---
# When invoked as a lefthook pre-commit hook, git sets GIT_DIR, GIT_INDEX_FILE,
# and GIT_WORK_TREE in the environment. These override GIT_CEILING_DIRECTORIES
# and cause test-spawned git commands to operate on the parent repo instead of
# their temp directories. Unsetting them restores normal git discovery behavior.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

# --- Bare Repo Guard ---
# Bare repos contain stale working-tree files that diverge from HEAD.
# Running tests from a bare root produces phantom failures.
# Use a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh
if git rev-parse --is-bare-repository 2>/dev/null | grep -q true; then
  echo "ERROR: Cannot run tests from a bare repository root." >&2
  echo "Stale files at the bare root diverge from HEAD and produce phantom test failures." >&2
  echo "Run from a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh" >&2
  exit 1
fi

# --- Contention instrumentation (#6789) ---
# Observe-only: /tmp headroom, sibling test-all.sh runs resolved to their
# worktrees, and machine pressure. Sourced defensively — a missing or broken
# lib must degrade to a normal run, never block tests. The no-op fallbacks
# below keep every call site total.
_TC_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/test-contention.sh"
if [[ -f "$_TC_LIB" ]]; then
  # shellcheck source=scripts/lib/test-contention.sh
  source "$_TC_LIB" || true
fi
# Guard on tc_acquire AND tc_capacity_line. The single-function form was
# reproduced dying under version skew: a lib that defines tc_acquire but not
# tc_capacity_line (an origin/main-era copy in a mixed checkout, a stale plugin
# cache, a half-reverted worktree) left the stubs uninstalled, and the bare
# top-level `tc_capacity_line >&2` below exited 127 under `set -e` —
#   scripts/test-all.sh: line 814: tc_capacity_line: command not found
# with NO summary, NO rc file and NO [FAIL] line, which is the signature this
# repo documents as "a harness reap, not your diff".
#
# The old parenthetical said tc_acquire is "the LAST-defined function in the
# lib". That was FALSE and had been false on main: tc_epilogue is defined after
# it (941 vs 816 here, 660 vs 569 on main). The all-or-nothing-parse argument it
# rested on is real but covers TRUNCATION only, never skew — so the guard now
# names every function whose absence would abort, rather than one function
# believed to dominate the rest. bash parses a
# sourced file all-or-nothing, so a file truncated at an exact function boundary
# is the only state where an earlier function exists but a later one does not —
# checking the last one closes even that edge. If the lib is absent or failed to
# parse, install no-op stubs for every call site so a broken/missing lib degrades
# to a normal run rather than aborting the suite.
# Checked as a SET, not via a proxy. Guarding on one function treats "the lib
# failed to load at all" as the only failure — true for a missing or truncated
# file, false for VERSION SKEW, which is the live case (an origin/main-era lib in
# a mixed checkout, a stale plugin cache, a half-reverted worktree). Reproduced:
# a lib with tc_acquire but no tc_capacity_line left the stubs uninstalled and
# the bare top-level call below exited 127 with no summary, no rc file and no
# [FAIL] line. The list is asserted against the stub bodies by
# scripts/test-all-capacity-signal.test.sh, so adding a stub without adding its
# name here reds.
_TC_STUBBED_FNS="tc_preamble tc_epilogue tc_tmp_entry_count tc_used_bytes tc_acquire tc_capacity_line"
_tc_lib_incomplete=0
for _tc_fn in $_TC_STUBBED_FNS; do
  declare -F "$_tc_fn" >/dev/null 2>&1 || _tc_lib_incomplete=1
done
if (( _tc_lib_incomplete )); then
  echo "WARNING: contention instrumentation unavailable ($_TC_LIB); continuing without it." >&2
  tc_preamble() { :; }
  tc_epilogue() { :; }
  tc_tmp_entry_count() { printf '0\n'; }
  tc_used_bytes() { printf '0\n'; }
  tc_acquire() { :; }
  # NOT a no-op, unlike its siblings above. Every other stub here degrades an
  # OBSERVATION to a harmless zero; this one degrades an ANSWER, and an answer
  # that silently vanishes is the failure this verdict exists to prevent — a
  # reader who sees no CAPACITY_ line cannot tell "the box is fine" from "the
  # instrument is gone". AC15/M11 pin it.
  tc_capacity_line() { echo '[contention] BANNER CAPACITY_UNKNOWN reason=lib_unavailable'; }
fi

# ADR-133 amendment instrument: bytes held per mount, at RUN boundaries.
#
# WHY BYTES. The per-suite probe records `tmp_delta=<ENTRY COUNT>`, but ADR-133's
# capacity verdict is about BYTES — it explicitly rejected count-based reasoning
# because 4,294 small entries held 160 MB (4.5%) while three trees held 3.1 GiB
# (88%). The quantity the advisory lock exists to protect had never been measured
# by the instrument shipped to measure it.
#
# WHY RUN BOUNDARIES AND NOT PER SUITE. `du` is a RECURSIVE walk, unlike the
# shallow `find -maxdepth 1` the entry-count probe uses. At two edges x ~289
# suites that is ~578 walks per mount over multi-GiB trees — the same
# observer-effect confound that got a background sampler rejected during
# planning. Four walks answer the question ADR-133 actually asks: how many bytes
# did this run hold on each mount. WHICH suite holds them is the coincident-peak
# question, and that belongs to the deferred multi-run experiment.
#
# TWO DIRECTORIES, NEVER SUMMED. TMPDIR is /var/tmp (disk-backed) and TC_TMPDIR
# is /tmp (the 4 GiB tmpfs) — deliberately different mounts. A single number
# spanning both would report health from whichever is roomier, which is
# indistinguishable from a healthy mount.
#
# Gated on TEST_TIMING_LOG, so a default local run pays nothing for it.
_emit_bytes_probe() {
  [[ -n "${TEST_TIMING_LOG:-}" ]] || return 0
  local tmpfs_bytes disk_bytes
  tmpfs_bytes=$(tc_used_bytes "${TC_TMPDIR:-/tmp}")
  disk_bytes=$(tc_used_bytes "${TMPDIR:-/var/tmp}")
  printf '%s\t0\tbytes_tmp=%s\tbytes_tmpdir=%s\n' \
    "$1" "$tmpfs_bytes" "$disk_bytes" >> "$TEST_TIMING_LOG"
}

# --- Relevance predicates (ADR-181) ---
# Sourced at TOP LEVEL, and deliberately NOT defensively, unlike the contention lib above. That
# one is observe-only, so a missing lib must degrade to a normal run. This one DECIDES WHETHER
# SUITES EXECUTE: were it absent and the arrays empty, every gated suite would decline silently
# and the summary would still read green — the exact "green that is not evidence" the gate
# exists to prevent, produced by the gate itself. A missing file is a hard failure.
# --- Repo-write boundary lib (#7652) ------------------------------------------------------
#
# The _REL_LIB class of contract, not the _TC_LIB `|| true` class, and the selection rule is the
# one _REL_LIB's own comment states: a lib that decides whether the gate MEANS ANYTHING is a hard
# failure when missing. Under `|| true`, `_repo_state` would be undefined, return 127 inside
# `if _repo_state_before="$(_repo_state)"` — where `set -e` does not fire — and the run would
# print "the repo-write boundary was not measured (git unavailable at run start)", naming a cause
# it did not measure. That is an AP-021 violation manufactured by the fix for #7652.
#
# `test -f` is checked too, and is not sufficient on its own: it proves a file exists, never that
# it defines what the caller will call. So the named function SET is asserted in the _TC_LIB
# shape, and a STALE lib is NAMED rather than silently narrowing the gate behind a full-width
# claim.
#
# Placed HERE, above `tc_acquire`, deliberately: both suites that drive this runner as their SUT
# splice out everything between that anchor and `tc_epilogue`, and the end block runs under
# `set -u`. A source line below the anchor is deleted in those sandboxes and surfaces as two
# unrelated red suites instead of one honest failure.
_RWB_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/repo-write-boundary.sh"
if [[ ! -f "$_RWB_LIB" ]]; then
  echo "ERROR: missing $_RWB_LIB — the repo-write boundary is undefined." >&2
  echo "Refusing to run: without it this runner cannot tell whether a suite wrote to your" >&2
  echo "repository, and a silent clean claim is worse than no claim." >&2
  echo "" >&2
  echo "  Restore it:  git checkout -- scripts/lib/repo-write-boundary.sh" >&2
  echo "  This runner also runs from lefthook's pre-commit hook. To commit before restoring:" >&2
  echo "    git commit --no-verify     (or)    LEFTHOOK=0 git commit" >&2
  exit 2
fi
# shellcheck source=scripts/lib/repo-write-boundary.sh
source "$_RWB_LIB"
_RWB_MISSING=""
for _rwb_fn in _repo_state repo_boundary_manifest \
               repo_boundary_render_inspected repo_boundary_render_not_inspected \
               repo_boundary_classify repo_boundary_next_action; do
  declare -F "$_rwb_fn" >/dev/null || _RWB_MISSING="$_RWB_MISSING $_rwb_fn"
done
if [[ -n "$_RWB_MISSING" ]]; then
  echo "ERROR: $_RWB_LIB is present but STALE — missing:$_RWB_MISSING" >&2
  echo "Refusing to run: a narrower check beneath a full-width claim is the exact defect the" >&2
  echo "boundary exists to prevent." >&2
  echo "" >&2
  echo "  Restore it:  git checkout -- scripts/lib/repo-write-boundary.sh" >&2
  echo "  To commit before restoring:  git commit --no-verify   (or)   LEFTHOOK=0 git commit" >&2
  exit 2
fi
unset _rwb_fn

_REL_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/test-relevance-paths.sh"
if [[ ! -f "$_REL_LIB" ]]; then
  echo "ERROR: missing $_REL_LIB — the suite relevance predicates are undefined." >&2
  echo "Refusing to run: without them every gated suite would decline silently while the" >&2
  echo "summary still reported green." >&2
  exit 2
fi
# shellcheck source=scripts/lib/test-relevance-paths.sh
source "$_REL_LIB"

# --- Test group selector ---
# TEST_GROUP partitions the suite list across CI matrix shards. Env var wins
# over positional ($1) so GitHub Actions `env:` blocks and `gh workflow run`
# compose without rewriting the call site. Default `all` preserves byte-
# identical behavior for local invocation and any caller that never set this.
#
#   all      every suite, in original order (no-args default)
#   webplat  only apps/web-platform vitest
#   bun      3 named bun tests + plugins/soleur + blog-link-validation
#   scripts  11 pre-suite bash/python + 21 plugins/soleur/test/*.test.sh
#   infra    ONLY the CI-registered apps/web-platform/infra/ runner (#7103 R5(a)).
#            This is the "TEST_GROUP asks" arm of the relevance gate below: an
#            explicit ask bypasses the diff check, so an infra run is reachable
#            without fabricating a diff. It is deliberately NOT part of `all`'s
#            shard set in ci.yml — infra gates through infra-validation.yml there.
#
# See `.github/workflows/ci.yml` test-{webplat,bun,scripts} jobs + the
# synthetic `test` aggregator. See plan
# `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`.
TEST_GROUP="${TEST_GROUP:-${1:-all}}"
case "$TEST_GROUP" in
  all|webplat|bun|scripts|infra) ;;
  *)
    echo "ERROR: TEST_GROUP must be one of: all, webplat, bun, scripts, infra (got: $TEST_GROUP)" >&2
    echo "Usage: bash scripts/test-all.sh [all|webplat|bun|scripts|infra]" >&2
    echo "   or: TEST_GROUP=<value> bash scripts/test-all.sh" >&2
    exit 2
    ;;
esac

# --- Subagent full-gate refusal (Item 6 of the 2026-08-11 test-pipeline post-mortem) ---------
# A spawned subagent runs only the suites targeting the files it was given. Three review agents
# running lints and suites concurrently inflated a measurement of the registry mutation battery
# by 1.9x (860 s -> 1675 s): the battery did not get slower, the machine did. A timing figure
# taken under that contention is not a measurement of the code — and this runner now GATES
# suites on measured cost, so a corrupted measurement propagates into what runs at all.
#
# MECHANICAL, not prose. The fan-out instructions in plugins/soleur/skills/{work,review}/SKILL.md
# carry the same rule in English, but a paragraph in a prompt IS agent discretion: a grep
# asserting that paragraph exists certifies the instruction was WRITTEN, never that it was
# obeyed. Those clauses explain this guard; this guard is what enforces it.
#
# It fires HERE — after TEST_GROUP is validated so the message can name it, but before
# tc_acquire and before the first suite — so a refused run costs nothing and never takes the
# advisory lock that a legitimate sibling run is queued on.
if [[ "${SOLEUR_SUBAGENT:-}" == "1" && "${SOLEUR_ALLOW_FULL_GATE:-}" != "1" ]]; then
  echo "ERROR: refusing a full-gate run — SOLEUR_SUBAGENT=1 is set (TEST_GROUP=$TEST_GROUP)." >&2
  echo "" >&2
  echo "Spawned agents run only the suites targeting the files they were given. Concurrent" >&2
  echo "full-gate runs inflate each other's timings and corrupt the measurement. The lead runs" >&2
  echo "the gate once, after collecting fan-out work." >&2
  echo "" >&2
  echo "Run the suite covering your files instead:" >&2
  echo "    bash <path/to/the/suite.test.sh>" >&2
  echo "" >&2
  echo "If you are the lead and this IS the sanctioned gate run, override explicitly:" >&2
  echo "    SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh" >&2
  # rc 4, deliberately NOT 3. #7424 assigned rc 3 the meaning "a suite was terminated —
  # unresolved, coverage not obtained", and that trichotomy is documented in one-shot/SKILL.md.
  # A refusal is the opposite claim (nothing ran, by design, and nothing is unresolved), so it
  # needs its own code; sharing 3 would make a refused run read as a killed suite. 1 is an
  # ordinary suite failure and 2 is a bad TEST_GROUP, so 4 is the next free value.
  exit 4
fi

want_scripts() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts" ]]; }
want_bun()     { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun"     ]]; }
want_webplat() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "webplat" ]]; }
# `infra` is reachable from `all` (so a default local run covers it when the diff is
# relevant) and from an explicit ask. It is NOT folded into `scripts`: that shard is a CI
# matrix job with no terraform/cloud-init toolchain, and registering an 87-suite runner
# into it would red a required check for want of a binary (#6454's exact shape).
want_infra()   { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "infra"   ]]; }

# --- Run Tests Per Directory ---
failed=0
suites=0
# Beside failed/suites deliberately, and required — but for a different reason
# than an earlier revision of this comment claimed. MEASURED 2026-08-11 (bash
# 5.3.9): with `killed` unset, `set -u` aborts at the FIRST read, which is the
# breakdown gate — ABOVE the terminal marker, not below it — and the run exits
# 1, not 0. So the failure mode is a loud abort with no terminal marker, not a
# silent false green. That shape is what work/SKILL.md reads as "a failure with
# no marker", which sends a reader hunting for [FAIL] lines that do not exist.
killed=0

# Classify a suite's exit code into exactly one of: ok | failed | killed.
#
# `killed` means SIGNAL-SHAPED, not "was killed by <signal>". $? cannot tell a
# signal death from a literal exit(128+N) — `bash -c 'exit 143'` also yields 143
# — so the class is a statement about the SHAPE of the status, and the rendered
# line says so. Naming a cause here would reintroduce, one layer up, the defect
# this whole change exists to remove.
#
# All three guards are load-bearing. Measured 2026-08-10, bash 5.3.9/Linux:
#   kill -l 0   -> "EXIT"  (rc 0)          so `rc > 128` is what excludes rc=128
#   kill -l 32  -> ""      (rc 0)          glibc-internal SIGCANCEL
#   kill -l 33  -> ""      (rc 0)          glibc-internal SIGSETXID
#                                          so `-n "$name"` is what excludes 160/161
#   kill -l 143 -> "TERM"                  it MASKS values > 64
# `kill -l` is therefore NOT a validity oracle. Anyone "simplifying away the
# redundant > 128 check because kill -l already bounds it" breaks the classifier.
#
# The numeric guard closes an INPUT-side false green: without it, `(( rc == 0 ))`
# on "" or " " evaluates TRUE and returns `ok` — the one class that increments no
# counter and emits no warning. Not reachable from today's run_suite (`local rc=0`
# guarantees numeric) but reachable from the suite that certifies this function.
suite_exit_class() {
  local rc="${1-}" name
  [[ "$rc" =~ ^[0-9]+$ ]] || { printf 'failed\n'; return 0; }   # fail CLOSED on a malformed rc
  (( rc == 0 )) && { printf 'ok\n'; return 0; }
  # `<= 192` is a legibility bound and is NOT load-bearing: the call passes
  # `kill -l $(( rc - 128 ))`, so for every rc in 193..255 the operand is 65..127,
  # which kill -l rejects — the `-n "$name"` guard already excludes it. Mutating
  # this to `rc > 128` leaves every table row byte-identical, so no test pins it.
  # It is kept to state the intended domain, not because a row proves it.
  if (( rc > 128 && rc <= 192 )); then
    name=$(kill -l $(( rc - 128 )) 2>/dev/null) || name=""
    [[ -n "$name" ]] && { printf 'killed\n'; return 0; }
  fi
  printf 'failed\n'
}

# Declared wall-clock budgets for suites known to be long. A `case`, not a
# `declare -A`: no initialization ordering to get right, no associative-array
# declaration at the top of a ~1000-line script, and zero churn at the 132
# run_suite call sites. Emits nothing for an undeclared label.
#
# A budget NEVER changes a suite's status or the runner's exit code. It exists so
# that a nine-minute suite is a STATED FACT rather than a surprise — which is the
# attribution half of what a reader needs when a long suite does not come back.
_suite_budget_ms() {
  case "$1" in
    # MEASURED 2026-08-11, both runs completing rc=0 on this 16-core host:
    #   860692ms  as run BY THIS RUNNER (TEST_TIMING_LOG), one sibling worktree
    #             running an individual suite concurrently
    #   1675430ms standalone, with three concurrent agent sessions on the box
    # Load alone moves it 1.9x, so a budget near either figure would fire on
    # ordinary busy runs and become noise. Declared at ~1.5x the HIGHEST observed.
    #
    # NOT derived from the incident's 560931ms: that is elapsed AT THE KILL,
    # roughly two thirds of the way in, so it is a lower bound on the duration
    # and useless as a budget.
    tests/scripts/registry-gate-mutation-battery) printf '2500000\n' ;;
    *) return 0 ;;
  esac
}

# Declines (ADR-181). Beside failed/killed for the same reason: a suite that was not run
# is not a suite that passed, and the denominator must still account for it.
skipped=0

run_suite() {
  local label="$1"; shift
  suites=$((suites + 1))
  # Per-suite tempfile delta (#6789, probe for hypothesis H4: a shared derived
  # tempfile path in some suite reached by this runner). Gated on
  # TEST_TIMING_LOG so the `find` costs nothing on a default local run.
  local tmp_before=""
  if [[ -n "${TEST_TIMING_LOG:-}" ]]; then
    tmp_before=$(tc_tmp_entry_count)
  fi
  # Recorded so the repo-write boundary can NAME the suite in flight when a write happened,
  # instead of reporting "something in this run wrote to your repo" and leaving the reader the
  # same ~330-suite haystack the incident already cost someone once. One assignment per suite;
  # per-suite git snapshots would narrow it further and cost ~660 extra process spawns, which is
  # not worth it for a strictly-narrower answer.
  _repo_last_suite="$label"
  local start="${EPOCHREALTIME:-}"
  echo "--- $label ---"
  # Capture the exit code rather than testing it. `if ! "$@"` is a boolean test:
  # it discards WHICH non-zero the suite returned, which is precisely the
  # information needed to tell a terminated suite from a failed one.
  local rc=0
  "$@" || rc=$?
  # An ABORTING classifier is its own degradation and must not be absorbed into
  # the ordinary `failed` bucket: that would make a broken classifier — which can
  # mis-bucket every subsequent suite — indistinguishable from one honest test
  # failure, silently. It is routed to the same fail-closed arm as an
  # unrecognized class so it is counted FAILED and SAID OUT LOUD.
  local status="failed" cls_rc=0
  status="$(suite_exit_class "$rc" 2>/dev/null)" || cls_rc=$?
  if (( cls_rc != 0 )); then
    status="__aborted(rc=$cls_rc)__"
  fi
  case "$status" in
    ok)     ;;
    failed) failed=$((failed + 1)) ;;
    killed) killed=$((killed + 1)) ;;
    # Fail CLOSED. Without this arm an unrecognized class increments NEITHER
    # counter, and `$((suites - failed - killed))` then counts the suite as
    # PASSED — the exact false green this change exists to prevent.
    *)      echo "WARNING: suite_exit_class returned unrecognized class '$status' for rc=$rc (classifier exit=$cls_rc); counting as FAILED." >&2
            status="failed"; failed=$((failed + 1)) ;;
  esac
  # Integer math on EPOCHREALTIME ("seconds.microseconds") avoids a coreutils
  # `date +%N` dependency that macOS lacks. 10# forces base-10 parsing of the
  # microseconds substring (a leading zero would otherwise trigger octal).
  # The `*.*` glob guard rejects bash-3.x values (where EPOCHREALTIME is unset
  # and the captured value is empty or non-dotted) and exits elapsed_ms=0
  # gracefully instead of arithmetic-overflowing on `${start#*.}` returning
  # the whole string.
  local end="${EPOCHREALTIME:-}"
  local elapsed_ms=0
  if [[ "$start" == *.* && "$end" == *.* ]]; then
    local start_us=$(( ${start%.*} * 1000000 + 10#${start#*.} ))
    local end_us=$(( ${end%.*} * 1000000 + 10#${end#*.} ))
    elapsed_ms=$(( (end_us - start_us) / 1000 ))
  fi
  # Appended as a LABELED trailing field (`tmp_delta=<N>`), never as a bare
  # positional one: field 3 already carries the `FAIL` marker, so an unlabeled
  # append would be positionally ambiguous between the ok and FAIL shapes.
  local tmp_field=""
  if [[ -n "${TEST_TIMING_LOG:-}" && -n "$tmp_before" ]]; then
    tmp_field=$'\t'"tmp_delta=$(( $(tc_tmp_entry_count) - tmp_before ))"
  fi
  # Advisory only: never changes status, never changes the exit code.
  local budget_ms; budget_ms="$(_suite_budget_ms "$label")"
  if [[ -n "$budget_ms" ]] && (( elapsed_ms > budget_ms )); then
    echo "[budget] $label ran ${elapsed_ms}ms against its declared ${budget_ms}ms budget — expected-long suite, declared here so a long run is a stated fact rather than a surprise." >&2
  fi
  # `[ok]` and `[FAIL]` keep their EXACT current text. Every monitor, learning and
  # skill anchored on `^\[FAIL\]` must keep working byte-for-byte; the new class is
  # additive, never a re-spelling of an existing one.
  if [[ "$status" == "ok" ]]; then
    echo "[ok] $label (${elapsed_ms}ms)"
    printf '%s\t%d%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  elif [[ "$status" == "killed" ]]; then
    # A declared budget is named HERE, on the one line where it changes the
    # reading: it tells the reader whether this suite's elapsed time was expected.
    # Without it "560931ms" is a bare number; with it, it is two thirds of a
    # declared 2500000ms budget, i.e. the kill was not this runner running long.
    # OUTSIDE the parenthetical, deliberately. main-health-monitor.yml anchors on
    # the exact shape `(exit=N, signal-shaped 128+n = SIGNAME, Nms)`; putting the
    # budget note inside it makes that grep miss and routes every terminated suite
    # to the generic "did not complete" arm. Measured — this comment exists because
    # the note was first written inside the parens and the monitor went blind.
    local _kb; _kb="$(_suite_budget_ms "$label")"
    local _bnote=""
    [[ -n "$_kb" ]] && _bnote=" This suite declares a ${_kb}ms budget, so compare the elapsed above against it before treating the duration as anomalous."
    echo "[KILLED] $label (exit=$rc, signal-shaped 128+$(( rc - 128 )) = SIG$(kill -l $(( rc - 128 )) 2>/dev/null), ${elapsed_ms}ms) — UNRESOLVED, not a failure: this runner did not measure what terminated it, and exit $rc is also what a suite calling exit($rc) reports.${_bnote}" >&2
    printf '%s\t%d\tKILLED%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  else
    echo "[FAIL] $label (${elapsed_ms}ms)" >&2
    printf '%s\t%d\tFAIL%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  fi
}

# A DECLINE IS A VERDICT, NOT AN ABSENCE (ADR-181).
#
# run_suite increments `suites` on ENTRY, so the older shape — wrapping the call in an `if` and
# echoing a notice on the else branch — silently removed the declined suite from the
# denominator. `N/N suites passed` then read IDENTICALLY whether a suite was deliberately gated
# or had been DE-REGISTERED, and the second is the #3366 class one level up: a suite running in
# zero runners behind a green summary. Counting the decline is what makes those two states
# distinguishable without reading the log body.
#
# A SIBLING of run_suite, deliberately NOT an option on it. scripts/lint-orphan-test-suites.sh
# anchors suite registration on the literal `run_suite ` token, and extracts the registered
# path from COMMAND position (the token after `bash`) on that line — so a
# `run_suite --skip-if-not-relevant "<paths>"` shape would let a path in the predicate list
# satisfy the registration check for a DIFFERENT suite than the one executed, and deleting that
# suite's real registration would still report `orphan test suites: none`. `skip_suite ` cannot
# match `^[[:space:]]*run_suite `, so it is invisible to that anchor by construction.
#
# $1 = label (must match the label the suite would have run under)
# $2 = machine-readable reason  $3 = the exact command that re-runs it
skip_suite() {
  local label="$1" reason="$2" rerun="$3"
  suites=$((suites + 1))
  skipped=$((skipped + 1))
  echo ""
  echo "[skip] $label ($reason)"
  echo "      Nothing in this run is evidence for it. Re-run with:"
  echo "        $rerun"
  echo ""
  # LABELLED trailing field, never a bare positional one: field 3 already carries the `FAIL`
  # marker, so an unlabelled append would be positionally ambiguous across the ok, FAIL and
  # skip shapes. Same reasoning the tmp_delta= field above already applies.
  printf '%s\t%d\tskip=%s\n' "$label" 0 "$reason" >> "${TEST_TIMING_LOG:-/dev/null}"
}

# INFRA RELEVANCE DETECTION (#6730/#7014, converted from a boundary to a gate by #7103).
# This runner NOW COVERS apps/web-platform/infra/, by registering
# apps/web-platform/infra/run-registered-suites.sh as a nested suite (see the registration
# block near the end of this file). That runner DERIVES its list from
# .github/workflows/infra-validation.yml, so registering it — rather than globbing the
# suites — is what keeps this file and CI from forking.
#
# What survives from #6730/#7014 is the DETECTION, which now decides whether to RUN the
# infra runner instead of merely whether to print a notice about not running it. The
# original gap cost two sessions: a required check was RED behind a 223/223 green here
# (#6730), and an infra diff was validated by the wrong runner entirely (#6969) — both
# times "all tests pass" was read as evidence for infra the run never touched. A notice
# asking the reader to go run something else is a weaker fix than running it, which is why
# this became a gate.
#
# It still fires HERE rather than after the suites: the announcement is only actionable
# while there is still a decision to make, and at the end of a ~20-minute run the cost is
# already paid. A one-line restatement stays in the epilogue for readers who `tail` the log.
#
# Detection reads a VARIABLE, not a pipe into `grep -q`. Under this script's `set -o
# pipefail` a `producer | grep -q` pipeline reports non-zero when grep exits on a match
# while the producer is still writing — the producer takes SIGPIPE (141) and pipefail
# surfaces it — so the condition evaluates FALSE despite the match. What decides this is
# whether the producer's output exceeds the ~64 KiB pipe buffer, NOT where the match sits:
# measured on a 185-byte diff the old form matched correctly every time, and only went
# fail-open past roughly 1,300 changed paths. So the old form was not failing open on
# realistic diffs — but it made correctness a function of diff SIZE, and a herestring has
# no producer to kill. Do not generalise this to "an early match causes SIGPIPE"; that is
# the wrong rule and it was written here first.
#
# Detection failure is reported, never silently equated with "no infra in the diff". Both
# refs can legitimately fail to resolve (shallow clone, no `origin`, a fresh repo) and the
# earlier form's `2>/dev/null … || true` made that indistinguishable from a clean result —
# a fail-open sitting inside the very notice this block exists to deliver. Untracked files
# are included too: `git diff --name-only` never lists them, so a session that ADDS a new
# infra suite and runs this before committing got no notice at all.
#
# `grep -qF` without a `^` anchor, and `core.quotePath=false`: git C-quotes any path with
# non-ASCII or control characters onto a single leading-quote line, which moves the path
# off the start of the line and defeats an anchored match. Over-matching a path that merely
# CONTAINS the directory string errs toward showing the notice, which is the safe direction.
# The two refs answer DIFFERENT questions and only one of them is load-bearing. `HEAD` sees
# uncommitted work; `origin/main...HEAD` sees what the BRANCH changes, which is the question
# the notice is about. On a branch whose infra edits are already committed the HEAD diff is
# legitimately empty, so treating "either ref resolved" as success reports a confident
# no-infra verdict from the ref that could not have known — measured on a scratch repo with a
# committed infra file and no remote. Only the range ref's failure means "could not determine".
_diff_detect_ok=0
_diff_head_ok=0
_diff_names=""
if _diff_out="$(git -c core.quotePath=false diff --name-only HEAD 2>/dev/null)"; then
  _diff_head_ok=1
  _diff_names="${_diff_names}
${_diff_out}"
fi
if _diff_out="$(git -c core.quotePath=false diff --name-only origin/main...HEAD 2>/dev/null)"; then
  _diff_detect_ok=1
  _diff_names="${_diff_names}
${_diff_out}"
fi
# RENAME SOURCES. `--name-only` emits only the DESTINATION of a rename, so `git mv` on a declared
# predicate path leaves the OLD path — the one the array names — absent from the diff, and the
# battery declines on the single most destructive edit possible to its own SUT. `--name-status -M`
# emits `R100<TAB>old<TAB>new`, and since matching is substring-based over this whole blob, adding
# it makes BOTH paths matchable. (The narrow window this closes is a rename WITHOUT a matching
# array update; `lint-orphan-test-suites.sh` already reds loudly in the same run for that case, so
# it was never a silent green — this just stops the suite declining while that error prints.)
_diff_names="${_diff_names}
$(git -c core.quotePath=false diff --name-status -M HEAD 2>/dev/null || true)
$(git -c core.quotePath=false diff --name-status -M origin/main...HEAD 2>/dev/null || true)"
# WIDENED from `-- apps/web-platform/infra` to the union of every prefix the relevance
# predicates declare. The narrow form was correct while the only consumer was the infra notice;
# as a suite GATE it was a fail-open, because a brand-new UNTRACKED mutation target under
# scripts/ or .github/ was invisible here — so the session that ADDS a target and runs the gate
# before committing would have had the suite declined on the very diff that needed it.
_diff_names="${_diff_names}
$(git ls-files --others --exclude-standard -- "${TEST_RELEVANCE_PREFIXES[@]}" 2>/dev/null || true)"

# Does this run's diff touch any of the given paths? Used to decline suites that guard code the
# diff does not reach. Substring match without a `^` anchor, matching the existing infra check:
# over-matching a path that merely CONTAINS the string errs toward RUNNING the suite, which is
# the safe direction.
#
# Reads a VARIABLE via a herestring, never `producer | grep -q`. Under this script's `set -o
# pipefail` that pipeline reports non-zero when grep exits on a match while the producer is
# still writing (SIGPIPE 141), which would make the condition evaluate FALSE despite the match —
# a fail-open whose likelihood scales with diff size. A herestring has no producer to kill.
_diff_touches() {
  # The two bypasses are UNCONDITIONAL early returns, not flags consulted later.
  #
  # Under CI a decline is therefore UNREACHABLE rather than merely detected. That is strictly
  # stronger than the assertion this replaced, and it is what keeps main-health-monitor green:
  # on `main` both diff refs resolve and return EMPTY, so _diff_detect_ok is 1 (the fail-SAFE
  # arm does not rescue it) and every gated suite would decline — an "assert no skips occurred"
  # design would have reddened that workflow every six hours.
  #
  # Written as explicit `if` blocks rather than `[[ … ]] && return 0`. Under this script's
  # `set -e` the short form's exit status depends on the CALL SITE — harmless inside an `if`
  # condition, an abort anywhere else — and a predicate that decides whether suites run must not
  # carry a landmine for the next caller.
  if [[ "${SOLEUR_TEST_FORCE_ALL:-}" == "1" ]]; then return 0; fi
  if [[ -n "${CI:-}" ]]; then return 0; fi
  # Fail SAFE, not fail quiet: a diff the runner could not determine RUNS everything.
  #
  # BOTH arms, not just the range. The HEAD arm is what sees UNCOMMITTED work, and it can fail
  # independently — a sibling process holding `index.lock` while `git diff` refreshes the index is
  # the realistic case in this repo, where parallel worktrees are the documented workflow. With
  # only the range arm consulted, that failure is swallowed: the range looks clean, and the battery
  # declines on a working tree carrying exactly the edits it guards.
  if [[ "$_diff_detect_ok" == 0 || "$_diff_head_ok" == 0 ]]; then return 0; fi
  local p
  for p in "$@"; do
    if grep -qF -- "$p" <<<"$_diff_names"; then return 0; fi
  done
  return 1
}

# Counted at the RELEVANCE call sites only. `skipped` also carries the infra runner's incident and
# not_in_diff declines, which SOLEUR_TEST_FORCE_ALL cannot force -- see the epilogue lever.
_relevance_declined=0

_infra_in_diff=0
# Two prefixes, not one. The infra guards assert against
# `.github/workflows/apply-web-platform-infra.yml` as well as against the `.tf`
# files -- `apex-single-node-replace.test.sh` reads its `-target=` allow-list --
# so a PR editing ONLY that workflow could drop an allow-list entry while this
# runner declined the whole infra suite as not-in-diff (#7640).
if grep -qF 'apps/web-platform/infra/' <<<"$_diff_names" \
  || grep -qF '.github/workflows/apply-web-platform-infra.yml' <<<"$_diff_names"; then
  _infra_in_diff=1
fi

if [[ "$_diff_detect_ok" == 0 ]]; then
  # Fail SAFE, not quiet: assume the boundary applies rather than assume it does not.
  _infra_in_diff=1
fi

# Observed, never predicted. Set ONLY where the runner is actually invoked; every coverage
# claim in this script keys off it.
_infra_ran=0
_infra_skip_reason=""

# WHY THE want_infra CONJUNCT IS LOAD-BEARING. These notices used to key on `_infra_in_diff`
# alone — a fact about the DIFF — while the runner keys on `want_infra`, a fact about
# TEST_GROUP, and nothing coupled them. CI runs `test-all.sh webplat`, `bun` and `scripts`;
# want_infra is false in all three. So on every CI run of an infra-touching PR — exactly the
# case this phase exists for — three job logs affirmatively announced that the infra runner
# would be invoked, and it never was. That is strictly worse than what it replaced: the old
# text said "infra is NOT covered above", which was true in every group. Inverting the
# sentence without adding this conjunct turned a universally-true warning into a
# conditionally-false assurance.
if ! want_infra; then
  _infra_skip_reason="group"
  if [[ "$_infra_in_diff" == 1 ]]; then
    echo ""
    echo "NOTE: your diff touches apps/web-platform/infra/, but TEST_GROUP=$TEST_GROUP does"
    echo "      NOT include the infra runner. Nothing below is evidence for that directory."
    echo "      Cover it with either:"
    echo "        bash apps/web-platform/infra/run-registered-suites.sh"
    echo "        TEST_GROUP=infra bash scripts/test-all.sh"
    echo ""
  fi
elif [[ "$_diff_detect_ok" == 0 ]]; then
  echo ""
  echo "NOTE: could not determine this branch's diff (no origin/main, shallow clone, or a"
  echo "      fresh repo), so this runner cannot tell whether apps/web-platform/infra/ is"
  echo "      affected. Assuming it IS: the CI-registered infra runner will be invoked"
  echo "      below as a nested suite. This costs time on an irrelevant diff, which is the"
  echo "      safe direction — the unsafe one is a green that skipped it silently."
  echo "      Set SOLEUR_INCIDENT_SKIP=1 to skip it on an incident path — that skip is loud"
  echo "      and prints its re-run command."
  echo ""
elif [[ "$_infra_in_diff" == 1 ]]; then
  echo ""
  echo "NOTE: your diff touches apps/web-platform/infra/. The CI-registered infra runner"
  echo "      (apps/web-platform/infra/run-registered-suites.sh) will be invoked below as a"
  echo "      nested suite, so the summary DOES account for it. Set SOLEUR_INCIDENT_SKIP=1"
  echo "      to skip it on an incident path — that skip is loud and prints its re-run"
  echo "      command."
  echo ""
fi

# Contention preamble — emitted before the first `--- <suite> ---` line so a
# contended run is self-identifying and a false RED is never again diagnosed
# as a regression (AC1/AC2).
tc_preamble
_TC_RUN_START_ENTRIES=$(tc_tmp_entry_count)

# Orphaned-PROCESS probe (#7537), emitted with the contention banners because it
# answers the same question they do — "is something else on this box eating the
# capacity this run needs?" — for processes rather than for /tmp.
#
# REPORT ONLY. Nothing in this repo invokes `reap` automatically: the detector
# has never been observed firing on a real orphan, so the first strike is a
# READER'S judgment. This is the moment an actor is present and already reading
# stderr, which is what makes a report here a decision point rather than a
# declaration site.
#
# `timeout 10` AND `|| true` are both load-bearing and cover different failures:
# `|| true` covers a non-zero exit, and `timeout` covers what it cannot — an
# unresponsive NFS/FUSE/autofs mount puts readlink/stat in uninterruptible
# sleep, and a command that never returns is never rescued by `|| true`.
#
# EXCLUDE_PGID is passed EXPLICITLY rather than inferred: `timeout` runs its
# child in its own process group, so the probe computing its own pgid would get
# timeout's pid rather than this runner's, and this runner's command-
# substitution forks would not be excluded from its own reap set.
if [[ -z "${CI:-}" ]] && [[ -x scripts/orphan-process-reaper.sh || -f scripts/orphan-process-reaper.sh ]]; then
  _orphan_rc=0
  ORPHAN_REAPER_EXCLUDE_PGID="$(command ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)" \
    timeout 10 bash scripts/orphan-process-reaper.sh report || _orphan_rc=$?
  # The caller emits on a non-zero rc ITSELF. `|| true` hides the status, so
  # without this line "the detector did not run" is indistinguishable from "it
  # ran and found nothing" — and the second reads as an all-clear.
  if [[ "$_orphan_rc" != "0" ]]; then
    printf 'ORPHAN_SCAN valid=0 reason=rc%s\n' "$_orphan_rc"
  fi
  unset _orphan_rc
fi

# The capacity verdict (#7545), emitted BETWEEN the preamble and the lock —
# after the readings exist, before the wait that may consume them.
#
# It is built from the values tc_preamble just promoted, never from a second
# /proc walk: two walks are two non-atomic snapshots, and a run that printed
# CAPACITY_OK above SIBLING_RUN_DETECTED: 2 would be reporting on two different
# machines. One call site, because the runner has one top-level control flow.
#
# Changes NO exit code and blocks NO suite. Every run that completes today still
# completes; the only new thing is that it says what it measured.
tc_capacity_line >&2

# --- Sibling full-gate refusal (#7553) -------------------------------------------------------
#
# The SOLEUR_SUBAGENT refusal above binds to a condition an agent must DECLARE. Nothing in this
# repository sets that variable — measured across every occurrence: ADR prose, learnings, archived
# plans, two skill sentences, and tests that set it for their own arm. So its antecedent has never
# held in normal operation and the refusal has never fired for the case it was written for.
#
# This one binds to a condition the runner MEASURES. tc_preamble has already resolved how many
# OTHER worktrees are running test-all.sh (via /proc, excluding this run's own ancestors and
# process group), so no spawn-path cooperation is needed and there is no fail-open mode when some
# upstream harness changes an undocumented variable. It is also the arm CI can actually run: start
# a real sibling, assert the second invocation is refused.
#
# It fires HERE, AFTER tc_preamble (which computes the count) and BEFORE tc_acquire, deliberately.
# Refusing after tc_acquire would make a run that should never have started wait up to
# TC_LOCK_TIMEOUT (900 s) to be told so, and take the advisory lock a legitimate sibling is queued
# on. A refused run must cost nothing.
#
# ADDITIVE, not a replacement: the SOLEUR_SUBAGENT arm above is untouched and still exits 4.
# The count must be one THIS process measured. TC_SIBLING_RUN_COUNT is exported, so a nested
# test-all.sh inherits it — and a suite that drives this runner as its SUT neuters tc_preamble
# in its sandbox, so the inherited number describes a machine state the sandbox never looked
# at. Refusing on it turned every such suite red whenever any sibling happened to be running,
# for a reason unrelated to its subject. Measured PRE-STAMP — i.e. against the tree before the
# TC_SIBLING_RUN_COUNT_PID condition below existed — `TC_SIBLING_RUN_COUNT=4` alone took
# test-all-killed-classification from 77/0 to 40/37 and test-all-infra-coverage-notice from
# 118/0 to 38/81. Those two numbers are NOT reproducible at HEAD: re-running that A/B now
# returns 77/0 and 118/0, because the stamp is exactly what makes an inherited count inert.
# tc_preamble stamps TC_SIBLING_RUN_COUNT_PID with its own $$ and does not export it, so an
# inherited count carries no stamp and cannot refuse.
if [[ "${TC_SIBLING_RUN_COUNT:-0}" -gt 0 && "${TC_SIBLING_RUN_COUNT_PID:-}" == "$$" \
      && "${SOLEUR_ALLOW_FULL_GATE:-}" != "1" ]]; then
  echo "ERROR: refusing a full-gate run — ${TC_SIBLING_RUN_COUNT} sibling full-gate run(s) already in flight (TEST_GROUP=$TEST_GROUP)." >&2
  echo "" >&2
  echo "The offending worktree(s) are listed in the contention preamble above, under" >&2
  echo "'[contention] siblings:'. Concurrent full-gate runs inflate each other's timings, and on a" >&2
  echo "contended host push suites past their own timeouts — turning a green suite red for a reason" >&2
  echo "unrelated to your diff, so the next reader investigates a phantom." >&2
  echo "" >&2
  echo "Run the suite covering your files instead:" >&2
  echo "    bash <path/to/the/suite.test.sh>" >&2
  echo "" >&2
  echo "Or wait for the sibling to finish. If you are the lead and this IS the sanctioned gate run," >&2
  echo "override explicitly:" >&2
  echo "    SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh" >&2
  # Same rc as the SOLEUR_SUBAGENT refusal: both mean REFUSED, nothing ran, nothing unresolved.
  # Deliberately NOT 3 — #7424 assigned 3 the meaning "a suite was terminated, coverage not
  # obtained", which is the opposite claim.
  exit 4
fi

# Advisory, self-announcing queue (#6789). Acquired INTERNALLY (not by a caller
# wrapping the script) so no invocation can forget it. It NEVER aborts — on
# timeout it proceeds with a named banner, so it cannot wedge a run. CI and the
# SOLEUR_DISABLE_SESSION_STATE kill switch are honoured inside tc_acquire.
# Declared BEFORE tc_acquire, i.e. OUTSIDE the region the two suites that drive this runner as
# their SUT replace wholesale. scripts/test-all-killed-classification.test.sh and its sibling
# splice their own fixture body between the lock-acquire call below and the epilogue, so a
# variable first assigned inside that window does not exist in their sandbox while the reader
# after it does — and under `set -u` that aborts the sandbox mid-run. Measured: it took AC2, AC3
# and AC8b red in a suite this branch does not otherwise touch. Exactly the shape of #7553's own
# regression, recorded in ADR-196 Decision 7.
#
# The anchors are NOT quoted verbatim here on purpose. Those fixtures locate the splice window by
# substring and require it to be UNIQUE; an earlier draft of this comment quoted the acquire call
# exactly, so the literal appeared twice and every sandbox build failed with
# "sandbox build failed: killed_only/none" — 40 passed, 51 failed, in a suite whose own code was
# untouched. A comment that names a token a parser keys on is part of that parser input
# (cq-assert-anchor-not-bare-token), which is this branch's own subject.
#
# Initialised to the NOT-MEASURED value, so a sandbox that drops the capture degrades to an
# honest "this run is not evidence" NOTE rather than either aborting or silently claiming a
# clean boundary.
_repo_guard_ok=0
_repo_state_before=""
_repo_last_suite="(none started)"
# Set by the end block once the boundary has been re-read and reported. Until then the EXIT trap
# below owns the verdict.
_repo_boundary_reported=0

# Before #7652 a run that ended before the end boundary emitted nothing — the runner armed no EXIT
# trap —
# and the escape most likely to end a run early is exactly the one that would suppress the
# verdict. So "no FATAL line" is indistinguishable from "clean", which is the reading that ships.
# This trap makes that absence speak for the signals bash can trap.
#
# STATED BECAUSE IT WOULD OTHERWISE BE OVER-READ: bash cannot trap SIGKILL, so an OOM-killed or
# `kill -9`'d run still emits nothing and still reads as silence. This closes the ordinary
# early-exit and timeout cases, not the whole class. Claiming otherwise here would be the same
# AP-021 defect the boundary exists to remove.
_repo_boundary_exit_note() {
  [[ "$_repo_boundary_reported" == 1 ]] && return 0
  [[ "$_repo_guard_ok" == 1 ]] || return 0
  echo "" >&2
  echo "NOTE: this run ended before the repo-write boundary was re-read, so it is NOT evidence" >&2
  echo "      that no suite wrote to your repository. The absence of a [FATAL] line above means" >&2
  echo "      the check did not run, not that it passed. Last suite started: ${_repo_last_suite}" >&2
}
trap '_repo_boundary_exit_note' EXIT

tc_acquire "test-all"

# AFTER tc_acquire, deliberately. A run that queued behind a sibling can wait up
# to TC_LOCK_TIMEOUT (3600 s) here, so a reading taken before the wait describes a
# machine state up to an hour stale and makes the start/end delta
# meaningless. Sampled at the moment this run actually begins doing work.
_emit_bytes_probe "__run_boundary_start__"

# --- REPO WRITE BOUNDARY (start) ---------------------------------------------------------
#
# This runner is READ-ONLY with respect to the repository it is run from. Nothing it registers
# may commit, check out, stage, or move a ref here. That is a property nobody was measuring,
# and on 2026-08-20 it was violated: a suite silenced its `git worktree add` failures and then
# ran `git add`/`git commit` in an unguarded subshell, so the commands executed in the CALLER
# CWD — the developer's live worktree. Four escapes across three sessions in under two hours;
# fixture commits landed on feature branches AND on local main, one worktree was checked out to
# main, and hours of uncommitted work were destroyed. Every suite reported green throughout.
#
# The site-level fix (a guard in that suite) is necessary and not sufficient: it protects the
# sites it covers, in the file it lives in. This is the BOUNDARY check, and it is deliberately
# characterised by the INVARIANT rather than by any fingerprint of that fixture. Detection by
# commit message, by the fixture's pinned committer date, or by author all key on incidental
# properties of today's escape and fail SILENTLY CLEAN against a future one that differs. "The
# gate wrote to the repo" does not.
#
# Sampled AFTER tc_acquire for the same reason the bytes probe is: a run that queued behind a
# sibling can wait here, and a reading taken before the wait describes a stale tree.
#
# Degrades OPEN. A missing or failing git must not wedge the gate — an unmeasurable boundary is
# reported at the end, never turned into a false RED.
if _repo_state_before="$(_repo_state)"; then
  _repo_guard_ok=1
fi

# Pre-suite bash/python tests — scripts shard.
if want_scripts; then
  run_suite "tests/hooks/incidents" bash tests/hooks/test_incidents.sh
  run_suite "tests/hooks/emissions" bash tests/hooks/test_hook_emissions.sh
  run_suite "tests/hooks/openhands-guardrails" bash tests/hooks/test_openhands_guardrails.sh
  run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids
  run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.rules.md
  # Hard-rule body-weakening gate (#6103, ADR-091): hermetic fixtures + a live
  # calibration (base HEAD → zero findings on the committed corpus). The real
  # merge-blocking gate is the standalone `rule-body-lint` ci.yml job with
  # --base <merge-base>; this live line is the calibration + orphan-suite guard.
  run_suite "tests/scripts/lint-rule-bodies" python3 -m unittest tests.scripts.test_lint_rule_bodies
  run_suite "scripts/lint-rule-bodies-live" python3 scripts/lint-rule-bodies.py --check --base HEAD
  # AGENTS B_ALWAYS rule-budget gate — CI-wired in #4599 (was lefthook pre-commit only).
  run_suite "scripts/lint-agents-rule-budget-live" python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md
  run_suite "scripts/lint-agents-rule-budget-unit" bash scripts/lint-agents-rule-budget.test.sh
  # The sync guard was lefthook-only, so a --no-verify commit bypassed it and
  # the byte-budget constant drifted across five artifacts unnoticed (#6461).
  # -live asserts the tree is in sync; -unit asserts the guard can still fail.
  run_suite "scripts/lint-agents-compound-sync-live" bash scripts/lint-agents-compound-sync.sh
  run_suite "scripts/lint-agents-compound-sync-unit" bash scripts/lint-agents-compound-sync.test.sh
  # Enforcement-tag parity — CI-wired in #7172 (was lefthook pre-commit only,
  # so main drifted to 13 unresolved tags with every local run green). -live
  # asserts the shipped corpus resolves AND that a non-zero number of tags was
  # actually scanned; -unit asserts the linter can still fail.
  run_suite "scripts/lint-agents-enforcement-tags-live" python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md
  run_suite "scripts/lint-agents-enforcement-tags-unit" bash scripts/lint-agents-enforcement-tags.test.sh
  run_suite "scripts/lint-infra-no-human-steps" bash scripts/lint-infra-no-human-steps.test.sh
  # Supabase Management API deprecation + host-pin assembly guard, and the
  # retained-log helper. Registered EXPLICITLY because neither directory is in
  # SUITE_GLOBS: `--print-suite-globs` lists `scripts/lib/*.test.sh` but not
  # `scripts/*.test.sh`, and `tests/scripts/` is absent entirely (its files are
  # also named `test-*.sh`, which a `*.test.sh` glob cannot match either way).
  # An unregistered suite there runs in zero runners and reads as passing (#7718).
  #
  # UNIT ONLY, AND THAT IS DELIBERATE. There is no `-live` line here, unlike the
  # sibling linters above. This shard runs inside the required `test` context, so
  # a `-live` run_suite would make the guard merge-blocking — which is exactly the
  # promotion this PR declined to make (see the guard header, ADR-197 and #7716).
  # Worth recording for whoever does promote it: this single line IS a promotion
  # path, and it bypasses the #6049 auto-fabrication trap that makes the
  # required-checks.txt route four coupled steps, because it adds no new
  # content-scoped gate NAME. The live run is advisory in `lint-bot-statuses`.
  run_suite "scripts/lint-supabase-deprecated-endpoints-unit" bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh
  run_suite "tests/scripts/supabase-logs-query" bash tests/scripts/test-supabase-logs-query.sh

  run_suite "scripts/lint-credential-path-literals" bash scripts/lint-credential-path-literals.test.sh
  # #7136: a `run:` step reading a variable declared only on ANOTHER step. Part B of this
  # suite EXECUTES the shipped release-failure email body under both deploy branches — the
  # alert path that had never once delivered, because `set -u` killed it before the curl.
  run_suite "scripts/lint-workflow-step-env-refs" bash scripts/lint-workflow-step-env-refs.test.sh
  run_suite "scripts/lint-workflow-step-env-refs-live" python3 scripts/lint-workflow-step-env-refs.py
  # ADR-170. Both halves are required: the unit suite proves the RULE is right (its fixtures are
  # the executable spec), the live scan proves the TREE is clean. Either alone is satisfiable by
  # a detector that has stopped detecting -- a broken linter and a clean repo emit identical
  # output, which is why the unit suite carries a verify-the-verifier case that re-introduces
  # the real defect into a tree copy.
  run_suite "scripts/lint-workflow-errexit-capture" bash scripts/lint-workflow-errexit-capture.test.sh
  run_suite "scripts/lint-workflow-errexit-capture-live" python3 scripts/lint-workflow-errexit-capture.py
  # ADR-191 (#7084). Same both-halves shape as the pair above, and for the same reason: after
  # this change the passing state of Guard 1 is "zero bun.lock found", which is byte-identical
  # to the output of a guard whose search is broken. The unit suites carry the anti-vacuity
  # floors and the must-PASS rows; the live scans prove the tree.
  #
  # Two guards rather than one: each one's floor has to be obviously matched to its own
  # enumeration (Guard 1 anchors on package-lock.json directories, Guard 2 on workflow files
  # AND matched install steps), and a single script hosting both would fail that name test for
  # half its job.
  run_suite "scripts/lint-dual-lockfile" bash scripts/lint-dual-lockfile.test.sh
  run_suite "scripts/lint-dual-lockfile-live" bash scripts/lint-dual-lockfile.sh
  run_suite "scripts/lint-workflow-install-sites" bash scripts/lint-workflow-install-sites.test.sh
  run_suite "scripts/lint-workflow-install-sites-live" bash scripts/lint-workflow-install-sites.sh
  # The wrapper the plan's `discoverability_test.command` contracts on. Registered
  # separately from the two guards it calls because what it can get wrong is its own:
  # reporting success while a guard beneath it reddened. preflight Check 10 matches on its
  # marker, so an unconditional marker would report a healthy invariant against any tree.
  run_suite "scripts/verify-lockfile-guards" bash scripts/verify-lockfile-guards.test.sh
  # The drain itself (#7084). Asserted from the committed lockfiles rather than from the
  # Dependabot API: this is deterministic, available at merge time, and needs no token the
  # workflow does not have. The alert COUNT is a lagging mirror of this same fact.
  run_suite "scripts/assert-dependabot-drain-live" python3 scripts/assert-dependabot-drain.py
  # ...and the guard's own guard (#1327). The live run above proves the tree is clean; it
  # cannot prove the assertion still has teeth. Both anti-vacuity floors there count ROWS,
  # so every CVE threshold in the table could be set to "0.0.0" and the live run still
  # exited 0. This suite mutates a sandbox copy and requires each mutation to RED with the
  # message that names its cause.
  run_suite "scripts/assert-dependabot-drain-unit" bash scripts/assert-dependabot-drain.test.sh
  # SIBLING gate (#7332): the same "captured a status nobody decided about" class, but in shell
  # SCRIPTS under `set -e` rather than Actions `run:` blocks. Separate anchor, separate
  # calibration -- the naive "a command-substitution assignment is a finding" rule found only
  # 2 of 17 sites for workflows and is the CORRECT rule here, which is why widening the sibling
  # would have meant each gate covering the other's blind spot badly.
  #
  # The live run carries a BASELINE of 216 pre-existing findings (206 abort-risk, 10
  # double-emit). The gate blocks NEW occurrences only; the baseline may shrink and must never
  # grow. Burn-down is tracked in the learning that ships with this gate. Registering it
  # baseline-free would have meant either a permanently red suite or a silently narrowed rule.
  run_suite "scripts/lint-shell-capture-exit" bash scripts/lint-shell-capture-exit.test.sh
  run_suite "scripts/lint-shell-capture-exit-live" python3 scripts/lint-shell-capture-exit.py \
    --baseline scripts/lint-shell-capture-exit.baseline.txt
  # #7471, amended #7493: the published distribution manifest in jikig-ai/soleur-marketplace
  # is the only artifact in the delivery path no CI check here can reach DIRECTLY. Its SOURCE
  # is now reachable (Terraform owns the content; marketplace-manifest-guard validates it
  # pre-merge, and that repo now carries a PR-required ruleset), so the "no CI, no review, no
  # CODEOWNERS" framing this comment used to carry no longer holds.
  # scheduled-marketplace-drift.yml remains the only check on what is actually SERVED;
  # this suite is that guard's guard. Registered explicitly because
  # scripts/*.test.sh is NOT auto-globbed here — an unregistered gate never runs.
  run_suite "scripts/marketplace-drift-check" bash scripts/marketplace-drift-check.test.sh
  # #7489: the legacy `soleur@soleur` marketplace entry carries client-side
  # `autoUpdate: true`, which cannot be revoked remotely — so the tracker's
  # closing condition is a claim about MACHINES, and the probe is how that claim
  # is made checkable rather than asserted. Guard 2's battery; registered
  # explicitly for the same reason as the suite above.
  run_suite "scripts/plugin-legacy-resolver-probe" bash scripts/plugin-legacy-resolver-probe.test.sh
  # #7490: the manifest suite above asserts the published POINTER is well-formed.
  # This one guards the assertion that following it actually DELIVERS the plugin --
  # complete, byte-correct at the delivered commit, and current. #7471 shipped 64
  # skill directories where 96 were expected with every metadata field reading
  # correct, which is the defect a manifest check structurally cannot see.
  run_suite "scripts/plugin-delivery-canary" bash scripts/plugin-delivery-canary.test.sh
  # Meta-guard over the two suites above: both end in an anti-vacuity floor, and
  # both originally enforced that floor by calling `fail` — the function whose
  # failure the floor exists to survive. This pins the fix by mutation (stub
  # `fail`, assert the floor still exits non-zero) rather than by inspection.
  # Registered explicitly: it lives under scripts/, which is not auto-globbed.
  run_suite "scripts/guard-vacuity-floor" bash scripts/guard-vacuity-floor.test.sh
  # Guard 4 (#7493): validates the manifest SOURCE that Terraform publishes, as opposed to the
  # sibling above which validates the PUBLISHED artifact. Neither subsumes the other — once the
  # drift workflow dispatches a reconcile, a bad SOURCE is republished daily while a
  # published-vs-source byte-diff reports in-sync, so the merge boundary is the only place that
  # loop can be broken.
  run_suite "scripts/marketplace-manifest-validate" bash scripts/marketplace-manifest-validate.test.sh
  # Guard 1 (#7493): the marketplace ruleset probe, driven against recorded ruleset-detail
  # fixtures. Its live mutations (flip enforcement, add a 4th bypass actor) cannot be performed
  # in CI, so fixtures are the only honest way to prove the probe reddens.
  run_suite "scripts/verify-marketplace-ruleset" bash scripts/verify-marketplace-ruleset.test.sh
  # ADR-140: Layer A encryption-posture detector (the mechanical resolver behind
  # the "encryption at rest + in transit" design-time gate). TS-1..8,15..17 +
  # the MB-1..MB-12 mutation battery (fixture-isolated, not suite-pass-count).
  run_suite "scripts/lint-encryption-posture" bash scripts/lint-encryption-posture.test.sh
  # Guard Contract completeness gate (plan/SKILL.md §2.12, deepen-plan §4.11).
  # TS-1..TS-10 fixtures + the MB-1..MB-4 mutation battery. The -live line runs
  # the sweep over the real plans/ tree so a non-compliant Guard Contract landing
  # in a plan reds CI, not just the fixtures.
  run_suite "scripts/lint-guard-contract" bash scripts/lint-guard-contract.test.sh
  run_suite "scripts/lint-guard-contract-live" python3 scripts/lint-guard-contract.py
  # Window-derived closure assertions must DECLARE their assembly (per helper).
  # Enforces a declaration, not semantic completeness — no static checker can
  # prove a regex window equals its assembly. TS-1..TS-11 + MB-1..MB-2.
  run_suite "scripts/lint-window-closure-assertion" bash scripts/lint-window-closure-assertion.test.sh
  run_suite "scripts/lint-window-closure-assertion-live" python3 scripts/lint-window-closure-assertion.py \
    --allowlist scripts/lint-window-closure-assertion.allowlist.txt
  # rename-guard: allowlist->allowlist renames (the archive-kb shape) are exempt;
  # outside->allowlist still fails. TS-1..TS-6 + MB-1..MB-2.
  run_suite "scripts/rename-guard" bash scripts/rename-guard.test.sh
  run_suite "scripts/extract-api-spend" bash scripts/extract-api-spend.test.sh
  run_suite "scripts/domain-model-drift" bash scripts/domain-model-drift.test.sh
  # #6602: exit-code harness for the expenses verify_by expiry gate. Registered
  # explicitly — this runner enumerates by hand and scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that never gates
  # (the #5417 class). The gate authorizes a fail-loud financial-accuracy alarm,
  # so its arms returning the right exit codes is load-bearing coverage.
  run_suite "scripts/expenses-verify-by-check" bash scripts/expenses-verify-by-check.test.sh
  run_suite "scripts/sentry-issue" bash scripts/sentry-issue.test.sh
  run_suite "scripts/sentry-issue-discover" bash scripts/sentry-issue-discover.test.sh
  run_suite "scripts/content-publisher" bash scripts/test-content-publisher.sh
  # Registered by #6734. scripts/*.test.sh is NOT covered by any glob here (only
  # scripts/lib/*.test.sh is), so each one must be named explicitly. The first four below
  # had silently never run in any CI job; scripts/lint-orphan-test-suites.sh now fails
  # when a scripts/*.test.sh is missing from this list.
  # NOTE: "scripts/content-publisher" above is the LEGACY test-content-publisher.sh suite;
  # the residue harness below is a different file (content-publisher.test.sh). Both run.
  run_suite "scripts/content-publisher-residue" bash scripts/content-publisher.test.sh
  run_suite "scripts/skill-freshness-aggregate" bash scripts/skill-freshness-aggregate.test.sh
  run_suite "scripts/compound-promote" bash scripts/compound-promote.test.sh
  run_suite "scripts/lint-trap-tempfile-ownership" bash scripts/lint-trap-tempfile-ownership.test.sh
  # The Cloudflare token-drift detector's Access-service-token arm. Registered explicitly
  # for the same reason as its neighbours — scripts/*.test.sh is NOT auto-globbed — and
  # the omission would be especially apt here: the defect this suite pins is a detector
  # that reported a clean bill of health for a family it never enumerated, and an
  # unregistered suite is the same failure one level up.
  run_suite "scripts/check-cloudflare-token-drift" bash scripts/check-cloudflare-token-drift.test.sh
  # #6789: arms for the contention instrumentation + advisory queue that this
  # runner itself now uses. Registered explicitly — scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that gates
  # nothing (the #5417 class). lint-orphan-test-suites.sh enforces this line.
  run_suite "scripts/test-contention" bash scripts/test-contention.test.sh
  # #6789: arms for the tmpfs scratch reaper. It DELETES files, so every gate
  # (age/size/ownership/liveness/protected-path) is asserted in both directions.
  run_suite "scripts/tmpfs-guard" bash scripts/tmpfs-guard.test.sh
  # #7537: the orphaned-PROCESS reaper. It SIGNALS processes, so every gate
  # (own-uid, unlinked cwd, unlinked fd/255, self-exclusion, mount/pid
  # namespace, age floor) is asserted in both directions here. Registered
  # explicitly for the same reason as its neighbours: scripts/*.test.sh is NOT
  # in the auto-glob below, so an unregistered suite is an ORPHAN that gates
  # nothing (the #5417 class). lint-orphan-test-suites.sh enforces this line.
  run_suite "scripts/orphan-process-reaper" bash scripts/orphan-process-reaper.test.sh
  # The mutation battery for the same detector. Both lines are needed for the
  # reason the legal-corpus pair below states: the behavioural suite proves the
  # detector can detect a planted orphan, and the battery is the only thing that
  # proves each of its GUARDS can be driven red. The preceding PR in this area
  # shipped nine guards that could not fail; measured here at ~90s for 36 rows.
  #
  # NOT registered as a live `report` run: that would be a second /proc walk per
  # launch, and a suite whose verdict depended on what else happened to be
  # running is cq-ac-must-not-depend-on-concurrent-sessions reproduced inside
  # the gate.
  run_suite "scripts/orphan-process-reaper-mutations" bash scripts/orphan-process-reaper-mutation.test.sh
  # The fstab ceiling applier. Every case drives a FIXTURE fstab through the
  # RAISE_TMPFS_FSTAB seam — the real /etc/fstab is never read or written, because a
  # test that touched it could leave the machine unbootable. Registered explicitly for
  # the same reason as its neighbours: scripts/*.test.sh is NOT auto-globbed, so an
  # unregistered suite is an ORPHAN that gates nothing.
  run_suite "scripts/raise-tmp-tmpfs-ceiling" bash scripts/raise-tmp-tmpfs-ceiling.test.sh
  # ADR-151 / #7012: arms for the rules-loader discoverability probe. The
  # NEGATIVE arms carry the weight — a probe that prints OK unconditionally is
  # indistinguishable from a working one. T6 additionally pins that preflight
  # Check 10 can still EXECUTE the plan's command, so a later "simplify it back
  # to a pipeline" edit fails here instead of silently un-verifying the probe.
  # Registered explicitly: scripts/*.test.sh is NOT auto-globbed by this runner.
  run_suite "scripts/rules-loader-stamp-probe" bash scripts/rules-loader-stamp-probe.test.sh
  run_suite "scripts/lint-orphan-test-suites" bash scripts/lint-orphan-test-suites.sh
  # Guard 1 (#7402). The LIVE line above points the linter at this working tree; this one is
  # its mutation battery, which builds a synthetic git repo and proves each of the eleven rows
  # reddens. Both are needed for the same reason the legal-corpus pair below states: the unit
  # suite proves the guard can detect a planted defect, the live line is the only thing that
  # ever points it at the real repo.
  #
  # NOT added to the linter's own REQUIRED_RUNNERS list: that array holds RUNNERS (files that
  # dispatch other suites), and a `.test.sh` is not one. The `scripts/*.test.sh` walk — now the
  # whole-repo walk — is what keeps THIS line honest.
  run_suite "scripts/lint-orphan-test-suites-mutations" bash scripts/lint-orphan-test-suites.test.sh
  # #7387 legal-corpus write-time gates. Each gate registers its unit suite AND a LIVE run
  # against the working tree: the unit suite proves the gate detects a planted defect in a
  # sandbox, the live line is the only thing that ever points it at the real corpus. The unit
  # lines are auto-enforced by lint-orphan-test-suites.sh; the live lines are enforced via its
  # REQUIRED_RUNNERS.
  #
  # check-tc-document-sha.sh is deliberately NOT registered here, and an earlier revision of
  # this block that did register it was wrong twice over. (a) It reintroduces #5780: that
  # script's TC_VERSION-bump bypass needs the step-scoped GITHUB_BASE_REF /
  # MERGE_GROUP_BASE_SHA that ci.yml gives the `tc-document-sha-guard` job and NOT this one
  # (`test-scripts` passes only GITHUB_TOKEN), so on the merge queue a legitimate stale-SHA +
  # TC_VERSION-bump PR would go green on its own required context and red here. (b) Its stated
  # rationale -- catching a normaliser weakening that "silently re-bases every drift
  # measurement" -- was measured false: weakening collapse() leaves that script green, because
  # it only detects ASYMMETRIC damage between the two normalisers. The engine pin in
  # scripts/lib/legal-normalise.test.sh is the detector for that, and it is fixture-anchored so
  # it cannot red on a legal edit.
  run_suite "scripts/lint-legal-scope-block-placement-unit" bash scripts/lint-legal-scope-block-placement.test.sh
  run_suite "scripts/lint-legal-scope-block-placement-live" bash scripts/lint-legal-scope-block-placement.sh
  run_suite "scripts/lint-legal-mirror-drift-baseline-unit" bash scripts/lint-legal-mirror-drift-baseline.test.sh
  run_suite "scripts/lint-legal-mirror-drift-baseline-live" bash scripts/lint-legal-mirror-drift-baseline.sh
  run_suite "scripts/tenant-dpa-register-guard-unit" bash scripts/tenant-dpa-register-guard.test.sh
  run_suite "scripts/tenant-dpa-register-guard-live" bash scripts/tenant-dpa-register-guard.sh count-signed
  # DECIDABILITY, not emptiness. `assert-empty` encoded a BUSINESS fact ("Jikigai has zero
  # tenants") as a passing test, so onboarding tenant #1 -- the day the guard finally matters --
  # would red the whole suite, and the under-pressure fix is to delete this line. `count-signed`
  # exits 0 on any readable register and 2 on one it cannot parse, which is the code property.
  run_suite "scripts/cron-artifact-age" bash scripts/cron-artifact-age.test.sh
  run_suite "scripts/watch-live-verify-pass" bash scripts/watch-live-verify-pass.test.sh
  run_suite "scripts/review-reminder-liveness" bash scripts/review-reminder-liveness.test.sh
  run_suite "scripts/zot-restart-loop-alarm" bash scripts/zot-restart-loop-alarm.test.sh
  run_suite "scripts/followthrough-exec-bit" bash scripts/followthrough-exec-bit.test.sh
  # #6757: enforce the ${VAR:?}/${VAR?} ban in follow-through probes. Two explicit run_suite
  # lines because scripts/*.test.sh is NOT auto-globbed here — an unregistered suite is an
  # ORPHAN that gates nothing (#5417/#6734 class; lint-orphan-test-suites.sh FAILs on it).
  # -live runs the guard over the REAL tree (the actual gate); the .test.sh is the mutation
  # proof (both RED directions) that the guard can catch the banned form.
  run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh
  run_suite "scripts/followthrough-varq-ban" bash scripts/lint-followthrough-varq-ban.test.sh
  # #7506: the callback-URL closure guard EXECUTES its shipped workflow step body under
  # `bash -e` (the shell Actions uses for a `run:` block with no `shell:` key). Registered
  # explicitly for the same reason as the two lines above — scripts/*.test.sh is not globbed,
  # and this suite existing-but-unregistered would gate exactly nothing, which is the failure
  # mode the guard it protects had in production.
  run_suite "scripts/follow-through-closure-guard" bash scripts/follow-through-closure-guard.test.sh
  # Was an ORPHAN until #6698 — the suite existed and passed locally but was
  # registered in no runner, so it gated nothing (exactly the class the comment
  # above warns about). It covers the sweeper's path-traversal/symlink rejection
  # AND the closed-set reopen path.
  run_suite "scripts/sweep-followthroughs" bash scripts/sweep-followthroughs.test.sh
  # #6462: exit-code harness for the zot soak's decision arms. Registered explicitly because
  # this runner enumerates suites by hand — an unregistered .test.sh is an ORPHAN that never
  # gates (the #5417 class). The soak authorizes an irreversible PAT revoke, so its arms
  # returning the right codes is not optional coverage.
  run_suite "scripts/zot-soak-6122-arms" bash scripts/followthroughs/zot-soak-6122.test.sh
  # #6616: exit-code harness for the host_name-mislabel follow-through's decision tree (identity,
  # liveness, TRANSIENT-not-PASS). Registered explicitly (orphan-suite class above) — its exit code
  # gates whether the sweeper auto-closes #6616, so a vacuous PASS regression must redden CI.
  run_suite "scripts/hostname-mislabel-web1-6616" bash scripts/followthroughs/hostname-mislabel-web1-6616.test.sh
  # #6475 (D-6): exit-code harness for the ci-deploy Sentry-POST-failure soak probe. Registered
  # explicitly (orphan-suite class above) — its exit code gates whether the sweeper auto-closes
  # #6475, and the probe's whole purpose is to be the fail-loud alarm, so a vacuous PASS (or a
  # false FAIL that pages a green codebase) must redden CI here.
  run_suite "scripts/ci-deploy-sentry-post-fail-6475" bash scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh
  # #6297: exit-code harness for the Anthropic admin-key follow-through. Registered explicitly
  # (orphan-suite class above). Its load-bearing arm is CONTAMINATION: GitHub webhook payloads
  # ship into the same Better Stack source from the same app container, so a substring-matching
  # probe could PASS on an echo of the PR/issue body that merely QUOTES the marker and auto-close
  # #6297 while the key is still unminted. The suite mutation-proves that guard, so a regression
  # to structural matching must redden CI rather than silently false-close a tracker.
  run_suite "scripts/anthropic-admin-key-6297" bash scripts/followthroughs/anthropic-admin-key-6297.test.sh
  # #7220: exit-code harness for the ACTIVATION soak. Registered explicitly (orphan-suite class
  # above). Review found this probe returning exit 0 — which auto-closes the tracker — on a host
  # where reconciliation was BROKEN: it counted `action=failed reason=sudo_denied` rows, and the
  # sibling `SOLEUR_INFRA_CONFIG_RESTART_STDERR:` diagnostic rows, toward its PASS condition. So
  # the probe would have closed the issue on the evidence of its own recurrence. The suite pins
  # the action-vocabulary split and the freshness guard that a PASS now requires.
  run_suite "scripts/infra-config-activation-7220" bash scripts/followthroughs/infra-config-activation-7220.test.sh
  # Post-recut registry fill rate (#7341). Same failure family as the probe directly above, which
  # is why it is registered next to it: five separate fail-open defects, every one of which
  # produced a GREEN verdict. Two are worth pinning here. A 72h window straddling the recut fitted
  # one line through the old 100%-full volume and the new empty one, reporting a WIPE as a trend
  # (`PASS slope=-58.48pp/day`). And `boot_id=([0-9a-f-]+)` matched only a PREFIX of the token, so
  # two distinct boots compared equal and the scoping the whole check rests on was silently off.
  # Registration is explicit in this file, so an unregistered harness runs only when someone
  # invokes it by hand — which for a probe that auto-closes a tracker means the anti-vacuity floor
  # is decoration.
  run_suite "scripts/zot-fill-rate-7341" bash scripts/followthroughs/zot-fill-rate-7341.test.sh
  # #7761 cutover-flip rollout probe. Registered because lint-orphan-test-suites.sh caught it
  # unregistered: every assertion in it gated nothing, which for a probe that authorizes
  # closing a P1 security issue after a production host replace is the permanent silent no-op
  # its own header says it exists to retire. The suite pins the two properties that decide
  # whether the probe can be trusted: its query stub APPLIES the --grep the probe passes (a
  # stub that ignored it certified a probe whose grep matched none of the rows it counts), and
  # a post-boundary marker must carry the guard stamp only the post-fix script emits (without
  # it every observable is byte-identical to the pre-fix script, so a replace that delivered
  # nothing would report success).
  run_suite "scripts/inngest-cutover-flip-rollout-7761" bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.test.sh
  # CPX22 invoice reconciliation (#7437). An operator-confirmed probe reads a production ledger
  # verdict out of free text a human typed, so the suite pins the two properties that decide
  # whether it can be trusted: the verdict is anchored at line start (an unanchored grep closes
  # the issue on a comment ASKING about it), and FAIL is evaluated before PASS (checking PASS
  # first let a retraction lose to the string it was retracting — the harness failed on the
  # original order). It also pins the accept-shape against the peers' `$`-anchored form, which
  # would reject the figure this issue requires the operator to state.
  run_suite "scripts/cpx22-invoice-reconcile-7431" bash scripts/followthroughs/cpx22-invoice-reconcile-7431.test.sh
  # Dedicated inngest host zot-primary boot readback (#7462/#7228). Two properties decide whether
  # this probe can be trusted to auto-close two P1 trackers, and both are pinned: PASS requires
  # `bootstrap-done` and not merely `inngest_zot`, because the pull half succeeding while nothing
  # installs IS the #7228 incident; and every count is taken from the DECODED `.stage` field, so a
  # row whose message merely echoes a stage name cannot supply it. The suite also pins the jq
  # stream shape — without `-R` + `fromjson?` one malformed warehouse line aborts the whole parse
  # and a clean PASS window reports as `channel_dark`, i.e. "the host never booted".
  run_suite "scripts/inngest-zot-boot-7462" bash scripts/followthroughs/inngest-zot-boot-7462.test.sh
  # Operator authorization for enrolling soleur-inngest as a zot client (#6500). This probe closes
  # the issue that GATES retiring GHCR push/egress, so the suite pins the two properties the #7437
  # sibling shipped wrong: the verdict is anchored at line start (an unanchored grep authorizes on
  # a comment ASKING about the criterion), and FAIL is evaluated before PASS (checking PASS first
  # lets a retraction lose to the string it retracts). Deliberately reads a HUMAN verdict rather
  # than telemetry — a green boot marker must not authorize a supply-chain retirement.
  run_suite "scripts/inngest-zot-client-authz-6500" bash scripts/followthroughs/inngest-zot-client-authz-6500.test.sh
  # Inngest external-watchdog decision helpers (#6374/#6384/#6407). Registered here in #6407 —
  # these sourceable classifiers/gates were previously orphan suites (run only when invoked
  # manually), so a regression to the watchdog decision logic would have shipped with green CI.
  run_suite "scripts/inngest-liveness-classify" bash scripts/inngest-liveness-classify.test.sh
  run_suite "scripts/inngest-restart-age-gate" bash scripts/inngest-restart-age-gate.test.sh
  run_suite "scripts/inngest-restart-poll-classify" bash scripts/inngest-restart-poll-classify.test.sh
  run_suite "scripts/tunnel-connector-census" bash scripts/tunnel-connector-census.test.sh
  # #6512 Fix 2a: the seccomp-unenforced actionable-alert emitter (sourced by
  # apply-deploy-pipeline-fix.yml). Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/seccomp-unenforced-alert" bash scripts/seccomp-unenforced-alert.test.sh
  run_suite "scripts/infra-config-red-alert" bash scripts/infra-config-red-alert.test.sh
  # Production version-drift alerter (#7091), sourced by scheduled-prod-version-drift.yml.
  # Explicit run_suite — scripts/*.test.sh is not auto-globbed here, and an unregistered
  # suite is the #5417 class: green CI over zero coverage.
  run_suite "scripts/prod-version-drift-check" bash scripts/prod-version-drift-check.test.sh
  # zot-mirror failure diagnosis (#7242 / ADR-166), sourced by reusable-release.yml AND by
  # .github/actions/cf-tunnel-registry-bridge/action.yml. Explicit run_suite — scripts/*.test.sh
  # is not auto-globbed here. Registration is also what gives this class BLOCKING enforcement:
  # `test-scripts` feeds the aggregate `test` job (ci.yml), which IS in the CI Required ruleset,
  # whereas the `lint-bot-statuses` job the other repo linters live in is advisory by design.
  run_suite "scripts/zot-mirror-diagnosis" bash scripts/zot-mirror-diagnosis.test.sh
  # APP_DOMAIN_BASE derivation, consumed by both D10 arms of registry-luks-recut and by
  # cf-tunnel-registry-bridge. It replaced a Doppler read of a secret that exists in no config
  # of the soleur project. Explicit run_suite — scripts/*.test.sh is not auto-globbed here.
  run_suite "scripts/derive-app-domain-base" bash scripts/derive-app-domain-base.test.sh
  # #7242: an alarm step that cannot run after an earlier failure cannot report the FIRE it
  # exists to report. Static gate over both alarm workflows — the condition is evaluated by
  # GitHub, so the YAML is the only artifact there is to test.
  run_suite "scripts/alarm-issue-filing-guard" bash scripts/alarm-issue-filing-guard.test.sh
  # A workflow that writes to the issue tracker must hold `issues: write`. Registered beside the
  # alarm guard because they are the same class one layer apart: that one checks an alarm step CAN
  # RUN, this one checks it CAN WRITE. The dispatcher's refusal artifact satisfied the first and
  # failed the second, silently, behind `|| true`.
  run_suite "scripts/lint-workflow-issue-write-scope" bash scripts/lint-workflow-issue-write-scope.test.sh
  # THE -live ARM IS THE GATE. The suite above only proves the lint BEHAVES correctly against
  # synthesized fixtures in $TMP; it never points the lint at `.github/workflows`, so without this
  # line a workflow carrying the exact shipped defect merges green and the lint catches nothing.
  # Every peer workflow lint is registered as this same pair (see lint-workflow-step-env-refs and
  # lint-workflow-errexit-capture above) — this one was registered once, which made it decoration.
  run_suite "scripts/lint-workflow-issue-write-scope-live" python3 scripts/lint-workflow-issue-write-scope.py
  # #7242 / ADR-166: no operator-facing CI message may name a cause the job did not measure.
  # Registered HERE rather than in the lint-bot-statuses job on purpose -- that job is
  # advisory (absent from required-checks.txt and the ruleset), and this defect has already
  # survived two non-blocking corrections. The suite invokes the lint, so a regression above
  # the committed .highwater reds the required `test` context.
  run_suite "scripts/lint-diagnosis-claims" bash scripts/lint-diagnosis-claims.test.sh
  # Dogfood Grok measure/bootstrap (#6545/#6546). Explicit run_suite — scripts/dogfood/
  # is not in the auto-glob; orphan suites are the #5417 class (green CI, zero coverage).
  run_suite "scripts/dogfood/grok-gpu-bootstrap" bash scripts/dogfood/grok-gpu-bootstrap.test.sh
  run_suite "scripts/dogfood/grok-measure" bash scripts/dogfood/grok-measure.test.sh
  # Stock preflight gate (#6453). Registered HERE because nothing auto-discovers
  # tests/scripts/ — the bash *.test.sh glob further down does NOT include it, and
  # infra-validation.yml only lists apps/web-platform/infra/*.test.sh. Without this line
  # the gate that stands between a -replace and a stranded fleet ships with zero coverage.
  run_suite "tests/scripts/stock-preflight-gate" bash tests/scripts/test-stock-preflight-gate.sh

  # (#6977) The git-data birth route's gates. NOTHING else runs these:
  # lint-orphan-test-suites.sh's producer is `git ls-files '*.test.sh'`, which the
  # `test-<name>.sh` convention used under tests/scripts/ does not match (#7402 widened that
  # walk from scripts/*.test.sh to the whole repo, but the SUFFIX convention is the producer's
  # scope and tests/scripts/ is deliberately outside it), and
  # apps/web-platform/infra/run-registered-suites.sh DERIVES its list from
  # infra-validation.yml's `run: bash apps/web-platform/infra/<name>.test.sh` steps, so a
  # tests/scripts/ suite is structurally invisible to both. These three run_suite lines
  # are the ONLY registration — an unregistered gate suite is silent AND green, which is
  # the exact shape that let a fail-open rung ship in #3366.
  run_suite "tests/scripts/plan-gate-preamble" bash tests/scripts/test-plan-gate-preamble.sh
  run_suite "tests/scripts/git-data-host-birth-gate" bash tests/scripts/test-git-data-host-birth-gate.sh
  run_suite "tests/scripts/git-data-birth-readiness-gate" bash tests/scripts/test-git-data-birth-readiness-gate.sh
  # (#7025) The rung-2 evidence-capture decision function. Registered HERE for the same
  # reason as every line around it: nothing auto-discovers tests/scripts/. This script is
  # what decides whether the file that RELEASES the birth interlock gets written, so an
  # unregistered — and therefore silent AND green — suite would leave that decision unproven
  # on every PR.
  run_suite "tests/scripts/git-data-rung2-evidence-capture" bash tests/scripts/test-git-data-rung2-evidence-capture.sh
  # Supabase advisor RLS gate (#3366). Registered HERE for the same reason as the
  # line above: nothing auto-discovers tests/scripts/. This is the harness that
  # proves the gate cannot silently pass (a 401 must not parse to a clean 0);
  # without this line that proof runs nowhere and the gate's entire value claim
  # is unverified on every PR — the exact defect the gate exists to catch.
  run_suite "tests/scripts/supabase-advisor-scan" bash tests/scripts/test-supabase-advisor-scan.sh
  # EU residency allow-set parity (#6453 review). {nbg1,fsn1,hel1} is replicated across three
  # terraform validations + the stock gate's default; nothing pinned them together, and the
  # gate's own suite overrides the value to stay hermetic, so the shipped default was asserted
  # nowhere. Drift makes the gate advise a location terraform rejects.
  run_suite "tests/scripts/eu-location-allowset-parity" bash tests/scripts/test-eu-location-allowset-parity.sh
  # betterstack-query.sh hot+archive UNION (#6288). remote() alone is the ~40-minute hot
  # window, so a hot-only query answers `--since 24h` with 40 minutes — no error, just a
  # short answer. That silently starved every soak gate built on it (#6288's needs 2h of
  # span and could never PASS). Hermetic: stubs curl, asserts SQL shape, never live rows.
  run_suite "tests/scripts/betterstack-query-archive" bash tests/scripts/test-betterstack-query-archive.sh
  # #7569 — the ingest-refusal discriminator and its cause-annotation probe. tests/scripts/ is
  # NOT auto-globbed by this runner, so an unregistered suite gates nothing, silently and
  # greenly. Both are registered here in the same commit that adds them.
  run_suite "tests/scripts/betterstack-absence-classifier" bash tests/scripts/test-betterstack-absence-classifier.sh
  run_suite "tests/scripts/betterstack-ingest-probe" bash tests/scripts/test-betterstack-ingest-probe.sh
  run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
  run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
  run_suite "scripts/rule-metrics-aggregate" bash scripts/rule-metrics-aggregate.test.sh
  run_suite "tests/scripts/weakness-miner" bash tests/scripts/test-weakness-miner.sh
  run_suite "tests/scripts/audit-ruleset-bypass" bash tests/scripts/test-audit-ruleset-bypass.sh
  run_suite "tests/scripts/audit-bot-codeql-coverage" bash tests/scripts/test-audit-bot-codeql-coverage.sh
  run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
  run_suite "tests/commands/sync-domain-model" bash tests/commands/test-sync-domain-model.sh
  # tests/commands/ is registered by these explicit lines ONLY — there is no glob here, and
  # lint-orphan-test-suites.sh's whole-repo walk is keyed on the `*.test.sh` SUFFIX, which the
  # `test-<name>.sh` convention in this directory does not carry. That linter covers the
  # directory through a SEPARATE dedicated loop (#7442) rather than through its main walk; a
  # new suite added below without a run_suite line silently never gates.
  run_suite "tests/commands/sync-producer-reachability" bash tests/commands/test-sync-producer-reachability.sh
  run_suite "tests/scripts/kb-drift-walker" bash tests/scripts/test-kb-drift-walker.sh
  # Destroy-guard counters (apply-* workflow trio). Pre-existing gap from
  # #4420 closed in #4419 — without these in CI, a PR that mutates a filter
  # to gut its clauses passes review only through CODEOWNERS approval.
  run_suite "tests/scripts/destroy-guard-counter-github" bash tests/scripts/test-destroy-guard-counter.sh
  run_suite "tests/scripts/destroy-guard-counter-sentry" bash tests/scripts/test-destroy-guard-counter-sentry.sh
  run_suite "tests/scripts/destroy-guard-counter-web-platform" bash tests/scripts/test-destroy-guard-counter-web-platform.sh
  # Pre-apply entrypoint gate (#6767 / ADR-136). Registered HERE for the same
  # reason as the destroy-guard trio above: nothing auto-discovers tests/scripts/
  # (the bash *.test.sh glob further down covers only scripts/lib/*.test.sh etc.,
  # NOT tests/scripts/test-*.sh), so an unregistered suite is an ORPHAN that gates
  # nothing. This suite proves the fail-closed gate that stands between a
  # whole-list ruleset create and a clobbered live dashboard entrypoint.
  run_suite "tests/scripts/preapply-entrypoint-gate" bash tests/scripts/test-preapply-entrypoint-gate.sh
  # host image/apply coherence preflight (AC10b) — drives the standalone preflight
  # via its test seams (no docker/network/prod write). Registered here alongside
  # the destroy-guard trio: it is the host-agnostic coherence verifier the
  # host_creates HALT's pinned-image chain names (#6575).
  run_suite "tests/scripts/host-image-coherence-preflight" bash tests/scripts/test-host-image-coherence-preflight.sh
  # #6197: inngest-host-replace scoped-recreate destroy-guard (same sourced-gate shape the
  # web2-recreate gate used before #6575 deleted it).
  run_suite "tests/scripts/inngest-host-replace-gate" bash tests/scripts/test-inngest-host-replace-gate.sh
  # registry-host-replace scoped-recreate destroy-guard (5-target; preserves the zot store volume).
  run_suite "tests/scripts/registry-host-replace-gate" bash tests/scripts/test-registry-host-replace-gate.sh
  # #7542: vector-redeliver scoped-delivery gate. Unlike the -replace arms above it permits a bare
  # ["create"] as well as ["delete","create"] (a delivery, not a replace), and its no-op outcome is
  # SUCCESS rather than a refusal — so "nothing to redeliver" cannot be reported for a lone delete.
  run_suite "tests/scripts/vector-redeliver-gate" bash tests/scripts/test-vector-redeliver-gate.sh
  # #7542 WIRING (not logic), and the same split as the D10 pair below. The suite above proves the
  # gate DECIDES correctly; it cannot prove the vector_redeliver job calls it, calls it on the
  # artifact the apply consumes, or is gated on its verdict at all. It also pins the one property
  # no unit test can see: the CF Tunnel bridge must precede the plan, because the plan bakes
  # TF_VAR_ci_ssh_private_key and `apply <savedplan>` accepts no variable input. Registered
  # explicitly — nothing auto-discovers tests/scripts/ (#3366).
  run_suite "tests/scripts/vector-redeliver-wiring" bash tests/scripts/test-vector-redeliver-wiring.sh
  # registry-region-migrate destroy-guard (#6288; permits the registry's OWN store-volume replace across regions, forbids all out-of-scope destroys).
  run_suite "tests/scripts/registry-region-migrate-gate" bash tests/scripts/test-registry-region-migrate-gate.sh
  # registry-luks-recut destroy-guard (#6929). The INVERSE of registry-host-replace: it REQUIRES
  # the store volume to be replaced alongside its attachment and the host, so cloud-init meets a
  # fresh RAW device and luksFormats it. A preserved volume is the footgun that darks the
  # registry. Its suite also asserts the two gates DISAGREE on the same fixtures.
  run_suite "tests/scripts/registry-luks-recut-gate" bash tests/scripts/test-registry-luks-recut-gate.sh
  # D10 pre-destroy authorization gate (#6929 / #7277) — authorizes a destroy only on a restore
  # CI has just executed into an empty registry. Leads with a positive control.
  run_suite "tests/scripts/registry-pull-path-health" bash tests/scripts/test-registry-pull-path-health.sh
  # #7555. tests/scripts/ is NOT auto-globbed by this runner (the *.test.sh glob cannot match a
  # test-* prefix), so an unregistered suite here would run in ZERO runners, green and invisible.
  run_suite "tests/scripts/registry-replace-preflight" bash tests/scripts/test-registry-replace-preflight.sh
  # The mutation battery for BOTH suites above. Registered, not ad-hoc: its previous incarnations
  # lived in a session transcript, so their "15/15 caught" protected nothing the next day — and
  # when it was finally committed it found 15 of its mutations surviving, including a seam that
  # could replace the pass condition itself. It sandboxes its own copies of both SUTs, so it
  # neither mutates the worktree nor depends on suite ordering here (#7277).
  #
  # RELEVANCE-GATED (ADR-181). At ~860 s this is the single most expensive suite in the runner —
  # about 32% of a full local run — and it guards a script most PRs never touch. The predicate is
  # referenced BY NAME: no path literal may appear on a `run_suite` line, because
  # lint-orphan-test-suites.sh reads registration out of those lines and a `*.test.sh` literal
  # sitting there would be extracted as a registration, so an inline list would certify a
  # DIFFERENT suite than the one this gate executes. (Since #7402 the extraction is anchored on
  # the COMMAND — the token after `bash` — not on the whole line, which narrows but does not
  # remove the hazard: a path literal in command position is still read as a registration.)
  if _diff_touches "${REGISTRY_BATTERY_PATHS[@]}"; then
    run_suite "tests/scripts/registry-gate-mutation-battery" bash tests/scripts/test-registry-gate-mutation-battery.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "tests/scripts/registry-gate-mutation-battery" "relevance" \
      "bash tests/scripts/test-registry-gate-mutation-battery.sh"
  fi
  # Registered explicitly, next to its D10 sibling. Nothing auto-discovers tests/scripts/: this
  # file's *.test.sh globs cannot match the `test-*` prefix, and scripts/lint-orphan-test-suites.sh
  # walks the whole repo but only for the `*.test.sh` SUFFIX, which this file does not carry. An
  # unregistered suite here runs in ZERO runners and is silent and green (#3366).
  run_suite "tests/scripts/registry-restore-from-ghcr" bash tests/scripts/test-registry-restore-from-ghcr.sh
  # D10 WIRING (not logic). The suites above prove the gate's logic; none of them proves the
  # workflow USES it. That gap is exactly how the gate shipped reading a Doppler secret which
  # exists in no config of the soleur project, aborting at PREPARE before it could reach its own
  # destroy-guard. A `run:` body is not executable by any of them, so this asserts the wiring
  # statically over both arms plus the composite action the restore leg runs inside.
  # Deliberately a separate file: the mutation battery sandboxes the D10 suite into a tree with
  # no .github/, so a workflow-reading row appended there would fail its baseline and harness_die.
  # Registered explicitly for the same reason as its neighbours — nothing auto-discovers
  # tests/scripts/ (#3366).
  run_suite "tests/scripts/registry-d10-workflow-wiring" bash tests/scripts/test-registry-d10-workflow-wiring.sh
  # D11 post-apply liveness poller (#6929) — requires a heartbeat TRANSITION, since the monitor
  # reports the dead host's residual `up` for ~90s and exposes no last_ping_at.
  run_suite "tests/scripts/registry-heartbeat-poll" bash tests/scripts/test-registry-heartbeat-poll.sh
  # (#7278) The read-only zot disk-inventory lever's two suites. Registered HERE for the same
  # reason as every line around them — nothing auto-discovers tests/scripts/, this file's
  # *.test.sh globs cannot match the `test-*` prefix, and lint-orphan-test-suites.sh's whole-repo
  # walk is keyed on that same suffix, so an unregistered suite here runs in ZERO runners while
  # looking covered.
  #
  # The FIRST is the enumerator: dedup-by-digest arithmetic against hand-computed literals, index
  # recursion, the partial/unreadable/empty-catalog verdict taxonomy, verb and egress confinement
  # measured at the wire by a recording origin, and secret masking. The number this lever exists
  # to produce is only as trustworthy as that arithmetic, and no other gate reads it.
  #
  # The SECOND is the round-trip gate, and it is separate on purpose: the pass condition was
  # deliberately extracted OUT of workflow YAML, where no test can reach it. Its primary case is
  # that a marker present with a DIFFERENT run_id must NOT pass, plus an arm requiring the gate to
  # FAIL when fed an undecoded fixture (Better Stack's `raw` column is double-encoded JSON, so a
  # bare grep silently returns nothing — a probe that can never pass, and therefore never fail).
  #
  # The workflow/composite-shape half of this feature is NOT here: it lives in
  # apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh, which this runner
  # already covers through the CI-registered infra runner.
  run_suite "tests/scripts/zot-inventory" bash tests/scripts/test-zot-inventory.sh
  run_suite "tests/scripts/zot-inventory-assert-marker" bash tests/scripts/test-zot-inventory-assert-marker.sh
  run_suite "tests/scripts/zot-disk-sample" bash tests/scripts/test-zot-disk-sample.sh
  # (#7440) The zot CONTAINER-LOG channel's readback probe. Registered HERE for the same reason as
  # its #7278 siblings above: nothing auto-discovers tests/scripts/.
  #
  # ONLY this fixture suite belongs in this file. The shipper's own suite is an INFRA suite and its
  # registration point is `.github/workflows/infra-validation.yml`, from which
  # apps/web-platform/infra/run-registered-suites.sh DERIVES its list — adding it here instead
  # would run it in ZERO runners (#3366), silent and green.
  #
  # The probe is INERT UNTIL DISPATCHED (the registry host is cloud-init-only, so merging applies
  # nothing), which makes every one of its arms a false-green candidate: a probe that can never PASS
  # is indistinguishable from one correctly reporting a not-yet. Its highest-value case is the
  # FALSE-GREEN — a window holding nothing but SOLEUR_ZOT_DISK heartbeat rows whose zot_last_err
  # echoes `zotregistry.dev` must NOT pass. That is not hypothetical: it is the state production is
  # in right now, where a bare grep for that string returns 53 rows over 6h and every one is an echo.
  run_suite "tests/scripts/zot-log-channel-probe" bash tests/scripts/test-zot-log-channel-probe.sh
  # git-data-host-replace scoped-recreate destroy-guard (#6242; 5-target, preserves BOTH data volumes + LUKS passphrase by omission).
  run_suite "tests/scripts/git-data-host-replace-gate" bash tests/scripts/test-git-data-host-replace-gate.sh
  # workspaces-luks-cutover FIRST-PROVISION destroy-guard (#6604). Permits the +create of the
  # five #6593-authored workspaces_luks resources; ABORTs any touch of the live plaintext
  # /mnt/data volume/attachment or the web-1 server, any passphrase re-mint, any destroy/forget,
  # or anything out of scope. Registered HERE — nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/workspaces-luks-cutover-gate" bash tests/scripts/test-workspaces-luks-cutover-gate.sh
  run_suite "tests/scripts/workspaces-luks-recut-gate" bash tests/scripts/test-workspaces-luks-recut-gate.sh
  # web-host BIRTH gate (#6730) — the INVERSE of web2-retire-gate: requires exactly one
  # hcloud_server create, matching the dispatched host key, with zero destroys. It is the
  # only check on the one route granted the host_creates capability (a new dispatch job
  # inherits nothing from the per-PR apply's inline HALT), so every arm is load-bearing and
  # the suite mutation-proves each one. Registered HERE — nothing auto-discovers tests/scripts/.
  run_suite "tests/scripts/web-host-birth-gate" bash tests/scripts/test-web-host-birth-gate.sh
  # web-host REPLACE gate (#6969) — the SIBLING of the birth gate above and its opposite by
  # contract: exactly one delete+create of the dispatched host, both volume families and the
  # LUKS passphrase preserved by omission, plus positive requirements on the NIC, the volume
  # attachment and the fleet firewall re-attachment. Same "a new dispatch job inherits
  # nothing" reasoning, so the same mutation battery. Registered HERE for the same reason the
  # line above says — nothing auto-discovers tests/scripts/, and an unregistered suite is
  # silent AND green.
  run_suite "tests/scripts/web-host-replace-gate" bash tests/scripts/test-web-host-replace-gate.sh
  run_suite "tests/scripts/destroy-guard-regex-parity" bash tests/scripts/test-destroy-guard-regex-parity.sh
  run_suite "tests/scripts/destroy-guard-sentry-scope-guard" bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh
  run_suite "tests/scripts/tenant-integration-gate-verdict" bash tests/scripts/test-tenant-integration-gate-verdict.sh
  # #6589 — the Sentry full-root delete path. These three gate the contract that
  # makes `terraform destroy` reachable at all for infra/sentry/**: the absence of
  # address-scoping in the apply (the #6074/#4929 root cause), the fail-closed
  # aggregator verdict, and the squash-body emulation that decides whether a
  # pre-staged [ack-destroy] will actually reach the merge commit.
  run_suite "tests/scripts/sentry-destroy-counts" bash tests/scripts/test-sentry-destroy-counts.sh
  run_suite "tests/scripts/sentry-full-root-apply" bash tests/scripts/test-sentry-full-root-apply.sh
  run_suite "tests/scripts/sentry-destroy-gate-verdict" bash tests/scripts/test-sentry-destroy-gate-verdict.sh
  run_suite "tests/scripts/sentry-squash-ack-detect" bash tests/scripts/test-sentry-squash-ack-detect.sh
  run_suite "tests/scripts/sentry-create-gate" bash tests/scripts/test-sentry-create-gate.sh
  # #7650 Phase 2 — Guard A (create protection, now wired into BOTH workflow jobs)
  # and Guard B (the forget<->import bijection) for the sentry_alert adoption.
  # Registered HERE for the reason the neighbouring comments give and this suite
  # makes acute: nothing under tests/scripts/ is auto-discovered, and the guards
  # this suite covers are the only things standing between a one-character edit
  # and 27 live paging rules — including the GDPR Art. 33 breach alert — being
  # orphaned or duplicated. An unregistered suite here would read as green
  # forever while asserting nothing.
  run_suite "tests/scripts/sentry-alert-adoption-guards" bash tests/scripts/test-sentry-alert-adoption-guards.sh
  # #7650 §2.9 — the live-fidelity probe. A fidelity probe compares a document to
  # itself for a living, and its degenerate implementation (return PASS) satisfies
  # every happy-path test anyone writes. This suite is one row per DRIFT CLASS the
  # probe's header claims to detect, so the claim is checked rather than asserted.
  # Hermetic: the live GET is replaced by SENTRY_FIXTURE_RULES throughout.
  run_suite "tests/scripts/sentry-alert-live-fidelity" bash tests/scripts/test-sentry-alert-live-fidelity.sh
  # The drift workflow's VERDICT BRANCHING, extracted from the shipped YAML and
  # executed — never restated. Two of its three outcomes are silent when wrong: a
  # verdict that files nothing looks like a clean run, and a wrongly-closed issue
  # looks like a fixed one. Neither is visible in a green workflow list.
  run_suite "tests/scripts/sentry-alert-drift-workflow" bash tests/scripts/test-sentry-alert-drift-workflow.sh
  # Class D (live monitor with no .tf block) is the delete path's other half: the
  # full-root apply can only reclaim a monitor the config once declared. Its whole
  # value is the non-zero exit — registered here because nothing auto-discovers
  # tests/scripts/, and an unregistered suite would leave the gate's fail-closed
  # claim asserted nowhere.
  run_suite "tests/scripts/sentry-monitors-audit-class-d" bash tests/scripts/test-sentry-monitors-audit-class-d.sh
  # md->Slack-mrkdwn converter (scripts/md-to-mrkdwn.mjs). Runs under stock
  # ubuntu-latest node (no setup-node — same bare-`node` precedent as
  # secret-scan.yml). node --test ships in Node >=18.
  run_suite "scripts/md-to-mrkdwn" node --test scripts/md-to-mrkdwn.test.mjs
  # Gitleaks-allowlist parser harness (#7402). It shells out to `node` for the parser under
  # test, so it sits beside md-to-mrkdwn above under the same stock-node precedent rather than
  # in the bun shard. It ran in ZERO runners until now: `apps/web-platform/test/` is under no
  # glob in this file and appears in no workflow step, which is exactly the shape the widened
  # scripts/lint-orphan-test-suites.sh walk exists to surface. Measured 0.8 s, 18 assertions.
  run_suite "apps/web-platform/test/parse-gitleaks-allowlists" bash apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh
  # Board-status mapper (#7402). #7402's body claims board-status-sync.yml runs this suite;
  # that is REFUTED — the workflow runs scripts/board/set-board-status.sh, the SCRIPT, and
  # names the .test.sh nowhere. `scripts/board/` is covered by no glob here, so this explicit
  # line is the suite's only registration anywhere. Mocks `gh` on PATH; needs no token.
  run_suite "scripts/board/set-board-status" bash scripts/board/set-board-status.test.sh

  # EXPLICIT, because no glob in this file reaches it. The suite extracts the
  # `run:` bodies out of the two skill-security-scan workflows and EXECUTES them
  # under the shell GitHub Actions uses, so it is the only thing in the repo that
  # can tell "the gate blocked this input" from "the gate never looked" (#7629).
  run_suite "scripts/skill-security-scan-step-body" bash scripts/skill-security-scan-step-body.test.sh

  # EXPLICIT: scripts/followthroughs/ is covered by no glob here. Drives the T5
  # skip-persistence probe against nine fixture samples through a fake `gh`,
  # with fixtures padded past the 64 KiB pipe buffer so the SIGPIPE race the
  # probe was losing matches to is actually reachable (#7574).
  run_suite "scripts/followthroughs/t5-skip-persistence-bound-7510" bash scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh
fi

# Named bun-test entries — bun shard.
if want_bun; then
  run_suite "test/content-publisher" bun test test/content-publisher.test.ts
  run_suite "test/x-community" bun test test/x-community.test.ts
  run_suite "test/linkedin-community" bun test test/linkedin-community.test.ts
  run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
fi

# Vitest in apps/web-platform — webplat shard.
# VITEST_SHARD (e.g., "1/2") is forwarded to vitest --shard for matrix sharding
# in CI. When unset, vitest runs all files. The empty-string suppression via
# ${VAR:+...} keeps local invocation byte-identical.
#
# VITEST_SHARD is passed via env: to the inner bash so the inner shell expands
# it under its own quoting (single-quoted outer, double-quoted inner). This
# blocks shell-injection if a caller ever sets VITEST_SHARD to a value
# containing `;` or `$(…)`. The matrix literal in ci.yml is always `K/N`
# today, but the script is a public surface — defense in depth.
#
# Split into two suites (#7498) so the app-local half can be DECLINED on a diff
# that touches nothing in the app, while the repo-wide half still runs.
#
#   repo-wide  — subject is the repository (plugin scripts, workflow YAML, the
#                knowledge base). NEVER gated: these exist to catch drift in
#                exactly the diffs that touch no app file, so gating them would
#                decline them on the commits they guard.
#   unit +     — subject is the app. Gated on apps/web-platform/.
#   component
#
# 42 of the last 80 commits on origin/main (52%; 96/200 over 200) touch no
# apps/web-platform file, so the decline is the common case rather than an edge.
# The split is safe only because test/repo-wide-containment.test.ts proves no
# gated suite reads outside the app — without it a new repo-reading test would
# land in the gated project and be silently declined. That guard runs in the
# repo-wide project, so it is never gated by the thing it guards.
if want_webplat; then
  # `component` runs ALWAYS, alongside repo-wide. #7498 evaluated gating it and
  # declined on measurement: at ~80 s it is a ~39 s expected saving, "statistically
  # the same quantity this PR already declined for the union predicate", and taking
  # it "would import a new fail-open surface to buy back exactly what was refused".
  #
  # #7666 gated it anyway, reasoning that the containment guard covers `component`
  # at zero marginal cost once it exists for `unit`. That reversed an explicit,
  # measured decision by the issue author on the strength of an argument about
  # cost, not about the risk the decision was made on — so it is reverted here.
  # The invariant the guard asserts (0 of 240 `.test.tsx` escape the app) is kept:
  # it is true and worth keeping true, it is simply no longer load-bearing.
  run_suite "apps/web-platform [repo-wide+component]" env VITEST_SHARD="${VITEST_SHARD:-}" \
    bash -c 'cd apps/web-platform && npm run test:ci -- --project repo-wide --project component ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'

  if _diff_touches "${WEBPLAT_APP_PATHS[@]}"; then
    run_suite "apps/web-platform [unit]" env VITEST_SHARD="${VITEST_SHARD:-}" \
      bash -c 'cd apps/web-platform && npm run test:ci -- --project unit ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "apps/web-platform [unit]" "relevance" \
      "cd apps/web-platform && npm run test:ci -- --project unit"
  fi
fi

# plugins/soleur bun-test recursion + blog-link-validation — bun shard.
# Co-located because validate-blog-links.sh reads _site/, which
# plugins/soleur/test/seo-aeo-drift-guard.test.ts builds. Under matrix
# sharding (separate runners) there is no race; co-location is a perf
# optimization (build once, reuse) AND defense against any future xargs-P
# attempt that would re-introduce the race within one runner.
if want_bun; then
  run_suite "plugins/soleur" bun test plugins/soleur/
  run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
  # frontmatter-strip three-way parity (#6794). The suite ALSO matches the
  # scripts-shard `scripts/lib/*.test.sh` glob below, but that shard has no bun,
  # so its strip.ts arm skip-gates there. Registering it here (bun guaranteed)
  # is what actually exercises strip.ts == strip.py == strip.sh in CI.
  run_suite "scripts/frontmatter-strip-parity" bash scripts/lib/frontmatter-strip.test.sh
fi

# Bash *.test.sh glob — scripts shard. (ci-deploy.test.sh runs in infra-validation.yml.)
# .claude/hooks/lib/*.test.sh added 2026-08-10 (#7409). Shell globs do NOT cross
# `/`, so the flat `.claude/hooks/*.test.sh` below never reached the `lib/`
# subdirectory: every suite there had NEVER gated CI. That is how the #5454
# vacuous-green class survived inside session-state.test.sh (34 KB, orphaned) —
# it relocates to plugins/soleur/test/ in this change, and this glob closes the
# hole for its remaining sibling, freeze-lock.test.sh (13 assertions, passing).
# Measured against every *.test.sh under any lib/ in the repo: after this line,
# zero orphans remain in that class. Do NOT check such coverage with Python
# `fnmatch` — its `*` DOES cross `/`, so it reports these files as already
# covered and falsifies the finding.
#
# .claude/hooks/*.test.sh added 2026-05-15 (#3799 prereq to #3789); covers the
# 8 hook tests that previously only the session-rules-loader entry pulled in.
if want_scripts; then
  # #7103 R3/R4/R5(b) + the R5(a) follow-up. These live in scripts/, which the glob below does
  # NOT cover (it reaches scripts/lib/*.test.sh, not scripts/*.test.sh), so each is registered
  # explicitly — an unregistered gate is the #3366 class, a suite whose whole claim is "this
  # cannot silently pass" running in zero runners.
  #
  # THE SHARD MATTERS. These were registered under want_bun, whose CI job (`test-bun`) installs
  # bun and node and nothing else. All four are bash, and two shell out to python3:
  # digest-oracle-guard.test.sh hard-exits 2 when `python3 -c 'import yaml'` fails, which
  # run_suite reports as a FAIL — a red required check for want of an interpreter its shard was
  # never documented to have. `test-scripts` is the job ci.yml describes as "bash + python3",
  # which is where the other 33 scripts/*.test.sh siblings already run.
  run_suite "scripts/betterstack-assert-absence" bash scripts/betterstack-assert-absence.test.sh
  run_suite "scripts/digest-oracle-guard" bash scripts/digest-oracle-guard.test.sh
  # Sandbox-only: copies scripts/ and .github/ into a mktemp -d, mutates the copies, and asserts
  # the working tree is unchanged when it finishes.
  # RELEVANCE-GATED (ADR-181), ~189 s. The battery COPIES all of scripts/ and .github/ into its
  # sandbox but only DEPENDS on the paths the predicate names; gating on the copy set would match
  # nearly every diff and never decline. Referenced by name — see the registry gate above.
  if _diff_touches "${CF_TUNNEL_BATTERY_PATHS[@]}"; then
    run_suite "scripts/cf-tunnel-liveness-gate-mutations" bash scripts/cf-tunnel-liveness-gate-mutations.test.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite "scripts/cf-tunnel-liveness-gate-mutations" "relevance" \
      "bash scripts/cf-tunnel-liveness-gate-mutations.test.sh"
  fi
  # Pins that this runner's OWN infra coverage claim matches whether it actually invoked the
  # infra runner. Registered here rather than under want_bun for the same reason as above.
  run_suite "scripts/test-all-infra-coverage-notice" bash scripts/test-all-infra-coverage-notice.test.sh
  # Guards this file's own webplat split (#7498). Registered next to its
  # sibling: both assert shape properties of test-all.sh that nothing else
  # would notice rotting.
  run_suite "scripts/test-all-webplat-gate" bash scripts/test-all-webplat-gate.test.sh
  # Pins this runner's THREE-CLASS result taxonomy (#7424): a signal-shaped exit renders as
  # [KILLED], stays out of the failure count, and exits 3. Registered here rather than under
  # want_bun for the same reason as its neighbours — it shells out to python3 to build its
  # sandbox, and `test-scripts` is the shard documented as "bash + python3".
  run_suite "scripts/test-all-killed-classification" bash scripts/test-all-killed-classification.test.sh
  # The #7545 pre-launch capacity signal: the verdict, --capacity, the wait
  # heartbeat and re-sample, and the diff-justification report. Registered
  # EXPLICITLY beside its neighbours for the same reason they state — repo-root
  # `scripts/*.test.sh` is NOT in SUITE_GLOBS (which carries `scripts/lib/*.test.sh`
  # only), so an unregistered suite here runs in zero runners and stays green
  # forever. AC18 asserts this registration by its invoked PATH, not its label,
  # because the orphan linter derives coverage from the path.
  run_suite "scripts/test-all-capacity-signal" bash scripts/test-all-capacity-signal.test.sh
  # ADR-178/ADR-187 textual parity pin (#7429): the signal-shape classifier is inlined in three
  # runners, and this asserts the three copies still agree. Registered explicitly beside its
  # sibling above — scripts/*.test.sh is NOT auto-globbed here, and this suite arrived
  # unregistered, which the widened scripts/lint-orphan-test-suites.sh walk caught on its first
  # run against the branch. A parity pin nothing executes is three copies with no pin at all.
  # Measured 0.1 s, 32 assertions, bash-only.
  run_suite "scripts/suite-exit-class-parity" bash scripts/suite-exit-class-parity.test.sh
  # The patterns are declared ONCE, at the top of this file, and published by
  # `--print-suite-globs` so scripts/lint-orphan-test-suites.sh reads the same list this loop
  # expands. Nested loop rather than one flat `for f in ${SUITE_GLOBS[@]}`: the flat form
  # depends on unquoted word-splitting, so a pattern containing a space would expand into two
  # broken patterns silently. Iteration order is unchanged (pattern 1's matches, then 2's, …),
  # so TEST_TIMING_LOG rows and suite ordering are byte-identical to the inline list this
  # replaced.
  for _suite_glob in "${SUITE_GLOBS[@]}"; do
  for f in $_suite_glob; do
    [[ -f "$f" ]] || continue
    # RELEVANCE-GATED (ADR-181) — declined on 96% of recent commits, and the only suite this loop
    # registers whose cost justifies a predicate. The justification is the SKIP RATE, not a
    # wall-clock figure: see the measurement caveat in scripts/lib/test-relevance-paths.sh, where
    # three reps of an unchanged tree spanned 23-91 s under sibling load. A per-file `if` rather
    # than a lookup table: bash 3.2 has no associative arrays and one gated member does not earn a
    # mapping.
    #
    # The label is written LITERALLY, not as "$f". skip_suite's contract is "$1 = label (must
    # match the label the suite would have run under)" and this loop's label IS the path, so the
    # two agree byte-for-byte — TEST_TIMING_LOG rows and any anchored reader stay stable.
    #
    # An `if` block, never `[[ … ]] && continue`: _diff_touches's own header forbids the short
    # form because under `set -e` its exit status depends on the call site.
    #
    # `run_suite "$f" bash "$f"` below is left byte-for-byte unchanged, so the glob's discovery
    # surface is untouched and the suite is still registered exactly once, by the glob.
    if [[ "$f" == "plugins/soleur/test/c4-from-components.test.sh" ]]; then
      if ! _diff_touches "${C4_PRODUCER_PATHS[@]}"; then
        _relevance_declined=$((_relevance_declined + 1))
        skip_suite "plugins/soleur/test/c4-from-components.test.sh" "relevance" \
          "bash plugins/soleur/test/c4-from-components.test.sh"
        continue
      fi
    fi
    run_suite "$f" bash "$f"
  done
  done
fi

# --- Nested CI-registered runners (#7103 R5(a)) -----------------------------------------
# Until now this file only NAMED these two runners, in comments and echo strings, while
# executing neither. That is the defect: a runner mentioned in a NOTE is not a runner that
# ran, and "all tests pass" was read as evidence for suites this file never invoked (#6730,
# #6969). Each registration counts as ONE suite at the aggregate level; the nested runner
# reports its own per-suite counts inside that line.
#
# The infra RUNNER is registered, never its 98 suites individually (re-derived 2026-08-13 via
# `bash apps/web-platform/infra/run-registered-suites.sh --list`; the previous figure of 87 had
# drifted). run-registered-suites.sh DERIVES its list from
# .github/workflows/infra-validation.yml and reports unregistered orphans; enumerating the
# suites here would fork that list and recreate the very drift the derivation prevents.
#
# Do not hand-edit that count: `--list` prints it, and scripts/lint-orphan-test-suites.sh reads
# the same command for its infra registration surface, so the number above is checkable in one
# second rather than trusted.
if want_infra; then
  # Relevance gate (2.2). The infra runner is the expensive one, so a docs-only run should
  # not pay for it. Reuses the preamble's `_infra_in_diff` verdict rather than re-deriving
  # it, so the notice up top and the gate down here can never disagree — including its
  # fail-SAFE arm, where an undeterminable diff sets 1 and the runner RUNS.
  #
  # Every skip is LOUD and carries the exact re-run command. A silent skip would reproduce,
  # one level up, the same "green that is not evidence" this phase exists to close.
  if [[ "${SOLEUR_INCIDENT_SKIP:-0}" == "1" ]]; then
    # Named incident bypass (2.3). The relevance gate fires on exactly the paths an infra
    # hotfix must touch, so without a documented lever this lands minutes on the incident
    # path. The alternative was leaving TEST_GROUP as an undocumented escape hatch — which
    # silently drops far more than the infra runner and says so nowhere.
    _infra_skip_reason="incident"
    skip_suite "apps/web-platform/infra/run-registered-suites.sh" "incident" \
      "bash apps/web-platform/infra/run-registered-suites.sh"
  elif [[ "$TEST_GROUP" == "infra" || "$_infra_in_diff" == 1 ]]; then
    run_suite "apps/web-platform/infra/run-registered-suites.sh" bash "apps/web-platform/infra/run-registered-suites.sh"
    # THE ONLY site that may set this. Every downstream coverage claim reads it, so it records
    # what happened rather than what was predicted.
    _infra_ran=1
  else
    _infra_skip_reason="not_in_diff"
    skip_suite "apps/web-platform/infra/run-registered-suites.sh" "not_in_diff" \
      "bash apps/web-platform/infra/run-registered-suites.sh"
  fi
fi

# The guard-script fixture runner. Its own MIN_SUITES floor (11 as of #7429, which added the
# signal-propagation guard as the 11th fixture suite) is what makes a silently empty run fail
# rather than pass, so registering it here inherits that floor instead of re-implementing one.
# The number is stated here for the reader; the runner is the authority — re-derive with
# `grep '^MIN_SUITES=' .github/scripts/test/run-all.sh` rather than trusting this comment.
#
# THE FLOOR AND A DECLINE ARE DIFFERENT OUTCOMES. The floor still applies whenever the runner
# runs, but it is not evaluated at all when the runner is DECLINED — nothing inside it executes.
# What distinguishes "declined" from "ran and found nothing" is skip_suite's output, which names
# the suite, the reason, and the exact re-run command. Reading the floor as coverage of a run
# that never happened is the same green-that-is-not-evidence shape ADR-181 closes one level up.
#
# RELEVANCE-GATED (ADR-181) — declined on 56% of recent commits. `run_suite … bash
# .github/scripts/test/run-all.sh` keeps its
# command shape byte-for-byte because scripts/lint-orphan-test-suites.sh's REQUIRED_RUNNERS check
# anchors on the COMMAND, not the label.
if want_scripts; then
  if _diff_touches "${GITHUB_SCRIPTS_SUITE_PATHS[@]}"; then
    run_suite ".github/scripts/test/run-all.sh" bash .github/scripts/test/run-all.sh
  else
    _relevance_declined=$((_relevance_declined + 1))
    skip_suite ".github/scripts/test/run-all.sh" "relevance" \
      "bash .github/scripts/test/run-all.sh"
  fi
fi

_emit_bytes_probe "__run_boundary_end__"
tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"

# --- REPO WRITE BOUNDARY (end) -----------------------------------------------------------
#
# Compared as a DELTA, so a tree that was already dirty at the start is fine; what is forbidden
# is this run CHANGING it. Reported before the summary block so the marker stays the last
# `=== ` line (#6750), and counted into `failed` so the exit code carries it: a run that
# corrupted the repository is not a pass, whatever the suites said.
# Counted into the BREAKDOWN line alongside `skipped`, per ADR-181's decision that a new outcome
# class of this runner is "a counted verdict, not an absence". REPORT still changes no exit code —
# ADR-181's `skipped` is the precedent for exactly that shape — but an outcome visible only as
# stderr prose above a several-thousand-line log reads as silence, which is the polarity that ADR
# already rejected once.
_repo_observations=0
_repo_unmeasured_dims=0
if [[ "$_repo_guard_ok" == 1 ]]; then
  if _repo_state_after="$(_repo_state)"; then
    # Classified per dimension rather than as one boolean. A sibling worktree's branch advancing
    # and this worktree's HEAD moving under it are not the same event, and collapsing them makes
    # the FATAL line cry wolf on the common case until nobody reads it.
    _repo_verdict="$(repo_boundary_classify "$_repo_state_before" "$_repo_state_after" || true)"

    # A dimension that failed to capture at BOTH boundaries produces no UNMEASURABLE (the manifests
    # agree) and no body delta — so the verdict is empty and, before this, the entire block
    # including NOT INSPECTED was skipped. Silence is this runner's "clean" signal, so that read as
    # a clean bill of health over a check that never looked. Narrowed coverage must speak even when
    # there is no delta to report.
    _repo_narrowed=""
    while IFS=$'\t' read -r _d _st; do
      [[ -n "$_d" ]] || continue
      [[ "$_st" == "measured" ]] || _repo_narrowed="$_repo_narrowed $_d"
    done <<<"$(repo_boundary_manifest "$_repo_state_after"; repo_boundary_manifest "$_repo_state_before")"
    if [[ -z "$_repo_verdict" && -n "$_repo_narrowed" ]]; then
      echo "" >&2
      echo "NOTE: no repo-write delta was detected, but this run did NOT measure every dimension." >&2
      echo "      A clean boundary is not evidence about the ones it could not read:" >&2
      repo_boundary_render_not_inspected "$_repo_state_before" "$_repo_state_after" >&2
      _repo_unmeasured_dims=$(printf '%s' "$_repo_narrowed" | wc -w | tr -d ' ')
    fi

    if [[ -n "$_repo_verdict" ]]; then
      _repo_fatal="$(printf '%s\n' "$_repo_verdict" | { grep '^FATAL' || true; })"
      _repo_report="$(printf '%s\n' "$_repo_verdict" | { grep '^REPORT' || true; })"
      _repo_unmeasurable="$(printf '%s\n' "$_repo_verdict" | { grep '^UNMEASURABLE' || true; })"

      if [[ -n "$_repo_fatal" ]]; then
        failed=$((failed + 1))
        echo "" >&2
        echo "[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY. This runner is read-only here." >&2
        echo "        Last suite started: ${_repo_last_suite}" >&2
        echo "        (the boundary is sampled exactly TWICE — once at the first suite and once" >&2
        echo "         here — so this names where the run had REACHED, not which suite wrote. No" >&2
        echo "         per-suite snapshot is taken, so the run has no evidence about any other" >&2
        echo "         individual suite.)" >&2
        echo "" >&2
        echo "        WHAT CHANGED:" >&2
        printf '%s\n' "$_repo_fatal" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "          [$_dim] $_detail" >&2
          echo "                 next: $(repo_boundary_next_action "$_dim")" >&2
        done
        echo "" >&2
        _rb_head_before="$(printf '%s\n' "$_repo_state_before" | sed -n 's/^head\t//p')"
        _rb_head_after="$(printf '%s\n' "$_repo_state_after"  | sed -n 's/^head\t//p')"
        if [[ -n "$_rb_head_before" && "$_rb_head_before" != "$_rb_head_after" ]]; then
          echo "        HEAD before: ${_rb_head_before}" >&2
          echo "        HEAD after : ${_rb_head_after}" >&2
          echo "        (good-sha is the BEFORE value; bad-sha is the AFTER value.)" >&2
        fi
        echo "        Committed work survives; UNCOMMITTED work may not. Recover in this order:" >&2
        echo "          1. git push origin <good-sha>:refs/heads/<branch>   # durability BEFORE local surgery" >&2
        echo "          2. git update-ref refs/heads/<branch> <good-sha> <bad-sha>   # compare-and-swap" >&2
        echo "          3. restore the checkout, then remove the fixture's files" >&2
        echo "        A suite whose fixture cd fails, or whose git -C operand is empty, runs git in" >&2
        echo "        the caller CWD (#7553/#7652)." >&2
      fi

      if [[ -n "$_repo_report" ]]; then
        echo "" >&2
        echo "[REPORT] A SHARED store changed in a way a sibling worktree routinely produces." >&2
        echo "         The per-line details below say which store and which member. This class" >&2
        echo "         increments nothing and changes no exit code; it is printed, and counted in" >&2
        echo "         the breakdown, so it is not mistaken for silence." >&2
        printf '%s\n' "$_repo_report" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "           [$_dim] $_detail" >&2
        done
        _repo_observations=$(printf '%s\n' "$_repo_report" | grep -c '^REPORT' || true)
        # `Last suite started` is deliberately NOT repeated here. The whole premise of this class
        # is that a suite of THIS run probably was not the cause, so naming one would point the
        # reader at an innocent label — the precise AP-021 shape this boundary exists to refuse.
        #
        # And attribution points at the set this run MEASURED, not at the [contention] preamble.
        # That preamble counts processes running test-all.sh — not sibling worktrees doing ordinary
        # git work, which is the population that produces this class — and the runner refuses with
        # rc=4 when it is non-zero, so at this point in the run it reads 0 on essentially every
        # invocation. A number that is zero exactly when it would matter is not attribution.
        echo "         Attribution: the branches this run measured as checked out elsewhere are" >&2
        echo "         listed below; \`git worktree list\` shows the current set." >&2
        printf '%s\n' "$_repo_state_before" | sed -n 's/^wt\t/           checked out elsewhere: /p' >&2
      fi

      if [[ -n "$_repo_unmeasurable" ]]; then
        echo "" >&2
        echo "[UNMEASURABLE] A dimension was captured at one boundary and not the other, so its" >&2
        echo "               delta is meaningless. This is neither clean nor dirty: the run is" >&2
        echo "               simply not evidence about it. Each line below names its own cause;" >&2
        echo "               the common one is [worktree], where git status refreshes the index" >&2
        echo "               and fails under index.lock contention that parallel worktrees produce." >&2
        printf '%s\n' "$_repo_unmeasurable" | while IFS=$'\t' read -r _sev _dim _detail; do
          echo "               [$_dim] $_detail" >&2
        done
      fi

      # Rendered FROM THE MANIFEST carried inside the snapshot — never from a literal list here.
      # If the lib narrows, this narrows with it, which is what stops a full-width claim from
      # sitting on top of a partial check.
      echo "" >&2
      echo "        INSPECTED (this is the whole of what was measured):" >&2
      repo_boundary_render_inspected "$_repo_state_before" "$_repo_state_after" >&2
      echo "        NOT INSPECTED (a clean boundary is not evidence about these):" >&2
      repo_boundary_render_not_inspected "$_repo_state_before" "$_repo_state_after" >&2
      echo "" >&2
      echo "        SCOPE, stated so it is not over-read: this covers runs of THIS runner only." >&2
      echo "        A suite invoked directly (bash path/to/x.test.sh), lefthook's pre-commit" >&2
      echo "        hook, and every other entry point are NOT inspected here. The per-site" >&2
      echo "        guards inside the suites are the protection; this is defence in depth over" >&2
      echo "        gate runs, and a clean run here is not evidence about those other paths." >&2
    fi
  else
    echo "" >&2
    echo "NOTE: the repo-write boundary could not be re-read; this run is not evidence that" >&2
    echo "      no suite wrote to the repository." >&2
  fi
else
  echo "" >&2
  echo "NOTE: the repo-write boundary was not measured (git could not read HEAD at run start);" >&2
  echo "      this run is not evidence that no suite wrote to the repository." >&2
fi
# Ownership of the verdict passes from the EXIT trap to this block, whatever the outcome above —
# including the degraded arms, which have already said their piece.
_repo_boundary_reported=1

# BREAKDOWN FIRST, TERMINAL MARKER LAST. The ordering is load-bearing, not cosmetic.
# Both lines are `=== ...`-shaped, and the documented lesson from #6750 is to match
# the runner's LAST emitted line and never a per-stage line that merely looks
# summary-shaped. Emitting the breakdown last would make a summary-shaped line that
# is NOT the terminal marker the final one — reintroducing that exact ambiguity in
# the one scenario (a killed run) where identifying completion correctly matters
# most. Ordering it first keeps both contracts at zero cost: byte-identical clean
# output, and `=== N/M suites passed ===` stays the last `===` line on every arm.
#
# ADR-181 adds `skipped` to the same breakdown rather than appending it to the marker.
# An earlier revision of this change DID append `(F failed, S skipped)` to the marker, which
# orphaned every anchored poll of it; the separate-line shape #7424 established keeps the marker
# byte-identical, so no reader is orphaned at all. Declines are counted in `suites` and excluded
# from the numerator: with skips in the denominator but not in `failed`, the numerator would
# report a gated suite as PASSED — a green that is not evidence, produced by the very change
# that added the gate.
if (( killed > 0 || skipped > 0 || ${_repo_observations:-0} > 0 || ${_repo_unmeasured_dims:-0} > 0 )); then
  # `_repo_observations` is APPENDED, never interleaved: every existing field keeps its position
  # so anchored readers of this line stay valid. Shown only when non-zero — a field that is 0 on
  # essentially every run carries no information, whereas `skipped` is routinely non-zero.
  _repo_obs_field=""
  if [[ "${_repo_observations:-0}" -gt 0 ]]; then
    _repo_obs_field=", ${_repo_observations} repo observation(s) (REPORT — not a verdict, exit code unchanged)"
  fi
  if [[ "${_repo_unmeasured_dims:-0}" -gt 0 ]]; then
    _repo_obs_field="${_repo_obs_field}, ${_repo_unmeasured_dims} boundary dimension(s) NOT MEASURED (this run is not evidence about them)"
  fi
  echo "=== $suites suites: $((suites - failed - killed - skipped)) passed, $failed failed, $killed killed (unresolved — coverage not obtained), $skipped skipped (declined — not relevant to this diff)${_repo_obs_field} ==="
fi
# THE LEVER, PRINTED ONCE, ONLY WHEN IT CAN ACTUALLY HELP. SOLEUR_TEST_FORCE_ALL appeared exactly
# once in this runner -- inside _diff_touches's early return -- and was printed nowhere, while the
# infra runner advertises its own lever in two places. A decline is only safe while it stays
# actionable, so the recovery path belongs beside the count of declines.
#
# GATED ON RELEVANCE DECLINES, NOT ON `skipped`, and the wording says "relevance-gated" rather than
# "everything". Both were defects review caught, and they compound: `skipped` also counts the infra
# runner's incident/not_in_diff declines, which _diff_touches never sees, so the earlier form (a)
# claimed to recover a suite it cannot, and (b) still fired after the operator obeyed it -- printing
# the same advice verbatim on the next run, which is advice that does not terminate. Worst case was
# SOLEUR_INCIDENT_SKIP=1 on an incident path: the only decline is one the operator set deliberately,
# answered with an unrelated lever. The infra runner keeps advertising its own.
if (( _relevance_declined > 0 )); then
  echo "      To run every relevance-gated suite regardless of the diff:"
  echo "        SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh"
fi
echo "=== $((suites - failed - killed - skipped))/$suites suites passed ==="

# Restatement of the PREAMBLE notice (#6730/#7014, re-pointed by #7103). Since the infra
# runner is now a REGISTERED nested suite, the thing worth restating inverted: it is no
# longer "the summary excludes infra" but "the summary includes it — unless it was skipped,
# in which case say so HERE too". A reader who `tail`s the log (the documented log-reading
# shape) must not have to infer which of those happened.
#
# Keyed on `_infra_ran`, which is set ONLY at the run_suite call site — an OBSERVED fact, not
# a predicted one. It previously keyed on `_infra_in_diff`, so the "IS covered above" line
# printed in the three CI shards where want_infra is false and the runner never executed, and
# the SOLEUR_INCIDENT_SKIP line attributed to the incident bypass any skip that happened for a
# different reason entirely (wrong TEST_GROUP, or a docs-only diff with the var incidentally
# set).
#
# Bare `$_infra_ran`, deliberately NOT `${_infra_ran:-0}`. The variable is set unconditionally
# at top level, so the default could only mask a future edit that removed that initialisation —
# and it would mask it by silently dropping every notice. Under `set -u` the bare form makes
# that edit fail loudly instead.
if [[ "$_infra_ran" == 1 ]]; then
  echo ""
  echo "NOTE (announced in the preamble): apps/web-platform/infra/ IS covered above, via the"
  echo "      nested apps/web-platform/infra/run-registered-suites.sh suite."
elif [[ "$_infra_skip_reason" == "incident" ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ was SKIPPED (SOLEUR_INCIDENT_SKIP=1)."
  echo "      Nothing above is evidence for it. Run the CI-registered suites:"
  echo "        bash apps/web-platform/infra/run-registered-suites.sh"
elif [[ "$_infra_skip_reason" == "group" && "$_infra_in_diff" == 1 ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ is NOT covered above — TEST_GROUP=$TEST_GROUP excludes"
  echo "      the infra runner, and your diff touches that directory. Run:"
  echo "        bash apps/web-platform/infra/run-registered-suites.sh"
elif [[ "$_infra_skip_reason" == "not_in_diff" ]]; then
  echo ""
  echo "NOTE: apps/web-platform/infra/ is NOT covered above (diff does not touch it)."
fi

if [[ "$failed" -gt 0 ]]; then
  exit 1
elif (( killed > 0 )); then
  exit 3
fi
