---
title: "fix(web): homepage copy and trust fixes (plan-cost line, privacy text, stale agent count) and land the #9580 CLO audit"
type: fix
date: 2026-10-06
slug: homepage-copy-and-trust-fixes
branch: feat-one-shot-9579-9580-homepage-copy-trust-fixes
issue: 9579
closes: [9579, 9580]
priority: p3-low
domain: marketing
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** 6 (Guard Contract, Phase 2 steps 1 to 11, Phase 3, Phase 4, Acceptance Criteria, Dependencies & Risks)
**Agents used before this pass (all findings merged into the sections below):** repo-research-analyst, learnings-researcher, functional-discovery, fact-checker, CMO, CLO, CPO, spec-flow-analyzer, ux-design-lead, copywriter, then a plan-review panel of DHH, Kieran, code-simplicity, architecture-strategist, CPO and CMO.

### Key Improvements

1. Guard 1 was re-derived after Kieran measured it against a real build: the case-sensitive "hosted" matcher missed the exact pricing sentence it exists to catch. It now uses an inverted, case-insensitive rule over every sentence, with floors and a key-phrase parity check (existing parity tests compare only question names and counts, not answer text).
2. Guard 2 now scans RAW template source (stripping template tags would have hidden the JSON-LD string concat and the page-freshness `{% set %}` strings), and its cascade mutation covers every page that includes the freshness block.
3. Guard 3's population was corrected: the Organization JSON-LD is emitted only on `/`, and four blog posts and two distribution files still carry the same framing until #9589, so text checks are scoped to the pages this PR fixes.
4. The critical-CSS gate chain was completed: `check-critical-css-coverage.mjs` never scans `index.njk` (added to its roots), the inline block has a 9 KB warn / 11 KB fail gzipped budget, the CSP hash must be recomputed last and `validate-csp.sh` runs in the inner loop, and the screenshot gate's single global viewport needs a second browser context for the 390px check.
5. D5 and D7 now share one gate (Buttondown double opt-in verification), and the brand-guide amendments follow the CMO's narrower wording.

### New Considerations Discovered

