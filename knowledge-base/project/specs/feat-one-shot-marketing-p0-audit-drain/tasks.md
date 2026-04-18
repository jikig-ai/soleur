# Tasks — feat-one-shot-marketing-p0-audit-drain

**Plan:** `knowledge-base/project/plans/2026-04-18-chore-marketing-p0-audit-drain-2551-2552-2553-2555-plan.md`
**Closes:** #2551, #2552, #2553, #2555

## 1. Setup

- 1.1. Re-read audit `knowledge-base/marketing/audits/soleur-ai/2026-04-18-content-audit.md` §R1, §R2, §R3 to confirm verbatim strings match plan before editing.
- 1.2. Re-read audit `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md` §P0-1, §P0-3 for FAQ Q-list and citation source list.
- 1.3. `grep -c 'rel="noopener noreferrer"' plugins/soleur/docs/pages/skills.njk` to establish pre-edit citation count for `/skills/`.
- 1.4. Confirm branch: `git branch --show-current` returns `feat-one-shot-marketing-p0-audit-drain`.

## 2. Core Implementation

### 2.1. Homepage — frontmatter + hero (#2551, #2552)

- 2.1.1. Edit `plugins/soleur/docs/index.njk` line 3: replace `seoTitle` with `"Soleur — AI Agents for Solo Founders | Every Department, One Platform"`.
- 2.1.2. Edit `plugins/soleur/docs/index.njk` line 4: replace `description` with the §R2 verbatim string.
- 2.1.3. Edit `plugins/soleur/docs/index.njk` line 11: replace `<h1>` body with `Stop hiring. Start delegating.`.
- 2.1.4. Edit `plugins/soleur/docs/index.njk` line 12: replace `.hero-tagline` body with the §R3 subhead verbatim.

### 2.2. /about/ — FAQ block + FAQPage JSON-LD (#2553)

- 2.2.1. Edit `plugins/soleur/docs/pages/about.njk`: insert a new `<section class="landing-section">` block with 5 `<details class="faq-item">` children before the final `</div>` of `.container` (after line 53).
- 2.2.2. Insert a new `<script type="application/ld+json">` block after the existing ProfilePage script (line 79), containing `"@type": "FAQPage"` with 5 `Question` entries matching the `<details>` UI content exactly.
- 2.2.3. Voice sweep on new copy: grep for banned words in the new block — `AI-powered`, `leverage`, `just\b`, `simply\b`, `assistant\b`, `copilot`, `plugin`. Only `plugin` is acceptable inside `<code>` (not in this block). Expect 0 hits.

### 2.3. Citation sweep — core pages (#2555)

- 2.3.1. `plugins/soleur/docs/pages/agents.njk` lines 19–23: anchor 2 inline links to Anthropic agent docs / MCP spec / Karpathy on agent systems. Use existing `<a href … rel="noopener noreferrer">` pattern.
- 2.3.2. `plugins/soleur/docs/pages/skills.njk`: if pre-edit count ≥ 2 to required sources (see Task 1.3), document "pre-existing citations satisfy §P0-3" in PR body and skip. Otherwise add 1–2 links per plan §3b.
- 2.3.3. `plugins/soleur/docs/pages/getting-started.njk` line 42 + intro: anchor 2 inline links (Claude Code docs + MCP spec) to existing phrases. Do NOT edit the Ollama callout (#2550 scope).

## 3. Verification

- 3.1. `npm run docs:build` from worktree root — expect zero warnings.
- 3.2. Inspect `_site/index.html`: `<title>`, `<meta name="description">`, `<h1>`, `.hero-tagline` all match R1/R2/R3.
- 3.3. Inspect `_site/about/index.html`: 5 `<details>` Qs + 2 `<script type="application/ld+json">` blocks. Validate JSON: `awk '/application\/ld\+json/,/<\/script>/' _site/about/index.html | jq -e 'select(.["@type"]=="FAQPage") | .mainEntity | length==5'`.
- 3.4. Inspect `_site/{agents,skills,getting-started}/index.html`: `grep -Ec '<a [^>]*href="https?://' <file>` ≥ 2 external per page.
- 3.5. Playwright MCP on local `npm run docs:dev` (port 8080): screenshot `/`, `/about/`, `/agents/`, `/skills/`, `/getting-started/`. Confirm FAQ `<details>` toggles. Attach to PR.
- 3.6. `npx markdownlint-cli2 --fix` on `knowledge-base/project/plans/2026-04-18-chore-marketing-p0-audit-drain-2551-2552-2553-2555-plan.md` and `knowledge-base/project/specs/feat-one-shot-marketing-p0-audit-drain/tasks.md` only (not repo-wide).

## 4. Ship

- 4.1. `skill: soleur:compound` to capture learnings.
- 4.2. Commit with message per plan Branch + PR Plan. Four separate `Closes #N` lines in body.
- 4.3. `skill: soleur:ship` — semver label `semver:patch`; ensures review gates and content-review gate (already carry-forward-covered) run.
- 4.4. Post-merge: verify #2551, #2552, #2553, #2555 moved to CLOSED. Verify #2554 remains OPEN (scoped out).
- 4.5. Capture any deferred P1 findings surfaced during QA into the existing P1 tracking issues (#2559 / #2560 / #2561) — do not file new ones in this PR.
