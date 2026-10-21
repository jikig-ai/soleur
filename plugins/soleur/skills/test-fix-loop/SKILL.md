---
name: test-fix-loop
description: "This skill should be used when autonomously iterating on test failures: runs the suite, diagnoses, applies minimal fixes, re-runs with checkpoint commit isolation until all tests pass."
---

<!-- Inspired by mattpocock/skills/skills/engineering/diagnosing-bugs/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->
<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Test-Fix Loop

Autonomous test-fix iteration loop. Run the test suite, diagnose failures, apply fixes to implementation code, and re-run until all tests pass or a termination condition is met. This is a recovery mechanism for unexpected failures -- not a replacement for RED/GREEN/REFACTOR (use `atdd-developer` for TDD discipline).

## When to Use

- After implementation produces unexpected test failures in unrelated modules
- When `soleur:work` GREEN phase fails and manual diagnosis is tedious
- To batch-fix multiple test failures across a codebase
- NOT for writing new tests (use `atdd-developer`)
- NOT for linting, type-checking, or non-test failures

## Phase 0: Detect and Confirm

### Detect Test Runner

Auto-detect the test command from project files in priority order:

1. `CLAUDE.md` -- explicit test command (highest priority)
2. `package.json` -- `scripts.test` field
3. `Cargo.toml` -- `cargo test`
4. `Makefile` / `Justfile` -- `test` target
5. `Gemfile` / `Rakefile` -- `bundle exec rake test` or `bin/rails test`
6. `pyproject.toml` -- `pytest`
7. `go.mod` -- `go test ./...`

If `$ARGUMENTS` contains `--cmd` or `--max` flags, extract values directly: `--cmd '<command>'` sets the test command and `--max N` the iteration cap; when either is present it wins over the number/command heuristics below (a red-capable command from `soleur:reproduce-bug` usually contains digits). Optional flag: `--max` (iterations, default 5). When the caller is `soleur:reproduce-bug`, `--cmd` is its Phase 8 red-capable command, already committed in its Phase 9 — the loop iterates on the user's symptom, not on a proxy. `--max` and `--max-fix-rounds` are the same ceiling — feed it to `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" init --max-fix-rounds N` ONLY when explicitly provided: the default-5 must never ratchet down a pipeline-set cap (#9403) — and the tally's own ratchet guard refuses a lower argv cap against a persisted one without `--reset`.
Otherwise: if `$ARGUMENTS` contains a custom test command, use it instead of auto-detection; if it contains a number, use it as max iterations (default: 5).
If no runner is detected, the plugin gate is the entry point — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh"` detects the stack (nx/turbo, JS/TS, Python, Go), reads `.soleur-test-gate.json` overrides, and refuses loudly rather than improvising a command; a repo with a capability-positive [scripts/test-all.sh](../../../../scripts/test-all.sh) is delegated to instead. Precedence to know: a committed `test_command` in that config runs FIRST — before delegation or adapters — so read it before assuming a stack's own selector applies. If the gate reports `no-stack`/`toolchain-missing` (rc 4) or `no-tests` (rc 7), ask the user for the test command.

### Require Clean Working Tree

Run `git status --porcelain`. If output is non-empty, STOP and tell the user to commit their changes first.

### Pre-flight Confirmation

<decision_gate>
**API budget.** Each iteration of this loop consumes one main-model turn (parse failures → cluster → fix → re-run) against the Anthropic API key in your Claude Code session. The `max iterations` cap (default 5, configurable via `$ARGUMENTS`) is the only cost ceiling — a runaway against a perpetually-flaky test command or an infinite-regression chain runs up to the cap before terminating. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Show the user: detected test command, max iterations, current branch.
Get one confirmation before starting the loop. This is the only approval gate --
no per-iteration approval.
</decision_gate>

## Phase 1: Test-Fix Loop

Record the current commit SHA as `<initial-sha>` before entering the loop. This is the rollback target if the loop terminates on failure after multiple iterations.

