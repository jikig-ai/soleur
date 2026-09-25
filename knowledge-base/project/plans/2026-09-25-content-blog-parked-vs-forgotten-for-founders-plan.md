---
title: "content: re-angled #8548 blog post for non-technical founders — 'Parked or Forgotten? How to Tell Before It Costs You'"
type: feat
date: 2026-09-25
slug: content-blog-parked-vs-forgotten-for-founders
branch: feat-one-shot-8548-blog-undecided-vs-forgotten
issue: 8548
closes: 8548
priority: p3
domain: marketing
brand_survival_threshold: none
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-25
**Sections enhanced:** 6 (Research Insights / facts, Post specification, X thread, FAQ and SEO, Acceptance Criteria, Relevant files)
**Research agents used:** soleur:marketing:fact-checker, soleur:marketing:seo-aeo-analyst, soleur:marketing:growth-strategist, and a standard-tier verify-the-negative and self-audit pass

**Halt gates:** all passed.

- **4.6 User-Brand Impact:** the section is present, with the `none` threshold and a sensitive-path scope-out.
- **4.7 Observability:** all five fields are present. `probe-verb-gate.sh` exits 0 on the probe. It was re-run live and printed `301`.
- **4.8 PAT:** no hits.
- **4.9 UI wireframe:** no UI-surface file is touched.
- **4.10 Encryption:** the section is present. There are no store or connection entries.
- **4.11 Guard:** no guard is delivered.
- **4.5 and 4.55:** did not trigger.

### Key Improvements

1. **Fact correction (DC-6).** "30 of 118" is a quarter of the *current phase*, not of the whole plan, which is about 2% against every open milestone. The wrong-priority pick and the 30-item limit were separate defects. The story now says "about a quarter of our current plan" and states the two defects side by side, with neither presented as the cause of the other.
2. **Credit accuracy.** Only two of the four places (not yet defined, and decided against) come from Pocock's wayfinder. The four-place rule and the "forgotten" test are Soleur's own. Fact-checked wording is now in the spec.
3. **SEO and AEO:**
   - the seoTitle is cut from 69 to 61 characters;
   - "idea parking lot", the phrase founders actually search, appears in the first 100 words;
   - the FAQ questions are standalone and answer-engine liftable;
   - the FAQ markup pattern and the `"@type": "FAQPage"` literal are pinned;
   - the file order is fixed so AC5 holds;
   - there is one inline contextual link to the founder playbook, and no `pillar:`.
4. **Negatives verified against code:**
   - the only apply workflow is `apply-web-platform-infra.yml`;
   - Eleventy has no future-date filter;
   - the site has no signup page;
   - the publisher's stale and today logic, and its auto-channel set, are as described;
   - the Nunjucks CTA renders, and no lint scans blog posts for `{{`.

### New Considerations Discovered

- `blog-jargon-scan.sh` is blind to text in `{{ }}` braces. The CTA's link text renders from `site.json`, so check the built HTML, as Phase 5 already does.
- `infra-validation.yml` also fires on `apps/*/infra/**`, but it runs no apply.

## Overview

Plan for the re-angled #8548 blog post. The earlier draft spoke to engineers and was rejected at founder review; the brand guide now carries a Blog channel note that targets non-technical solo founders. This plan re-angles the post around the founder's own problem (parked ideas and forgotten ideas look the same), reuses the earlier draft's verified facts, and ships the post together with its X thread.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch.

### Plan Review Revisions (2026-09-25)

The review panel was DHH, Kieran, code-simplicity, CMO and CTO, plus a scoped advisor consult.

**Mechanical, applied:**

- The CTA now uses Nunjucks `site.primaryCta`.
- The thread is scheduled for the day after go-live. That replaces the same-day timing window and the manual trigger, which auto-merge could not honour.
- The re-date step is a portable block, and AC21 checks the date coupling.
- The X thread uses the labeled tweet format, so CI checks tweet lengths.
- AC4 is portable, and AC9 has runnable section-scoped commands.
- AC15 covers the calendar row, and AC14 adds `blog-audience-contract.test.ts`.
- `linkedin-personal` is added to the channels.
- The pre-draft angle-check step is cut. The copywriter pass stays, and the fact-check re-runs only when a claim changes.

**Taste and User-Challenge, persisted:** DC-1 to DC-5 in `knowledge-base/project/specs/feat-one-shot-8548-blog-undecided-vs-forgotten/decision-challenges.md`.

**CMO wording, applied:**

- the story paragraph states the fix;
- section 5 describes outcomes, not the system;
- the general thesis line;
- a "not yet defined" example;
- heading and tweet wording.

## Research Insights

### Premise Validation (Phase 0.6)

Every cited reference was checked on 2026-09-25 and all of them hold.

- **#8548** is OPEN and labelled `content`, `domain/marketing`, `type/feature` and `priority/p3-low`. It has three comments: the 2026-09-23 provenance triage, the 2026-09-24 founder rejection and the 2026-09-25 `8774-handoff`.
- **#8774** is CLOSED. **PR #8801** merged at 2026-09-25T02:23Z as commit `5f07bea4`, which is an ancestor of this branch's HEAD.
- **PR #8536** merged on 2026-09-22, which puts the two-week window at **2026-10-06**. **PR #8649**, the old draft, was closed without merging. **PR #8647** and **PR #8284** are merged.
- The `### Blog` note sits in `knowledge-base/marketing/brand-guide.md` under `## Channel Notes`. `plugins/soleur/skills/content-writer/SKILL.md` has Phase 2.4, the Blog Note Scan, and `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh` exists.
- The old draft is on `origin/feat-content-8548-roadmap-undecided-vs-forgotten`, in three files:
  - `plugins/soleur/docs/blog/2026-09-24-roadmap-undecided-vs-forgotten.md`
  - `knowledge-base/marketing/distribution-content/2026-09-24-roadmap-undecided-vs-forgotten.md`
  - the `seo-bulk-redirects.tf` entry
  None of the three is reused. The facts are carried forward below.
- The issue to leave out of the post is **#8808** ("Decisions to confirm: blog audience defaults from PR #8801").

### Property List (Phase 0.6b)

1. A non-technical solo founder sees their own problem in the title, the meta description and the first two sentences: parked and forgotten ideas look the same.
2. After reading, the founder can sort their own list into four places with whatever tool they already use.
3. No reader-visible text breaks the Blog note's jargon limits. The one exception is the closing technical link.
4. Every factual claim can be traced to a source. The only number is "about a quarter".
5. Matt Pocock is credited by name, with a link, at first mention.
6. The CTA is one step a non-technical founder can take, with no commands.
7. The post shows up outside the blog index's "Engineering Deep Dives" bucket.
8. The X thread goes out with the post, at the first publisher run after the page is live (the next day at 14:00 UTC), not on a later auto-assigned Tue/Thu slot and never before the page is live. Hacker News gets no post submission.
9. The dated slug returns an edge 301, which the Guard-1 parity check requires.
10. `content-strategy.md` no longer describes the rejected technical angle.
11. #8808, the headless-defaults decision issue, is not mentioned anywhere in the post or its distribution copy.

### Cut List (Phase 0.6b)

