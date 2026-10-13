---
title: "chore(content): growth-audit #5302 four-issue content cleanup bundle"
type: chore
date: 2026-06-15
branch: feat-one-shot-5302-growth-audit-content-fixes
lane: cross-domain
issues:
  - 2670
  - 2673
  - 3179
  - 2073
parent: 5302
---

# chore(content): growth-audit #5302 four-issue content cleanup bundle

## Overview

Bundle four independent domain/marketing content fixes referenced by the weekly growth-audit issue #5302 into one cleanup PR. All four are `domain/marketing` + `type/chore` + `priority/p2-medium` (except #2073 which is labeled P1 in its title). The PR body uses `Closes #N` for each sub-issue.

This is a **pure docs/content change** — Eleventy `.njk`/`.js`/`.md` files under `plugins/soleur/docs/` plus one new marketing knowledge-base markdown file. No application code (`apps/*`), no infrastructure, no migrations, no regulated-data surfaces.

The four fixes:

1. **#2670 — /skills/ page.** Fold the literal "Uncategorized" H2 into existing categories, and ensure a one-paragraph inline definition of "agentic engineering" sits near the H1.
2. **#2673 — /community/ page.** Reframe "active community" → "early builder community, small by design" across the three mirror sites (prose, FAQ answer, FAQPage JSON-LD).
3. **#3179 — AEO citation-monitoring tracker.** Create `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md` scaffolding the 8 anchor queries with citation/non-citation columns across ChatGPT / Perplexity / Claude.ai / Gemini.
4. **#2073 — zero listicle presence.** CODE-fixable half: create our own "Best AI tools for solo founders 2026" listicle blog post (+ bespoke OG image). Outreach half (contact top-10 listicle authors) is an external operator/outbound action — surfaced explicitly as a post-merge operator follow-up, NOT silently deferred.

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-06-15. **Passes:** verify-the-claim (10 claims, all confirmed), growth-strategist AEO review, code-simplicity review. Gates 4.6/4.7/4.8/4.9 all pass (User-Brand Impact present; pure-docs → Observability N/A; no PAT-shaped vars; no UI surface).

