---
title: Knowledge Base Retrieval Improvement
date: 2026-04-07
status: decided
participants: founder, CTO, CPO, CMO, COO
---

# Knowledge Base Retrieval Improvement

## What We're Building

Improved file-based knowledge base retrieval through two components:

1. **Auto-generated INDEX.md manifest** -- a single file listing every KB file with a one-line description extracted from frontmatter. Agents read this to discover what exists. Regenerated automatically on commits (git hook or compound integration).

2. **Cross-domain search skill (`soleur:kb-search`)** -- runs parallel grep across all KB domains with ranked results. Replaces ad-hoc agent grepping with a consistent, discoverable interface. Standardized YAML frontmatter (`tags:`, `domain:`, `created:`) on new files improves grep precision.

## Why This Approach

### The Problem

- 1,653 KB files (~240,000 words, 17 MB) with no search index
- All retrieval is live grep against raw files using keyword overlap with YAML frontmatter
- Cross-category blind spot: a learning filed under `workflow-issues/` won't surface for queries mapped to `runtime-errors/`
- KB viewer UI is a placeholder with no search capability
- Context compaction already causes real problems (skills failing as "unknown" when metadata gets truncated)
- `depends_on` frontmatter exists on only 20 of 1,643 files

### Why Not RAG or PageIndex

Four domain leaders assessed RAG and PageIndex (vectorless, LLM-reasoning-based retrieval) and unanimously recommended against both for now:

| Option | Rejection Reason |
|--------|-----------------|
| **Traditional RAG** | Adds 4+ new components (embedding model, vector store, indexing pipeline, query API). Brand says "no vector DB, no embeddings" -- would require messaging migration across 10+ files. $0-25/month infrastructure + embedding costs. |
| **PageIndex** | LLM-in-the-loop-of-an-LLM anti-pattern -- Claude already has Read/Grep/Glob. Every query is an LLM call ($50-200+/month at 10 users). 0 external users, no measured failure rate to justify the cost. |
| **Improved file-based** | Zero infrastructure, zero cost, days not weeks. Solves discovery (agents don't know what exists) and cross-category search (grep across all domains). Preserves brand claims and KB transparency. |

### CTO's Key Insight

The problem is **discovery** (agents don't know what files exist), not **retrieval** (agents can't semantically match queries). An index file fixes discovery. Consistent frontmatter fixes searchability. At 17 MB / 1,643 files, grep returns results in milliseconds -- this is not a scale that demands vector search.

### Trigger for Reconsidering RAG

When the knowledge base exceeds ~50,000 files or ~500 MB, OR when there is evidence that agents consistently fail to find relevant content despite having a manifest and standardized frontmatter.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Retrieval mechanism | Improved file-based (no RAG, no PageIndex) | Zero cost, zero infrastructure, solves actual bottleneck (discovery not retrieval) |
| Scope | Manifest + cross-domain search skill (Approach 2) | Balances quick wins with cross-category gap closure |
| Frontmatter standardization | New files only (no backfill of 1,643 files) | Backfill is high effort, low urgency -- compound skill enforces on new files |
| RAG/PageIndex | Deferred with tracking issue | Revisit when user base grows or file count exceeds trigger thresholds |
| KB viewer search | Deferred to Phase 3 | Grep-based API is sufficient at current scale, natural home is Phase 3 KB REST API |

## Open Questions

- What should the INDEX.md generation trigger be? Git hook vs. compound integration vs. CI step?
- Should the kb-search skill return ranked results or just file paths? How to rank without embeddings?
- What minimum frontmatter fields to enforce on new files? (`tags`, `domain`, `created` are proposed)
- Should INDEX.md include file size and last-modified date to help agents prioritize?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** PageIndex is an LLM-in-the-loop-of-an-LLM anti-pattern for this use case. Claude Code agents already have native file tools (Read/Grep/Glob) -- adding a retrieval intermediary adds latency, cost, and failure modes without proven benefit. Option C (manifest + frontmatter + search skill) addresses the actual bottleneck (discovery, not retrieval) with zero infrastructure. Trigger for RAG: 50k files or measured evidence of consistent failures despite good metadata.

### Product (CPO)

**Summary:** Two distinct consumers (agents vs. humans) need different solutions. With 0 external users, this is premature optimization -- beta users start with empty KBs. No failure analysis exists to prove retrieval quality is the bottleneck. Recommends improving metadata now and evaluating retrieval engines during Phase 3 when the KB REST API is being designed.

### Marketing (CMO)

**Summary:** Brand guide (line 293) explicitly states "No vector DB, no embeddings." 6+ competitive articles are built on the "simple, transparent, git-tracked" narrative. Traditional RAG would require messaging migration across 10+ files. PageIndex preserves all existing claims. Improved file-based retrieval is the marketing-safe path and opens a content opportunity ("how we scaled without embeddings").

### Operations (COO)

**Summary:** Current approach costs $0. PageIndex: $50-200+/month at 10 users (every query and index update is an LLM call). RAG: $0-25/month (dominated by vector DB hosting). If retrieval is needed later, Supabase pgvector is the zero-new-vendor path (already in stack, free tier, RLS for multi-tenant). BYOK implications are critical -- retrieval costs through user API keys need the usage indicator (3.6) to ship concurrently.
