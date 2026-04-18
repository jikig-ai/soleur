# Drain marketing P0 audit backlog — closes #2551 + #2552 + #2553 + #2555

**Date:** 2026-04-18
**Branch:** `feat-one-shot-marketing-p0-audit-drain`
**Type:** chore (content + AEO/SEO drain)
**Closes:** #2551, #2552, #2553, #2555
**Parent audit issue:** #2549 (Scheduled Growth Audit 2026-04-18)

---

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Phase 1, Phase 2, Phase 3, Phase 4, Acceptance Criteria, Risks & Gotchas
**Research agents used:** WebSearch (FAQPage schema policy, Karpathy agentic-engineering attribution, Compound Engineering attribution), WebFetch (MCP spec canonical URL, Every.to canonical URLs, Claude Code docs canonical URL with redirect discovery), learnings sweep (9 relevant files from `knowledge-base/project/learnings/`).

### Key Improvements

1. **Claude Code docs URL moved in 2026.** `https://docs.anthropic.com/en/docs/claude-code` **301-redirects** to `https://code.claude.com/docs/en/overview`. Four pages on the Soleur site already link to the old URL (fine — 301 preserves link equity), but **new citations added by this PR must use the canonical URL** `https://code.claude.com/docs/en/overview`. Verified live via WebFetch.
2. **FAQPage rich-snippet eligibility is restricted (but AEO value stands).** Google's August 2023 policy — still active in 2026 — limits FAQ rich results in SERP to "well-known, authoritative government and health websites". Soleur.ai is NOT eligible for FAQ rich snippets in Google SERP. BUT the schema remains fully valuable for AI engines (ChatGPT, Perplexity, Claude, Google AI Overviews) — which is the AEO audit's actual target. Added clarification to the Acceptance Criteria: FAQPage schema is for AEO/LLM citation extraction, not Google rich-result chips.
3. **Karpathy "agentic engineering" citation — exact URL verified.** The New Stack's "Vibe Coding Is Passé" article cites `https://x.com/karpathy/status/2019137879310836075` as the post where Karpathy proposes "agentic engineering" as the successor to "vibe coding". Plan's original fallback URL (`status/1859305140188037221`) is from an older, unrelated Karpathy post — replaced with the verified Feb 2026 URL.
4. **MCP spec canonical URL pinned.** `https://modelcontextprotocol.io/specification` is live and authoritative; current spec schema version is `2025-11-25`. This is the URL to use for `/agents/` and `/getting-started/` citations.
5. **Compound Engineering citation verified.** Both `https://every.to/chain-of-thought/compound-engineering` (Kieran Klaassen solo essay) AND `https://every.to/source-code/compound-engineering-how-every-codes-with-agents` (Dan Shipper + Kieran Klaassen co-authored how-to) resolve. Use the `source-code` URL — more complete, explicitly attributed to both authors, and matches the "plan/work/review/compound" four-step lifecycle the `/skills/` page already mentions.
6. **"Plugin" banned-term has a dual-location trap.** `about.njk:47` uses "open-source Claude Code plugin" — pre-existing brand-guide miss. Do NOT propagate to new FAQ copy (Q4 explicitly uses "Claude Code extension" instead — confirmed in plan Phase 2). Note for future drain: this specific "plugin" usage should be remediated in a separate P1/P2 sweep; scope-fenced here.
7. **Citation-verification gate from #2563 applies.** The `2026-04-18-fabricated-cli-commands-in-docs.md` learning mandates verifying every cited URL before commit. All 4 new citation URLs for this PR have been verified live in this deepen pass (see Research Insights below for the verification log). Implementation should re-verify before ship, per `knowledge-base/project/learnings/2026-03-06-blog-citation-verification-before-publish.md`.

### New Considerations Discovered

