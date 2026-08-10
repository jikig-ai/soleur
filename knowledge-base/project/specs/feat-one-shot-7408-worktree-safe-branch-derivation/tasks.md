# Tasks — feat-one-shot-7408-worktree-safe-branch-derivation

Derived from the finalized (post-plan-review) plan: `knowledge-base/project/plans/2026-08-10-fix-git-worktree-safe-branch-derivation-plan.md`. `[R#]` tags map to that plan's §Plan Review Revisions.

`Closes #7408`

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Confirm `_validate_worktree_name`'s regex is `^[A-Za-z0-9._-]+$` in `.claude/hooks/lib/session-state.sh`, **and** that it separately rejects `.` and `..`. The regex alone is not the whole validator.
- [ ] 0.2 Read `scripts/test-all.sh`'s discovery globs; confirm `plugins/soleur/test/*.test.sh` is discovered.
- [ ] 0.3 Re-read `plugins/soleur/test/test-helpers.sh` (`assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists`, `print_results`).
- [ ] 0.4 Read `plugins/soleur/test/worktree-manager-sandbox-tmp-sweep.test.sh` for the **source-the-script** harness pattern. [R9]
- [ ] 0.5 `git fetch origin`; confirm PR #7407 has not merged. **Land #7407 first, then rebase.** Record the base SHA.

## Phase 1 — RED: regression suite (before any source change)

Create `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh`.

- [ ] 1.1 Fixture: seed repo → `git clone --bare` (shape from `worktree-manager-feature-spec-dir.test.sh`).
- [ ] 1.2 **Reaper arms must `source` the script and call `cleanup_orphan_worktree_dirs` directly** — there is no CLI verb for it. Source inside the fixture repo (the preamble `exit 3`s outside one, and sourcing imports `set -euo pipefail`). [R9]
- [ ] 1.3 A1 — `create ci/rule-metrics` → `.worktrees/ci-rule-metrics`; assert `test -d .worktrees/ci-rule-metrics && test ! -e .worktrees/ci`. Do **not** use `find -maxdepth 2`. [R8]
- [ ] 1.4 A2 — created ref is exactly `ci/rule-metrics`.
- [ ] 1.5 A3 — lease key == directory basename, passes `_validate_worktree_name`, lease file exists.
- [ ] 1.6 A4 — slash-branch worktree with an uncommitted file survives the reaper, invoked from **outside** it.
- [ ] 1.7 A5 — `feature a/b`: `basename(spec_dir) == basename(worktree_path) == safe_branch` (self-consistency only). [R6]
- [ ] 1.8 A6 — `create feat-plain` unchanged vs `origin/main` behavior.
- [ ] 1.9 A7 — **M1 mutant**: revert the derivation **and** the descendant guard → A1 and A4 must FAIL. [R7]
- [ ] 1.10 A8 — descendant guard: pre-built nested layout (built with a **direct `git worktree add`**, since the fixed manager can no longer produce one) survives the reaper.
- [ ] 1.11 A8b — **M2 mutant**: revert only the descendant guard, keep the producer fix → A8 must FAIL. [R7]
- [ ] 1.12 A9 — boundary: `.worktrees/ci-foo` registered + `.worktrees/ci` a true orphan → `ci` **IS** reaped (proves path-boundary, not string-prefix, matching).
- [ ] 1.13 Run the suite; it MUST fail on A1/A4/A5 before Phase 2 (`cq-write-failing-tests-before`).

## Phase 2 — GREEN: shared derivation helper

- [ ] 2.1 Add `_safe_worktree_name` near the other private helpers. **Pure transform, three lines, never returns non-zero.** [R1]
- [ ] 2.2 FR4 (observability only): in `_acquire_worktree_lease`, split the existing marker's `reason=` — `name-not-keyable` when `_validate_worktree_name` rejects, `rc-nonzero` otherwise. **No abort.** [R1]

## Phase 3 — GREEN: route producers through the helper

Cite content anchors, never line numbers — #7407 shifts every line below ~650. [`cq-cite-content-anchor-not-line-number`]

