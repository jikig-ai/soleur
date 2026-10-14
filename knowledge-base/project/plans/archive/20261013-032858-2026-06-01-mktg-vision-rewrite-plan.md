# Plan — `/vision/` voice rewrite: demote internal codenames (#3993)

**Branch:** `feat-one-shot-mktg-vision-rewrite-3993`
**Source:** `plugins/soleur/docs/pages/vision.njk`
**Audit:** `knowledge-base/marketing/audits/soleur-ai/2026-05-18-content-audit.md` §1 (`/vision/`)
**Brand guide:** `knowledge-base/marketing/brand-guide.md` §Don't ("startup jargon", "over-explain")

## Problem

`/vision/` reads as an internal strategy memo. It uses four internal codenames /
metaphors as proper nouns that filter out non-technical readers (founders,
journalists, investors) and leak into AEO extraction:

- **"vessel"** — metaphor-as-jargon (same register as "synergy"/"disrupt").
- **"Swarm of Agents"** — proper-noun codename ("manage a 'Swarm of Agents'").
- **"The Global Brain"** — proper-noun codename ("Internally called...").
- **"The Decision Ledger"** — proper-noun codename ("Internally called...").

The "Coordination Engine" card uses the same "Internally called..." pattern; it
is not one of the four named codenames but carries the identical inside-baseball
voice, so it gets the same treatment for consistency.

## Constraints (preserve)

- PR B (#4754) added: `last_updated` frontmatter, `summaryRegister: technical`,
  the `{% include "page-freshness.njk" %}` block (stat-led summary + last-updated
  byline). PRESERVE all of it — the rewrite touches prose/headings only.
- Preserve FAQ structure + FAQPage JSON-LD. The FAQ answers do NOT contain any of
  the four codenames (verified), so FAQ parity is unaffected — but if any visible
  FAQ answer changed, the JSON-LD twin must change identically.
- No new CSS/colors/hex. Prose-only edit. `{{ site.url }}` no trailing slash (n/a here).

## Rewrite map (codename → plain description)

| Old (proper-noun / metaphor) | New (lowercase, plain) |
|---|---|
| "Soleur is the vessel that allows those with unique insights to capture the non-linear rewards of the AI revolution." | Audit-recommended 3-sentence rewrite: "Soleur turns judgment and taste into leverage. When code and AI replicate labor at near-zero marginal cost, the founder's unique insight becomes the entire moat. Soleur is the platform that makes one founder's insight scale like a hundred-person team." |
| manage a "Swarm of Agents" instead of a headcount | "agents across every department, working in parallel, instead of a headcount of employees" |
| Internally called "The Global Brain". Soleur selects the best model... | "Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy. Local models for privacy-sensitive data. One orchestrator across every provider." |
| Internally called "The Decision Ledger". A centralized CEO Dashboard... | "A durable record of the decisions your agents make. A centralized CEO Dashboard where the human-in-the-loop reviews, approves, or pivots agent decisions. Human taste at machine speed." |
| Internally called "The Coordination Engine". ... | drop the "Internally called" callout; keep the substance ("A multi-agent hierarchy where lead agents manage specialized teams...") |

Also: "specialized swarms" / "specialized sub-swarms" → "specialized agent
teams" (the lowercase noun "swarm" still reads as internal jargon; the audit
flags "swarm" alongside the proper nouns). Keep "agent swarms" → "agent teams".

Strategic substance (CaaS thesis, leverage, model-agnostic architecture,
human-in-the-loop, milestones, revenue philosophy) is fully retained — no
section removed, page length materially unchanged.

## Optional (audit R3): definitional H2

Audit recommends a "WHAT IS COMPANY-AS-A-SERVICE?" definition section after the
hero. The page already opens with a strong "The Company-as-a-Service Platform"
section whose first paragraph defines the thesis, and the homepage/CaaS pillar
already own that definitional query. Out of scope for #3993 (which is strictly
the codename/metaphor demotion) — skip to keep the change focused.

## Tests (extend `plugins/soleur/test/seo-aeo-drift-guard.test.ts`)

New describe block:
- Absence guard: built `/vision/index.html` must NOT contain proper-noun forms
  `"Global Brain"`, `"Swarm of Agents"`, `"Decision Ledger"`, or the word
  `"vessel"` — via `html.includes(literal)` → assert `false` (no regex needed).
- Positive guard (don't regress B): `/vision/` still renders exactly one
  `.page-summary` and one `.page-meta` "Last updated" block.

CodeQL hygiene: absence checks are pure `html.includes()` — no tag-strip, no
`&amp;` decode, no unanchored `.test()`. Self-check grep before commit.

## Verify

- `npx @11ty/eleventy --output=/tmp/site-vision` exit 0
- `grep -c -E 'Global Brain|Swarm of Agents|Decision Ledger|vessel' /tmp/site-vision/vision/index.html` → 0
- `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh /tmp/site-vision` exit 0
- `bun test plugins/soleur/test/` green
- CodeQL self-check grep clean
