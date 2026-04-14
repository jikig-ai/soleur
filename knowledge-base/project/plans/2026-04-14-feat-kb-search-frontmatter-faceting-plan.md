---
title: feat - kb-search frontmatter faceting
date: 2026-04-14
issue: 2211
branch: feat-kb-search-faceting
pr: 2212
status: plan
type: feat
---

# Plan: kb-search Frontmatter Faceting

> Implements #2211. Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-kb-search-faceting-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-kb-search-faceting/spec.md`.

## Overview

Add `--tag` and `--category` flags to the `kb-search` skill so agents can filter `knowledge-base/project/learnings/` by YAML frontmatter facets before grep runs, cutting result-set noise during cross-referencing in `/compound`. Extend `scripts/generate-kb-index.sh` to emit two sibling autocomplete artifacts (`knowledge-base/_tags.txt`, `knowledge-base/_categories.txt`). Update `compound-capture/SKILL.md` Step 3 with faceted-query guidance.

- **Effort**: ~5 hours (medium)
- **Stack**: Bash (awk, grep, xargs), markdown SKILL.md files. No new dependencies.
- **Risk**: Low. Extends existing tooling; no user-facing surface; preserves existing perf pattern.

## Context (research consolidated from brainstorm)

- `plugins/soleur/skills/kb-search/SKILL.md` is instructions-only (no backing script). Implementation extends instructions + agent-executed bash.
- `scripts/generate-kb-index.sh` uses `xargs -P4 -n100` parallel batching (1.27s on 386 files; budget 5s). Must be preserved — per learning `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`.
- Frontmatter parsing must use the `awk '/^---$/{c++; next} c==1'` idiom — per learnings `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` and `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`. Never `sed` range expressions (known broken with body `---`).
- Corpus drift is real: both inline (`tags: [a, b, c]`) and block (`tags:\n  - a`) forms exist. Some files have dirty values (space-separated free-form inside brackets). Warn-but-accept + best-effort extraction absorbs this.
- No community overlap: functional-discovery agent confirmed no existing skill does this.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/_tags.txt` | Sorted unique lowercased tags, one per line. Generated artifact, committed to git. |
| `knowledge-base/_categories.txt` | Sorted unique lowercased categories, one per line. Generated artifact, committed to git. |
| `scripts/lib/extract-facets.sh` | Reusable bash library for frontmatter facet extraction. Sourced by `generate-kb-index.sh`. Keeps the main script readable and enables unit-style testing of the extraction logic. |
| `tests/scripts/test-extract-facets.bats` | Bats test for facet extraction covering inline form, block form, missing field, dirty values, empty tags, quoted values, case-fold dedup. |

## Files to Modify

| Path | Change |
|---|---|
| `scripts/generate-kb-index.sh` | Add a second xargs pass (or augment existing pass) that emits `_tags.txt` and `_categories.txt`. Preserve `-P4 -n100` batching. |
| `plugins/soleur/skills/kb-search/SKILL.md` | Add `--tag` / `--category` flag documentation, warn-but-accept "did you mean?" algorithm, error semantics (FR10–FR12), tag-only query support (FR9). |
| `plugins/soleur/skills/compound-capture/SKILL.md` | Update Step 3 (Related Docs Finder) with faceted-query pattern examples. Docs-only. |
| `knowledge-base/project/specs/feat-kb-search-faceting/spec.md` | Already updated in planning phase — no further changes. |

## Implementation Phases

### Phase 1 — Facet extraction library (1h)

1. Create `scripts/lib/extract-facets.sh` exposing two functions:
   - `extract_tags_from_file <path>` — prints tags one per line, lowercased, quote-stripped.
   - `extract_category_from_file <path>` — prints single category value, lowercased, quote-stripped, or empty.
2. Extraction logic:
   - Use `awk '/^---$/{c++; next} c==1'` to isolate frontmatter block. No `sed` range expressions.
   - Detect inline form `tags: [...]` with `grep -E '^tags:\s*\['` and extract comma-separated tokens via `tr ',' '\n' | sed 's/[][]//g'`.
   - Detect block form (`tags:` on its own line followed by `- value` lines) via awk state machine.
   - Strip surrounding `"` / `'` quotes and leading/trailing whitespace.
   - Lowercase output (`tr '[:upper:]' '[:lower:]'`).
   - Silently skip files with no frontmatter (no leading `---`), empty `tags:`, or `tags: []`.
   - Best-effort on dirty values (e.g., `tags: [a, b, c workflow fails...]` — extract comma-separated tokens, tolerate free-form tails).
3. Unit tests via `bats` in `tests/scripts/test-extract-facets.bats`:
   - Inline form
   - Block form
   - Missing frontmatter entirely
   - Missing `tags:` field (frontmatter present, no tags)
   - Empty `tags: []`
   - Quoted values (`"foo"`, `'foo'`)
   - Mixed casing → lowercase output
   - Dirty value tolerance (best-effort, no crash)

### Phase 2 — Index generator augmentation (1h)