- [ ] 3.1 `create_worktree`: derive `safe_branch` once; use it for `worktree_path` and both lease keys (`create`, `create-reentry`). **Leave `git worktree add … -b "$branch_name"` raw.**
- [ ] 3.2 `create_for_feature`: same for `worktree_path`, `spec_dir`, and both lease keys. Leave `-b "$branch_name"` raw. **Also update the trailing `echo` that prints the spec path**, or it will disagree with what was created.
- [ ] 3.3 `switch_worktree`: slugify the argument to resolve the path; **derive the lease key as `basename "$worktree_path"`**, not from the argument — that is the invariant `cleanup_merged_worktrees` actually reads back. Preserve the raw input in the not-found error message.
- [ ] 3.4 `cleanup_merged_worktrees`: replace the inline `tr` with the helper. Behavior-identical **because the helper is a pure transform** — this is only true given 2.1. [R1]
- [ ] 3.5 `create_worktree` re-entry arm: pass `$safe_branch` to `switch_worktree`, not the raw name. [R5]
- [ ] 3.6 Leave `heal_stale_branch` raw — it operates on refs only.
- [ ] 3.7 **Not changed:** `copy_env_to_worktree` (pure consumer, no refname caller). [R4]

## Phase 3b — GREEN: reaper descendant guard

- [ ] 3b.1 In `cleanup_orphan_worktree_dirs`, inside the `[[ -z "${registered_paths[$dir]:-}" ]]` block: skip when any registered path matches `"$dir"/*`.
- [ ] 3b.2 **The `/` is load-bearing.** `"$dir"*` would treat `.worktrees/ci-foo` as a descendant of `.worktrees/ci` and self-match every directory — turning a fail-closed reaper into a no-op. Do **not** copy `cleanup_merged_worktrees`'s `[[ "$PWD" == "$worktree_path"* ]]`, which has this bug.
- [ ] 3b.3 Quote `"$dir"` so a glob metacharacter in a directory name is not treated as a pattern.
- [ ] 3b.4 Emit `SOLEUR_ORPHAN_SKIP_DESCENDANT dir=… registered=… reason=holds-live-worktree` and reference the SKILL.md remediation.
- [ ] 3b.5 **Not added:** `$PWD` guard — unreachable given the registered + `.git` chain. [R3]

## Phase 4 — Documentation

- [ ] 4.1 `plugins/soleur/skills/git-worktree/SKILL.md` §Sharp Edges: slash-bearing branch → hyphenated directory; ref keeps its slashes; basename is the lease key. Include a **runbook** for a pre-existing nested worktree (`git worktree list --porcelain` → `git worktree move` → verify), referenced from 3b.4's warning.
- [ ] 4.2 Append one idiom bullet to `ADR-099-git-surface-topology.md`'s existing "Idiom rules" list. Append at the **end** (PR #7407 also edits this file). State the rule as *the lease key is the resolved directory basename*.

## Phase 5 — Verification

- [ ] 5.1 `bash scripts/test-all.sh` from a worktree; record the pass count and confirm the new suite is discovered.
- [ ] 5.2 `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`. (No `shellcheck` job exists in `.github/workflows/` — do not gate on one.)
- [ ] 5.3 Walk AC1–AC13.
- [ ] 5.4 PR body: `Closes #7408`; name the untouched fourth transform copy at `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`; do **not** scope in #7409.

## Deferred (file as issues, do not scope in)

- [ ] D.1 Slug/name collision guard for `create_worktree` **and** `create_for_feature`'s existing-directory arms, with defined behavior for detached HEAD and hollow-shell debris. [R2] Live example on the operator's machine: `.worktrees/fix-6808-heartbeat-wire` is on branch `docs-redaction-fails-open`.
- [ ] D.2 Legacy nested worktrees remain invisible to `list`, `switch`, `copy-env` and `cleanup` (Phase 3b covers only the reaper). Either a migration verb or a documented runbook.
- [ ] D.3 `cleanup_merged_worktrees`'s `[[ "$PWD" == "$worktree_path"* ]]` carries the same missing-`/` prefix bug as 3b.2.
- [ ] D.4 Worktree-creation paths that bypass the manager entirely (`fix-issue/SKILL.md` fallback, `git-worktree/SKILL.md`, `ops-provisioner.md`) run unleased. Nesting is not a risk there (all use flat names), but the "unleased" half of this issue's title is unaddressed for them.
