---
title: "Strategy Document Review Cadence via Frontmatter Metadata + CI Cron + Dependency Cascade"
category: process-workflows
module: knowledge-management
tags:
  - frontmatter-schema
  - scheduled-ci
  - dependency-cascade
  - strategy-review
  - github-actions
severity: medium
date: 2026-03-23
---

# Learning: Strategy Document Review Cadence System

## Problem

Strategy documents (product roadmap, marketing strategy, pricing, brand guide, competitive intelligence, content strategy) go stale silently when upstream documents change. The business validation update (2026-03-22) — which invalidated CLI/plugin delivery and validated the CaaS thesis — needed to propagate to 6 dependent documents. Without explicit dependency tracking, this cascade happens incompletely: some documents get updated, others don't, and the inconsistency compounds over weeks.

Prior learnings identified pieces of this problem:

- `2026-03-03-cmo-orchestrated-strategy-review-pattern.md` — cascade documents generated during CMO analysis but never committed
- `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — awk-based frontmatter parsing for staleness detection

But no system tied these pieces together into a complete review cadence.

## Solution

Three-layer system:

1. **Frontmatter schema** — 5 standardized fields (`last_updated`, `last_reviewed`, `review_cadence`, `owner`, `depends_on`) applied to all 17 strategy documents in `knowledge-base/{product,marketing,sales}/`. The `depends_on` field creates an explicit dependency graph between documents.

2. **Scheduled CI workflow** — `scheduled-strategy-review.yml` runs weekly (Monday 08:00 UTC), parses frontmatter via awk, computes days since last review against cadence-to-days mapping (monthly=30, quarterly=90), creates GitHub issues for overdue documents with dedup check (skips if open issue already exists).

3. **Event-driven cascade** — When an upstream document changes (e.g., business-validation.md), domain leader sub-agents (CPO, CMO) review all dependent documents in parallel, adding timestamped annotations with delivery pivot findings and updating `last_reviewed`/`last_updated`.

## Key Insight

The generalizable pattern is: **metadata-driven dependency tracking + scheduled staleness detection + event-driven cascade**. The frontmatter `depends_on` field is the critical piece — it makes the implicit dependency graph explicit, enabling both automated detection (CI can trace which documents need review when an upstream changes) and human understanding (anyone reading a document can see what it depends on).

The cascade review pattern (spawn domain leaders in parallel, each annotates their owned documents) is reusable for any future upstream change that needs to propagate — not just business validation updates.

## Related

- [#1005](https://github.com/jikig-ai/soleur/issues/1005) — Feature issue
- `2026-03-03-cmo-orchestrated-strategy-review-pattern.md` — CMO cascade pattern (predecessor)
- `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` — Frontmatter migration approach
- `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — Awk frontmatter parsing pattern
- `2026-02-22-business-validation-agent-pattern.md` — Business validation workshop pattern

## Tags

category: process-workflows
module: knowledge-management
