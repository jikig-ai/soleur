---
title: "content(blog): arc synthesis — 'First We Made Green Mean Something. Then We Made It Fast.' (#10971)"
type: content
date: 2026-10-28
slug: content-testsuite-arc-synthesis
branch: feat-one-shot-11362-arc-synthesis
issue: 11362
closes: 11362
priority: p3-low
domain: marketing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# Content: arc synthesis — "First We Made 'Green' Mean Something. Then We Made It Fast." (#11362)

## Overview

Write and ship the Pillar-2 methodology arc-synthesis article for epic #10971
("testsuite improvements (local + CI machinery)", closed 2026-10-27 with every
child shipped): twelve consecutive changes rebuilt what a green test verdict
means — seven fixed the verdict's accounting (pre-existing-failure baseline,
skip counted as pass, printf-SIGPIPE flake masking, orphan-suite lint blind
spot, incident-sandbox leakage on direct runs, stale selection edges to deleted
subjects, Inngest step-boundary census), then five added throughput (PR
path-gating, main-health-monitor sharding, bounded selection as the default,
affected-selector convergence, opt-in lane-based parallelism measured at 1.88×
on the bounded benchmark corpus with the serial default untouched). The brief's
angle (#11362, CMO-filed at epic close): honesty was sequenced before speed —
"we refused to make the suite faster until the verdict could be trusted — and
the suite being repaired judged all twelve repairs."

The post is a sequel to the agentic-verification arc hub (#10902, published at
`plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`),
scheduled for the Nov 19–26, 2026 window — the first open slots after the
Nov 17 committed item, and at least three weeks after the Oct 24 hub so it
reads as a continuation, not a repeat.

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed);
> no `spec.md` exists for this branch at plan time.

## Problem Statement / Motivation

The #10971 epic is the strongest proof point in the codebase that "green CI" is
a claim, not a fact: the test arbiter that judged every pull request was itself
lying in at least four distinct ways, and the same arbiter then adjudicated its
own rebuild across twelve merges with zero broken mains. Founders reading the
Pillar-2 arc have already met the verification-machinery story (#10902 hub and
its spokes); the synthesis lands the second half of the argument — that the
discipline extends to the machinery that checks the machinery — and converts a
closed internal epic into public methodology content on the Blog's actual
reader: a non-technical solo founder.

## Proposed Solution

Produce one PR containing:

1. The blog post (~1,500–2,000 words, General register per the brand-guide Blog
   note) at `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`,
   drafted through the prescribed `soleur:content-writer` route (frontmatter,
   FAQ + parity-matched FAQPage JSON-LD, Blog-note jargon limits, founder
   re-angle) with a `soleur:marketing:fact-checker` pass on the defect-class
   taxonomy — both are plan-prescribed inline checkpoints at work time, per the
   brief's Drafting route.
