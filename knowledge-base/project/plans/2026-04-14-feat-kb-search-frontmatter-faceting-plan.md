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
>
> **Revision:** 2026-04-14 post-review. Stripped `extract-facets.sh` library (inline into generator), killed Levenshtein (replaced with static hint to artifact), collapsed 5 phases → 2, cut 17 test scenarios → 7 focused bats/smoke tests. Kieran's correctness bugs addressed: per-worker `mktemp` for xargs race, awk block-form termination rule, POSIX character classes, automated TS5.

## Overview

Add `--tag` and `--category` flags to the `kb-search` skill so agents can filter `knowledge-base/project/learnings/` by YAML frontmatter facets before grep runs, cutting result-set noise during cross-referencing in `/compound`. Extend `scripts/generate-kb-index.sh` to emit two sibling autocomplete artifacts (`knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt`). Update `compound-capture/SKILL.md` Step 3 with faceted-query guidance.

- **Effort**: ~2.5 hours (post-review strip)
- **Stack**: Bash (awk, grep, xargs), markdown SKILL.md files. No new dependencies.
- **Risk**: Low. Extends existing tooling; no user-facing surface; preserves existing perf pattern.

## Context

- `plugins/soleur/skills/kb-search/SKILL.md` is instructions-only. Implementation = SKILL.md edits + agent-executed bash at query time.
- `scripts/generate-kb-index.sh` uses `xargs -P4 -n100` parallel batching (1.27s on 386 files; budget 5s). Must be preserved — per learning `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`.
- Frontmatter parsing uses `awk '/^---$/{c++; next} c==1'` — per `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` and `2026-03-05-awk-scoping-yaml-frontmatter-shell.md`. No `sed` range expressions.
- Corpus has both inline (`tags: [a, b, c]`) and block (`tags:\n  - a`) forms, plus dirty values. Skip malformed entries silently (TR6).
- No community overlap (functional-discovery verified).
- Naming: `kb-tags.txt` / `kb-categories.txt` (kebab-case, `kb-` prefix) — not `_tags.txt` (underscore conflicts with hidden-file conventions per reviewer feedback).

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/kb-tags.txt` | Sorted unique lowercased tags, one per line. Committed to git. |
| `knowledge-base/kb-categories.txt` | Sorted unique lowercased categories, one per line. Committed to git. |
| `tests/scripts/test-generate-kb-index.bats` | Bats test covering the facet extraction behavior baked into `generate-kb-index.sh`. |
| `tests/scripts/fixtures/facets/` | Fixture learning files exercising inline/block/malformed/dedup scenarios. |

## Files to Modify

| Path | Change |
|---|---|
| `scripts/generate-kb-index.sh` | Add inline facet extraction + emission. Use per-worker `mktemp` to avoid `xargs -P4` append races. Keep INDEX.md path unchanged. |
| `plugins/soleur/skills/kb-search/SKILL.md` | Add `--tag` / `--category` flag docs, algorithm, 4 examples, scope note. |
| `plugins/soleur/skills/compound-capture/SKILL.md` | Update Step 3 with faceted-query pattern (docs-only). |
| `knowledge-base/project/specs/feat-kb-search-faceting/spec.md` | Already updated in planning phase. |

## Implementation Phases

### Phase A — Generator + autocomplete artifacts (~1.5h)

1. **Fixtures first** (TDD gate, AGENTS.md Code Quality). Create `tests/scripts/fixtures/facets/`:
   - `inline.md` — `tags: [eager-loading, n+1, performance]`, `category: performance-issues`
   - `block.md` — block-form equivalent of inline.md
   - `mixed-case.md` — `tags: ["Eager-Loading", 'EAGER-LOADING']` for dedup
   - `no-frontmatter.md` — plain markdown, no `---`
   - `missing-tags.md` — frontmatter present, no `tags:` field
   - `empty-tags.md` — `tags: []`
   - `dirty.md` — `tags: [a, b, c workflow fails...]` (best-effort)
2. **Write failing bats** covering TS1–TS5 (see spec). Tests invoke `bash scripts/generate-kb-index.sh` against a controlled fixture directory (via `KB_ROOT` env var override) and assert on output artifacts.
3. **Extend `scripts/generate-kb-index.sh`** inline (no separate library):

   ```bash
   # Inside the script, after existing INDEX.md generation:

   extract_facets() {
     local file="$1" worker_id="$2"
     # Isolate frontmatter with awk (not sed — body --- leaks)
     awk '/^---$/{c++; next} c==1' "$file" | {
       # Category: single value
       grep -E '^category:[[:space:]]*' | \
         sed -E 's/^category:[[:space:]]*//; s/^["\x27]//; s/["\x27]$//' | \
         tr '[:upper:]' '[:lower:]' >> "/tmp/kb-cats.$worker_id"

       # Tags: inline form [a, b] OR block form (- a\n- b)
       # Block-form termination: stop at next non-indented key (^[a-z_]+:)
       awk '
         /^tags:[[:space:]]*\[/ {
           gsub(/^tags:[[:space:]]*\[|\][[:space:]]*$/, "")
           gsub(/[[:space:]]*,[[:space:]]*/, "\n")
           print; next
         }
         /^tags:[[:space:]]*$/ { in_block=1; next }
         in_block && /^[[:space:]]+-[[:space:]]+/ {
           sub(/^[[:space:]]+-[[:space:]]+/, ""); print; next
         }
         in_block && /^[a-z_]+:/ { in_block=0 }
       ' | \
         sed -E 's/^["\x27]//; s/["\x27]$//' | \
         tr '[:upper:]' '[:lower:]' | \
         grep -v '^[[:space:]]*$' >> "/tmp/kb-tags.$worker_id"
     }
   }
   export -f extract_facets

   # Parallel extraction with per-worker temp files (avoids append race)
   find knowledge-base/project/learnings -name '*.md' -print0 | \
     xargs -0 -P4 -n100 -I{} bash -c '
       WORKER_ID=$$
       extract_facets "{}" "$WORKER_ID"
     '

   # Merge worker outputs
   cat /tmp/kb-tags.* | sort -u > knowledge-base/kb-tags.txt
   cat /tmp/kb-cats.* | sort -u > knowledge-base/kb-categories.txt
   rm -f /tmp/kb-tags.* /tmp/kb-cats.*
   ```

   Note: the above is indicative, not final. Implementation must verify `export -f` works with the script's existing bash version and adjust the worker_id scheme if there's a cleaner approach. The per-worker temp file pattern is the invariant that must hold.

4. **Run bats suite** — all Phase A tests pass.
5. **Perf check** — run `time bash scripts/generate-kb-index.sh` 3× on full corpus; median must stay under 5s. If over budget, reduce to a single awk invocation that extracts title + category + tags in one pass.
6. **Commit artifacts** — `kb-tags.txt` and `kb-categories.txt` are committed to git (deterministic regeneration).

### Phase B — Skill docs (~1h)

1. **Update `plugins/soleur/skills/kb-search/SKILL.md`** with:
   - Argument Parsing section documenting `--tag`, `--category`, FR9–FR15.
   - Algorithm block (agent-executable pseudocode):

     ```bash
     # 1. Validate artifacts present
     if [ ! -f knowledge-base/kb-tags.txt ] || [ ! -f knowledge-base/kb-categories.txt ]; then
       echo "Autocomplete artifacts missing. Run: bash scripts/generate-kb-index.sh"
       exit 1
     fi

     # 2. Duplicate / unknown flag guards (bash case + counter)
     # 3. Validate value against artifact (case-insensitive, fixed-string whole-line)
     tag_lc=$(echo "$TAG" | tr '[:upper:]' '[:lower:]')
     if [ -n "$TAG" ] && ! grep -Fxq "$tag_lc" knowledge-base/kb-tags.txt; then
       echo "No matches. Valid values: knowledge-base/kb-tags.txt"
       exit 0
     fi

     # 4. Filter learnings/ by frontmatter (inline awk — same idiom as generator)
     # 5. If keyword supplied, grep -F through survivors
     # 6. Emit title + path (+ snippet only when keyword present)
     ```

   - 4 examples: tag+keyword, category+keyword, tag-only, miss.
   - Scope note (learnings/ only, FR14).
   - Output format note (title+path for tag-only, FR15).
2. **Update `plugins/soleur/skills/compound-capture/SKILL.md` Step 3** (Related Docs Finder):
   - One paragraph introducing the faceted-query pattern.
   - Before/after example: `grep -r "eager loading" knowledge-base/project/learnings/` → `/kb-search --tag eager-loading`.
   - Guidance: prefer facets when the current learning has a specific tag/category; fall back to grep otherwise.
3. Run `npx markdownlint-cli2 --fix` on both SKILL.md files (AGENTS.md Code Quality).

## Test Strategy

| ID | What | How |
|---|---|---|
| TS1 | Inline-form extraction | bats + fixture `inline.md` |
| TS2 | Block-form extraction | bats + fixture `block.md` |
| TS3 | Malformed files skipped | bats + fixtures `no-frontmatter.md`, `missing-tags.md`, `empty-tags.md` |
| TS4 | Case-fold dedup | bats + fixture `mixed-case.md` |
| TS5 | Missing artifact fallback | bats: `rm kb-tags.txt && run /kb-search --tag foo`; assert actionable error |
| TS6 | Perf budget (< 5s) | bash: `time bash scripts/generate-kb-index.sh`, median of 3 runs |
| TS7 | End-to-end smoke | bash: `/kb-search --tag <real-tag>` returns non-empty title+path list |

**TDD gate** (AGENTS.md): bats fixtures and failing tests go in before the generator edits.

## Acceptance Criteria

Tracked in spec. Copy for implementation ticking:

- [x] FR1–FR15 (all listed in spec)
- [x] TR1–TR11 (all listed in spec)
- [x] TS1–TS7 (all listed in spec)
- [x] Index generation median < 5s on full corpus (measured 1.4–1.5s on 646-file corpus)

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Separate `scripts/lib/extract-facets.sh` library | Single consumer (the index generator). Creating a library for future callers is speculative. YAGNI — inline now, extract if a second consumer appears. |
| Levenshtein "did you mean?" suggestions | Bash fuzzy matching for an agent-facing flag. Agent can read `kb-tags.txt` after a miss (one extra tool call). Static hint satisfies the brainstorm's token-efficiency intent without the implementation cost. |
| Strict enum on `category` (issue's "helpful error" AC taken literally) | Requires upfront cleanup of ~50 freeform categories. Brainstorm chose warn-but-accept to avoid this; post-review strip reduces the warn-but-accept to a static hint, further simplifying. |
| Single `kb-facets.json` instead of two plain-text files | Requires jq in kb-search logic. No per-file reverse lookup needed. |
| BM25 or embeddings | Per issue: grep is 15ms; noise is the real friction. Revisit only past 3000 files. |
| Claude-ranked grep (haiku reranking) | Deferred per issue; revisit only if faceting alone doesn't cut noise enough post-ship. |
| Backing `scripts/kb-search.sh` called by SKILL.md | Existing kb-search is instructions-only. Adding a script changes the skill's execution model. Agent-executed bash is sufficient. |

**Deferred items tracked as follow-ups:**

- `problem_type` enum vs `category` asymmetry — separate issue if it becomes friction.
- Retroactive tag/category normalization — not needed while graceful skip holds.
- Multi-tag OR/AND — no demand.
- Stale-artifact detection — not needed while pre-commit regenerates.

## Domain Review

**Domains relevant:** none

Internal tooling (bash script + skill instructions) with no user-facing surface. No new skill — extending an existing one. No mechanical escalation triggered (no new `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). No service signup, no expense, no content/brand surface. Engineering review via `/plan_review` (DHH + Kieran + Code Simplicity) applied and incorporated.

