---
title: "content: five remaining agentic-verification arc spoke posts in one PR (epic #10902)"
type: content
date: 2026-10-25
slug: content-agentic-verification-arc-spokes
branch: feat-one-shot-10902-arc-spokes
issue: 10636
closes: [10636, 10694, 10730, 10737, 10739]
priority: p3-low
domain: marketing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# Content: five remaining agentic-verification arc spoke posts in one PR (#10636, #10694, #10730, #10737, #10739)

## Overview

Write and ship the five remaining Pillar-2 methodology spoke posts of the
agentic-verification arc — the child briefs filed under epic #10902, whose hub
post is already live at
`plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
(merged via PR #10922). The operator directive is one PR covering all five.
Two sibling spokes already shipped with the file set this plan repeats per
post: PR #10996 (`2026-10-27-audited-102-guardrails-four-portable.md`) and PR
#11067 (`2026-10-29-property-test-cannot-fail-teaches-nothing.md`, issue
#10904 — the structural template for every spoke here).

The five spokes, each carrying a distinct publish date on the Tue/Thu slot
convention the prior spokes used (the 2026-10-27 and 2026-10-29 slots are
already occupied by the shipped siblings):

| Issue | Working title (strategy row) | Slug | Publish date | Hub section it expands |
|---|---|---|---|---|
| #10636 | The First Property Test We Wrote Found a Real Bug | `first-property-test-found-real-bug` | 2026-11-03 (Tue) | "The test that found a bug on day one — and the example that could never fail" |
| #10694 | A Map That Can't Drift — the Feature Map That Guards Itself | `map-that-cant-drift` | 2026-11-05 (Thu) | "The map that guards itself — and the four ways the guard was wrong" |
| #10730 | Test the Migration, Not Just the Schema | `test-the-migration-not-just-the-schema` | 2026-11-10 (Tue) | "Old versus new, side by side" |
| #10737 | The Map That Only Records What the Agent Saw | `map-that-only-records-what-the-agent-saw` | 2026-11-12 (Thu) | "The map that guards itself" (founder-codebase half) |
| #10739 | A Flaky Test Passed on Retry and the Loop Called It Fixed | `flaky-test-passed-on-retry-quarantine` | 2026-11-17 (Tue) | "A pass on retry is not a pass" |

The two feature-map posts are deliberately separated by a week so they do not
cannibalize each other's distribution window.

## Problem Statement / Motivation

The arc hub tells each of these stories in one or two paragraphs; the briefs
(the CMO Content-Opportunity Gate's own output, one per issue) call for the
methodology-grade expansion a founder can act on. The shared arc thesis —
"verification machinery is machinery; every verifier shipped with at least one
way it could lie" — only lands if each spoke carries the honest build log:
what shipped, what review caught in it, and what changed. Five separate PRs
would also repeat the shared wiring five times (hub edit, redirect map,
calendar regen); the operator ruled one PR.

## Proposed Solution

One PR containing, per spoke: (1) the blog post at
`plugins/soleur/docs/blog/<date>-<slug>.md` (1,500–2,000 words, General
register per the brand-guide Blog note, frontmatter + FAQ + parity-matched
FAQPage JSON-LD, generated through `soleur:content-writer` conventions);
(2) a bespoke Pillow OG card at
`plugins/soleur/docs/images/blog/og-<slug>.png` (1200×630, `#1a1a1a`
background, `#c4a35a` gold, textless — `soleur:gemini-imagegen` remains
unavailable, #10940 still OPEN); (3) a dated→canonical pair in
`local.blog_redirect_pairs` in `apps/web-platform/infra/seo-bulk-redirects.tf`;
(4) a `status: draft` social-distribution file at
`knowledge-base/marketing/distribution-content/<date>-<slug>.md` (channels
`x, bluesky, discord, linkedin-personal`).

Shared work done once: (5) five one-sentence spoke links appended inside the
published hub post (two in the map section — guard spoke and convention spoke
— one each in the test-found-a-bug, old-versus-new, and pass-on-retry
sections); (6) one append of five entries to `blog_redirect_pairs`; (7) one
regeneration of `knowledge-base/marketing/campaign-calendar.md` via the
`soleur:campaign-calendar` skill.

## Technical Considerations

- **Filename date coherence (one source of truth per spoke).** Each post's
  filename date, frontmatter `date:`, distribution filename, and redirect-pair
  key carry the same date. The dates above are assumed scheduling defaults
  (recorded in `decision-challenges.md`): the next five free Tue/Thu slots
  after the two occupied ones. `eleventy.config.js` has no future-date
  exclusion — every post goes live on merge-to-deploy regardless of `date:`,
  so all five publish together when this PR merges; the dates are the
  canonical-URL and calendar convention, not a release gate.
- **Jargon limits are mechanical, not stylistic.** `blog-jargon-scan.sh` flags
  backticks, code/pre tags, `--flags`, and `#NN` tokens in reader-visible
  text; the Blog note bans file paths, commands, API/tool names, and internal
  skill/agent names outright, plus code blocks. Founder-term renderings per
  spoke are pinned in the Draft Specs below. No issue/PR numbers, no internal
  paths, no commit SHAs, no library names in body text (the hub renders
  "a generator that throws thousands of random inputs at a rule" for
  fast-check — same register).
- **OG image is a hard CI gate** (`seo-aeo-drift-guard.test.ts` threads
  `ogImage` into `BlogPosting.image`; content-writer treats it as mandatory).
  Pillow fallback for all five — do not block on Gemini key rotation (#10940
  still open). Distinct motif per card, same palette.
- **No Liquid in distribution bodies** (`lint-distribution-content.sh`);
  distribution links are absolute `https://soleur.ai/…` URLs
  (`distribution-content-format.test.ts`); each declared channel needs its
  exact section heading (`## X/Twitter Thread`, `## Bluesky`, `## Discord`,
  `## LinkedIn Personal`); labeled tweets ≤ 280 chars; `status: draft` for the
  tweet-draft validator.
- **FAQ parity.** Any visible `## Frequently Asked Questions` section must
  match the FAQPage JSON-LD `mainEntity` twins verbatim
  (`seo-aeo-drift-guard.test.ts`). Follow the hub's format: `###` question
  headings + plain answers + trailing JSON-LD block.
- **Merging this PR mutates production (first line of the PR body).**
  `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**` on
  push to main — the bulk-redirect list gains five items at merge. The posts
  deploy via `deploy-docs.yml` (`plugins/soleur/docs/**`). Both are the
  existing IaC/deploy paths; no manual step.
