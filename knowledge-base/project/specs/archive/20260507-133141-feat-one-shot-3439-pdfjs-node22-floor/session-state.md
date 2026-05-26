# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-07-fix-pdfjs-node22-floor-sibling-test-guard-plan.md
- Status: complete (extended post-deepen to also close #3438 per user request)

### Errors
None

### Decisions
- engines.node already pinned by PR #3391 — no package.json change needed.
- Refactor inline guard from PR #3431 into shared helper at apps/web-platform/test/helpers/engines-floor.ts (vitest discovery verified safe).
- Extend describe.skipIf guard to two sibling bundled-server suites named in #3439.
- Add apps/web-platform/.nvmrc (22.3.0) and one-line README pointer.
- Fold in #3438: add direct `lazy_import_failed` test (vi.doMock pdfjs-dist) outside the skipIf block — runs on all Node versions.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh CLI (issue/pr verification: #3439, #3438, #3383, #3431, #3391)