**Brainstorm carry-forward:** no `## Domain Assessments` in the brainstorm — scope was internal tooling.

**Product/UX Gate:** N/A.

## Sharp Edges

- Dirty tag values in the corpus (space-separated free-form inside brackets). Extraction tokenizes on commas only; tail text past a bad comma stays in the last token. Acceptable — skipped at dedup if it doesn't match any query.
- `awk '/^---$/{c++; next} c==1'` is mandatory. `sed '/^---$/,/^---$/'` is known-broken (body `---` horizontal rules leak).
- **Xargs write race** — `>>` on parallel workers is NOT reliably atomic above PIPE_BUF. Per-worker `mktemp`-style filenames are required (TR9).
- **Block-form parser termination** — must exit block-state on `^[a-z_]+:` to avoid swallowing sibling keys (TR10).
- **POSIX character classes** — use `[[:space:]]`, not `\s`. BSD grep on macOS dev machines doesn't support `\s` (TR11).
- `npx` cache in worktrees is shared; prefer direct binary paths for bats if npx resolves wrong (AGENTS.md).
- Lefthook may hang in worktrees >60s (known bug). Kill + commit with `LEFTHOOK=0`.
- Re-read the spec after any `replace_all` on its tables (AGENTS.md Code Quality).
- Plan calls out `export -f extract_facets` — verify this works with the script's bash version before committing. If it doesn't, rewrite the xargs invocation to use `xargs -0 -P4 -n100 bash -c '...'` without function export.

## References

- Issue: [#2211](https://github.com/jikig-ai/soleur/issues/2211)
- PR: [#2212](https://github.com/jikig-ai/soleur/pull/2212) (draft)
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-kb-search-faceting-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-kb-search-faceting/spec.md`
- Existing kb-search: `plugins/soleur/skills/kb-search/SKILL.md`
- Index generator: `scripts/generate-kb-index.sh`
- Frontmatter schema: `plugins/soleur/skills/compound-capture/references/yaml-schema.md`
- Compound Related Docs Finder: `plugins/soleur/skills/compound-capture/SKILL.md` (Step 3)
- awk idiom: `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- Parallel xargs perf: `knowledge-base/project/learnings/2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
- Drift tolerance: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
- awk scoping: `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