- **Brand/subject claims.** `marketing-content-drift.test.ts` bans
  Soleur-subject Apache-2.0/open-source claims and "Spark"-tier references;
  soft-floor rules apply to agent/skill counts in prose ("60+ agents", never
  exact). Headline numbers must trace to the brief/strategy row: 32 pages
  (27 mapped + 5 reasoned exemptions — the map's own census), 102 audited
  checks → four portable (hub + #10903 row), "thousands of random inputs"
  (qualitative).
- **Pillar frontmatter** resolves to a `_data/pillars.js` series key; all five
  use `pillar: billion-dollar-solo-founder` (the arc series). No `members[]`
  rows — hub and both spokes declare the key without membership.
- **No guard ships — the deliverable is prose about guards.** No `lint-*`,
  `*.test.sh`, hook, CI gate, or `lifecycle.precondition` is created or
  modified; the words "guard"/"test"/"quarantine" in prose are subject matter.
  Plan Phase 2.12 (Guard Contract) assessed and skipped on that basis.
- **Precedent-diff.** The only code-shaped edit is five map appends in
  `seo-bulk-redirects.tf` — the file's own ascending-date `blog_redirect_pairs`
  convention (most recent entries added by PRs #10996/#11067); identical
  shape, new slug strings. The hub edit is five facts-only sentences appended
  to published sections; title/slug/H1/meta/keywords untouched (Blog note
  refresh rule).
- **Sibling-story boundaries (verify at draft time).** The published
  `property-test-cannot-fail-teaches-nothing` spoke owns the vacuous-example
  post-mortem; the #10636 post references it in one line only. #10694 owns the
  web-platform coverage-guard story (the four guard defects + the census-glob
  trap); the user-codebase convention gets one line. #10737 owns the
  convention (seeds-exercised-only, field-scoped refresh); the coverage guard
  gets one line. Cross-references may link the sibling spoke where one is
  live.
- **Fact pins per spoke** are enumerated in the Draft Specs; several are
  honesty-critical: the feature-map lint is advisory in CI today
  (`lint-bot-statuses`, absent from `scripts/required-checks.txt`) — "the
  build fails" claims are wrong; it fails the local test path
  (`test-all.sh`). The differential-migration reference explicitly does NOT
  cover SQL DDL migrations — "migration" in its sense means replacing a
  running system; the motivating incident class (clean-applied change, broken
  consumers for ~3 weeks) is the story, and the post must not claim the doc
  governs `*.sql` files. The #10636 post's twin-defect story ends resolved —
  the SQL twin fix (#10633, CLOSED) already shipped.

## Research Insights

**Premise validation (Phase 0.6).** Every cited reference verified live:

- Issues #10636, #10694, #10730, #10737, #10739 all OPEN with
  `domain/marketing` labels; epic #10902 OPEN (hub merged, published
  2026-10-23/24); related decision-challenge #10736 OPEN (feature-map
  citation scope — context for the two map posts; see Dependencies & Risks).
- Source PRs all MERGED: #10624 (PBT adoption, 2026-10-20), #10666 (feature
  map + coverage guard, 2026-10-20), #10727 (differential-migration-testing
  reference, 2026-10-20), #10735 (feature-map convention, 2026-10-21), #10738
  (flake-quarantine screen + determinism checklist, 2026-10-21).
- Template artifacts exist on this branch: the sibling plan
  (`knowledge-base/project/plans/archive/20261025-150240-2026-10-25-content-pbt-methodology-spoke-plan.md`)
  and both published spokes; every brief-cited source file exists
  (ADR-293, the three PBT learnings, `apps/web-platform/test/feature-map.md`,
  `scripts/lint-feature-map-coverage.sh`,
  `plugins/soleur/skills/plan/references/differential-migration-testing.md`,
  `plugins/soleur/skills/test-browser/references/feature-map.md`,
  `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`,
  the census-guard, copied-template-links, forced-test-condition,
  basename-substring-census, and cannot-fire learnings — paths in the
  strategy rows verified individually since several live in subdirectory
  folders).
