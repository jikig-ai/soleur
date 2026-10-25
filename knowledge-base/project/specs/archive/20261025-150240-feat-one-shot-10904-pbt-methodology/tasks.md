# Tasks — content: "A Property Test That Cannot Fail Teaches Nothing" PBT-guidance spoke (#10904)

Plan: `knowledge-base/project/plans/2026-10-25-content-pbt-methodology-spoke-plan.md`
Branch: `feat-one-shot-10904-pbt-methodology`
PR: (to be opened by the work phase)

## Phase 1 — Draft + image

- [x] 1.1 Write founder sentence + outline working notes per the plan's Draft Spec
- [x] 1.2 Write `plugins/soleur/docs/blog/2026-10-29-property-test-cannot-fail-teaches-nothing.md`
      (frontmatter per Draft Spec; 1,500–2,000-word General-register body; FAQ + parity
      JSON-LD; retro-link to the arc post; one closing GitHub link to the post-mortem
      learning doc; waitlist CTA; zero code blocks — the vacuous example renders in prose)
- [x] 1.3 Generate `plugins/soleur/docs/images/blog/og-property-test-cannot-fail-teaches-nothing.png`
      via Pillow (1200×630, `#1a1a1a`/`#c4a35a`, textless dots-through-gap motif);
      fallback: reuse `og-agentic-verification-checklist.png` rather than omit `ogImage`

## Phase 2 — Site wiring

- [x] 2.1 Append `"2026-10-29-property-test-cannot-fail-teaches-nothing" = "property-test-cannot-fail-teaches-nothing"`
      to `local.blog_redirect_pairs` in `apps/web-platform/infra/seo-bulk-redirects.tf`
- [x] 2.2 Add the one-sentence spoke link at the end of the arc post's "The test that
      found a bug on day one — and the example that could never fail" section
      (`2026-10-23-agentic-verification-checklist-shipped.md`)

## Phase 3 — Distribution + calendar

- [x] 3.1 Write `knowledge-base/marketing/distribution-content/2026-10-29-property-test-cannot-fail-teaches-nothing.md`
      (`status: draft`, `issue_reference: "#10904"`, channels `x, bluesky, discord,
      linkedin-personal`; sections `## X/Twitter Thread` / `## Bluesky` / `## Discord` /
      `## LinkedIn Personal`; labeled tweets ≤ 280 chars; the vacuous-example sequence
      is the payload; absolute soleur.ai URLs with utm params; no Liquid markers)
- [x] 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md` via the
      campaign-calendar skill (--headless)

## Phase 4 — Verification

- [x] 4.1 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` → 0
- [x] 4.2 `bash scripts/lib/validate-tweet-draft.sh <distribution file>` → 0
- [x] 4.3 `npm run docs:build` clean
- [x] 4.4 `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
      plugins/soleur/test/marketing-content-drift.test.ts
      plugins/soleur/test/distribution-content-format.test.ts
      plugins/soleur/test/blog-audience-contract.test.ts` green
- [x] 4.5 `bash scripts/validate-blog-links.sh` Guard-1 parity green
- [x] 4.6 Body word count inside [1500, 2000]
- [x] 4.7 Date coherence: filename date == frontmatter `date:` == redirect-pair key (AC11)
- [x] 4.8 Read-through claim check: every number traces to the cited sources; sequence
      honesty (tautology → first fix still admitted a do-nothing program → third
      property closed it); no jargon-scan blind spots
- [ ] 4.9 PR body line 1 carries the merge-mutates-production answer (AC12) — deferred to
      the ship phase; this work session does not push or open the PR (parent pipeline owns it)

## Ship notes

- Stage only this feature's paths (sibling-session rule); never `git add -A`.
- No push in the planning phase; work phase ships via the normal pipeline.
- Sibling-story boundary: reference the first-test-found-a-bug story in one line only
  (it belongs to the unwritten #10636 post); do not retell the bug hunt.