- **New "Founder Playbooks" section in `blog.njk`** (recommended by the CMO) → Property 7 → already covered by the existing routing tag `ai-agents`. That tag puts the post under "What is Company-as-a-Service?", next to the other two founder posts (`ai-agents-for-solo-founders` and `best-ai-tools-for-solo-founders-2026`). Editing a `*.njk` page also trips the plan's mechanical UI-surface override: a BLOCKING UX gate and a required `.pen` wireframe, for an index change that is not this post's job. The section is not built here. It is recorded as a founder decision (DC-1 in `decision-challenges.md`), which `ship` files as an `action-required` issue. It is not a deferral: a tracking-issue attempt was refused by the repo's filing gate as being inside the inline fix-size threshold (ADR-131). The blocker is a taste decision plus the wireframe gate, not size.
- **One with-merge feature tweet via `feature-tweet`** (the original brief) → Property 8 → superseded. The CMO table says the thread ships with the post, and the distribution file carries it. No `feature-tweet` run.
- **Audit retrospective of all five bundles** (the original brief) → dropped by the handoff ("Drop from the body: … the audit-bundle list"). It serves no founder property.

### Value-Proposition Measurement (Phase 0.6c)

Not applicable. The plan justifies itself on audience fit, not on cost or performance savings.

### Facts carried forward from the old draft (verified against PR #8536's body)

- Before the fix, our roadmap assistant could see 30 of the 118 open items in the phase we were working on. That is about 25.4%. Source: PR #8536, section "Pre-existing `next` defects folded in".
  - **Deepen fact-check correction (2026-09-25):** 30 of 118 is a quarter of the *current phase*, not of the whole plan. The open milestones hold roughly 125 + 6 + 1,268 issues, so against the whole plan it is about 2%. The brief's "a quarter of our plan" is therefore rendered as **"about a quarter of our current plan"**, meaning the stage in progress (recorded as DC-6).
- It recommended work planned for a later stage (Phase 5, the desktop app) while Phase 4 was active. It gave no warning. The post puts it as "it pointed me at the wrong priority".
  - **Deepen fact-check correction:** the wrong pick and the 30-item limit were two *separate* defects. The phase was skipped because Phase 4's Current State row had no frozen count; the limit is a different bug. The post must not say the wrong pick happened *because* it could see only a quarter. State them side by side, not as cause and effect.
- After the fix, it reads all 118 and names a current-phase item.
- The four places are: a phase row (doing now), Post-MVP / Later (chosen for later), Not Yet Specified (you cannot yet state the question), and Out of Scope (closed as not planned, with a one-line reason). Anything outside those four with no record was forgotten. An open item with no placement is "unsorted".
- The test for "not yet defined" is whether you can state the question precisely now, not whether you can answer it. Sources: PR #8536 Summary, and `plugins/soleur/NOTICE` Bundle 5.
- The idea comes from Matt Pocock's MIT-licensed collection at `https://github.com/mattpocock/skills`: its `wayfinder` method's fog-of-war section. Matt Pocock is the author of Total TypeScript. Sources: `plugins/soleur/NOTICE`, the `mattpocock/skills` block, and the `knowledge-base/product/competitive-intelligence.md` audit row.
- **Credit verified live on 2026-09-25:** `gh api repos/mattpocock/skills` reports license `MIT`. `skills/engineering/wayfinder/SKILL.md` carries `## Not yet specified` ("in-scope fog you can't ticket yet") and `## Out of scope` ("closed, never graduates") sections, so the credit sentence names a mechanic the source really contains. `https://github.com/mattpocock/skills` returns 200.
- **Discoverability probe verified live on 2026-09-25:** `curl -s -o /dev/null -w %{http_code} https://soleur.ai/blog/2026-06-15-best-ai-tools-for-solo-founders-2026/` prints `301`.
- **Not for public use:** star or fork counts. The audit row says "Internal context only, not for citation". Also excluded are any competitive comparison and every bundle or issue number.

### Relevant files

- `plugins/soleur/docs/blog/blog.json`: `permalink: "blog/{{ page.fileSlug }}/index.html"`. Eleventy's `fileSlug` strips the `YYYY-MM-DD-` prefix, so the live URL is `/blog/<slug>/`. The old distribution file used the same undated URL.
- `plugins/soleur/docs/pages/blog.njk`: category buckets, in order.
  - "What is Company-as-a-Service?": `"CaaS"` tag, or `"ai-agents"` without `comparison` or `case-study`.
  - "Soleur vs. Competitors": `comparison`.
  - "Case Studies": `case-study`.
  - Everything else falls to "Engineering Deep Dives".
  - Tags are case-sensitive. `company-as-a-service` routes nowhere, which is why the 2026-05-14 founder playbook currently sits under Engineering Deep Dives.
