# Tasks: Preflight Lockfile Consistency Check

**Plan:** [2026-04-05-feat-preflight-lockfile-consistency-plan.md](../../plans/2026-04-05-feat-preflight-lockfile-consistency-plan.md)
**Issue:** #1532
**Branch:** preflight-v2-1532

## Phase 1: Implementation

### 1.1 Add Check 3: Lockfile Consistency to SKILL.md

- [ ] Add "Check 3: Lockfile Consistency" section after Check 2 in `plugins/soleur/skills/preflight/SKILL.md`
- [ ] Step 3.1: Detect lockfile changes via `git diff --name-only origin/main...HEAD -- '*/bun.lock' '*/package-lock.json' 'bun.lock' 'package-lock.json'`
- [ ] Step 3.2: Extract unique directories from diff results
- [ ] Step 3.3: For each directory, check if both `bun.lock` and `package-lock.json` exist (dual-lockfile test)
- [ ] Step 3.4: If dual-lockfile and only one lockfile in diff, report FAIL with directory and missing file
- [ ] Update Phase 1 header ("four validations" instead of "three")
- [ ] Update Phase 2 aggregation table with Lockfile Consistency row

### 1.2 Update skill description

- [ ] Update YAML frontmatter `description:` to mention lockfile validation

## Phase 2: Validation

### 2.1 Verify SKILL.md structure

- [ ] Confirm Check 3 follows the same pattern as Check 1 and Check 2 (step numbering, result format)
- [ ] Confirm Phase 2 table includes all 4 checks
- [ ] Run `npx markdownlint-cli2 --fix` on modified SKILL.md

### 2.2 Component test

- [ ] Run `bun test plugins/soleur/test/components.test.ts` to verify skill description stays under budget
