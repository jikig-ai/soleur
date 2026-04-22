# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-domain-marketing-drain/knowledge-base/project/plans/2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md
- Status: complete

### Errors
- Non-blocking: `Task` (subagent spawning) tool unavailable in deepen-plan; substituted with direct WebSearch + WebFetch + in-line file reads (3 WebSearch + 6 curl probes + 2 file reads, all parallel).
- Non-blocking: `PreToolUse` security hook flagged `execSync` in a doc snippet (false positive — pseudocode in plan, not source). Rewrote to `Bun.spawn(["npm","run","build"])` (argv array, no shell metacharacters).

### Decisions
- **Marketing site lives in `plugins/soleur/docs/` (Eleventy), NOT `apps/web-platform/` (Next.js).** Issue #2656 mis-stated location; plan corrects via Research Reconciliation table; pinned as Risk #7.
- **Pricing footnote citations: Robert Half + Payscale + Levels.fyi (NOT BLS).** BLS returns HTTP 403 to all curl invocations (Akamai bot-fight); using a citation that fails the pre-merge gate is operationally worse. All three replacement URLs verified 200.
- **`foundingDate: "2026"`** (corrected from initial draft "2025"). Verified via `gh api repos/jikig-ai/soleur` → repo created 2026-01-27.
- **Test runner is `bun:test`** (verified — `plugins/soleur/test/components.test.ts` imports `bun:test`). Plan + tasks pin this; do NOT use vitest.
- **301 over canonical-tag for #2658 CaaS pillar promotion.** Google ignores declared canonicals ~84% of the time when sitemap and canonical disagree; 301 is unambiguous. Drift-guard test 4 explicitly forbids the redirect target page from carrying a canonical-back link.
- **Drift-guard test allowlist must include `knowledge-base/project/plans/` and `specs/`** (in addition to `audits/` and `learnings/`) — this very plan quotes stale numbers as Research Reconciliation evidence; would fail its own test otherwise.

### Components Invoked
- soleur:plan
- soleur:deepen-plan
- WebSearch x4 (schema.org Organization JSON-LD; 301 vs canonical; Eleventy meta-refresh; Robert Half/Payscale alternatives)
- gh api (`repos/jikig-ai/soleur` for foundingDate; multiple `gh issue view` for verbatim bodies)
- curl x6 (BLS x3 → 403; Robert Half + Payscale + Levels.fyi → 200)
- In-line file inspection (8 reads): index.njk, pricing.njk, vision.njk, base.njk, stats.js, agents.js, what-is-company-as-a-service.md, components.test.ts, brand-guide.md, pageRedirects.js