- Ancillary facts verified against the artifacts, not the briefs: the map
  carries 27 route-heading entries plus 5 `## Deliberately unmapped` rows (=
  the hub's "32 pages"); the lint's own doc line says advisory-in-CI;
  `determinism-checklist.md` carries exactly six axes (seeds, clocks,
  network, state isolation, output terseness, contention/ordering); the
  convention doc names four consumers (test-browser, qa, ux-audit,
  reproduce-bug) and its seed contract (exercised-routes-only; zero
  exercised → no seed; field-scoped refresh); the test-fix-loop screen spec
  carries the sentinel dedup, the three acts (quarantine/file/report), and
  the at-least-one-quarantined fix on the all-screened-out row; the migration doc's
  oracle/ledger/exit-criterion apparatus and its explicit not-schema-migrations
  scope note; the migration pointer sentence ships at three sites in
  `plan-issue-templates.md` (Test Scenarios blocks, lines ~235/491/769).
- Proposed mechanism check vs ADR corpus: the delivery mechanism (blog post +
  Cloudflare bulk-redirect pair + distribution draft) follows ADR-194 (docs
  site on Cloudflare Pages) and the #3328 redirect migration; no ADR's
  rejected-alternatives table is re-entered. ADR-130/136 govern Cloudflare
  apply safety — five items appended to an existing list resource, no new
  ruleset phase.
- **Functional overlap (Phase 1.5b, inline — no Task spawn):** grep of
  `plugins/soleur/docs/blog/` and `distribution-content/` for
  feature-map/migration/flake/quarantine/property-test terms hits only the
  arc hub (per-story summaries by design), the two published spokes, the
  published `property-based-testing-adoption` feature-tweet (different
  channel), and incidental mentions in older posts. No existing piece covers
  any of the five stories at spoke depth.
- **Community discovery (Phase 1.5):** no stack signatures outside the
  covered set — skipped silently.
- **External research (Phase 1.6):** skipped — the file set, gates, register,
  and per-story fact pins are fully established by the two published siblings
  and the brand guide; external research adds nothing to a five-copy
  repetition of a proven pattern.

**Property list (Phase 0.6b).**

1. Five Pillar-2 spoke posts exist and read to the blog's founder audience
   (Blog note), one per issue brief.
2. Each retro-links the arc hub and is linked back once (hub-and-spoke per
   the #10902 brief).
3. Each URL is stable/canonical — dated→canonical redirect pair present.
4. Social payloads exist per post for the declared channels (X thread carries
   each story's signature sequence).
5. All existing content gates stay green (ogImage, jargon scan, tweet-draft
   structure, redirect parity, content-drift, FAQ parity,
   blog-audience-contract).
6. One PR — shared wiring (hub edits, redirect map, calendar) applied once,
   per the operator directive.

**Cut list.** No new machinery proposed or needed:

- content-writer conventions + `blog-jargon-scan.sh`,
  `validate-tweet-draft.sh`, `validate-blog-links.sh` already cover every
  property — no new validator.
- content-strategy.md rows for all five issues already exist (lines ~261,
  278–281) — do not re-edit.
- `pillars.js` membership rows — not needed (hub + sibling precedent:
  declare the key only).
- Campaign-calendar regen uses the existing `soleur:campaign-calendar` skill.
- A dedicated HN lane — briefs name X threads only; HN adjacency is a
  distribution note, not a deliverable.
- Five separate PRs — the operator ruled one PR; the split assessment below
  stays under the split thresholds anyway.

**Relevant file paths.**

- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
  — arc hub; format + voice + FAQ/JSON-LD convention; receives five spoke-link
  sentences (map section gets two).
- `plugins/soleur/docs/blog/2026-10-29-property-test-cannot-fail-teaches-nothing.md`
  — freshest format precedent.
- Source-of-truth docs per spoke: `ADR-293-property-based-testing-adoption.md`
  plus the three 2026-10-20 PBT learnings (#10636);
  `apps/web-platform/test/feature-map.md` and `scripts/lint-feature-map-coverage.sh`
  plus the census-guard learning (#10694);
  `plugins/soleur/skills/plan/references/differential-migration-testing.md`
  plus the copied-template-links and forced-test-condition learnings (#10730);
  `plugins/soleur/skills/test-browser/references/feature-map.md` plus the
  basename-substring-census learning and the archived convention plan (#10737);
  `plugins/soleur/skills/test-fix-loop/SKILL.md` flake-screen block plus
  `references/determinism-checklist.md` plus the cannot-fire/success-row learning
  (#10739).
- `knowledge-base/marketing/brand-guide.md` §Channel Notes > ### Blog;
  `plugins/soleur/skills/content-writer/SKILL.md`;
  `knowledge-base/marketing/distribution-content/2026-10-29-property-test-cannot-fail-teaches-nothing.md`
  (distribution precedent); `apps/web-platform/infra/seo-bulk-redirects.tf`
  `local.blog_redirect_pairs`.

**Institutional learnings applied.**

- `2026-10-21-one-regen-gap-three-committed-state-reds.md` — regenerate
  derived artifacts by inventory: the five distribution files are enumerated
  by one `campaign-calendar.md` regen; the five dated filenames by five
  `blog_redirect_pairs` entries; the five PNGs by five `ogImage` frontmatter
  values.
- `2026-10-21-sibling-session-owned-commits-on-my-branch.md` — stage only
  this feature's paths.
- The per-story learnings are the posts' fact base (listed per-spoke above).

**CLAUDE.md / constitution conventions.** kebab-case filenames;
`YYYY-MM-DD-<type>-<slug>-plan.md`; plan review precedes tasks.md; no version
bumps; General register; markdown links not bare URLs.

**Findings (surfaced, not folded).**

- HN submission stays conditional per the strategy rows ("only if not
  adjacent" to sibling lanes) and submits technical write-ups, never posts;
  distribution note only.
- #10739's brief hedged "not a standalone piece; queue as a methodology
  candidate" — the operator directive overrides: it ships as a full spoke in
  this PR. Recorded as an operator-scope note in `decision-challenges.md`.
- #10736 (open decision-challenge) questions the convention's citation scope
  (four consumers vs the two #10402 named). The #10737 post describes the
  convention doc as shipped (four consumers); a later revert would leave the
  post's convention claims intact — it names no consumer count.

### Open Code-Review Overlap

Two hits, both acknowledged (same as the sibling plan):

- **#3649** mentions `knowledge-base/marketing/distribution-content/` —
  acknowledge: a different piece's scheduling; our five files are new.
- **#10240** mentions `knowledge-base/marketing/campaign-calendar.md` —
  acknowledge: a zero-findings review record of a different PR's refresh.

## Files to Create

- `plugins/soleur/docs/blog/2026-11-03-first-property-test-found-real-bug.md`
- `plugins/soleur/docs/blog/2026-11-05-map-that-cant-drift.md`
- `plugins/soleur/docs/blog/2026-11-10-test-the-migration-not-just-the-schema.md`
- `plugins/soleur/docs/blog/2026-11-12-map-that-only-records-what-the-agent-saw.md`
- `plugins/soleur/docs/blog/2026-11-17-flaky-test-passed-on-retry-quarantine.md`
- `plugins/soleur/docs/images/blog/og-first-property-test-found-real-bug.png`
- `plugins/soleur/docs/images/blog/og-map-that-cant-drift.png`
- `plugins/soleur/docs/images/blog/og-test-the-migration-not-just-the-schema.png`
- `plugins/soleur/docs/images/blog/og-map-that-only-records-what-the-agent-saw.png`
- `plugins/soleur/docs/images/blog/og-flaky-test-passed-on-retry-quarantine.png`
- `knowledge-base/marketing/distribution-content/2026-11-03-first-property-test-found-real-bug.md`
- `knowledge-base/marketing/distribution-content/2026-11-05-map-that-cant-drift.md`
- `knowledge-base/marketing/distribution-content/2026-11-10-test-the-migration-not-just-the-schema.md`
- `knowledge-base/marketing/distribution-content/2026-11-12-map-that-only-records-what-the-agent-saw.md`
- `knowledge-base/marketing/distribution-content/2026-11-17-flaky-test-passed-on-retry-quarantine.md`

## Files to Edit

- `apps/web-platform/infra/seo-bulk-redirects.tf` — append five
  `blog_redirect_pairs` entries (ascending-date order preserved at the tail)
- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
  — five one-sentence spoke links (two in the map section; one each in the
  test-found-a-bug, old-versus-new, and pass-on-retry sections)
- `knowledge-base/marketing/campaign-calendar.md` — regenerated once by the
  campaign-calendar skill after all five distribution files exist

## Implementation Phases

### Phase 1 — Five drafts + five OG images

- 1.1 Per spoke, run `soleur:content-writer` conventions against that spoke's
  **Draft Spec** below: founder sentence first (working notes), General
  register, outline, redaction list.
- 1.2 Write the five post files (frontmatter + 1,500–2,000-word body + FAQ
  section + parity-matched FAQPage JSON-LD each).
- 1.3 Generate the five OG PNGs with Pillow: 1200×630 RGB, `#1a1a1a`
  background, `#c4a35a` gold accent, textless abstract motif per card
  (suggested: #10636 — a field of scattered dots where one dot is circled in
  gold, the input nobody hand-picked; #10694 — a gold ruled line that mirrors
  itself, with a thin vertical checksum bar, the map checking the territory;
  #10730 — two parallel gold traces diverging then being reconciled at a
  ledger line, old as referee; #10737 — footprints pressed into a field and a
  map drawn only where the prints land, records-what-was-seen; #10739 — a
  gold loop interrupted by a quarantine box, retry stopped). If Pillow is
  somehow unavailable, reuse `og-agentic-verification-checklist.png` rather
  than omit the field.

### Phase 2 — Site wiring (once)

- 2.1 Append five entries to `local.blog_redirect_pairs` in
  `apps/web-platform/infra/seo-bulk-redirects.tf`, tail of the ascending-date
  map, matching the column-aligned `=` style:
  `"2026-11-03-first-property-test-found-real-bug" = "first-property-test-found-real-bug"`,
  `"2026-11-05-map-that-cant-drift" = "map-that-cant-drift"`,
  `"2026-11-10-test-the-migration-not-just-the-schema" = "test-the-migration-not-just-the-schema"`,
  `"2026-11-12-map-that-only-records-what-the-agent-saw" = "map-that-only-records-what-the-agent-saw"`,
  `"2026-11-17-flaky-test-passed-on-retry-quarantine" = "flaky-test-passed-on-retry-quarantine"`.
- 2.2 Edit `2026-10-23-agentic-verification-checklist-shipped.md` — append
  five facts-only spoke-link sentences, one per spoke, at the end of the
  section each expands: the map section gains two (the guard post and the
  convention post, phrased as distinct companions — e.g. one on the guard
  that keeps our own map honest, one on the convention that lets a founder's
  agent keep its map honest); the test-found-a-bug section gains one
  (immediately after the existing property-test companion sentence, linking
  the day-one-bug story); old-versus-new gains one (the
  differential-migration write-up); pass-on-retry gains one (the
  quarantine-protocol write-up). Title/slug/H1/meta/keywords untouched.

### Phase 3 — Five distribution drafts + one calendar regen

- 3.1 Write the five `distribution-content/<date>-<slug>.md` files:
  frontmatter `title` (post title), `type: pillar`, `publish_date:` empty,
  `channels: x, bluesky, discord, linkedin-personal`, `status: draft`,
  `issue_reference:` the spoke's issue; body sections `## X/Twitter Thread`
  (labeled `**Tweet N**`, ≤ 280 chars, the spoke's signature sequence as
  payload, closing tweet links `https://soleur.ai/blog/<slug>/` with utm
  params per sibling precedent), `## Bluesky`, `## Discord`,
  `## LinkedIn Personal`. No Liquid; absolute URLs only.
- 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md`
  (campaign-calendar skill, `--headless`) once, after all five drafts exist.

### Phase 4 — Verification

- 4.1 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>`
  → rc 0 for each of the five posts.
- 4.2 `bash scripts/lib/validate-tweet-draft.sh <distribution file>` → rc 0
  for each of the five drafts.
- 4.3 `npm run docs:build` clean; `bun test
  plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` green.
- 4.4 `bash scripts/validate-blog-links.sh` Guard-1 parity green (all five
  dated slugs covered).
- 4.5 Word count per post (frontmatter + JSON-LD excluded) inside
  1,500–2,000.
- 4.6 Read-through pass per post against its **Redaction & claim list** —
  every claim traces to a cited source; zero code blocks; sibling-boundary
  one-line caps honored; hub-link count per spoke exactly one.

## Draft Specs (contract for the writer step)

Shared redaction & claim list for all five: no issue/PR numbers, no file
paths, no code blocks or inline code, no library/tool names, no commit SHAs,
no internal skill/agent names in reader-visible text. One retro-link to the
arc hub inline, one closing technical link, one waitlist CTA
(`https://soleur.ai/pricing/#waitlist`). FAQ 2–4 questions with verbatim
JSON-LD parity. Frontmatter per post: `title` + `seoTitle`, `date:` matching
the filename (unquoted), `description` 120–160 chars carrying the hook,
`ogImage: "blog/og-<slug>.png"`, `pillar: billion-dollar-solo-founder`,
`tags` led by `agentic-verification, methodology, solo-founder,
build-in-public` plus the spoke's topic tags.

### Spoke 1 — #10636 `first-property-test-found-real-bug` (2026-11-03)

- **Title (default):** "The First Property Test We Wrote Found a Real Bug"
  (strategy-row working title; re-angle is a taste call — slug pinned either
  way).
- **Founder sentence (working notes):** "A solo founder tests the cases they
  remember to write down. After reading, they know why a rule that must
  always hold — hammered by inputs nobody would think to try — catches what
  example lists never will, and that the very first run already paid for the
  practice."
- **Outline:** (1) founder problem — your test list is your imagination, and
  your imagination shares your blind spots; (2) the practice — state a rule
  that must always hold ("running a cleanup twice changes nothing the second
  time"), let a generator throw thousands of random inputs at it; (3) day one
  — the first generated run caught a real defect: a repository-address
  tidy-up that could leave an invisible trailing space, so two runs produced
  a third answer — the documented contract said that was impossible; (4) the
  twin — once looked for, the same defect lived in the database-side twin of
  the same logic, the third drift between two implementations of one idea —
  both now fixed; (5) the harness needed fixing too — the generated-input
  tooling itself had two fail-open surfaces (a coverage counter that read 31
  of 39 while green; test inputs that could silently fold into permanent
  no-ops) plus a shell randomness trap that produced a degenerate stream;
  (6) the lesson — example tests sample the cases you remembered; rules +
  generation find the one you didn't; (7) close — one line citing the
  companion post-mortem (the published sibling spoke, may be linked), the
  single closing technical link (the public learning doc
  `knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md`),
  waitlist CTA.
- **Fact pins:** the defect was `normalizeRepoUrl`-shaped idempotence
  breakage (suffix strip exposing shielded whitespace) — render in founder
  terms; the SQL twin shipped its fix via a follow-up that is already closed;
  extraction-coverage was 31/39 under a green suite; the `$RANDOM` trap is
  bash-3.2 command-substitution — render as "a shell built-in that quietly
  repeats its random stream"; ADR-293 is the adoption decision.
- **FAQ candidates:** "What is a property test in plain terms?", "How is a
  rule better than a list of examples?", "Do I need this if my AI writes my
  tests?"

### Spoke 2 — #10694 `map-that-cant-drift` (2026-11-05)

- **Title (default):** "A Map That Can't Drift" (strategy row carries the
  subtitle "— the Feature Map That Guards Itself"; the post title may keep or
  drop it — taste call).
- **Founder sentence:** "A solo founder cannot keep product documentation
  honest by memory; after reading, they know a map can carry its own
  enforcement — and that the enforcement itself needed four fixes before it
  could be trusted."
- **Outline:** (1) documentation rots because nothing makes it true — the
  difference between a map someone wrote and a map the product cannot drift
  from; (2) what shipped — a maintained map of the platform's 32 reachable
  pages (27 mapped, 5 deliberately exempt with written reasons), and a guard
  that checks both directions: a page missing from the map fails, a map entry
  naming a page that no longer exists fails; (3) the four defects review
  found in the guard itself — a census pattern that silently skipped the
  homepage (31 of 32 — a file-listing glob that drops the file sitting at the
  root), a completeness check descriptive text could satisfy without the
  required fields, an in-doc example a reader could miscount as a real entry,
  and two separate scoreboards for "did it pass"; (4) the census trap
  generalized — any check built on a file listing can under-count and stay
  green; (5) honest scope — the guard is advisory in CI today, enforced on
  the local test path (name it straight: enforcement that reports is still
  enforcement, but the post does not claim it blocks merges); (6) one line:
  the same convention exists for a founder's own codebase — the companion
  spoke tells that story; (7) close — closing technical link (the
  census-guard learning doc
  `knowledge-base/project/learnings/2026-10-20-a-census-guard-under-counts-on-both-enumerators.md`),
  CTA.
- **Fact pins:** 27 + 5 = 32 (the hub says "32 pages" — use 32 reachable /
  27 mapped / 5 exempt); advisory-in-CI per the map's own doc line
  (`lint-bot-statuses`, absent from `required-checks.txt`) — this is the
  honesty-critical pin; the bidirectional checks are route→map coverage AND
  map→route staleness (tombstone) plus field-bullet conformance and a
  both-sets contradiction check.
- **FAQ candidates:** "What is a feature map?", "How can documentation check
  itself?", "Why did the checker need checking?"

### Spoke 3 — #10730 `test-the-migration-not-just-the-schema` (2026-11-10)

- **Title (default):** "Test the Migration, Not Just the Schema" (strategy-row
  working title).
- **Founder sentence:** "A solo founder replaces a working system trusting
  the new one's own tests; after reading, they know the old system is the
  referee — run both on the same inputs and account for every difference —
  and that 'it applied cleanly' is not evidence anything downstream still
  works."
- **Outline:** (1) the incident class — a change that applies cleanly while
  everything downstream quietly breaks (our own measured instance ran ~3
  weeks undetected); users never relied on the specification — they relied
  on what the old thing did; (2) the answer — the old system is the oracle:
  feed old and new the same inputs, normalize the non-semantic differences,
  diff the outputs; every difference is a bug or a written-down deliberate
  change; when the diff is clean modulo the ledger, the old system retires;
  (3) where it shipped — the planning workflow our users' agents run now
  demands before/after evidence whenever a change replaces a running system
  — the requirement is routed so only migration-shaped plans pick it up; (4)
  honest scope — the recipe covers replacing a runnable system (rewrites,
  ports, engine swaps); it deliberately does not govern database-schema
  files, which keep their own runbooks — the title's "schema" is the cheap
  test everyone already runs, not the doc's scope; (5) the companion lesson
  — a coverage claim needs a failing case to prove the harness can see red;
  a copied-template link that resolved nowhere was only believed fixed after
  a negative control ran; (6) the doc itself was shaped by an in-plan
  escalation ruling — kept a full reference, not a slimmed skill page; (7)
  close — closing technical link (the shipped reference doc on GitHub
  `plugins/soleur/skills/plan/references/differential-migration-testing.md`),
  CTA.
- **Fact pins:** do NOT claim the doc covers SQL DDL migrations — its own
  scope note says the opposite; the pointer sentence lives in the plan
  templates' Test Scenarios blocks (three sites); the oracle apparatus names
  a normalization contract, a replayed-traffic corpus, an approved-changes
  ledger, and a delete-the-old exit criterion.
- **FAQ candidates:** "What is differential testing?", "How is this different
  from a migration test?", "What counts as evidence a replacement is safe?"

### Spoke 4 — #10737 `map-that-only-records-what-the-agent-saw` (2026-11-12)

- **Title (default):** "The Map That Only Records What the Agent Saw"
  (strategy-row working title).
- **Founder sentence:** "A solo founder's AI needs a map of their product it
  can trust; after reading, they know a map an agent writes is only
  trustworthy when it can never fabricate — record only what was exercised,
  and refresh only what the run contradicted."
- **Outline:** (1) an agent without a map re-derives your product's
  navigation on every run and discards it at session end — flailing, not
  testing; (2) the convention — one committed map file in the repo
  (`docs/feature-map.md` shape), one `##` entry per route naming how a user
  reaches it, the stable selectors, the expected outcome, the session state;
  (3) the trust contract — the map seeds only routes the agent actually
  exercised, because an entry for a route never navigated fabricates exactly
  the fields that make the map trustworthy; zero exercised routes means no
  seed is written at all; (4) refresh is field-scoped — a run updates only
  the fields it contradicted, so an operator's annotations survive; the
  update contract is the guard — presence-not-conformance, no separate lint;
  (5) the review catch — a control written to prove the link could be
  removed could not go red against a basename-substring census (the audit
  passed either way — a falsification of the harness, not the map); (6) one
  line: our own platform map plus its drift guard is the companion spoke's
  story (link `map-that-cant-drift`); (7) close — closing technical link
  (the shipped convention doc
  `plugins/soleur/skills/test-browser/references/feature-map.md`), CTA.
- **Fact pins:** four consumer workflows read the convention today (name
  them as "the workflows that browse, audit, and reproduce" in founder
  terms — do NOT print skill names); the doc specifies the entry schema
  (route/entry/selectors/expects/auth/gotchas), the canonical
  `docs/feature-map.md` location, the seed contract, and the field-scoped
  refresh; #10736 (open citation-scope question) does not change what the
  convention doc says — the post describes the doc, not the citation spread.
- **FAQ candidates:** "Why can't the agent write the whole map at once?",
  "What happens to notes I add to the map?", "Where does the map live in my
  repo?"

### Spoke 5 — #10739 `flaky-test-passed-on-retry-quarantine` (2026-11-17)

- **Title (default):** "A Flaky Test Passed on Retry and the Loop Called It
  Fixed" (strategy-row working title; the brief's angle — "stop retrying
  flaky tests; quarantine them deterministically" — is the same story told
  from inside the loop).
- **Founder sentence:** "A solo founder's AI fixing a flaky test by retrying
  it teaches the whole system that red is negotiable; after reading, they
  know the deterministic alternative — one isolated re-run, then quarantine
  with a filed tracker, never a silent pass."
- **Outline:** (1) the failure mode unique to AI-driven work — a pass on
  retry is a strategy the agent learns, not a fix; a flaky check left in the
  suite is worse than no check; (2) what shipped — every newly failed test
  gets exactly one isolated re-run on the unchanged code; a pass there is a
  flake signature: the test is quarantined (removed from the failure set for
  the run, never counted as fixed, never tripping the fix loop), a tracker
  is filed (deduped on a written marker, not a title search), and the report
  names it — a green line can never read clean over quarantined flakes;
  (3) what review caught — the "everything that failed turned out to be a
  flake" row could fire on a run that produced no readable results at all:
  zero quarantines reading as green — fixed by requiring at least one real
  quarantine; and a warning flag whose trigger was empty by construction —
  decoration that reads as coverage; (4) the determinism checklist — six
  axes a founder can audit any suite against: seeds, clocks, network, state
  isolation, output terseness, contention; (5) the boundary — quarantine
  never launders a regression the change caused (a flake first seen after
  the loop's own fix, or in files the diff touched, is flagged as a possible
  diff-interaction); (6) close — closing technical link (the determinism
  checklist
  `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`),
  CTA.
- **Fact pins:** the screen runs per-test on the failure set, keyed by
  file + test name; a re-run that errors or times out is NOT a pass — the
  failure stays on the fix path; dedup is sentinel-in-body
  (`soleur:flake test=`) not title search; "SUCCESS (N quarantined — issues
  …)" is the mandated render, never bare green; the six axes are verbatim
  from the shipped checklist.
- **FAQ candidates:** "Isn't retrying a flaky test harmless?", "What does
  quarantine actually do to the test?", "How do I make my suite less flaky
  in the first place?"

## User-Brand Impact

- **If this lands broken, the user experiences:** five published posts on
  soleur.ai that misstate the engineering record (e.g., claiming the map
  guard blocks merges when it is advisory-in-CI, or claiming the migration
  doc governs schema files it explicitly excludes) — durable, public,
  brand-bearing artifacts carrying wrong claims. A post about honest
  verification that itself overstates what shipped would be the exact
  defect class the arc describes.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing —
  the posts re-publish an already-public engineering record (merged PRs,
  public learning docs) in founder language; no user data, credentials, or
  internal-only detail ships.
- **Brand-survival threshold:** `aggregate pattern` — a wrong post is
  correctable (edit + redeploy); the risk class is a pattern of unreviewed
  public claims, which the fact-checker/jargon-scan/drift-test gauntlet plus
  this plan's per-spoke fact pins cover. Multiplied surface (5 posts) keeps
  the threshold the same — the pins, not heroics, carry the honesty load.
- **Threshold decision (challengeable):** public copy with verifiable
  internal claims and no user-data surface — above `none` because durable
  and brand-bearing, below `single-user incident` because no user action or
  data hangs on it.

## Observability

```yaml
liveness_signal:
  what: "Docs deploy + redirect apply are both push-triggered on main: deploy-docs.yml publishes the five posts; apply-web-platform-infra.yml applies the five new bulk-redirect pairs"
  cadence: "per merge to main"
  alert_target: "GitHub Actions run status on main (red run = failed publish or apply)"
  configured_in: ".github/workflows/deploy-docs.yml, .github/workflows/apply-web-platform-infra.yml"
error_reporting:
  destination: "GitHub Actions run logs + PR check status"
  fail_loud: "deploy-docs or apply-web-platform-infra red run; validate-blog-links Guard-1 FAIL lines pre-merge"
failure_modes:
  - mode: "post file missing/malformed frontmatter"
    detection: "Eleventy build fails or seo-aeo-drift-guard reds in CI"
    alert_route: "required-check red on the PR"
  - mode: "dated slug has no redirect pair"
    detection: "validate-blog-links.sh Guard-1 parity check"
    alert_route: "CI blog-link-validation suite red"
  - mode: "social card 404"
    detection: "ogImage frontmatter must point at a committed png; seo-aeo-drift-guard threads it into BlogPosting.image"
    alert_route: "CI red; link-preview inspection on share"
logs:
  where: "GitHub Actions run logs for ci.yml, deploy-docs.yml, apply-web-platform-infra.yml"
  retention: "GitHub-hosted run retention"
discoverability_test:
  command: "grep -c -e 'first-property-test-found-real-bug' -e 'map-that-cant-drift' -e 'test-the-migration-not-just-the-schema' -e 'map-that-only-records-what-the-agent-saw' -e 'flaky-test-passed-on-retry-quarantine' apps/web-platform/infra/seo-bulk-redirects.tf"
  expected_output: "5"
```

## Encryption Posture

```yaml
at_rest:
  - store: "cloudflare_list bulk-redirect list items (existing resource; Terraform state on the existing encrypted R2 backend)"
    mechanism: "provider-managed: Cloudflare account-level list; no new store introduced — five map entries appended to an existing committed list"
    evidence: "apps/web-platform/infra/seo-bulk-redirects.tf local.blog_redirect_pairs (entries appended in this diff)"
    defends_against: "n/a — redirect map entries are public routing metadata, not a data store"
    does_not_defend: "anything; the entries are not sensitive material"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — post-merge, curl each dated URL shape and observe the 301 to the canonical slug"
in_transit:
  - connection: "visitor -> soleur.ai edge redirect -> canonical post URL"
    enforced_at: "apps/web-platform/infra/seo-bulk-redirects.tf (existing cloudflare_ruleset wiring; unchanged by this diff)"
    tls: "https at the Cloudflare edge — pre-existing, unchanged"
    cert_verification: "on (vendor edge; unchanged)"
    does_not_defend: "n/a — no new connection is introduced; the redirect targets are https URLs in the same map"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/seo-bulk-redirects.tf`: five entries in
  `local.blog_redirect_pairs`. No new resources, providers, variables, or
  secrets; no `terraform import`.

### Apply path

- `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**` on
  push to main (its only other entry point is `workflow_dispatch` with a
  `reason` input). Merging this PR therefore mutates production exactly once:
  the account-level bulk-redirect list gains five items. **PR body line 1
  must state this.** Expected blast radius: five added edge 301s; no resource
  replacement; no downtime.

### Host fan-out

- N/A — no `terraform_data` SSH provisioner and no host is touched.

### Distinctness / drift safeguards

- Redirects are edge config, identical dev/prod semantics; no
  `lifecycle.ignore_changes` interplay. State already contains
  `cloudflare_list` items of the same shape.

### Vendor-tier reality check

- Cloudflare bulk-redirect list items are within existing account quotas
  (the map already carries ~29 pairs); no free-tier gate needed.

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** (inline — domain-leader Task spawn unavailable in this
subagent context; assessment performed against `brand-guide.md` +
`content-strategy.md` directly.) This IS the marketing deliverable: five
Pillar-2 methodology spokes of the agentic-verification arc, one PR per the
operator directive. Binding constraints are mechanical and already enforced:
General register, founder-first openings, jargon limits (blog-jargon-scan),
absolute-URL distribution rules, one closing technical link per post,
waitlist CTA, HN submits write-ups not posts. The briefs' channel lists map
cleanly onto the distribution file's channel enum. Content-strategy rows for
all five issues already exist (~lines 261, 278–281); nothing to add there.

**Brainstorm-recommended specialists:** none (no brainstorm ran; the briefs
are the CMO gate's own output). `soleur:marketing:copywriter` coverage is
inherent — the draft step IS the content pipeline (content-writer + jargon
scan + fact-checker at work time).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Do all of those ideally in one PR" [operator directive in invocation] | single-PR shape; shared-work-once phases (2.x, 3.2); AC13 | mapped |
| 2 | "write all five remaining agentic-verification arc spoke posts (epic 10902)" [operator directive] | Phase 1 → five post files; Draft Specs 1–5 | mapped |
| 3 | "each post gets a distinct publish date — the Tue/Thu slot convention used by prior spokes; existing scheduled distribution rows occupy 2026-10-27 and 2026-10-29" [operator directive] | schedule table (Overview); per-spoke dates 2026-11-03/05/10/12/17; AC11 | mapped |
| 4 | "blog post under plugins/soleur/docs/blog/ + Pillow OG image + seo-bulk-redirects.tf pair + hub↔spoke links + knowledge-base/marketing/distribution-content/ file + campaign-calendar regen" [operator directive — the spoke file set] | Files to Create/Edit lists; Phases 1–3 | mapped |
| 5 | "blog scheduled (not with-merge); X thread" + per-issue hooks and data points [issues #10636, #10694, #10730, #10737, #10739 bodies] | per-spoke Draft Spec outlines + fact pins; Phase 3.1 distribution files | mapped |
| 6 | "the arc post links each child post per the one-link rule … children retro-link" [#10902 brief — hub-and-spoke design] | Phase 2.2 (five hub sentences) + per-spoke retro-link AC7 | mapped |
| 7 | "#10736 is a related open decision-challenge about feature-map citation scope — read it for context" [operator directive] | read and absorbed; #10737 fact pin + Dependencies & Risks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| five `docs/blog/<date>-<slug>.md` posts | "write all five remaining agentic-verification arc spoke posts" + per-brief "1,500-2,000" lengths | asked |
| five `og-<slug>.png` files | — | inferred — justification: `ogImage` is mandatory for every post (seo-aeo-drift-guard + content-writer); a post cannot land without it |
| five `seo-bulk-redirects.tf` pairs | "seo-bulk-redirects.tf pair" [operator directive] + validate-blog-links Guard-1 fails CI for any date-prefixed post with no entry | asked |
| hub-post spoke-link edits | "hub↔spoke links" [operator directive] + "the arc post links each child post per the one-link rule" [#10902 brief] | asked |
| five `distribution-content/<date>-<slug>.md` | "knowledge-base/marketing/distribution-content/ file" [operator directive] + briefs' channel lists | asked |
| `campaign-calendar.md` regen | "campaign-calendar regen" [operator directive]; the file is auto-generated from distribution-content frontmatter | asked |
| Pillow OG generation (not gemini-imagegen) | "Pillow OG image" [operator directive]; GEMINI keys dead (#10940 still open); Pillow shipped the arc + both sibling cards | asked |
| distinct Tue/Thu dates 2026-11-03→17 | "each post gets a distinct publish date — the Tue/Thu slot convention" [operator directive]; specific dates chosen to keep spacing past the occupied 10-27/10-29 slots | asked (dates inferred — justification: the directive fixes the convention and the occupied slots; the next five free Tue/Thu slots are the only conformant assignment) |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (docs blog + images),
  `apps/web-platform` (infra tf), `knowledge-base` (marketing files)
- Planned files: 18 (5 posts, 5 pngs, 5 distribution files, tf edit, hub
  edit, calendar regen)
- Estimated changed lines: ~2,200 (mostly post bodies; ~350/spoke + shared
  wiring)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated
  lines — the lines estimate exceeds 800, but the operator directive ("one
  PR") is an explicit scope decision that overrides the advisory threshold;
  the diff is five structurally identical file sets + three small shared
  edits, reviewable per spoke. Recorded here rather than silently ignored.
- Recommendation: single PR (operator-directed; threshold exceedance noted)

## Acceptance Criteria

- [ ] AC1 — All five post files exist at the paths in Files to Create, each
      with frontmatter carrying `title`, `seoTitle`, `date:` matching its
      filename (unquoted), `description` (120–160 chars), `ogImage`,
      `pillar: billion-dollar-solo-founder`, `tags`; no `layout`/`ogType`
      keys (inherited from `blog.json`).
- [ ] AC2 — Each post's body word count is 1,500–2,000 (frontmatter and
      JSON-LD excluded).
- [ ] AC3 — `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh`
      exits 0 on all five posts; no issue/PR numbers, backticks, code,
      paths, commands, or tool names in reader-visible text; zero code
      blocks.
- [ ] AC4 — Sequence honesty per spoke: #10636 carries the day-one defect +
      twin + both-now-fixed arc; #10694 carries 27 mapped / 5 exempt / 32
      reachable AND the advisory-in-CI framing (never "fails the merge");
      #10730 carries the old-system-as-oracle apparatus AND the
      not-schema-migrations scope honesty; #10737 carries
      seeds-exercised-only + zero-exercised-no-seed + field-scoped refresh;
      #10739 carries one-isolated-rerun + sentinel dedup + the vacuous
      all-screened-out row fix + the six axes.
- [ ] AC5 — Five `plugins/soleur/docs/images/blog/og-<slug>.png` files exist
      (1200×630) and each post's `ogImage` frontmatter references its own.
- [ ] AC6 — `local.blog_redirect_pairs` contains all five new pairs;
      `grep -c -e 'first-property-test-found-real-bug' -e 'map-that-cant-drift'
      -e 'test-the-migration-not-just-the-schema' -e
      'map-that-only-records-what-the-agent-saw' -e
      'flaky-test-passed-on-retry-quarantine' apps/web-platform/infra/seo-bulk-redirects.tf`
      prints `5` (repeated `-e` form — Check 10 rejects `|` bytes even inside
      a quoted regex).
- [ ] AC7 — Each post retro-links the arc hub once
      (`{{ site.url }}/blog/agentic-verification-checklist-shipped/`), and the
      hub gains exactly five new spoke-link sentences (two in the map
      section, one each in the other three), one per spoke; each post
      carries exactly one closing technical link and one CTA link.
- [ ] AC8 — Five `distribution-content/<date>-<slug>.md` files exist with
      `status: draft`, the correct `issue_reference` per spoke, channels
      `x, bluesky, discord, linkedin-personal`, and the four matching
      section headings; `bash scripts/lib/validate-tweet-draft.sh` exits 0
      on each.
- [ ] AC9 — `knowledge-base/marketing/campaign-calendar.md` regenerated once
      to enumerate all five new distribution files.
- [ ] AC10 — `bun test` suites `seo-aeo-drift-guard`,
      `marketing-content-drift`, `distribution-content-format`,
      `blog-audience-contract` green; `npm run docs:build` clean; `bash
      scripts/validate-blog-links.sh` Guard-1 green.
- [ ] AC11 — Per spoke, filename date, frontmatter `date:`, distribution
      filename, and redirect-pair key carry the same publish date
      (2026-11-03, 11-05, 11-10, 11-12, 11-17 respectively); if a date
      shifts at ship time, all four surfaces move together.
- [ ] AC12 — PR body line 1 states the merge-mutates-production answer
      (bulk-redirect list gains five items via auto-apply; posts publish via
      deploy-docs) and the body carries `Closes #10636`, `Closes #10694`,
      `Closes #10730`, `Closes #10737`, `Closes #10739`.
- [ ] AC13 — Sibling-boundary caps honored: the #10636 post references the
      vacuous-example post-mortem in at most one line (and may link the
      published sibling); #10694 ↔ #10737 cross-reference in at most one
      line each; no post retells a sibling's payload.

## Test Scenarios

- `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh
  <each of the five post paths>` → rc 0 (verified against the published hub
  during planning; it exits 0 on clean text). *(integration)*
- `bash scripts/lib/validate-tweet-draft.sh <each of the five distribution
  files>` → rc 0 (verified against the sibling `status: draft` file during
  planning). *(integration)*
- `npm run docs:build` → clean build including the five new posts; then
  `bash scripts/validate-blog-links.sh` → Guard-1 parity PASS for all five
  dated slugs. *(integration; suite name `blog-link-validation` in
  test-all.sh)*
- `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` → green; specifically:
  ogImage→BlogPosting.image thread ×5, pillar key resolves ×5, FAQ↔JSON-LD
  parity ×5, distribution channel/section parity + absolute-URL rule ×5,
  brand-claim bans. *(unit/integration)*
- Word count: `awk`/`wc -w` over each body region (exclude frontmatter and
  the `<script>` JSON-LD) lands in [1500, 2000]. *(unit)*
- Mutation-minded spot checks (manual at work time, not new code): deleting
  one ogImage file or one redirect pair must red the corresponding suite —
  already-instrumented repo guards, not new machinery.

## Success Metrics

- Five posts live at `https://soleur.ai/blog/<slug>/` after the next docs
  deploy; each dated-slug URL 301s to its canonical slug.
- Five distribution drafts promotable by the existing cron publisher
  (status flip + publish_date) with no further authoring.
- The arc hub visibly links all five spokes (the second distribution wave
  per the hub-and-spoke design completes the arc).
- Epic #10902's five child briefs close with the merge.

## Dependencies & Risks

- **Publish-date assumptions.** The five dates are assumed (next free
  Tue/Thu slots after the occupied 2026-10-27/10-29 pair). Recorded in
  decision-challenges as operator-schedule items; coherent-renaming rule is
  AC11. All five go live on merge regardless — the dates are
  canonical-URL/calendar labels, not release gates.
- **Gemini image generation unavailable** — Pillow fallback is planned ×5;
  quality bar matched to the cards shipped in #10922/#10996/#11067.
- **Hub edit scope.** Five sentences appended to a published post is a
  facts-only refresh; the Blog note permits fact updates and pins
  title/slug/H1/meta. The map section absorbs two links — phrased as
  distinct companions (our map's guard vs the convention for a founder's
  codebase) so it does not read as a duplicate.
- **#10736 pendulum risk.** The open citation-scope challenge could narrow
  the convention's consumer set after this post ships. Mitigation: the
  #10737 post describes the convention document's contract (seed-only-
  exercised, field-scoped refresh, entry schema), which is independent of
  how many skills cite it.
- **#10739 brief tension.** Its own brief queued it as "a methodology
  candidate," not a standalone piece; the operator directive overrides —
  noted in decision-challenges so the intent is on record.
- **Review-load risk.** Five posts in one diff concentrate the fact-check
  burden; the per-spoke fact pins + AC4 sequence-honesty + jargon-scan +
  content-writer fact-checker phase carry it. If the diff proves
  unreviewable as one PR, the seam is per-spoke — but the operator already
  ruled single-PR.
- **HN submissions** stay conditional on slot adjacency and submit technical
  write-ups — no action in this PR beyond noting it.

## References & Research

- Issues: #10636, #10694, #10730, #10737, #10739 (the five briefs); #10902
  (arc hub + hub-and-spoke design); #10903, #10904 (closed sibling briefs);
  #10736 (open citation-scope decision-challenge); #10633 (closed — the SQL
  twin fix); #10940 (OPEN — GEMINI rotation, the Pillow-fallback reason).
- PRs: #10922 (arc hub), #10996 (sibling spoke 1), #11067 (sibling spoke 2 —
  the structural template), #10624, #10666, #10727, #10735, #10738 (merged
  sources).
- Source docs: enumerated per-spoke in Research Insights; brand-guide
  §Channel Notes > ### Blog; `plugins/soleur/skills/content-writer/SKILL.md`.
- Template plan:
  `knowledge-base/project/plans/archive/20261025-150240-2026-10-25-content-pbt-methodology-spoke-plan.md`.
- Workflow refs: `.github/workflows/apply-web-platform-infra.yml`,
  `.github/workflows/deploy-docs.yml`.

### Sharp-edge note

A plan whose `## User-Brand Impact` section is empty or placeholder-only
fails deepen-plan Phase 4.6; it is filled above. Commands prescribed in Test
Scenarios were executed once during planning where their green state is
pre-change-independent (jargon scan on the hub rc 0; tweet-draft validator on
the sibling draft rc 0; the five-slug redirect grep prints `0` pre-change by
construction and `5` post-change).
