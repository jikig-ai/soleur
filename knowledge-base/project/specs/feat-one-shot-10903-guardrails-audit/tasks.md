# Tasks — content: "We Audited 102 Guardrails" verification-scaffold spoke (#10903)

Plan: `knowledge-base/project/plans/2026-10-24-content-guardrail-audit-spoke-plan.md`
Branch: `feat-one-shot-10903-guardrails-audit`
PR: #10996

## Phase 1 — Draft + image

- [ ] 1.1 Write founder sentence + outline working notes per the plan's Draft Spec
- [ ] 1.2 Write `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md`
      (frontmatter per Draft Spec; 1,500–2,000-word General-register body; FAQ + parity
      JSON-LD; retro-link to the arc post; one closing GitHub link to the audit doc;
      waitlist CTA)
- [ ] 1.3 Generate `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png`
      via Pillow (1200×630, `#1a1a1a`/`#c4a35a`, textless census-grid motif); fallback:
      reuse `og-agentic-verification-checklist.png` rather than omit `ogImage`

## Phase 2 — Site wiring

- [ ] 2.1 Append `"2026-10-27-audited-102-guardrails-four-portable" = "audited-102-guardrails-four-portable"`
      to `local.blog_redirect_pairs` in `apps/web-platform/infra/seo-bulk-redirects.tf`
- [ ] 2.2 Add the one-sentence spoke link inside the arc post's "Safety rails you can
      install" section (`2026-10-23-agentic-verification-checklist-shipped.md`)

## Phase 3 — Distribution + calendar

- [ ] 3.1 Write `knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md`
      (`status: draft`, `issue_reference: "#10903"`, channels `x, bluesky, discord,
      linkedin-personal`; sections `## X/Twitter Thread` / `## Bluesky` / `## Discord` /
      `## LinkedIn Personal`; labeled tweets ≤ 280 chars; census split is the payload;
      absolute soleur.ai URLs with utm params; no Liquid markers)
- [ ] 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md` via the
      campaign-calendar skill (--headless)

## Phase 4 — Verification

- [ ] 4.1 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` → 0
- [ ] 4.2 `bash scripts/lib/validate-tweet-draft.sh <distribution file>` → 0
- [ ] 4.3 `npm run docs:build` clean
- [ ] 4.4 `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
      plugins/soleur/test/marketing-content-drift.test.ts
      plugins/soleur/test/distribution-content-format.test.ts
      plugins/soleur/test/blog-audience-contract.test.ts` green
- [ ] 4.5 `bash scripts/validate-blog-links.sh` Guard-1 parity green
- [ ] 4.6 Body word count inside [1500, 2000]
- [ ] 4.7 Date coherence: filename date == frontmatter `date:` == redirect-pair key (AC11)
- [ ] 4.8 Read-through claim check: every number traces to the cited sources; no jargon-scan
      blind spots (paths, tool names) in prose
- [ ] 4.9 PR body line 1 carries the merge-mutates-production answer (AC12)

## Ship notes

- Stage only this feature's paths (sibling-session rule); never `git add -A`.
- No push in the planning phase; work phase ships via the normal pipeline.