2. A bespoke OG image at
   `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png`
   (1200×630, flat `#1a1a1a` background, gold `#c9a962`/`#dcbe6e` geometry,
   textless) generated with deterministic PIL per
   `knowledge-base/project/learnings/best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`
   — `soleur:gemini-imagegen` is unavailable (#10940 OPEN; stored GEMINI keys
   dead) and Pillow shipped the sibling arc card (#10939).
3. A dated→canonical redirect pair in `apps/web-platform/infra/seo-bulk-redirects.tf`
   `local.blog_redirect_pairs` (every date-prefixed post needs an edge 301
   entry; enforced by `scripts/validate-blog-links.sh` and
   `plugins/soleur/test/lib/bulk-redirect-pairs.ts`).
4. A social-distribution draft at
   `knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md`
   — `status: parked` + `publish_date: 2026-11-19`, channels
   `x, bluesky, discord, linkedin-personal`. Parked is the documented hold
   lever (content-strategy.md §Hold lever): it excludes the file from
   auto-promotion while its `publish_date` still occupies the Nov 19 slot so
   nothing double-books it. Shipping `status: draft` instead would let
   `content-promotion.ts` rewrite `publish_date` to the earliest free Tue/Thu
   slot (~Oct 29), violating the window.
5. A publish-window follow-through: `scripts/followthroughs/parked-green-synthesis-11362.sh`,
   a NOTIFY-ONLY probe (exit 2 = not yet inside the window; exit 5 = ACTION
   REQUIRED on/after 2026-11-19 while the file is still `parked`; exit 3 =
   cannot establish) plus a `<!-- soleur:followthrough … -->` tracker directive
   and `follow-through` label on #11362. The flip `parked → scheduled` is the
   documented one-line lever the probe wakes for — the publisher then fires
   the file on Nov 19 14:00 UTC exactly.
6. A one-sentence sequel-link edit inside the published arc hub
   (`plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`,
   in its closing section) — facts-only refresh of a published post per the
   Blog note; readers of the first arc should find the sequel.
7. The content-strategy pipeline row the brief proposes, appended to the
   Pillar-2 methodology table in `knowledge-base/marketing/content-strategy.md`
   (real 5-column schema `| Piece | Type | Words | Priority | Status |`,
   matching sibling rows).
8. Regenerated `knowledge-base/marketing/campaign-calendar.md` via the
   `soleur:campaign-calendar` skill (auto-generated from `distribution-content/`
   frontmatter — the regen-by-inventory habit from the cited learning).

## Technical Considerations

- **Filename date coherence (one source of truth).** Blog filename date,
  frontmatter `date:`, the redirect pair's key, and the distribution file's
  `publish_date:` all carry `2026-11-19` — the first open Thursday slot after
  the Nov 17 committed item, inside the brief's Nov 19–26 window. There is no
  future-date exclusion in `eleventy.config.js` — the post goes live on
  merge-to-deploy regardless of `date:` (sibling precedent: the Nov 17 post is
  already committed with a future date). The publish *window* governs the
  distribution wave + display date, not URL availability; if the operator wants
  a different slot inside the window, all four date sites move together.
- **The `parked` mechanism is measured, not assumed.** `isReadyDraft`
  (`apps/web-platform/server/inngest/functions/content-promotion.ts:176-187`)
  requires `status === "draft"`; `occupied` is the `publish_date` of EVERY
  file carrying one (`cron-content-publisher.ts:264-292`), and
  `nextTueThuSlots` assigns ready drafts to the earliest free Tue/Thu in the
  28-day horizon (`content-promotion.ts:197-260`). A `status: draft` file
  merged in late October would promote to ~Oct 29 — three weeks early.
  `status: parked` is inert to `isReadyDraft`, to
  `distribution-content-format.test.ts` (which validates only
  `scheduled|draft`), and to the publisher (`content-publisher.sh` fires only
  `status == "scheduled"` && `publish_date == today`).
- **`validate-tweet-draft.sh` requires `status: draft`.** Author the file as
  `status: draft`, run the validator green, then flip to `status: parked` as
  the final edit in the same commit — the format guard is inert on `parked`.
- **Jargon limits are mechanical, not stylistic.** `blog-jargon-scan.sh` flags
  backticks, code/pre tags, `--flags`, and `#NN` tokens in reader-visible text;
  the Blog note bans file paths, commands, API/tool names, internal
  skill/agent names, and issue/PR numbers outright (allowed only inside the
  one closing GitHub URL). All epic internals render in founder terms: test
  suite → "the checks that run before work ships"; SKIP-as-pass → "a check that
  reported 'skipped' was counted as a pass"; sandbox leak → "a throwaway test
  environment that sometimes survived into the real one"; selection edge →
  "the map telling the runner which checks a change needed."
- **Fact-check pins for the writer (the fact-checker pass's job is to verify
  each against source):**
  - Split is **7 honesty children / 5 speed children**: honesty = #8335
    (baseline, PR #10973), #9325 (SIGPIPE flake, #10989), #8773
    (SKIP→UNRESOLVED, #11031), #7718 (orphan lint, #11045), #8659
    (EXIT-trap sandbox leak, #11051), #9441 (deleted-subject edge, #11056),
    #8764 (step-harness census, #11278); speed = #9323 (path-gate, #11088 —
    **issue deliberately stays OPEN for the soak verdict; the caveat is the
    point**), #9410 (sharding, #11119), #10333 (bounded default +
    `--print-selection`, #11153), #8621 (selector convergence, #11264), #8231
    (opt-in parallel scheduler, #11282). All twelve PRs verified MERGED at
    plan time.
  - **1.88× is the bounded fixture corpus** (4 sleep + 4 CPU-bound suites,
    serial 4,642 ms → parallel 2,472 ms @ jobs=4) from
    `scripts/test-all-parallel-benchmark.test.sh` — opt-in lane scheduler,
    serial default preserved. Do NOT cite the larger 6.22× figure (a
    different gate measurement over the registered population in the #8231
    acceptance evidence); the brief's "measured modesty" chooses 1.88×.
  - **Suite count:** the brief says "~686-suite arbiter" (epic-close census).
    Plan-time evidence: `git ls-files '*.test.sh'` = 757 tracked files and
    `scripts/suite-shard-legs.tsv` = 673 shard rows; the registered
    population the runner discovers is what the sentence means. Phrase as
    "nearly 700" or "around 680" — fact-checker pins the exact figure via the
    registered population, never 757.
  - **Taxonomy honesty:** say "the machinery's lies," NOT "every fix was
    accounting" — #8335 fixed real failing suites (per the brief's own
    cross-child note).
  - **Precedent phrasing:** ratchets-as-governance is "a continuation, not a
    first claim" — #8326 (state-machine post, still OPEN/unpublished) and
    #10694 (published `map-that-cant-drift`) precede it.
- **OG image is a hard CI gate** (`seo-aeo-drift-guard.test.ts` threads
  `ogImage` into BlogPosting.image; content-writer treats it as mandatory).
  PIL is the plan; if generation is somehow unavailable, reuse the nearest
  on-theme card rather than omit the field.
- **No Liquid in distribution bodies** (`lint-distribution-content.sh`);
  distribution links must be absolute `https://soleur.ai/…` URLs with UTM
  params per arc precedent, each declared channel needs its exact section
  heading (`## X/Twitter Thread`, `## Bluesky`, `## Discord`,
  `## LinkedIn Personal`), labeled tweets ≤ 280 chars.
- **FAQ parity.** If the post carries a visible `## Frequently Asked
  Questions` section, its questions/answers must match the FAQPage JSON-LD
  `mainEntity` twins verbatim (`seo-aeo-drift-guard.test.ts` parity tests).
  Follow the arc post's format: `###` question headings + plain answers +
  trailing JSON-LD block.
- **Merging this PR mutates production (first line of the PR body).**
  `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**` on
  push to main — the bulk-redirect list gains the new pair at merge. Deploy of
  the post itself goes through `deploy-docs.yml` (push to main,
  `plugins/soleur/docs/**`).
- **Brand/subject claims.** `marketing-content-drift.test.ts` bans
  Soleur-subject Apache-2.0/open-source claims and "Spark"-tier references;
  soft-floor rules apply to agent/skill counts in prose.
- **Pillar frontmatter** must resolve to a `_data/pillars.js` series key; use
  `pillar: billion-dollar-solo-founder` (the arc hub's series). No
  `members[]` row — the hub declares the key without membership.
- **One guard-shaped deliverable: the follow-through probe.** The post and
  wiring are prose + a PNG + map/table/frontmatter edits (no `lint-*`, hook,
  or CI gate), but `scripts/followthroughs/parked-green-synthesis-11362.sh`
  IS an assertion-based control — a probe whose wrong verdict silently
  misses the publish window. Plan Phase 2.12 therefore fires; the contract
  is emitted in `## Guard Contract` below and the probe's task surface in
  `## Task Design`.
- **Precedent-diff:** the only code-shaped edit is a one-line map append in
  `seo-bulk-redirects.tf` — the file's own `blog_redirect_pairs` convention is
  the precedent (most recent entry added for the Nov 17 post); the diff is
  identical in shape, differing only in the slug strings.

## Research Insights

**Premise validation (Phase 0.6).** Every cited reference verified live:

- Epic #10971 **CLOSED** (per spawn note — cited in date-anchored prose only,
  never as a work target); its close comment enumerates all 12 children with
  their PRs. All 12 PRs verified **MERGED** individually at plan time.
- Cited issues: #10902 CLOSED (arc hub published); #8335, #10397, #10694,
  #8764 CLOSED; #8326 OPEN (state-machine governance post, unpublished);
  #9323 OPEN **deliberately** (soak verdict window — the brief's honest-limit
  caveat); #11364 OPEN (the #8764 census-lint spoke brief, sibling work, no
  overlap).
- Cited machinery verified: `scripts/test-all-parallel-benchmark.test.sh`
  (1.88× line), `scripts/suite-shard-legs.tsv` (673 rows),
  `apps/web-platform/server/inngest/functions/content-promotion.ts`
  (promotion mechanics), `scripts/content-publisher.sh` (publish semantics),
  `scripts/lib/validate-tweet-draft.sh` (`status: draft` requirement),
  `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh`,
  `scripts/validate-blog-links.sh` — all exist on this branch.
- **Collision precheck:** `collision-precheck.sh 11362` flagged PR #11378 —
  that is THIS pipeline's own auto-created draft PR on branch
  `feat-one-shot-11362-arc-synthesis`, not a foreign duplicate. Reported, not
  blocking.
- Proposed mechanism vs ADR corpus: the delivery mechanism (blog post +
  Cloudflare bulk-redirect pair + distribution draft + parked hold lever)
  follows conventions ADR-194 and the #3328 redirect migration established;
  no ADR's rejected-alternatives table is re-entered.

**Property list (Phase 0.6b).**

1. A Pillar-2 arc-synthesis post exists and reads to the blog's founder
   audience (Blog note).
2. Its claims trace to the closed epic's measured record (fact-checked
   taxonomy: 7 honesty / 5 speed, 12 merges, 1.88× opt-in, open soak caveat).
