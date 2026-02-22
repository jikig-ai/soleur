# Learning: Domain prerequisites refactor -- table-driven routing and token budget recovery

## Problem

Three blocking issues prevented scaling to new domains:

1. **Token budget at capacity** -- Agent descriptions consumed 2,496 of 2,500 available words, leaving no headroom for new agents.
2. **Brainstorm routing not scalable** -- 258 lines of inline per-domain blocks (assessment, routing, participation sections) made adding each domain expensive (~35 lines of template duplication).
3. **Domain enumeration drift** -- 8 files listed domains without "sales" (added in v2.28.0), creating inconsistent documentation.

## Solution

### Phase 1: Agent Description Trimming

Trimmed 16 agent descriptions from 2,496 to 2,154 words (342 recovered). Key technique: remove verbose filler while preserving disambiguation sentences ("Use X for Y; use this agent for Z"). Two agents were already trimmed from a prior session -- the Edit tool failed silently when the old string didn't match, which was the correct signal to skip them.

### Phase 2: Table-Driven Brainstorm Refactor

Replaced ~258 lines of inline domain blocks with ~125 lines:
- Single Domain Config table: 6 columns (Domain, Assessment Question, Leader, Routing Prompt, Options, Task Prompt) x 6 rows
- 6-step Processing Instructions that interpret the table generically
- Merged brand into marketing (3 options: workshop / include-CMO / skip) reducing 7 rows to 6
- Workshop sections (Brand, Validation) preserved unchanged as named sections referenced by the table

Adding a new domain now requires adding one table row (~3 lines) instead of ~35 lines across three sections.

### Phase 3: Domain Enumeration Fix

Updated 8 files: plugin.json, README.md (x2), AGENTS.md, getting-started.md (2 locations), llms.txt.njk, terms-and-conditions.md. Code review caught 3 additional issues: missing Sales row in README table, stale agent counts in T&C (45->54, 45->46), and stale "Adding a New Domain Leader" checklist step referencing old structure.

## Key Insight

When a markdown command's structure scales linearly with the number of variants (N domains = N inline blocks), refactor to a table-driven config where N domains = N rows. The LLM interprets the table + generic instructions just as reliably as inline blocks, but the maintenance cost drops from O(N * block_size) to O(N * row_size). The critical constraint: preserve exact question text, full option labels, and task prompts in the table cells so routing behavior doesn't change.

## Session Errors

1. **Edit tool "File has not been read yet" (x5)** -- Attempted to edit 5 files without reading them first. The Edit tool requires a prior Read. Fix: always read before editing, especially after context compaction.
2. **Edit old_string mismatch (x2)** -- deployment-verification-agent.md and seo-aeo-analyst.md had already been trimmed in a prior session. The old description string didn't match. This was the correct signal to skip, not an error to fix.

## Prevention

- **Token budget check**: Run `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` before and after any agent changes. Target: under 2,300 (not 2,500) to maintain headroom.
- **Domain enumeration**: When adding a domain, grep for the old domain list pattern across all file types: `grep -ri "engineering, marketing, legal, operations" --include="*.md" --include="*.json" --include="*.njk"`
- **Code review catches drift**: The review agent caught 3 issues that manual inspection missed (README table, T&C counts, AGENTS.md checklist). Always run review before committing multi-file changes.

## Tags

category: logic-errors
module: brainstorm-routing
tags: token-budget, table-driven-config, domain-enumeration, scalability
