---
title: "Tasks — backfill-frontmatter recurse + extract harden"
date: 2026-05-20
issue: 4163
lane: single-domain
---

# Tasks: feat-one-shot-backfill-frontmatter-recurse-4163

Derived from `knowledge-base/project/plans/2026-05-20-chore-backfill-frontmatter-recurse-and-extract-harden-plan.md`.

## 1. Setup (Phase 0)

- 1.1. Confirm baseline missing-frontmatter count: `find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---'` returns 34.
- 1.2. Confirm sentinel survival baseline: `grep -rEn "^- (module-level-state|category-design)\b" knowledge-base/project/learnings/` returns exactly 2 hits.
- 1.3. Record `wc -l knowledge-base/kb-tags.txt` baseline.
- 1.4. Confirm `python3 -c "import yaml"` succeeds (no new dep).

## 2. Core Implementation (Phases 1-2)

- 2.1. RED: write `scripts/test_backfill_frontmatter.py` with FOUR fixtures (deepen-pass split structured-kv vs normalize_tags fallback):
  - 2.1.1. Pre-existing `tags:` frontmatter containing `category-design` + `module-level-state` (untouched-path test).
  - 2.1.2. `## Tags` YAML-block-scalar with structured key:value rows only (structured path corruption).
  - 2.1.3. `**Tags:** category-design, module-level-state, ui` (comma-form preserves prefix-tokens).
  - 2.1.4. `## Tags` block with mixed `key: value` + `  - "id"` sub-bullets (normalize_tags fallback corruption — the canonical 82584251 shape).
- 2.2. Run `python3 scripts/test_backfill_frontmatter.py` — expect FAIL on both corruption-path assertions.
- 2.3. GREEN: edit `scripts/backfill-frontmatter.py`:
  - 2.3.1. Add `_reject_yaml_block_noise(tags)` helper rejecting `^--`, `^category-`, `^module-`, len > 50. Apply at BOTH returns inside the `## Tags` branch (structured path AND normalize_tags fallback). Rename local `lines` to `lines_in_section` to avoid shadowing. Do NOT modify the `**Tags:**` comma-form branch.
  - 2.3.2. Add `iter_learning_files(root)` helper using `os.walk`, skipping case-insensitive `README.md`.
  - 2.3.3. Replace `os.listdir(LEARNINGS_DIR)` at the four call sites (process loop ~line 292, frontmatter-presence verifier ~line 315, required-fields verifier ~line 331, category counter ~line 353) with `iter_learning_files()`.
  - 2.3.4. Update `rename_dateless_file()` docstring noting it remains top-level by design.
- 2.4. Run `python3 scripts/test_backfill_frontmatter.py` — expect PASS.

## 3. Testing (Phase 3 — operator-driven dry-run)

- 3.1. Snapshot HEAD state of two sentinel files + one corruption-canary file to `/tmp/`.
- 3.2. Run `python3 scripts/backfill-frontmatter.py` against the worktree.
- 3.3. `diff` sentinel-A and sentinel-B against `/tmp/` snapshots — expect empty diffs.
- 3.4. `head -10` corruption canary — confirm no `--<digits>`, no `category-*`, no `module-*` in extracted tags.
- 3.5. `bash scripts/generate-kb-index.sh` to regenerate `kb-tags.txt` and `kb-categories.txt`.
- 3.6. Run AC grep: `awk '/^(--|category-process|category-integration-issues|module-brainstorm|module-marketing-aeo)$/ { print }' knowledge-base/kb-tags.txt` — expect no output.
- 3.7. Run acceptance verification: `find knowledge-base/project/learnings -name '*.md' -not -iname 'README.md' -exec head -1 {} \; | grep -vc '^---'` returns 0.
- 3.8. Verify sentinel survival post-run: `grep -rEn "^- (module-level-state|category-design)\b" knowledge-base/project/learnings/` returns 2 hits.

## 4. Ship (Phase 4)

- 4.1. `git add scripts/backfill-frontmatter.py scripts/test_backfill_frontmatter.py knowledge-base/`.
- 4.2. `git status --short` sanity check — expect only `scripts/` + `knowledge-base/{kb-*.txt,INDEX.md,project/learnings/**}`.
- 4.3. Commit with message per plan §Phase 4.
- 4.4. Push; open PR with body containing `Closes #4163` and Pre-merge AC checklist from plan.
- 4.5. Multi-agent review via `/soleur:review` (single-domain lane).
- 4.6. After review-green and CI-green, mark PR ready and merge.

## Notes

- No new dependencies (Python 3 stdlib `unittest` only).
- No infrastructure changes, no AGENTS.md edits, no skill description changes.
- Operator-driven verification (Phase 3) is the gate; future CI integration deferred (no follow-up issue filed — operator-only tooling).
