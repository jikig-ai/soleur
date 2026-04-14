---
title: kb-search frontmatter faceting
date: 2026-04-14
issue: 2211
branch: feat-kb-search-faceting
status: draft
---

# Spec: kb-search Frontmatter Faceting

## Problem Statement

The `kb-search` skill is grep-only across `knowledge-base/`. On the learnings corpus (386 files, 1.9 MB), grep is fast (~15 ms) but returns noisy result sets when cross-referencing during `/compound`. Agents waste tokens filtering irrelevant matches. The real friction is result-set noise, not query latency — vector/BM25 approaches are overkill at this corpus size and carry high adoption cost.

Learning files already carry validated YAML frontmatter (`tags`, `category`) but no existing tooling consumes those fields for filtering.

## Goals

1. Agents can filter `kb-search` results by `--tag` and `--category` before grep runs, cutting noise in related-docs lookups.
2. When an agent passes an invalid tag/category, they get a one-line hint pointing to the autocomplete artifact so they can self-correct in one round-trip.
3. The existing `/kb-search <keyword>` plain path stays unchanged — no breaking change.
4. Compound's Related Docs Finder documents the faceted-query pattern so future invocations use it when applicable.
5. Index generation stays under the pre-commit perf budget (currently 1.27s).

## Non-Goals

- No vector DB, embeddings, or BM25 index.
- No new runtime dependencies (stay on Node + Bash).
- No replacement of `grep` as the underlying search mechanism.
- No strict enum enforcement of tag/category values.
- No retroactive normalization of existing learning frontmatter.
- No multi-tag OR/AND logic beyond a single `--tag` value per query.
- No fuzzy matching (Levenshtein / "did you mean?") — the autocomplete artifact is the self-service correction path.
- No handling of YAML-spec-compliant edge cases that don't appear in the current corpus: commas inside quoted tag values, `tags: null`, unicode tags requiring locale-aware case folding. If encountered, skip silently per TR6.

## Functional Requirements

- **FR1** — `kb-search` accepts `--tag <value>` flag. Matches files where the frontmatter `tags:` array contains `<value>` (case-insensitive).
- **FR2** — `kb-search` accepts `--category <value>` flag. Matches files where frontmatter `category:` equals `<value>` (case-insensitive).
- **FR3** — `--tag` and `--category` can combine with each other and with a positional keyword argument (AND semantics). Example: `/kb-search --category performance-issues csrf`.
- **FR4** — When `--tag` or `--category` value is not in the autocomplete artifact, the skill returns an empty result block plus a single hint line: `"No matches. Valid values: knowledge-base/kb-tags.txt (or kb-categories.txt)."` No fuzzy matching.
- **FR5** — When `--tag` or `--category` matches, the skill returns matching files in the same format as the existing keyword search output (title + path).
- **FR6** — `scripts/generate-kb-index.sh` emits two sibling artifacts: `knowledge-base/kb-tags.txt` and `knowledge-base/kb-categories.txt`. Each contains sorted unique values, one per line, lowercased.
- **FR7** — `kb-search` SKILL.md documents both flags with at least one example per flag plus one combined example.
- **FR8** — `compound-capture/SKILL.md` Step 3 documents the faceted-query pattern and when to prefer it over raw grep.
- **FR9** — `--tag` and `--category` are each independently optional; any combination is valid (tag-only, category-only, tag+category, flag(s)+keyword, keyword-only, neither).
- **FR10** — Duplicate flag usage (`--tag a --tag b`) errors with usage hint.
- **FR11** — Unknown flags (e.g., `--taag`) error with an explicit usage line listing supported flags.
- **FR12** — When `kb-tags.txt` / `kb-categories.txt` are missing at query time, the skill returns an actionable error: `"Autocomplete artifacts missing. Run \`bash scripts/generate-kb-index.sh\` to regenerate."` No crash, no silent empty.
- **FR13** — Tag/category values are treated as literals during content matching (fixed-string, not regex). `--tag n+1` matches literal `n+1`, not `n` followed by `1`.
- **FR14** — Faceted queries (`--tag` / `--category`) scope to `knowledge-base/project/learnings/` only. Other KB subtrees are skipped for facet lookups.
- **FR15** — For tag-only or category-only queries (no keyword), output is title + path per file. No content snippet.

## Technical Requirements

