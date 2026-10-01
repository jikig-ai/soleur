# Learning: GitHub's merge ref runs your PR's own defect against it — and the fix class has three surfaces, not one

## Problem

PR #8151 bundles fixes for #8091 (hosted ship merge-base failure on shallow clones), #8116 (GitHub reports `knowledge-base/INDEX.md` CONFLICTING because the `kb-index` merge driver is local-only), and #8117 (markdown-lint sandbox GC race). After the branch synced with main, CI went red twice in ways the local suite could not see:

1. `rename-guard` failed: our merge commit's **first-parent** diff re-attributed main's already-vouched rename `plan/SKILL.md → plan/references/plan-sharp-edges.md` (from merged PR #8301) to our PR's range. The guard scans per-commit (`--diff-merges=first-parent`), so any branch created before a rename lands that later merges main re-trips it. Filed upstream as #8348.
2. `test-scripts (2/3)` failed at **AC17**: `generate-kb-index.sh --check` runs against `refs/pull/N/merge` — GitHub's driverless merge — which produced an `INDEX.md` carrying main's two new entries but our stale `Total files: 6653` header (real count 6655). Locally `--check` was green on the same commit; only the merge ref was stale. Filed as #8370 — the #8116 defect class expressing on the CI-check surface rather than the mergeable-state surface.

## Solution

- For the state side (#8116): `sync-pr-behind.sh` and both Phase-7 poll loops now treat `DIRTY` as a sync candidate **gated on `git merge-tree --write-tree origin/main HEAD` exit code** — clean (rc=0) rewrites to `OPEN BEHIND` and falls through to auto-sync; nonzero exits 6 / dirty-exits for manual resolution. The admin-merge hatch stays BEHIND-only.
- For the shallow clone (#8091): `git fetch --unshallow --no-tags origin` after `gh pr checkout`, tolerating the measured `fatal: --unshallow on a complete repository` on full clones, then always `git merge-base origin/main HEAD`.
- For the CI surfaces above: the `secret-scan-allow-rename` label (the same escape #8301 used) cleared rename-guard; merging current main + regenerating `INDEX.md` made our committed index a superset of main's, so the merge-ref textual merge yields a fresh artifact.

## Key Insight

**A fix for "GitHub can't run our merge driver" has at least three surfaces**: the mergeable bit (`mergeStateStatus`/`CONFLICTING`), the merge-ref CI tree (any check that reads merged generated artifacts — here AC17 freshness), and the guard layer (rename-guard's first-parent attribution). Verifying only the first while the second and third still fire is how a correct fix ships red CI on its own PR.

Two instrument-level traps surfaced while diagnosing:

- `git log BASE..HEAD -- <path>` prints **nothing** for changes that arrived via merge commits — per-path log filtering skips merge diffs. An empty result proved nothing; `git log --follow <path> origin/main` located the rename's true origin.
- `git diff --name-only --diff-filter=U` on a `merge-tree`-detected conflict is **guaranteed empty** — merge-tree never touches the worktree, so no unmerged paths exist. The real conflicted paths live in merge-tree's discarded stdout (`^CONFLICT ` lines). Three surfaces in this diff carried the vacuous diagnostic; all now emit merge-tree's own output.

## Session Errors

1. **Ran `npx vitest` on a `bun:test` file** — collection failed with `Cannot find package 'bun:test'`. Recovery: `bun test <file>`. Prevention: check the test file's import (`bun:test` vs `vitest`) before choosing a runner; this repo mixes both.
2. **Ran `npx tsc` at repo root** — no root typescript package; npx printed an install suggestion and exited 0, which *masks a skipped typecheck*. Recovery: `apps/web-platform/node_modules/.bin/tsc --noEmit`. Prevention: run the package's own `typecheck` script from its directory; treat npx's "add TypeScript" prompt as a failed check, not a pass.
3. **`git log -- path` misread** — empty range output led to a momentary "rename not in range" conclusion before remembering merge diffs are skipped. Recovery: `--follow` against `origin/main`. Prevention: for "when did this path change" questions, never trust per-path `git log` over a range containing merge commits.
4. **Pre-commit flock serialization** — two ~1h waits behind `test-all.lock` (flock `-w 3600` vs holders on `-w 14400`). Recovery: patience + retry. Prevention: tracked upstream as #7697 (wedged-holder lock); the queue cost is inherent until that lands.
5. **rename-guard CI failure** — merge-back re-attribution, fixed by the `secret-scan-allow-rename` label. Prevention: tracked as #8348; until it lands, expect the label tax on any branch that merges main after a vouched rename.
6. **AC17 merge-ref failure** — fixed by main merge + `generate-kb-index.sh` re-run. Prevention: tracked as #8370; mitigation until fixed is "regen INDEX.md immediately before push when the diff touches it".

## Tags

category: test-failures
module: ci-merge-machinery
issues: #8091 #8116 #8117 #8151 #8348 #8370 #7697
