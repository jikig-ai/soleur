# Tasks: CMO Ship Content Gate

**Issue:** #1265
**Plan:** [2026-03-29-feat-cmo-ship-content-gate-plan.md](../../plans/2026-03-29-feat-cmo-ship-content-gate-plan.md)

## Phase 1: Core Implementation

- [x] 1.1 Edit `plugins/soleur/skills/ship/SKILL.md` Phase 5.5 CMO Content-Opportunity Gate
  - [x] 1.1.1 Fix intro text: "two conditional gates" → "three conditional gates" (line 249)
  - [x] 1.1.2 Replace Trigger line (line 253) with flat OR-list: file-path matches + `semver:minor`/`major` label + `feat:` title
  - [x] 1.1.3 Replace Detection line (line 255) to include `gh pr view --json labels,title` check
- [x] 1.2 Edit `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
  - [x] 1.2.1 Add "new user-facing product capabilities that could warrant content amplification or feature announcements" to CMO Assessment Question
- [x] 1.3 Edit `AGENTS.md` line 29
  - [x] 1.3.1 Update CMO content-opportunity gate description: add "or feature signals (`semver:minor`/`major` label, `feat:` title)"

## Phase 2: Validation

- [x] 2.1 Run `npx markdownlint-cli2 --fix` on all changed `.md` files
- [x] 2.2 Verify no adjacent table formatting broken in `brainstorm-domain-config.md`
- [x] 2.3 Review final diff to confirm all three files are consistent
