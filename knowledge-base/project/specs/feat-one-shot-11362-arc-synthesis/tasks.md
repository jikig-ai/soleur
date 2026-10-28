---
title: "Tasks — content(blog): arc synthesis 'First We Made Green Mean Something. Then We Made It Fast.' (#11362)"
branch: feat-one-shot-11362-arc-synthesis
plan: knowledge-base/project/plans/2026-10-28-content-testsuite-arc-synthesis-plan.md
issue: 11362
---

# Tasks

Derived from the finalized plan. Prescribed skill/agent checkpoints run
**inline** at work time per `hr-pipeline-skills-never-inline-after-go-route`'s
inverse: the plan prescribes them, the work phase executes them.

## Phase 1 — Draft + image (`soleur:content-writer`, Blog register)

- [ ] 1.1 Write founder sentence + outline from the plan's Draft Spec
      (General register per `knowledge-base/marketing/brand-guide.md` ### Blog).
- [ ] 1.2 Draft `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`
      — frontmatter per Draft Spec (unquoted `date: 2026-11-19`,
      `pillar: billion-dollar-solo-founder`, `ogImage`), 1,500–2,000-word
      body, FAQ section + parity-matched FAQPage JSON-LD.
- [ ] 1.3 Generate `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png`
      via PIL (1200×630, `#1a1a1a` + gold `#c9a962`/`#dcbe6e`, textless,
      3× supersample + LANCZOS; fallback: nearest on-theme `og-*.png`).

## Phase 2 — Site wiring

- [ ] 2.1 Append `"2026-11-19-first-we-made-green-mean-something" =
      "first-we-made-green-mean-something"` to `local.blog_redirect_pairs` in
      `apps/web-platform/infra/seo-bulk-redirects.tf` (end of ascending-date
      map, column-aligned `=` style).
- [ ] 2.2 Append one sequel-link sentence in the closing section of
      `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
      (`{{ site.url }}/blog/first-we-made-green-mean-something/`); facts-only
      edit — title/slug/H1/meta untouched.
- [ ] 2.3 Append the pipeline row to the Pillar-2 methodology table in
      `knowledge-base/marketing/content-strategy.md` (5-col schema
      `| Piece | Type | Words | Priority | Status |`).

## Phase 3 — Distribution + follow-through + calendar

- [ ] 3.1 Write
      `knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md`
      — `title`, `type: pillar`, `publish_date: 2026-11-19`, `channels:
      x, bluesky, discord, linkedin-personal`, `issue_reference: "#11362"`;
      sections `## X/Twitter Thread` (tweets ≤280 chars, taxonomy payload,
      closing UTM link), `## Bluesky`, `## Discord`, `## LinkedIn Personal`;
      no Liquid markers; absolute URLs only.
- [ ] 3.2 Validate while still `status: draft`:
      `bash scripts/lib/validate-tweet-draft.sh <file>` → rc 0; then flip to
      `status: parked` as the final edit (hold lever — see plan Technical
      Considerations).
- [ ] 3.3 Write `scripts/followthroughs/parked-green-synthesis-11362.sh`
      (`#!/usr/bin/env bash`, `set -euo pipefail`; exit 2 pre-window, 5
      in-window while `status: parked` persists, 3 if file missing; NEVER
      0/1; `RETIREMENT:` + credential-posture header).
- [ ] 3.4 Regenerate `knowledge-base/marketing/campaign-calendar.md` via the
      campaign-calendar skill (`--headless`).

## Phase 4 — Verification (`soleur:marketing:fact-checker` + gates)

- [ ] 4.1 `soleur:marketing:fact-checker` pass inline on the defect-class
      taxonomy — every claim traces to a named source (epic close comment,
      merged PRs, `scripts/test-all-parallel-benchmark.test.sh`, #8231
      acceptance evidence); UNSOURCED claims cut or sourced.
- [ ] 4.2 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh
      <post>` → rc 0 + Blog-note read-through for the scan's undetected
      subset.
- [ ] 4.3 `npm run docs:build` clean; `bun test
      plugins/soleur/test/seo-aeo-drift-guard.test.ts
      plugins/soleur/test/marketing-content-drift.test.ts
      plugins/soleur/test/distribution-content-format.test.ts
      plugins/soleur/test/blog-audience-contract.test.ts` green.
- [ ] 4.4 `bash scripts/validate-blog-links.sh` Guard-1 parity green.
- [ ] 4.5 Word count check: body in [1500, 2000] excluding frontmatter +
      JSON-LD.
- [ ] 4.6 Probe dry runs: pre-window → exit 2; in-window + parked → exit 5;
      missing file → exit 3.
- [ ] 4.7 At ship time: file the `<!-- soleur:followthrough
      script=scripts/followthroughs/parked-green-synthesis-11362.sh
      earliest=2026-11-19 secrets= -->` tracker + `follow-through` label on
      #11362; PR body line 1 states the production mutation (bulk-redirect
      list gains one item; post publishes via deploy-docs).

## Phase 5 — Post-merge (window)

- [ ] 5.1 On/after 2026-11-19: responder flips `status: parked → scheduled`
      in a one-line commit so the daily publisher fires the file on the
      window date; closes the tracker.
