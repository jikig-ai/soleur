# Session State

## Plan Phase
- Plan file: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-drain-seo-aeo-2026-04-21/knowledge-base/project/plans/2026-04-22-refactor-drain-seo-aeo-2026-04-21-plan.md`
- Status: complete
- Draft PR: https://github.com/jikig-ai/soleur/pull/2794

### Errors
None

### Decisions
- Eleventy output is `_site/` not `dist/` — corrected across all acceptance criteria and drift-guard assertions.
- Reconciled #2711 path drift: layout is `docs/_includes/blog-post.njk`; photo asset is `docs/images/jean-deruelle.jpg` (passthrough-copied).
- #2707 re-scoped from "add JSON-LD" to "add visible FAQ matching existing JSON-LD". Pricing already has FAQPage JSON-LD; audit gap is the missing visible `<details>` section. Drift-guard test asserts visible-count == JSON-LD-count.
- #2708 reconciled via Next.js 15 title-template: `{ template: "%s — Soleur Dashboard", default: "Soleur Dashboard — Your Command Center" }` in `apps/web-platform/app/layout.tsx`. Eleventy homepage `seoTitle` already correct.
- #2709 uses `seoTitle` override pattern (mirrors `docs/index.njk`) to fix `<title>` without touching visible `<h1>`. Includes Blog JSON-LD `name` reconciliation.
- #2711 extends existing Person node in `blog-post.njk` JSON-LD with `@id`, `image`, `sameAs`; adds inline author-card DOM, site.json metadata, CSS.
- Drift-guard test is additive: `plugins/soleur/test/seo-aeo-drift-guard.test.ts` with `bun:test`, `beforeAll` Eleventy build, `_site/` assertions.

### Components Invoked
- `skill: soleur:plan` (9-section plan, 7 files-to-edit, 2 files-to-create, 7 implementation phases)
- `skill: soleur:deepen-plan` (8 enhancements — `_site/` correction, Next.js 15 verification, Person schema E-E-A-T shape, test-runner path verification)