Pipeline tally (#9403): `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" init` (merge-safe — the resolved `--max` lands via `--max-fix-rounds`). Before EACH iteration's fix attempt: `VERDICT="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" gate fix_rounds)"` — `STOP` → write `knowledge-base/project/specs/<feature>/session-state.md` (`status: budget-capped` + `budget-capped: fix_rounds=<count>/<cap>` + resume prompt) and exit cleanly without reset (a capped run preserves its commits; the iteration table's `Max iterations` row still governs its own cap). `WARN`/`OK` → continue and `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" incr fix_rounds` once per iteration. `UNKNOWN` → continue (caps unenforced — ship renders `cap-unenforced`).

Run the initial test suite and **capture its exit code** (`rc`) — the verdict is `rc`, not the parsed output. Exit with "All tests already pass. Nothing to fix." only when `rc` is 0. A run that exits non-zero while parsing to zero failures is not a pass: this repo's `test-all.sh` exits 3 when zero suites failed and at least one was terminated with a signal-shaped status, rendered `[KILLED]` rather than `[FAIL]` (see its `EXIT CONTRACT` block). Handle that through the *Suite terminated* row in §2 — never by entering the loop and never by reporting success.

For each iteration (up to max iterations):

### 1. Parse Failures

Extract failure summaries from test output: test name and error message only (one line each). Discard full stack traces and passing test output to minimize context consumption.

Distinguish build/compilation errors from test failures. If the suite fails to compile, treat the entire build error as a single cluster and fix the compilation issue first.

Count `^[KILLED]` lines separately from failures, and record both alongside `rc`. A terminated suite emits no assertion output, so it parses to zero failures and produces zero clusters: "non-zero `rc`, nothing parseable" is a real shape, and it is *unresolved coverage*, not an empty failure set. Never let it fall through to "all tests pass".

**Flake screen — the failure set §2's delta rows and §3's clustering read is the POST-SCREEN set.** For each test in this run's failure set that is not already quarantined — keyed by file + test name (the same `it()` title in two files is two entries, not one flake) — re-run that test alone on the unchanged code via the runner's filter flag (`vitest -t`, `pytest -k`, `go test -run`, `bun test -t` / `--test-name-pattern`; when the runner cannot filter, one suite-level re-run answers the same question by absence). **A pass on that re-run — same code, no fix applied — is a flake signature.** A re-run that itself errors or times out is NOT a pass: the failure stays on the fix path. Mixed sets compose per-test — passers quarantine, failers proceed to §3. The screen never runs on a `^[KILLED]` / `rc` 3 suite (the *Suite terminated* row owns those — ADR-177) nor on build/compile errors (no single test to isolate). Per quarantined test, three acts:

- **Quarantine it** — remove it from the failure set driving fix/cluster bookkeeping and from every later delta count: a test quarantined in iteration N stays quarantined for the run, never counts toward "fixed", and never trips *Circular fix*. It consumes no fix-round tally (no fix was attempted).
- **File it** — when a GitHub remote and `gh` exist: ensure the label first (`gh label create flaky --color FBCA04 --description "Intermittently-failing test" 2>/dev/null || true` — the create self-heals on a repo lacking the label and never rewrites an existing one), then dedupe on a sentinel, not the title: `gh issue list --state open --label flaky --json number,body` and match `<!-- soleur:flake test="<file>::<name>" -->` in the bodies, commenting on the existing tracker rather than filing a duplicate (the sentinel-dedup arm of `check-red-on-main.sh`; an `in:title "…"` phrase breaks on a test name carrying `"` or search-significant punctuation and silently misses the tracker it exists to find). On a miss, `gh issue create` titled `flake: <test> — <signature>` with `--label flaky`, body carrying the sentinel line, the pass-on-retry signature, the runner command, and a pointer to [determinism-checklist.md](./references/determinism-checklist.md). With no `gh`/remote the quarantine is report-only and the report says so.
- **Report it** — a `Quarantined flakes:` block in the Diagnostic Report naming each test + its issue. Once quarantined, a later re-failure is noted in the report and the filed issue, not re-entered for fixing; if the flake was first observed in an iteration after this loop's first fix commit, or the flaked test exercises files this branch's diff touched, flag **possible diff-interaction** — a diff-introduced flake passes the screen by construction, and a path intersection against the loop's commits can never fire (the loop never edits test files), so timing and exercised-surface are the only honest signals. Quarantine must never launder a real regression this branch caused. Quarantine never edits, skips, or deletes a test file.

### 2. Check Termination Conditions

Before attempting fixes, check whether to stop. Rows are checked top to bottom; the first match wins.

**The count driving every delta row below is `failures + killed` on the post-screen set (the §1 flake screen's quarantines never enter it), and a suite that is KILLED in either of the two iterations being compared is excluded from the delta rather than counted as fixed.** A failures-only count is arithmetically unsafe here: a suite that FAILED in iteration N and is KILLED in N+1 lowers it, which reads as a fabricated improvement; when the same suite completes again in N+2 the count jumps back, which reads as **Regression** and would `git reset --hard HEAD` over real fixes on the strength of a signal artifact.

| Condition | Detection | Action |
|-----------|-----------|--------|
| Suite terminated (unresolved) | Any `^[KILLED]` line in the output, or runner `rc` 3 | Do NOT stage, do NOT report success, do NOT reset. Re-run that suite alone; if it is KILLED again, STOP and report UNRESOLVED naming the suite |
| All tests pass | `rc` 0 (zero failures **and** zero killed) | Run the probe grep from §4 first (on output, remove the probes and re-run the suite); when it is silent, stage fixes with `git add -A`, report success |
| All failures screened out | Post-screen failure set empty while `rc` non-zero **and ≥1 test was quarantined this run** — every parsed failure passed its isolated re-run (a zero-failure parse with non-zero `rc` is NOT this row: nothing screened is nothing proven, and it falls through to the rows below) | Run the same probe grep as the row above; when silent, `git add -A` and report `SUCCESS (N quarantined — issues #…)` — never NON_CONVERGENCE or MAX_ITERATIONS on an all-flake set |
| Max iterations | iteration == limit | `git reset --hard <initial-sha>` (revert all iterations), report |
| Regression | Failure count increased vs previous iteration | `git reset --hard HEAD` (discard uncommitted fixes), report |
| Circular fix | Failure name set matches any prior iteration | `git reset --hard <initial-sha>` (revert all iterations), report |
| Non-convergence | Failure count unchanged for 2 consecutive iterations | `git reset --hard <initial-sha>` (revert all iterations), report |
| Build error persists | Same compilation error after fix attempt | `git reset --hard <initial-sha>` (revert all iterations), report |

If a termination condition triggers, skip to the Diagnostic Report.

### 3. Cluster and Diagnose

Cluster failures by file or module (max 5 groups, sorted by failure count descending). If more than 5 modules fail, take the top 5 and note the skipped modules.

For each cluster, apply the diagnostic-first rule:

- Read the failing test to understand expected behavior
- Read the implementation code referenced by the error
- Identify the root cause before proposing a fix

### 4. Checkpoint and Fix

<critical_sequence>
Commit the current working tree as a rollback checkpoint before applying fixes. Skip on iteration 1 if the tree is clean -- `<initial-sha>` already serves as the rollback point.

Before the checkpoint commit run `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- ':/' ':(top,exclude)knowledge-base/**/*.md'`; it must print nothing (top-anchored: the whole repo from whatever cwd the suite needs). On output, remove the probes and re-run the suite before committing -- a probe removal is not a fix and never checkpoints as one (ADR-230). Then `git ls-files --others --exclude-standard | grep -iE '\.(har|webm|mp4|mov|dmp|core)$'` -- also nothing: a captured artifact from `soleur:reproduce-bug` Phase 2 option 3 must never be swept up by the `git add -A` below.

    git add -A && git commit -m "test-fix-loop: checkpoint iteration N"

Apply fixes to implementation code only. NEVER modify test files, add skip annotations, delete tests, or weaken assertions.

Re-run the full test suite after applying fixes.

Evaluate the result (same `failures + killed` count and the same row order as §2):

- Any `^[KILLED]` line or `rc` 3: do NOT stage, do NOT report success, do NOT reset — take the *Suite terminated* row
- All pass (`rc` 0): run the same probe grep and the artifact grep; on output, remove the probes / the artifact, re-run the suite, and stage only when both are silent and `rc` is still 0. Then `git add -A`, report success, STOP
- Failures decreased: continue to next iteration (fixes stay in working tree; the next iteration's checkpoint commits them)
- Regression: `git reset --hard HEAD` (discard uncommitted fixes, return to checkpoint), STOP
- Circular or non-convergence: `git reset --hard <initial-sha>` (revert ALL iterations), STOP
- Max iterations reached: `git reset --hard <initial-sha>` (revert ALL iterations), STOP
</critical_sequence>

## Diagnostic Report

On termination (success or failure), write a report to stdout:

- **Result**: SUCCESS, REGRESSION, CIRCULAR, MAX_ITERATIONS, NON_CONVERGENCE, or UNRESOLVED
- **Iterations completed**: N out of max
- **Termination reason**: one-line explanation
- **Iteration history**: failure count per iteration with delta
- **Remaining failures**: test name and error message for each (if not success)
- **Quarantined flakes**: one line per quarantined test — name + filed issue (or `report-only` when no `gh`/remote); a SUCCESS with quarantines renders `SUCCESS (N quarantined — issues #…)`, never a bare green
- **Fixes applied**: files modified and what changed (last iteration)
- **Recommendation**: what the user should investigate next (if not success). CIRCULAR or NON_CONVERGENCE on one cluster is an architecture signal, not a fix signal: recommend `soleur:engineering:review:legacy-code-expert` for that cluster's seams and characterization tests before another loop. Likewise when a fix landed but no existing test asserts the behaviour it changed -- this loop never writes tests, so name the agent that should. On NON_CONVERGENCE or MAX_ITERATIONS, name the remaining failures as load-only flake candidates to review against [determinism-checklist.md](./references/determinism-checklist.md) — the isolated re-run under-detects the contention class (fails only under suite load), so the honest answer there is determinism work on the test, not retry.

On success, fixes are staged but NOT committed. The user reviews and commits via `soleur:ship` or manually.

## Key Principles

- Diagnose before fixing -- never guess at the root cause
- Fix implementation code only -- tests define the contract
- Truncate aggressively -- failure summaries only, no full stack traces
- Fail safe -- checkpoint commit before every fix attempt, revert on regression
- Exit early -- stop as soon as the trajectory indicates non-convergence
- Stage, do not commit -- respect the Workflow Completion Protocol
- Probes are not fixes -- a `[DEBUG-<hex4>]` line never checkpoints or stages (ADR-230)
- Pass-on-retry is a flake to quarantine, not a fix to report