- **TR1** — Frontmatter parsing uses `awk '/^---$/{c++; next} c==1'` idiom (per `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`). No new YAML dependency. No `sed` range expressions.
- **TR2** — `generate-kb-index.sh` extension preserves `xargs -P4 -n100` parallel batching (per `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`). Runtime must stay under 5s on the current corpus (baseline: 1.27s).
- **TR3** — Case-insensitive comparison: lowercase both user input and stored values.
- **TR4** — Autocomplete artifacts are committed to git, regenerated deterministically, under 5 KB each.
- **TR5** — `kb-search` default path (keyword-only) is byte-identical to pre-change behavior.
- **TR6** — Tolerate known corpus drift: files without frontmatter, empty `tags: []`, quoted values, inline form (`tags: [a, b]`), block form (`tags:\n  - a`). Silently skip malformed entries.
- **TR7** — Index generator strips quotes and lowercases before dedup.
- **TR8** — Filter stage uses `grep -Fx` (fixed-string whole-line) against the autocomplete artifact. Content matching uses `grep -F`. No regex interpretation.
- **TR9** — Parallel writes from `xargs -P4` use per-worker temp files (via `mktemp`) to avoid append races. Concatenate in the main process after all workers complete.
- **TR10** — Block-form awk parser exits block-state on the next non-indented line matching `^[a-z_]+:` (new frontmatter key). Prevents swallowing sibling frontmatter keys as tag values on malformed files.
- **TR11** — Shell regex uses POSIX character classes (`[[:space:]]`), not `\s`. Ensures BSD (macOS) compatibility for developer machines.

## Out of Scope (tracked elsewhere if needed)

- Reconciling the `problem_type` enum (compound-capture) vs freeform `category` asymmetry.
- Claude-ranked grep / haiku reranking.
- Per-file reverse lookup index.
- Retroactive frontmatter normalization.
- Stale-artifact detection (artifact exists but out-of-date vs latest learnings).

## Test Scenarios

All scenarios are **bats** tests unless explicitly labeled otherwise.

- **TS1 (bats)** — Inline form (`tags: [a, b, c]`) extraction produces three separate tag entries, lowercased, quote-stripped.
- **TS2 (bats)** — Block form (`tags:\n  - a\n  - b`) extraction produces the same output as TS1 for equivalent content.
- **TS3 (bats)** — Malformed frontmatter: file with no leading `---`, file with missing `tags:` field, `tags: []` empty array → all skipped silently, no crash, exit 0.
- **TS4 (bats)** — Case-fold dedup: fixtures with `Eager-Loading`, `eager-loading`, `"eager-loading"` produce one entry in `kb-tags.txt`.
- **TS5 (bats)** — Missing `kb-tags.txt` at query time: `kb-search --tag foo` run with artifact removed produces actionable error containing `scripts/generate-kb-index.sh`. Exit non-zero.
- **TS6 (smoke)** — `bash scripts/generate-kb-index.sh` on the full corpus completes in under 5s (median of 3 runs). Artifacts exist, are sorted, unique, lowercased.
- **TS7 (smoke)** — `/kb-search --tag <existing-tag>` returns a non-empty title+path list for a known tag in the current corpus. Confirms end-to-end wiring.

## Acceptance Criteria (from #2211 + refinements)

- [ ] `kb-search` accepts `--tag` and `--category` flags (FR1, FR2)
- [ ] Flags combine with each other and with keyword (AND) (FR3, FR9)
- [ ] Miss produces hint pointing at the artifact (FR4)
- [ ] Generator emits `kb-tags.txt` and `kb-categories.txt` (FR6)
- [ ] Compound's Related Docs Finder documents the pattern (FR8)
- [ ] kb-search SKILL.md documents flags with examples (FR7)
- [ ] Duplicate flag, unknown flag, missing artifact each produce explicit errors (FR10, FR11, FR12)
- [ ] Fixed-string matching, not regex (FR13, TR8)
- [ ] Scope is learnings/ only (FR14)
- [ ] Default kb-search path unchanged (TR5)
- [ ] `xargs` parallelism preserved; runtime < 5s (TR2, TS6)
- [ ] All TS1–TS7 pass

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-kb-search-faceting-brainstorm.md`
- Existing skill: `plugins/soleur/skills/kb-search/SKILL.md`
- Index generator: `scripts/generate-kb-index.sh`
- Frontmatter schema: `plugins/soleur/skills/compound-capture/references/yaml-schema.md`
- Related docs finder: `plugins/soleur/skills/compound-capture/SKILL.md` (Step 3)
- Reusable awk idiom: `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- Perf pattern: `knowledge-base/project/learnings/2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
- Schema drift tolerance: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
- awk scoping rule: `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
