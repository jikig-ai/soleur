---
title: "feat: Add Polsia.com to competitive landscape"
type: feat
date: 2026-03-09
semver: patch
---

# feat: Add Polsia.com to Competitive Landscape

## Overview

Add polsia.com to the 6-tier competitive landscape in `knowledge-base/overview/business-validation.md`, then run `/soleur:competitive-analysis` to produce a fresh competitive intelligence scan that includes the new entrant. Polsia was flagged in the 2026-02-27 competitive intelligence brainstorm as needing tier classification but was never added.

## Problem Statement / Motivation

The competitive intelligence brainstorm (`knowledge-base/brainstorms/archive/20260227-164928-2026-02-27-competitive-intelligence-brainstorm.md`) explicitly listed "Polsia.com tier classification" as an open question. The competitive-intelligence agent dynamically reads `business-validation.md` on each scan -- if Polsia is not listed there, it will never be scanned.

Polsia is a direct CaaS competitor: autonomous AI agents (CEO, Engineer, Growth Manager) that plan, code, market, and operate a company 24/7 for $49/month. It covers engineering, marketing, and operations domains with a compounding daily-cycle model. 2,000+ companies on the platform, $1.8M in cash flows. This makes it one of the closest competitors to Soleur's Company-as-a-Service thesis.

## Tier Classification: Tier 3

**Rationale:** Polsia is a Company-as-a-Service / full-stack business platform. It is not a Claude Code plugin (Tier 1), not a no-code agent builder (Tier 2), not an agent framework (Tier 4), and not a DIY coding tool (Tier 5). It does not control the model, API, or distribution surface (not Tier 0). It belongs in Tier 3 alongside SoloCEO, Tanka, Lovable, Bolt, Notion AI, and Systeme.io.

Within Tier 3, Polsia has **Medium-High** overlap with Soleur because:

- Multi-domain coverage: engineering + marketing + operations (3 of 8 Soleur domains)
- Autonomous agent organization with role-based agents (CEO, Engineer, Growth Manager)
- Targets solo founders / small teams explicitly
- Daily compounding cycles (analogous to Soleur's compounding knowledge base)
- $49/month pricing directly in Soleur's target range

**Differentiation from Soleur:**

- Fully autonomous / cloud-hosted (vs. Soleur's local-first, human-in-the-loop)
- No legal, finance, sales, support, or product domains (3 of 8 vs. 8 of 8)
- No Claude Code integration or terminal-first workflow
- No persistent structured knowledge base (daily cycles, not session-compounding documents)
- Proprietary, closed-source platform (vs. Soleur's Apache-2.0 open source)

## Proposed Solution

### Phase 1: Add Polsia to business-validation.md (Tier 3 table)

Add a new row to the Tier 3 table in `knowledge-base/overview/business-validation.md` with:

| Field | Value |
|-------|-------|
| Competitor | `[Polsia](https://polsia.com)` |
| Approach | Autonomous AI company-operating platform. Role-based agents (CEO, Engineer, Growth Manager) run daily cycles of development, marketing, and operations. $49/month. 2,000+ companies. |
| Differentiation from Soleur | Cloud-hosted, fully autonomous (no human-in-the-loop). Covers 3 domains (engineering, marketing, ops) vs. Soleur's 8. No legal, finance, sales, support, or product domains. No structured knowledge base that compounds across domains. No Claude Code integration. Proprietary, closed-source. |

Insert after the Tanka row (alphabetical-ish ordering within the tier, and Polsia's overlap level is comparable to Tanka's).

Update the `last_updated` frontmatter field to `2026-03-09`.

### Phase 2: Run competitive-analysis skill

Run `skill: soleur:competitive-analysis` with `--tiers 0,3` to produce a fresh scan that includes Polsia. The agent reads `business-validation.md` dynamically, so the newly added entry will be picked up automatically.

### Phase 3: Verify output

Confirm that `knowledge-base/overview/competitive-intelligence.md` contains a Polsia row in the Tier 3 overlap matrix after the scan completes.

## Acceptance Criteria

- [ ] Polsia appears in the Tier 3 table of `knowledge-base/overview/business-validation.md` with correct competitor name, approach, and differentiation
- [ ] `last_updated` frontmatter in `business-validation.md` is set to `2026-03-09`
- [ ] `/soleur:competitive-analysis` scan completes without errors
- [ ] `knowledge-base/overview/competitive-intelligence.md` contains a Polsia entry in the Tier 3 overlap matrix
- [ ] No existing competitor entries are modified or removed

## Test Scenarios

- Given Polsia is added to the Tier 3 table, when the competitive-intelligence agent reads business-validation.md, then Polsia appears in the competitor list for Tier 3 scanning
- Given the competitive-analysis skill runs with `--tiers 0,3`, when the scan completes, then the output report at competitive-intelligence.md includes a Polsia row with overlap level, differentiation, and convergence risk
- Given business-validation.md is edited, when markdownlint runs, then the file passes all lint checks (table formatting, frontmatter structure)

## Non-goals

- Updating the Vulnerabilities or Assessment sections of business-validation.md (those require a full business-validator reassessment)
- Adding Polsia to any other tier -- the classification is Tier 3
- Modifying the competitive-intelligence agent's behavior or the competitive-analysis skill
- Creating battlecards or SEO comparison pages for Polsia (handled by cascade agents during the scan)

## References

- Brainstorm: `knowledge-base/brainstorms/archive/20260227-164928-2026-02-27-competitive-intelligence-brainstorm.md` (open question: "Polsia.com tier classification")
- Business validation: `knowledge-base/overview/business-validation.md` (target file, lines 69-83 Tier 3 table)
- Competitive intelligence report: `knowledge-base/overview/competitive-intelligence.md` (scan output)
- Competitive analysis skill: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Competitive intelligence agent: `plugins/soleur/agents/product/competitive-intelligence.md`
- Learning: `knowledge-base/learnings/2026-02-27-competitive-intelligence-agent-implementation.md`
- Polsia Product Hunt: https://www.producthunt.com/products/polsia
- Polsia website: https://polsia.com