- `marketing-content-drift.test.ts` Test 1 rejects literal stale counts (`59|61|62|63|65|66|67 agents|skills`) across `knowledge-base/marketing/**`; the brand-guide note must not quote a count.
- Pencil CLI 0.3.8 writes a session `fileToken` UUID into `.pen` files and the commit-time gitleaks scan flags it as a generic API key (false positive); other committed `.pen` files carry no such key, so it was stripped before committing. The repo MCP adapter also silently saves empty documents against that CLI version (see Dependencies & Risks).
- Deepen gates run: 4.6 User-Brand Impact present with a valid threshold; 4.8 no PAT-shaped tokens; 4.9 `.pen` wireframe referenced and committed (116 KB); 4.10 no store or connection (skipped); 4.11 `lint-guard-contract.py` green on 3 entries and assemblies are structural; 4.12 exactly one unfenced Scope Check, every ask mapped, no BLOCKED marker. Live checks: every cited rule id is active, every cited issue and PR resolved (#1439, #2965, #3165, #4757, #5068, #9500, #9573, #9584 all as described), all cited paths exist.

## Overview

One marketing PR that lands the six homepage copy and trust items from the deferred Sutra
competitor-analysis follow-up, and files the CLO live-terms audit that gates three of them.
The audit already sits untracked in the worktree; this PR commits it and closes its tracking issue.

Note: no `spec.md` exists for this branch, so `lane:` defaults to `cross-domain` (fail-closed). The Phase 4 evaluation issue (#9588) and the roadmap row are the follow-up tracking items.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9579 and #9580 are both OPEN with no closing PR; draft PR is #9584. The audit file exists untracked at
`knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md` (23.6 kB, read in full).
`stats.js` output verified by running it: `{ agents: 67, skills: 103, commands: 3, departments: 8 }`; the issue's "67" holds.
`site.json` `statsLastVerified` is `2026-04-22` as claimed. The ADR corpus has no ADR on soft-floor counts or hero CTA hierarchy
(grep of `knowledge-base/engineering/architecture/decisions/` hit only unrelated BYOK/SDK ADRs).

What was STALE or contradicted (each is a plan decision, see `## Research Reconciliation`):

- **No `/compare/` page exists.** Only `compare/soleur-vs-cursor/` and `compare/soleur-vs-devin/` are built. Item 6 as worded links to a 404.
- **Item 4 collides with a closed P1 and an enforcing test.** Brand-guide `Numbers: soft floors in prose` (line 81) and
  `plugins/soleur/test/seo-aeo-drift-guard.test.ts` Test 16 (#3165) require the `60+` soft floor in homepage/pricing/about prose and
  forbid `\d+ agents` prose. `60+` is accurate for agents (67) and understated for skills (103).
- **Item 3 collides with brand-guide line 491**: "Do not reference CLI installation as the primary CTA in any new landing page content"
  (2026-03-22 business validation, premised on the hosted platform launching; it has not).
- **Item 5 is bigger than "verify".** The fact-checker found the homepage blockquote is NOT in the cited Inc.com article, the
  "As seen in: Inc.com, the thesis behind Soleur" strip is contradicted (the article never mentions Soleur), and `base.njk`
  declares an Organization `subjectOf` NewsArticle with a wrong `datePublished`.
- **The sr-only waitlist sentence over-claims versus the Privacy Policy.** Section 4.6 covers "newsletter" signup via the Docs
  Site form (purpose: periodic emails about Soleur updates, double opt-in, Buttondown as processor). The word "waitlist" appears
  nowhere in `docs/legal/*.md`, and "only email you about your waitlist spot" is narrower than 4.6.
- **Brand guide bans "plugin"/"tool"** in public copy, so the audit's phrase "self-hosted plugin" must render as "self-hosted version".

### Property List (Phase 0.6b)

- P1. A visitor can tell, near the hero, what Claude access each path needs: self-hosted runs in their own Claude Code on their plan or key; hosted takes their own Anthropic API key. No hosted statement uses "plan", "Pro/Max" or "subscription limits".
- P2. A visitor sees, at the point of entering an email, what will be done with it, and each clause traces to the Privacy Policy.
- P3. A visitor can start the free self-hosted path from the first screen while the hosted waitlist stays available.
- P4. Agent and skill counts in homepage prose equal what the build computes, and `statsLastVerified` reflects a real verification.
- P5. Every attributed quote and third-party claim on the homepage is supported by the source it cites.
- P6. The hero reaches a comparison page that exists, and a community door follows the FAQ.
- P7. The CLO audit is committed and #9580 closes with this PR.
- P8. Existing site copy that contradicts the CLO constraints (pricing page) is corrected in the same PR.
- P9. The finished wording for items 1 to 3 gets CLO sign-off before merge.

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| New `/compare/` hub page (implied by "link to /compare/") | P6 | Two comparison pages already exist; link to the one whose title matches the hero link text. Hub becomes its own issue if wanted. |
| A/B experiment framework for the CTA test | P3 | No infra exists; Plausible already receives `Waitlist Signup` with `location: homepage-hero`, so a before/after window with one added click event measures it. |
| Follow-through probe script for the CTA test | P3 | Evaluation is a judgement call on Plausible data, not a soak-gated close; a plain tracking issue is enough. |
| Privacy Policy / legal-doc edit to name "waitlist" | P2 | Visible wording is rewritten to fit 4.6 as it stands; whether 4.6 should name "waitlist" is a CLO question tracked as a follow-up. |
| Rewriting the 4 Amodei blog posts | P5 | They are dated posts with their own sources; one tracking issue, not this PR. |
| Web-platform key-rotation-form / ws-client copy edits | P1 | Operator-only oauth branch (403 for everyone else per the audit); acknowledged, no change unless CLO says otherwise. |

### Repo and institutional findings

- Guards that pin this copy: `seo-aeo-drift-guard.test.ts` Test 16 (lines ~1297-1361: soft floor + hero `href="#soleur-vs-copilots"`), `#2707` pricing FAQ parity (visible `<details>` equals FAQPage JSON-LD, test at line ~172), `#3171` FAQPage parity on the homepage (line ~1006), `#2708`/`#2808` homepage title and meta description. CI runs `validate-seo.sh _site`.
- Form wiring: `base.njk` `handleSignupForm` selects `.hero-waitlist-form` for the hero (event `Waitlist Signup`, `location: homepage-hero`); `.newsletter-privacy` is the visible-text class already used on `/pricing/`.
- Critical CSS (`cq-eleventy-critical-css-screenshot-gate`): hero selectors (`.landing-hero*`, `.hero-cta`, `.hero-waitlist-form*`, `.newsletter-form*`) are inlined in `base.njk`; any NEW above-the-fold selector must be inlined there and pass `plugins/soleur/docs/scripts/screenshot-gate.mjs`. `.newsletter-privacy` is NOT in the inlined set today (it was never above the fold); the hero privacy line now is.
- Learnings applied: `2026-03-06-blog-citation-verification-before-publish.md` (no naked quotes, fact-check before publish), `2026-02-21-marketing-audit-brand-violation-cascade.md` (grep the full repo for each banned term; legal docs live in two locations), `2026-03-25-waitlist-form-reuse-newsletter-pattern.md` (reuse `.newsletter-form` classes), `2026-02-17-playwright-screenshots-land-in-main-repo.md` (absolute paths for screenshots).
- Discord: `site.discord` is already used in `base.njk` footer, `community.njk` and `blog.njk`; no new data needed.
- Open code-review overlap check ran against the planned files: no issue body names any of them (only #2965, which names the docs directory generally).
- Functional overlap: registries offer nothing beyond the local `copywriter`, `fact-checker`, `clo` agents; nothing to install.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality | Plan response |
|---|---|---|
| Item 6: "Link the hero to `/compare/` instead of the in-page anchor" | No `/compare/` route is built. `compare/soleur-vs-cursor/` and `compare/soleur-vs-devin/` exist; neither has an install or waitlist CTA; the Cursor page does not mention Copilot. | Link to `/compare/soleur-vs-cursor/` with neutral text "Compare Soleur with Cursor". No hub (Cut List). Hub, CTA blocks and a screenshot-gate route for the compare pages go to a follow-up issue. |
| Item 4: replace hardcoded "60+" with the computed count | Brand-guide `Numbers: soft floors in prose` and drift-guard Test 16 (#3165, closed P1) require the soft floor on homepage/pricing/about. `{{ stats.* }}` prose is build-time computed and cannot drift; `llms.txt.njk` and the stat strip already render exact counts. `page-freshness.njk` is shared by 7 pages, and pricing/about are pinned to the floor. | Operator direction (exact computed count) is the default. Scope: `index.njk` hero, FAQ (+ JSON-LD twin), final CTA, plus `page-freshness.njk` behind an opt-in `summaryCounts: computed` frontmatter flag that only the homepage sets. Pricing and about keep the soft floor. Brand-guide Numbers rule gets a dated carve-out; Test 16 is re-pinned. CMO alternative (floor-to-nearest-10 filter) is recorded as a decision challenge. |
| Item 3: "Test self-host install as the primary CTA" | Brand-guide line 491 forbids a CLI-install primary CTA in new landing content, premised on the hosted platform launching (it has not). There is no experiment tooling. | Ship as a time-boxed, measured rollout (CPO: it is a rollout, not an experiment): one new Plausible event, a baseline pulled before merge, metrics and decision rule in a Phase 4 tracking issue, dated carve-out in the brand guide. |
| Item 2: sr-only text can be made visible | The sentence ("only email you about your Soleur waitlist spot") is narrower than Privacy Policy 4.6 (periodic newsletter emails about updates; "waitlist" is not named anywhere in `docs/legal/`). `/pricing/` already shows "No spam. We email you once when early access opens.", which has the same defect. | Rewrite the line so each clause traces to 4.6 and use the same text on both pages. Privacy Policy edit is out of scope (follow-up for CLO). |
| Item 5: "verify the attribution" | Fact-check: blockquote not in the cited article; "As seen in Inc.com" contradicted; `base.njk` `subjectOf` NewsArticle is false structured data with a wrong date; `company-as-a-service.njk:136` says "interview". | Replace with a dated, attributed paraphrase (no quotation marks), drop the strip, remove `subjectOf`, fix the interview wording, add a non-affiliation line. Blog posts with the same sources go to a follow-up issue. |
| Item 1: "currently only in the FAQ and pricing page" | Also asserted wrongly elsewhere: `/pricing/` FAQ "Pro, Max,", claude note "Claude subscription or API key", FAQ "You choose the Claude plan"; `/getting-started/` "keep every byte of memory on your own machine" and "your data, your compute"; homepage "Is Soleur free?" blurs hosted into "Claude usage". | One sweep of all of them in this PR (CLO pre-review items 1 and 2), enforced by a drift guard. |
| Audit: "self-hosted plugin" | Brand guide bans "plugin"/"tool" in public copy. | Render as "self-hosted version". |
| Audit/brief: `key-rotation-form.tsx:137` and `ws-client.ts:1208` mention the Claude subscription | Operator-only oauth branch (`canUseOauthCredential` and `CC_OAUTH_ENABLED`); no customer reaches them (CLO pre-review). | Acknowledge, no change; recorded in the sign-off. A widened gate fires the audit's re-evaluation trigger. |

## Proposed Solution

Four edits to one story: say precisely who pays for Claude on each path, say precisely what happens to an email address, stop asserting things no source supports, and make the homepage numbers computed. Every changed string is checked against the audit's section 6 constraints, and the finished wording goes to the CLO before merge.

### Decisions

- **D1 Counts (item 4).** Exact computed counts in `index.njk` prose (hero-sub, FAQ HTML and JSON-LD, final CTA) and in the `page-freshness.njk` summary when the page sets `summaryCounts: computed`. Skills render too (103 versus the stale "60+"). Pricing and about keep the soft floor. `site.json` `statsLastVerified` is set to the actual verification date after the counts are compared against `stats.js` output in the same session.
- **D2 CTA (item 3).** Hero order, as drawn in the committed wireframe (`knowledge-base/product/design/marketing/homepage-hero-trust-9579.pen`, frame B): eyebrow, H1, tagline, hero-sub, the existing `hero-trust` line (kept), primary "Get the self-hosted version" button (`btn-primary`, the only gold button in the hero) with sub-label "Source-available. Runs inside your own Claude Code; you pay for your own Claude usage.", a bordered hosted card labelled "Hosted version (coming soon)" holding the existing email form (submit demoted to `btn-secondary`, outline) and the now-visible privacy line, the two-column plan line (self-hosted and hosted sentences, never merged), and one neutral compare link. The nav CTA ("Join the waitlist") stays. The final CTA at the page bottom stays waitlist-led on purpose: the rollout's scope is the hero only. No "free" on the button (CMO/CLO), no "install", "CLI" or "terminal" (brand guide). The existing 768px rule `.hero-waitlist-form .btn-primary { flex: 1 1 100% }` must be widened to cover `btn-secondary`. Wireframe labels differ slightly from the final strings above; the strings in this plan govern.
- **D3 Compare (item 6).** `href="/compare/soleur-vs-cursor/"`, text "Compare Soleur with Cursor". The in-page `#soleur-vs-copilots` section and its `id` stay (AEO, #3996); its sentence "Cursor and Copilot start fresh every session. Soleur remembers." and the FAQ and JSON-LD variant "Cursor starts fresh every session. Soleur remembers." become "Soleur keeps a persistent knowledge base across every department." because the brief says brand-guide competitor-claim rules apply and that sentence states what a competitor lacks.
- **D4 Attribution (item 5).** See Phase 2 step 6. No verbatim Amodei quotation marks anywhere on the homepage; past tense; "Inc. reported" for the 70 to 80 percent.
- **D5 Privacy line (item 2).** Candidate (CLO-approved shape, final text still goes to sign-off): "We'll email you Soleur updates, including when hosted access opens. Double opt-in, unsubscribe any time. Sent through Buttondown. Privacy Policy." If double opt-in cannot be verified in Phase 0, use the version without that sentence. Same text on `/pricing/`.
- **D6 Hosted wording (item 1).** Hero plan line is two separate elements: "Self-hosted runs inside your own Claude Code, signed in with your Claude plan or an Anthropic API key." and "Hosted version (coming soon): bring your own Anthropic API key, billed by Anthropic to you." No "private", no "we never see your data", no plan/Pro/Max/limits wording on any hosted statement, and nothing that says Soleur pays for or bundles Claude usage.
- **D7 Form success state.** The shared success string says "You are on the list" before the double opt-in click, and says "cloud platform" while the rest of the site says "hosted". It becomes "Check your inbox to confirm your spot (and your spam folder). Meanwhile, you can get the self-hosted version today." for the hero and pricing waitlist forms, but only if Phase 0 step 3 verifies double opt-in (same gate as D5); if it cannot be verified, keep the existing wording and change only "cloud platform" to "hosted version". This edits the hash-pinned inline script, so the CSP `sha256` in `base.njk` must be recomputed.
- **D8 Threshold.** `single-user incident`, because a wrong claim about which Claude credential hosted accepts or about email handling is a trust and legal exposure for each visitor who relies on it, and it matches the audit's own threshold. CPO has reviewed (Domain Review), so `requires_cpo_signoff` is satisfied by that carry-forward.

## Implementation Phases

### Phase 0 — Prerequisites that gate copy (do first; no copy edits yet)

1. **Baseline.** Pull the 28 days before the change: unique visitors to `/`, `Waitlist Signup` with `location=homepage-hero`, via the Plausible Stats API (`scripts/weekly-analytics.sh` shows the call shape; key `PLAUSIBLE_API_KEY` from Doppler if present). If the key is absent or scoped out, drive the dashboard with Playwright (`hr-exhaust-all-automated-options-before`). Record numbers and dates in the evaluation issue. If the baseline is under about 30 signups, say so in the issue (CPO: comparison is anecdotal below that).
2. **Plausible goal.** Create the goal `Hero Self-host Click` before merge (Plausible requires a matching goal). Try the Sites API; fall back to Playwright on the dashboard; the only human hand-off allowed is a login or 2FA gate.
3. **Double opt-in.** Confirm Buttondown confirmation emails are enabled (Buttondown API with the account key in Doppler, or settings via Playwright). The result gates both D5 (privacy line wording) and D7 (success text); freeze the final strings after this step.
4. **Fact-check the final quote block** with `soleur:marketing:fact-checker` once the wording is written (CMO: re-run on the replacement). The Inc.com page returns 403 to curl and WebFetch; read it with Playwright (it rendered in full during planning).
5. **Plausible tagged-event class.** Confirm with a local build plus Playwright that `class="plausible-event-name=Hero+Self-host+Click"` on the link fires under the site's `pa-…js` script and CSP (Plausible docs state the class syntax but not script-version scope). Class-based tagging is preferred to a new inline script because the CSP pins inline-script hashes.

### Phase 1 — RED: tests before copy (`cq-write-failing-tests-before`)

Edit `plugins/soleur/test/seo-aeo-drift-guard.test.ts` only, in the style of Test 16 (built-HTML presence checks, `html.includes` literals, no tag-strip regex). Add the three guards in `## Guard Contract` and re-pin Test 16. Run the suite and watch the new assertions fail for the right reason before Phase 2.

### Phase 2 — GREEN: copy and markup

1. `plugins/soleur/docs/index.njk`
   - hero: replace the `sr-only` class on the privacy `<p>` with `newsletter-privacy` (keep `id` and `aria-describedby`; the `<p>` currently carries `sr-only` only); add the plan line (two elements), the primary button with its tagged-event class and sub-label, the hosted block label (associated with the form via `aria-labelledby`), submit `btn-secondary`, compare link; delete the old "Or self-host it free" and `#soleur-vs-copilots` hero links.
   - counts: hero-sub, "What is Soleur?" (HTML and the JSON-LD string concat), final CTA line; `summaryCounts: computed` in the page frontmatter.
   - "Is Soleur free?" and "How do I get started?" (HTML and JSON-LD): hosted = own Anthropic API key; "cloud platform" becomes "hosted version" in the strings this PR already rewrites (no site-wide rename; `llms.txt.njk`, the `base.njk` SoftwareApplication offer name and the compare pages are left alone).
   - quote section, press strip and Discord line per D4/D5/D6 and Phase 2 step 6.
2. `plugins/soleur/docs/_includes/page-freshness.njk`: when `summaryCounts == "computed"` build the summary from `stats.agents`, `stats.skills`, `stats.departments` in both registers; default branches unchanged. The site already renders exact `{{ stats.* }}` counts on agents, skills, company-as-a-service and `llms.txt.njk`, so this documents existing practice; the opt-in only keeps pricing, about and the other pages on the floor their tests pin.
3. `plugins/soleur/docs/pages/pricing.njk` (visible HTML and the JSON-LD twin, parity test #2707): remove "Pro, Max,"; "Do I pay for Claude separately?" and "Is there a free option?" per the final strings; claude note becomes "Soleur plans don't include Claude usage. Hosted plans use your own Anthropic API key, billed by Anthropic to you."; waitlist privacy line replaced by the D5 text.
4. `plugins/soleur/docs/pages/getting-started.njk` (HTML and JSON-LD): "keep every byte of memory on your own machine" becomes "keep your knowledge base as plain files on your own machine"; "your data, your compute" becomes "your files, running inside your own Claude Code"; add a visible prerequisite line in `#self-hosted` ("Requires Claude Code, signed in with your Claude plan or an Anthropic API key", linking the existing Claude Code docs link); "cloud platform" becomes "hosted version"; add `scroll-margin-top` to `#self-hosted` only if a 375px screenshot of `/getting-started/#self-hosted` shows the fixed header covering the section label.
5. `plugins/soleur/docs/_includes/base.njk`: remove the Organization `subjectOf` NewsArticle block; add a short footer non-affiliation line; D7 success strings; inline any new above-the-fold selectors and extend the "Selectors covered" comment (`.sr-only`, `.newsletter-privacy` at hero scope with `flex-basis:100%`, `.newsletter-status` hero rules, `.btn-secondary`, the wrapped/column `.hero-cta`, plan-line and hosted-label classes); name the new classes `landing-hero-*` or `hero-waitlist-form-*` so `check-critical-css-coverage.mjs` recognises them, add `plugins/soleur/docs/index.njk` to that script's `TEMPLATE_ROOTS` (it scans only `pages/` and `_includes/` today and would never see the homepage), and check the inline block's gzipped size against the script's 9 KB warn / 11 KB fail budget before adding rules. Recompute the CSP `sha256` LAST: only the `handleSignupForm` inline script changes (the other two hashes stay), the success string appears twice (waitlist and hero), so finish all `base.njk` edits first, then run `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` immediately, in the Phase 2 inner loop (it runs in `deploy-docs.yml` only, not under `bun test`). The footer carries the short non-affiliation line (CLO: the naming rule is site-wide; the quote block carries the long form).
6. Attribution: replace `landing-quote` blockquote with a `<p>` carrying the past-tense paraphrase (CMO/CLO/copywriter shape: "In May 2025, at Anthropic's Code with Claude developer conference in San Francisco, Anthropic CEO Dario Amodei was asked when the first billion-dollar company with one human employee would arrive. His answer: 2026. Inc. reported that in a later press Q&A he put the chance at 70 to 80 percent."), a source line "Inc. report by Ben Sherry, May 23, 2025", and the non-affiliation line ("Soleur is an independent product, not affiliated with, sponsored by, or endorsed by Anthropic."); delete the "As seen in" strip and its now-dead `.landing-press-strip` and `.press-outlet*` rules in `style.css` (no test pins them). `company-as-a-service.njk:136`: "predicted in an interview with Inc.com" becomes "said at Anthropic's Code with Claude conference (May 2025)". `vision.njk:26` is an accurate paraphrase attributed to Inc. and is acknowledged, not edited.
7. Discord line after the FAQ list, inside the FAQ section, using `{{ site.discord }}` ("Questions we didn't cover? Ask in the Soleur Discord").
8. `plugins/soleur/docs/_data/site.json`: `statsLastVerified` to the verification date, after running `node -e "import('./plugins/soleur/docs/_data/stats.js').then(m=>console.log(m.default()))"` and comparing against the rendered homepage.
9. `plugins/soleur/docs/css/style.css`: hero plan line, hosted label, privacy-line contrast (scope `--color-text-secondary` to `.hero-waitlist-form .newsletter-privacy` so `/pricing/` is unchanged, at least 4.5:1), `.hero-cta` wrap/column at 768px scoped to `.landing-hero .hero-cta`, `.landing-quote` paragraph styles, `scroll-margin-top`.
10. `plugins/soleur/docs/scripts/screenshot-gate.mjs`: add two inline-CSS-only assertions for `/` (the privacy line sits below the submit button; no horizontal overflow at 390px). The gate has one global viewport from the routes file and no per-route override, so the 390px check needs a second browser context in the gate code, not just a routes-file edit.
11. Bump `last_updated` and `date` frontmatter on the pages whose copy changes (`index.njk`, `pricing.njk`, `getting-started.njk`, `company-as-a-service.njk`); they drive the visible "Last updated" line, `dateModified` JSON-LD and sitemap `lastmod`.

### Phase 3 — Governing documents and the audit

1. `knowledge-base/marketing/brand-guide.md`, CMO wording: under `Numbers`, a dated note that pages opting in via `summaryCounts: computed` (the homepage only) may render computed `{{ stats.* }}` counts, while pricing, about, blog and static prose keep the floor, plus a remark that the line-490 "60+ agents" stats line now differs from the homepage count; at the line-491 rule keep the original rule and first sentence and append a dated note scoped to the homepage hero only, with the test start date, the review date and the revert triggers (waitlist rate, alpha-cohort recruitment mix, developer-register drift), stating that it does not license "install", "CLI" or "terminal" wording and that new landing pages remain bound by the rule. Do not quote an exact agent count in the amendment: `marketing-content-drift.test.ts` Test 1 sweeps `knowledge-base/marketing/**` and rejects literal stale counts such as "67 agents".
2. `knowledge-base/product/roadmap.md`: add the evaluation row under Phase 4 (CPO) pointing at the evaluation issue.
3. Commit `knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md` with its body unchanged now; at DISCHARGED the CLO gate edits only its frontmatter (`status` to SIGNED-OFF plus a pointer key to the counsel-review audit). Merge is blocked until that verdict, so `Closes #9580` cannot fire early.

### Phase 4 — Verify

`npm run docs:build` (with `SOLEUR_DOCS_OFFLINE=1`), `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`, `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`, `validate-csp.sh _site`, `node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs`, `node plugins/soleur/docs/scripts/check-stylesheet-swap.mjs`, `node plugins/soleur/docs/scripts/screenshot-gate.mjs` against a local server on 8888 (inline-only state, desktop and 390px), Playwright screenshots at 1440, 768, 390 and 320 with the full stylesheet (absolute paths), the contrast check, and the repo-wide grep sweep in the acceptance criteria.

### Phase 5 — Sign-off, follow-ups and PR

Freeze all copy first (after Phase 0 step 3), then submit the diff and a before/after table of every changed string (including the JSON-LD twins) to `soleur:legal:clo` via the ship Phase 5.5 counsel-review gate; the CLO writes `knowledge-base/legal/audits/2026-10-counsel-review-9579.md` in the house style and the #9580 audit's `status` flips only on DISCHARGED. File the follow-up issues listed under Deferrals. PR body: `Closes #9579`, `Closes #9580` (safe: merge waits for DISCHARGED), a Legal section citing both audits, a one-line milestone note (both issues sit in Post-MVP / Later while the evaluation issue #9588 is in Phase 4), and a `## Changelog` section.

## Deferrals (tracking issues to file before ship)

| Deferred | Why | Re-evaluation | Milestone |
|---|---|---|---|
| Evaluate the hero CTA rollout (metrics, window, decision rule, bundle caveat) — #9588 | Needs 14 to 28 days of data and a judgement call | Review date in the brand-guide carve-out; revert if waitlist rate falls over about 30 percent relative without matching install activity | Phase 4: Validate + Scale (CPO) |
| Amodei sources in 4 blog posts and 2 distribution files — #9589 | Dated content with its own sources; same unverified framing | After the homepage wording is accepted | Post-MVP / Later |
| Privacy Policy 4.6 should name the waitlist and 5.1 should say "your own credentials" — #9590 | `docs/legal/` edits pull in the mirror, SHA re-pin and five CI gates | CLO | Post-MVP / Later |
| Compare pages: `/compare/` hub, install/waitlist CTA block, `screenshot-gate-routes.json` entry — #9591 | New page and design work | After the CTA rollout verdict | Post-MVP / Later |
| Form states: distinct errors, focus after submit, visible hero honeypot — #9592 | Pre-existing, shared by three forms | Next docs-site pass | Post-MVP / Later |
| Brand-guide overclaims noticed by the copywriter ("hand off 8 of 9 hats", "running autonomously", "catches what humans miss", CLI-flavoured Ship card) — #9593 | Outside the six items | Next homepage copy pass | Post-MVP / Later |

Related, acknowledged without folding in: #9500 (model-support claim differs per page) shares the Claude-specific hero wording; this PR keeps its wording consistent with "runs inside Claude Code" and does not decide #9500.

## Open Code-Review Overlap

Checked every planned file path against open `code-review` issues. None names any of them. #2965 (build-time critical-CSS extractor) mentions the docs directory generally. Acknowledge: this PR touches the hand-inlined critical CSS but does not replace the mechanism; #2965 stays open.

## Technical Considerations

- **Critical CSS and CSP are the two traps.** Hero selectors are inlined in `base.njk` and the inline scripts are sha256-pinned in the CSP meta tag; the gate that exists asserts only honeypot, h1 and one font, at 1440x900, so Phase 2 step 10 extends it. Without `flex-basis:100%` inlined the visible privacy `<p>` sits in the button row until the stylesheet swaps.
- **Accessibility.** `--color-text-tertiary` (#737373) on #0A0A0A is about 4.17:1 at 12px, below 4.5:1; the privacy line is now load-bearing so it moves to `--color-text-secondary`. Tab order: install CTA, email, submit, Privacy Policy link, compare link; DOM order equals visual order at both widths. The two plan sentences are separate elements so assistive tech announces which path each describes.
- **Parity.** Every FAQ edit is made twice (visible `<details>` and JSON-LD) on `/`, `/pricing/` and `/getting-started/`. Tests #2707 and #3171 compare only question names and counts, not answer text, so Guard 1's forbidden-pattern scan over both copies plus its key-phrase parity assertion carry the answer-text check.
- **Not touching:** `docs/legal/**` and its mirror (no legal-doc CI gate fires), `apps/web-platform/**`, blog posts, `vision.njk`, `about.njk`.
- **Observability, encryption posture and architecture gates** do not apply: no server, infra, store, connection or architectural decision changes. The only new telemetry is one aggregate cookieless Plausible event (covered by Privacy Policy 4.3 per CLO pre-review).

## Observability

The change is a static docs-site copy edit with one new aggregate telemetry event; there is no server, job or infra surface. The section exists because deepen-plan Phase 4.7 applies to any non-docs file list.

```yaml
liveness_signal:
  what: Plausible custom event "Hero Self-host Click" (class-tagged link) plus the unchanged "Waitlist Signup" event with location homepage-hero
  cadence: per visitor interaction
  alert_target: none (evaluation is a review of the Plausible dashboard figures pulled via the Stats API in the Phase 4 evaluation issue #9588)
  configured_in: plugins/soleur/docs/index.njk (link class) and the Plausible site goal list
error_reporting:
  destination: build-time gates (docs build, validate-csp.sh, validate-seo.sh, check-critical-css-coverage.mjs, screenshot-gate.mjs, the three drift guards) fail the PR; no runtime error path is added
  fail_loud: true
failure_modes:
  - mode: Plausible goal missing or class syntax unsupported by the site script, so clicks are never counted
    detection: post-merge Playwright click then Stats API breakdown by event:goal shows the event; the pre-merge local check in Phase 0 step 5
    alert_route: PR acceptance criterion, then the evaluation issue #9588
  - mode: inline script edited without recomputing the CSP hash, so the signup form JS is blocked in production
    detection: validate-csp.sh over the built site in CI (deploy-docs.yml and the Phase 2 inner loop)
    alert_route: CI failure on the PR
logs:
  where: Plausible dashboard (aggregate, cookieless) and CI logs
  retention: Plausible default retention; CI log retention per GitHub
discoverability_test:
  command: grep -c -e 'plausible-event-name=Hero+Self-host+Click' plugins/soleur/docs/index.njk
  expected_output: "1"
```

## Guard Contract

Three drift guards land in `plugins/soleur/test/seo-aeo-drift-guard.test.ts` in Phase 1, before the copy changes (one file: the build `beforeAll` and the `readSite` helper already live there). Their matrices are derived from the design, not from the finished copy, and were trimmed at plan review to the contract minimum plus the rows the review showed are feasible.

### Guard 1 — hosted-claims copy guard

**Property.** No built marketing page (visible text or JSON-LD) applies Claude-plan, Pro, Max, Claude-subscription or subscription-limit wording to anything except the self-hosted version, and no sentence about the hosted tier says "private" or "never see".

**Assembly.** Population: every built `index.html` under `_site/` except `blog/**` and `legal/**` (blog posts legitimately quote Cowork's Claude Pro price; legal docs have their own gates), plus `llms.txt`, each including its JSON-LD blocks, because a claim lives twice (visible `<details>` and its FAQPage twin). One extractor yields visible text and decoded JSON-LD text per page and splits sentences on punctuation AND at block-level tags (`summary`, `p`, `li`, `h1` to `h6`), so a heading without a final period never merges with its neighbour. Two case-insensitive (`/i`) rules run over every sentence: (a) INVERTED quantifier: a sentence matching `Claude (plan|Pro|Max|subscription)|Pro,? (or )?Max|subscription limits` fails unless it also matches `self-host`; this catches sentences that never say "hosted" (today's `pricing.njk` claude note and "You choose the Claude plan" sentence); (b) a sentence matching `(?<!self-)\b(hosted|cloud platform|managed)\b` must not match `\bprivate\b|never (see|leaves)`. "Soleur subscription" (the $49 product price) is outside the forbidden set. Floors: pages scanned is at least 15 and sentences matching rule (b)'s host alternation is at least 5. A calibration run over the current build (planning measured it: case-insensitive, no false positives on current pages) fixes the floors. Edited FAQ answers also get a key-phrase parity assertion (the distinctive new phrase appears in both the visible answer and its decoded JSON-LD twin), because tests #2707 and #3171 compare only question names and counts, not answer text.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore "Hosted plan users pay ... their own Claude Pro, Max, or API costs" (capital H) in the visible `/pricing/` FAQ answer | RED |
| 2 | Restore the same string only in the `/pricing/` FAQPage JSON-LD twin | RED |
| 3 | Add a second sentence "You choose the Claude plan that fits your usage" (no "hosted" in it) after a compliant first | RED |
| 4 | Point the page glob at an empty directory | RED (floor on pages scanned) |
| 5 | Suite edit: replace the sentence scanner with `return []` | RED (floor on host-alternation sentences) |
| 6 | Must-PASS, not the canonical: "Self-hosted runs with your Claude plan or an Anthropic API key." beside a compliant hosted sentence | PASS |

**Anchor.** No stored value is compared; the forbidden-pattern list is the contract, and the Phase 5 CLO sign-off is the independent review any weakening would also need.

### Guard 2 — computed-counts guard (re-pin of Test 16, #3165)

**Property.** Homepage prose counts equal what `stats.js` computes and no template carries a hard-coded literal exact count in prose; pricing and about keep the soft floor.

**Assembly.** (a) RAW source of `index.njk` and `page-freshness.njk` (not stripped of template tags, which would also hide the JSON-LD string concat and the `{% set _summary %}` strings): fail on `\b\d{2,3}\+?\s+(AI )?(agents|skills)` on any line that does not contain `stats.`; the `60+` soft floor is also a literal now banned in these two files' homepage branch. (b) Built `_site/index.html` hero-sub, FAQ answer, final CTA and FAQPage JSON-LD answer, compared with the default export of `docs/_data/stats.js` imported once in the test. (c) Cascade: built `pricing`, `about`, `vision`, `agents`, `skills` and `getting-started` pages (all include the freshness block) keep the soft floor and contain no `\d+ AI agents` phrase. Test 16's `PROSE_PAGES` loses its `index.html` entry (the homepage moves to (b)); the soft-floor loop keeps pricing and about.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hard-code "67 AI agents" in `index.njk` hero-sub | RED (raw-source scan) |
| 2 | Hard-code "103 skills" inside the `{% set _summary %}` string of `page-freshness.njk` | RED (the stripped-source design would have missed this) |
| 3 | Revert only the JSON-LD string concat to "60+ AI agents" after hero and FAQ are compliant | RED |
| 4 | Leave the final CTA line at "60+ agents" after the other three are compliant | RED |
| 5 | Set `summaryCounts: computed` on `/pricing/`, `/about/` or `/vision/` (cascade) | RED (each page pinned to the floor) |
| 6 | Make the stats import resolve to an empty object | RED (expected counts must be positive integers) |
| 7 | Suite edit: delete the raw-source scan | RED (floor on templates scanned) |
| 8 | Must-PASS, not the canonical: built homepage numbers equal the `stats.js` output with no source change | PASS |

**Anchor.** No stored value is compared (counts are recomputed from the filesystem each run), so a weakened floor cannot pass by editing a stored number.

### Guard 3 — attribution guard

**Property.** No built page makes a structured-data claim that Soleur is the subject of Inc.com coverage, and the homepage and `company-as-a-service` page do not carry the unverified quotation or the "As seen in" framing.

**Assembly.** Two populations, not one: (a) ALL built pages for the JSON-LD `subjectOf` check (the Organization block is emitted by `base.njk` only when `page.url == "/"`, so a fixture page is used to prove the loop reaches every page the template can render); (b) `_site/index.html` and `_site/company-as-a-service/index.html` only for the text checks ("As seen in", "next couple of years", "predicted in an interview with Inc.com"), because four blog posts and two distribution files still carry the same framing until #9589 and must not redden the suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add the `subjectOf` NewsArticle block to the Organization JSON-LD | RED |
| 2 | Re-add "As seen in" to the homepage | RED |
| 3 | Re-add "next couple of years" in the final CTA after the quote section is compliant | RED |
| 4 | Point the page iteration at an empty list | RED (floor on pages scanned) |
| 5 | Suite edit: check only `/` for `subjectOf` | RED (fixture page carrying `subjectOf` is flagged) |
| 6 | Must-PASS, not the canonical: the Inc. URL as a plain source link beside the past-tense paraphrase | PASS |

**Anchor.** No stored value is compared.

## User-Brand Impact

- **If this lands broken, the user experiences:** a homepage or pricing page that tells a visitor their Claude Pro or Max plan funds the hosted product (it takes an Anthropic API key), or a privacy line that promises something the Privacy Policy does not, or an attributed quote Anthropic's CEO never said sitting above a product pitch.
- **If this leaks, the user's data is exposed via:** no new data path; the exposure is an over-claim, for example "private" or "we never see your data" on a hosted tier whose workspace content lives on Jikigai infrastructure, which a visitor would rely on when deciding what to type into it.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one visitor relying on a false credential or privacy claim, or one screenshot of a fabricated CEO quote, is enough to damage trust and invite an Anthropic or regulator complaint; `aggregate pattern` would understate a legal-claim surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Surface \"runs on your Claude plan\" near the hero." [issue #9579] | Phase 2 step 1 (plan line), D6 | mapped |
| 2 | "Make the waitlist form's privacy text visible; it is currently `sr-only`." [issue #9579] | Phase 2 step 1, D5 | mapped |
| 3 | "Test self-host install as the primary CTA, keeping the waitlist for the hosted tier." [issue #9579] | Phase 0 steps 1 and 2, Phase 2 steps 1 and 9, D2, Deferrals row 1 | mapped |
| 4 | "Replace the hardcoded \"60+ agents\" in the hero and FAQ with the computed count (`stats.js` gives 67) and refresh `statsLastVerified` (2026-04-22)." [issue #9579] | Phase 2 steps 1, 2 and 8, D1, Guard 2 | mapped |
| 5 | "Verify the Dario Amodei attribution with the fact-checker before reuse; the only source is the Inc.com link." [issue #9579] | Phase 0 step 4, Phase 2 step 6, Guard 3 | mapped |
| 6 | "Link the hero to `/compare/` instead of the in-page anchor; add one Discord line after the FAQ." [issue #9579] | Phase 2 steps 1 and 7, D3 | mapped |
| 7 | "close #9580 in the same PR by landing its CLO audit" [brief] | Phase 3 step 3, Phase 5 | mapped |
| 8 | "plugins/soleur/docs/pages/pricing.njk currently says ... both are out of line and must be fixed in this PR." [brief] | Phase 2 step 3 | mapped |
| 9 | "Check the waitlist sr-only sentence against the Privacy Policy before making it visible." [brief] | D5, Research Reconciliation row 4 | mapped |
| 10 | "The finished items 1 to 3 wording must go back to the soleur:legal:clo agent for sign-off before merge" [brief] | Phase 5 | mapped |
| 11 | "brand-guide rules on competitor claims apply." [issue #9579] | D3 (competitor sentence), Phase 3 step 1 | mapped |
| 12 | "Do not start the homepage demo or the founder-defined acceptance check; they are separate issues." [brief] | none | descoped — justification: the brief excludes both; neither appears in any phase |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `index.njk` edits | "Surface \"runs on your Claude plan\" near the hero." (asks 1 to 6) | asked |
| `page-freshness.njk` `summaryCounts` flag | "Replace the hardcoded \"60+ agents\" in the hero and FAQ with the computed count" (ask 4) | inferred — justification: the shared summary renders "60+ AI agents" directly under the homepage hero and would contradict the new exact count; the flag keeps pricing and about on the floor their test pins |
| `site.json` `statsLastVerified` | "refresh `statsLastVerified` (2026-04-22)" (ask 4) | asked |
| `pricing.njk` edits | "both are out of line and must be fixed in this PR" (ask 8) | asked |
| `getting-started.njk` edits (byte/compute claims, prerequisite line, anchor margin, "cloud platform") | none | inferred — justification: CLO pre-review named the same defect class (claims that do not trace to the Privacy Policy or the audit) and the audit says existing out-of-line copy is fixed in this PR; the prerequisite line closes spec-flow gap G1 created by making install primary |
| `company-as-a-service.njk` line 136 | "Verify the Dario Amodei attribution ... before reuse" (ask 5) | asked |
| `base.njk` `subjectOf` removal | "Verify the Dario Amodei attribution ... before reuse" (ask 5) | inferred — justification: the fact-check CONTRADICTED the claim the block makes, and structured data is machine-quoted |
| `base.njk` footer non-affiliation (CLO kept it despite a simplicity cut proposal), success strings, CSP hash, critical CSS | none | inferred — justification: Anthropic naming rule (audit S3/S4, CLO pre-review); the visible "Double opt-in" line would contradict the old success text; the CSP and critical-CSS contracts (`cq-eleventy-critical-css-screenshot-gate`) fail the build otherwise |
| `style.css` edits | "make the waitlist form's privacy text visible" (ask 2) | inferred — justification: contrast and layout of the now-visible line; the inlined mirror contract needs the stylesheet rule too |
| `screenshot-gate.mjs` and `check-critical-css-coverage.mjs` | none | inferred — justification: the existing gate cannot see this change (spec-flow section 6), the coverage script never scans `index.njk`, and the rule requires both to pass |
| `seo-aeo-drift-guard.test.ts` guards and re-pins | "Replace the hardcoded \"60+ agents\"" (ask 4) and "Link the hero to `/compare/` instead of the in-page anchor" (ask 6) | inferred — justification: Test 16 currently pins the very strings the asks replace; leaving it red or silently weakened rots the contract |
| `brand-guide.md` amendments | "brand-guide rules on competitor claims apply." (ask 11) | inferred — justification: two asks (3 and 4) reverse existing brand-guide rules; amending the rule in the same PR keeps the guide from contradicting the site |
| `roadmap.md` row | none | inferred — justification: CPO advisory; the roadmap workflow gate requires a tracked row for the rollout evaluation |
| Audit commit | "landing its CLO audit" (ask 7) | asked |
| Deferral issues | "Re-evaluation criteria ... Take as one marketing PR." [issue #9579] | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for each item cut from the one PR |

### Split Assessment

- Subsystems touched: 2 — plugins/soleur (docs, test), knowledge-base
- Planned files: 14 | Estimated changed lines: 420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `plugins/soleur/docs/index.njk`
- `plugins/soleur/docs/_includes/page-freshness.njk`
- `plugins/soleur/docs/_includes/base.njk`
- `plugins/soleur/docs/_data/site.json`
- `plugins/soleur/docs/pages/pricing.njk`
- `plugins/soleur/docs/pages/getting-started.njk`
- `plugins/soleur/docs/pages/company-as-a-service.njk`
- `plugins/soleur/docs/css/style.css`
- `plugins/soleur/docs/scripts/screenshot-gate.mjs`
- `plugins/soleur/docs/scripts/check-critical-css-coverage.mjs` (add `docs/index.njk` to `TEMPLATE_ROOTS`)
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts`
- `knowledge-base/marketing/brand-guide.md`
- `knowledge-base/product/roadmap.md`

## Files to Create

- `knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md` (already on disk, committed unchanged)
- `knowledge-base/legal/audits/2026-10-counsel-review-9579.md` (written by the CLO agent at the Phase 5 gate)
- `knowledge-base/product/design/marketing/homepage-hero-trust-9579.pen` and exported PNGs (produced at plan time)
- `knowledge-base/project/specs/feat-one-shot-9579-9580-homepage-copy-trust-fixes/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9579-9580-homepage-copy-trust-fixes/decision-challenges.md`

## Acceptance Criteria

### Pre-merge (PR)

- [x] Hero plan line is present as two separate elements; the self-hosted one may say "Claude plan or an Anthropic API key"; the hosted one says only "bring your own Anthropic API key, billed by Anthropic to you"; Guard 1 passes (`bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`).
- [x] The waitlist privacy `<p>` has no `sr-only` class on `/`, keeps its `id`, `aria-describedby` resolves to it, and its text is identical to the `/pricing/` line; every clause traces to Privacy Policy 4.6 (cited in the sign-off); contrast is at least 4.5:1.
- [x] The hero has exactly one install CTA (`btn-primary`, `/getting-started/#self-hosted`, tagged `plausible-event-name=Hero+Self-host+Click`), one hosted form with a visible label and a `btn-secondary` submit, and one compare link to `/compare/soleur-vs-cursor/`; at most two `btn-primary` above the fold (nav plus install); no leftover "Or self-host it free" link.
- [x] No hosted statement on any non-blog, non-legal page contains Claude plan, Pro, Max, subscription-limit, "private" or "never see" wording: `rg -n -i "Pro, Max|Claude Pro|Claude subscription|subscription limits|never see|never leaves|every byte|your compute|cloud platform" plugins/soleur/docs --glob '!blog/**' --glob '!pages/legal/**'` returns only reviewed intended wording.
- [x] `/pricing/` visible FAQ and FAQPage JSON-LD carry the same new answer text (Guard 1 key-phrase parity; tests #2707 and #3171 stay green but only cover question names and counts); the claude note and the "Is there a free option?" answer match the final strings.
- [x] Homepage hero-sub, "What is Soleur?" (HTML and JSON-LD), final CTA and the page-freshness summary show `{{ stats.agents }}` and `{{ stats.skills }}` values equal to the `stats.js` output; pricing and about still render the soft floor; Guard 2 passes; `statsLastVerified` equals the date the counts were checked.
- [x] No verbatim Amodei quotation marks, no "As seen in", no `subjectOf` block anywhere in built output; `company-as-a-service` says "said at Anthropic's Code with Claude conference (May 2025)"; the fact-checker re-verified the final quote block (verdict VERIFIED recorded in the PR); Guard 3 passes.
- [x] `rg -n -i "starts? fresh every session" plugins/soleur/docs/index.njk` returns nothing (section sentence, FAQ HTML and FAQ JSON-LD are three different strings); `LEAD` ("Cursor and Copilot help you write code. Soleur helps you run a company.") and `id="soleur-vs-copilots"` remain; Test 16 hero-link assertion is re-pinned to the new href.
- [x] A Discord line follows the FAQ list on `/` and uses `site.discord`.
- [x] Success state text follows D7 (confirming by email only if double opt-in was verified; "hosted version" either way); CSP hash recomputed last; `validate-csp.sh _site`, `validate-seo.sh _site`, `check-critical-css-coverage.mjs` (with `index.njk` in its `TEMPLATE_ROOTS`) and `check-stylesheet-swap.mjs` pass.
- [x] `node plugins/soleur/docs/scripts/screenshot-gate.mjs` passes, including the two new inline-only assertions on `/` (privacy line below the submit button; no horizontal overflow at 390px via a second browser context); each new above-the-fold selector is in the inline block and its "Selectors covered" comment, and the inline block stays under the gzipped size budget.
- [x] Screenshots at 1440, 768, 390 and 320 taken with absolute paths and attached to the PR; the `.pen` wireframe exists, is non-empty, and is referenced from this plan.
- [x] `brand-guide.md` carries the dated Numbers note and the dated, homepage-hero-only CTA-test note (test start date, review date, revert triggers, no licence for "install"/"CLI"/"terminal" wording, quotes no literal agent count); `marketing-content-drift.test.ts` stays green; `roadmap.md` has the Phase 4 row; `last_updated` and `date` are bumped on the four edited pages.
- [ ] The CLO audit is committed; `soleur:legal:clo` returned DISCHARGED on the final wording (path of `2026-10-counsel-review-9579.md` cited in the PR body); `key-rotation-form.tsx` and `ws-client.ts` are recorded as acknowledged, no change.
- [ ] Deferral issues filed (table above), the evaluation issue holds the baseline numbers, the metric definitions and the decision rule.
- [ ] PR body contains `Closes #9579`, `Closes #9580` and a `## Changelog` section; `semver:patch` label.

### Post-merge (operator-free verification)

- [ ] After deploy, one Playwright click on the homepage install button produces a `Hero Self-host Click` event visible via the Plausible Stats API (goal exists from Phase 0).
- [ ] `curl -s https://soleur.ai/ | rg -c "Get the self-hosted version"` prints 1 or more.

## Domain Review

**Domains relevant:** Marketing, Legal, Product

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Brand-trust PR, positioning unchanged. D1: approve, with the floor-to-10 alternative recorded as a decision challenge; D2: ship as a time-boxed measured test with a dated brand-guide carve-out, drop "free" from the button, state that the bundle (not the CTA alone) is measured, create the Plausible goal before merge, avoid new inline scripts because of the CSP hashes; D3: link the existing Cursor page, neutral link text; D4: approve in full, attribute "70 to 80 percent" to Inc., remove `subjectOf`. Gaps adopted: full-repo grep for the quote (done: 4 blog posts and 2 distribution files go to a follow-up), brand-guide amendments in this PR. Invoke copywriter and a light conversion-optimizer pass; seo-aeo-analyst not needed.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Plan-time pre-review only; final sign-off is the Phase 5 gate. Hero plan line OK as drafted. Privacy line needs "Sent through Buttondown" wording and "Double opt-in" only if verified (Phase 0 step 3). `/pricing/` privacy line ("We email you once...") and FAQ ("Self-hosted users bring their own API key", "choose the Claude plan") need changes; `/getting-started/` "every byte" and "your compute" claims need changes; remove the Organization `subjectOf` block; no verbatim quote; non-affiliation line site-wide in the footer; `key-rotation-form.tsx` and `ws-client.ts` acknowledged with no change; Privacy Policy 5.1 and 4.6 wording are a separate follow-up (no `docs/legal/` edit here, so no legal-doc CI gate fires). gdpr-gate: not required (existing email notice made visible, no schema, route or new processing).

### Product (CPO)

**Status:** reviewed
**Assessment:** Reversal of brand-guide line 491 is defensible because its premise has not occurred, but the alpha cohort needs at least 3 of 10 non-Claude-Code founders (today 0), so a self-host-primary hero may skew recruitment; keep the hosted block visible and labelled, keep the `Waitlist Signup` event and `homepage-waitlist` tag unchanged for baseline comparability, define metrics and the decision rule before merge, file the evaluation under Phase 4 with a roadmap row, reference #9500. The test is a time-boxed rollout, not an experiment.

### Product/UX Gate

**Tier:** blocking (mechanical override: `*.njk` files are in the Files to Edit list)
**Decision:** reviewed (pipeline: wireframes ready for async review at `knowledge-base/product/design/marketing/screenshots/`)
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead, soleur:marketing:copywriter
**Skipped specialists:** none (conversion-optimizer: folded into the CMO assessment, the CMO asked for a light pass at work time; seo-aeo-analyst: CMO declined)
**Pencil available:** yes (drove the headless CLI 0.3.8 directly; the repo MCP adapter silently saved empty documents and is out of step with that CLI, see Sharp Edges)

#### Findings

- Wireframe `homepage-hero-trust-9579.pen` (116 KB, non-empty) with frames A current, B proposed, C mobile 390px, D quote section, E FAQ-end community line, plus focus and aria annotation panels; PNGs 01 to 12 beside it. Referenced from D2 and the Files to Create list.
- Spec-flow adopted into the plan: prerequisite line for the install path (G1), anchor `scroll-margin-top` (G2), a single gold hero CTA (G3), success text consistent with double opt-in (G4), deliberate final-CTA asymmetry (G5), "Soleur plans don't include Claude usage" cost line (G6), the copy sweep (G7), neutral compare link (G8), `btn-secondary` selector widening and inline-CSS gate extension (sections 5 and 6), contrast and tab order. Deferred to a follow-up: distinct error states, focus after submit, visible hero honeypot (G10), compare-page CTA and gate route (G8), cost guidance link to Anthropic pricing (needs a verified URL).
- Copywriter final strings are adopted verbatim where quoted in this plan; it also flagged existing brand-guide overclaims outside the six items (deferred, one issue) and the "start fresh every session" competitor claim (fixed here, ask 11).

## Test Scenarios

- Given the built homepage, when the hero is read, then the plan line renders as two elements and the hosted one contains none of: Claude plan, Pro, Max, subscription limits, private, never see.
- Given `/pricing/`, when the FAQ "Do I pay for Claude separately?" is expanded and when the FAQPage JSON-LD is parsed, then both contain the same new answer and neither contains "Pro, Max".
- Given the homepage built with `stats.js` returning 67 agents and 103 skills, when hero-sub, FAQ and final CTA are read, then each carries those numbers; given an extra agent file and a rebuild, then the numbers follow (Guard 2 must-PASS).
- Given `/pricing/` and `/about/`, when built, then prose still shows the soft floor and contains no `\d+ AI agents` phrase.
- Given the built homepage, when searched, then it contains no "As seen in", no `subjectOf`, no "next couple of years", and a source link to the Inc. URL.
- Given a keyboard user on `/`, when tabbing from the top of the page content, then focus goes install CTA, email, submit, Privacy Policy link, compare link.
- Given 390x844 inline-CSS-only, when `/` loads, then `scrollWidth <= clientWidth` and the privacy `<p>` is below the submit button.
- Given JS disabled, when the hero form is submitted, then the browser posts to Buttondown (accepted behaviour) and the install CTA still works.
- Given a successful signup, when the response is ok, then the status reads "Check your inbox to confirm your spot" and Plausible `Waitlist Signup` still fires with `location=homepage-hero`.
- Browser verification (Playwright, absolute screenshot paths): `/`, `/pricing/`, `/getting-started/` at 1440, 768, 390, 320 with and without the stylesheet.
- Regression: tests #2707, #2708, #2808, #3171, #3168, #3996 (LEAD sentence and section id) stay green.

## Dependencies & Risks

- **gitleaks false positive on `.pen` files:** Pencil CLI 0.3.8 writes a session `fileToken` UUID that the commit-time scan flags (generic-api-key). Strip the key before staging; unstage first, because the hook scans the index before the command runs.
- **Pencil adapter drift** (found while producing the wireframe): `batch_design` through the repo adapter returns OK but saves an empty document with `@pencil.dev/cli` 0.3.8. Not fixed here; tracked in the Session Summary for compounding.
- **Inc.com blocks curl and WebFetch (403).** Fact-checks need Playwright; the Playwright MCP server failed to connect late in this session, so Phase 0 step 4 must verify it is reachable first.
- **Plausible goal creation may need an Enterprise Sites API key.** Fallback is Playwright on the dashboard; a login or 2FA gate is the only allowed hand-off.
- **Baseline traffic may be too low** for any inference; the evaluation issue says so rather than pretending otherwise.
- **Buttondown double opt-in unverifiable** (no key or setting access): ship the version of the privacy line without it and open the CLO follow-up.
- **Brand-guide reversals** (lines 81 and 491) are operator-directed; both are recorded as decision challenges and carry revert triggers.
- **Counts cascade:** setting `summaryCounts` on any page other than `/` breaks pricing/about pins; Guard 2 mutation 5 covers it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan declares `single-user incident`.
- `page-freshness.njk` is included by 7 pages; the `summaryCounts` flag is opt-in so only the homepage changes. Do not flip the default.
- The inline script in `base.njk` is CSP-hashed; any edit to it (including copy strings) needs the hash recomputed and `validate-csp.sh` green.
- `.newsletter-privacy` and `.sr-only` are not in the inlined critical CSS; the privacy line is now above the fold, so inline them or the layout shifts at stylesheet swap.
- JSON-LD twins: every visible FAQ edit has a second copy in a `<script type="application/ld+json">` block on the same page.
- Do not call the product a "plugin" or "tool" in public copy; "Self-hosted" contains "hosted", so any scan for hosted claims must exclude the `self-` prefix.
- Do not write "free" on the install button without the pay-your-own-Claude-usage line beside it.
- The sign-off wording must be resubmitted if any string changes after the CLO verdict.
- `knowledge-base/marketing/**` is swept by `marketing-content-drift.test.ts` Test 1 for stale literal counts: the brand-guide amendment must not quote an exact agent count.
- D5 and D7 share one gate (double opt-in verification); do not ship one without the other.
- The three drift guards live in one 1,900-line test file because the Eleventy build `beforeAll` and `readSite` helper are there; a second file would pay a second ~10s build.

## References & Research

- Audit: `knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md`; baseline `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`.
- Privacy Policy sections 4.1, 4.3, 4.6, 4.7, 5.1, 5.3 (`docs/legal/privacy-policy.md`).
- Brand guide: `knowledge-base/marketing/brand-guide.md` lines 81, 86, 99, 491.
- Tests: `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (Test 16, #2707, #3171, #3996).
- Prior art: PR #4757 (soft-floor counts, promoted comparison), PR #5068 (hero waitlist a11y), PR #9573 (Sutra analysis that deferred these items).
- Plausible custom-event goals: <https://plausible.io/docs/custom-event-goals> (class syntax `plausible-event-name=Name+With+Plus`; goal must exist first).
- Wireframes: `knowledge-base/product/design/marketing/homepage-hero-trust-9579.pen`.
- Issues: #9579, #9580, #9500 (related), #3165 (superseded in part), PR #9584 (draft).

## Addendum — 2026-10-06 (work and review; supersedes the wording quoted above where they differ)

Appended, not edited in place: the plan text above is the record of what was decided at plan time.

- **Phase 0 outcome.** Plausible baseline and goal creation are login-gated (the Stats and Sites APIs answer 402 for this plan, no login credentials exist in Doppler), and Buttondown double opt-in cannot be read through the API. Tracked in #9605. D5 and D7 therefore shipped their fallback: the privacy line has no "Double opt-in" sentence, and the success text reads "You are on the list. If a confirmation email arrives, open it to finish signing up. We will notify you when the hosted version is ready." (true whether or not confirmation is on).
- **Attribution wording shipped (supersedes D4 and Phase 2 step 6).** The fact-checker found the plan's draft overstated three points (the question asked, the answer, the month). Shipped: "Amodei was asked whether a billion-dollar company run by one person using AI could be built. He said it would certainly happen, as soon as 2026. Inc. reported that in a later press Q&A he slightly walked back that prediction, putting the chance at 70-80 percent." The "May 2025" month rests on the article date, not on a sentence in the article. Three sibling sentences were also corrected on the fact-check's advice: the Krieger sentence on `/company-as-a-service/` ("told Inc.com" was contradicted), `/vision/` and `/about/`.
- **Competitor sentences (D3).** The "starts fresh every session" sentences were deleted rather than replaced, because the surrounding text already states the knowledge-base point.
- **Review-driven changes beyond the plan:** the hosted JSON-LD offer is renamed and marked pre-order, `llms.txt` pricing/getting-started/positioning lines are aligned, `/company-as-a-service/` gains a frontmatter `date`, the hosted waitlist card has square corners (brand rule), and the guards were widened (Guard 1 reads blog pages, attributes and structured data and flags mixed hosted/self-hosted sentences; scanner moved to `test/lib/visible-text.ts`).
- **Not changed, deliberately:** `docs/legal/**` (the hero privacy line says "Soleur updates, including when hosted access opens"; Privacy Policy 4.6 names the newsletter and not the waitlist, so the counsel-review gate records that clause as a reading of 4.6, and #9590 tracks naming the waitlist); the duplicated self-hosted/hosted plan sentences (the CLO requires them separate); style.css rules mirrored in the inline critical CSS (the mirror contract).
- **User-Brand Impact, vectors added by review** (the section above did not name them): (1) the visitor's email entered into the hero form, against the visible privacy line and Privacy Policy 4.6; (2) the post-submit text, which must not promise a launch email the double-opt-in flow may never deliver; (3) a self-hosted visitor's own Claude plan bearing usage-limit risk for autonomous multi-agent runs, covered by the CLO audit's self-hosted carve-out and not restated on the install path.
