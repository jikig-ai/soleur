---
title: Tasks — KB Manifest and Search Skill
issue: 1739
branch: feat-kb-rag-evaluation
status: in-progress
created: 2026-04-07
---

# Tasks — KB Manifest and Search Skill

## Phase 1: INDEX.md Generator

- [ ] 1.1 Create `scripts/generate-kb-index.sh`
  - Walk `knowledge-base/**/*.md` recursively
  - Skip `archive/` directories, `INDEX.md` itself, non-`.md` files
  - Extract `title:` from YAML frontmatter (awk pattern)
  - Fallback: first `# heading`, then kebab-to-title-case filename
  - Output flat sorted list grouped by top-level domain
  - Use `LC_ALL=C sort` for deterministic ordering
  - No timestamp in output (avoid unnecessary diffs)
- [ ] 1.2 Verify determinism: run twice, diff returns 0
- [ ] 1.3 Verify performance: completes in <5 seconds for ~2,375 files
- [ ] 1.4 Verify archive exclusion: files under `archive/` dirs are not listed

## Phase 2: Lefthook Integration

- [ ] 2.1 Add `generate-kb-index` command to `lefthook.yml` under `pre-commit: commands:`
  - Priority: 10
  - Glob: `knowledge-base/**/*.md`
  - Run: `bash scripts/generate-kb-index.sh && git add knowledge-base/INDEX.md`
- [ ] 2.2 Add `knowledge-base/INDEX.md` to `.markdownlintignore`
- [ ] 2.3 Verify hook triggers on KB file changes and stages INDEX.md

## Phase 3: kb-search Skill

- [ ] 3.1 Create `plugins/soleur/skills/kb-search/SKILL.md`
  - Name: `kb-search` (no `soleur:` prefix in frontmatter)
  - Description: third person, routing text, under 30 words
  - Accept keyword arguments via `#$ARGUMENTS`
- [ ] 3.2 Implement two-tier search logic in SKILL.md instructions
  - Tier 1: grep INDEX.md for title matches
  - Tier 2: grep `knowledge-base/` file contents for body matches
  - Output tier 1 first, then tier 2, capped at 20 via `head`
- [ ] 3.3 Verify cross-domain results (e.g., "authentication" returns hits from multiple domains)
- [ ] 3.4 Run `bun test plugins/soleur/test/components.test.ts` — verify skill description budget

## Phase 4: Agent Integration

- [ ] 4.1 Update `plugins/soleur/agents/engineering/research/learnings-researcher.md`
  - Add step: read INDEX.md first for file discovery before grepping
  - Expand search scope hint: INDEX.md covers all domains, not just learnings
- [ ] 4.2 Verify learnings-researcher uses INDEX.md in a test query

## Phase 5: Cleanup

- [ ] 5.1 Run `npx markdownlint-cli2 --fix` on changed `.md` files
- [ ] 5.2 Generate initial INDEX.md by running the script
- [ ] 5.3 Commit all artifacts
