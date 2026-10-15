---
title: "Tasks — docs: salvage learnings and planning trail from orphaned feat-10117 draft PR"
date: 2026-10-14
branch: feat-one-shot-salvage-10117-artifacts
plan: knowledge-base/project/plans/2026-10-14-docs-salvage-10117-artifacts-plan.md
lane: cross-domain
---

# Tasks — salvage 10117 artifacts

Source of truth for content: `git show feat-10117-edge-coverage-residuals:<path>`
(branch `1219f7a0`). Never copy from the sibling worktree's checkout or the bare
root. `TS=$(date -u +%Y%m%d-%H%M%S)` is generated ONCE in Phase 0 and reused for
all four archive destinations AND the Phase 1 frontmatter retarget.

## Phase 0 — Setup

- [x] 0.1 Confirm `git rev-parse --show-toplevel` is this worktree and
  `git branch --show-current` is `feat-one-shot-salvage-10117-artifacts`.
- [x] 0.2 `TS=$(date -u +%Y%m%d-%H%M%S)` — capture once; record the value for
  reuse across Phases 1 and 3.
- [x] 0.3 `pgrep -f test-all` — if a battery is running in this worktree, hold
  the `work/SKILL.md` edit (bash incremental-read hazard; the very learning
  being ported).

## Phase 1 — Five learnings (verbatim copies)

- [x] 1.1 `git show feat-10117-edge-coverage-residuals:<path> > <same path>` for
  each of the five learnings:
  - `knowledge-base/project/learnings/test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md`
  - `knowledge-base/project/learnings/test-failures/2026-10-14-c-quoted-names-evade-extension-anchored-list-filters.md`
  - `knowledge-base/project/learnings/workflow-patterns/2026-10-13-plan-review-fold-in-hazards-test-seams-and-quoted-literals.md`
  - `knowledge-base/project/learnings/workflow-patterns/2026-10-13-residual-bundle-brainstorm-rulings-and-packaging.md`
  - `knowledge-base/project/learnings/workflow-patterns/2026-10-14-bash-reads-a-running-script-incrementally-mid-run-edits-corrupt-it.md`
- [x] 1.2 In `…/2026-10-13-plan-review-fold-in-hazards-test-seams-and-quoted-literals.md`,
  retarget the `related_artifacts` entry
  `knowledge-base/project/plans/2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
  → `knowledge-base/project/plans/archive/${TS}-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`.

## Phase 2 — Two bullet ports

- [x] 2.1 `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`:
  insert the branch bullet ("**Never edit a script while a suite is still
  executing it — bash reads a running script incrementally.** …") verbatim
  BETWEEN the `#6760` seat bullet and the PID-namespace bullet (~line 79).
  Extract the line from `git show feat-10117-edge-coverage-residuals:…` by
  anchor grep, not by retyping.
- [x] 2.2 `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md`:
  append the branch bullet ("**A mutation row is vacuous until a fixture
  distinguishes the mutant…**") verbatim as a `## ` section — relocated
  from SKILL.md's tail (the file is at its byte ceiling; see
  decision-challenges).
- [x] 2.3 Do NOT port: the sibling-worktree paragraph variant, the `6.8`
  bullet deletion, or the test-harness-sharp-edges pointer deletion.

## Phase 3 — Planning docs to archive paths

- [x] 3.1 `git show …:knowledge-base/project/brainstorms/2026-10-13-edge-coverage-residuals-brainstorm.md`
  → `knowledge-base/project/brainstorms/archive/${TS}-2026-10-13-edge-coverage-residuals-brainstorm.md`
- [x] 3.2 `git show …:knowledge-base/project/plans/2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
  → `knowledge-base/project/plans/archive/${TS}-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
- [x] 3.3 `mkdir -p knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals`,
  then `git show …:knowledge-base/project/specs/feat-10117-edge-coverage-residuals/{spec.md,tasks.md}`
  → `knowledge-base/project/specs/archive/${TS}-feat-10117-edge-coverage-residuals/{spec.md,tasks.md}`

## Phase 4 — Verification

- [x] 4.1 Verbatim diffs: four learnings + four archive files diff empty against
  `git show feat-10117-edge-coverage-residuals:<path>`; fold-in-hazards differs
  only on the `related_artifacts` line.
- [x] 4.2 Anchor probes: the risk-tier bullet sits between the `#6760` and
  PID-namespace bullets; `tail -1 plugins/soleur/skills/work/SKILL.md` is the
  mutation-vacuity bullet; `git diff origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md`
  (three-dot, merge-base-scoped) shows ONLY the appended bullet.
- [x] 4.3 `bun test plugins/soleur/test/review-tier-parity.test.ts` green; run
  whichever suite the affected-diff selector picks for `work/SKILL.md`
  (expected `plugins/soleur/test/components.test.ts`).

## Phase 5 — PR and post-merge trail

- [ ] 5.1 Draft PR first; body carries `## Changelog` (semver:patch); `Ref`
  prose only for the 10117 arc — no `Closes`/`Fixes`.
- [ ] 5.2 Squash merge after green (full affected battery at ship).
- [ ] 5.3 Post-merge, in order: comment on PR #10190 naming the salvage PR and
  delivery PRs #10237/#10242 → close #10190 unmerged → verify no live-session
  activity (`gh pr view 10190` updatedAt unchanged; sibling worktree
  `status --porcelain` empty) → delete remote branch
  `feat-10117-edge-coverage-residuals` → remove worktree
  `.worktrees/feat-10117-edge-coverage-residuals`.
