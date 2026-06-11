# Learning: Consolidating N pipelines onto one helper — behavior-preserving migration traps (#5111)

## Problem

PR #5133 migrated 9 bot cron PR pipelines (4 prompt-level + 5 handler-side) onto the shared `safeCommitAndPr()` helper. The migrations were "behavior-preserving" on the visible axis (commit messages, PR titles, merge mechanics) but multi-agent review caught four trap classes the implementation missed — all generic to any consolidate-N-copies-onto-one-helper migration.

## Solution / Key Insights

1. **A "cosmetic" rename is load-bearing when anything keys on the old name.** The helper derives `ci/content-vendor-drift-<ts>`; the old branch was `ci/vendor-drift-<date>`. The migration comment called this "cosmetic" — but the cron's own open-PR dedup guard searched `head:ci/vendor-drift-`, so the rename silently killed duplicate-PR suppression. Before accepting any rename as cosmetic, grep for the old name across the file AND its consumers (`git grep -n "<old-prefix>"`). The thing that breaks is rarely in the diff hunk that renamed.

2. **Swapping a THROWING primitive for a NON-THROWING one changes loop/retry semantics, not just error formatting.** The old `spawnGitChecked` threw → Inngest step failed → retries + loop halt + red heartbeat. The non-throwing helper returns a result → the per-cluster loop CONTINUES past a failed cluster, carrying its unstaged residue (applied diff + promotion-log row) into the next cluster's commit, and the heartbeat stays green. Fixes: explicit worktree reset (`git reset --hard && git clean -fd`) on non-committed exits; documented monitoring-semantics change in the ADR. When migrating callers onto a non-throwing contract, enumerate every behavior the THROW was load-bearing for: retries, loop halts, heartbeat color, residue cleanup.

3. **A fallback rung that recovers successfully still needs a Sentry mirror.** `direct` merge fails → arm auto-merge succeeds → run "succeeds" — but the PR is now parked in the armed-auto-merge state where a later conflict disarms silently (the #5138 stale-PR class). The legacy code mirrored every merge failure; the consolidated ladder initially mirrored only both-rungs-failed. `cq-silent-fallback-must-mirror-to-sentry` applies to PARTIAL fallbacks too: any rung transition that changes the run's risk posture is reportable even when the run continues.

4. **Helper-side claims ("comments on the scheduled issue") must be verified against each NEW caller's actual environment.** `commentOnScheduledIssue` filters issues by `scheduledIssueLabel`; the 5 pure-TS pipelines passed their Sentry monitor slug, which no GitHub issue ever carries — the comment channel was structurally dead for the whole cohort and the runbook's "green monitor + no comment = healthy" inference became unsound. When a helper's observability contract depends on caller-side state (a label existing, an issue being created), each migration must verify that state exists for that caller — or the helper must loudly report the missing precondition (added op `safe-commit-comment-no-target`).

5. **Same-commit TDD produces vacuous tests for fallback ladders.** Two new tests ("direct falls back to arming", "both rungs fail") passed against the PRE-change helper because the auto-mode default produced the same observable assertions. Anti-vacuity for mode/fallback tests: assert the FIRST rung was *attempted* (the PUT call), not just that the second rung's effect occurred — a negative-only or effect-only assertion cannot distinguish "fell back" from "option ignored."

6. **Source-shape anchor tests are comment-sensitive in both directions.** A helpful code comment mentioning `spawnGitChecked` tripped the parity test's `not.toContain` (false-fail); a comment quoting the `PERSISTENCE:` anchor would let the test pass after the real directive was deleted (false-pass). When writing comments near source-shape-tested files, never quote tested literals; when writing the tests, prefer exported-const `toEqual` assertions over whole-file `toContain` where a const exists.

## Session Errors

1. **Both migration subagents died on a session limit mid-pipeline.** Phase 2's 4-cron migration was complete on disk; Phase 3 had made no edits. — Recovery: verified Phase 2's on-disk work from scratch (tests + tsc, per the resumed-artifacts-are-unverified rule), implemented Phase 3 inline. — **Prevention:** existing partial-artifact recovery pattern (2026-05-15 learning) worked; when a background agent dies, `git status` is the authoritative record of what landed, and the parity/anchor test suite is the cheap verifier.
2. **Orphan shell suite failed the test-all exit gate** (`vendor-drift-workflow.test.sh` asserted the moved `check-runs` literal). — Recovery: updated the suite to assert the new `safeCommitAndPr` shape. — **Prevention:** the work skill's full-suite exit gate exists precisely for this; when deleting/moving a literal, `grep -rln "<literal>" plugins/soleur/test/ scripts/` finds shell-side consumers vitest never sees.
3. **ADR-053's heading said ADR-051** (pre-existing, PR #5096), making next-free-number verification confusing. Five historical duplicate ADR numbers also exist (027, 030, 031, 033, 038). — Recovery: fixed the heading inline; verified numbering by FILENAME (`ls | sort -V`), which is the authoritative key. — **Prevention:** derive next-ADR-number from filenames, never headings.
4. **Two of my own artifacts tripped the PR's new grep gates** (helper header comment carried `MANDATORY FINAL STEP`; a new comment carried `spawnGitChecked`). — Recovery: reworded both. — **Prevention:** after adding a `not.toContain(X)` invariant, grep your OWN diff for X before running the suite.
5. **Bash CWD drift** (vitest EXIT=127, ugrep ENOENT from a non-persisted `cd`). — Recovery: explicit `cd <abs> && cmd` chains. — **Prevention:** already a documented trap; the discipline is per-call absolute `cd` chains in worktree pipelines.
6. **Edit-tool read-before-edit failures + a perl multiline mismatch.** — Recovery: Read then Edit; re-read exact text. — **Prevention:** one-off friction; Read the exact region before structural edits in files not yet loaded.

## Prevention (generalized)

When consolidating N near-identical code copies onto one parameterized helper:

- Grep every old artifact NAME (branch prefixes, step IDs, check names) for consumers before declaring renames cosmetic.
- List what the old code's THROWS were load-bearing for (retry, halt, cleanup, monitor color) and re-provide each explicitly.
- For each new caller, verify the helper's observability preconditions exist in that caller's world (labels, issues, env).
- For mode/option tests, assert the attempted FIRST action, not just the fallback's effect.

## Tags

category: integration-issues
module: web-platform/inngest
refs: #5111, #5133, #5091, #5026, #5138, #5139, ADR-054
