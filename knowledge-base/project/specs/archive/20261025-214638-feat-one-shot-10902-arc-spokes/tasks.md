# Tasks — feat-one-shot-10902-arc-spokes

Derived from `knowledge-base/project/plans/2026-10-25-content-agentic-verification-arc-spokes-plan.md`.
Five agentic-verification arc spoke posts in one PR (closes #10636, #10694, #10730, #10737, #10739).

## Phase 1 — Five drafts + five OG images

### 1.1 Spoke #10636 — `2026-11-03-first-property-test-found-real-bug.md`

- 1.1.1 Draft per plan Draft Spec Spoke 1 (content-writer conventions: founder
  sentence first, General register, outline, redaction list; 1,500–2,000 words;
  FAQ 2–4 + parity JSON-LD)
- 1.1.2 Write `plugins/soleur/docs/blog/2026-11-03-first-property-test-found-real-bug.md`
- 1.1.3 Pillow-generate `plugins/soleur/docs/images/blog/og-first-property-test-found-real-bug.png`
  (1200×630, `#1a1a1a` bg, `#c4a35a` gold, textless; motif: scattered dots,
  one circled in gold)

### 1.2 Spoke #10694 — `2026-11-05-map-that-cant-drift.md`

- 1.2.1 Draft per Draft Spec Spoke 2 — fact pins: 27 mapped + 5 exempt = 32
  reachable; lint is advisory-in-CI (`lint-bot-statuses`), enforced on the local
  test path — never claim it blocks merges
- 1.2.2 Write `plugins/soleur/docs/blog/2026-11-05-map-that-cant-drift.md`
- 1.2.3 Pillow `og-map-that-cant-drift.png` (gold ruled line mirroring itself +
  thin checksum bar)

### 1.3 Spoke #10730 — `2026-11-10-test-the-migration-not-just-the-schema.md`

- 1.3.1 Draft per Draft Spec Spoke 3 — fact pins: old-system-as-oracle,
  normalization contract, replayed corpus, approved-changes ledger,
  delete-the-old exit; doc does NOT cover SQL DDL migrations — scope honesty
- 1.3.2 Write `plugins/soleur/docs/blog/2026-11-10-test-the-migration-not-just-the-schema.md`
- 1.3.3 Pillow `og-test-the-migration-not-just-the-schema.png` (two parallel
  gold traces diverging, reconciled at a ledger line)

### 1.4 Spoke #10737 — `2026-11-12-map-that-only-records-what-the-agent-saw.md`

- 1.4.1 Draft per Draft Spec Spoke 4 — fact pins: seeds exercised-routes-only;
  zero exercised → no seed; field-scoped refresh; presence-not-conformance;
  describe the doc, not the citation spread (#10736-neutral)
- 1.4.2 Write `plugins/soleur/docs/blog/2026-11-12-map-that-only-records-what-the-agent-saw.md`
- 1.4.3 Pillow `og-map-that-only-records-what-the-agent-saw.png` (footprints +
  a map drawn only where prints land)

### 1.5 Spoke #10739 — `2026-11-17-flaky-test-passed-on-retry-quarantine.md`

- 1.5.1 Draft per Draft Spec Spoke 5 — fact pins: one isolated re-run;
  error/timeout re-run is NOT a pass; sentinel dedup; `SUCCESS (N quarantined)`
  render; six determinism axes
- 1.5.2 Write `plugins/soleur/docs/blog/2026-11-17-flaky-test-passed-on-retry-quarantine.md`
- 1.5.3 Pillow `og-flaky-test-passed-on-retry-quarantine.png` (gold loop
  interrupted by a quarantine box)

## Phase 2 — Site wiring (once)

- 2.1 Append five `local.blog_redirect_pairs` entries to
  `apps/web-platform/infra/seo-bulk-redirects.tf` (ascending-date tail,
  column-aligned `=` style) — exact strings in plan Phase 2.1
- 2.2 Append five one-sentence spoke links in
  `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`:
  two at end of the map section (guard + convention, distinct companions), one
  at end of test-found-a-bug (after the existing property-test sentence), one
  each at end of old-versus-new and pass-on-retry. Facts-only; title/slug/H1/
  meta/keywords untouched

## Phase 3 — Five distribution drafts + calendar

- 3.1–3.5 Write the five `knowledge-base/marketing/distribution-content/<date>-<slug>.md`
  files: `type: pillar`, `publish_date:` empty, `channels: x, bluesky, discord,
  linkedin-personal`, `status: draft`, `issue_reference:` per spoke; sections
  `## X/Twitter Thread` / `## Bluesky` / `## Discord` / `## LinkedIn Personal`;
  tweets ≤ 280 chars, labeled `**Tweet N**`; absolute `https://soleur.ai/…`
  URLs with utm params; no Liquid
- 3.6 Regenerate `knowledge-base/marketing/campaign-calendar.md` once via the
  campaign-calendar skill (`--headless`) after all five drafts exist

## Phase 4 — Verification

- 4.1 `blog-jargon-scan.sh` rc 0 on all five posts
- 4.2 `validate-tweet-draft.sh` rc 0 on all five distribution files
- 4.3 `npm run docs:build` clean; `bun test` the four suites
  (`seo-aeo-drift-guard`, `marketing-content-drift`,
  `distribution-content-format`, `blog-audience-contract`) green
- 4.4 `bash scripts/validate-blog-links.sh` Guard-1 parity green (5 slugs)
- 4.5 Per-post word count 1,500–2,000 (frontmatter + JSON-LD excluded)
- 4.6 Read-through per post against its Redaction & claim list + AC4 fact
  pins + AC13 sibling-boundary caps + AC7 hub-link counts
- 4.7 PR body: line 1 states merge-mutates-production (bulk-redirect list
  gains five items via auto-apply; posts publish via deploy-docs); body
  carries `Closes #10636`, `Closes #10694`, `Closes #10730`,
  `Closes #10737`, `Closes #10739`