**Key changes applied:**
1. **Tracker (#3179) made measurable, not just counted** — added `Cited source / URL`, `Mention type` (cited-with-link/named-no-link/absent), per-run `date`, `Position`, and `Competitors named` columns; pinned a fixed run-weekday. A binary cited/not-cited cell cannot explain AEO Presence movement (the reason #3179 exists).
2. **Listicle (#2073) guardrails** — explicit "do NOT rank Soleur #1 on its own list"; lead seoTitle with the head keyword `AI tools for solo founders`; require a sibling-blog internal link; FAQ+FAQPage schema promoted from optional to default; at least one independent (non-Anthropic) citation.
3. **Agentic-engineering definition (#2670)** — the existing `:24` first sentence is a *negation* ("is more than…"), not a definition; the light-tightening now fronts the affirmative `[Term] is [definition]` form for AEO extractability.
4. **Simplified** — cut LARP/duplicate ACs, removed the bespoke /community/ extract-and-diff harness (lockstep edit + spot-check instead), folded Phase 5 into the AC block (5 phases → 4), removed the redundant ALL-posts ogImage loop (the seo-aeo test covers it repo-wide).
5. **Count reconciliation** — fixed a numeric inconsistency (header "82" was a stale 2026-06-01 snapshot); authoritative live counts pinned: 85 on disk, 66 mapped, 19 unmapped.

**Verify-the-claim results:** all 10 load-bearing claims confirmed against the codebase — existing agentic-engineering definition at `skills.njk:13/:24`; data-driven Uncategorized at `skills.js:142/:184-192`; exactly 19 unmapped skills (re-derived, list matches); "active community" at `community.njk:47/:173/:213`; no existing `citation-monitoring.md`; no existing "best AI tools for solo founders" listicle; ogImage `.toBe(0)` at `seo-aeo-drift-guard.test.ts:709`; `blog.json` supplies `layout`/`ogType`; `marketing` is in `SANCTIONED_DIRS` (`kb-domain-allowlist-guard.sh:50`); PIL 12.1.1 available + existing OG PNGs are 1200×630.

## Research Reconciliation — Spec vs. Codebase

The issue descriptions were paraphrased into the one-shot arguments. Two paraphrase gaps were caught at plan-write time by reading the actual files:

| Spec/argument claim | Codebase reality | Plan response |
|---|---|---|
| #2670: "add a one-paragraph inline definition of agentic engineering near the H1" | An inline definition **already exists** at `plugins/soleur/docs/pages/skills.njk:13` (H1) + `:24` (defining paragraph: "Agentic engineering is more than writing code with AI. It is a structured methodology where skills orchestrate agents, tools, and institutional knowledge into repeatable workflows…"). | Down-scope: do NOT add a duplicate paragraph. Verify the existing definition is intact and AEO-extractable (a self-contained, quotable first sentence near the H1). Make at most a light tightening so the first sentence reads as a standalone definition; if already adequate, leave it. The substantive #2670 work is the skills.js category fix below. |
| #2670: "rename/fold the literal Uncategorized H2" — implies an editable H2 in the `.njk` | The "Uncategorized" H2 is **data-driven**, not literal. `plugins/soleur/docs/_data/skills.js:142` assigns `SKILL_CATEGORIES[name] \|\| "Uncategorized"`; `:184-192` appends an "Uncategorized" category object when any skill is unmapped; `skills.njk:41-60` renders one `<h2 class="category-title">` per category. The map header says "Last verified: 2026-06-01 (4 categories, 82 skills)" but **19 skills added since** are unmapped. | Fix the data, not the template: add the 19 unmapped skills to `SKILL_CATEGORIES` so the "Uncategorized" bucket is never populated. Verified unmapped set (live `git`/`comm` against on-disk `SKILL.md` `name:` fields, 2026-06-15): `admin-ip-refresh, drain-labeled-backlog, feature-tweet, flag-create, flag-set-role, gdpr-gate, incident, kb-search, linear-fetch, model-launch-review, operator-digest, pencil-setup, provision-cloudflare, provision-doppler, provision-github, provision-hetzner, trigger-cron, user-set-role, ux-audit` (19). |

Premise Validation: all five GitHub issues (#5302, #2670, #2673, #3179, #2073) verified `OPEN` via `gh issue view` (2026-06-15); none closed by a merged PR. The cited source audits exist on disk (`knowledge-base/marketing/audits/soleur-ai/2026-04-19-content-audit.md`, `2026-05-04-content-plan.md` §P2 #31, line 250/290). No stale premise. The `#3179` tracker file does not yet exist (`find` returned nothing) — confirmed a *create*, not an *edit*.

## User-Brand Impact

**If this lands broken, the user experiences:** a broken Eleventy build (no `_site/` output → docs deploy fails) or a visibly malformed `/skills/`, `/community/`, or `/blog/<new-post>/` page. The most likely concrete artifact: a new blog post that fails the `seo-aeo-drift-guard` test suite (missing `ogImage`, missing/duplicated `BlogPosting` JSON-LD) and blocks CI, or a `/community/` page whose visible FAQ text drifts from its FAQPage JSON-LD (Google rich-result parity break).

**If this leaks, the user's data is exposed via:** N/A — no user data, secrets, auth, or PII surfaces are touched. All edits are public marketing content and a public knowledge-base tracker scaffold (no real citation data, no operator-identifying info).

**Brand-survival threshold:** none.

(Threshold `none`; the diff touches no sensitive path per the preflight Check 6 canonical regex — `.njk`/`.js`/`.md` docs + a marketing KB file only. No `requires_cpo_signoff`.)

## Implementation Phases

### Phase 1 — #2670: /skills/ category fix + agentic-engineering definition

**Files to edit:**

- `plugins/soleur/docs/_data/skills.js` — add the 19 unmapped skills to the `SKILL_CATEGORIES` object (lines 12-86), each into one of the four existing categories. Proposed assignments (final call belongs to the implementer reading each skill's purpose; these are the defaults):
  - **Workflow:** `admin-ip-refresh`, `drain-labeled-backlog`, `flag-create`, `flag-set-role`, `incident`, `kb-search`, `linear-fetch`, `provision-cloudflare`, `provision-doppler`, `provision-github`, `provision-hetzner`, `trigger-cron`, `user-set-role`
  - **Review & Planning:** `gdpr-gate`, `model-launch-review`, `ux-audit`
  - **Content & Release:** `feature-tweet`, `operator-digest`
  - **Development:** `pencil-setup`
  - Update the category-count comments in the file header (`// Content & Release (17)` etc.) and the "Last verified" line (`// Last verified: 2026-06-01 (4 categories, 82 skills)`) to `2026-06-15` with the new per-category and total counts. **Authoritative counts (live, 2026-06-15):** 85 skill dirs with a `SKILL.md` on disk; 66 currently category-mapped; 19 unmapped (the set above). After mapping all 19, the four categories sum to 85. (The header's "82 skills" was the 2026-06-01 snapshot and is stale — do not propagate it.)
- `plugins/soleur/docs/pages/skills.njk` — front the **affirmative** definition of agentic engineering near the H1 for AEO extractability. The current `:24` first sentence is a *negation* ("Agentic engineering is more than writing code with AI."), not a definition; an answer engine wants the `[Term] is [definition]` shape as the quotable unit. P2 micro-edit (within the "light tightening" scope): reorder so the standalone first sentence reads affirmatively, e.g. *"Agentic engineering is a structured methodology where skills orchestrate agents, tools, and institutional knowledge into repeatable workflows — more than writing code with AI."* Keep the existing external `<a href>` (Karpathy link) and verify the sentence still reads cleanly as plain text when the anchor is stripped. Do NOT add a duplicate paragraph. Bump `last_updated:` (`:7`) to `2026-06-15` and keep `date:` aligned per the `page-freshness.njk` contract (the include is used at `:18`).

**Acceptance criteria (Phase 1):**
- After `npx @11ty/eleventy`, `grep -c 'Uncategorized' _site/pages/skills.html` returns `0` (no Uncategorized H2 or pill rendered) — this is the load-bearing post-condition. (A typo'd category key would re-trigger the Uncategorized bucket, so this single check also catches misspelled additions.)
- `_site/pages/skills.html` contains the affirmative agentic-engineering definition sentence near the H1 (the `[Term] is [definition]` form).

### Phase 2 — #2673: /community/ reframe (3 mirror sites)

**Files to edit:**

- `plugins/soleur/docs/pages/community.njk` — replace "active community" framing at all three mirror locations. The three sites MUST stay codepoint-identical in their shared phrasing where they overlap (FAQ answer ↔ JSON-LD), per the FAQPage parity guard:
  - `:47` community-summary prose — `"…Company-as-a-Service platform with an active community across Discord, GitHub, and X."` → reframe to e.g. `"…Company-as-a-Service platform with an early builder community — small by design — across Discord, GitHub, and X. We are early; the community is small and growing, and we would rather say so than overstate it."` (final copy belongs to the copywriter; keep "source-available (BSL 1.1)" / "converts to Apache-2.0 four years after each release" framing intact and do NOT introduce "open source" for Soleur per `marketing-content-drift.test.ts`).
  - `:172-174` FAQ answer for "Is there a Soleur community?" — reframe "Soleur has an active community across Discord, GitHub, and X/Twitter…" to the early-builder framing.
  - `:209-214` FAQPage JSON-LD `acceptedAnswer.text` for the same question — **must match the visible `<summary>`/answer text codepoint-for-codepoint** after Nunjucks autoescape (`&#39;`, `&quot;`). The JSON-LD here is a literal string (not interpolated); if any prose contains `</`, route it through `| jsonLdSafe`. Since this block is static text, the safest path is to keep the answer free of `</` and Unicode separators and edit both surfaces in lockstep.

**Acceptance criteria (Phase 2):**
- `grep -ci 'active community' _site/community/index.html` returns `0` (rendered post-condition).
- The visible FAQ answer for "Is there a Soleur community?" and the FAQPage JSON-LD `acceptedAnswer.text` are codepoint-identical. This is achieved by editing both surfaces in lockstep (they are adjacent in the file); spot-verify by eye after the edit. No bespoke diff harness — the long-term parity guard belongs in a separate issue extending `#3171` to `/community/`, not inline in a copy PR.
- The reframed copy keeps a concrete, extractable claim (names the three channels: Discord, GitHub, X) — do not replace the claim with only a hedge.
- `marketing-content-drift.test.ts` still passes (`bun test plugins/soleur/test/marketing-content-drift.test.ts`) — confirms no banned "open source"/"Apache-2.0 licensed"-for-Soleur claim was introduced.

### Phase 3 — #3179: AEO citation-monitoring tracker scaffold

**Files to create:**

- `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md` — a markdown tracker scaffold (NOT an Eleventy page; lives in knowledge-base, not `docs/`). Structure:
  - Frontmatter: `title`, `category: marketing`, `tag: aeo`, `last_updated: 2026-06-15` (matches sibling audit-file convention; optional but consistent).
  - Purpose paragraph: this tracker logs whether Soleur is cited by AI answer engines for its 8 anchor queries, measured weekly, to move the AEO **Presence** dimension (the binding constraint per `2026-05-04-content-plan.md` line 290: "Citation-monitoring queries tracked 0 → 8 weekly").
  - **Methodology** section: how to run each test — paste the query verbatim into a **fresh/unconditioned session** (logged-out where possible, no memory, no prior turns) on each engine; **pin a fixed run weekday** (e.g. every Monday) so the cadence does not silently die; record the result per the column schema below. State the honest limitation: 8 queries × 4 engines, hand-run, n=1 per cell — this is **directional, not statistical**.
  - **The 8 anchor queries** (verbatim from the issue / content-plan #31): `AI agents for solo founders`, `Company-as-a-Service`, `Soleur vs Cursor`, `Soleur vs Devin`, `agentic engineering platform`, `replace contractors with AI`, `AI cofounder platform`, `billion-dollar one-person company`.
  - **Log table** — ONE format (do not litigate alternatives): one table per weekly run, headed with the **run date**, columns `Query | Engine | Mention type | Cited source / URL | Position | Competitors named | Notes`. Required because a binary cited/not-cited cell cannot explain Presence movement (the whole reason #3179 exists):
    - **Mention type** — `cited-with-link` / `named-no-link` / `absent` (a named-but-unlinked brand is a real-but-weaker Presence signal; collapsing it into "not cited" understates progress).
    - **Cited source / URL** — *which* page the engine attributed (soleur.ai homepage vs. a specific blog post vs. a third-party listicle). This is the single most load-bearing field: it is the only way to know whether the #2073 listicle or the third-party outreach drove a citation, and it directly maps to the Presence rubric (own-site vs third-party mention).
    - **Position** — `first-result` / `mentioned` / `buried` (cheap; distinguishes winning from merely appearing).
    - **Competitors named** — free competitive-intel byproduct, especially for the two `Soleur vs *` queries.
    - Include a pre-seeded "**2026-06-15 baseline run**" block with all cells `TBD` so the cadence and column shape are obvious (a `TBD` placeholder is the correct end-state for an unfilled human-run tracker — this is a data-collection scaffold, not a code field).
  - A short **"How this feeds AEO scoring"** note linking back to `2026-05-04-content-plan.md` (Presence dimension 12/25 → ≥15/25, exit criterion line 290: "Citation-monitoring queries tracked 0 → 8 weekly").

**Acceptance criteria (Phase 3):**
- File exists at the exact path `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md`.
- All 8 anchor queries appear verbatim (`grep -c` each).
- All 4 engine names appear as columns/sections (`ChatGPT`, `Perplexity`, `Claude.ai`, `Gemini`).
- Markdown table syntax is valid (renders; pipe-escaped where needed).
- The `kb-domain-allowlist-guard` does not flag a new top-level KB dir — the path is under the already-sanctioned `knowledge-base/marketing/`, so no allowlist edit is required.

### Phase 4 — #2073: own "Best X" listicle blog post (CODE half)

**Files to create:**

- `plugins/soleur/docs/blog/2026-06-15-best-ai-tools-for-solo-founders-2026.md` — a ranked "Best X" listicle in the established blog format (model on `2026-04-30-best-claude-code-plugins-2026.md`).
  - **Frontmatter (required):** `title`, `seoTitle` (target the SERP window ~120-160 chars per `seo-aeo-drift-guard.test.ts:40`; **lead with the head term `AI tools for solo founders`** — the higher-volume Commercial query per the content-plan keyword research — not only the "Best…2026" framing), `description`, `date: 2026-06-15`, `ogImage: "blog/og-best-ai-tools-for-solo-founders-2026.png"` (**MANDATORY** — `seo-aeo-drift-guard.test.ts:709` asserts zero imageless posts, `.toBe(0)`; #4753), `tags:` (e.g. `solo-founder`, `solopreneur`, `agentic-engineering`, `ai-agents`, `company-as-a-service`).
  - **Target keyword:** primary `AI tools for solo founders`; secondary `solopreneur AI stack`. (Slug `best-ai-tools-for-solo-founders-2026` is chosen over the content-plan's `ai-tools-for-solo-founders-2026` because the "best" prefix matches listicle SERP intent better; the seoTitle still leads with the bare head term.)
  - **Do NOT re-declare** `layout` or `ogType` — inherited from `blog/blog.json` (`layout: blog-post.njk`, `ogType: article`); the layout auto-emits `BlogPosting` + author JSON-LD. Re-declaring duplicates the schema (learning `2026-03-05-eleventy-blog-post-frontmatter-pattern.md`).
  - **Body:** a genuine ranked list of the best AI tools/platforms for solo founders in 2026, applying the brand voice (lead with what becomes possible; declarative; no banned words — no "AI-powered", "just", "simply", "assistant"/"copilot", "leverage AI", "disrupt"; no emojis).
    - **Do NOT rank Soleur #1 on its own list.** A vendor listicle that crowns itself is the textbook over-claim and answer engines (and readers) discount it. Rank genuinely useful third-party tools honestly (Cursor, Claude Code, Linear, etc.) and place Soleur as a *distinct organization-layer / Company-as-a-Service category* that "raises the ceiling" beyond single-purpose tools — the same honest-comparison shape the Best-Claude-Code-Plugins post uses. Even-handedness makes the page more citation-worthy.
    - Note the scope honestly: this closes the *content/Structure* half of #2073. AI engines citing "best AI tools for solo founders" overwhelmingly quote *third-party* listicles, not a vendor ranking itself — so the *Presence* half is closed by the operator-outreach follow-up below, not by this post. The PR's `Closes #2073` covers the code half only.
    - Include 3-6 inline external citations (Carta solo-founders report, Anthropic Claude Code docs, MCP spec, etc.) per the content-plan authority directive; at least one must be a genuinely independent source (not all Anthropic-owned).
    - Internal-link to existing pillar pages (`/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/solo-founder-ai-stack/`) AND to at least one **sibling blog post** (e.g. `/blog/best-claude-code-plugins-2026/` or a relevant `/blog/soleur-vs-*`) so the post is not an orphan in the pillar/cluster graph (content-plan pillar/cluster contract).
  - **FAQ block (default, not optional):** add a visible `<details class="faq-item">` FAQ — a "Best AI tools for solo founders" post is a prime conversational-query target, and FAQPage JSON-LD is a P1 site-wide AEO lever per the content-plan (required on all cluster posts). Hand-write a matching `FAQPage` JSON-LD `<script type="application/ld+json">` block using `| jsonLdSafe | safe` on any answer text containing `</` or Unicode separators (learnings `2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`, `2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md`: escape `</` → `<\/` *inside* answer strings only; the block-closing `</script>` stays literal). Keep question set codepoint-identical between `<summary>` and JSON-LD `name`.
  - **Avoid Eleventy authoring traps** (learning `2026-04-21-fact-checker-file-scope-plus-eleventy-footnote-gap.md`): no markdown footnotes `[^1]` (not wired — use parenthetical caveats); use ATX headings WITH a space (`## Heading`).

- `plugins/soleur/docs/images/blog/og-best-ai-tools-for-solo-founders-2026.png` — a bespoke **1200×630** OG image generated with **Python PIL** (PIL 12.1.1 confirmed available), matching the existing fleet's deterministic vector-art aesthetic: dark `#1A1A1A` background, gold `#C9A962`–`#DCBE6E` lines/geometry, post title text (learning `2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md` — do NOT use Gemini; the fleet is precise vector geometry, AI raster art looks inconsistent). A throwaway generation script may live in `/tmp`; only the PNG is committed.

**Acceptance criteria (Phase 4):**
- `npx @11ty/eleventy` builds clean; `_site/blog/best-ai-tools-for-solo-founders-2026/index.html` exists.
- `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` passes — exercises (and is the canonical guard for): zero imageless posts (`.toBe(0)`, so the new ogImage must resolve), `BlogPosting` schema present, `Person.knowsAbout` topical array, `/blog/` card byline for the new post, ogImage threaded to the rendered filename. (No separate hand-rolled ogImage-404 loop needed — this test covers it repo-wide.)
- `bun test plugins/soleur/test/jsonld-escaping.test.ts` passes (FAQ JSON-LD block).
- The committed OG PNG is `1200x630` (`file plugins/soleur/docs/images/blog/og-best-ai-tools-for-solo-founders-2026.png` → `1200 x 630`).
- Soleur is NOT ranked #1 on its own list (honest third-party ranking; Soleur as the org-layer category).
- Brand-voice / banned-word screen happens in the copywriter pass at /work (not a mechanical AC) — the listicle is a prose deliverable; the copywriter checks for "AI-powered", "just", "simply", "copilot"/"assistant", "leverage AI", "disrupt", emojis, and confirms the source-available (BSL 1.1) framing.

### Bundle-wide verification (run once, not a separate phase)

The whole-bundle build + test commands live in the Pre-merge Acceptance Criteria below — there is no standalone "Phase 5" (a content PR runs these once). Two non-AC sanity notes for the implementer: (a) `cq-eleventy-critical-css-screenshot-gate` is satisfied without action because this PR introduces no new above-the-fold selectors to `base.njk`/page templates (it edits data + copy + a blog post reusing existing classes); confirm no new class names were added to `skills.njk`/`community.njk`. (b) `git status --porcelain` should show only the intended files changed.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **#2670:** `_site/pages/skills.html` contains zero "Uncategorized" headings/pills; `skills.js` maps all on-disk skills; agentic-engineering definition present near H1; `last_updated` bumped.
- [ ] **#2673:** `_site/community/index.html` contains zero "active community" strings; community framing is "early builder community, small by design"; FAQ visible answer ↔ FAQPage JSON-LD are codepoint-identical; `marketing-content-drift.test.ts` passes.
- [ ] **#3179:** `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md` exists with all 8 anchor queries verbatim and all 4 engines as columns/sections.
- [ ] **#2073 (code half):** new blog post builds and passes `seo-aeo-drift-guard.test.ts`; bespoke 1200×630 PIL OG image committed; ogImage-404 audit clean for all posts; no banned brand words.
- [ ] `npx @11ty/eleventy` builds clean; full affected test set green.
- [ ] PR body uses `Closes #2670`, `Closes #2673`, `Closes #3179`, `Closes #2073` (one line each) and `Ref #5302`.
- [ ] PR body includes a `## Changelog` section and the PR carries `semver:patch` (docs/content only — no new components).

### Post-merge (operator / outbound)
- [ ] **#2073 outreach half (NOT code — surfaced, not deferred):** identify and contact the authors of the top ~10 high-traffic listicles for "best AI tools for solo founders", "best Claude Code plugins", "best AI agent platforms", "AI tools for solopreneurs", "solopreneur tech stack". Provide each a brief: product name, one-line description, differentiator (Company-as-a-Service organization layer), link to soleur.ai and the new listicle post. **Automation: not feasible** — this is relationship-based outbound (personalized author email/DM, often gated by contact forms or social DMs requiring human judgment on tone and targeting); it is a genuine operator/outbound-marketing motion, not a code change. Owned by the `outbound-strategist` / `copywriter` agents at the operator's direction. The `/soleur:ship` summary MUST list this as an explicit follow-up. **Decision for the implementer:** default to `Closes #2073` for the code half + create a new `domain/marketing` outreach-tracking issue titled "Listicle outreach: contact top-10 'best AI tools for solo founders' authors" linking the new post; this avoids leaving #2073 open indefinitely on an outbound motion while keeping the work visible. (Alternative if the operator prefers: keep #2073 open and use `Ref #2073` for the code half.)

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed (plan-time assessment; pipeline auto-accept)
**Assessment:** All four fixes are marketing/content surface owned by the CMO domain. #2670 and #2673 are on-site copy/data corrections; #3179 is an AEO measurement scaffold (Presence dimension); #2073 is content+outbound. The plan applies brand-guide voice rules (banned words, source-available framing) and the content-plan's authority/citation directives. A copywriter pass is recommended at /work time for the new blog post body and the /community/ reframe copy (the prose is the deliverable). spec-flow-analyzer is N/A — no user flows.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none — N/A (no UI-surface file: edits are to `_data/*.js`, page copy, a blog markdown post, and a KB markdown file; no `components/**/*.tsx`, no `app/**/page.tsx`, no new interactive surface)
**Pencil available:** N/A (no UI surface)

#### Findings

The mechanical UI-surface override does not fire — no path in Files-to-Create/Edit matches the UI-surface glob superset (`.tsx` components, `app/**/page.tsx`). The `.njk`/`.md` edits modify existing public pages' *copy and data*, not interactive UI structure. Product gate is ADVISORY at most; auto-accepted in pipeline. A copywriter review is folded into the /work pass for the two prose deliverables (blog post + /community/ reframe) per the Content Review Gate signal.

## Infrastructure (IaC)

None. No new server, service, cron, secret, vendor account, DNS record, TLS cert, or firewall rule. Pure docs/content change against the already-provisioned GitHub-Pages docs deploy. Phase 2.8 skipped.

## Open Code-Review Overlap

None. No open `code-review`-labeled issue references `plugins/soleur/docs/_data/skills.js`, `pages/skills.njk`, `pages/community.njk`, the new blog post path, or `knowledge-base/marketing/audits/soleur-ai/`.

## Risks & Mitigations

- **JSON-LD ↔ visible-copy drift on /community/.** The FAQPage `acceptedAnswer.text` (`:213`) must match the visible answer (`:173`) codepoint-for-codepoint after Nunjucks autoescape. Mitigation: edit both in lockstep; add an explicit extract-and-diff AC; keep the answer free of `</`, U+2028/U+2029. The existing `#3171` parity guard does NOT cover `/community/`, so manual verification is load-bearing.
- **New blog post fails the ogImage zero-tolerance test.** `seo-aeo-drift-guard.test.ts:705-709` asserts `.toBe(0)` imageless posts. Mitigation: Phase 4 commits a bespoke 1200×630 PIL OG image as a hard deliverable, not optional.
- **Duplicate BlogPosting JSON-LD** if the post re-declares `layout`/`ogType`. Mitigation: inherit from `blog.json`; frontmatter carries only `title/seoTitle/description/date/ogImage/tags`.
- **Skill category misassignment** (a skill landing in a surprising category). Low impact (cosmetic grouping). Mitigation: implementer reads each skill's `description:` before assigning; defaults provided above are reasonable.
- **Banned brand words slipping into the listicle.** Mitigation: explicit grep AC in Phase 4; copywriter review at /work.
- **OG image aesthetic inconsistency.** Mitigation: PIL vector art matching the `#1A1A1A`/gold fleet palette, per learning; not Gemini raster.

## Observability

N/A — pure static-docs/content change. No server-side code, no new error paths, no runtime failure modes, no infrastructure. The only "failure mode" is a broken build, caught synchronously by `npx @11ty/eleventy` + the `bun test` suite + the `deploy-docs` GitHub Actions workflow (which runs the build and the screenshot gate on every push). No liveness signal, error-reporting destination, or discoverability test applies. (Phase 2.9 skip condition: pure-docs, no Files-to-Edit under `apps/*/server`, `apps/*/src`, `apps/*/infra`, or `plugins/*/scripts/`.)

## Test Scenarios

1. Build the site; assert `/skills/` renders 4 categories and no "Uncategorized".
2. Build the site; assert `/community/` has no "active community" and FAQ parity holds.
3. Assert `citation-monitoring.md` exists with 8 queries + 4 engines.
4. Build the site; assert the new blog post renders, carries BlogPosting JSON-LD + author byline, and its OG image resolves (no 404).
5. Run `marketing-content-drift`, `seo-aeo-drift-guard`, `jsonld-escaping`, `components` test files — all green.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a stated rationale; the section is complete.
- The `citation-monitoring.md` log cells are intentionally `TBD` placeholders — this is a human-run data-collection scaffold, not a code field, so the `TBD` is the correct end-state for an unfilled tracker, NOT a planning gap.
