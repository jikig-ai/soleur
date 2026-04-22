# Learning: multi-agent review catches AEO semantic drift that drift-guard tests accept

## Problem

PR #2794 shipped the 2026-04-21 AEO audit drain (closed #2707+#2708+#2709+#2711). The initial implementation:

1. Added `https://www.linkedin.com/company/jikigai/` to `site.author.sameAs` — a Company URL under a Person's sameAs graph claim.
2. Wrote drift-guard assertions `expect(author.sameAs.length).toBeGreaterThanOrEqual(2)` against a 3-element array — tautologically passes if anyone deletes an entry.
3. Regex-matched `<img src="/images/jean-deruelle.(jpg|png|svg)"` without asserting the file exists in `_site/images/` — a deleted image ships a broken `<img>` and the test still passes.
4. Dropped sentences from FAQ JSON-LD `acceptedAnswer.text` (Q1/Q3/Q5 on /pricing/) that appeared in visible `<details>` — positioning content only humans could read.
5. JSON-LD Person node had `image` + `sameAs` but not `description` or `knowsAbout`, while the visible author card rendered bio and credentials — audience split.
6. New `@id: /about/#jean-deruelle` referenced an anchor that did not exist on `about.njk`.

The 26/26 unit test suite (`plugins/soleur/test/seo-aeo-drift-guard.test.ts`) was GREEN with all six defects present.

## Solution

Ran `/soleur:review` with 10 parallel review agents (8 core + test-design-reviewer + semgrep-sast). Each found a different slice:

- **data-integrity-guardian** — caught the LinkedIn Company URL misuse and both weak-assertion classes.
- **agent-native-reviewer** — character-compared visible vs JSON-LD answer text across 7 FAQ entries and found 3 with dropped sentences.
- **architecture-strategist** — flagged missing `/about/` anchor for the `@id` reference and the unused `%s` title-template slot.
- **pattern-recognition-specialist** — caught BEM `__` convention drift (first uses in a 1594-line flat-hyphen file).
- **performance-oracle** — flagged `existsSync`-only build-skip in test `beforeAll` causing stale `_site/` false-passes.

All six defects fixed inline in 3 commits (`c5eb3f45`, `0719f38e`, `f0f0e1ec`). Drift-guard tightened to assert `sameAs` deep-equality against `site.json` (per `cq-mutation-assertions-pin-exact-post-state`) and to `existsSync` the image file. Test `beforeAll` switched to always-rebuild. Extended drift-guard to cover `apps/web-platform/app/layout.tsx` strings (prevents #2708 regression).

## Key Insight

**Unit tests written from the same mental model as the implementation inherit its blind spots.** The drift-guard test was drafted RED then made GREEN against the same author-written assertions — but semantic errors (Company URL ≠ Person sameAs; visible-vs-JSON-LD sentence parity; dangling `@id`) were invisible to the author at both write-times.

Multi-agent review catches these because each agent comes with a *different* prior:

- `data-integrity-guardian` reads schema.org semantics, not code behavior.
- `agent-native-reviewer` does character-by-character parity checks humans skim past.
- `architecture-strategist` asks "does this ID resolve?" not "does this compile?"

For any PR touching structured data that crawlers consume (JSON-LD, OpenGraph, Microdata, RSS, sitemaps, meta tags), the invariant tests must be complemented by multi-agent review — and the drift-guard assertions themselves must be reviewed for exact-value pinning, not just existence/shape checks.

## Prevention

- **Assertion rigor:** when a test verifies a known-count collection or fixed string, assert the exact value from the config/data source (read `site.json` in the test, diff against it). Existence, `>=`, and `toContain` are traps. Rule `cq-mutation-assertions-pin-exact-post-state` already covers this; the PR drafted two violations in fresh code anyway.
- **Multi-agent review is mandatory for structured-data PRs.** Skipping to QA or ship without `/soleur:review` on a PR that modifies JSON-LD, sitemap generation, or meta tags is a workflow regression. Add to ship Phase 5.5 pre-merge detection if not already gated.
- **Extend drift-guard scope to both surfaces in cross-surface PRs.** The initial test covered Eleventy `_site/` only, missing the Next.js `apps/web-platform/app/layout.tsx` string regression surface. When a PR reconciles two surfaces, the drift-guard must assert against both.
- **SVG asset provenance:** synthesizing a real person's likeness via image models is inappropriate regardless of tool availability. Monogram SVG is the correct automated fallback; hand off real-photo procurement to the owner (#2799 filed).

## Session Errors

Session error inventory: **none detected**. No failed commands, no path confusion, no forwarded errors from plan phase. Clean pipeline execution.

## Tags

category: integration-issues
module: marketing-aeo
prs:
  - "2794"
closes:
  - "2707"
  - "2708"
  - "2709"
  - "2711"
follow-up:
  - "2799"
