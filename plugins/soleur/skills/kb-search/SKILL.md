---
name: kb-search
description: "This skill should be used when searching the knowledge base for files matching keywords or YAML frontmatter facets (tag, category) across domains."
---

# KB Search

Search the knowledge base across all domains. Returns title matches first (tier 1), then content matches (tier 2). Optional `--tag` and `--category` flags filter `knowledge-base/project/learnings/` by YAML frontmatter before grep runs, cutting result-set noise during cross-referencing.

## Arguments

<search_query> #$ARGUMENTS </search_query>

Accepted forms:

- `/kb-search <keyword>` — existing behavior, unchanged.
- `/kb-search --tag <value>` — filter learnings by frontmatter `tags:`.
- `/kb-search --category <value>` — filter learnings by frontmatter `category:`.
- `/kb-search --tag <value> --category <value> <keyword>` — combine (AND).

If `$ARGUMENTS` is empty, ask: "What would you like to search for in the knowledge base?"

### Flag Semantics

- Values are matched **case-insensitively** and **as literals** (fixed-string, not regex). `--tag n+1` matches the literal tag `n+1`.
- Duplicate flags (`--tag a --tag b`) error with usage hint.
- Unknown flags (`--taag`) error with usage hint listing supported flags.
- Faceted queries scope to `knowledge-base/project/learnings/` only; other KB subtrees are skipped for facet lookups.
- Tag-only or category-only queries emit `title + path` per file (no content snippet). Combined with a keyword, snippets come from the keyword match.

## Execution

### Phase 0: Parse Arguments

Parse `$ARGUMENTS` into `$TAG`, `$CATEGORY`, and `$KEYWORD`. Track whether each flag was already seen to detect duplicates. On duplicate or unknown flag, emit:

```text
Usage: /kb-search [--tag VALUE] [--category VALUE] [KEYWORD]
```

Then exit without searching.

### Phase 1: Facet Validation (only if `--tag` or `--category` supplied)

Validate that autocomplete artifacts exist. If missing, emit and exit:

```bash
if [ ! -f knowledge-base/kb-tags.txt ] || [ ! -f knowledge-base/kb-categories.txt ]; then
  echo "Autocomplete artifacts missing. Run: bash scripts/generate-kb-index.sh"
  exit 1
fi
```

Validate each supplied value against its artifact (case-insensitive, fixed-string, whole-line). On miss, emit and exit:

```bash
tag_lc=$(printf '%s' "$TAG" | tr '[:upper:]' '[:lower:]')
if [ -n "$TAG" ] && ! grep -Fxq "$tag_lc" knowledge-base/kb-tags.txt; then
  echo "No matches. Valid values: knowledge-base/kb-tags.txt"
  exit 0
fi
```

Same pattern for `--category` against `knowledge-base/kb-categories.txt`.

### Phase 2: Filter Learnings by Frontmatter (only if `--tag` or `--category` supplied)

Walk `knowledge-base/project/learnings/*.md`. For each file, parse YAML frontmatter with the same awk idiom the index generator uses:

```awk
/^---$/ { c++; next }
c != 1 { next }
# then match on ^tags: or ^category:
```

Accept both inline (`tags: [a, b]`) and block (`tags:\n  - a`) forms. Compare values case-insensitively. Collect the surviving file paths.

If both flags are supplied, a file must match BOTH to survive (AND).

### Phase 3: Keyword Search

- **Facet-only (no keyword):** Emit one line per surviving file in `- [Title](path)` form (title read from frontmatter or first `# heading`).
- **Keyword-only (no facets):** Run the existing two-tier search:
  1. Grep `knowledge-base/INDEX.md` for title matches (tier 1).
  2. Grep `knowledge-base/` contents for the keyword (tier 2), excluding INDEX.md and archive/.
- **Facets + keyword:** Apply keyword grep **only** to the facet-filtered file list (not the whole KB). Use `grep -F` (fixed-string).

Missing `INDEX.md` → note and continue with content grep only.

### Phase 4: Display Results

Title matches come first, then content matches. Cap total at 20; if truncated, append:

```text
Showing top 20 of N matches. Narrow the query for more specific results.
```

Zero results → suggest:

- Check spelling
- Try broader or alternative keywords
- For `--tag`/`--category` misses, inspect `knowledge-base/kb-tags.txt` or `kb-categories.txt`
- Run `bash scripts/generate-kb-index.sh` to ensure artifacts are current

## Examples

### Tag filter with keyword

```text
/kb-search --tag eager-loading rails
```

Returns learnings tagged `eager-loading` whose content matches `rails`.

### Category filter alone

```text
/kb-search --category performance-issues
```

Returns all learnings with `category: performance-issues` as title+path.

### Combined facets

```text
/kb-search --tag n+1 --category performance-issues
```

Returns learnings tagged `n+1` AND categorized as `performance-issues`.

### Miss with hint

```text
/kb-search --tag nonexistent-tag
# Output:
# No matches. Valid values: knowledge-base/kb-tags.txt
```

The agent can read the artifact in a follow-up round-trip to self-correct.

## Output Format

```text
## Title Matches

1. [Title](knowledge-base/path) — title match
2. [Title](knowledge-base/path) — title match

## Content Matches

3. [Title](knowledge-base/path) — content match (line N: "...snippet...")
```

Tag-only or category-only output uses the `## Title Matches` block only, without snippets.
