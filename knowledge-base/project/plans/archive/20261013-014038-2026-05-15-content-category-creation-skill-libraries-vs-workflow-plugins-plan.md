---
title: "content: category-creation piece — 'Skill libraries vs. workflow plugins'"
type: content
issue: 2729
parent: 2718
related_prs: [2734]
branch: feat-one-shot-2729
lane: single-domain
requires_cpo_signoff: false
detail_level: MORE
status: draft
created: 2026-05-15
deepened: 2026-05-15
owner: marketing
domain: marketing
---

# content: category-creation piece — "Skill libraries vs. workflow plugins"

Closes #2729. Parent: #2718. Sibling already-shipped: #2728 (Skill Library tier seed, closed via PR #2734), #2722 (peer-plugin-audit sub-mode, same PR).

## Enhancement Summary

**Deepened on:** 2026-05-15
**Sections enhanced:** Acceptance Criteria, Phases 0/2/3/4/5/6/7, Files to Create, Risks, Test Strategy, Research Insights (new).
**Research sources used:** repo precedents (8 existing `soleur-vs-*` posts, `2026-04-30-best-claude-code-plugins-2026.md`), 4 institutional learnings, brand-guide grep, `seo-aeo` SKILL contract, `content-writer` SKILL contract, `social-distribute` SKILL Phase-9 contract, Eleventy `blog.json` directory-data cascade.

### Key Improvements

1. **Corrected three fabricated script/command paths** discovered at deepen-time:
   - SEO validate script is `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` (NOT `seo-validate.sh`).
   - Build command is `npm run docs:build` / `npx @11ty/eleventy` (NOT `bun run build` — `package.json` `scripts.build` does not exist; the canonical commands are `docs:dev` and `docs:build`).
   - `scripts/lint-distribution-content.sh` IS at repo-root `scripts/` (verified live in this worktree).
2. **Folded `2026-03-05-eleventy-blog-post-frontmatter-pattern.md` learning**: `blog.json` cascades `layout: blog-post.njk` and `ogType: article` — frontmatter MUST NOT redeclare these. Body MUST NOT add inline `BlogPosting` JSON-LD (template emits it). Inline `FAQPage` JSON-LD is allowed and standalone — but per copywriter sharp edge `2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md`, the safe default is to skip inline FAQPage JSON-LD entirely.
3. **Added keyword-density target** (0.3-0.4% for primary keyword across ~1,500-word article = 5-7 occurrences of "skill library" / "workflow plugin"). Forcing this prevents both stuffing and zero-signal under-use.
4. **Hardened AC4 grep gate**: replaced regex alternation that would over-match neutral uses ("two shapes", "head-to-head" can validly appear in a section discussing the rejected framing) with a sentence-level review pattern — every match is read in context, never auto-rejected.
5. **Added Phase 4.5 distribution-content lint pre-write step**: `social-distribute` SKILL Phase 9.4 already writes frontmatter; the lint MUST run AFTER each platform variant block lands, not after the file is written, to keep the loop tight.
6. **Tracked the `Slug derivation collision risk`** in Risks: `social-distribute` slug derivation strips path and `.md`, keeping kebab-case. The blog filename `2026-05-15-skill-libraries-vs-workflow-plugins.md` produces slug `2026-05-15-skill-libraries-vs-workflow-plugins` — no collision with the 12 existing distribution-content files (verified).
7. **Verified all GitHub labels prescribed for Phase 8 follow-up issue exist**: `domain/marketing`, `chore`, `priority/p3-low`, `content` all confirmed via `gh label list`. `seo` and `infrastructure` (originally considered) do NOT exist — substituted.
8. **Added image asset path note**: `ogImage` declared in frontmatter at `blog/og-skill-libraries-vs-workflow-plugins.png` does NOT need to exist in-tree at PR time (precedent: 2026-04-30 + 2026-05-14 posts). Image generation is a separate workflow.

### New Considerations Discovered

- The Skill Library tier seeded by PR #2734 in `competitive-intelligence.md` has been overwritten by a subsequent weekly-CI regeneration — already captured in Research Reconciliation; Phase 8 follow-up issue files the re-seed without expanding this PR's scope.
- `content-writer` `--headless` mode auto-accepts when all citations PASS — if fact-checker is unavailable, it auto-accepts with a warning. The plan does NOT rely on `--headless` in implementation: Phase 1.1 invokes interactively, and Phase 4 spawns `fact-checker` explicitly. This avoids the silent-degradation path.
- Eleventy version is implicit (`npx @11ty/eleventy` resolves whatever is installed); Eleventy 3.x changed config-file naming from `.eleventy.js` to `eleventy.config.js` — repo uses the 3.x form. No version-pin concern for this content PR (no API surface touch).


## Overview

Author a long-form blog article that reframes the Soleur vs. [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) comparison on the axis of **portable skill library vs. workflow plugin** — explicitly NOT on skill count. The CMO assessment in parent #2718 is unambiguous: a head-to-head count framing (68 vs. 235+) cedes the argument before the reader finishes the title bar. A category-creation frame (two complementary shapes, not two competing products) defends the positioning at skim-read time, bundles future ICP expansions naturally, and reinforces the brand-guide rule "state what Soleur does, never what others lack".

The article ships to the existing Eleventy blog at `plugins/soleur/docs/blog/` (same surface as the 8 existing `soleur-vs-*` posts) and is distributed via the standard pipeline (`knowledge-base/marketing/distribution-content/`). It cites alirezarezvani/claude-skills as a **category exemplar** — the canonical example of the "portable skill library" shape — not as a competitor.

