# Learning: shared-mutable-dir test fixture race — fix producer-side, not consumer-side

## Problem

`scripts/test-all.sh webplat` intermittently failed locally with
`ENOENT: no such file or directory, open '.../supabase/migrations/zzz_unmerged_gate_<hex>.sql'`
while **main CI stayed green** (#4957).

Root cause: `run-migrations-unmerged-gate.test.ts` wrote a synthetic
`zzz_unmerged_gate_<hex>.sql` fixture into the **real**
`apps/web-platform/supabase/migrations/` dir (the SUT's `*.sql` glob roots there)
and `unlinkSync`'d it in `afterAll`. Four sibling suites
(`dsar-worm-guc-sites`, `dsar-message-redact-fields-sweep`, `migration-rpc-grants`,
`dsar-allowlist-completeness`) `readdirSync` + `readFileSync` that same dir. When
the local unsharded `vitest run` co-located the producer and a reader in one
process tree, the reader listed the fixture, the producer's `afterAll` deleted
it, and the reader's `readFileSync` hit ENOENT.

## Solution

**Producer-side elimination, not a consumer-side guard.** There was exactly ONE
writer and FOUR readers, so removing the single write surface fixes all readers
(current + future) at once; a `readdir` filter on one reader would leave three
racing.

1. Added an opt-in seam to `run-migrations.sh`:
   `MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"`
   — `:-` default is byte-identical for every prod/CI caller (none set the var).
2. The gate test now stages a temp copy of the real dir
   (`mkdtempSync` + `cpSync(real, temp, {recursive:true})`), writes the synthetic
   fixture into the **temp** dir, and passes `RUN_MIGRATIONS_TEST_DIR=<temp>` to
   the SUT. The real dir is never written again.
3. The `git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`
   gate predicate stays anchored to the **canonical repo path** (basename-only
   lookup), so a temp-dir-only `zzz_*` file still trips the gate — the test's
   three contracts are preserved.

## Key Insight

- **CI-green / local-red asymmetry is a sharding artifact, not a flaky test.**
  Sharded CI (`VITEST_SHARD`) splits producer and readers across processes that
  never co-execute; the unsharded local full-suite is the only place they race.
  When a test passes in isolation and in CI but fails in the local full suite,
  suspect a shared-mutable-filesystem surface, not the test logic.
- **`isolate: true` does not isolate the filesystem.** Per-file module-graph /
  process isolation is irrelevant to a shared on-disk directory; forked workers
  share the real FS. The fix must remove the shared write surface.
- **Pick the lever with the smallest fan-out.** 1 producer fixing 4 readers beats
  4 consumer guards that must be re-applied to every future reader.
- **Test-scoped env-override name, not a generic one.** `RUN_MIGRATIONS_TEST_DIR`
  (not `MIGRATIONS_DIR`) is collision-proof against a same-named secret a future
  Doppler config might inject via `doppler run` into the prod migrate step.
- Precedent for the temp-dir staging idiom already existed in-repo:
  `apps/web-platform/test/legal-doc-shas-guard.test.ts` (`mkdtempSync` + `cpSync`
  + `rmSync`). See also [[cq-test-fixtures-synthesized-only]] and the
  write-boundary discipline.

## Session Errors

1. **Planning subagent could not spawn nested Task agents** — `plan-review` /
   `deepen-plan` fan-out degraded to in-context self-review.
   Recovery: self-review covered the same halt-gates + verify-the-negative pass.
   Prevention: environmental constraint (nested-subagent spawn unavailable);
   already handled by the plan skill's graceful degradation — no workflow change.
2. **`git diff main...HEAD` returned stale-ref noise** — local `main` ref lagged
   `origin/main`, listing ~50 unrelated already-merged files.
   Recovery: re-diffed against `origin/main` (the branch's real base).
   Prevention: already covered by the work-skill bare-repo stale-ref guard; use
   `origin/main...HEAD` (three-dot) for scope checks in a bare-repo worktree.

## Tags
category: test-failures
module: apps/web-platform/test/scripts