1. Edit `scripts/generate-kb-index.sh` to source `scripts/lib/extract-facets.sh`.
2. Add a second pass over the already-batched file list (`xargs -P4 -n100`) that:
   - Calls `extract_tags_from_file` and `extract_category_from_file` per file.
   - Streams values to two temp files (`/tmp/all-tags.txt`, `/tmp/all-categories.txt`).
3. Final step: `sort -u` each temp file into `knowledge-base/_tags.txt` and `knowledge-base/_categories.txt`.
4. Keep the existing `INDEX.md` generation path untouched — facet emission is a new parallel branch, not a rewrite.
5. Verify runtime stays under 5s (current 1.27s). Print timing to stderr when run manually.

**Verification step before committing**: run `bash scripts/generate-kb-index.sh` three times and record median wall-clock time. If >5s, optimize before proceeding.

### Phase 3 — kb-search skill instructions (1.5h)

Update `plugins/soleur/skills/kb-search/SKILL.md` with:

1. **Argument parsing section** documenting:
   - `--tag <value>` — filter by frontmatter tag (case-insensitive, literal match, requires value)
   - `--category <value>` — filter by frontmatter category (same semantics)
   - Both flags independently optional; any combination valid (FR9)
   - Duplicate flag usage → error (FR10)
   - Unknown flag → error with usage line (FR11)
   - Missing autocomplete artifact → actionable error (FR12)
   - Value treated as literal, not regex (FR13)
2. **Algorithm** for the agent to execute when flags are present:

   ```bash
   # Step 1: validate artifacts exist
   test -f knowledge-base/_tags.txt || echo "Run: bash scripts/generate-kb-index.sh"

   # Step 2: warn-but-accept validation
   # Lowercase the user input; compare against lowercased artifact
   tag_input_lc=$(echo "$TAG" | tr '[:upper:]' '[:lower:]')
   if ! grep -Fxq "$tag_input_lc" knowledge-base/_tags.txt; then
     # Find top-3 closest via substring match, then Levenshtein fallback
     # Emit: "No matches. Did you mean: <top3>?"
   fi

   # Step 3: filter file list by frontmatter (uses extract-facets.sh library)
   # Step 4: if keyword also provided, grep -F through survivors
   # Step 5: emit title + path (snippet only when keyword is present)
   ```

3. **Examples** in SKILL.md:
   - `/kb-search --tag eager-loading n+1` (tag + keyword)
   - `/kb-search --category performance-issues csrf` (category + keyword)
   - `/kb-search --tag playwright` (tag only, no keyword → returns title + path list)
   - `/kb-search --tag xyz-unknown` (miss → did-you-mean)
4. **Scope note**: facet queries scope to `knowledge-base/project/learnings/` only (FR14).
5. **Output format note**: tag-only queries return title + path with no snippet (FR15).

### Phase 4 — Compound-capture integration (0.5h)

Update `plugins/soleur/skills/compound-capture/SKILL.md` Step 3 (Related Docs Finder):

1. Add a paragraph introducing the faceted-query pattern for cutting noise.
2. Show the before/after pattern:
   - Before: `grep -r "eager loading" knowledge-base/project/learnings/`
   - After: `/kb-search --tag eager-loading` or `/kb-search --category performance-issues`
3. Guidance on when to prefer facets: when the current learning has identified a specific `category` or `tags` value; when grep returns >10 unrelated matches.
4. Keep grep as the fallback — no breaking change to existing behavior.

### Phase 5 — Validation and docs (1h)

1. Regenerate `_tags.txt` and `_categories.txt` from the full corpus. Commit artifacts.
2. Run manual test scenarios TS1–TS17 from the spec. Record results in spec as an appendix.
3. Verify the pre-commit hook still completes under budget (`bash scripts/generate-kb-index.sh` median < 5s).
4. Update any existing KB documentation that references kb-search to mention the new flags (grep `knowledge-base/` for "kb-search").

## Test Strategy

| ID | What | Approach |
|---|---|---|
| TS1–TS5 | Happy-path + case-insensitivity | Manual: invoke `/kb-search` with each flag combination, verify result set matches expected files. |
| TS6 | Index generation perf | Time `bash scripts/generate-kb-index.sh` 3× on full corpus, assert median < 5s. |
| TS7, TS14 | Missing `tags:` field / missing frontmatter | Bats test on fixture files in `tests/scripts/fixtures/`. |
| TS8, TS11, TS16 | Argument parsing errors | Manual: invoke with bad flags, verify usage hint emitted. |
| TS9, TS10 | Tag-only / category-only / combined (no keyword) | Manual: verify title + path output, no snippet. |
| TS12 | Regex literal safety (`n+1`) | Manual: add fixture with `n+1` tag, verify query returns only that file (not `n1`). |
| TS13 | Inline vs block form parity | Bats test on two fixtures with identical content in different forms. |
| TS15 | Missing artifact fallback | Manual: delete `_tags.txt`, run query, verify actionable error (no crash). |
| TS17 | Case-fold dedup | Bats test on fixtures with `Eager-Loading`, `eager-loading`, `"eager-loading"` → one entry. |

