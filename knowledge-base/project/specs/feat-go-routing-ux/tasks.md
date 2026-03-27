# Tasks: Go Routing UX

**Plan:** [2026-03-27-feat-go-routing-ux-plan.md](../../plans/2026-03-27-feat-go-routing-ux-plan.md)
**Issue:** #1188

## Phase 1: Implementation

- [ ] 1.1 Read current `plugins/soleur/commands/go.md`
- [ ] 1.2 Replace Step 2 (Classify Intent) with 3-intent table: fix, review, default→brainstorm
- [ ] 1.3 Remove Step 3 (Confirm Route) entirely
- [ ] 1.4 Merge Step 4 into Step 2 — route directly after classification
- [ ] 1.5 Add AskUserQuestion fallback for truly ambiguous intent only

## Phase 2: Validation

- [ ] 2.1 Run `bun test plugins/soleur/test/components.test.ts` to verify structural tests pass
- [ ] 2.2 Verify file stays under 60 lines (thin router constraint)
