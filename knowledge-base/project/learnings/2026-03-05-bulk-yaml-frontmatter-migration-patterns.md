---
title: Bulk YAML Frontmatter Migration Patterns
date: 2026-03-05
category: documentation
tags:
  - yaml
  - frontmatter
  - migration
  - python
  - metadata-extraction
  - idempotent-scripts
---

# Learning: Bulk YAML Frontmatter Migration Patterns

## Problem

85 of 124 learnings files in `knowledge-base/project/learnings/` lacked structured YAML frontmatter with the required fields (`title`, `date`, `category`, `tags`). An additional 18 had partial frontmatter missing one or more fields. The corpus had grown organically over months with inconsistent metadata: some files used inline `## Tags` sections with `key: value` pairs, others had no metadata at all, and one file (`agent-prompt-sharp-edges-only.md`) lacked a date prefix in its filename.

Without standardized frontmatter, downstream tooling (search, filtering by category/date, validation) could not operate on the learnings corpus reliably.

## Solution

Wrote `scripts/backfill-frontmatter.py` -- a Python migration script using PyYAML that processes all 124 files in a single pass:

1. **Extraction pipeline**: Title from `# H1` headings, date from filename `YYYY-MM-DD-` prefix, tags from inline `## Tags` sections and `tags:` fields in existing partial frontmatter.
2. **Category inference**: Priority-ordered pattern matching against filename slugs (e.g., `eleventy|docs-site` maps to `build-errors`, `gdpr|legal|cla` maps to `legal`).
3. **Frontmatter insertion**: For files with no frontmatter, inserts a complete YAML block before the body. For files with partial frontmatter, augments missing fields without disturbing existing values.
4. **Normalization**: Converts singular `symptom:` keys to `symptoms:` arrays. Strips YAML-unsafe characters (`$()`, `#`, `[]`, `/`) from tag values. Serializes tags with single quotes to avoid nested-double-quote breakage.
5. **Filename fix**: Renames `agent-prompt-sharp-edges-only.md` with a `2026-02-20-` date prefix via `git mv`.
6. **Integrity verification**: Computes MD5 hashes of body content (everything after frontmatter) before and after transformation, aborting if any body is altered.
7. **Idempotency**: Second run detects all 124 files as complete and skips them.

Also updated `.markdownlint.json` to add `front_matter_title: ""` to the MD025 config, preventing false positives where both frontmatter `title:` and body `# heading` exist.

## Session Errors

1. **awk backslash errors** -- Initial attempt used bash+awk+sed for YAML insertion. Backslash escaping in heredocs and awk's limited YAML awareness caused silent corruption. Switched entirely to Python with PyYAML, which eliminated the class of errors.
2. **git stash in worktree** -- Used `git stash` to compare markdownlint counts before/after (violation of AGENTS.md rule). Immediately popped. Correct approach: commit WIP first, then compare.
3. **Review agent timeouts** -- 3 sub-agents exceeded the 120-second TaskOutput limit during review. The review scope (124 files) was too large for a single agent pass. Breaking into smaller batches or using grep-based validation instead of agent review would have been faster.
4. **Invalid YAML tags from extraction** -- 5 files produced invalid YAML because extracted tag values contained nested brackets (`[value]`), unquoted special characters (`$()`, `#`), or comma-separated values that PyYAML interpreted as nested lists. Required a post-processing sanitization step.

## Key Insight

When extracting metadata from semi-structured inline text (like `## Tags` sections with freeform `key: value` lines), the extraction must handle three categories of edge cases:

- **Structural ambiguity**: Comma-separated values within a single field produce nested lists if not explicitly split and flattened before YAML serialization.
- **Character safety**: YAML reserves `[]`, `{}`, `#`, `:`, and other characters. Values containing these must be quoted or stripped.
- **Format variance**: Human-authored metadata uses inconsistent spacing around colons, optional quotes, backtick wrapping, and mixed casing.

Python with PyYAML is significantly safer than bash+sed for bulk YAML transformation because PyYAML handles quoting, escaping, and structural validation automatically. The shell approach fails silently on edge cases that only surface in a handful of files out of 124.

For idempotent migrations specifically: compute a content hash of the portion you must not change (the body), verify it round-trips unchanged, and make the "already complete" detection run first so re-runs are safe and fast.

## Related Learnings

- `2026-02-06-docs-consolidation-migration.md` -- Covers the original migration of docs into `knowledge-base/`. The grep-based reference scanning pattern from that learning applies here (verify all old patterns are eliminated after bulk edits).
- `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` -- Similar bulk-edit-with-verification pattern for legal documents. Shares the "scope all edits first, then apply, then grep-verify" workflow.
- `technical-debt/2026-02-12-plugin-components-untested.md` -- Identified that broken YAML frontmatter silently degrades discovery. This migration directly addresses that risk for the learnings corpus.

## Tags

category: documentation
module: knowledge-base
severity: medium
problem_type: tooling
root_cause: inconsistent-metadata