**TDD gate**: Per AGENTS.md Code Quality rule, write failing bats tests BEFORE extraction library code. Phase 1 starts with the test file.

## Acceptance Criteria (from spec)

Copy-paste from `knowledge-base/project/specs/feat-kb-search-faceting/spec.md` for implementation tracking:

- [ ] FR1–FR8: original ACs (tag, category, combined, warn-but-accept, output format, generator emission, skill docs, compound integration)
- [ ] FR9: flags independently optional
- [ ] FR10: duplicate flag errors
- [ ] FR11: unknown flag errors
- [ ] FR12: missing artifact → actionable error
- [ ] FR13: value literal, not regex
- [ ] FR14: facet queries scope to learnings/
- [ ] FR15: tag-only output is title + path (no snippet)
- [ ] TR1–TR8: parsing reuses awk idiom; xargs batching preserved; case-insensitive; artifacts < 5KB; no runtime deps; drift tolerance; case-fold dedup; fixed-string grep
- [ ] TS1–TS17: all test scenarios pass
- [ ] Index generation median runtime < 5s (verified 3× on full corpus)

## Rollout

1. Land the PR with the extracted library, index generator changes, and new artifacts committed.
2. No backward compatibility concerns: existing `/kb-search <keyword>` behavior is unchanged; new flags are additive.
3. Post-merge: watch for the next `/compound` session to confirm the Related Docs Finder picks up the faceted pattern naturally.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Strict enum on `category` (issue's "helpful error listing valid values" AC taken literally) | Would require upfront category cleanup PR across 120+ learnings (~50 freeform values). Per brainstorm decision, warn-but-accept + did-you-mean resolves in one round-trip without cleanup. |
| Single `_facets.json` instead of two plain-text files | Requires jq in kb-search logic. YAGNI — no per-file reverse lookup needed. |
| Add BM25 or embeddings | Per issue: grep is 15ms, result-set noise is the friction. Revisit only if corpus >3000 files or queries return >500 matches. |
| Add Claude-ranked grep (haiku reranking top-5) | Deferred per issue. Revisit if faceting alone doesn't cut noise enough post-ship. |
| Inline logic in `generate-kb-index.sh` without extracting a library | Rejected for testability — bats tests need a scoped entry point, and future consumers (e.g., pre-commit hooks, CI validators) benefit from a reusable lib. |
| Backing `scripts/kb-search.sh` that kb-search SKILL.md calls | Rejected for consistency — existing kb-search is instructions-only. Adding a script changes the skill's execution model. Agent-executed bash per SKILL.md is sufficient and matches current pattern. |

**Deferred items tracked as follow-ups:**

- Reconciling `problem_type` enum (compound-capture) vs freeform `category` (general learnings) — file separate issue if drift becomes friction.
- Retroactive tag/category normalization across existing learnings — not needed while warn-but-accept holds.
- Multi-tag (`--tag a --tag b`) OR/AND semantics — no current demand.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is internal tooling (bash script + skill instructions) with no user-facing surface. No new skill being created (extending an existing one). No architectural escalation triggered: no new files under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. No service signup, no expense, no content/brand surface. Engineering/CTO review is implicit via the `/plan_review` pipeline (DHH + Kieran + Code Simplicity reviewers).

**Brainstorm carry-forward:** The 2026-04-14 brainstorm did not produce a `## Domain Assessments` section because the scope was internal tooling.

**Product/UX Gate:** N/A (Product domain not relevant).

## Sharp Edges

- Dirty tag values exist in the corpus (e.g., space-separated free-form inside brackets). Extraction logic must tolerate these without crashing — best-effort tokenization only.
- `awk '/^---$/{c++; next} c==1'` is mandatory — `sed '/^---$/,/^---$/'` is known-broken (body `---` horizontal rules leak into parsed values; see learning `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`).
- `npx` cache in worktrees is shared; prefer direct binary paths for bats if npx resolves wrong (per AGENTS.md Code Quality).
- Running the index generator inside lefthook in a worktree may hang >60s (known bug). If it does, kill and commit with `LEFTHOOK=0` per AGENTS.md.
- After any `replace_all` on the spec's ACs table, re-read the file (AGENTS.md Code Quality).
- Don't mix inline and block extraction in the same awk pass — use `grep -E '^tags:\s*\['` to branch first, then apply form-specific parser.

## References

- Issue: [#2211](https://github.com/jikig-ai/soleur/issues/2211)
- PR: [#2212](https://github.com/jikig-ai/soleur/pull/2212) (draft)
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-kb-search-faceting-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-kb-search-faceting/spec.md`
- Existing kb-search: `plugins/soleur/skills/kb-search/SKILL.md`
- Index generator: `scripts/generate-kb-index.sh`
- Frontmatter schema: `plugins/soleur/skills/compound-capture/references/yaml-schema.md`
- Compound Related Docs Finder: `plugins/soleur/skills/compound-capture/SKILL.md` (Step 3)
- Reusable awk idiom: `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- Parallel xargs perf pattern: `knowledge-base/project/learnings/2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
- Schema drift tolerance: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
- awk scoping rule: `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