- `plugins/soleur/docs/_includes/blog-post.njk`: renders every tag as a visible `blog-tag-chip`, so tags are reader-visible text and fall under the jargon limits.
- `plugins/soleur/docs/_data/site.json` `primaryCta`: `{"label": "Join the waitlist", "url": "/pricing/#waitlist"}`. This is the site-wide conversion CTA. The docs site has no "signup" page. `https://app.soleur.ai/signup` answers 200 ("Create your account"), but the marketing site sends visitors to the waitlist, so the post follows `site.primaryCta`.
- `apps/web-platform/infra/seo-bulk-redirects.tf`, `local.blog_redirect_pairs`: add one `"<YYYY-MM-DD>-<slug>" = "<slug>"` row, column-aligned with its neighbours. Applied automatically on merge by `.github/workflows/apply-web-platform-infra.yml` (`push: main`, `paths: apps/web-platform/infra/**`, `-target=cloudflare_list.legal_redirects`).
- `scripts/validate-blog-links.sh`: Guard 1 (#3328) fails when any date-prefixed post lacks a redirect entry, and it also checks that distribution-content URLs resolve in `_site`. It runs in the bun test group in CI.
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts`: Test 12 fails CI when a post has no `ogImage` (`expect(without.length).toBe(0)`). It does not check that the PNG exists on disk; the OG learning's audit one-liner does that.
- `plugins/soleur/test/redirect-tombstones.test.ts`: the redirect census.
- `knowledge-base/marketing/content-strategy.md`: the #8548 Pillar-2 row (content anchor `| Your Roadmap Can't Tell Undecided from Forgotten | Retrospective / methodology |`) and the rolling-calendar entry (anchor `| Within 2 weeks of PR #8536 merging | Draft "Your Roadmap Can't Tell Undecided from Forgotten"`). Both still describe the technical angle.
- `scripts/content-publisher.sh` and `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` (cron `0 14 * * *` UTC): publish a file **only when `status: scheduled` and `publish_date == today`**. A scheduled file whose date has passed is marked `status: stale` and never posted.
- `apps/web-platform/server/inngest/functions/content-promotion.ts` (`isReadyDraft`, `nextTueThuSlots`, `HORIZON_DAYS = 28`): the cron auto-promotes a `status: draft` file into the next free Tue/Thu slot. A draft would therefore post on an arbitrary later Tue/Thu, not with the post.
- Automated channels are discord, x, linkedin-personal, linkedin-company and bluesky. Reddit, IndieHackers and Hacker News are manual copy only.
- `plugins/soleur/skills/social-distribute/SKILL.md` §5.5: when the Blog note says so, it already writes the HN section as a one-line "skipped" note.
- `plugins/soleur/docs/images/blog/og-*.png`: OG images are 1200×630, textless, gold on `#1A1A1A`, drawn as abstract vector geometry.

### Institutional learnings applied

- `knowledge-base/project/learnings/best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`: make the OG image with deterministic PIL at a 3× supersample, downscaled with LANCZOS, not with Gemini. Then run the all-posts `ogImage` audit one-liner.
- `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md`: leave `date:` unquoted. Do not set `layout` or `ogType`, and add no BlogPosting JSON-LD in the body. FAQPage JSON-LD is the only inline schema.
- `knowledge-base/project/learnings/2026-03-26-case-study-three-location-citation-consistency.md`: the body, the FAQ `<details>` and the FAQ JSON-LD must say the same thing.
- `knowledge-base/project/learnings/2026-03-20-stale-content-publisher-duplicate-warnings.md`: a scheduled file whose date passes turns stale. The file is dated to the merge, as described under Sharp Edges.
- `knowledge-base/project/learnings/best-practices/2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`: internal links are root-relative (`/blog/…`) or full `https://soleur.ai/...` URLs.

### Conventions

- CLAUDE.md and AGENTS.md: `cq-cite-content-anchor-not-line-number` applies. Line numbers in this plan are informational only; edits key on the content anchors above.
- `wg-plan-prescribed-skills-must-run-inline`: the work phase runs `soleur:content-writer` and `soleur:social-distribute` inline, as prescribed below.

### Related issues and PRs

#8548 (target), #8774 and PR #8801 (the Blog note), PR #8536 (the technical write-up behind the closing link), PR #8649 (the rejected draft, closed), PR #8647 and PR #8284 (audit record), #6087 (per-category blog pillar pages, a different scope), and #8808 (must not be mentioned).

### Community discovery and functional overlap (Phases 1.5 and 1.5b)

No new stack is involved: Eleventy and Markdown are already covered. No capability is being built, so there is no registry overlap to check. A content deliverable has no skill or agent equivalent in community registries.

## Research Reconciliation — Brief vs. Codebase and Brand Guide

| Brief or handoff says | Reality | Plan response |
|---|---|---|
| The CTA is "signup". The handoff outline says "ask Soleur what is next". | The docs site has no signup page. `site.json` `primaryCta` is "Join the waitlist" → `/pricing/#waitlist`, and the nav says "Hosted version (coming soon)". The Blog note allows exactly **one** next step. | Use `site.primaryCta`'s label and URL as they read on the day the post is drafted (today that is the waitlist), and label the link honestly. Add no second CTA. |
| "A 20-minute sort any founder can run this week" (handoff outline). | The Blog note says: "Use only numbers from a real source you can check". "20 minutes" is an unsourced estimate. The copywriter review flagged it. | Drop the number from the title, the SEO title, the meta description and the headings. Frame the section as "a sort you can run this week, with any tool". |
| "Our planning assistant once pointed at the wrong priority" (handoff outline). | `brand-guide.md` `### Do's and Don'ts` says: Don't "Say 'assistant' or 'copilot'". | Write "the part of my AI team that plans our roadmap". |
| The opening is in the founder's words ("I lose track…"), and outline items 4 and 5 are "our" story. | The post byline is `site.author`, "Jean Deruelle, Founder". | Write the whole post in the founder's first person singular ("I", "my AI team"). The opening quote is then the author speaking, not an unnamed "I". |
| The issue brief sends a with-merge tweet via `feature-tweet`, uses HN/Reddit only for the retrospective, and targets "technical PMs". | CMO table (the 2026-09-25 `8774-handoff`): the X thread ships with the post, HN is skipped, and the audience is non-technical solo founders. | The distribution file carries the thread, scheduled for the first publisher run after go-live (the post date plus one day, 14:00 UTC). No `feature-tweet` run and no HN submission. The content-strategy row is rewritten to match. |
| "Tags that place it outside … Engineering Deep Dives". | `blog.njk` routes only `CaaS`, `ai-agents`, `comparison` and `case-study`. Tags render as visible chips. | Tags are `solo-founder`, `decision-making` and `ai-agents`. `ai-agents` is the only routing tag in plain words, and the two sibling founder posts carry it. The founder-facing index section is left as founder decision DC-1. |

## Problem Statement

The first #8548 draft opened on a CLI bug ("saw 30 of 118 open issues") and taught a GitHub-Issues mechanism. On 2026-09-24 the founder rejected it as written for engineers. The idea underneath still holds for a non-technical founder: a parked idea and a forgotten one look the same until one costs you. The brand guide now requires every blog post to start from that founder's problem. This post is the first one written under that rule.

## Proposed Solution

Write one new post with `soleur:content-writer`, which applies the Blog note and runs the Phase 2.4 jargon scan and the Phase 2.5 fact-check. The post comes with:

- its OG image,
- its distribution file, with the X thread scheduled for the first publisher run after go-live,
- the dated-slug redirect,
- the content-strategy rewrite.

### Founder sentence (working note; not in the post)

"A solo founder has this problem: they cannot tell the ideas they chose to park from the ones they forgot, so they re-argue settled decisions and lose good ideas. After reading, they can sort their own list into four places, with the tool they already use, and see what they forgot."

### Post specification

- **File:** `plugins/soleur/docs/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`. `<YYYY-MM-DD>` is the UTC date the post goes live, which is the merge date. Pick it at drafting time, and re-date it at ship time if the merge slips (see Phase 5). The live URL is `https://soleur.ai/blog/parked-vs-forgotten-ideas/`.
- **Frontmatter:** match the recent siblings. Use `title`, `seoTitle`, `date` (unquoted, equal to the filename date), `description`, `ogImage: "blog/og-parked-vs-forgotten-ideas.png"` (no leading `/images/`) and `tags`. Do not set `layout` or `ogType`, since `blog.json` supplies both.
  - `title: "Parked or Forgotten? How to Tell Before It Costs You"`
  - `seoTitle: "Parked vs. Forgotten Ideas: How Solo Founders Track Decisions"`. At 61 characters it is rendered verbatim into `<title>` by `base.njk` line 126, which adds no suffix. The earlier 69-character version would be truncated in search results (deepen: SEO/AEO analyst).
  - `description`: 120-160 characters, naming the problem. Starting point, 149 characters: "Can't tell a parked idea from a forgotten one? Sort every idea into one of four places, in any tool, and stop re-debating decisions you already made."
  - `tags`: `solo-founder`, `decision-making`, `ai-agents`.
- **Voice:** first person singular throughout, in the General register. "Explain, don't dumb down." Say "your AI team" and "my AI team". Never say "assistant", "copilot", "agent" or "skill" counts.
- **Opening (first paragraph):** "I lose track of what I decided and what I just forgot. From the outside, a parked idea and a forgotten one look exactly the same." Add a third sentence naming the cost, for example: "So I re-argue choices I already made, or find an idea months later and realize I never decided anything about it."
  - The first sentence is the operator-specified wording and is kept verbatim.
  - The CMO flagged that "just" is a brand-guide Don't. That is recorded as DC-4, a User-Challenge, and the operator's words stay the default.
- **Sections.** Headings name outcomes, not mechanisms. Each heading below is a starting point; content-writer may refine it within the Blog note.
  1. **What it costs when you can't tell them apart.** Settled decisions get re-debated, and parked ideas get lost.
  2. **Every idea belongs in one of four places.**
     - *Doing now.*
     - *Later, chosen on purpose.*
     - *Not yet defined.* State the test every time this label appears: you can't yet say what question it would answer. Being unable to answer the question does not put an idea here.
       - Include one founder example. For instance, "Do a podcast" has no question yet, so it stays here. "Should a podcast replace my newsletter?" is a question you can state now, so the idea goes under Later.
     - *Decided against, with one line on why.* A changed mind is a new decision, not a reopened one.
     - Close the section with: anything in none of the four wasn't parked; it was forgotten.
     - First mention credits Matt Pocock inline and accurately. Two of the four places ("not yet defined" and "decided against, with a reason") come from the wayfinder method in his collection. The four-place rule itself, and the "anything outside is forgotten" test, are ours: PR #8536 says "A four-places rule ties it together", and phase rows and Post-MVP already existed. Wording verified by the fact-checker: "Two of those places, not yet defined and decided against, come from [Matt Pocock's free, public collection of AI working methods](https://github.com/mattpocock/skills). I added them to the now and later lists I already had, and made the rule that anything in none of the four was forgotten." Do not use the word "skills" as link text. Do not put "Soleur" within 40 characters before any "open source" wording (`marketing-content-drift.test.ts` Test 2c2). Preferably avoid "open source" altogether.
  3. **Sort your list this week, with any tool.** Numbered steps work in a notebook, Notion or a spreadsheet:
     1. List everything.
     2. Place each item in one of the four places.
     3. For each "not yet defined" item, write the question it would answer. If you can't write it yet, the item stays there.
     4. For each "decided against" item, write one line on why.
     5. Anything left unplaced was forgotten. Decide on it now, or place it.
  4. **How I found out the hard way.** One short paragraph that states the failure and the fix together, so it does not read as an unfixed product defect: "The part of my AI team that plans our roadmap once pointed me at the wrong priority. It could also see only about a quarter of our current plan, and it never warned me about either. Now it reads the whole plan, and tells me when it can't." The two defects sit side by side; neither is presented as the cause of the other (fact-check correction). Our story illustrates the problem; it is not the subject.
  5. **What changed: decisions stay decided.** Describe outcomes, not the system. Claim only what PR #8536 shipped, in plain words:
     - ideas I can't phrase yet go on a "not yet defined" list instead of into a half-made plan;
     - anything I rule out is closed with one line on why;
     - my AI team sees the whole plan and tells me when it can't;
     - what it suggests next is something I can start today.
     Avoid "unblocked", "frontier" and other system words. Say what the founder still decides (which place each idea goes) and what the AI team does (keeps the list, flags anything unplaced). No hours-saved claims. Close the section with the Blog note's general thesis, for example: "Running a company alone shouldn't mean remembering everything alone."
  6. **CTA (one).** For example: "Want an AI team that keeps the list while you make the calls? [{{ site.primaryCta.label }}]({{ site.primaryCta.url }})". Blog markdown is rendered through Nunjucks (`eleventy.config.js` `markdownTemplateEngine: "njk"`, precedent `{{ site.url }}` in `2026-03-16-soleur-vs-anthropic-cowork.md`), so the CTA follows `site.json` and changes with it when the waitlist becomes signup.
- **FAQ (3 plain-words entries)**, with matching FAQPage JSON-LD. The body, the `<details>` blocks and the JSON-LD must agree word for word in substance.
  - **Questions.** Each one names the idea itself, so an answer engine can lift it out of the post (deepen: SEO/AEO analyst and growth-strategist):
    - "What is the difference between a parked idea and a forgotten idea?"
    - "When is an idea 'not yet defined' instead of 'later'?"
    - "How do I stop going back over decisions I've already made?" The answer: write down the one-line reason for every "decided against".
  - **Answers.** 40-60 words each, readable on their own, with no brand name, no links and no markdown. Markdown is not rendered inside raw HTML.
  - **Markup.** Copy the pattern in `2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md`: `<div class="faq-list"><details class="faq-item"><summary class="faq-question">…</summary><p class="faq-answer">…</p></details></div>`. Write the JSON-LD with `"@type": "FAQPage"` exactly, space after the colon, because `validate-seo.sh` looks for that string whenever a page has `faq-item`. Use straight ASCII apostrophes in both copies.
  - **File order:** body → FAQ → CTA → closing technical link → FAQ JSON-LD `<script>`. AC5 needs the closing link to be the last non-JSON-LD line.
- **Search phrase.** Use "idea parking lot" once within the first 100 words, and define it in one quotable sentence. Then show that the four-place sort adds the "forgotten" check a plain parking lot lacks. That phrase is the one founders actually search for; "parked vs forgotten" has no measurable volume (growth-strategist). Secondary phrases for the body only: "too many ideas", "decision log".
- **Inline contextual link (not a CTA).** Link one phrase in section 5, such as "the rest of the company", to `/blog/how-to-run-every-department-with-ai-agents/`. Keep "agent" out of the link text and do not phrase it as a next step. `validate-blog-links.sh` checks that it resolves.
- **Do not set `pillar:`.** It requires a `pillars.js` entry, which is outside this diff. `ogImageAlt` is optional, e.g. "Four outlined containers holding ideas, with stray ones drifting away".
- **Closing technical link: the last line, below the CTA, and the only place a PR number may appear.** "For the technical write-up, see [how we fixed it](https://github.com/jikig-ai/soleur/pull/8536)."
- **Length:** about 1,100-1,600 words. The issue's 1,500-2,000 target assumed the retrospective framing that the handoff drops.
- **Hard exclusions** from every reader-visible line (title, headings, body, FAQ, tag chips):
  - backticks, code, commands or flags;
  - file paths, skill or agent names;
  - issue or PR numbers, except inside the closing link's URL;
  - "30 of 118", "118", "Phase 4", "Phase 5", "milestone", "Post-MVP", "Not Yet Specified", "Out of Scope", "frontier", "GitHub Issues";
  - the audit-bundle list, star or fork counts, and any competitive comparison;
  - **any reference to #8808 or to "headless" defaults.**

### OG image

Draw a deterministic PIL image, 1200×630, following `2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md`:

- 3× supersample, opaque gold strokes precomputed over `#1A1A1A`, gold in the `#C9A962`→`#DCBE6E` range, LANCZOS downscale;
- textless;
- concept: four outlined containers holding dots, with a few stray dots drifting outside and fading.

Save it to `plugins/soleur/docs/images/blog/og-parked-vs-forgotten-ideas.png`. Keep the generator in the session scratch directory, not in the repo, which matches the precedent.

### Distribution file

Run `soleur:social-distribute` on the post. It writes `knowledge-base/marketing/distribution-content/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md` and applies the Blog note: §5.5 writes Hacker News as a one-line "skipped for this post" note, and `hackernews` never goes in `channels`. Then hand-edit the frontmatter:

- `channels: discord, x, bluesky, linkedin-company, linkedin-personal`.
  - These are all automated channels (`content-publisher.sh` posts each of them). `linkedin-personal` is included because the CMO rates first-person LinkedIn as the best fit for this post; there is precedent in two existing files.
  - Keep Discord in the file rather than posting it immediately.
  - IndieHackers and Reddit stay as manual-copy sections, which social-distribute writes anyway. They are not auto-posted.
- `status: scheduled`;
- `publish_date: "<YYYY-MM-DD + 1 day>"`, the day **after** the post's filename date.
  - The thread then goes out at the first 14:00 UTC publisher run after the page is live. That run is at most about a day after the post, and it removes every merge-time race.
  - **A `draft` is wrong here**: `content-promotion.ts` would move it to the next free Tue/Thu slot, days after the post.

**X thread.** Rules: hook first, statements not questions, 280 characters or fewer per tweet, link only in the final tweet, at most one hashtag. Use the **labeled** format `**Tweet N (Hook|Body|CTA) -- NNN chars:**`, as in `01-legal-document-generation.md`, so that `distribution-content-format.test.ts` checks each tweet's length. Starting point from the copywriter and CMO reviews:

1. "From the outside, a parked idea and a forgotten one look exactly the same. That's how solo founders end up re-arguing settled decisions and quietly losing good ones."
2. "2/ Every idea belongs in one of four places. Now. Later, chosen on purpose. Not defined yet: you can't say what question it answers. Decided against, with one line on why."
3. "3/ Anything in none of the four wasn't parked. It was forgotten."
4. "4/ I learned this the hard way. My AI team once pointed me at the wrong priority, and it could see only about a quarter of our current plan. No warning about either. Now it reads the whole plan, and says when it can't."
5. "5/ How to sort your list this week, with a notebook, Notion or a spreadsheet:" plus the undated UTM URL `https://soleur.ai/blog/parked-vs-forgotten-ideas/?utm_source=x&utm_medium=social&utm_campaign=parked-vs-forgotten-ideas` and `#solofounder`.

Every posted URL uses the **undated** slug with an absolute `https://soleur.ai`. `validate-blog-links.sh` and `distribution-content-format.test.ts` both check this.

### Redirect

Add one row to `local.blog_redirect_pairs` in `apps/web-platform/infra/seo-bulk-redirects.tf`, after the `"2026-06-15-best-ai-tools-for-solo-founders-2026"` row. `terraform fmt` sets the column alignment:

```hcl
    "<YYYY-MM-DD>-parked-vs-forgotten-ideas" = "parked-vs-forgotten-ideas"
```

**Merging this alone mutates production.** `apply-web-platform-infra.yml` fires on `push: main` for `apps/web-platform/infra/**` and applies `-target=cloudflare_list.legal_redirects`. That adds three edge-301 items: the directory URL, `index.html` and the bare form. No other apply workflow's `paths:` covers this file. The merge click is the authorization for this small, additive, reversible change, and the PR body's first line must say so.

### Content strategy rewrite

Replace the #8548 Pillar-2 row and the rolling-calendar entry in `knowledge-base/marketing/content-strategy.md`, matching on their content anchors, with the founder angle:

- the new title and slug;
- audience: non-technical solo founders;
- hook: parked and forgotten ideas look the same;
- proof: "about a quarter of our current plan";
- CTA: the site primary CTA;
- channels: blog, plus an X thread, Discord, Bluesky and both LinkedIn pages at the first publisher run after go-live, with **no Hacker News**;
- status: published on merge date, with a link to the post.

Remove the `product-roadmap next --frontier` CTA, the "technical PMs" audience and the HN/Reddit line. Leave `campaign-calendar.md` alone: it is generated from the distribution files by `soleur:campaign-calendar`.

## Files to Create

- `plugins/soleur/docs/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`
- `plugins/soleur/docs/images/blog/og-parked-vs-forgotten-ideas.png`
- `knowledge-base/marketing/distribution-content/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`

## Files to Edit

- `apps/web-platform/infra/seo-bulk-redirects.tf`: one `blog_redirect_pairs` row.
- `knowledge-base/marketing/content-strategy.md`: the #8548 Pillar-2 row and its rolling-calendar entry.

Pipeline-written files the diff will also carry: `knowledge-base/project/plans/<this plan>`, `knowledge-base/project/specs/feat-one-shot-8548-blog-undecided-vs-forgotten/{tasks.md,session-state.md,decision-challenges.md}` and any generated `knowledge-base/INDEX.md` refresh.

**Not edited:**

- `plugins/soleur/docs/pages/blog.njk`: a new index section is left to the founder (DC-1; see Non-Goals). Editing any `*.njk` trips the UI-surface BLOCKING gate.
- `brand-guide.md`, `content-writer/SKILL.md` and `social-distribute/SKILL.md`: already correct on `main`.

## Implementation Phases

### Phase 0: Preconditions (read-only)

- Re-read `brand-guide.md` `## Channel Notes > ### Blog`, `### X/Twitter` and `### Audience Voice Profiles` on the branch.
- `curl -s -o /dev/null -w '%{http_code}' https://github.com/mattpocock/skills` should print `200`. The credit also has to stay honest: planning verified on 2026-09-25 that `skills/engineering/wayfinder/SKILL.md` still carries its "Not yet specified" and "Out of scope" sections. If they are gone, soften the credit to "inspired by".
- Set `<YYYY-MM-DD>` to today's UTC date, the expected merge date. Phase 5 re-dates it if the merge slips.

### Phase 1: Draft the post (`soleur:content-writer`, run inline)

- Invoke `soleur:content-writer` with:
  - the topic;
  - the Post specification above as `--outline`, including the founder sentence;
  - `--keywords "keep track of decisions, solo founder, prioritize ideas"`;
  - `--path plugins/soleur/docs/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`.
- Its Phase 2.4 runs `blog-jargon-scan.sh`, and the draft must end with `SCAN_RC=0`.
- Its Phase 2.5 runs `soleur:marketing:fact-checker`. Every claim must come back PASS or SOURCED:
  - "about a quarter of our current plan" (the current phase) → PR #8536 body;
  - the wrong pick and the limit stated as separate defects → PR #8536 body;
  - the four places and their test → PR #8536 and `NOTICE`;
  - the Matt Pocock credit → the repo URL.
- Apply the hard-exclusion list by hand after the scan. The scan detects only a fixed subset.
- Headless defaults apply under one-shot (Accept on all PASS or SOURCED).
- **Copywriter voice pass on the finished draft.** The last draft failed on voice and angle, which neither the scan nor the fact-checker checks.
  - Run `soleur:marketing:copywriter` on the full draft with the prompt: "Voice review for a non-technical solo founder against brand-guide.md ### Blog; flag any paragraph a reader who has never opened a terminal could not repeat back".
  - Apply its fixes, then re-run the jargon scan.
  - Re-run the fact-check only if a factual claim changed.

### Phase 2: OG image

- Generate with PIL as specified.
- Verify 1200×630 RGB: `python3 -c "from PIL import Image; im=Image.open('<png>'); print(im.size, im.mode)"`.
- Run the all-posts `ogImage` existence audit one-liner from the OG learning. It must print nothing.

### Phase 3: Distribution file (`soleur:social-distribute`, run inline)

- Invoke it on the post and decline any immediate Discord post.
- Hand-set `status: scheduled`, `publish_date` (the post date plus one day) and `channels` as above. Convert the X section to the labeled tweet format.
- Name the file `knowledge-base/marketing/distribution-content/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`, where `<YYYY-MM-DD>` is the post date.
- Run `bash scripts/lint-distribution-content.sh <file>` and require exit 0.

### Phase 4: Redirect and content strategy

- Add the redirect row and run `terraform fmt -check apps/web-platform/infra/seo-bulk-redirects.tf`.
- Rewrite the two content-strategy entries.

### Phase 5: Verify, then ship

- Run `npm run docs:build`, then these checks. Each has a pass condition:
  - `bash scripts/validate-blog-links.sh _site`
  - `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts plugins/soleur/test/distribution-content-format.test.ts plugins/soleur/test/marketing-content-drift.test.ts plugins/soleur/test/redirect-tombstones.test.ts`
  - `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` exits 0.
- Check the rendered page:
  - `_site/blog/parked-vs-forgotten-ideas/index.html` exists;
  - `og:image` points at `https://soleur.ai/images/blog/og-parked-vs-forgotten-ideas.png`;
  - the CTA renders with `site.primaryCta`'s label and URL, with no literal braces left in the HTML;
  - the post's card appears inside `<section id="company-as-a-service">` of `_site/blog/index.html` and not inside `id="engineering"`.
- **Re-date immediately before queueing the merge**, only if today's UTC date differs from `<YYYY-MM-DD>`. Run this block from the worktree root, then re-run AC21 and `validate-blog-links.sh`. Guard 1 checks the pairing.

  ```bash
  NEW=$(date -u +%F)
  NEXT=$(python3 -c "import datetime,sys;print(datetime.date.fromisoformat(sys.argv[1])+datetime.timedelta(days=1))" "$NEW")
  post=$(ls plugins/soleur/docs/blog/*-parked-vs-forgotten-ideas.md)
  dist=$(ls knowledge-base/marketing/distribution-content/*-parked-vs-forgotten-ideas.md)
  OLD=$(basename "$post" | cut -c1-10)
  git mv "$post" "plugins/soleur/docs/blog/$NEW-parked-vs-forgotten-ideas.md"
  git mv "$dist" "knowledge-base/marketing/distribution-content/$NEW-parked-vs-forgotten-ideas.md"
  perl -pi -e "s/^date: $OLD\$/date: $NEW/" "plugins/soleur/docs/blog/$NEW-parked-vs-forgotten-ideas.md"
  perl -pi -e "s/^publish_date: \".*\"\$/publish_date: \"$NEXT\"/" "knowledge-base/marketing/distribution-content/$NEW-parked-vs-forgotten-ideas.md"
  perl -pi -e "s/\"$OLD-parked-vs-forgotten-ideas\"/\"$NEW-parked-vs-forgotten-ideas\"/" apps/web-platform/infra/seo-bulk-redirects.tf
  ```

  Commit the result as one commit. The date math uses `python3` and the edits use `perl -pi`, because both are portable; `date -d` and `sed -i` behave differently on macOS.
  - **Stale guard:** a merge that lands more than one day after `<YYYY-MM-DD>` leaves `publish_date` in the past, and the publisher then marks the file `stale`. If auto-merge is still pending the next UTC day, re-run the block and push.
- **Founder review (DC-3).** `ship` surfaces DC-3 in the PR body. Merging publishes the post, and the next day's 14:00 UTC run publishes the social posts, which cannot be taken back.
- **Post-merge (automated in `soleur:ship`):**
  - wait for the `deploy-docs.yml` run on the merge SHA to succeed;
  - `curl -s -o /dev/null -w '%{http_code}' https://soleur.ai/blog/parked-vs-forgotten-ideas/` must print `200`;
  - `curl -s -o /dev/null -w '%{http_code}' https://soleur.ai/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas/` must print `301` once `apply-web-platform-infra.yml` succeeds.
  - The thread needs no manual step: the publisher's 14:00 UTC run on `publish_date` posts it, and the page has been live since the day before.
  - On or after `publish_date`, confirm the thread went out: the publisher's bot PR flips the file to `status: published`. If an `[Content Publisher] X API failed` issue appears, it carries the thread text for manual posting.

## Non-Goals

- **A founder-facing section on the blog index** (the CMO's "Founder Playbooks" proposal). This is a founder taste decision, recorded as DC-1 in `knowledge-base/project/specs/feat-one-shot-8548-blog-undecided-vs-forgotten/decision-challenges.md`. `ship` renders it into the PR body and files it as an `action-required` issue.
  - DC-1 also names the pre-existing mis-bucketing: posts tagged `company-as-a-service` but not `CaaS` fall into Engineering Deep Dives.
  - A standalone tracking issue was attempted and refused by the repo's filing gate, because the change is inside the ADR-131 inline threshold of about 22 lines in one file. The reason it is not folded in here is authority, not size: it is a taste call plus a UI-surface wireframe gate.
- **Rewriting, retitling or redirecting the old technical draft or any existing post.** The Blog note's `Scope` bullet grandfathers them, and the old draft was never published.
- **Hacker News for this post.** The Blog note skips it. Submitting PR #8536 there is a separate, optional call and is not part of this PR.
- **Waitlist UTM or referrer attribution** for in-post CTAs. The behaviour is the same for every post, and this post does not change it.
- **Mentioning or acting on #8808.**

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Add the "Founder Playbooks" section to `blog.njk` now (CMO) | Adds a UI-surface change and its BLOCKING wireframe gate to a content PR. The property it buys (not Engineering Deep Dives) is already bought by a routing tag. Left to the founder as DC-1. |
| Pick one fixed future Tue/Thu date now and let the cron publish it with no merge-timing rules (advisor consult) | Eleventy does not hide future-dated posts (`blog.json` sets only `tags`, and `eleventy.config.js` has no date filter). The page would go live at merge showing a future date, days before its thread, which breaks "the thread ships with the post". The next-day `publish_date` plus AC21's date check keeps the advisor's "no merge-timing rules" benefit instead. |
| Same-day thread: `publish_date` = merge date, a 13:00-14:00 UTC no-merge window, and a same-day manual trigger for late merges (plan v1) | `ship` queues auto-merge, so the merge moment is not chosen and the window cannot be honoured (CTO). A merge just before 14:00 UTC posts links to a page that is not live yet, and X caches the broken card. Next-day scheduling removes the race, the window and the manual trigger (DHH, code-simplicity, CTO). |
| Undated post filename, so no redirect row and no Terraform change (code-simplicity) | It drops a handoff-listed deliverable and breaks the dated-filename convention that content-writer uses by default. Recorded as DC-5 for the founder. |
| Tag `case-study` | Puts the post among department walkthroughs, which mislabels a method post (CMO). |
| Tag `CaaS` | Visible chip jargon for this reader. |
| Leave the distribution file as `draft` (the social-distribute default) | Auto-promotion posts it on the next free Tue/Thu, not with the post. |
| Use `feature-tweet` for a with-merge tweet | Superseded by the CMO table: the thread ships with the post from the distribution file. |
| Replace the post with a different topic | The handoff recommends a re-angle. Only the technical telling failed. |

## Open Code-Review Overlap

1 open code-review issue mentions a file this plan edits. The check ran `gh issue list --label code-review --state open --limit 200` (81 issues), with a `jq contains` match per path.

- **#3649** (a content brief for PR-A2 #3603, scheduled for PR-C merge) mentions `knowledge-base/marketing/content-strategy.md` and `distribution-content/`. **Acknowledge.** It tracks a different row and a different launch. This plan edits only the #8548 row and its calendar entry, and adds a new distribution file.

No open code-review issue mentions `seo-bulk-redirects.tf`, `plugins/soleur/docs/blog/` or `plugins/soleur/docs/images/blog/`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder arriving from X or LinkedIn finds a post that still reads as an engineering write-up (a command, an issue number, "30 of 118"), decides "this isn't for me", and leaves. Other ways it can break:
  - the X thread posts days late, or never (a `stale` file);
  - it links to a page that is not live yet, and X caches the broken preview card;
  - the dated URL 404s.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The diff is public marketing prose, a PNG, a distribution file posted from the existing publisher, and one additive edge-redirect row. No user data, credential or new data flow is involved.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the only sensitive-path edit is one additive public blog redirect row in seo-bulk-redirects.tf, which carries no user data and reverts by deleting the row.`

## Observability

The only production-mutating change is the redirect row, which the existing edge list serves. The X thread goes out through the existing publisher cron and its existing monitors.

```yaml
liveness_signal:
  what: "Better Stack monitor betteruptime_monitor.seo_redirect_bulk_item (a liveness check on the shared account Bulk Redirect list via its privacy-policy item, expecting 301; it does not probe blog items) plus the Sentry cron monitor scheduled-content-publisher for the thread"
  cadence: "180s for the redirect monitor; daily 14:00 UTC for the publisher"
  alert_target: "Better Stack incident (operator email) for the redirect list; Sentry cron-monitor missed/failed check-in for the publisher"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf (resource betteruptime_monitor.seo_redirect_bulk_item); apps/web-platform/server/inngest/functions/cron-content-publisher.ts (SENTRY_MONITOR_SLUG)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (publisher cron heartbeat and reportSilentFallback); GitHub issue '[Content Publisher] X API failed -- manual posting required for <title>' opened by scripts/content-publisher.sh"
  fail_loud: "apply-web-platform-infra.yml job failure on merge (terraform apply of cloudflare_list.legal_redirects); a publisher X failure opens the GitHub issue carrying the thread text"

failure_modes:
  - mode: "Dated slug not redirected (row missing, typo, or apply failed)"
    detection: "scripts/validate-blog-links.sh Guard 1 in CI (pre-merge); apply-web-platform-infra.yml failure (post-merge); post-merge curl of the dated URL expecting 301 in soleur:ship"
    alert_route: "PR CI red / workflow failure notification"
  - mode: "Thread never posts (file went stale after a late merge)"
    detection: "content-publisher.sh stale detection writes the STALE_EVENTS_FILE TSV row the cron reports; AC21 plus the Phase 5 stale guard keep publish_date at merge date + 1 before merge"
    alert_route: "Sentry (cron) and the ship phase's post-merge verification"
  - mode: "X API rejects the thread"
    detection: "content-publisher.sh opens the '[Content Publisher] X API failed' GitHub issue"
    alert_route: "GitHub issue (action item) for manual posting"

logs:
  where: "GitHub Actions logs for apply-web-platform-infra.yml and deploy-docs.yml; Inngest run logs plus pino to Better Stack for cron-content-publisher"
  retention: "GitHub Actions 90 days; Better Stack per plan retention"

discoverability_test:
  command: "curl -s --max-time 10 -o /dev/null -w %{http_code} https://soleur.ai/blog/2026-06-15-best-ai-tools-for-solo-founders-2026/"
  expected_output: "301"
```

## Encryption Posture

No persistent store and no new cross-component connection. The one `.tf` edit appends three items to the existing account-level Cloudflare Bulk Redirect list (`cloudflare_list.legal_redirects`), and the blog is served over the existing Cloudflare edge.

```yaml
at_rest: []    # no new store
in_transit: [] # no new connection; existing visitor -> Cloudflare edge path is unchanged
```

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** CMO: the Blog note settles most choices. Title, SEO title and meta direction are adopted. Channels are X, the LinkedIn pair, IndieHackers, Reddit and Discord, with Bluesky lowest priority and no HN. The plan automates X, both LinkedIn pages, Discord and Bluesky. IndieHackers and Reddit stay as manual-copy sections. The waitlist is the only honest CTA. The thread is written from the founder's line, not the bug. Grep the draft for "headless" before the PR. Copywriter review is required. CMO recommended a new "Founder Playbooks" index section instead of reusing a tag. This plan defers that (Non-Goals) and records the dissent in `decision-challenges.md`.

### Product/UX Gate

**Tier:** none. No `*.njk`, `*.tsx`, page or component file is created or edited. The post renders inside the existing `blog-post.njk` layout.

**Brainstorm-recommended specialists:** none (no brainstorm). CMO-recommended `soleur:marketing:copywriter`: **invoked** (Content Review Gate). Its fixes are folded in:

- drop "20-minute";
- no "assistant";
- consistent first person;
- one CTA;
- SEO title "…Keep Track of Decisions";
- heading "What changed: decisions stay decided";
- the X thread draft.

Its suggestion to drop the `ai-agents` tag conflicts with the index-routing requirement. It is recorded as a Taste decision challenge. `soleur:product:spec-flow-analyzer` was invoked for the publication flow. Its findings are folded into Phase 5: scheduled over draft, re-dating, undated URLs, and the page going live before the thread. The plan-review panel (DHH, Kieran, code-simplicity, CMO, CTO) replaced the same-day timing rules with next-day scheduling.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1**: exactly one new post exists at `plugins/soleur/docs/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`. Its frontmatter `date:` equals the filename date and is unquoted. `ogImage` is `"blog/og-parked-vs-forgotten-ideas.png"`, and that PNG exists at 1200×630.
- [ ] **AC2**: the title, `seoTitle`, `description` and the first paragraph name the founder's problem. The first paragraph contains "I lose track of what I decided and what I just forgot".
- [ ] **AC3**: `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` exits 0.
- [ ] **AC4**: this command prints `0` (FAQ JSON-LD excluded, closing link line excluded):

  ```bash
  awk '/<script type="application\/ld\+json">/{s=1} !s{print} /<\/script>/{s=0}' <post> | grep -v 'For the technical write-up' | grep -c -i -E '30 of 118|(^|[^0-9])118([^0-9]|$)|Phase [0-9]|milestone|Post-MVP|Not Yet Specified|Out of Scope|frontier|GitHub Issues|headless|8808|assistant|copilot|product-roadmap|--limit|gh issue' || true
  ```

  Matches are case-insensitive on purpose. Plain-English uses of "milestone" or "out of scope" are also rewritten, so the reader never meets roadmap vocabulary.

- [ ] **AC5**: `grep -c 'github.com/jikig-ai/soleur' <post>` prints `1`, and that one line is the last non-JSON-LD content line, reading "For the technical write-up, see [how we fixed it](https://github.com/jikig-ai/soleur/pull/8536)".
- [ ] **AC6**: the first body line mentioning "Pocock" carries a markdown link to `https://github.com/mattpocock/skills`.
- [ ] **AC7**: the post's single CTA is written as `[{{ site.primaryCta.label }}]({{ site.primaryCta.url }})`, and the built HTML renders it as `site.json`'s label and URL. No terminal command, install step or second "next step" link, apart from the closing technical link.
- [ ] **AC8**: `soleur:marketing:fact-checker` reports every claim PASS or SOURCED. No `[FAIL` or `[UNSOURCED]` markers remain in the file.
- [ ] **AC9**: `tags` are `solo-founder`, `decision-making` and `ai-agents`. In the built `_site/blog/index.html`, `awk '/<section id="company-as-a-service"/,/<\/section>/' _site/blog/index.html | grep -c 'href="/blog/parked-vs-forgotten-ideas/"'` prints `1` and the same command over `id="engineering"` prints `0`; that is, the post's card appears inside `id="company-as-a-service"` and **not** inside `id="engineering"`.
- [ ] **AC10**: the distribution file has `status: scheduled`, `publish_date` equal to the post filename date plus one day, and `channels: discord, x, bluesky, linkedin-company, linkedin-personal` with no `hackernews`. Its X/Twitter Thread section holds 4-6 **labeled** tweets (`**Tweet N (…) -- NNN chars:**`), each 280 characters or fewer. The link appears only in the final tweet, as the absolute undated URL with UTM. The HN section is a one-line note (a pointer to the technical write-up, or "skipped") with no HN tracked URL. `grep -c -i -E 'headless|8808|30 of 118' <distribution file>` prints `0`.
- [ ] **AC11**: `bash scripts/lint-distribution-content.sh <distribution file>` exits 0, and `bun test plugins/soleur/test/distribution-content-format.test.ts` passes. Its output must include the test "labeled X thread tweets are within the 280-char limit" for this file, which proves the length check actually ran.
- [ ] **AC12**: `seo-bulk-redirects.tf` has exactly one new `blog_redirect_pairs` row, `"<YYYY-MM-DD>-parked-vs-forgotten-ideas" = "parked-vs-forgotten-ideas"`, whose key equals the post's filename stem. `terraform fmt -check apps/web-platform/infra/seo-bulk-redirects.tf` exits 0.
- [ ] **AC13**: `bash scripts/validate-blog-links.sh _site` exits 0 after `npm run docs:build`. Guard 1 checks redirect parity and the distribution URLs resolve.
- [ ] **AC14**: `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts plugins/soleur/test/marketing-content-drift.test.ts plugins/soleur/test/redirect-tombstones.test.ts plugins/soleur/test/blog-audience-contract.test.ts` passes.
- [ ] **AC15**: in `content-strategy.md`, `git grep -n -e 'product-roadmap next --frontier' -e 'technical PMs who plan in GitHub Issues' -e 'Undecided from Forgotten' -- knowledge-base/marketing/content-strategy.md` prints nothing. The #8548 row and its calendar entry name the new title, the non-technical founder audience and "no Hacker News".
- [ ] **AC16**: the diff is limited to the three created files, the two edited files, and the pipeline-written plan/spec/INDEX files listed under Files to Edit.
- [ ] **AC17**: `knowledge-base/project/specs/feat-one-shot-8548-blog-undecided-vs-forgotten/decision-challenges.md` carries DC-1 (founder-facing blog index section, including the `company-as-a-service` mis-bucketing), DC-2 (the `ai-agents` chip) and DC-3 (founder review before merge), so `ship` Phase 6 renders them under `## Model Dissents (informational)` and files the `action-required` issue.
- [ ] **AC21 (date coupling)**: this check prints `ok`.

  ```bash
  post=$(ls plugins/soleur/docs/blog/*-parked-vs-forgotten-ideas.md)
  dist=$(ls knowledge-base/marketing/distribution-content/*-parked-vs-forgotten-ideas.md)
  [ "$(printf '%s\n' "$post" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$dist" | wc -l)" -eq 1 ] || { echo "expected exactly one post and one distribution file"; exit 1; }
  d=$(basename "$post" | cut -c1-10)
  [ -n "$d" ] || exit 1
  n=$(python3 -c "import datetime,sys;print(datetime.date.fromisoformat(sys.argv[1])+datetime.timedelta(days=1))" "$d")
  [ "$(basename "$dist" | cut -c1-10)" = "$d" ] \
    && grep -q "^date: $d\$" "$post" \
    && grep -q "^publish_date: \"$n\"\$" "$dist" \
    && grep -q "\"$d-parked-vs-forgotten-ideas\"" apps/web-platform/infra/seo-bulk-redirects.tf \
    && echo ok
  ```

  It checks that the post filename date, the post `date:`, the distribution filename date and the redirect key are identical, and that `publish_date` is exactly one day later. Re-run it after any ship-time re-date. It uses `ls`, not `git ls-files`, so it also works before the files are committed.
- [ ] **AC18**: the PR body's first line states that merging applies one additive Cloudflare edge-redirect row automatically. The body uses `Closes #8548`.

### Post-merge (automated in soleur:ship)

- [ ] **AC19**: `deploy-docs.yml` succeeds on the merge SHA. `curl -s -o /dev/null -w '%{http_code}' https://soleur.ai/blog/parked-vs-forgotten-ideas/` prints `200`, and the dated URL prints `301` after `apply-web-platform-infra.yml` succeeds.
- [ ] **AC20**: on `publish_date`, the day after the post goes live, the publisher's 14:00 UTC run posts the thread, and its bot PR flips the distribution file to `status: published`. It must never reach `status: stale`: the Phase 5 stale guard re-dates before merge whenever auto-merge slips past the post date.

## Test Scenarios

- Given the drafted post, when `blog-jargon-scan.sh` runs, then it exits 0. When AC4's grep runs, then it prints 0.
- Given the post with a leftover "30 of 118" line (a mutation), when AC4's grep runs, then it prints ≥1. This proves the check can go red.
- Given the redirect row with a mistyped date key, when `validate-blog-links.sh` runs, then Guard 1 fails.
- Given the distribution file left as `status: draft`, the plan's AC10 fails. This is the regression the spec-flow review named.
- Given auto-merge still pending on the UTC day after `<YYYY-MM-DD>`, when the Phase 5 re-date block runs, then AC21 prints `ok` for the new date and `publish_date` is the new date plus one day, so the publisher never sees a past date.
- Given the built site, when `_site/blog/index.html` is parsed, then the post appears under "What is Company-as-a-Service?" and not under Engineering Deep Dives.

## Success Metrics

- Founder review accepts the post as written for them.
- The X thread posts at the first publisher run after go-live, the next day at 14:00 UTC.
- Reader signals (X engagement, waitlist sign-ups from `utm_campaign=parked-vs-forgotten-ideas`) are read from existing analytics. No new tracking.

## Dependencies & Risks

- **Risk: the credit link's content drifts.** Phase 0 re-checks the upstream repo, and the credit softens to "inspired by" if the mechanic is no longer visible.
- **Risk: the fact-checker cannot open GitHub PR bodies.** PR #8536 is public, and its body section "Pre-existing `next` defects folded in" is the source for "about a quarter".
- **Risk: the X API fails.** The publisher opens a manual-posting issue carrying the thread text.
- **Dependency:** none open. The Blog note (PR #8801) and the technical fix (PR #8536) are both merged.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- **Scheduled date vs. merge date.** The publisher posts only when `publish_date == today`, and a past date turns the file `stale` permanently. `publish_date` is the post date plus one day, so the thread goes out at the first 14:00 UTC run after the page is live. Re-date all coupled values together with the Phase 5 block (post filename, `date:`, redirect key, distribution filename, `publish_date`) whenever the merge slips past the post date.
- **The jargon scan is a subset.** It misses file paths, bare command or skill names and bare numbers, so AC4's exclusion grep and a manual read against the Blog note are required. Tags are reader-visible chips.
- **`marketing-content-drift.test.ts` Test 2c2** rejects "Soleur" within 40 characters before "open source" on one line. Word the Pocock credit without "open source" near "Soleur".
- **Absence greps quote their own tokens.** AC4 and AC10 scope to the post and the distribution file. They must never run over this plan, which quotes the forbidden tokens.
