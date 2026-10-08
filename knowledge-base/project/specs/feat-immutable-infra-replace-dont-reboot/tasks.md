# Tasks: replace-don't-reboot in shipped skills, agents and gates (#9750)

Plan: `knowledge-base/project/plans/2026-10-08-feat-replace-dont-reboot-in-shipped-skills-plan.md`

## Phase 1: Setup

- 1.1 Fetch `origin/main` and record the baseline: `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.
- 1.2 Record current byte sizes of `plan/SKILL.md` (119996 B, ceiling 120000) and `review/SKILL.md` (475596 B, ceiling 477000).

## Phase 2: Core Implementation

- 2.1 Edit `plugins/soleur/agents/engineering/infra/terraform-architect.md`.
  - 2.1.1 Insert `## Replace, Don't Reboot` between `## Review Protocol` and `## State Management Advisory` using the exact text in plan Phase 1.
  - 2.1.2 Confirm there is no plan or runbook review bullet in the section.
- 2.2 Edit `plugins/soleur/agents/engineering/infra/platform-strategist.md`.
  - 2.2.1 Add the one Reproducibility First bullet after "Always IaC for configuration"; do not cite "§4".
- 2.3 Edit `plugins/soleur/skills/plan/SKILL.md` §2.8.
  - 2.3.1 Replace the `### Apply path` bullet with the exact new text in plan Phase 2.
  - 2.3.2 Run the ratchet lint; if it reds, trim an equal number of bytes inside that same line. Never raise the ceiling.
- 2.4 Edit `plugins/soleur/skills/plan/references/plan-sharp-edges.md`.
  - 2.4.1 Append the Phase 3a bullet at the end of the file; keep it at most 1100 B.
- 2.5 Edit `plugins/soleur/skills/review/SKILL.md`.
  - 2.5.1 Extend the downtime bullet trigger list with the plan-or-runbook case.
  - 2.5.2 Append the clause inside the quoted `MUST instruct` text; total added bytes under 400.

## Phase 3: Testing and verification

- 3.1 Run the plan's AC1-AC5 greps (after committing).
- 3.2 Run `python3 scripts/lint-skill-body-budget.py --base origin/main` (exit 0).
- 3.3 Run `bun test plugins/soleur/test/components.test.ts`.
- 3.4 Run `npx markdownlint-cli2` on the plan, spec, tasks and the five edited plugin files.
- 3.5 Confirm no `description:` line changed and no `hcloud_` token was added under `plugins/soleur`.

## Phase 4: Spec and issue hygiene

- 4.1 Confirm the spec matches the shipped text (FR1-FR5).
- 4.2 PR body: `Closes #9750`, with a note that the deploy-time half is tracked in #9764.
