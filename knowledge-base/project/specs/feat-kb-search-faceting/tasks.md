---
title: Tasks for feat-kb-search-faceting
date: 2026-04-14
issue: 2211
plan: knowledge-base/project/plans/2026-04-14-feat-kb-search-frontmatter-faceting-plan.md
---

# Tasks: kb-search Frontmatter Faceting

> Post-review strip: ~2.5h total. Two phases.

## Phase A — Generator + autocomplete artifacts (~1.5h)

- [ ] **A.1** — Create fixtures in `tests/scripts/fixtures/facets/`: `inline.md`, `block.md`, `mixed-case.md`, `no-frontmatter.md`, `missing-tags.md`, `empty-tags.md`, `dirty.md`.
- [ ] **A.2** — Write failing bats at `tests/scripts/test-generate-kb-index.bats` covering TS1–TS5. Use `KB_ROOT` env override or tmp-dir setup so the script targets fixtures, not the real corpus.
- [ ] **A.3** — Edit `scripts/generate-kb-index.sh`: inline facet extraction after existing INDEX.md section. Preserve `xargs -P4 -n100`.
- [ ] **A.4** — Implement awk frontmatter isolation + dual-mode tag parser (inline `[a,b]` + block `- value`) with explicit block-form termination (`^[a-z_]+:`).
- [ ] **A.5** — Use per-worker `mktemp` temp files (e.g., `/tmp/kb-tags.$$`) inside xargs workers. Merge with `cat | sort -u` in main process.
- [ ] **A.6** — Use POSIX character classes (`[[:space:]]`), not `\s`. Verify `export -f` compatibility or inline the function into the `bash -c` string.
- [ ] **A.7** — Strip quotes, lowercase, skip empty lines before dedup.
- [ ] **A.8** — Run bats — all Phase A tests pass.
- [ ] **A.9** — Run `time bash scripts/generate-kb-index.sh` 3× on full corpus. Median must be < 5s. If over budget, collapse to single awk pass.
- [ ] **A.10** — Commit `knowledge-base/kb-tags.txt` and `knowledge-base/kb-categories.txt`.

## Phase B — Skill docs (~1h)

- [ ] **B.1** — Update `plugins/soleur/skills/kb-search/SKILL.md`: add Argument Parsing section, algorithm pseudocode, 4 examples, scope note, output format note.
- [ ] **B.2** — Update `plugins/soleur/skills/compound-capture/SKILL.md` Step 3: faceted-query pattern, before/after example, preference guidance.
- [ ] **B.3** — Run `npx markdownlint-cli2 --fix` on both SKILL.md files.
- [ ] **B.4** — Run end-to-end smoke (TS6, TS7): measure perf on full corpus and issue `/kb-search --tag <real-tag>` to confirm wiring.

## Pre-Ship (~30min)

- [ ] **P.1** — Run `/soleur:review` pipeline.
- [ ] **P.2** — Resolve review findings.
- [ ] **P.3** — Run `/soleur:compound` to capture session learnings.
- [ ] **P.4** — Mark PR ready, label `semver:patch`, auto-merge.

## Dependencies

- A.3 depends on A.2 (TDD gate)
- A.10 depends on A.8, A.9
- B.4 depends on A.10
- P.x depends on A, B complete

## Exit criteria

All FR1–FR15, TR1–TR11, TS1–TS7 from spec satisfied; perf median < 5s; CI green; PR merged.
