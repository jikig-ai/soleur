# Marketing Strategy Review — Spec

**Issue:** #236
**Branch:** feat-marketing-strategy-review
**Date:** 2026-03-03

## Problem Statement

Soleur lacks a unified marketing strategy document. Existing marketing artifacts (content plan, SEO audits, brand guide, competitive intelligence) are fragmented across multiple files with no cohesive strategy tying them together. The Feb 19 content plan is 100% unexecuted, 7 cascade documents were generated but never committed, and the competitive landscape has shifted with Anthropic's Cowork Plugins launch.

## Goals

- G1: Create a unified marketing strategy document that accounts for current competitive landscape, capacity constraints, and validated moats
- G2: Regenerate and commit all 7 lost cascade documents (content-strategy.md, pricing-strategy.md, 4 battlecards, SEO refresh queue)
- G3: Provide a realistic, phased execution plan that avoids the over-ambition that stalled the Feb 19 plan

## Non-Goals

- NG1: Implementing the strategy (that's follow-up work)
- NG2: Building blog infrastructure (engineering prerequisite, separate issue)
- NG3: Applying SEO copy rewrites (separate execution task)
- NG4: Setting up email capture or conversion funnels

## Functional Requirements

- FR1: Unified marketing strategy document at `knowledge-base/overview/marketing-strategy.md`
- FR2: Content strategy document at `knowledge-base/overview/content-strategy.md`
- FR3: Pricing strategy document at `knowledge-base/overview/pricing-strategy.md`
- FR4: SEO refresh queue at `knowledge-base/marketing/seo-refresh-queue.md`
- FR5: Battlecards for top competitors at `knowledge-base/sales/battlecards/`
- FR6: Strategy must reference existing brand guide positioning and competitive intelligence
- FR7: Execution plan must be phased with explicit capacity assumptions

## Technical Requirements

- TR1: All documents committed to feat-marketing-strategy-review branch
- TR2: Documents follow existing knowledge-base conventions (markdown, YAML frontmatter where applicable)
- TR3: CMO agent orchestrates specialist agents for cascade document generation
- TR4: Strategy document includes a `last_reviewed` field for cadence tracking