3. Its URL is stable/canonical — dated→canonical redirect pair present.
4. Social payloads exist for the declared channels, held for the prescribed
   Nov 19–26 window rather than the machinery's earliest free slot.
5. All existing content gates stay green (ogImage, jargon scan, tweet-draft
   structure, redirect parity, content-drift, FAQ parity).

**Cut list.** No new machinery proposed or needed:

- content-writer conventions + `blog-jargon-scan.sh` +
  `validate-tweet-draft.sh` + `validate-blog-links.sh` already cover every
  property — no new validator.
- The `status: parked` hold lever + notify-only follow-through probe are
  existing documented machinery — no "publish-at-date" mechanism is invented.
- `pillars.js` membership row — not needed (hub precedent: declare the key
  only).
- Campaign-calendar regeneration uses the existing `soleur:campaign-calendar`
  skill — not a new script.

**Relevant file paths.**

- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
  — the previous arc hub; format + voice + FAQ/JSON-LD convention; also the
  retro-link target and the sequel-link edit site.
- `plugins/soleur/docs/blog/2026-11-17-flaky-test-passed-on-retry-quarantine.md`
  — most recent post; frontmatter + scheduling convention.
- `knowledge-base/marketing/brand-guide.md` §Channel Notes > ### Blog —
  register, founder-sentence rule, jargon limits, one-closing-link rule, CTA
  rule, HN rule.
- `plugins/soleur/skills/content-writer/SKILL.md` — frontmatter schema,
  unquoted `date:`, ogImage mandate, jargon-scan phase, fact-checker phase.
- `knowledge-base/marketing/distribution-content/2026-11-17-flaky-test-passed-on-retry-quarantine.md`
  and `2026-10-23-agentic-verification-arc.md` — distribution file precedents
  (frontmatter shape, section headings, UTM link style).
- `apps/web-platform/infra/seo-bulk-redirects.tf` (`local.blog_redirect_pairs`)
  — append one pair at the end of the ascending-date map.
- `apps/web-platform/server/inngest/functions/content-promotion.ts` +
  `cron-content-publisher.ts` + `scripts/content-publisher.sh` — the
  slot-assignment machinery the `parked` decision was measured against.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
  — notify-only probe exit-code vocabulary (2/3/5).
- `knowledge-base/project/learnings/best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`
  — PIL OG convention + the audit-every-ogImage habit.
- `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`
  — the #8231 measurement record (6.22× gate; do not conflate with the 1.88×
  fixture benchmark).
- `knowledge-base/project/plans/archive/20261024-214442-2026-10-24-content-guardrail-audit-spoke-plan.md`
  — sibling content plan whose shape this plan mirrors.

**Institutional learnings applied.**

- `2026-10-21-one-regen-gap-three-committed-state-reds.md` — regenerate
  derived artifacts by inventory: the distribution file is enumerated by
  `campaign-calendar.md` (regenerated), the dated post filename by
  `blog_redirect_pairs` (the .tf edit), the OG image by `ogImage` frontmatter.
- `2026-10-21-sibling-session-owned-commits-on-my-branch.md` — stage only
  this feature's paths.
- `2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`
  — PIL generation + audit every `ogImage` reference, not only the new one.

**CLAUDE.md / constitution conventions.** kebab-case filenames;
`YYYY-MM-DD-<type>-<slug>-plan.md`; plan review precedes tasks.md; no version
bumps; General register for blog content.

**Findings (surfaced, not folded).**

- The brief's "~686-suite arbiter" is an epic-close census figure; the live
  registered population drifts with every suite merge. The Draft Spec pins
  "nearly 700"-class phrasing and assigns the exact count to the
  `soleur:marketing:fact-checker` pass.
- HN submission is conditional ("if the fortnight slot is free") and submits
  the technical write-up (the public epic), never the post (Blog note's HN
  rule); tracked as a distribution note, not a deliverable.
- The LinkedIn-Personal "T+4–7d" stagger from the brief is not mechanically
  encodable in the single-file distribution contract (one `publish_date`
  publishes every declared channel) — the arc hub's file made the same
  simplification; same-day publication of all four channels on the window
  date is the recorded disposition.

### Open Code-Review Overlap

Two hits, both **acknowledge**:

- **#10240** (`review: campaign calendar refresh on PR 10140`) — a per-PR
  review record of a specific calendar refresh; not a scope-out touching any
  file this plan creates. Our calendar regen is the standard generated-file
  workflow it does not conflict with.
- **#3649** (`marketing: PR-A2 #3603 content brief — schedule for PR-C merge`)
  — a different content piece's scheduling; touches no file this plan
  creates or edits. Sibling content work #11364 (#8764 spoke) is also noted
  — separate brief, no file overlap.

## Files to Create

- `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`
  — the arc-synthesis post
- `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png`
  — OG card (PIL)
- `knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md`
  — social draft (`status: parked`)
- `scripts/followthroughs/parked-green-synthesis-11362.sh` — notify-only
  publish-window probe

## Files to Edit

- `apps/web-platform/infra/seo-bulk-redirects.tf` — append one
  `blog_redirect_pairs` entry
- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`
  — one-sentence sequel link
- `knowledge-base/marketing/content-strategy.md` — append the proposed
  pipeline row to the Pillar-2 methodology table
- `knowledge-base/marketing/campaign-calendar.md` — regenerated by the
  campaign-calendar skill
- `knowledge-base/project/INDEX.md` (if regenerated by the work pipeline's
  own bookkeeping) and `knowledge-base/project/specs/<branch>/session-state.md`
  — pipeline-written artifacts listed for diff-scope completeness, per the
  sharp-edge on AC scope.

## Implementation Phases

### Phase 1 — Draft + image (prescribed skill checkpoint: `soleur:content-writer`)

- 1.1 Run `soleur:content-writer` conventions **inline** (Blog register) against
  the **Draft Spec** below: founder sentence first (working notes), General
  register, outline, redaction list, fact-check pin list.
- 1.2 Write `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`
  (frontmatter + 1,500–2,000-word body + FAQ section + parity-matched FAQPage
  JSON-LD).
- 1.3 Generate `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png`
  with PIL: 1200×630 RGB, `#1a1a1a` background, gold `#c9a962`/`#dcbe6e`
  strokes, textless abstract motif (suggested: a ledger/board of twelve cells —
  seven re-lit in gold, five in a fainter stroke — the honesty-before-speed
  visual), metadata-clean, 3× supersample + LANCZOS downscale per the PIL
  learning. If PIL generation is somehow unavailable, reuse the nearest
  on-theme `og-*.png` rather than omit the field.

### Phase 2 — Site wiring

- 2.1 Append to `local.blog_redirect_pairs` in
  `apps/web-platform/infra/seo-bulk-redirects.tf` (end of the ascending-date
  map, matching the column-aligned `=` style):
  `"2026-11-19-first-we-made-green-mean-something" = "first-we-made-green-mean-something"`.
