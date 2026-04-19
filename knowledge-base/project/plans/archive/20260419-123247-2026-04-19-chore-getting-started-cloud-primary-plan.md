# Plan: Getting Started — Cloud-Primary Rewrite (M5)

**Issue:** [#1446](https://github.com/jikig-ai/soleur/issues/1446)
**Milestone:** Pre-Phase 4 Marketing Gate (M5)
**Branch:** `feat-getting-started-cloud-primary`
**Worktree:** `.worktrees/feat-getting-started-cloud-primary/`
**Draft PR:** #2627
**Brainstorm:** [`2026-04-19-getting-started-cloud-primary-brainstorm.md`](../brainstorms/2026-04-19-getting-started-cloud-primary-brainstorm.md)
**Spec:** [`specs/feat-getting-started-cloud-primary/spec.md`](../specs/feat-getting-started-cloud-primary/spec.md)

## Overview

Final Pre-Phase 4 Marketing Gate item. Flip the Getting Started page so the cloud platform is the primary path and the open-source CLI is a secondary path on the same page. Add a sitewide "Reserve access" nav CTA and a "Hosted version (coming soon)" footer entry. Align with M1 (#1004 brand guide), M2 (#1129 homepage), and M11 (#1134 open-source differentiator).

This is a content + structural change to `plugins/soleur/docs/pages/getting-started.njk` plus targeted edits to `_data/site.json`, `_includes/base.njk`, `css/style.css`, and a small reorder in `pricing.njk` (see Research Reconciliation). No new pages, no new layouts, no data-model changes.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "Primary CTA links to existing `pricing/#waitlist` form — no pricing-page changes (Non-Goal)" | `<section id="waitlist">` on `pricing.njk:330` sits **after** the pricing cards and FAQ. Anchor-jumping from Getting Started lands users past a full screen of pricing content on mobile — breaks the intended funnel. | **Fold in a small reorder of `pricing.njk`:** move the `<section id="waitlist">` to appear before the pricing cards (`<section class="landing-section">` at L171). The form markup, action URL, and Buttondown integration stay untouched — only the section position moves. This stays within the spirit of the Non-Goal (no form/markup/integration change) while fixing the anchor-jump UX break. |
| "FAQ JSON-LD mirrors visible copy (TR2)" | Existing JSON-LD at `getting-started.njk:195-250` has a verified drift with the visible FAQ answer at L189 (Q6 trailing sentence `Both versions access the same …` missing from the JSON-LD). | Plan regenerates the **entire** JSON-LD block from the visible FAQ copy as the last implementation step, and adds a review checkpoint to diff the two before commit. |
| "`Shipping weekly` line links to `/changelog/`" (FR1) | `/changelog/` renders `{{ changelog.html | safe }}`pulled from GitHub releases (`_data/changelog.js` → `_data/github.js`). Recent releases have dates visible in the rendered HTML. | `/changelog/` is the right target — dated momentum signal confirmed. Keep FR1 as-is. Drop the "or `/vision/`" alternative from the spec. |
| "No inline waitlist form on Getting Started (D11)" | Index.njk already embeds an inline waitlist form (`hero-waitlist-form`) with Plausible event binding in `base.njk:229-246`. CSP whitelists `buttondown.com`. | No change. Stick with D11 — link to `pricing/#waitlist`. Analytics funnel split (homepage vs Getting Started) stays clean this way. |
| "Sitewide nav CTA button (FR4)" | Only two `.btn-*` variants exist; nav bar has no CTA slot today; `.btn-primary` padding is chunky (`var(--space-4) var(--space-6)`) for a small nav slot. | Add a `.btn-primary.btn--sm` modifier (or a targeted `.nav-cta` class) sized for the nav. Data model: add a `primaryCta` object to `site.json` and render it in `base.njk` after the `nav-links` `<ul>`. |

## Open Code-Review Overlap

| Open issue | Files touched | Disposition |
|---|---|---|
| [#2609](https://github.com/jikig-ai/soleur/issues/2609) — base.njk JSON-LD interpolations need `| dump` filter | `plugins/soleur/docs/_includes/base.njk` | **Acknowledge.** The nav CTA interpolation I'm adding is `{{ site.primaryCta.label }}` inside plain HTML attributes, not JSON-LD. The existing JSON-LD drift (e.g., Organization / WebSite blocks in `base.njk`) is a separate concern and out of scope for M5. The plan does NOT touch JSON-LD interpolations in `base.njk` and does NOT introduce new ones. #2609 remains open. |

No other open `code-review` scope-outs touch `getting-started.njk`, `_data/site.json`, `css/style.css`, or `pricing.njk`.

## Files to Edit

- `plugins/soleur/docs/pages/getting-started.njk` — full body rewrite (hero, "Run it yourself" section, FAQ, JSON-LD) + frontmatter description
- `plugins/soleur/docs/_data/site.json` — add `primaryCta` field; add "Hosted version (coming soon)" link to the Product footer column
- `plugins/soleur/docs/_includes/base.njk` — render `site.primaryCta` after the `<ul class="nav-links">` loop as a right-aligned accent button
- `plugins/soleur/docs/css/style.css` — add `.btn--sm` size modifier (or `.nav-cta` class) for the nav CTA button, verify hero dual-CTA reuses existing `.hero-cta > .cta-button + .cta-link` pattern
- `plugins/soleur/docs/pages/pricing.njk` — move the `<section id="waitlist">` block from L328+ to sit between the hero (L18) and the first `landing-section` (L21). No form/markup/action change.

## Files to Create

None.

## CLI Verification (docs-cli-verification gate)

Per rule `cq-docs-cli-verification` (hook-enforced by `docs-cli-verification.sh`), every `claude …` command that lands in the rewritten page must be verified. Commands on the page:

- `claude plugin marketplace add jikig-ai/soleur`
- `claude plugin install soleur`

Verification strategy (picks ONE per command):

1. Run `claude plugin --help` and `claude plugin marketplace --help` locally in the worktree; paste the relevant `subcommand` line into the implementation PR under a `## Research Insights` heading.
2. If the `claude` CLI is not installed in the worktree sandbox, annotate the code block with `<!-- verified: 2026-04-19 source: https://code.claude.com/docs/en/plugins -->` (canonical Anthropic docs URL for plugin installation).

The hook inspects the page at commit time and blocks if neither annotation nor an equivalent trusted source comment is present. Plan does NOT invent new CLI tokens.

## Implementation Phases

### Phase 1: Data + Scaffolding (low risk, ship first)

- [x] 1.1 Add `primaryCta` to `plugins/soleur/docs/_data/site.json`: `{ "label": "Reserve access", "url": "pricing/#waitlist", "ariaLabel": "Reserve access to the hosted Soleur platform" }`.
- [x] 1.2 Add the footer entry `{ "label": "Hosted version (coming soon)", "url": "pricing/#waitlist", "title": "Reserve access — opening in waves to a founding cohort" }` to the Product column of `footerColumns` (sits alongside existing Get Started / Pricing / Agents / Skills / Changelog entries; does NOT demote or remove CLI entries).
- [x] 1.3 Render the CTA in `_includes/base.njk` after the `{% for item in site.nav %}` loop, as a separate `<li class="nav-cta-slot">` with `<a href="{{ site.primaryCta.url }}" aria-label="{{ site.primaryCta.ariaLabel }}" class="btn btn-primary btn--sm">{{ site.primaryCta.label }}</a>`. Do NOT interpolate into JSON-LD; plain HTML attribute is safe.
- [x] 1.4 Add `.btn--sm` modifier to `css/style.css` near the existing `.btn-primary` rule — `padding: var(--space-2) var(--space-4); font-size: 0.875rem;` — so the nav slot fits without crowding. Verify the modifier does NOT regress any existing `.btn-primary` use site.
- [x] 1.5 Mobile breakpoint audit: at `max-width: 768px`, the hamburger drawer already absorbs `.nav-links` children. Ensure the new `.nav-cta-slot` renders inside the drawer (is a descendant of `.nav-links`) so it gets swept in for free. Verify at 1280/900/375px per the 2026-04-02 footer-layout learning class.

### Phase 2: Hero rewrite

- [x] 2.1 Rewrite the hero `<section class="page-hero">` block (currently `getting-started.njk:8-15`):
  - H1: `The AI that already knows your business.`
  - Subtitle: `Soleur remembers every decision, customer, and context — so your next prompt starts where the last one ended. Ship faster because the AI already caught up.`
- [x] 2.2 Replace the two-card `.path-cards` block (currently L18-48) with a single `.hero-cta` block that reuses the existing `index.njk` L28-31 pattern:
  - Primary: `<a href="pricing/#waitlist" class="cta-button">Reserve access</a>` with helper `<p class="cta-helper">Takes 30 seconds. We'll email when your spot opens.</p>` immediately below.
  - Secondary: `<a href="#self-hosted" class="cta-link">Run the open source version today →</a>`
- [x] 2.3 Add the founder-intro line as a sibling `<p class="hero-meta">` — `<a href="mailto:ops@jikigai.com?subject=Soleur%20founding%20cohort%20intro">Founding cohort — limited to 10. Book intro →</a>` followed by a visible fallback `<span class="hero-meta-fallback">(or email <code>ops@jikigai.com</code>)</span>`. The fallback serves users whose mail client is missing (spec-flow-analyzer flag).
- [x] 2.4 Add the proof-of-momentum line as a sibling `<p class="hero-meta">` — `<a href="changelog/">Shipping weekly →</a>`.
- [x] 2.5 Scarcity wording: use "Founding cohort — limited to 10" rather than "closing at 10" (removes the unverifiable live-count implication flagged by spec-flow-analyzer).
- [x] 2.6 Update frontmatter `description:` to `The AI that already knows your business. Soleur remembers every decision and customer so your team stops re-explaining context. Reserve access.` (150 chars, cloud-primary, no "plugin").

### Phase 3: "Run it yourself" section (condensed CLI)

- [x] 3.1 Rename the H2 from "Installation" to "Run it yourself" and the section label from "Self-Hosted" to `Open source. Install in Claude Code.` (subhead rendered as `<p class="section-subtitle">`). **Preserve `id="self-hosted"`** on the `<section>` — external deep-links rely on the anchor.
- [x] 3.2 Add a short intro paragraph before the install commands: `Prefer to run it yourself? Soleur is open source and works in Claude Code today. Install it in two commands, keep every byte of memory on your own machine, and upgrade to the hosted version whenever you're ready.`
- [x] 3.3 Keep the existing `claude plugin marketplace add` / `claude plugin install` code block verbatim. Add the CLI-verification annotation (`<!-- verified: 2026-04-19 source: https://code.claude.com/docs/en/plugins -->`) immediately above the `<pre>` block.
- [x] 3.4 Keep the "Existing project / Starting fresh" callout verbatim.
- [x] 3.5 Keep the "The Workflow" and "Commands" and "Example Workflows" subsections verbatim — no copy change; only the parent heading renames.
- [x] 3.6 Remove the duplicate `/soleur:go` entry under the "The Workflow" section (currently L70-74 redundant with L104-107 under "Commands"). Cleanup pass noticed during research.
- [x] 3.7 Keep `{{ stats.agents }}` / `{{ stats.skills }}` interpolations intact where they currently appear in section copy.

### Phase 4: FAQ rewrite

- [x] 4.1 Reorder FAQ items so the first FAQ leads with cloud: rewrite `What do I need to run Soleur?` answer to the copywriter draft: `Nothing to install. The hosted version runs in your browser once your access opens — bring a workspace and your team. Prefer to self-host? The open source version runs inside Claude Code on macOS, Linux, or Windows (WSL) and takes two commands to set up.`
- [x] 4.2 Insert a new FAQ item after that: `Why a waitlist?` with answer `We're onboarding a founding cohort of 10 teams by hand so every workflow lands right. Access opens in waves as the hosted infrastructure matures — we ship weekly and move people off the list as capacity grows. Want to skip the line? Run the open source version today.`
- [x] 4.3 Keep the existing "Does Soleur work on Windows, Linux, and macOS?" FAQ as-is (content still accurate).
- [x] 4.4 Update `How much does Soleur cost?` to lead with cloud pricing (`See the [pricing page](pricing/) for hosted plans — founder pricing starts at $49/month.`) then the CLI cost sentence. No change to the $49 figure — confirmed against `pricing.njk`.
- [x] 4.5 Update `What is the difference between the cloud platform and self-hosted?` to remove the word "plugin" — replace "the full platform" wording so it does not frame CLI as "the plugin".
- [x] 4.6 Regenerate the `<script type="application/ld+json">` block **verbatim from the updated visible FAQ copy**. Diff visible vs JSON-LD text-by-text before commit.

### Phase 5: `pricing.njk` waitlist reorder (folded in from Research Reconciliation)

- [x] 5.1 Move the `<section class="landing-cta" id="waitlist">…</section>` block (currently starts at `pricing.njk:330`) to sit between the page hero (ends L18) and the first `landing-section` "What You Replace" (L21). No form/markup/action changes — only section position.
- [x] 5.2 Verify the waitlist section's `<h2>` and surrounding copy still make sense at the top of the page. The heading `Your AI organization is ready.` works as a top-of-page hook. If the section was relying on context from preceding sections, rewrite the first line of copy.
- [x] 5.3 Check that the pricing FAQ answers still reference "join the waitlist" coherently after the section moved up.

### Phase 6: Build, lint, visual verification

- [x] 6.1 Run `npx markdownlint-cli2 --fix` on any changed `.md` files (plan + tasks). Skip `.njk` (not Markdown).
- [x] 6.2 Run Eleventy build from repo root: `cd /home/jean/git-repositories/jikig-ai/soleur && npm run build --workspace=plugins/soleur/docs` (or the equivalent — consult `package.json`). Build must succeed with zero warnings on the touched pages.
- [x] 6.3 Serve the built site locally and visit `/getting-started/`, `/pricing/`, `/`, and `/changelog/` at desktop (1280), tablet (900), and mobile (375) widths per the 2026-04-02 footer-layout learning. Verify:
  - Hero renders with visible primary + secondary CTA + founder-intro + momentum lines at all widths.
  - Nav "Reserve access" button is right-aligned on desktop, absorbed into the hamburger drawer on mobile, and does not overlap the hamburger toggle at 768px.
  - Footer "Hosted version (coming soon)" entry is visible under Product column on all widths.
  - `#self-hosted` anchor still scrolls to the "Run it yourself" section.
  - `pricing/#waitlist` scrolls to the reordered waitlist section above the pricing cards.
- [x] 6.4 FAQ JSON-LD validation — paste the rendered page into Google Rich Results Test (or the `/soleur:seo-aeo` skill) and confirm the FAQPage schema matches the visible FAQ.
- [x] 6.5 Visual diff the Index vs Getting Started hero — confirm they use the same `hero-cta` pattern and voice register.

### Phase 7: Commit, PR body, ready-for-review

- [ ] 7.1 Commit Phase 1 (data + nav scaffolding) as one commit: `chore(docs): add primaryCta nav button + hosted-version footer entry`.
- [ ] 7.2 Commit Phases 2-5 as one commit: `docs(marketing): rewrite Getting Started cloud-primary (closes #1446)`.
- [ ] 7.3 Push to `feat-getting-started-cloud-primary`.
- [ ] 7.4 Update PR #2627 body with the `## Changelog` section and summary of the cloud-primary flip. Body must contain `Closes #1446`.
- [ ] 7.5 Set semver label: `semver:patch` (docs/marketing-only change; no new agents, no new skills, no breaking change). Confirmed against plugin-AGENTS.md semver rules.
- [ ] 7.6 Run `/soleur:review` multi-agent review before marking ready — per AGENTS.md `rf-never-skip-qa-review-before-merging`. Fix any findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 7.7 Mark the PR ready, queue auto-merge via `gh pr merge 2627 --squash --auto`, poll until MERGED, then `cleanup-merged` per AGENTS.md `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- [ ] 7.8 Post-merge: update `knowledge-base/product/roadmap.md` Pre-Phase 4 Marketing Gate row M5 from `Not started` to `Done — #1446`. Verify `gh issue view 1446 --json state` is `CLOSED`.

## Acceptance Criteria

### Pre-merge (PR)

1. `/getting-started/` renders a cloud-primary hero with H1 "The AI that already knows your business.", dual CTA (primary "Reserve access" → `pricing/#waitlist`; secondary "Run the open source version today →" → `#self-hosted`), and the founder-intro + proof-of-momentum lines.
2. The founder-intro link opens the default mail client with the pre-filled subject AND the fallback `ops@jikigai.com` text is visible next to the link.
3. The "Run it yourself" section is present on the same page with `id="self-hosted"`, contains the two install commands with the `<!-- verified: 2026-04-19 source: … -->` annotation, and explicitly uses the words "open source".
4. The new "Why a waitlist?" FAQ entry is present; existing FAQs reordered to lead with cloud; FAQ JSON-LD matches the visible FAQ copy exactly (diff check passes).
5. Right-aligned "Reserve access" button appears in the site nav on every page sampled (`/`, `/getting-started/`, `/pricing/`, `/changelog/`, `/agents/`, `/blog/`) and is keyboard-accessible with a visible focus state.
6. Footer Product column contains "Hosted version (coming soon)" linking to `pricing/#waitlist`; existing "Get Started" entry still present.
7. The rewritten page source contains no occurrences of the word "plugin" outside (a) literal `claude plugin install` / `claude plugin marketplace add` commands and (b) the verification annotation URL. Verified via `grep -n plugin plugins/soleur/docs/pages/getting-started.njk`.
8. External deep-links to `getting-started/#self-hosted` still resolve — verified by visiting the anchor after build.
9. `pricing/#waitlist` anchor-jump lands above the pricing cards at all three viewport widths (1280/900/375).
10. Eleventy build succeeds with zero warnings; the existing docs-cli-verification hook does not reject the commit.

### Post-merge (operator)

1. Roadmap M5 row updated to `Done — #1446` and `Current State` section last_updated bumped to 2026-04-19.
2. Issue #1446 auto-closed by `Closes #1446` in the PR body.
3. Production `/getting-started/` renders the new hero within the normal Cloudflare cache window.
4. Google Rich Results test on the live URL returns zero FAQPage errors.

## Test Scenarios

| Scenario | Given | When | Then |
|---|---|---|---|
| Non-CC founder on desktop | A first-time visitor at 1280px lands on `/getting-started/` | They click "Reserve access" | Browser navigates to `pricing/#waitlist` and the waitlist form is visible without scrolling below the fold |
| Non-CC founder on mobile | A first-time visitor at 375px lands on `/getting-started/` | They click "Reserve access" | Browser navigates to `pricing/#waitlist` and the waitlist form is in the initial viewport (no pre-form pricing cards visible) |
| CC-native dev on desktop | A Claude Code user lands on `/getting-started/` | They click "Run the open source version today" | Page scrolls to the `#self-hosted` section with install commands visible |
| Founder intro — mail client available | A user with a default mail client clicks "Book intro" | Default mail opens with the pre-filled subject | — |
| Founder intro — no mail client | A user without a default mail client clicks "Book intro" | Fallback text `ops@jikigai.com` is visible next to the link | User can copy-paste the email address |
| Nav CTA sitewide | A user on any other page (`/blog/post-x`, `/pricing/`, etc.) | They look at the top-right of the nav | "Reserve access" accent button is visible and links to `pricing/#waitlist` |
| Keyboard navigation | A keyboard-only user lands on `/getting-started/` | They press Tab from the H1 | Focus order: Reserve access → secondary CTA → founder-intro → momentum link → nav CTA (if not already focused above) |
| Brand-voice regression | Any automated grep in CI | Running `grep -nE '\bplugin\b' plugins/soleur/docs/pages/getting-started.njk` | Only matches inside literal `claude plugin install` / `claude plugin marketplace add` commands AND the `<!-- verified: … -->` URL |
| FAQ JSON-LD mirror | A diff tool | Comparing visible FAQ text to JSON-LD text | Each FAQ item's visible answer matches the JSON-LD `acceptedAnswer.text` word-for-word (modulo HTML entity decoding) |

## Alternative Approaches Considered

| Approach | Pros | Cons | Disposition |
|---|---|---|---|
| Create a dedicated `/self-hosted/` page and make `/getting-started/` cloud-only | Cleanest split | Breaks existing `getting-started/#self-hosted` anchor; 2x page maintenance | **Rejected** in brainstorm Phase 2. Single-page keeps the OSS signal visible and avoids 404s. |
| Add an inline waitlist form on Getting Started (duplicate of the `pricing/#waitlist` form) | Higher conversion (no page navigation) | Analytics split, two forms to maintain, drift risk | **Rejected** in brainstorm D11. |
| Keep two equal cards, only reorder | Minimum change, lowest risk | Fails the brief — cloud is primary, not "first of two peers" | **Rejected**. |
| Open self-serve cloud signup and drop the waitlist entirely | Unlocks recruitment funnel immediately | Stripe live mode + multi-user readiness gates not passed yet (Phase 4 exit criteria) | **Rejected** — deferred to Phase 4 proper. |
| Replace the mailto with a Cal.com link in v1 | Lower friction than email for founder-intro | Cal.com account not provisioned yet | **Deferred** — tracked in spec follow-up table. v1 uses mailto with visible fallback address. |
| Copywriter A/B persona-split hero variants (CC-native vs tool-agnostic register) | Optimizes conversion per persona | Requires analytics plumbing; brainstorm deferred | **Deferred** — tracked in spec follow-up table. v1 uses the tool-agnostic register. |

## Deferred — Tracked Issues

Existing deferred items from the brainstorm/spec already live in the spec's "Deferred / Follow-up" table. No new deferrals introduced by the plan beyond:

- **Analytics event for hero dual-CTA split** — "Reserve access" vs "Run the open source version" click events. Not wired in v1. Track as a Post-MVP issue if not already covered by an analytics tracking umbrella issue.
- **Live count on the "Founding cohort — limited to 10" scarcity line** — v1 uses static copy. If the cohort fills, manual copy update. Defer as Post-MVP.
- **FAQ JSON-LD build-time lint** — spec-flow-analyzer flagged that TR2 (mirror FAQ JSON-LD to visible copy) has no automated guardrail. Defer as a separate docs-site tooling issue.

Pre-submission: confirm whether each of the three has an existing tracking issue; if not, file under milestone "Post-MVP / Later" with body linking back to this plan.

## Domain Review

**Domains relevant:** Marketing, Product (carried forward from brainstorm Domain Assessments)

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward + fresh copywriter invocation during plan)
**Assessment:** Cloud-primary aligns with M1 brand guide and M2 homepage. Lead with memory-first outcome rather than "cloud" as delivery mode. CTA labels "Reserve access" + "Run it yourself" heading preserve brand voice and the M11 OSS differentiator. Waitlist-as-primary risk is real but mitigated by the proof-of-momentum line and the founder-intro escape hatch.

**Brainstorm-recommended specialists:** copywriter (invoked during plan; v1 baseline copy produced for all hero/CTA/FAQ slots).

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward + fresh spec-flow-analyzer invocation during plan)
**Assessment:** 10-founder recruitment is a sales motion, not a marketing funnel. Plan adopts all three CPO recommendations: (1) dual hero CTA so CC-native devs see the working path immediately, (2) founder-intro mailto for the non-CC founder target, (3) "Hosted version (coming soon)" footer label that does not demote CLI. Spec-flow-analyzer flags (anchor-jump UX break, mailto fallback, scarcity wording, "or /vision/" ambiguity) folded into Phases 2 and 5.

**Brainstorm-recommended specialists:** ux-design-lead (deferred — no Pencil .pen file planned for this text/structural change; BLOCKING gate did not fire because this modifies an existing page without new interactive surfaces).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** spec-flow-analyzer, copywriter
**Skipped specialists:** ux-design-lead (advisory tier + no new components; brainstorm-recommended for wireframes but not required for content rewrite without new interactive surfaces)
**Pencil available:** N/A

#### Findings

Spec-flow-analyzer surfaced 12 flags across three personas. Five folded into the plan (mailto fallback, scarcity softening, `pricing.njk` reorder, stacking on mobile, `/changelog/` verified as dated). Three acknowledged as existing constraints or defensible choices ("Install in Claude Code" narrowing is accurate since Soleur IS a Claude Code plugin in implementation, not pretending otherwise; CC-dev nav-CTA nag has no low-cost dismissal mechanism in v1; Curious Browser return hook is covered by the existing footer newsletter). Three deferred to tracking issues (FAQ JSON-LD build-time lint, analytics CTA split, live-count on scarcity line).

## Research Insights

### Local conventions (from repo-research-analyst)

- `getting-started.njk` uses `base.njk` directly with `permalink: getting-started/` and handwritten FAQ JSON-LD at L195-250. Existing Q6 mismatch between visible L189 and JSON-LD L245 — drift risk confirmed.
- `base.njk:128-140` renders the nav as `<ul class="nav-links">` via `{% for item in site.nav %}`; right-aligned CTA belongs as an additional `<li>` after the loop so the hamburger drawer absorbs it on mobile.
- `site.json` has `nav` (8 entries) and `footerColumns` (Product, Resources). No `primaryCta` field today — plan adds it.
- Hero dual-CTA pattern already exists on `index.njk:28-31` using `.hero-cta > .cta-button + .cta-link`. Getting Started hero reuses this pattern for voice/CSS consistency.
- Only `.btn-primary` and `.btn-secondary` variants exist; nav slot needs a `.btn--sm` modifier or a dedicated `.nav-cta` class.
- CSP in `base.njk:28` already allow-lists `buttondown.com` for `connect-src` and `form-action`; no CSP change needed.
- Plausible events already wired: `'Waitlist Signup'` via `.waitlist-form` class (base.njk:229-246). Not relevant since Getting Started does NOT carry an inline form.
- No other pages inbound-link to `getting-started/#self-hosted` — anchor preservation is defensive, not rescuing a known link.
- `<!-- verified: YYYY-MM-DD ... -->` convention already in use at `_data/skills.js:11`. Extend to the rewritten page's CLI code block.

### Prior learnings (from learnings-researcher)

- `eleventy-v3-passthrough-and-nunjucks-gotchas.md` — Nunjucks does not interpolate `{{ }}` inside YAML frontmatter; `page.url` already has a leading slash. Relevant if frontmatter is updated.
- `2026-03-17-faq-section-nesting-consistency.md` — `landing-section` sits outside `<div class="container">`; preserve the DOM structure.
- `footer-layout-redesign-flex-children-visual-verification-20260402.md` — adding a new child to `.footer-inner` changes `justify-content: space-between`. Our change is inside an existing `<ul>`, NOT a new flex child of `.footer-inner` — safe.
- `2026-03-05-eleventy-blog-post-frontmatter-pattern.md` — inline FAQPage JSON-LD is OK; no layout-level emitter exists on this page.
- `2026-02-22-landing-page-grid-orphan-regression.md` — when a grid child count changes, audit all breakpoints (desktop, tablet 769-1024, mobile ≤768). We are REMOVING the two-card grid; verify no orphan layout behavior remains.
- `2026-03-15-eleventy-build-must-run-from-repo-root.md` — always run Eleventy from repo root; `_data/agents.js` uses CWD-relative `resolve(...)`.
- AGENTS.md `cq-docs-cli-verification` [hook-enforced] — the `claude plugin install` commands require the `<!-- verified: … -->` annotation or the commit is blocked.

## Risks

- **Scope drift into `pricing.njk`.** The waitlist section reorder is defensible but expands the file list. If a reviewer objects to touching `pricing.njk` at all, fall back to adding a second anchor `<span id="waitlist-top"></span>` above the pricing cards with a CSS `scroll-margin-top` adjustment — same UX outcome, zero functional change to the existing waitlist section.
- **CSP inline-script sha256 drift.** `base.njk:27,121,188` have inline `<script>` hashes that CSP enforces. The FAQ JSON-LD regeneration on `getting-started.njk` is NOT inline (it's `<script type="application/ld+json">` which CSP treats differently — data, not executable script) so no sha256 update needed. Confirmed by reading `base.njk` CSP block during research.
- **`.btn-primary` modifier collision.** Adding `.btn--sm` could overlap with existing utility classes. Mitigation — scope the selector as `.btn-primary.btn--sm` so it only applies when both are present.
- **Mobile hamburger drawer absorbing the nav CTA.** Expected behavior — the drawer is driven by `.nav-links` transform at `max-width: 768px`. If the CTA is a direct child of `.nav-links`, it's included. Verify visually at 375px.
- **`cq-docs-cli-verification` hook rejecting the commit.** If the `<!-- verified: … -->` annotation format is off, the hook rejects. Pre-emptive: run the hook locally before commit — `.claude/hooks/docs-cli-verification.sh` — and confirm exit 0.
- **FAQ JSON-LD visible-vs-structured drift surviving the rewrite.** Mitigation — the regeneration step is the LAST step of Phase 4 after all visible copy is final, and Phase 6.4 validates via Google Rich Results.

## Rollback Strategy

This is a pure documentation/marketing change. If a problem surfaces post-merge:

1. Revert the squash-merge commit on `main` via `git revert`.
2. `/getting-started/` returns to the current two-card state.
3. Nav CTA and footer entry disappear with the revert (all changes are in a single squash commit).
4. No data migration to roll back — `site.json` is static.
5. Cloudflare cache is the only asymmetry — manual cache purge on `/getting-started/` to speed up propagation after revert.

## Open Questions

None. All spec and brainstorm open questions resolved during this plan. Two items deferred with tracking commitments above.
