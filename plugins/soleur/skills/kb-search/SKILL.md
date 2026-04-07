---
name: kb-search
description: "This skill should be used when searching the knowledge base for files matching keywords across all domains."
---

# KB Search

Search the knowledge base across all domains. Returns title matches first (tier 1), then content matches (tier 2).

## Arguments

#$ARGUMENTS

If no arguments are provided, ask: "What would you like to search for in the knowledge base?"

## Execution

### Phase 1: Title Search (Tier 1 — High Relevance)

Search `knowledge-base/INDEX.md` for title matches. INDEX.md contains one line per file in the format `- [Title](path)`.

Run Grep on `knowledge-base/INDEX.md` with the search keywords. Use case-insensitive matching. Each match is a file whose title contains the query terms.

Display tier 1 results:

```text
## Title Matches

1. [Title](knowledge-base/path) — title match
2. [Title](knowledge-base/path) — title match
```

If INDEX.md does not exist, skip to Phase 2 and note: "INDEX.md not found — run `bash scripts/generate-kb-index.sh` to generate it."

### Phase 2: Content Search (Tier 2 — Lower Relevance)

Run Grep across `knowledge-base/` for the search keywords in file contents. Use case-insensitive matching. Exclude `knowledge-base/INDEX.md` and `knowledge-base/**/archive/**` from results.

Filter out any files already found in tier 1. Display tier 2 results:

```text
## Content Matches

3. [path](knowledge-base/path) — content match (line N: "...context snippet...")
4. [path](knowledge-base/path) — content match (line N: "...context snippet...")
```

### Phase 3: Summary

Cap total results at 20 (tier 1 + tier 2 combined). If more than 20 matches exist, note: "Showing top 20 of N matches. Narrow the query for more specific results."

If zero results, suggest:

- Check spelling
- Try broader or alternative keywords
- Run `bash scripts/generate-kb-index.sh` to ensure INDEX.md is current
