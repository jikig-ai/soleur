---
feature: loop-engineering-positioning
issue: 5088
date: 2026-06-12
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Spec: Loop Engineering Positioning Blog (#5088)

## Problem Statement

Addy Osmani's June-2026 "Loop Engineering" essay (Substack + O'Reilly Radar, endorsed by Boris
Cherny and Peter Steinberger) is coining recognized vocabulary for designing systems that prompt
agents autonomously — but it scopes the term to **code**. Soleur runs the same architecture across
every department (marketing, sales, legal, finance, ops). "Loop engineering for your whole company,
not just your codebase" is a free, timely differentiator. The news-hook value decays in ~2-3 weeks.

## Goals

- Publish a brand-consistent blog article adopting "loop engineering" and extending it cross-domain.
- Map Osmani's 5 building blocks + external memory onto Soleur's **actual, shipped** capabilities at
  an honest-hedge posture (no testable over-claim).
- Distribute via `social-distribute` with a news-hook angle.
- Own the "loop engineering" term for AEO before competitors.

## Non-Goals

- **No landing/homepage copy change** (deferred — heavier, needs cross-domain coherence review).
- **No closing of the 2 cross-domain architecture gaps** (autonomous business-domain scheduling +
  cross-domain maker/checker verifiers) — decoupled to a follow-up issue; unlocks a v2 post.
- No claim that scheduled agents or verifier loops run across business domains **today**.
- No "open source" self-claim (Soleur is source-available, BSL 1.1).

## Functional Requirements

- **FR1** — Blog article authored via `content-writer` to `plugins/soleur/docs/blog/2026-06-12-loop-engineering-for-your-whole-company.md` (or content-writer's chosen slug), with Eleventy frontmatter (`title`, `seoTitle`, `date`, `description`, `tags`, optional `ogImage`).
- **FR2** — Body maps all 6 Osmani elements to Soleur, honest-hedge: Worktrees / Skills / MCP connectors / External memory framed as cross-domain today; Automations + maker/checker verifiers framed as "proven in engineering, generalizing outward."
- **FR3** — Block 4 framed as **"MCP connectors"** only; no "plugin" framing of Soleur. MCP claims distinguish 4 git-committed servers from runtime-available ones.
- **FR4** — **Credit-and-extend wall:** an attributed section (Osmani coinage + verbatim Cherny/Steinberger quotes about the term) structurally separated from Soleur claims/CTAs, with an explicit **non-affiliation disclaimer** (not affiliated with or endorsed by Osmani, Cherny, Steinberger, Google, or Anthropic).
- **FR5** — `Article` + `FAQPage` JSON-LD; FAQ includes "Is Soleur affiliated with Addy Osmani / Google / Anthropic?" (disclaimer in AEO-readable form).
- **FR6** — `social-distribute` content file generated for the article (Discord/X/LinkedIn/HN), timeliness-flagged.

## Technical Requirements

- **TR1 (blocking)** — Every quote attributed to a named real person MUST be verbatim and sourced to
  a specific URL, verified by the `fact-checker` agent **before publish**. Paraphrase-as-quotation
  prohibited.
- **TR2 (blocking)** — `legal-compliance-auditor` pre-publish pass for false-endorsement language and
  "open source" leakage against the final draft.
- **TR3** — Article must pass `marketing-content-drift.test.ts` (no Soleur-subject "open source").
- **TR4** — Build green: `cd apps/...docs` Eleventy build succeeds with the new post; component/post
  counts updated if the build asserts them.

## Execution Pipeline

`content-writer` (draft + frontmatter + JSON-LD) → `fact-checker` (TR1 blocking) →
`legal-compliance-auditor` (TR2 blocking) → publish → `social-distribute` (FR6).

## Decoupled Follow-up (separate issue)

Close the 2 cross-domain gaps so a v2 post can claim full autonomous loop engineering honestly:
(1) wire ≥1 business-domain scheduled **agent** cron via the `schedule` skill; (2) add maker/checker
verifier agents to operations/product/support and designate finance/sales pairs.
