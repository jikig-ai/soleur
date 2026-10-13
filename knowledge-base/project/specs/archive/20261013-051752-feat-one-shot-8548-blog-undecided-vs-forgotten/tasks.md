# Tasks: #8548 re-angled blog post, "Parked or Forgotten?"

Plan: `knowledge-base/project/plans/2026-09-25-content-blog-parked-vs-forgotten-for-founders-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-read `brand-guide.md` `### Blog`, `### X/Twitter` and `### Audience Voice Profiles`.
- [ ] 1.2 Confirm `https://github.com/mattpocock/skills` returns 200. If the wayfinder "Not yet specified" and "Out of scope" sections are gone, soften the credit.
- [ ] 1.3 Set `<YYYY-MM-DD>` to today's UTC date.

## Phase 2: Core Implementation

- [ ] 2.1 Draft the post with `soleur:content-writer`, run inline, using the plan's Post specification as the outline.
  - [ ] 2.1.1 Write the file to `plugins/soleur/docs/blog/<YYYY-MM-DD>-parked-vs-forgotten-ideas.md`, with `date:` unquoted and equal to the filename date.
  - [ ] 2.1.2 Write in the founder's first person. The opening sentence stays verbatim (DC-4). Do not say "assistant".
  - [ ] 2.1.3 Credit Matt Pocock with an inline link at first mention, using the fact-checked wording: only "not yet defined" and "decided against" come from his wayfinder method, and the four-place rule and the "forgotten" test are ours. Do not put "open source" near "Soleur".
  - [ ] 2.1.3a The story paragraph says "about a quarter of our current plan", not "of our plan" (DC-6). State the wrong pick and the limit side by side, with neither as the cause of the other.
  - [ ] 2.1.3b Frontmatter: `seoTitle: "Parked vs. Forgotten Ideas: How Solo Founders Track Decisions"`. The description is 120-160 characters and names parked vs forgotten. Do not set `pillar:`.
  - [ ] 2.1.3c Use "idea parking lot" once within the first 100 words, with a one-sentence definition. Add one inline contextual link to `/blog/how-to-run-every-department-with-ai-agents/`; it is not a CTA, and its link text contains no "agent".
  - [ ] 2.1.4 Write the one CTA as `[{{ site.primaryCta.label }}]({{ site.primaryCta.url }})`.
  - [ ] 2.1.5 Make the closing technical link the last line: "For the technical write-up, see [how we fixed it](https://github.com/jikig-ai/soleur/pull/8536)".
  - [ ] 2.1.6 Add three standalone FAQs using the `faq-list`/`faq-item` markup and `"@type": "FAQPage"` JSON-LD. The questions come from the plan, and each answer is 40-60 words with no links. File order: body → FAQ → CTA → closing link → JSON-LD.
  - [ ] 2.1.7 Reach `SCAN_RC=0` on the jargon scan and PASS or SOURCED on every fact-check claim.
  - [ ] 2.1.8 Run a `soleur:marketing:copywriter` voice pass on the finished draft, then re-run the scan. Re-run the fact-check only if a claim changed.
- [ ] 2.2 Generate the OG image with deterministic PIL: 1200×630, textless, gold on `#1A1A1A`. Save it as `plugins/soleur/docs/images/blog/og-parked-vs-forgotten-ideas.png`, then run the all-posts `ogImage` audit.
- [ ] 2.3 Create the distribution file with `soleur:social-distribute`, run inline. Decline the immediate Discord post.
  - [ ] 2.3.1 Set `status: scheduled`, `publish_date` to the post date plus one day, and `channels: discord, x, bluesky, linkedin-company, linkedin-personal`.
  - [ ] 2.3.2 Use the labeled X thread format. Put the link, as the undated UTM URL, only in the final tweet. The HN section is a one-line note.
  - [ ] 2.3.3 `bash scripts/lint-distribution-content.sh <file>` exits 0.
- [ ] 2.4 Add the `seo-bulk-redirects.tf` row `"<YYYY-MM-DD>-parked-vs-forgotten-ideas" = "parked-vs-forgotten-ideas"`, then run `terraform fmt -check`.
- [ ] 2.5 Rewrite the #8548 Pillar-2 row and its rolling-calendar entry in `content-strategy.md`.

## Phase 3: Testing

- [ ] 3.1 Run `npm run docs:build`, then `bash scripts/validate-blog-links.sh _site`.
- [ ] 3.2 Run `bun test` on `seo-aeo-drift-guard`, `distribution-content-format`, `marketing-content-drift`, `redirect-tombstones` and `blog-audience-contract`. Confirm the labeled-tweet length test ran for the new file.
- [ ] 3.3 AC4's exclusion grep prints 0, and AC21's date check prints `ok`.
- [ ] 3.4 Built index: the post's card is inside `id="company-as-a-service"` and not inside `id="engineering"`. The CTA renders with no literal braces.
- [ ] 3.5 Confirm neither the post nor the distribution file mentions #8808 or "headless".
- [ ] 3.6 Ship: if the UTC date changed, run the Phase 5 re-date block immediately before queueing the merge. The PR body's first line discloses the auto-applied redirect row, and the body uses `Closes #8548`.
- [ ] 3.7 Post-merge: `deploy-docs` is green, the page returns 200 and the dated URL returns 301. The thread posts at 14:00 UTC on `publish_date`, and the file reaches `status: published`.
