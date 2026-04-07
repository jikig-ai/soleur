# Tasks: Update health endpoint comment

Source: `knowledge-base/project/plans/2026-04-07-fix-health-endpoint-comment-plan.md`

## Phase 1: Implementation

- [ ] 1.1 Update comment block in `apps/web-platform/server/index.ts` (lines 30-32)
  - Replace existing 3-line comment with updated wording reflecting dual-purpose design
  - Keep line 29 (`// Health check for deployment`) unchanged

## Phase 2: Verification

- [ ] 2.1 Run `npx tsc --noEmit` in `apps/web-platform/` to confirm no TypeScript errors
- [ ] 2.2 Visual review: confirm comment accurately describes both load balancer and CI gating behavior
