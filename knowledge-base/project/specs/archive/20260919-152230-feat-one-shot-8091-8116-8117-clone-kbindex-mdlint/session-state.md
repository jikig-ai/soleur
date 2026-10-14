# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8091-8116-8117-clone-kbindex-mdlint/knowledge-base/project/plans/2026-09-14-fix-ship-clone-kbindex-mdlint-plan.md
- Status: complete

### Errors
None. Research, domain, spec-flow, advisor, and plan-review ran in-process (no Task-spawn tool in this harness). Halt gates 4.6–4.11 passed.

### Decisions
- **#8091:** ship-merge-only `git fetch --unshallow origin` after `gh pr checkout` in `event-ship-merge.ts`; keep substrate `--depth=1` (ADR-099). Continue on measured fatal `fatal: --unshallow on a complete repository does not make sense` (exit 128); always then `git merge-base origin/main HEAD`.
- **#8116:** DIRTY-but-locally-clean sync via `git merge-tree --write-tree` (exit-code only), not “stop committing INDEX.md” (ADR-210). Real conflicts still dirty-exit. Admin-merge hatch stays BEHIND-only. Ephemeral clones have no kb-index driver, so hosted Phase 7 still dirty-exits on a true INDEX.md conflict.
- **#8117:** `git config gc.auto 0` immediately after `git init` in `build_sandbox`.
- Hosted verification does **not** expand trigger-cron (`ship-merge.manual-trigger` is not allowlisted). Pre-merge proof is a hermetic git fixture; post-merge is the next natural `event-ship-merge` run.
- Brand-survival `none` with sensitive-path scope-out: server/inngest edit only deepens an already-authenticated ephemeral clone.

### Components Invoked
- `plugins/soleur/skills/plan/SKILL.md` (`/plan`)
- `plugins/soleur/skills/deepen-plan/SKILL.md` (`/deepen-plan`)
- In-process: repo-research, learnings, spec-flow, scoped advisor, DHH/Kieran/simplicity panel
- `knowledge-base/project/specs/feat-one-shot-8091-8116-8117-clone-kbindex-mdlint/decision-challenges.md`