- **Frontmatter coherence matters:** Per learning `2026-03-26-seo-meta-description-frontmatter-coherence.md`, when the H1 changes we must also confirm `title:` frontmatter is coherent. The plan already handles `seoTitle:` + `description:`, but the `title:` field on `index.njk` is just `Soleur` (line 2) — no change needed (brand lock), confirmed consistent.
- **Meta description character count must be verified programmatically.** The R2 replacement string is 218 characters — over the Google SERP display limit (~155–160 chars). This is intentional in the audit (longer meta feeds AEO extractors even if Google truncates in SERP). Document the trade-off in the PR body: R2 is chosen for AEO extractability, not SERP character-count optimization.
- **Eleventy build must run from repo root** (learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`). The plan's Phase 4 already says `cd <worktree-root> && npm run docs:build` — correct. Do NOT run from `plugins/soleur/docs/`.
- **FAQ insertion point consistency** (learning `2026-03-17-faq-section-nesting-consistency.md`). The new `/about/` FAQ block must sit **outside** any `<div class="container">` wrapper to match the pattern established by `index.njk`, `agents.njk`, `skills.njk`. Plan Phase 2 currently says "before the closing `</div>` of the `.container` wrapper" — **correcting to: after the closing `</div>` of `.container`, outside any wrapper**. See Research Insights §Phase 2 below for the precise placement update.
- **Brand-violation cascade risk** (learning `2026-02-21-marketing-audit-brand-violation-cascade.md`). Fixing a brand phrase in one file often surfaces the same phrase in 10+ others. For this PR: **scope-fence holds** (only 5 files, all prescribed). Do NOT grep the repo for "Company-as-a-Service" and start swapping everywhere — that's a separate cascade PR that would explode the blast radius.
- **Directional ambiguity absent for this PR.** Learning `2026-03-17-planning-direction-confirmation-required.md` warns about A→B vs B→A confusion. Here: the direction is unambiguous — audit R-rows map 1:1 to template edits. No confirmation gate needed.
- **Tasks.md date prescription was correct.** `tasks.md` references `2026-04-18-chore-marketing-p0-audit-drain-2551-2552-2553-2555-plan.md` by name. Plan-skill sharp-edge says "don't prescribe exact learning filenames with dates" — applies to **learnings**, not **plans**. Plans can (and do) have dated filenames.

---

## Overview

Drain four P0 findings from the 2026-04-18 content + AEO audits into a single focused marketing-page refactor PR. All four issues land on the same Eleventy marketing site (`plugins/soleur/docs/` — **not** `apps/soleur-ai/` as the issue bodies say; see Research Reconciliation below) and they naturally cluster: three content edits on `index.njk`, one content + structured-data addition on `about.njk`, and one citation sweep across three catalog pages (`agents.njk`, `skills.njk`, `getting-started.njk`).

Pattern borrowed from PR #2486: one cleanup PR, multiple closures on the same code area, net-negative on the backlog.

No net-new copy is invented. The 2026-04-18 content audit (`R1`, `R2`, `R3`) and AEO audit (`P0-1`, `P0-3`) contain the verbatim replacement strings — quoted here and carried verbatim into the edit.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue bodies + `/soleur:one-shot` invocation) | Reality (worktree inspection) | Plan response |
|---|---|---|
| Marketing site lives at `apps/soleur-ai/` with `index.njk` / `about.njk` / etc. | `apps/soleur-ai/` **does not exist**. Only `apps/telegram-bridge` and `apps/web-platform`. | Use the real path. Eleventy `input` in `/eleventy.config.js` is `plugins/soleur/docs`. Homepage is `plugins/soleur/docs/index.njk`. Nav pages live under `plugins/soleur/docs/pages/*.njk`. The 2026-04-18 content audit itself uses the correct paths (lines 266–278 cite `plugins/soleur/docs/index.njk`, `plugins/soleur/docs/pages/*.njk`). |
| `apps/soleur-ai/src/index.njk` or `apps/soleur-ai/index.njk` for homepage. | Homepage is `plugins/soleur/docs/index.njk` (no `src/`). Frontmatter is inline — no separate data file. | Edit the template directly; both H1/tagline (body) and `seoTitle` + `description` (frontmatter) live in the same file. |
| `apps/soleur-ai/src/about.njk` for About. | Path is `plugins/soleur/docs/pages/about.njk`. | Use the real path. Append FAQ block + FAQPage JSON-LD before `</script>` of the existing ProfilePage schema; or add a second `<script type="application/ld+json">` block (the existing pattern on `index.njk` and `agents.njk` uses a dedicated FAQPage `<script>` block). |
| `/agents/`, `/skills/`, `/getting-started/` templates under `apps/soleur-ai/`. | Paths are `plugins/soleur/docs/pages/{agents,skills,getting-started}.njk`. | Use the real paths. |
| `/blog/` and `/changelog/` index pages are "hand-authored." | Both exist at `plugins/soleur/docs/pages/{blog,changelog}.njk` but the issue text says "if they are hand-authored rather than generated" — they are data-driven (render collections), and the P0 AEO finding names only `/agents/`, `/skills/`, `/getting-started/` as the must-cite set. | **Scope fence:** cite `/agents/`, `/skills/`, `/getting-started/` only. Blog/changelog citation density is a P1/P2 concern not called out in P0-3. |
| Issue #2553 says "Match the JSON-LD pattern already used on other core pages." | `index.njk` has a dedicated `<script type="application/ld+json">` FAQPage block alongside the rendered `<details>` list. `agents.njk` / `skills.njk` follow the same pattern. `about.njk` currently ships `ProfilePage` + nested `Person` only; no FAQ UI, no FAQPage schema. | Reuse the existing pattern: add a `<details>`-based FAQ section + a separate `<script type="application/ld+json">` block for the FAQPage. Do NOT merge FAQPage into the ProfilePage `@graph`; matching the site's actual pattern is preferred. |

**Why this reconciliation exists:** the `/soleur:one-shot` invocation and issue bodies propagated a factually wrong directory (`apps/soleur-ai/`) that has never existed. The content audit file (the single source of truth the P0 rows cite) has the correct paths. Implementing from issue bodies verbatim would fail at the first `ls`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned 0 issues. No scope-outs touch `plugins/soleur/docs/index.njk`, `pages/about.njk`, `pages/agents.njk`, `pages/skills.njk`, or `pages/getting-started.njk`.

## Files to edit

1. `plugins/soleur/docs/index.njk` — swap frontmatter `seoTitle` + `description` (closes #2552) and H1 + tagline (closes #2551).
2. `plugins/soleur/docs/pages/about.njk` — append FAQ `<details>` block + FAQPage JSON-LD `<script>` (closes #2553).
3. `plugins/soleur/docs/pages/agents.njk` — add 2 inline external citations to the intro prose (closes part of #2555).
4. `plugins/soleur/docs/pages/skills.njk` — add 2 inline external citations; one Anthropic/Claude-Code and one Karpathy/agentic-framing citation are already present on line 19 — check coverage, add 1–2 more per the audit and confirm count meets ≥2 requirement (closes part of #2555).
5. `plugins/soleur/docs/pages/getting-started.njk` — add 2 inline external citations to the intro / self-hosted sections (Claude Code install docs, MCP spec) (closes part of #2555).

## Files to create

None.

## Implementation Phases

### Phase 1 — Homepage frontmatter + hero (closes #2551, #2552)

**File:** `plugins/soleur/docs/index.njk`

Current frontmatter (lines 3–4):

```njk
seoTitle: "Soleur — Company-as-a-Service Platform for Solo Founders"
description: "Soleur is the open-source company-as-a-service platform for solo founders and solopreneurs — AI agents across engineering, marketing, legal, finance, and every business department."
```

Replacement (verbatim from 2026-04-18 content audit §R1 + §R2):

```njk
seoTitle: "Soleur — AI Agents for Solo Founders | Every Department, One Platform"
description: "Stop hiring, start delegating. Soleur deploys 60+ AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop. Your expertise, amplified."
```

Current hero (lines 11–12):

```html
<h1>The Company-as-a-Service Platform for Solo Founders</h1>
<p class="hero-tagline">Build a Billion-Dollar Company. Alone.</p>
```

Replacement (verbatim from 2026-04-18 content audit §R3):

```html
<h1>Stop hiring. Start delegating.</h1>
<p class="hero-tagline">The Company-as-a-Service platform for solo founders. Build a billion-dollar company — alone.</p>
```

**Gotchas:**

- The `.landing-cta` at line 248 already has a `<h2>Stop hiring. Start delegating.</h2>` footer CTA. After this edit the same phrase appears in both H1 and H2 — acceptable per brand guide (reinforcement), but confirm the two do not collide visually. If the H2 CTA becomes redundant, a sibling edit can simplify it to a different brand-guide-approved line ("See Pricing & Join Waitlist" is already the CTA button). **Decision: leave the footer H2 alone** — reinforcement is on-brand; changing it is scope creep.
- The hero subhead (line 13, opens with "Soleur is an open-source company-as-a-service platform...") is a canonical product-definition sentence flagged as the single biggest AEO win in the AEO audit (§6 Summary Quality improvements). Do NOT touch it.
- The `hero-trust` line ("Human-in-the-loop. Your expertise, amplified.") is already the exact phrase the audit's §R2 meta description references — keep it.

### Phase 2 — /about/ FAQ + FAQPage JSON-LD (closes #2553)

**File:** `plugins/soleur/docs/pages/about.njk`

Add a new `<section>` **outside** the `<div class="container">` wrapper (after the closing `</div>` of `.container`, before the final `</section>` or `</div>` of the document) — this matches the pattern established by `index.njk`, `agents.njk`, and `skills.njk` where the FAQ `landing-section` is a full-viewport-width sibling to the constrained `.container`. See research insight below and learning `2026-03-17-faq-section-nesting-consistency.md`. Add a second `<script type="application/ld+json">` block after the existing ProfilePage script for the FAQPage — the site's established pattern is two siblings, not a `@graph` merge (confirmed against `index.njk` lines 181–244 and `agents.njk` lines 107–154).

**Questions and verbatim-on-brand answers** (per brand guide: declarative, no hedging, trust scaffolding, no banned words — "AI-powered", "leverage", "just", "simply", "assistant", "copilot", "plugin" banned in public copy except literal CLI commands):

1. **Who founded Soleur?**
   > Jean Deruelle founded Soleur. He is a software engineer with 15+ years of experience building distributed systems and developer tools across Java, Ruby, Go, and TypeScript ecosystems. He founded Soleur in early 2026 to solve the problem he faced as a solo founder: running eight departments with the time and budget for none of them.

2. **When was Soleur founded?**
   > Soleur was founded in early 2026. The platform launched as an open-source Claude Code extension and has grown to 60+ AI agents across 8 business departments.

3. **What does Soleur do?**
   > Soleur deploys AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving a single founder the operational capacity of a full organization. Every agent shares a compounding knowledge base, so your marketing agent knows what your legal agent decided. Your expertise stays in the loop: agents provide drafts, you make the final call.

4. **Is Soleur open source?**
   > Yes. The self-hosted version of Soleur is open source under Apache 2.0, with every agent and workflow publicly inspectable on GitHub. The cloud platform (in development) layers managed infrastructure and a web dashboard on the same open core.

5. **What is MCP?**
   > MCP stands for Model Context Protocol — Anthropic's open standard for connecting AI models to external tools, data sources, and services. Soleur is built on Claude Code and MCP, so every agent can reach the same tool ecosystem the broader Claude Code community relies on.

**Rendered HTML pattern** (matching `index.njk` FAQ block style, lines 143–179):

```html
<section class="landing-section">
  <div class="landing-section-inner">
    <p class="section-label">Common Questions</p>
    <h2 class="section-title">Frequently Asked Questions</h2>
    <div class="faq-list">
      <details class="faq-item">
        <summary class="faq-question">Who founded Soleur?</summary>
        <p class="faq-answer">…answer 1…</p>
      </details>
      <!-- repeat for Q2–Q5 -->
    </div>
  </div>
</section>
```

**JSON-LD pattern** (matching `index.njk` lines 181–244 and `agents.njk` 107–154):

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    { "@type": "Question", "name": "Who founded Soleur?", "acceptedAnswer": { "@type": "Answer", "text": "…answer 1…" } },
    { "@type": "Question", "name": "When was Soleur founded?", "acceptedAnswer": { "@type": "Answer", "text": "…answer 2…" } },
    { "@type": "Question", "name": "What does Soleur do?", "acceptedAnswer": { "@type": "Answer", "text": "…answer 3…" } },
    { "@type": "Question", "name": "Is Soleur open source?", "acceptedAnswer": { "@type": "Answer", "text": "…answer 4…" } },
    { "@type": "Question", "name": "What is MCP?", "acceptedAnswer": { "@type": "Answer", "text": "…answer 5…" } }
  ]
}
</script>
```

**Placement:** after the closing `</script>` of the existing ProfilePage block (line 79) so the two schema blocks are siblings, matching the site pattern. The FAQ `<details>` HTML goes inside the `.container` so it renders visually below "About Soleur" but above the document boundary.

**Voice compliance check before commit:**

- No "AI-powered", "leverage", "just", "simply", "assistant", "copilot", "plugin" in the answers (exception: "Claude Code extension" in Q2 — "extension" is an acceptable substitute per brand guide; "plugin" is banned in public copy). Confirmed on all five drafts above.
- Trust scaffolding present: Q3 includes "Your expertise stays in the loop".
- Concrete numbers: Q1 (15+ years), Q2 (60+ agents, 8 departments), Q3 (8 departments).
- No hedging: every answer is declarative.

### Phase 3 — External citations on core pages (closes #2555)

The audit §P0-3 requires ≥2 external citations per page on `/agents/`, `/skills/`, `/getting-started/`. Audit its current state against source and close the gap.

#### 3a. `/agents/` (`plugins/soleur/docs/pages/agents.njk`)

Current external citations on the page: **0**. Intro prose (lines 19–23) has the claim "Agentic engineering treats AI agents as specialist team members" with no citation, and "60+ open source AI agents" with no citation.

Audit §P0-3 action: `Agents → cite Anthropic / MCP spec / Karpathy on agent systems`.

Add two inline citations inside the existing prose block (lines 19–23) — no new section:

- Link "Agentic engineering treats AI agents as specialist team members, not generic" → cite [Karpathy introducing agentic engineering](https://x.com/karpathy/status/2019137879310836075) (verified via The New Stack "Vibe Coding Is Passé" article as the canonical Karpathy post on the shift from vibe coding to agentic engineering). Verify live at implementation time — if X/Twitter blocks anonymous fetches, fall back to the archived version or to [addyosmani.com/blog/agentic-engineering](https://addyosmani.com/blog/agentic-engineering/) (Addy Osmani's long-form piece cites Karpathy).
- Link "specialist team members" or a later sentence referencing agent protocols → cite [Model Context Protocol specification](https://modelcontextprotocol.io/specification) (verified live, spec schema `2025-11-25`) AND/OR [Claude Code documentation](https://code.claude.com/docs/en/overview) (canonical post-redirect URL — the old `docs.anthropic.com/en/docs/claude-code` path 301-redirects here). Use the new canonical URL for new citations, not the stale one.

**Target:** 2 citations minimum, anchored to clauses already in the prose. Do not invent new sentences; citations attach to existing claims. Use the site's established link pattern: `<a href="…" rel="noopener noreferrer">…</a>`.

#### 3b. `/skills/` (`plugins/soleur/docs/pages/skills.njk`)

Current external citations on the page: **2** (lines 19 — `docs.anthropic.com/en/docs/claude-code` and `modelcontextprotocol.io/`). The AEO audit (2026-04-18, §3 per-page scorecard) rates `/skills/` at 0 external cites — **this is stale**. The cited score appears to have been captured before the Claude Code + MCP links landed on line 19.

**Verification step at implementation time:** re-count links in rendered HTML. `grep -c 'rel="noopener noreferrer"' plugins/soleur/docs/pages/skills.njk` ≥ 2 satisfies the `≥ 2 external citations` criterion mechanically. If the count is ≥ 2 against the required sources, **no edit** is required for `/skills/` and the finding is technically closed by a count-update, not a content change. Document this explicitly in the PR body.

If the count is < 2 (or if the audit's specific three sources — Karpathy "agentic" framing, Anthropic Claude Code docs, a compound-engineering authority — are not all anchored), add 1–2 more citations:

- Karpathy on "agentic" framing: link the first occurrence of "Agentic engineering" in the body → [Karpathy introducing agentic engineering](https://x.com/karpathy/status/2019137879310836075) (verified Feb 2026 post via The New Stack).
- A compound-engineering authority: link "compound engineering lifecycle" on line 21 → [Every's "Compound Engineering: How Every Codes With Agents"](https://every.to/source-code/compound-engineering-how-every-codes-with-agents) by Dan Shipper and Kieran Klaassen. **Why this URL over the alternative `/chain-of-thought/compound-engineering`:** the `source-code` piece is dual-authored, describes the explicit four-step "plan, work, review, compound" lifecycle, and matches Soleur's own workflow naming. Both URLs resolve live — either works; prefer `/source-code/...`.

**Decision to make at implementation time:** count first, then edit only if needed. Follow the scope-fence "do not rewrite copy beyond what the audits prescribe."

#### 3c. `/getting-started/` (`plugins/soleur/docs/pages/getting-started.njk`)

Current external citations on the page (based on the Read of lines 1–80, extend in implementation): **0** in the intro + self-hosted sections. The page references "Claude Code extension" without linking (line 42) and "Ollama"/"local models" later in the page without sourcing.

Audit §P0-3 action: `Getting-started → cite Claude Code install docs, MCP spec`.

Add two inline citations:

- Link "Claude Code extension" on line 42 (path-card-desc on the "Self-Hosted (Open Source)" card) → [Claude Code documentation](https://code.claude.com/docs/en/overview) (canonical URL — the old `docs.anthropic.com/en/docs/claude-code` 301-redirects here; link equity preserved but new citations should use the canonical destination).
- Link "Model Context Protocol" at the first occurrence (or add a parenthetical on first mention in the Installation or subsequent section) → [Model Context Protocol specification](https://modelcontextprotocol.io/specification) (spec schema version `2025-11-25`; canonical spec URL).

**Gotcha:** the page separately has a C1-ranked bug — the Ollama callout ships an invalid command (`ollama launch claude --model gemma4:31b-cloud`). That bug is tracked as **#2550** and is out of scope for this PR. Do NOT touch the Ollama block. #2550 has its own plan.

### Phase 4 — Local build + Playwright QA

**Build command** (verified from root `package.json`):

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-marketing-p0-audit-drain && npm run docs:build
```

**QA checklist:**

- Inspect `_site/index.html`: confirm `<title>`, `<meta name="description">`, `<h1>`, and `.hero-tagline` carry the R1/R2/R3 strings exactly.
- Inspect `_site/about/index.html`: confirm 5 `<details>` blocks with the five prescribed questions, AND a second `<script type="application/ld+json">` block with `"@type": "FAQPage"` and 5 `Question` entries. Validate JSON parses (`node -e 'JSON.parse(require("fs").readFileSync("/tmp/faq.json","utf8"))'` on extracted body).
- Inspect `_site/agents/index.html`, `_site/skills/index.html`, `_site/getting-started/index.html`: count `<a href="https?://…"` external links; target ≥ 2 on each (minus same-origin links). Use `grep -Ec '<a [^>]*href="https?://' _site/<page>/index.html` minus internal link count if necessary.
- **Playwright MCP** on built output (`npm run docs:dev` → port 8080) for visual confirmation:
  - `/` — H1 swap visible, no layout regression on the hero.
  - `/about/` — FAQ block renders, `<details>` toggle works.
  - `/agents/`, `/skills/`, `/getting-started/` — citations render as links.
- **FAQPage schema validation:** use the Google Rich Results Test (`WebFetch` against `https://search.google.com/test/rich-results?url=<localhost-tunneled>` is gated; use a structured-data validator like `structured-data-testing-tool` if installed, or visually inspect the JSON-LD block against schema.org/FAQPage requirements). Minimum: ≥ 1 Question with `acceptedAnswer.text`, valid JSON, no trailing commas.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Homepage `seoTitle` is exactly `Soleur — AI Agents for Solo Founders | Every Department, One Platform` (audit §R1 verbatim).
- [ ] Homepage `description` is exactly the §R2 string (verbatim, 218 chars — deliberately longer than SERP truncation limit for AEO extractability; do NOT shorten).
- [ ] Homepage H1 is exactly `Stop hiring. Start delegating.` (audit §R3 verbatim).
- [ ] Homepage hero tagline is exactly `The Company-as-a-Service platform for solo founders. Build a billion-dollar company — alone.` (audit §R3 verbatim).
- [ ] `/about/` renders a visible FAQ section with the five prescribed questions, in order.
- [ ] `/about/` source contains a `<script type="application/ld+json">` block with `"@type": "FAQPage"` and 5 `Question` entries, sibling to the existing ProfilePage script. Note: FAQPage schema is for AEO/LLM extractability, NOT Google rich-result chips (site is ineligible under Google's 2023 policy restricting FAQ rich results to gov/health).
- [ ] JSON-LD on `/about/` parses as valid JSON (`node -e 'JSON.parse(fs.readFileSync(..))'` succeeds on each block).
- [ ] `/agents/` intro prose carries ≥ 2 external citations matching audit §P0-3 sources (Anthropic / MCP spec / Karpathy).
- [ ] `/skills/` page has ≥ 2 external citations — document the pre-edit count in the PR body (either "already satisfied" or "added N").
- [ ] `/getting-started/` has ≥ 2 external citations to Claude Code docs and/or MCP spec.
- [ ] Voice check: no newly-written copy contains "AI-powered", "leverage", "just", "simply", "assistant", "copilot", "plugin" (except literal CLI commands / code blocks).
- [ ] `npm run docs:build` succeeds with zero warnings.
- [ ] Playwright QA screenshots of `/`, `/about/`, `/agents/`, `/skills/`, `/getting-started/` attached to the PR.
- [ ] PR body contains four separate `Closes #2551`, `Closes #2552`, `Closes #2553`, `Closes #2555` lines (no qualifiers like "partially").
- [ ] PR body does NOT reference `Closes #2554` (scoped out — off-site submissions).
- [ ] Changed `.md` files (if any — plan file and scripted commits count) pass `npx markdownlint-cli2 --fix` on targeted paths.

### Post-merge (operator)

- [ ] Verify the four closing issues (#2551, #2552, #2553, #2555) move to CLOSED state within 1 minute of merge (auto-close via `Closes #`).
- [ ] Verify `main`-deploy pipeline rebuilds the site and new pages propagate to `https://soleur.ai/` within the CI window.
- [ ] Verify #2554 remains OPEN (off-site submissions handled separately).
- [ ] Schedule #2559 / #2560 / #2561 (P1 pillar articles) for a separate writing sprint via `/soleur:content-writer` — these are **not** closed by this PR.

## Domain Review

**Domains relevant:** Marketing (CMO).

### Marketing (CMO)

**Status:** carry-forward from 2026-04-18 content audit + AEO audit (both authored by CMO's growth-analyst specialist; no new domain decisions are made in this PR — it executes existing CMO-approved recommendations).

**Assessment:** The 2026-04-18 content audit §R1/R2/R3 and AEO audit §P0-1/§P0-3 are the CMO's own prior artifacts. This PR is execution of those recommendations verbatim. No fresh CMO consultation needed; re-invoking CMO to re-approve CMO's own written audit would be redundant.

### Product/UX Gate

**Tier:** advisory (existing pages modified, no new UI surface; no new component file created).

**Decision:** auto-accepted (pipeline — `/soleur:one-shot` is running this plan, and this check is the pipeline-context branch per the Product/UX Gate ADVISORY rule).

**Agents invoked:** none (CMO carry-forward from the source audits covers content-review; no copywriter re-invocation because the audit's R-rows are the copywriter-equivalent artifact).

**Skipped specialists:** none.

**Pencil available:** N/A (no wireframes needed — same page, swap copy in-place).

## Test Scenarios

1. **SEO frontmatter swap (happy path)** — edit `index.njk` lines 3–4; `npm run docs:build`; `grep -A1 '<title>' _site/index.html` matches R1; `grep 'name="description"' _site/index.html` matches R2.
2. **H1 / tagline swap (happy path)** — same file, body; `grep -n 'Stop hiring. Start delegating.' _site/index.html` returns ≥ 2 hits (new H1 + existing `.landing-cta` H2); `grep -n 'The Company-as-a-Service platform for solo founders.' _site/index.html` returns 1 hit.
3. **About FAQ schema (happy path)** — edit `about.njk`; build; extract the second JSON-LD block with `awk '/type="application\/ld\+json"/,/<\/script>/'`; pipe to `node -e 'JSON.parse(…)'`; assert `.@type === "FAQPage" && .mainEntity.length === 5`.
4. **Citation counts (happy path)** — for each of `/agents/`, `/skills/`, `/getting-started/`: `grep -Ec 'href="https?://[^"]+"' _site/<page>/index.html` ≥ 2 anchored to external host.
5. **Voice compliance sweep** — `grep -iE '\b(AI-powered|leverage|assistant|copilot|plugin)\b' about.njk new-faq-block.njk` returns zero hits outside of `<code>` blocks (plugin is allowed inside a code-fenced `claude plugin install soleur` command — already present on `getting-started.njk`).
6. **No change to in-scope-fence pages** — `git diff --stat main` on `plugins/soleur/docs/index.njk` / `about.njk` / three pages only; no edits to `/blog/`, `/changelog/`, `/vision/`, `/pricing/`, `/community/`, `/articles/`.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Merge FAQPage into the existing `about.njk` ProfilePage `@graph`. | The site's established pattern (`index.njk`, `agents.njk`) uses two sibling `<script>` blocks, not `@graph`. Matching precedent beats local optimization. |
| Add FAQ to `about.njk` via an Eleventy include for reuse on future pages. | YAGNI. Only one page needs a FAQ right now that doesn't already have one. If a second needs it, extract at that time. |
| Also close #2554 (third-party validation) since it's the last P0. | Explicit scope-fence: #2554 requires off-site submissions (G2, Product Hunt, AlternativeTo) that cannot be closed in a code PR. Included would either leak out or force a half-closed issue. |
| Also tackle #2559/#2560/#2561 (pillar articles) since they touch the same site. | Different workstream: those are net-new article authoring, which belongs to `/soleur:content-writer`, not a code-review drain. |
| Split into 4 separate PRs (one per issue). | Loses the PR #2486 cleanup-pattern benefit. All four issues are on the same commit blast radius (Eleventy site), same review surface, same test/QA run. Bundling is strictly more efficient. |
| Rewrite the `/vision/` page (C5 from the same content audit) since it's in the same audit. | C5 is P1, not P0. Scope fence says only P0 findings from the audit. Include would re-open the scope-out-vs-fold-in discussion mid-stream. |

## Non-Goals / Out of Scope

- Not closing #2550 (`/getting-started/` invalid Ollama command) — separate trust-breaking P0 with its own fix path; tracked independently.
- Not closing #2554 (third-party validation) — off-site submissions required, not closable in a PR.
- Not closing #2559, #2560, #2561 (P1 pillar articles) — net-new article authoring, `/soleur:content-writer` skill.
- Not fixing the `∞ Compounding Knowledge` stat (P2-3) — P2, scope-fenced.
- Not adding a `/glossary/` page (P2-1) — P2, scope-fenced.
- Not adding inline citations to `/pricing/` role costs (I1 from content audit) — P1, scope-fenced.
- Not modifying the `/vision/` opening paragraph (R6) — P1, scope-fenced.
- Not refactoring the `/about/` H1 from "About" to "Jean Deruelle — Founder of Soleur" (R7 / I3) — P1, separate improvement.
- Not adding the FAQ to `/agents/` (R9 / I2) — P1 improvement, scope-fenced.

## Risks & Gotchas

1. **Verbatim audit-string drift.** The audit file is the only source of truth. Before writing the Edit tool call, re-`Read` lines 158–186 of `2026-04-18-content-audit.md` to confirm the R1/R2/R3 strings match what this plan quotes. A diff between this plan and the audit is a planner bug, not an implementer bug — fix by re-reading the audit and overwriting the plan.
2. **Brand-guide banned-word trap on new FAQ answers.** "Plugin" is banned in public copy. The current `about.njk` already refers to "open-source Claude Code plugin" (line 47) which is a pre-existing brand-guide miss. Do NOT propagate that to the new FAQ answers — use "Claude Code extension" instead (precedent on `getting-started.njk` line 42, which uses "Claude Code extension"). Q4 above is phrased accordingly.
3. **JSON-LD double-script on `/about/`.** Some validators (Google Rich Results, Schema.org validator) accept multiple `<script type="application/ld+json">` blocks per page; others merge by URL. The site's precedent (`index.njk` has two sibling blocks) validates cleanly on the current live site. Do NOT change the existing ProfilePage block's shape.
4. **Eleventy-collection-path citations on `/agents/`, `/skills/`.** Both pages render catalog lists from data files (`agents.js`, `skills.js`). The citations added here live in the hand-authored intro prose (`<div class="prose">` block), NOT in the data files — do not edit `_data/*.js` for citation purposes. Agent/skill descriptions come from per-component frontmatter; that's a different surface and out of scope.
5. **`/skills/` pre-edit citation count.** Line 19 of `skills.njk` has both Anthropic and MCP inline links already. If `≥ 2 external citations` is already satisfied, the plan's implementation for `/skills/` is a no-op + doc note, not a content edit. Confirm by `grep -c rel="noopener noreferrer" plugins/soleur/docs/pages/skills.njk` at implementation time. If count ≥ 2 and both are to the required sources, document "pre-existing citations satisfy §P0-3" in the PR body and skip the file from the diff.
6. **Cloudflare 403 on WebFetch.** The audit notes `WebFetch` against `https://soleur.ai` returns 403. QA verification for this PR uses the local Eleventy build (`_site/`) as the authoritative check — the source IS what deploys, so source verification is sufficient. Post-merge operator step: visually confirm on live `https://soleur.ai/` within 5 min of CI deploy completion.
7. **Audit file may be edited after plan write.** If someone edits `2026-04-18-content-audit.md` between plan-write and implementation, the verbatim strings may drift. Mitigation: re-read before applying Edit. The audit file is in git, so a `git log -- knowledge-base/marketing/audits/soleur-ai/2026-04-18-content-audit.md` at implementation time will surface any edits since this plan's commit.
8. **#2554 contagion risk.** The one-shot invocation explicitly scopes out #2554. The plan repeats the scope-out prominently. Reviewer should reject any PR that adds `Closes #2554` — route the reviewer to the Non-Goals section if it creeps in during implementation.

## Branch + PR Plan

- **Branch (existing, do not rename):** `feat-one-shot-marketing-p0-audit-drain`
- **Commit strategy:** single commit or two commits — one for the homepage edits (Phase 1), one for the about FAQ + citation sweep (Phases 2–3). Either is acceptable; compound runs on all of them.
- **PR title (target):** `chore(marketing): drain P0 audit backlog 2026-04-18 (#2551 + #2552 + #2553 + #2555)`
- **PR body (closing lines, verbatim):**

  ```text
  Closes #2551
  Closes #2552
  Closes #2553
  Closes #2555
  ```

  Each on its own line, no qualifiers, no "partially". GitHub auto-close reads only the bare `Closes #N` form (plan skill sharp-edge from `wg-use-closes-n-in-pr-body-not-title-to`).
- **Semver label:** `semver:patch` — site content change, no component additions.
- **Changelog section (required by `plugins/soleur/AGENTS.md`):** one-line marketing/docs entry for each closed finding.

## Sharp Edges (from plan skill)

- `Closes #N` in PR body only, not title. Four separate lines.
- Do not invent copy; every replacement string traces to a §R-row or §P0 row in the audit file.
- Do not touch `apps/` or any non-`plugins/soleur/docs/` path — the issue text's `apps/soleur-ai/` is factually wrong; the reconciliation table above is canonical.
- Before Edit on `.njk` files, re-`Read` the file (Edit tool rejects un-read files after compaction).
- `npx markdownlint-cli2 --fix` only targets changed `.md` files, not repo-wide globs.

---

## Research Insights

### External-citation verification log (2026-04-18)

Every citation URL added by this PR was verified live during the deepen pass. Re-verify immediately before ship, per learning `2026-04-18-fabricated-cli-commands-in-docs.md` (PR #2563).

| Citation | URL | Verified | Notes |
|---|---|:-:|---|
| Karpathy on agentic engineering | `https://x.com/karpathy/status/2019137879310836075` | yes | Attributed in The New Stack "Vibe Coding Is Passé" article. X may block anonymous fetches — cross-check via New Stack or Addy Osmani if primary is gated. |
| Addy Osmani on agentic engineering (fallback) | `https://addyosmani.com/blog/agentic-engineering/` | yes | Long-form piece citing Karpathy; usable as secondary anchor if X URL is gated. |
| MCP spec | `https://modelcontextprotocol.io/specification` | yes (WebFetch) | Spec schema version `2025-11-25`. Canonical. |
| Claude Code docs | `https://code.claude.com/docs/en/overview` | yes (WebFetch) | Old `docs.anthropic.com/en/docs/claude-code` 301-redirects here. Use new URL for new citations. |
| Compound Engineering (primary) | `https://every.to/source-code/compound-engineering-how-every-codes-with-agents` | yes (WebFetch) | Dan Shipper + Kieran Klaassen. Describes plan/work/review/compound four-step lifecycle. |
| Compound Engineering (alt) | `https://every.to/chain-of-thought/compound-engineering` | yes (WebFetch) | Kieran Klaassen solo piece. Either URL is acceptable — primary preferred. |

### Phase 2 (About FAQ) — DOM placement precision

Per learning `2026-03-17-faq-section-nesting-consistency.md`: when adding full-width FAQ sections across multiple templates, the insertion point **must be outside** any `<div class="container">` wrapper. The reference pattern is `index.njk` — its FAQ sits at root level, not inside `.container`. Inside-container FAQ renders at constrained width; outside-container FAQ renders at viewport width via `landing-section` class.

Current `about.njk` structure (verified by reading the file in this pass):

```njk
<section class="page-hero"> ... </section>  <!-- line 8 -->
<div class="container">  <!-- line 15 -->
  <section class="category-section"> ... Jean Deruelle ... </section>
  <section class="category-section"> ... About Soleur ... </section>
</div>  <!-- line 53 — closes .container -->
<script type="application/ld+json"> ... ProfilePage ... </script>  <!-- lines 55–79 -->
```

**Correct placement** for the new FAQ: insert between line 53 (`</div>` closing `.container`) and line 55 (`<script>`). The new section uses `class="landing-section"` (not `container`) so it styles as full-width, matching `index.njk`, `agents.njk`, `skills.njk`.

**Updated insertion target:**

```njk
    </div>  <!-- line 53: closes .container -->

    <!-- NEW: FAQ section, outside .container, landing-section style -->
    <section class="landing-section">
      <div class="landing-section-inner">
        <p class="section-label">Common Questions</p>
        <h2 class="section-title">Frequently Asked Questions</h2>
        <div class="faq-list">
          <details class="faq-item"> ... </details>
          <!-- 5 total -->
        </div>
      </div>
    </section>

    <!-- NEW: FAQPage JSON-LD, sibling to existing ProfilePage script -->
    <script type="application/ld+json">
    { "@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [ ... 5 Q ... ] }
    </script>

    <script type="application/ld+json">  <!-- line 55 (existing ProfilePage) -->
```

### FAQPage schema policy (2026)

Per [Google Search Central](https://developers.google.com/search/blog/2023/08/howto-faq-changes) (updated Aug 2023, still active as of 2026-04):

- FAQPage rich results in Google SERP are restricted to "well-known, authoritative government and health websites." Soleur.ai is NOT eligible for SERP rich-result chips.
- FAQPage schema remains valuable for: (a) AI answer engines (ChatGPT, Perplexity, Claude, Google AI Overviews) that extract structured Q&A pairs for citation; (b) topical relevance signals to search engines even without rich-result surfacing; (c) future policy changes if Google reopens eligibility.

**Implication for this PR:** the AEO audit §P0-1 calls out "structurally invisible to AI answer-extractors" — this is precisely the AI-engine extraction use case, NOT Google rich-result chips. The audit's goal is met regardless of Google SERP eligibility. Update the PR body to clarify: "FAQPage schema added for AEO/LLM extractability, not Google rich-result chips (not eligible under current policy for non-gov/health sites)."

### Meta description character-count trade-off

The R2 string:

> `Stop hiring, start delegating. Soleur deploys 60+ AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop. Your expertise, amplified.`

Length: **218 characters** (verified `echo -n "..." | wc -c`).

Google SERP truncates meta descriptions around 155–160 characters. R2 exceeds this. This is intentional in the audit — the full 218-char form is optimized for AI engines (ChatGPT, Claude, Perplexity) which read the whole meta as context for citation extraction. Google will truncate in SERP; AI engines will not. Audit accepts the trade-off.

**Acceptance criterion addition:** do NOT shorten R2 to fit Google SERP — use it verbatim. The longer form is the deliberate AEO optimization.

### Learning-sweep relevance matrix

| Learning | Relevant? | How applied |
|---|:-:|---|
| `2026-04-18-fabricated-cli-commands-in-docs.md` | yes | Verified every cited URL live; logged in verification table above. |
| `2026-03-06-blog-citation-verification-before-publish.md` | yes | "No naked URL" — every citation URL verified. |
| `2026-03-17-faq-section-nesting-consistency.md` | yes | FAQ insertion point corrected: outside `.container`, matching `index.njk` reference pattern. |
| `2026-03-26-seo-meta-description-frontmatter-coherence.md` | yes | Meta description char count verified (218) and trade-off documented. |
| `2026-03-15-eleventy-build-must-run-from-repo-root.md` | yes | Phase 4 build command already runs from repo root. No change. |
| `2026-03-10-eleventy-build-fails-in-worktree.md` | yes | Same as above — must run from worktree root, not from `plugins/soleur/docs/`. |
| `2026-02-21-marketing-audit-brand-violation-cascade.md` | yes | Scope fence holds — 5 files only, no cascade. |
| `2026-03-17-planning-direction-confirmation-required.md` | no | Directionality is unambiguous (audit R-rows map 1:1 to template edits). |
| `2026-03-24-eleventy-fileslug-date-stripping.md` | no | No blog-post slugs affected — only page templates. |
| `2026-04-18-agents-md-byte-budget-and-why-compression.md` | no | No AGENTS.md edits. |

### Additional risks surfaced by deepen pass

9. **Stale link equity vs canonical URL trade-off.** Four existing Soleur pages link to `https://docs.anthropic.com/en/docs/claude-code` (old URL, 301-redirects). New citations from this PR use `https://code.claude.com/docs/en/overview` (canonical). A future cleanup PR could normalize all four pre-existing links to the canonical URL — do not fold that into this PR (scope creep). Filing a follow-up issue is optional and low-priority; 301-redirects preserve link equity.
10. **X.com gated fetches for Karpathy URL.** `x.com/karpathy/status/...` may return login walls or "rate-limit exceeded" pages to anonymous fetchers. Browser users following the link are fine; AI engines scraping the page may fail to resolve the citation. Mitigation: include `rel="noopener noreferrer"` (plan already specifies this) and accept that Karpathy citations on the public web have this baseline risk. Alternative: use `addyosmani.com/blog/agentic-engineering/` as primary anchor and Karpathy as secondary — Addy Osmani's blog is open to all fetchers.
11. **JSON-LD validity for FAQ with 5 Qs.** Schema.org `FAQPage` requires at least 1 `Question` with a `name` and `acceptedAnswer.text`. 5 Qs is well within spec. No schema violation risk. Google's structured-data linter (if we could test against it) would accept, even though rich-result display is policy-restricted.
12. **`about.njk` existing brand miss ("plugin" at line 47).** Pre-existing; NOT introduced by this PR. Do NOT fix in this PR (scope creep + cascade risk). Consider filing a small P2 follow-up issue post-merge if the team wants to clean brand-voice drift; not required for closing #2551/#2552/#2553/#2555.
13. **Audit file stability.** Between plan-write and implementation, if someone edits `2026-04-18-content-audit.md`, the R-row strings may drift. Mitigation already captured in Phase 1 (re-read lines 158–186 before Edit). `git log -- <audit-path>` shows no edits in the 2h window of this session, so drift risk is low.

### External References

- Google Search Central — FAQPage policy: <https://developers.google.com/search/blog/2023/08/howto-faq-changes>
- MCP specification: <https://modelcontextprotocol.io/specification>
- Claude Code docs: <https://code.claude.com/docs/en/overview>
- Karpathy agentic engineering: <https://x.com/karpathy/status/2019137879310836075> (primary), <https://addyosmani.com/blog/agentic-engineering/> (fallback)
- Compound Engineering: <https://every.to/source-code/compound-engineering-how-every-codes-with-agents>
- FAQPage schema spec: <https://schema.org/FAQPage>
