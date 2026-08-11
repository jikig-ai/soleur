#!/usr/bin/env bash
set -euo pipefail

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
# run_suite() invocation appends "<label>\t<elapsed_ms>[\tFAIL]" to that path.
# Elapsed time uses bash 5.0+ EPOCHREALTIME (microsecond precision, no
# coreutils dependency, portable across Linux + Homebrew bash on macOS).
# CI runs ubuntu-latest (bash 5.x). macOS default /bin/bash is 3.2 — install
# bash 5 from Homebrew if you need timing locally; otherwise EPOCHREALTIME
# resolves to empty and elapsed_ms computes 0 silently.

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
# Guard on tc_acquire (the LAST-defined function in the lib): bash parses a
# sourced file all-or-nothing, so a file truncated at an exact function boundary
# is the only state where an earlier function exists but a later one does not —
# checking the last one closes even that edge. If the lib is absent or failed to
# parse, install no-op stubs for every call site so a broken/missing lib degrades
# to a normal run rather than aborting the suite.
if ! declare -F tc_acquire >/dev/null 2>&1; then
  echo "WARNING: contention instrumentation unavailable ($_TC_LIB); continuing without it." >&2
  tc_preamble() { :; }
  tc_epilogue() { :; }
  tc_tmp_entry_count() { printf '0\n'; }
  tc_acquire() { :; }
fi

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
  local start="$EPOCHREALTIME"
  echo "--- $label ---"
  local status="ok"
  if ! "$@"; then
    status="FAIL"
    failed=$((failed + 1))
  fi
  # Integer math on EPOCHREALTIME ("seconds.microseconds") avoids a coreutils
  # `date +%N` dependency that macOS lacks. 10# forces base-10 parsing of the
  # microseconds substring (a leading zero would otherwise trigger octal).
  # The `*.*` glob guard rejects bash-3.x values (where EPOCHREALTIME is unset
  # and the captured value is empty or non-dotted) and exits elapsed_ms=0
  # gracefully instead of arithmetic-overflowing on `${start#*.}` returning
  # the whole string.
  local end="$EPOCHREALTIME"
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
  if [[ "$status" == "ok" ]]; then
    echo "[ok] $label (${elapsed_ms}ms)"
    printf '%s\t%d%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  else
    echo "[FAIL] $label (${elapsed_ms}ms)" >&2
    printf '%s\t%d\tFAIL%s\n' "$label" "$elapsed_ms" "$tmp_field" >> "${TEST_TIMING_LOG:-/dev/null}"
  fi
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
_infra_detect_ok=0
_infra_diff_names=""
if _infra_out="$(git -c core.quotePath=false diff --name-only HEAD 2>/dev/null)"; then
  _infra_diff_names="${_infra_diff_names}
${_infra_out}"
fi
if _infra_out="$(git -c core.quotePath=false diff --name-only origin/main...HEAD 2>/dev/null)"; then
  _infra_detect_ok=1
  _infra_diff_names="${_infra_diff_names}
${_infra_out}"
fi
_infra_diff_names="${_infra_diff_names}
$(git ls-files --others --exclude-standard -- apps/web-platform/infra 2>/dev/null || true)"

_infra_in_diff=0
if grep -qF 'apps/web-platform/infra/' <<<"$_infra_diff_names"; then
  _infra_in_diff=1
fi

if [[ "$_infra_detect_ok" == 0 ]]; then
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
elif [[ "$_infra_detect_ok" == 0 ]]; then
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

