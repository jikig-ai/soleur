---
title: Tasks for feat-kb-search-faceting
date: 2026-04-14
issue: 2211
plan: knowledge-base/project/plans/2026-04-14-feat-kb-search-frontmatter-faceting-plan.md
---

# Tasks: kb-search Frontmatter Faceting

## Phase 1 — Facet extraction library (1h)

- [ ] **1.1** — Create fixtures under `tests/scripts/fixtures/learnings/` covering: inline form, block form, no frontmatter, missing tags field, empty tags array, quoted values, mixed casing, dirty values.
- [ ] **1.2** — Write failing bats tests in `tests/scripts/test-extract-facets.bats` per TDD gate (AGENTS.md Code Quality).
- [ ] **1.3** — Create `scripts/lib/extract-facets.sh` with two exported functions: `extract_tags_from_file`, `extract_category_from_file`.
- [ ] **1.4** — Implement awk-based frontmatter isolation (`/^---$/{c++; next} c==1`). No `sed` range expressions.
- [ ] **1.5** — Implement inline-form detection (`^tags:\s*\[`) and block-form detection (tags label followed by indented `- value` lines).
- [ ] **1.6** — Implement quote stripping, whitespace trim, lowercase output, silent skip on missing/empty/malformed inputs.
- [ ] **1.7** — Run bats suite, confirm all Phase 1 tests pass.

## Phase 2 — Index generator augmentation (1h)

- [ ] **2.1** — Source `scripts/lib/extract-facets.sh` from `scripts/generate-kb-index.sh`.
- [ ] **2.2** — Add parallel pass emitting tags and categories into temp files, preserving `xargs -P4 -n100` batching.
- [ ] **2.3** — `sort -u` temp files into `knowledge-base/_tags.txt` and `knowledge-base/_categories.txt`.
- [ ] **2.4** — Leave existing INDEX.md generation untouched.
- [ ] **2.5** — Run generator 3× on full corpus, record median wall-clock (must be < 5s).
- [ ] **2.6** — Commit the two autocomplete artifacts (`_tags.txt`, `_categories.txt`).

## Phase 3 — kb-search skill instructions (1.5h)

- [ ] **3.1** — Update `plugins/soleur/skills/kb-search/SKILL.md` with Argument Parsing section documenting `--tag`, `--category`, FR9–FR15 semantics.
- [ ] **3.2** — Add agent-executable algorithm pseudocode (artifact validation → warn-but-accept → file filter → keyword grep → emit).
- [ ] **3.3** — Add 4 examples: tag+keyword, category+keyword, tag-only, miss with did-you-mean.
- [ ] **3.4** — Add scope note (learnings/ only) and output format note (title+path for tag-only).
- [ ] **3.5** — Run markdownlint on SKILL.md (`npx markdownlint-cli2 --fix`).

## Phase 4 — Compound-capture integration (0.5h)

- [ ] **4.1** — Update `plugins/soleur/skills/compound-capture/SKILL.md` Step 3 (Related Docs Finder) with faceted-query pattern.
- [ ] **4.2** — Add before/after example (grep → `/kb-search --tag`).
- [ ] **4.3** — Add guidance on when to prefer facets vs grep.
- [ ] **4.4** — Run markdownlint on SKILL.md.

## Phase 5 — Validation (1h)

- [ ] **5.1** — Execute all test scenarios TS1–TS17 from spec. Record results.
- [ ] **5.2** — Verify pre-commit hook still completes under budget.
- [ ] **5.3** — Grep `knowledge-base/` for "kb-search" references; update any that should mention new flags.
- [ ] **5.4** — Run `/soleur:review` pipeline before marking PR ready.
- [ ] **5.5** — Resolve any review findings.
- [ ] **5.6** — Run `/soleur:compound` to capture any session learnings.
- [ ] **5.7** — Mark PR ready, label with `semver:patch`, auto-merge.

## Dependencies

- 2.1 depends on 1.3
- 3.2 depends on 2.3 (algorithm references artifact paths)
- 5.1 depends on 1.7, 2.5, 3.x, 4.x
- 5.7 depends on 5.1–5.6

## Exit criteria

All Phase 5 tasks complete; all FRs + TRs from spec satisfied; CI green; PR merged.
