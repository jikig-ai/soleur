# Tasks — feat-one-shot-domain-marketing-drain

Derived from `knowledge-base/project/plans/2026-04-21-refactor-marketing-site-aeo-content-drain-plan.md`.

## Phase 1 — Setup (RED tests scaffolding)

- 1.1 Test runner is **bun:test** (verified during deepen pass: `head plugins/soleur/test/components.test.ts` shows `import { describe, test, expect } from "bun:test";`). Do NOT use vitest.
- 1.2 Create `plugins/soleur/test/marketing-content-drift.test.ts` with the 5 drift-guard tests, written to FAIL against current `main`.
  - 1.2.1 Test 1: prose-stale-numerals sweep (knowledge-base/marketing/*.md + components/*.md + project/README.md), allowlist audits/ + learnings/.
  - 1.2.2 Test 2: no `Spark` token in current site copy (`plugins/soleur/docs/_includes/`, `index.njk`, `pages/*.njk`).
  - 1.2.3 Test 3: Organization JSON-LD has founder.name === "Jean Deruelle" + foundingDate matches /^\d{4}$/.
  - 1.2.4 Test 4: `_site/company-as-a-service/index.html` exists with `<h1>` + `_site/blog/what-is-company-as-a-service/index.html` has meta-refresh.
  - 1.2.5 Test 5: `_site/pricing/index.html` `.hiring-footnote` parent has >=2 `<a href="https://` + a `YYYY-MM-DD` date.
- 1.3 Run `bun test plugins/soleur/test/marketing-content-drift.test.ts` — confirm all 5 RED.
- 1.4 Commit RED state with message `test(marketing): add drift-guard suite (RED)`.

## Phase 2 — Eleventy site edits

- 2.1 (#2666) Edit `plugins/soleur/docs/_includes/base.njk`:
  - 2.1.1 Add `founder` (Person, name "Jean Deruelle", url "https://github.com/deruelle") to Organization @graph node.
  - 2.1.2 Add `foundingDate: "2026"` (verified during deepen pass — repo created 2026-01-27; year-only ISO 8601 valid per Schema.org).
  - 2.1.3 Rename SoftwareApplication offer "Spark (Cloud Platform)" → "Solo (Cloud Platform)".
  - 2.1.4 Use `| jsonLdSafe | safe` on every new string interpolation.
  - 2.1.5 Preserve existing `@id: "https://soleur.ai/#organization"` (Schema.org best practice — stable URI for cross-page entity stitching).
- 2.2 (#2657 + #2664) Edit `plugins/soleur/docs/index.njk`:
  - 2.2.1 Insert eyebrow `<p class="section-label">Company-as-a-Service</p>` inside `.landing-hero` BEFORE the `<h1>`.
  - 2.2.2 Change line 60 H2 to "The Company-as-a-Service platform that already knows your business."
  - 2.2.3 Rewrite "Is Soleur free?" FAQ answer (lines 185-187) per content-plan RW-2 — drop "Spark", link to /pricing/.
  - 2.2.4 Mirror the rewrite into the FAQPage JSON-LD block (lines 240-244).
- 2.3 (#2665) Edit `plugins/soleur/docs/pages/pricing.njk` line 120:
  - 2.3.1 Replace footnote with the 3-citation HTML block: **Robert Half 2026 Salary Guide, Payscale US database, Levels.fyi total-comp methodology** (BLS dropped: it returns HTTP 403 to all curl checks because of Akamai bot-fight, breaking pre-merge gate).
  - 2.3.2 Use commit-day date in the Payscale citation (`queried YYYY-MM-DD`).
  - 2.3.3 Run `curl -fsI -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" <url> | head -1` for each of the 3 URLs; abort if any !=200. (Mozilla UA required — bot-protection sites 403 plain curl.)
- 2.4 (#2663) Edit `plugins/soleur/docs/pages/vision.njk`:
  - 2.4.1 Line 81 card title → "Multi-Model AI Agent Orchestration"; prepend description "Internally called \"The Global Brain\". ".
  - 2.4.2 Line 89 card title → "Centralized Decision Memory and Approval Dashboard"; prepend "Internally called \"The Decision Ledger\". ".
  - 2.4.3 Line 105 card title → "Cross-Department Agent Coordination"; prepend "Internally called \"The Coordination Engine\". ".
- 2.5 (#2658) CaaS pillar promotion:
  - 2.5.1 Create `plugins/soleur/docs/pages/company-as-a-service.njk` with frontmatter `permalink: company-as-a-service/`, `layout: base.njk`, copied content from the blog post.
  - 2.5.2 Add bottom back-link strip with `Compare Soleur to <competitor>` for: anthropic-cowork, notion-custom-agents, cursor, polsia, paperclip, devin (six links).
  - 2.5.3 Delete `plugins/soleur/docs/blog/what-is-company-as-a-service.md`.
  - 2.5.4 Append `{ from: "blog/what-is-company-as-a-service/index.html", to: "/company-as-a-service/" }` to `plugins/soleur/docs/_data/pageRedirects.js`.
- 2.6 Run `cd plugins/soleur/docs && npm run build`; verify zero warnings; verify `grep -rl Spark _site/` returns zero.
- 2.7 Re-run drift-guard tests — Test 2/3/4/5 should be GREEN.

## Phase 3 — Knowledge-base prose drift fixes (#2659)

- 3.1 Edit `knowledge-base/marketing/brand-guide.md`:
  - 3.1.1 Replace "63 agents, 62 skills" → "60+ agents, 60+ skills" repo-wide in this file.
  - 3.1.2 Replace standalone "63 agents" → "60+ agents", "62 skills" → "60+ skills".
  - 3.1.3 Add meta paragraph at top of Numbers section: "Use soft floors in static prose. The live site renders exact counts via {{ stats.agents }} — never duplicate exact counts in prose."
- 3.2 Edit `knowledge-base/project/components/agents.md` line 54: "(63 agents across 8 domains)" → "(60+ agents across 8 departments)".
- 3.3 Edit `knowledge-base/project/components/skills.md` line 68: "(62 skills)" → "(60+ skills)".
- 3.4 Edit `knowledge-base/project/README.md`:
  - 3.4.1 Line 115 "(63 agents)" → "(60+ agents)".
  - 3.4.2 Line 126 "(62 skills)" → "(60+ skills)".
- 3.5 Edit `knowledge-base/marketing/content-strategy.md` line 334: "(63 agents, 62 skills, 420+ PRs)" → "(60+ agents, 60+ skills, 420+ PRs)".
- 3.6 `npx markdownlint-cli2 --fix` on each changed `.md` file individually (per `cq-markdownlint-fix-target-specific-paths`).
- 3.7 Re-run drift-guard test 1 — GREEN.

## Phase 4 — Verification + commit

- 4.1 Full drift-guard suite run — all 5 GREEN.
- 4.2 Visual smoke screenshots: homepage (eyebrow + H2 + FAQ), /pricing/ (footnote), /vision/ (3 cards), /company-as-a-service/ (new page + back-link strip), /blog/what-is-company-as-a-service/ (meta-refresh).
- 4.3 `git diff --stat` confirms changes only in `plugins/soleur/docs/`, `knowledge-base/marketing/`, `knowledge-base/project/components/`, `knowledge-base/project/README.md`, `plugins/soleur/test/marketing-content-drift.test.ts`. ABORT if any `apps/web-platform/` files appear.
- 4.4 Verify labels exist via `gh label list --limit 100 | grep -i marketing` and `... | grep -i p1-high`.
- 4.5 Run `compound` skill before commit per `wg-before-every-commit-run-compound-skill`.
- 4.6 Commit with message `refactor(marketing): drain SEO/AEO + content backlog from 2026-04-19 audit`.
- 4.7 Push, open PR with body containing `Closes #2666`, `Closes #2665`, `Closes #2664`, `Closes #2663`, `Closes #2659`, `Closes #2658`, `Closes #2657`, `Ref #2656`, plus `## Changelog` (semver:patch), plus the `## Net impact on backlog` table per PR #2486 reference.
- 4.8 Apply labels `domain/marketing`, `type/chore`, `priority/p1-high`, `semver:patch`.
- 4.9 `gh pr merge <N> --squash --auto` and poll until MERGED.

## Phase 5 — Post-merge

- 5.1 Verify `https://soleur.ai/company-as-a-service/` returns 200.
- 5.2 Verify `https://soleur.ai/blog/what-is-company-as-a-service/` returns the meta-refresh body.
- 5.3 Submit `/company-as-a-service/` URL to Google Search Console for indexing (manual handoff at the GSC URL submission page — only the captcha/auth step is genuinely manual; the rest is Playwright-able).
- 5.4 `gh issue view 2666 2665 2664 2663 2659 2658 2657 --json state` — confirm all CLOSED.
- 5.5 Update `knowledge-base/product/roadmap.md` Current State if any phase milestone closes (likely not — these are individual P1 fixes).
