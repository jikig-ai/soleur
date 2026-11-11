---
plan: knowledge-base/project/plans/2026-11-11-feat-spec-kit-ingestion-plan.md
issue: 12531
branch: feat-12531-spec-kit-ingestion
lane: cross-domain
---

# Tasks: Spec Kit directory intake (#12531)

Ref the plan for rationale. The feature spec's FR2, FR4, FR5, and TR2 are already aligned. Do not revert them. Do not edit either skill `description:` field. Do not edit `plugins/soleur/skills/one-shot/SKILL.md`. Do not run `gh pr edit` for the provenance trailer. `soleur:ship` writes that trailer as the last paragraph of the PR body.

## Phase 1: Setup

- [ ] 1.1 Write `plugins/soleur/test/spec-kit-intake.test.sh` from the plan's Test Scenarios, with synthesized fixtures under `mktemp`. Install the `EXIT` trap before `mktemp`. Do not `source` `test-helpers.sh`. Bound the FIFO case with `timeout`, then `gtimeout`, then the bare pattern, around the test only.
- [ ] 1.2 The over-cap row has a same-input positive control at exactly 1048576 bytes. Sentinel names stay `SENTINEL-OUTSIDE`, `SENTINEL-RESEARCH`, `SENTINEL-PLAN-ONLY`, `SENTINEL-FM`, `SENTINEL-DIRLINK`, `SENTINEL-CONTRACT`, and `SENTINEL-LINK`.

## Phase 2: Core Implementation

- [ ] 2.1 Write `plugins/soleur/scripts/spec-kit-intake.sh` until `plugins/soleur/test/spec-kit-intake.test.sh` exits 0. The shell file is the probe wrapper. Containment is `python3`: open each lexical component from the parent directory fd with `O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_NONBLOCK`, then open `spec.md`, `plan.md`, and `tasks.md` from that directory fd with `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`. `fstat` before any read. Read at most `st_size` and never more than 1048576. The script writes no file and calls no GNU `realpath`, `stat -c`, `readlink -f`, `sha256sum`, or `timeout`.
- [ ] 2.2 `bash plugins/soleur/scripts/spec-kit-intake.sh --probe` prints `spec-kit-intake: ok` and exits 0.
- [ ] 2.3 In `plugins/soleur/skills/brainstorm/SKILL.md`, add the intake under `## Feature Description` before the empty-description question, before the worktree `cd`, and before the clear-requirements shortcut. Phase 3.6 step 4 does not generate a second spec when a projected body exists. Step 5 writes that body only when the branch spec is absent. Both clear-requirements arms pass the absolute directory captured before the `cd`. Stay inside the measured byte ceiling.
- [ ] 2.4 In `plugins/soleur/skills/plan/SKILL.md`, remove the duplicate knowledge-base list and add the spec-kit intake line before step 4. Write `plugins/soleur/skills/plan/references/spec-kit-intake.md` with the full procedure. `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.

## Phase 3: Testing

- [ ] 3.1 `bash plugins/soleur/test/spec-kit-intake.test.sh` exits 0.
- [ ] 3.2 After the test file is tracked, `scripts/lint-orphan-test-suites.sh` exits 0. No new `AFFECTED_*_PATHS` row.
- [ ] 3.3 Confirm the feature spec still refuses every symlink, including a same-directory link, and the projected appendix lists heading names without copying section bodies.