# Advisory, self-announcing queue (#6789). Acquired INTERNALLY (not by a caller
# wrapping the script) so no invocation can forget it. It NEVER aborts — on
# timeout it proceeds with a named banner, so it cannot wedge a run. CI and the
# SOLEUR_DISABLE_SESSION_STATE kill switch are honoured inside tc_acquire.
tc_acquire "test-all"

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
  # ADR-140: Layer A encryption-posture detector (the mechanical resolver behind
  # the "encryption at rest + in transit" design-time gate). TS-1..8,15..17 +
  # the MB-1..MB-12 mutation battery (fixture-isolated, not suite-pass-count).
  run_suite "scripts/lint-encryption-posture" bash scripts/lint-encryption-posture.test.sh
  run_suite "scripts/extract-api-spend" bash scripts/extract-api-spend.test.sh
  run_suite "scripts/domain-model-drift" bash scripts/domain-model-drift.test.sh
  # #6602: exit-code harness for the expenses verify_by expiry gate. Registered
  # explicitly — this runner enumerates by hand and scripts/*.test.sh is NOT in
  # the auto-glob below, so an unregistered suite is an ORPHAN that never gates
  # (the #5417 class). The gate authorizes a fail-loud financial-accuracy alarm,
  # so its arms returning the right exit codes is load-bearing coverage.
  run_suite "scripts/expenses-verify-by-check" bash scripts/expenses-verify-by-check.test.sh
  run_suite "scripts/sentry-issue" bash scripts/sentry-issue.test.sh
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
  # lint-orphan-test-suites.sh walks only scripts/*.test.sh, and
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
  run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
  run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
  run_suite "scripts/rule-metrics-aggregate" bash scripts/rule-metrics-aggregate.test.sh
  run_suite "tests/scripts/weakness-miner" bash tests/scripts/test-weakness-miner.sh
  run_suite "tests/scripts/audit-ruleset-bypass" bash tests/scripts/test-audit-ruleset-bypass.sh
  run_suite "tests/scripts/audit-bot-codeql-coverage" bash tests/scripts/test-audit-bot-codeql-coverage.sh
  run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
  run_suite "tests/commands/sync-domain-model" bash tests/commands/test-sync-domain-model.sh
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
  # The mutation battery for BOTH suites above. Registered, not ad-hoc: its previous incarnations
  # lived in a session transcript, so their "15/15 caught" protected nothing the next day — and
  # when it was finally committed it found 15 of its mutations surviving, including a seam that
  # could replace the pass condition itself. It sandboxes its own copies of both SUTs, so it
  # neither mutates the worktree nor depends on suite ordering here (#7277).
  run_suite "tests/scripts/registry-gate-mutation-battery" bash tests/scripts/test-registry-gate-mutation-battery.sh
  # Registered explicitly, next to its D10 sibling. Nothing auto-discovers tests/scripts/: this
  # file's *.test.sh glob cannot match the `test-*` prefix, and scripts/lint-orphan-test-suites.sh
  # covers scripts/*.test.sh only. An unregistered suite here runs in ZERO runners and is silent
  # and green (#3366).
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
  # *.test.sh glob cannot match the `test-*` prefix, and lint-orphan-test-suites.sh covers
  # scripts/*.test.sh only, so an unregistered suite runs in ZERO runners while looking covered.
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
if want_webplat; then
  run_suite "apps/web-platform" env VITEST_SHARD="${VITEST_SHARD:-}" \
    bash -c 'cd apps/web-platform && npm run test:ci -- ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1'
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
  run_suite "scripts/cf-tunnel-liveness-gate-mutations" bash scripts/cf-tunnel-liveness-gate-mutations.test.sh
  # Pins that this runner's OWN infra coverage claim matches whether it actually invoked the
  # infra runner. Registered here rather than under want_bun for the same reason as above.
  run_suite "scripts/test-all-infra-coverage-notice" bash scripts/test-all-infra-coverage-notice.test.sh
  for f in plugins/soleur/test/*.test.sh plugins/soleur/skills/*/test/*.test.sh plugins/soleur/scripts/*.test.sh .claude/hooks/*.test.sh apps/cla-evidence/scripts/*.test.sh apps/web-platform/scripts/*.test.sh apps/web-platform/scripts/lib/*.test.sh scripts/lib/*.test.sh; do
    [[ -f "$f" ]] || continue
    run_suite "$f" bash "$f"
  done
fi

# --- Nested CI-registered runners (#7103 R5(a)) -----------------------------------------
# Until now this file only NAMED these two runners, in comments and echo strings, while
# executing neither. That is the defect: a runner mentioned in a NOTE is not a runner that
# ran, and "all tests pass" was read as evidence for suites this file never invoked (#6730,
# #6969). Each registration counts as ONE suite at the aggregate level; the nested runner
# reports its own per-suite counts inside that line.
#
# The infra RUNNER is registered, never its 87 suites individually. run-registered-suites.sh
# DERIVES its list from .github/workflows/infra-validation.yml and reports unregistered
# orphans; enumerating the suites here would fork that list and recreate the very drift the
# derivation prevents.
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
    echo ""
    echo "SKIPPED (SOLEUR_INCIDENT_SKIP=1): apps/web-platform/infra/run-registered-suites.sh"
    echo "      Nothing below is evidence for apps/web-platform/infra/. Re-run with:"
    echo "        bash apps/web-platform/infra/run-registered-suites.sh"
    echo ""
  elif [[ "$TEST_GROUP" == "infra" || "$_infra_in_diff" == 1 ]]; then
    run_suite "apps/web-platform/infra/run-registered-suites.sh" bash "apps/web-platform/infra/run-registered-suites.sh"
    # THE ONLY site that may set this. Every downstream coverage claim reads it, so it records
    # what happened rather than what was predicted.
    _infra_ran=1
  else
    _infra_skip_reason="not_in_diff"
    echo ""
    echo "SKIPPED (diff does not touch apps/web-platform/infra/): apps/web-platform/infra/run-registered-suites.sh"
    echo "      Re-run explicitly with either:"
    echo "        bash apps/web-platform/infra/run-registered-suites.sh"
    echo "        TEST_GROUP=infra bash scripts/test-all.sh"
    echo ""
  fi
fi

# The guard-script fixture runner. Its own MIN_SUITES floor (10) is what makes a silently
# empty run fail rather than pass, so registering it here inherits that floor instead of
# re-implementing one.
if want_scripts; then
  run_suite ".github/scripts/test/run-all.sh" bash .github/scripts/test/run-all.sh
fi

tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"

echo "=== $((suites - failed))/$suites suites passed ==="

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
fi
