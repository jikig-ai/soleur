# Tasks: Enforce UX Design and Content Review Gates

**Issue:** #1137
**Plan:** `knowledge-base/project/plans/2026-03-25-fix-enforce-ux-content-gates-plan.md`

## Phase 1: Plan Skill — UX Gate Tightening

- [ ] 1.1 Read `plugins/soleur/skills/plan/SKILL.md` (full file for context)
- [ ] 1.2 Insert brainstorm carry-forward pre-check BEFORE step 3 in "On BLOCKING" section
- [ ] 1.3 After step 3 resolves, record outcome in existing `**Agents invoked:**` or new `**Skipped specialists:**` field

## Phase 2: Plan Skill — Content Review Gate

- [ ] 2.1 Add step 4 to BLOCKING pipeline: check if any domain leader recommended copywriter
- [ ] 2.2 If recommended: invoke copywriter agent, add to `**Agents invoked:**`
- [ ] 2.3 If user declines: add to `**Skipped specialists:**` with reason
- [ ] 2.4 If agent fails: add to `**Skipped specialists:**` with error note, set `Decision: reviewed (partial)`
- [ ] 2.5 Gate also fires on ADVISORY tier when domain leader recommended copywriter

## Phase 3: Plan Skill — Heading Contract Update

- [ ] 3.1 Add `**Skipped specialists:**` field to Product/UX Gate heading contract template
- [ ] 3.2 Update `**Agents invoked:**` examples to include `copywriter` when relevant

## Phase 4: Work Skill — Pre-Implementation Check

- [ ] 4.1 Read `plugins/soleur/skills/work/SKILL.md` (full file for context)
- [ ] 4.2 Add check 9 to Phase 0.5: read Domain Review section
- [ ] 4.3 Check `Decision: reviewed (partial)` → WARN
- [ ] 4.4 Cross-reference domain leader recommendations against `Agents invoked` and `Skipped specialists`
- [ ] 4.5 Missing specialists → FAIL with "Run now" or "Skip with justification" options
- [ ] 4.6 Pipeline mode: auto-invoke missing specialists, WARN on failure (no hard block)

## Phase 5: Verification

- [ ] 5.1 Verify markdown lint passes on both modified files
- [ ] 5.2 Review changes for consistency between plan and work skill field formats
- [ ] 5.3 Run `bun test plugins/soleur/test/components.test.ts` to verify skill description budget