This is a content/marketing deliverable. No code is shipped. The only code-surface touch is the new markdown file under `plugins/soleur/docs/blog/` and the distribution-content markdown under `knowledge-base/marketing/distribution-content/`. Both are caught by the docs change-class loader (no code/infra sidecars fire).

## Why now

1. **Parent #2718's CMO line item is the last open child of the audit.** #2719 / #2720 / #2721 / #2722 / #2723 / #2724 / #2725 / #2726 / #2727 / #2728 are all shipped or actively in progress; #2730 is closed-not-planned. #2729 is the final CMO deliverable.
2. **Search-intent capture for a defensible long-tail query.** "Claude skills vs Claude Code plugins", "portable skills vs workflow plugins", and adjacent variants currently have no first-party Soleur surface — the gap closes if the category framing is published.
3. **Reusable framing for future ICP expansions.** Defining "portable skill library" as a category lets future skill-library entrants slot into a pre-existing frame instead of forcing per-competitor rewrites.

## User-Brand Impact

**If this lands broken, the user experiences:** a published blog post that frames alirezarezvani/claude-skills as a competitor (violating the brand-guide rule "state what Soleur does, never what others lack"), or that cites head-to-head skill counts (cedes the framing axis CMO explicitly rejected in #2718), or that contains a fabricated stat / dead citation URL surfaced by the fact-checker mode.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is public marketing content with no user data, no auth surface, no schema change. No GDPR/CCPA regulated-data class is touched.

**Brand-survival threshold:** `none` — content quality miss is recoverable via a follow-up edit; no per-PR CPO sign-off required. The deepen-plan Phase 4.6 gate is satisfied by this section being present with explicit threshold + reasoning. Preflight Check 6 will detect zero sensitive-path matches.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Article exists.** New file at `plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` with valid Eleventy frontmatter (`title`, `seoTitle`, `date`, `description`, `ogImage`, `tags`). `npm run docs:build` (canonical command per `package.json` `scripts.docs:build` = `npx @11ty/eleventy`) emits the page at `_site/blog/2026-05-15-skill-libraries-vs-workflow-plugins/index.html`. Verify the emitted file contains valid JSON-LD `BlogPosting` (no broken `<script type="application/ld+json">` from a `</script>` collision in body content — see `2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md` learning). **Frontmatter MUST NOT include `layout:` or `ogType:`** — both are inherited from `plugins/soleur/docs/blog/blog.json` (verified). Per `2026-03-05-eleventy-blog-post-frontmatter-pattern.md`, redeclaring inherited fields is the canonical mis-step on new blog posts.
- [ ] **AC2 — Authored via `copywriter` + `content-writer` flow, fact-checked.** PR body documents which agent produced the first draft (the `content-writer` skill is the canonical blog-article author per its description; `copywriter` reviews voice/CTA). Every cited external URL passes the fact-checker invocation — see the inline `fact-checker` step in copywriter's sharp edges. PR body lists every external citation with PASS / SOURCED / UNSOURCED status.
- [ ] **AC3 — No head-to-head count citations.** Grep gate: `grep -nE '\b(68|235|235\+)\b|skill count|skills count' plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` returns **zero** lines. The CMO directive in #2718 forbids the count axis. If a count must be referenced for ecosystem-size context (e.g., "the alirezarezvani repository catalogs over two hundred skills"), the prose MUST frame it as a property of the category exemplar, never as a comparison delta against Soleur.
- [ ] **AC4 — alirezarezvani/claude-skills cited as category exemplar (not competitor).** **Two-stage check** (regex surfacing + sentence-level review, never auto-rejection):
  1. **Surfacing grep** — `grep -nE '(alirezarezvani|claude-skills)' plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` returns ≥ 1 match (the article MUST name the exemplar at least once in the "What a Skill Library Is" section).
  2. **Sentence-level review** — for every match line, read the full enclosing sentence. Each must be framed as exemplar / category-defining / canonical-of-the-portable-library-shape. Forbidden frames (auto-fail): "vs.", "versus", "competitor", "competing against", "head-to-head", "better than", "worse than", "more skills than", "fewer skills than". Allowed frames: "the canonical exemplar of", "defines the shape", "the reference repository for the portable-library category", "catalogs over [N] skills" (descriptive, not comparative).
  3. **Title constraint** — `head -5 <article>` MUST NOT match the regex `Soleur vs\.` (the 8 existing `soleur-vs-*` posts establish that exact verbatim title shape — reusing it here would auto-frame the article as competition at the H1 / SEO-title level).
- [ ] **AC5 — SEO/AEO metadata per the `seo-aeo` skill.** Build first: `npm run docs:build` (resolves to `npx @11ty/eleventy`). Then validate: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` (verified script path, exits 0/1) AND `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` (sibling CSP gate that `seo-aeo fix` already pairs with `validate-seo.sh`). Equivalent: invoke `skill: soleur:seo-aeo validate`. All checks pass: `<title>` ≤ 60 chars (matches `seoTitle`), meta description 140-160 chars, OG image referenced, canonical URL set, JSON-LD `BlogPosting` valid (parseable JSON, `headline` + `author` + `publisher` fields all populated — emitted automatically by `blog-post.njk`).
- [ ] **AC6 — Distribution content file present.** New file at `knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md` with valid YAML frontmatter per `social-distribute` SKILL Phase 9 spec (`title: "<blog-post-title>"`, `type: pillar` — per the `2026-03-24-vibe-coding-vs-agentic-engineering.md` precedent (Status: scheduled, `type: pillar`), `publish_date: ""` empty string per Phase-9 template OR `2026-05-15` if cron-immediate, `channels: discord, x, bluesky, linkedin-company`, `status: draft` or `scheduled`). Includes per-platform variants (Discord, X/Twitter thread, IndieHackers, Reddit, LinkedIn, optional Hacker News) following the existing `2026-03-24-vibe-coding-vs-agentic-engineering.md` pattern. Run `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md` — exit 0. **Verified at deepen-time**: script exists at the repo-root `scripts/` path (not in a plugin subdirectory).
- [ ] **AC7 — `redirects.njk` (if applicable) untouched.** Confirm no `redirects.njk` edit is needed (new page is not replacing an existing URL).
- [ ] **AC8 — Tag conventions match existing comparison posts.** Tags include `comparison`, `category-creation`, `claude-code`, `solo-founder` at minimum; date is ISO `2026-05-15`.

### Post-merge (operator)

- [ ] **AC9 — Discord webhook variant delivered.** If the social-distribute flow's Discord webhook was deferred per `social-distribute/SKILL.md`, confirm the content-publisher cron picks up the new distribution-content file at next scheduled run, or invoke `skill: soleur:social-distribute` against the new blog post for immediate webhook delivery. **Automation feasibility:** Discord webhook is automatable via `mcp__plugin_soleur_*` / curl; the cron pipeline (`content-publisher.sh`) already handles X / Bluesky / LinkedIn. The only steps requiring human judgment are platform-specific gates (Hacker News submission is operator-gated by design — HN's submission flow is anti-automation).
- [ ] **AC10 — `Ref #2729` not `Closes #2729` on PR body.** This is a content piece with no post-merge prod-write step; `Closes` is correct. Standard `Closes #2729` in PR body — does NOT match the `ops-remediation` class that requires `Ref #N`.

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue claim | Reality at plan time | Plan response |
|--------------------|----------------------|---------------|
| "Parent: #2718, Spec FR7" | #2718 is a tracking issue; no spec.md exists at `knowledge-base/project/specs/feat-claude-skills-audit/` (archive `2026-04-21-180046-feat-claude-skills-audit/` is empty). FR7 is enumerated in #2718's body, not in a checked-in spec. | Plan treats `#2718` body as the spec source-of-truth. AC4 directly encodes the CMO directives in `#2718` (no head-to-head count, no competitor framing). |
| "Skill Library tier in `competitive-intelligence.md`" (per closed #2728) | Tier was seeded in PR #2734 (commit 31cb987c). Current `knowledge-base/product/competitive-intelligence.md` does NOT contain the strings `Skill Library`, `alirezarezvani`, or `claude-skills` — the file is auto-regenerated by the weekly CI cron and the tier appears to have been overwritten in a subsequent refresh. | The article does NOT depend on the CI tier being visible at publish time. The article cites alirezarezvani/claude-skills directly via the GitHub URL. File a follow-up scope-out (see Open Code-Review Overlap below) to re-seed the Skill Library tier into the weekly-CI regeneration template — out of scope for this PR. |
| "Authored via `copywriter` + `content-writer`, fact-checked" | `plugins/soleur/skills/content-writer/SKILL.md` exists and is the canonical blog-article author. `plugins/soleur/agents/marketing/copywriter.md` exists and explicitly redirects blog articles to `content-writer`. `plugins/soleur/agents/marketing/fact-checker.md` exists. | Author flow: `content-writer` primary draft → `copywriter` voice/CTA pass (NOT the redirect — used in editorial-review role) → `fact-checker` agent for citations. PR body documents which agent produced which artifact. |
| "Published to blog with proper SEO/AEO metadata per `seo-aeo` skill" | `plugins/soleur/skills/seo-aeo/SKILL.md` exists with sub-commands `audit`, `fix`, `validate`. Blog template at `plugins/soleur/docs/_includes/blog-post.njk` already emits `BlogPosting` JSON-LD using `jsonLdSafe` filter per #2609 learning. | AC5 invokes `seo-aeo validate` against the built `_site` output. JSON-LD safety is template-enforced — no manual escape required in body. |

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` then checked the planned file paths via standalone `jq --arg`:

- `plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` → no matches
- `knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md` → no matches
- `knowledge-base/product/competitive-intelligence.md` → no matches (file NOT being edited in this PR — see Research Reconciliation row 2 for the deferred re-seed)

**None.** No open scope-outs touch the files this plan modifies. The Skill Library tier re-seed (Research Reconciliation row 2) is filed as a follow-up tracking issue at PR merge time, NOT a code-review issue.

## Domain Review

**Domains relevant:** Marketing (primary), Product (advisory — content references positioning)

### Marketing (CMO)

**Status:** carry-forward from parent #2718.
**Assessment:** The CMO assessment in #2718's body is the source-of-truth directive: "head-to-head count coverage loses every skim-read comparison (235 vs. 68). Category-creation framing wins on our terms." This plan encodes that directive verbatim in AC3 + AC4. No fresh CMO Task spawn is required — the brainstorm/parent-issue assessment is already explicit.

**Brainstorm-recommended specialists:**
- `copywriter` — voice/CTA pass (covered by AC2 + Phase 3 below).
- `content-writer` — primary draft authoring (covered by AC2 + Phase 2 below).
- `fact-checker` — citation verification (covered by AC2 + Phase 4 below).

All three are invoked inline during /work; none is silently skipped.

### Product/UX Gate

**Tier:** none — no new user-facing UI surface. The article ships into an existing blog template (`blog-post.njk`) with established design. No new page route, no new component, no new flow. The mechanical escalation regex (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) does not match the new file path. Skip Product/UX Gate entirely.

## GDPR / Compliance Gate

The canonical regex (schemas, migrations, auth flows, API routes, `.sql` files) does NOT match any file touched. Triggers (a)-(d) also do NOT fire: (a) no new LLM/external-API processing of operator-session-derived data, (b) brand-survival threshold is `none` (not `single-user incident`), (c) no new cron/workflow reads from `knowledge-base/project/learnings/` or `specs/`, (d) one new artifact-distribution surface (the blog post + distribution-content variants) — but the surface is public marketing content with no operator-session-derived data flow. Skip gdpr-gate silently.

## Files to Edit

None.

## Files to Create

| Path | Purpose |
|------|---------|
| `plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` | The article — Eleventy markdown with frontmatter, ~1,400-1,800 words, structured per the section list below. |
| `knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md` | Distribution variants (Discord, X thread, IndieHackers, Reddit, LinkedIn, optional HN) per the `2026-03-24-vibe-coding-vs-agentic-engineering.md` precedent. |
| `knowledge-base/project/specs/feat-one-shot-2729/tasks.md` | Generated from this plan at the Save Tasks step. |

**Glob verification at plan time:**
- `git ls-files | grep -E 'plugins/soleur/docs/blog/.*\.md$' | wc -l` → 28 existing blog `.md` files (verified).
- `git ls-files | grep -E 'knowledge-base/marketing/distribution-content/.*\.md$' | wc -l` → 12 existing distribution-content files (verified).
- `test -f plugins/soleur/skills/seo-aeo/SKILL.md` → exists.
- `test -f plugins/soleur/skills/content-writer/SKILL.md` → exists.
- `test -f plugins/soleur/agents/marketing/copywriter.md` → exists.
- `test -f plugins/soleur/agents/marketing/fact-checker.md` → exists.

## Article Outline

The article body MUST follow this section structure (intentionally non-prescriptive on prose — `content-writer` owns the voice). The structure encodes the category-creation argument across the skim path: header → opener → category definition → exemplar citation → Soleur-shape → reader decision guide → FAQ.

### Header (frontmatter)

- `title: "Skill Libraries vs. Workflow Plugins: Two Shapes of Claude Code Extension"`
- `seoTitle: "Skill Libraries vs. Workflow Plugins: When to Use Each in Claude Code"` (≤ 60 chars target — verify)
- `date: 2026-05-15`
- `description:` 140-160 chars summarizing the two shapes and when each wins.
- `tags: [comparison, category-creation, claude-code, solo-founder]`
- `ogImage: "blog/og-skill-libraries-vs-workflow-plugins.png"` — file does NOT need to exist at PR time; the OG image generation is a separate workflow (verified: existing posts like `2026-05-14-how-to-run-every-department-with-ai-agents.md` ship without the image file in-tree).

### H2 sections (mandatory)

1. **Opener (~120 words)** — Frame the question every Claude Code user eventually asks: "I see two very different shapes of repository when I search for skills — which one do I install?" Cite the official marketplace + claudemarketplaces.com aggregator (per the `2026-04-30-best-claude-code-plugins-2026.md` precedent) as the context. Name the two shapes without naming Soleur yet.
2. **What a Skill Library Is** — Define the portable-library category in its own terms (not as Soleur's negative space): catalog of self-contained skills, breadth-first coverage, intentionally unopinionated about orchestration, pick-and-mix usage, MIT-licensed portability. Cite [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) as the canonical exemplar — the repository that defines the shape. Frame it positively. NO head-to-head count.
3. **What a Workflow Plugin Is** — Define the workflow-plugin category in its own terms: opinionated orchestration across a lifecycle (brainstorm → plan → work → review → compound), agents with cross-domain knowledge-base reads/writes, decisions in session 1 shape what session 50 produces. Frame Soleur as the canonical exemplar of this shape. State what Soleur does — never what claude-skills "lacks".
4. **Why Two Shapes (Not One Hierarchy)** — The category-creation core: these are not competing entries on a leaderboard; they answer different needs. Portable libraries optimize for ecosystem reach and zero-orchestration drop-in. Workflow plugins optimize for opinionated execution across a sustained lifecycle. A solo founder might install both. Use a 2-column attribute table (not a "vs." matrix — use neutral framing like "Optimizes for").
5. **When a Skill Library Wins** — Three concrete user moments where the portable-library shape is the right call (e.g., "you want a one-off Excel cleanup skill", "you're evaluating Claude Code itself", "you have an existing orchestration layer you want to keep"). Be specific. NO hedging.
6. **When a Workflow Plugin Wins** — Three concrete user moments where the workflow-plugin shape is the right call: solo-founder organizational execution, compounding cross-domain knowledge, lifecycle gates from brainstorm to compound. Reference Soleur's existing CaaS framing via internal link to `/company-as-a-service/`.
7. **They Stack** — Brief section noting the two shapes are not mutually exclusive. The framing parallels the `2026-03-19-soleur-vs-cursor.md` "they stack" pattern (different layers, no conflict). One paragraph max.
8. **FAQ** (3-5 Q&A pairs) — questions like: "Is alirezarezvani/claude-skills a competitor to Soleur?" (Answer: no, different category — exemplar of the portable-library shape that Soleur intentionally is not). "Can I use both?" (Yes, at different layers). "Why isn't there a count comparison?" (Counts compare scope of the catalog; the two products answer different questions). The FAQ MUST follow the FAQPage JSON-LD inline-block convention or omit JSON-LD entirely — per copywriter sharp edge on `2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md`, the safe path is to let the blog template's BlogPosting JSON-LD handle structured data and skip inline FAQPage JSON-LD in body. **Default: skip inline FAQPage JSON-LD; rely on `blog-post.njk` `BlogPosting` only.**

### Word budget

Target ~1,400-1,800 words total. The 8 existing `soleur-vs-*` posts cluster around this range (verified: `2026-05-07-soleur-vs-crewai.md` is ~1,500 words including the 8-row comparison table).

## Implementation Phases

### Phase 0 — Preconditions (5 min)

- [ ] 0.1 Verify Eleventy build is currently green on this branch: `npm run docs:build` from repo root (resolves to `npx @11ty/eleventy` per `package.json` `scripts.docs:build`). If build is already broken at HEAD, abort and surface to operator. **DO NOT use `bun run build`** — that script does not exist in `package.json` (verified at deepen-time: only `test`, `docs:dev`, `docs:build` are defined). The `npm run docs:build` invocation is portable across bun/npm because it resolves the same Eleventy CLI.
- [ ] 0.2 Verify `plugins/soleur/skills/content-writer/SKILL.md`, `plugins/soleur/agents/marketing/copywriter.md`, `plugins/soleur/agents/marketing/fact-checker.md`, `plugins/soleur/skills/seo-aeo/SKILL.md` all exist. Re-run the existence checks from `Files to Create > Glob verification`.
- [ ] 0.3 Read `knowledge-base/marketing/brand-guide.md` Voice + Identity sections — `content-writer` Phase 0 already enforces this; verify the file is present and readable.
- [ ] 0.4 Read parent issue body via `gh issue view 2718 --json body` and extract the CMO directive verbatim for AC3/AC4 enforcement.

### Phase 1 — Outline approval (15 min)

- [ ] 1.1 Invoke `skill: soleur:content-writer "Skill libraries vs. workflow plugins" --outline "<the 8-section outline above>" --audience "solo founders evaluating Claude Code extensions" --headless` to generate a draft outline expansion. The skill enforces brand-guide voice and Eleventy frontmatter. The `--headless` flag auto-accepts when citations all PASS — if any FAIL, the skill's headless fallback removes/replaces failed claims and re-runs.
- [ ] 1.2 Verify draft outline includes all 8 H2 sections in the order specified.

### Phase 2 — Primary draft (30-45 min)

- [ ] 2.1 `content-writer` generates the article body section-by-section. Each H2 is gated on the previous having been written (sequential, not parallel — voice consistency).
- [ ] 2.2 First-pass self-check against AC3 (no head-to-head counts) and AC4 (no competitor framing) BEFORE handing to `copywriter`. Run `grep -nE '\b(68|235|235\+)\b|competitor|competing|vs\.|versus|head-to-head' <draft-path>` and read every match — fix or justify each in the same pass.

### Phase 3 — Copywriter voice + CTA pass (15 min)

- [ ] 3.1 Spawn `copywriter` agent via Task with prompt: "Review the attached blog draft for brand-voice compliance and CTA clarity. Reference `knowledge-base/marketing/brand-guide.md` Voice + Identity. Do NOT rewrite — apply minimal voice corrections and ensure the CTA (typically an internal link to `/company-as-a-service/`) is present and clear. Return the corrected markdown."
- [ ] 3.2 Apply the corrections inline. Re-run the Phase 2.2 grep gates.

### Phase 4 — Fact-checker citations (15 min)

- [ ] 4.1 Spawn `fact-checker` agent via Task with the draft and explicit list of external citations (typically the alirezarezvani/claude-skills GitHub URL + any market-context citations like the official marketplace or claudemarketplaces.com).
- [ ] 4.2 For each citation, `fact-checker` returns PASS / SOURCED / UNSOURCED / FAIL. FAIL → remove the claim or replace with a verified alternative. SOURCED with web.archive.org/web/* fallback is acceptable for ephemeral pages but NOT for the canonical alirezarezvani/claude-skills URL (which must be live).
- [ ] 4.3 Write the citation table into the PR body (per AC2).

### Phase 5 — SEO/AEO validation (10 min)

- [ ] 5.1 Run the Eleventy build: `npm run docs:build` (canonical command; resolves to `npx @11ty/eleventy`).
- [ ] 5.2 Run validators directly: `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` AND `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site`. Equivalent: `skill: soleur:seo-aeo validate` (the skill's `validate` sub-command wraps both scripts). Both scripts exit 0 on success, 1 on any check failure.
- [ ] 5.3 Fix any validation failures in-source (frontmatter `description` length 140-160 chars, `seoTitle` ≤ 60 chars, `ogImage` field present, JSON-LD parseability — the template handles this automatically, so only body-content `</script>` collisions would break it). Iterate until clean.
- [ ] 5.4 **Keyword density check (manual, not scripted)**: compute occurrences of "skill library" and "workflow plugin" across the article body. Target 5-7 occurrences each in a ~1,500-word article (0.3-0.4% density per `2026-03-05-eleventy-blog-post-frontmatter-pattern.md`). If either keyword has < 3 or > 10 occurrences, revisit with `content-writer` for a density tune.

### Phase 6 — Distribution content variants (30 min)

- [ ] 6.1 Invoke `skill: soleur:social-distribute` against the published article path. The skill generates per-platform variants (Discord, X thread, IndieHackers, Reddit, LinkedIn, optional HN) and writes the persistent content file to `knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md`.
- [ ] 6.2 Run `bash scripts/lint-distribution-content.sh <path>` — exit 0.
- [ ] 6.3 Verify the distribution-content `channels: discord, x, bluesky, linkedin-company` (Hacker News is operator-gated, not in the cron channel list).

### Phase 7 — PR body + commit (15 min)

- [ ] 7.1 Stage all created files: `git add plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md knowledge-base/project/plans/2026-05-15-content-category-creation-skill-libraries-vs-workflow-plugins-plan.md knowledge-base/project/specs/feat-one-shot-2729/tasks.md`.
- [ ] 7.2 Commit with conventional-commit prefix `content:` (NOT `feat:` — this is marketing content, not a code feature). Message body summarizes the category-creation framing and cites the parent #2718.
- [ ] 7.3 PR body MUST include:
  - `## Changelog` section (per plugin AGENTS.md pre-commit checklist) with the new blog post listed under "New content".
  - `## Citation Table` from Phase 4.3.
  - `Closes #2729` reference.
  - `Ref #2718` (parent tracking issue — NOT `Closes` since #2718 has other in-flight children).
  - **Note**: No `semver:*` label is required for content-only PRs (verify against existing precedent — the `2026-04-30-best-claude-code-plugins-2026.md` PR for the same scope).

### Phase 8 — Follow-up issue (5 min, post-merge)

- [ ] 8.1 File a tracking issue: "docs(ci): re-seed Skill Library tier in competitive-intelligence.md weekly regeneration template". Body cites this PR + #2728 + commit 31cb987c. Labels: `domain/marketing`, `chore`, `priority/p3-low` — **all three verified to exist via `gh label list --limit 200` at deepen-time**. The label `content` also exists if a finer-grained tag is desired. `seo` and `infrastructure` were initially considered and rejected — neither exists. This is the deferred follow-up from Research Reconciliation row 2 — captures the drift without expanding this PR's scope.

## Research Insights

### Best Practices (precedents in this repo)

- **Title pattern.** All 8 existing `soleur-vs-*` posts use `Soleur vs. <Vendor>: <Differentiator>` — explicitly avoided here. The closest non-`vs.` precedent is `2026-04-30-best-claude-code-plugins-2026.md` (`Best Claude Code Plugins 2026: The Extensions Worth Installing`) and `2026-04-23-knowledge-compounding-in-ai-development.md`. Use a similar non-comparative shape: `Skill Libraries vs. Workflow Plugins: Two Shapes of Claude Code Extension`. The internal `vs.` here is between categories (not products) and explicitly resolved as "two shapes" in the subtitle.
- **Frontmatter contract.** Per `blog.json`: `layout` and `ogType` are auto-inherited. Required per-post fields (verified against `2026-05-07-soleur-vs-crewai.md`): `title`, `seoTitle`, `date` (ISO), `description`, `ogImage` (path relative to `images/`), `tags` (list). Optional: `updated`, `pillar`. The site uses Jean Deruelle as author via `site.author` — never declared per-post.
- **JSON-LD safety.** `blog-post.njk` already emits `BlogPosting` JSON-LD using the `jsonLdSafe` filter (`jsonLdSafe` strips `</script>`, U+2028, U+2029 per `2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`). No body-level `BlogPosting` JSON-LD is needed and would create a duplicate-schema warning (per `2026-03-05-eleventy-blog-post-frontmatter-pattern.md`).
- **FAQPage JSON-LD (if added).** Inline FAQPage is allowed and standalone (different `@type` so no duplicate). HOWEVER — per copywriter sharp edge `2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md`, the JSON-LD `<script>` block terminator MUST be a literal `</script>`. Inside JSON string values, escape `</` → `<\/`. Wrong placement (terminating with `<\/script>`) leaves the element open and absorbs the rest of the body. **Recommended default: skip inline FAQPage JSON-LD entirely; let the natural FAQ section render as plain markdown.** This sidesteps the entire escape-collision class.
- **Internal-link CTAs.** The CaaS pillar page lives at `{{ site.url }}/company-as-a-service/` — use this exact form (Nunjucks variable interpolation, not a hardcoded URL). Existing precedent: `2026-05-07-soleur-vs-crewai.md` lines 14/30.
- **Stat-template variables.** The footer/body stats are provided by `_data/stats.js` as `{{ stats.agents }}`, `{{ stats.skills }}`, `{{ stats.departments }}`. The plan's article SHOULD reference these (not hardcoded numbers) where Soleur scale needs naming. Hardcoded counts go stale.

### Performance Considerations

- **Eleventy 11ty build cost.** Existing site has 28 blog posts; adding one new post is ~50ms incremental build time. No perf gate.
- **JSON-LD payload.** `blog-post.njk` BlogPosting block adds ~600 bytes gzipped per page. Adding an FAQPage block would add ~200 bytes per Q&A pair. Recommend skipping inline FAQPage (per the safety note above) — also keeps payload smaller and avoids the AEO ranking dilution that can occur when FAQPage competes with the parent BlogPosting for rich-result eligibility.

### Edge Cases

- **`fact-checker` returns FAIL on the alirezarezvani repo URL.** Mitigation: the URL is the canonical exemplar — if it 4xx/5xxs, do NOT swap to `web.archive.org`. Pause and surface to operator. The article's premise depends on a live category exemplar.
- **`seoTitle` exceeds 60 chars after a copy-pass that adds context.** Mitigation: `seoTitle` is decoupled from `title`. Treat the SEO title as a structural constraint (≤ 60 chars), and tune `title` for editorial flow.
- **Distribution-content slug collision.** Verified at deepen-time: 12 existing files, none of them match `2026-05-15-skill-libraries-vs-workflow-plugins`. Slug is unique.
- **`content-writer` Phase 0 brand-guide check.** The skill aborts if `knowledge-base/marketing/brand-guide.md` is missing — verified present in this worktree at deepen-time.

### References (verified)

- `plugins/soleur/docs/blog/blog.json` — directory data file (layout + ogType cascade).
- `plugins/soleur/docs/_includes/blog-post.njk` — template emitting `BlogPosting` JSON-LD with `jsonLdSafe` filter (lines 12-49).
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — SEO validator (corrected from `seo-validate.sh`).
- `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh` — CSP validator (sibling gate).
- `plugins/soleur/skills/content-writer/SKILL.md` — primary blog-article author.
- `plugins/soleur/skills/social-distribute/SKILL.md` — distribution-content variant generator (Phase 9 writes the file).
- `plugins/soleur/agents/marketing/copywriter.md` — voice/CTA editorial pass (blog articles redirect to `content-writer`).
- `plugins/soleur/agents/marketing/fact-checker.md` — citation verification.
- `scripts/lint-distribution-content.sh` — repo-root deterministic linter (verified path).
- `knowledge-base/marketing/brand-guide.md` — Voice + Identity contract.
- `knowledge-base/project/learnings/2026-03-05-eleventy-blog-post-frontmatter-pattern.md` — frontmatter inheritance, JSON-LD duplication risk, keyword density target.
- `knowledge-base/project/learnings/2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md` — FAQPage script-terminator escape rule.
- `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md` — why `jsonLdSafe` is required (already template-enforced).
- `knowledge-base/project/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` — brand-guide contract pattern.

## Test Strategy

This is content; the relevant "tests" are deterministic grep/lint/build gates that run as part of CI on the docs change-class:

| Gate | Command | Failure mode |
|------|---------|--------------|
| Eleventy build | `npm run docs:build` (resolves to `npx @11ty/eleventy`) | Frontmatter parse error, broken Nunjucks include, JSON-LD escape failure, missing `jsonLdSafe` filter on user-controlled string |
| seo-aeo validate | `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` + `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` (equivalent: `skill: soleur:seo-aeo validate`) | Title > 60 chars, missing meta description, OG image not declared, broken JSON-LD, missing canonical URL |
| distribution-content lint | `bash scripts/lint-distribution-content.sh <path>` | Forbidden tokens, UTM markers, brand-rule violations |
| AC3 grep gate | `grep -nE '\b(68|235|235\+)\b\|skill count\|skills count' <article>` returns 0 | Head-to-head count slipped in |
| AC4 grep gate | `grep -nE '(competitor\|competing\|vs\.\|versus\|head-to-head)' <article>` returns 0 sentences naming alirezarezvani / claude-skills | Competitor framing slipped in |

No new test framework is added (the existing `scripts/lint-distribution-content.sh` and `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` are the canonical gates).

## Risks & Sharp Edges

- **Risk: `content-writer` Phase 0 fails if `brand-guide.md` is missing or stale.** Mitigation: Phase 0.3 reads the brand guide explicitly. If missing, abort and surface — do not draft without the voice baseline.
- **Risk: `fact-checker` flags the alirezarezvani repo URL as 4xx/redirect.** Mitigation: Phase 4.2 fallback to `web.archive.org/web/*` is acceptable for context citations but NOT for the canonical exemplar URL — if the GitHub URL goes down, the article's category-exemplar premise is invalidated and the PR pauses until the URL recovers or the framing is restructured around a different exemplar.
- **Risk: AC3 over-matches if "68" or "235" appears in an unrelated context (e.g., a year, an unrelated count).** Mitigation: the grep gate reads every match before declaring pass — `grep -nE` is for surfacing, not for auto-rejection. The CMO directive is the semantic gate; the grep is a forcing function to bring every numeric token into view.
- **Risk: SEO `seoTitle` ≤ 60 chars constraint clashes with a natural-language title that already encodes the category-creation argument.** Mitigation: `seoTitle` is decoupled from `title`. Use a punchier SEO form ("Skill Libraries vs. Workflow Plugins: When to Use Each in Claude Code") while keeping the article's display `title` slightly longer if needed.
- **Risk: `social-distribute` headless flow forgets the brand-guide rule "Competitor criticism or comparisons -- state what Soleur does, never what others lack" when generating per-platform variants.** Mitigation: AC4's grep gate ALSO runs against the distribution-content file post-generation. Re-run the same grep over the distribution-content variants — any "competitor", "vs.", "head-to-head" hit in a sentence naming alirezarezvani / claude-skills is a fix-inline.
- **Risk: a future Eleventy build silently emits a redirect stub at the legacy URL if the permalink scheme changes.** Mitigation: per the `2026-04-28-learning-sharp-edges-need-tracking-issues-not-memory.md` learning, the verification gate `test -f _site/blog/<slug>/index.html` MUST contain the canonical path. AC1 does this. No `redirects.njk` edit is required (verified — new page, no URL migration).
- **Sharp edge: the article ships under `plugins/soleur/docs/blog/` but is conceptually marketing content. The change-class loader treats `plugins/soleur/docs/**` as docs-only when the diff is markdown-only.** Verify via `.claude/hooks/session-rules-loader.sh` if uncertain — the SessionStart hook resolves the class. Distribution-content file under `knowledge-base/marketing/distribution-content/` is also docs-only.
- **Sharp edge: PR title MUST NOT contain `Soleur vs.`** — the 8 existing `soleur-vs-*` PRs anchor that title shape to competition framing. Use `content:` prefix and `Skill libraries vs. workflow plugins` (no `Soleur` prefix in the title).
- **Sharp edge: frontmatter MUST NOT redeclare `layout` or `ogType`.** `blog.json` cascades these. Adding either to the new post creates duplicate Eleventy data layers and (per `2026-03-05-eleventy-blog-post-frontmatter-pattern.md`) is the canonical mis-step. Verify before commit: `grep -E '^(layout|ogType):' plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` MUST return zero lines.
- **Sharp edge: do NOT add inline `BlogPosting` JSON-LD in body markdown.** `blog-post.njk` emits it from frontmatter. A duplicate `@type: BlogPosting` script in body triggers schema-validation warnings and competes for rich-result eligibility. Inline FAQPage IS allowed but is intentionally deferred per the Research Insights FAQPage note.
- **Sharp edge: do NOT invoke `content-writer --headless` in this PR.** The headless flow auto-accepts UNSOURCED citations if `fact-checker` fails to load — a silent-degradation path. Phase 1.1 invokes `content-writer` interactively (or with explicit user approval gates), and Phase 4 spawns `fact-checker` as an explicit Task — both surface failures rather than swallow them.

## Alternative Approaches Considered

| Alternative | Why rejected |
|-------------|--------------|
| Author as a `soleur-vs-claude-skills` post matching the existing 8-post pattern | Directly violates the CMO directive in #2718. The `soleur-vs-*` title shape pre-frames the article as competition. Wrong framing axis at skim-read time. |
| Add the article to `case-study-*` instead of a standalone blog post | Case-study format is wrong shape — case studies are first-person "we built X and shipped Y" narratives. Category-creation is third-person definitional content. |
| Skip the distribution-content file and only ship the blog post | The CMO line item in #2718 implicitly requires distribution (the brainstorm + parent issue treat content as a launch, not just an asset). Skipping distribution leaves the article undiscoverable. |
| Include a comparison matrix table | Tables auto-frame as competition. Use a 2-column "Optimizes for" attribute table at most — never a "vs." matrix. |
| Re-seed the Skill Library tier in `competitive-intelligence.md` in the same PR | Expands scope past the CMO line item. The CI doc is auto-regenerated by the weekly cron — the right fix is the regeneration template, not a one-shot file edit. Deferred to Phase 8 follow-up issue. |

## Out of Scope / Non-Goals

- Re-seeding the Skill Library tier into `knowledge-base/product/competitive-intelligence.md` — deferred to a follow-up issue (Phase 8) because it requires changes to the weekly-CI regeneration template, not just the artifact.
- Authoring OG images (`blog/og-skill-libraries-vs-workflow-plugins.png`) — separate workflow, not gating per existing precedent.
- Posting to Hacker News — HN is operator-gated (anti-automation), not in the social-distribute cron channel list.
- Authoring additional category-creation pieces for other portable-library competitors — this is the first article in a potential series; subsequent pieces are out of scope.
- Updating `knowledge-base/marketing/content-strategy.md` to add this article to the content-gap table — strategy doc updates are a separate maintenance pass.

## PR Body Template

```markdown
## Summary

Category-creation blog post: "Skill Libraries vs. Workflow Plugins: Two Shapes of Claude Code Extension."

Reframes the Soleur vs. alirezarezvani/claude-skills comparison on the axis of category shape (portable library vs. workflow plugin), not skill count. Cites alirezarezvani/claude-skills as a category exemplar — not a competitor.

Closes #2729. Ref #2718.

## Changelog

**New content:**
- `plugins/soleur/docs/blog/2026-05-15-skill-libraries-vs-workflow-plugins.md` — long-form article (~1,500 words).
- `knowledge-base/marketing/distribution-content/2026-05-15-skill-libraries-vs-workflow-plugins.md` — Discord / X / Bluesky / LinkedIn variants.

## Citation Table

(populated from Phase 4.3)

## Test Plan

- [ ] `npm run docs:build` succeeds.
- [ ] `skill: soleur:seo-aeo validate` passes.
- [ ] `bash scripts/lint-distribution-content.sh <path>` exits 0.
- [ ] AC3 + AC4 grep gates return zero.
```

## Plan Self-Consistency Check

- The article's section count (8 H2 sections) is consistent with the word budget (1,400-1,800) — ~200 words per H2 on average, with the FAQ being shorter.
- The AC count (10 ACs split pre-/post-merge) is consistent with the file-count surface (2 new files + 1 follow-up issue).
- No aggregate numeric target is asserted that would require a per-item sum to align (no "≥N bytes saved" / coverage / perf claim).
- Phase ordering: contract-changing edits (none — no schema/return-code/signature changes) come before consumers — trivially satisfied. Phase ordering is content-flow ordering: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-15-content-category-creation-skill-libraries-vs-workflow-plugins-plan.md. Branch: feat-one-shot-2729. Worktree: .worktrees/feat-one-shot-2729/. Issue: #2729. PR: <pr-number>. Plan reviewed, content authoring next.
```