- 2.2 Edit `2026-10-23-agentic-verification-checklist-shipped.md` — in its
  closing section, append one plain-words sentence linking the sequel:
  `[the next chapter]({{ site.url }}/blog/first-we-made-green-mean-something/)`.
  Facts-only update of a published post; title/slug/H1/meta/keywords untouched
  (Blog note's refresh rule).
- 2.3 Append the brief's proposed pipeline row to the Pillar-2 methodology
  table in `knowledge-base/marketing/content-strategy.md`, matching the
  table's real 5-column schema (`| Piece | Type | Words | Priority | Status |`)
  — e.g. `| First We Made 'Green' Mean Something. Then We Made It Fast. | Arc
  synthesis / methodology | 1,500-2,000 | P3 | scheduled, Nov 19–26 window.
  Issue #11362 (epic #10971 capstone). |`

### Phase 3 — Distribution draft + follow-through + calendar

- 3.1 Write
  `knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md`:
  frontmatter `title` (post title), `type: pillar`, `publish_date:
  2026-11-19`, `channels: x, bluesky, discord, linkedin-personal`,
  `issue_reference: "#11362"`; body sections `## X/Twitter Thread` (labeled
  `**Tweet N**`, each ≤ 280 chars, the four-ways-green-lied taxonomy as the
  payload thread, closing tweet links
  `https://soleur.ai/blog/first-we-made-green-mean-something/` with UTM params
  per arc precedent), `## Bluesky`, `## Discord`, `## LinkedIn Personal`.
  Author with `status: draft`, run `validate-tweet-draft.sh` green, then flip
  to `status: parked` as the last edit (the hold lever — see Technical
  Considerations).
- 3.2 Write `scripts/followthroughs/parked-green-synthesis-11362.sh`
  (notify-only; `#!/usr/bin/env bash` + `set -euo pipefail`; exits 2 before
  2026-11-19 or when the file already reads `status: scheduled`/`published`,
  5 on/after 2026-11-19 while the file still reads `status: parked` or
  `status: draft` (a draft in-window is already a violation — promotion
  rewrites its slot), 3 if the file is missing/unparseable, NEVER 0/1 per
  the convention's notify-only invariant; header states credential posture
  `none` + a `RETIREMENT:` line listing the tracker directive + this plan
  reference).
- 3.3 At ship time, file the tracker: `<!-- soleur:followthrough
  script=scripts/followthroughs/parked-green-synthesis-11362.sh
  earliest=2026-11-19 secrets= -->` + `follow-through` label on #11362 —
  the probe comments ACTION REQUIRED inside the window; the responder flips
  `status: parked → scheduled` in a one-line commit and closes the tracker.
- 3.4 Regenerate `knowledge-base/marketing/campaign-calendar.md`
  (campaign-calendar skill, `--headless`) so the new file is enumerated.

### Phase 4 — Verification (prescribed agent checkpoint: `soleur:marketing:fact-checker`)

- 4.1 `soleur:marketing:fact-checker` pass **inline** on the defect-class
  taxonomy per the brief's Drafting route: every load-bearing claim in the
  post maps to a named source (epic close comment, merged PR, benchmark
  script, acceptance evidence); UNSOURCED claims are cut or sourced.
- 4.2 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>`
  → rc 0; then a Blog-note read-through for the subset the scan does not
  detect (paths, tool names, bare numbers).
- 4.3 `npm run docs:build` clean; `bun test
  plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` green.
- 4.4 `bash scripts/validate-blog-links.sh` Guard-1 parity green (post ↔
  redirect pair).
- 4.5 Word count check: body (frontmatter + JSON-LD excluded) inside
  1,500–2,000.
- 4.6 Read-through pass against the fact-check pin list and the Redaction &
  claim list below — every claim traces to a cited source.

## Draft Spec (contract for the writer step)

- **Title (default):** "First We Made 'Green' Mean Something. Then We Made It
  Fast." — the issue's own title choice and the proposed pipeline-row name.
  The brief's lead candidate ("A Skipped Test Counted as a Pass. So We
  Rebuilt the Scoreboard.") is the recorded alternative if the writer judges
  it names the founder's problem more directly (taste call; decision-challenges).
- **Founder sentence (working notes, not the post):** "A solo founder has this
  problem: the automated checks their business leans on report 'fine' and they
  have no way to know what 'fine' is worth. After reading, they know what a
  trustworthy green actually requires — and that the honest order is
  truth-telling first, speed second."
- **Frontmatter:** `title` (above), `seoTitle` ≈ "We Made Green Mean
  Something, Then Made It Fast", `date: 2026-11-19` (unquoted), `description`
  120–160 chars carrying the honesty-before-speed hook, `ogImage:
  "blog/og-first-we-made-green-mean-something.png"`, `pillar:
  billion-dollar-solo-founder`, `tags: [methodology, ai-trust, solo-founder,
  build-in-public, pillar]`.
- **Outline (mapped to the brief's angle):**
  1. Opening — the founder's problem in their words: your tools report green;
     you have already learned to ask what green means.
  2. Green was lying, at least four ways — the four flagship lies in
     founder-legible form: a check that reported "skipped" counted as a pass;
     a whole directory of checks the orphan-finder could not see; the map
     still selecting checks for files that no longer existed; a baseline of
     known failures meaning nobody knew what green was worth.
  3. The rest of the dishonesty ledger — flake masking, a throwaway test
     environment leaking into the real one, a boundary census — seven repairs
     to what a verdict means, none to speed.
  4. Only then, speed — five changes (gating, sharding, bounded selection,
     converged selectors, opt-in parallelism at a measured 1.88×, serial
     default untouched) deliberately sequenced last.
  5. The part that lives in no single diff — the arbiter adjudicated its own
     rebuild: twelve consecutive merges, zero broken mains; the suite being
     repaired judged all twelve repairs.
  6. The honest limits — the caveat is the point: one child deliberately left
     open pending its soak verdict; the speed claim is a bounded-corpus,
     opt-in measurement, not a promise.
  7. The pattern continues — ratchets-as-governance extended to the suite
     itself; a continuation of the checklist arc (one retro-link sentence to
     the Oct 24 hub), not a first claim.
  8. The lesson for the founder — ask what green means before asking how fast
     it runs; then the single closing technical link: the public epic on
     GitHub (`https://github.com/jikig-ai/soleur/issues/10971`), then the
     waitlist CTA (`https://soleur.ai/pricing/#waitlist`).
- **FAQ (2–4 questions, parity JSON-LD):** e.g. "What does a green check mark
  actually prove?", "Can an automated check itself be wrong?", "Should speed
  come before accuracy in automated checks?", "How do I know whether to trust
  my AI tool's results?" — founder-readable answers only.
- **Numbers note for the draft:** 7 honesty / 5 speed / 12 merges / 1.88×
  bounded-corpus opt-in / "nearly 700" registered checks (fact-checker pins
  exact) / one child still open by design. Never `#` numbers, never file
  paths, never the 6.22× figure.
- **Redaction & claim list:** no issue/PR numbers in body (the one closing
  GitHub URL excepted); no skill/agent/command names; no file paths or
  commands; no exact suite-name internals; "the machinery's lies," not
  "every fix was accounting" (#8335 fixed real failing suites).

## User-Brand Impact

- **If this lands broken, the user experiences:** a published post on
  soleur.ai that misstates the epic's record (wrong split, wrong speed figure,
  a claimed caveat that is false), reads as jargon-walled engineering content
  to the founder audience, 404s its social card, or publishes its social wave
  weeks before the prescribed window — a public, durable artifact carrying a
  wrong or mistimed claim.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing —
  the post re-publishes an already-public engineering record (merged PRs, a
  public closed epic) in founder language; no user data, credentials, or
  internal-only detail ships in it.
- **Brand-survival threshold:** `aggregate pattern` — one wrong blog post is
  correctable (edit + redeploy); the risk class is a pattern of unreviewed
  public claims, which the fact-checker/jargon-scan/drift-test gauntlet
  covers.
- **Threshold decision (challengeable):** public copy with verifiable
  internal claims and no user-data surface — above `none` because the
  artifact is durable and brand-bearing, below `single-user incident` because
  no user action or data hangs on it.

## Observability

```yaml
liveness_signal:
  what: "Docs deploy + redirect apply are both push-triggered on main: deploy-docs.yml publishes the post; apply-web-platform-infra.yml applies the new bulk-redirect pair; the daily cron-content-publisher fires the parked file only after the scheduled flip"
  cadence: "per merge to main / daily 14:00 UTC publisher"
  alert_target: "GitHub Actions run status on main; campaign-calendar overdue flag; follow-through probe ACTION REQUIRED comment"
  configured_in: ".github/workflows/deploy-docs.yml, .github/workflows/apply-web-platform-infra.yml, scripts/content-publisher.sh, scripts/followthroughs/parked-green-synthesis-11362.sh"
error_reporting:
  destination: "GitHub Actions run logs + PR check status + follow-through sweeper comments"
  fail_loud: "deploy-docs or apply-web-platform-infra red run; validate-blog-links Guard-1 FAIL line pre-merge; parked file still parked inside the window (probe exit 5)"
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
  - mode: "distribution publishes outside the Nov 19-26 window"
    detection: "status: parked holds the file out of promotion; follow-through probe exit 5 if still parked on/after Nov 19"
    alert_route: "sweeper comment on the tracker issue"
logs:
  where: "GitHub Actions run logs for ci.yml, deploy-docs.yml, apply-web-platform-infra.yml; follow-through sweeper comments"
  retention: "GitHub-hosted run retention"
discoverability_test:
  command: "grep -c 2026-11-19-first-we-made-green-mean-something apps/web-platform/infra/seo-bulk-redirects.tf"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "cloudflare_list bulk-redirect list item (existing resource; Terraform state on the existing encrypted R2 backend)"
    mechanism: "provider-managed: Cloudflare account-level list; no new store introduced — one map entry appended to an existing committed list"
    evidence: "apps/web-platform/infra/seo-bulk-redirects.tf local.blog_redirect_pairs (entry appended in this diff)"
    defends_against: "n/a — a redirect map entry is public routing metadata, not a data store"
    does_not_defend: "anything; the entry is not sensitive material"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — post-merge, curl the dated URL shape and observe the 301 to the canonical slug"
in_transit:
  - connection: "visitor -> soleur.ai edge redirect -> canonical post URL"
    enforced_at: "apps/web-platform/infra/seo-bulk-redirects.tf (existing cloudflare_ruleset wiring; unchanged by this diff)"
    tls: "https at the Cloudflare edge — pre-existing, unchanged"
    cert_verification: "on (vendor edge; unchanged)"
    does_not_defend: "n/a — no new connection is introduced; the redirect target is an https URL that already exists in the same map"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/seo-bulk-redirects.tf`: one entry in
  `local.blog_redirect_pairs`. No new resources, providers, variables, or
  secrets; no `terraform import`.

### Apply path

- `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**` on
  push to main. Merging this PR therefore mutates production exactly once:
  the account-level bulk-redirect list gains one item. **PR body line 1 must
  state this.** Expected blast radius: one added edge 301; no resource
  replacement; no downtime.

### Host fan-out

- N/A — no `terraform_data` SSH provisioner and no host is touched.

### Distinctness / drift safeguards

- Redirects are edge config, identical dev/prod semantics; no
  `lifecycle.ignore_changes` interplay. State already contains
  `cloudflare_list` items of the same shape.

### Vendor-tier reality check

- Cloudflare bulk-redirect list items are within existing account quotas (the
  map already carries ~25 pairs); no free-tier gate needed.

## Guard Contract

### Guard 1 — publish-window probe (`parked-green-synthesis-11362.sh`)

**Property.** On/after the first day of the publish window, a distribution
file still holding `status: parked` (or still `draft`, meaning promotion can
steal the slot) surfaces an ACTION REQUIRED signal; nothing exits silent
while a window obligation is unmet.

**Assembly.** The chokepoint is the sweeper's per-tracker probe dispatch:
every `scripts/followthroughs/*.sh` referenced by a
`<!-- soleur:followthrough script=… -->` directive runs under
`scheduled-followthrough-sweeper.yml`, which maps the probe's exit code to a
tracker comment. The probe's own decision surface is one frontmatter field
(`status:`) × one date boundary (`publish_date` / window start) — the state
space is: pre-window, in-window + parked, in-window + draft, in-window +
scheduled/published, file missing.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Probe unconditionally `exit 0` (guard's own dispatch — a probe that never reports is vacuous) | RED |
| 2 | Probe `exit 2` while the file still reads `status: parked` on/after 2026-11-19 (the wake never fires — the exact window-miss this exists for) | RED |
| 3 | Probe `exit 2` while the file reads `status: draft` on/after the window start (a SECOND actionable state after the compliant first — a draft in-window is already a window violation because promotion rewrites its slot) | RED |
| 4 | Harness row: a probe run where the file reads `status: scheduled` inside the window — the compliant-but-not-canonical state the contract permits (the flip landed early; nothing to wake for) | must-PASS at exit 2 |
| 5 | File absent or unparseable — the probe must name its inability, not improvise a verdict | exit 3, not 0/2 |

## Task Design

```yaml
tasks:
  - task: "follow-through probe scripts/followthroughs/parked-green-synthesis-11362.sh (runs under the existing scheduled-followthrough-sweeper.yml — no new workflow)"
    trigger: "daily sweeper cron, gated by the tracker directive's earliest=2026-11-19"
    services: "reads distribution-content file frontmatter; writes tracker issue comments via the sweeper"
    next: "nothing — notify-only; the responder's parked-to-scheduled flip is the act it wakes for"
    human_reentry: "flip status: parked → scheduled in a one-line commit, then close the tracker and remove the follow-through label"
    dedupe: "one tracker directive on #11362; the probe's verdict is idempotent across sweeps (same state, same exit)"
    source_dedupe: "not a ticket source"
```

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** (inline — domain-leader Task spawn unavailable in this
subagent context; assessment performed against `brand-guide.md` +
`content-strategy.md` directly.) This IS the marketing deliverable: the
Pillar-2 arc synthesis for epic #10971, sequel to the #10902 hub. Binding
constraints are mechanical and already enforced: General register,
founder-first opening, jargon limits (blog-jargon-scan), absolute-URL
distribution rules, one closing technical link, waitlist CTA, HN submits the
write-up not the post. The brief's channels list maps cleanly onto the
distribution file's channel enum (`hackernews` is not an automated channel —
noted, not emitted).

**Brainstorm-recommended specialists:** none (no brainstorm ran; the brief is
the CMO epic-close sweep's own output). The brief's own Drafting route
prescribes `soleur:content-writer` (Blog register) + a
`soleur:marketing:fact-checker` pass on the defect-class taxonomy — both are
encoded as inline work-time checkpoints (Phases 1 and 4.1), not spawns this
plan can perform.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Pillar 2 methodology arc synthesis, ~1,500–2,000 words, general register (Blog note)" [issue #11362 DISPOSITION] | Phase 1 → blog post file; Draft Spec | mapped |
| 2 | "Publish window: Nov 19–26, 2026 (first open slots after the Nov 17 committed item; ≥3 weeks after the Oct 24 #10902 arc hub so it reads as a sequel)" [issue #11362] | `date: 2026-11-19` filename/frontmatter/redirect/publish_date coherence; `status: parked` hold lever; follow-through probe; hub sequel-link edit | mapped |
| 3 | "Drafting route: `soleur:content-writer` (Blog register) + `soleur:marketing:fact-checker` pass on the defect-class taxonomy" [issue #11362] | Phase 1 prescribed checkpoint + Phase 4.1 fact-checker checkpoint | mapped |
| 4 | "Channels: Blog primary → social-distribute (X thread + Bluesky + Discord + LinkedIn Personal T+4–7d). HN Tue–Thu takes the technical write-up only, if the fortnight slot is free." [issue #11362] | Phase 3.1 distribution file (all four channels, same-day per repo contract); LinkedIn stagger disposition recorded in Findings; HN noted as conditional write-up submission | mapped |
| 5 | "Proposed content-strategy.md pipeline row … `arc-synthesis-10971`" [issue #11362] | Phase 2.3 row appended to the Pillar-2 table | mapped |
| 6 | "honesty was sequenced before speed — seven children fixed what a verdict means … only then did five add throughput" + cross-child meta-findings [issue #11362 body] | Draft Spec outline items 2–7 + fact-check pin list | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md` | "Pillar 2 methodology arc synthesis, ~1,500–2,000 words" | asked |
| `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png` | — | inferred — justification: `ogImage` is mandatory for every post (seo-aeo-drift-guard + content-writer Phase 4.5); a new post cannot land without it |
| `apps/web-platform/infra/seo-bulk-redirects.tf` pair | — | inferred — justification: validate-blog-links Guard 1 fails CI for any date-prefixed post with no `blog_redirect_pairs` entry |
| hub post sequel-link edit | "≥3 weeks after the Oct 24 #10902 arc hub so it reads as a sequel" [issue #11362] | asked |
| `distribution-content/2026-11-19-…md` | "Channels: blog primary → social-distribute (X thread + Bluesky + Discord + LinkedIn Personal)" | asked |
| `status: parked` + follow-through probe | "Publish window: Nov 19–26, 2026" | inferred — justification: the promotion machinery assigns the earliest free Tue/Thu slot regardless of a pinned `publish_date`; `parked` is the documented hold lever and the probe is the documented wake mechanism for a date-gated flip |
| `content-strategy.md` pipeline row | "Proposed content-strategy.md pipeline row" | asked |
| `campaign-calendar.md` regen | — | inferred — justification: the file is auto-generated from distribution-content frontmatter; adding a file without regen repeats the cited regen-gap defect class |
| PIL OG generation (not gemini-imagegen) | — | inferred — justification: GEMINI keys dead (#10940, unrotated); PIL is the documented fallback and shipped the sibling card in #10939 |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (docs blog+images),
  `apps/web-platform` (infra tf), `knowledge-base` (marketing files) +
  `scripts/` (follow-through probe)
- Planned files: 6–7 (post, png, distribution md, probe, tf edit, strategy
  row, calendar regen, +1-line hub edit)
- Estimated changed lines: ~400 (mostly the post body)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated
  lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`
      exists; frontmatter carries `title`, `seoTitle`, `date: 2026-11-19`
      (unquoted), `description` (120–160 chars), `ogImage`,
      `pillar: billion-dollar-solo-founder`, `tags`; no `layout`/`ogType`
      keys (inherited from `blog.json`).
- [ ] AC2 — Post body word count is 1,500–2,000 (frontmatter and the JSON-LD
      block excluded).
- [ ] AC3 — `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>`
      exits 0; no issue/PR numbers, no backticks/code/paths/commands/tool
      names appear in reader-visible text (Blog note).
- [ ] AC4 — The taxonomy reads 7 honesty children / 5 speed changes / 12
      merges; the speed claim reads 1.88× bounded-corpus and opt-in (never
      6.22×); the open-soak caveat is stated; suite count phrased "nearly
      700"-class (never the 757 file-count).
- [ ] AC5 — `plugins/soleur/docs/images/blog/og-first-we-made-green-mean-something.png`
      exists (1200×630) and `ogImage:
      "blog/og-first-we-made-green-mean-something.png"` references it.
- [ ] AC6 — `local.blog_redirect_pairs` contains
      `"2026-11-19-first-we-made-green-mean-something" = "first-we-made-green-mean-something"`;
      `grep -c 2026-11-19-first-we-made-green-mean-something
      apps/web-platform/infra/seo-bulk-redirects.tf` prints `1`.
- [ ] AC7 — The post retro-links the Oct 24 hub once (`{{ site.url
      }}/blog/agentic-verification-checklist-shipped/`), and the hub post
      gains exactly one sentence linking `{{ site.url
      }}/blog/first-we-made-green-mean-something/`; the post carries exactly
      one closing technical link (the public epic on GitHub) and one CTA
      link.
- [ ] AC8 —
      `knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md`
      exists with `status: parked`, `publish_date: 2026-11-19`,
      `issue_reference: "#11362"`, channels `x, bluesky, discord,
      linkedin-personal`, and the four matching section headings; the X
      thread carries the defect-taxonomy payload within 280-char tweets.
- [ ] AC9 — `scripts/followthroughs/parked-green-synthesis-11362.sh` exists,
      is executable, carries the notify-only exit-code contract (2/3/5,
      never 0/1) and a `RETIREMENT:` header line.
- [ ] AC10 — `knowledge-base/marketing/content-strategy.md` Pillar-2 table
      contains a row naming the post title and the Nov 19–26 window;
      `knowledge-base/marketing/campaign-calendar.md` regenerated to
      enumerate the new distribution file.
- [ ] AC11 — `bun test` suites `seo-aeo-drift-guard`,
      `marketing-content-drift`, `distribution-content-format`,
      `blog-audience-contract` green; `npm run docs:build` clean; `bash
      scripts/validate-blog-links.sh` Guard-1 green.
- [ ] AC12 — Filename date, frontmatter `date:`, redirect-pair key, and
      distribution `publish_date:` all carry the same publish date; if the
      date shifts at ship time, all four move together.
- [ ] AC13 — PR body line 1 states the merge-mutates-production answer
      (bulk-redirect list gains one item via auto-apply; post publishes via
      deploy-docs).

### Post-merge (window action)

- [ ] AC14 — On/after 2026-11-19 the tracker probe reports ACTION REQUIRED
      while `status: parked` persists; the responder flips `status: parked →
      scheduled` in a one-line commit so the daily publisher fires the file
      on the window date, then closes the tracker.

## Test Scenarios

- `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh
  plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`
  → rc 0 (verified against the published arc hub during planning; it exits 0
  on clean text). *(integration — the CI surface that enforces the Blog
  note's mechanical half)*
- `bash scripts/lib/validate-tweet-draft.sh` on the distribution file while
  it still reads `status: draft` → rc 0 (verified against an existing
  `status: draft` file during planning); the parked flip is the last edit.
  *(integration)*
- `npm run docs:build` → clean build including the new post; then `bash
  scripts/validate-blog-links.sh` → Guard-1 parity PASS (the dated slug is
  covered by the new pair). *(integration; suite name `blog-link-validation`
  in test-all.sh)*
- `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` → green; specifically:
  ogImage→BlogPosting.image thread, pillar key resolves, FAQ↔JSON-LD parity
  if a visible FAQ ships, distribution channel/section parity + absolute-URL
  rule, brand-claim bans. *(unit/integration)*
- Follow-through probe dry runs at work time: simulated pre-window date →
  exit 2; simulated in-window date with `status: parked` → exit 5; missing
  file → exit 3. *(unit — the notify-only contract)*
- Word count: `awk`/`wc -w` over the body region (exclude frontmatter and the
  `<script>` JSON-LD) lands in [1500, 2000]. *(unit)*
- Mutation-minded spot checks (manual at work time, not new code): deleting
  the ogImage file or the redirect pair must red the corresponding suite —
  both are already-instrumented repo guards, not new machinery.

## Success Metrics

- Post live at `https://soleur.ai/blog/first-we-made-green-mean-something/`
  after the next docs deploy; dated-slug URL 301s to it.
- Distribution file held `parked` until the window, then published on the
  window date with no re-authoring.
- The arc hub visibly links the sequel; the Pillar-2 table records the piece
  as scheduled.

## Dependencies & Risks

- **Publish-date assumption.** 2026-11-19 is the first open Thursday slot
  after the Nov 17 committed item, inside the brief's window. Recorded in
  decision-challenges as an operator-schedule item; coherent-renaming rule is
  AC12.
- **Parked semantics.** `status: parked` is load-bearing for the window; the
  flip back is a one-line commit the follow-through probe wakes for inside
  the window — no earlier-slot promotion can fire while parked.
- **Gemini image generation unavailable** — PIL fallback is planned; quality
  bar matched to #10939's shipped card.
- **Hub post edit scope.** Editing a published post is a facts-only refresh
  (one link sentence); the Blog note permits fact updates and pins
  title/slug/H1/meta.
- **Suite-count ambiguity** is retired by the "nearly 700"-class phrasing +
  the fact-checker pin (the registered population drifts; never quote 757).
- **HN submission** stays conditional on the fortnight slot and submits the
  technical write-up — no action in this PR beyond noting it.

## References & Research

- Issue: #11362 (this brief), #10971 (closed epic — cited in date-anchored
  prose only), #10902 (arc hub), #8326 (open precedent), #10694 (published
  precedent), #11364 (sibling spoke brief), #10940 (GEMINI rotation — PIL
  fallback reason).
- PRs: #10973, #10989, #11031, #11045, #11051, #11056, #11088, #11119,
  #11153, #11264, #11278, #11282 (the twelve children — all verified MERGED),
  #10922 (arc post + distribution precedent), #10939 (OG image via Pillow
  precedent), #11378 (this pipeline's own draft PR — collision precheck hit,
  reported).
- Source docs: `knowledge-base/marketing/brand-guide.md` (### Blog),
  `plugins/soleur/skills/content-writer/SKILL.md`,
  `knowledge-base/marketing/content-strategy.md` (Pillar-2 table + Hold
  lever), `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`,
  `knowledge-base/project/learnings/best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`,
  `knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`.
- Machinery read at plan time:
  `apps/web-platform/server/inngest/functions/content-promotion.ts`,
  `cron-content-publisher.ts`, `scripts/content-publisher.sh`,
  `scripts/lib/validate-tweet-draft.sh`,
  `scripts/test-all-parallel-benchmark.test.sh`,
  `scripts/suite-shard-legs.tsv`.
- Workflow refs: `.github/workflows/apply-web-platform-infra.yml`
  (push-triggered apply), `.github/workflows/deploy-docs.yml` (docs publish),
  `scheduled-followthrough-sweeper.yml` (probe sweeps).

### Sharp-edge note

A plan whose `## User-Brand Impact` section is empty or placeholder-only
fails deepen-plan Phase 4.6; it is filled above. Commands prescribed in Test
Scenarios were executed once during planning where their green state is
pre-change-independent (jargon scan on the arc hub rc 0; the redirect grep
prints `0` pre-change by construction and `1` post-change; `validate-tweet-draft.sh`
runs against a live `status: draft` file in the corpus). Sharp-edges applied:
diff-scope AC lists pipeline-written files (`INDEX.md`, `session-state.md`);
every cited issue/PR number verified live (12 children + all 12 PRs);
`discoverability_test.command` is allowlisted-verb-clean with no
shell-active bytes; the status-flip (`parked → scheduled`) is a probe-woken
one-line lever, not an unrecorded post-merge step.

## Enhancement Summary

Deepen-plan pass applied inline (no Task/Agent tool in this subagent
context — the per-section research and review fan-outs were substituted by
direct reads of every cited source and mechanical runs of every gate that
has a script):

- **4.4 Precedent-diff** — `seo-bulk-redirects.tf` `blog_redirect_pairs` map
  convention cited (most recent: the Nov 17 post's pair); diff is
  shape-identical. PASS.
- **4.5 Network-outage** — no trigger pattern in the feature description.
  SKIP.
- **4.55 Downtime & Cutover** — no offline-inducing operation (a map append
  plus prose files; the edge 301 add is downtime-free). SKIP.
- **4.6 User-Brand Impact** — section present, threshold `aggregate
  pattern`, concrete artifact + exposure lines. PASS.
- **4.7 Observability** — triggered by the `apps/*/infra/` `.tf` edit;
  section present with all five fields populated;
  `discoverability_test.command` starts with `grep` (allowlisted), no `ssh`,
  no shell-active bytes, finishes in <1s, `expected_output` is the literal
  `1`. PASS.
- **4.8 PAT-shaped variable sweep** — zero hits (plan introduces no
  PAT-shaped TF variable/env var/token). PASS.
- **4.9 UI-wireframe halt** — no Files-to-Create/Edit path matches the
  UI-surface glob superset (.md/.png/.tf/.sh only). SKIP.
- **4.10 Encryption posture** — `.tf` match fires the trigger; section
  present with full at_rest/in_transit fields and no boilerplate ("provider
  handles it" / "supports TLS" absent); no exception needed. PASS.
- **4.11 Guard contract** — the follow-through probe is an assertion-based
  control, so the gate fires: `## Guard Contract` emitted with Property,
  structural Assembly (the sweeper's probe dispatch chokepoint + the
  status×date state space), and a 5-row mutation matrix including a
  vacuous-dispatch row, a second-actionable-state row, and a compliant
  must-PASS row. PASS.
- **4.12 Scope check** — exactly one unfenced `## Scope Check`; Ask Mapping
  6 rows all `mapped`; every plan-item row is `asked` or `inferred` with
  justification. PASS.
- **4.13 Task-design** — the probe registers under the existing sweeper;
  `## Task Design` emitted answering all six questions. PASS.

### Key Improvements (applied during the deepen pass)

- Added `## Guard Contract` + `## Task Design` for the follow-through probe
  (initial draft had assessed 2.12 as skipped; the probe is guard-shaped).
- Refined the probe's verdict table to treat `status: draft` inside the
  window as an ACTION REQUIRED state (a draft in-window is already a slot
  violation, not a compliant state).
- Recorded the `lane:` fail-closed default inline (no `spec.md` exists).

### Review coverage disclosure

`Reviewed-Coverage: sequential-fallback` — the plan-review agent panel
(DHH/Kieran/simplicity + named lenses) and the deepen-plan research fan-out
could not be spawned from this subagent context; the plan was instead
verified section-by-section against the primary sources quoted above
(brand-guide Blog note, content-promotion/publisher source, sibling plan,
followthrough convention, closed epic record) and against the mechanical
gates listed. No independent review ran.
