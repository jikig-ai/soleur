# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3424-pdf-extract-tests/knowledge-base/project/plans/2026-05-07-fix-pdf-text-extract-tests-node-version-3424-plan.md
- Status: complete

### Errors
None. User-Brand Impact gate (deepen-plan Phase 4.6) passed — section present, threshold `none` with non-empty reason, diff scoped to `apps/web-platform/test/**` (no sensitive-path match). Network-Outage gate (Phase 4.5) did not trigger (no SSH/connectivity keywords).

### Decisions
- Root cause is operator-side Node-version drift, not a code bug. Verified live: pdfjs-dist@5.4.296 calls `process.getBuiltinModule` at `legacy/build/pdf.mjs:5465`, which lands in Node 22.3 / 20.16. Operator Node v21.7.3 → import throws → all 8 assertion failures resolve to `lazy_import_failed`. CI on Node 22 passes 9/9 in 4.9s.
- Reject both strategy (A) "make extractor surface lazy_import_failed in tests" and (B) "widen test assertions to accept lazy_import_failed." Both lie about system state. Adopted strategy (C): an engine-floor guard at the top of the test file using `describe.skipIf` + `process.env.CI` escalation (skip-with-diagnostic in dev, throw-with-diagnostic in CI).
- Empirically validated reporter shapes for both `throw`-in-`beforeAll` and `describe.skipIf` before flipping the strategy from throw (original draft) to skipIf+CI-bifurcation (deepened). The bifurcated model preserves operator UX (no false red on local Node 21) AND CI safety (no vacuous green on misconfigured runner). Matches existing `byok.integration.test.ts` / `mu1-integration.test.ts` precedent.
- Production extractor unchanged. Verified via `git log -p apps/web-platform/server/pdf-text-extract.ts`: lazy-import branch is unchanged across #3338 → #3353 → #3384, contradicting the issue body's "Likely the lazy-import path was changed" hypothesis. Reconciliation row added.
- Phase 2 (shared setup file) downgraded to explicit non-goal — the only test exercising real pdfjs is the one being fixed; every other PDF-touching test mocks at the function boundary. YAGNI applied.
- 30s timeout sentinel placed on the `MAX_PAGES` 600-page case only (per issue AC); follow-up issue scoped for the 2026-04-18 learning's "Promote to enforcement" prescription (operator-side `.nvmrc` honor in `/work` Phase 0).

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh CLI (issue view, label list, pr view --json mergedAt for #3338/#3353/#3384/#3421)
- vitest probes (Node 21 vs Node 22 reporter shape verification, both throw and skipIf models)
- Live verification of `apps/web-platform/node_modules/pdfjs-dist/package.json` engines and `legacy/build/pdf.mjs:5465` call site
- `git log -p apps/web-platform/server/pdf-text-extract.ts` for cross-PR cause reconciliation
- Cross-reference of `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md`
