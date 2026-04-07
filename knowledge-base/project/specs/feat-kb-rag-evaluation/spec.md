---
title: Knowledge Base Retrieval Improvement
issue: 1739
branch: feat-kb-rag-evaluation
status: draft
created: 2026-04-07
---

# Knowledge Base Retrieval Improvement

## Problem Statement

Soleur's knowledge base (1,653 files, ~240,000 words) has no discovery mechanism beyond ad-hoc grepping. Agents miss relevant context because they don't know what files exist, and cross-category searches fail when files are categorized differently than queries expect. The KB viewer UI has no functional search.

## Goals

- G1: Agents can discover all KB files from a single manifest file
- G2: Cross-domain search returns relevant results regardless of category filing
- G3: New KB files are created with standardized frontmatter for searchability
- G4: Manifest stays current without manual intervention

## Non-Goals

- Backfilling frontmatter on existing 1,643 files (high effort, low urgency)
- Vector/embedding-based retrieval (deferred -- see tracking issue)
- KB viewer search API (deferred to Phase 3)
- PageIndex or LLM-powered retrieval (deferred -- see tracking issue)

## Functional Requirements

- **FR1:** Auto-generated `knowledge-base/INDEX.md` listing all KB files with one-line descriptions extracted from YAML frontmatter `title` or first heading
- **FR2:** INDEX.md includes file path, description, domain, and tags (when available)
- **FR3:** INDEX.md regeneration triggered automatically (git hook, compound integration, or CI)
- **FR4:** `soleur:kb-search` skill that runs parallel grep across all KB domains and returns ranked file paths with context
- **FR5:** Standardized YAML frontmatter template enforced for new files (`tags`, `domain`, `created` at minimum)

## Technical Requirements

- **TR1:** INDEX.md generation must complete in under 30 seconds for 2,000+ files
- **TR2:** kb-search skill must return results in under 10 seconds
- **TR3:** No external service dependencies (no API calls, no vector DB, no hosting)
- **TR4:** Works in both CLI plugin and worktree contexts
- **TR5:** INDEX.md format must be readable by both agents (structured for grep) and humans (scannable)

## Acceptance Criteria

- [ ] `knowledge-base/INDEX.md` exists and lists all KB files with descriptions
- [ ] Running the generation script produces identical output on repeated runs (deterministic)
- [ ] `soleur:kb-search` skill returns relevant results for cross-category queries
- [ ] New files created by compound/brainstorm/plan skills include standardized frontmatter
- [ ] learnings-researcher agent can use INDEX.md to improve discovery
