---
plan: knowledge-base/project/plans/2026-10-20-feat-feature-map-convention-plan.md
issue: 10402
---

# Tasks — feat: feature-map artifact convention for user codebases

## Phase 1 — Convention doc

- [x] 1.1 Create `plugins/soleur/skills/test-browser/references/feature-map.md` (~150 lines): plain `# Title`, no frontmatter, kebab-case, ASCII, markdown links. Self-contained — no `knowledge-base/`, `scripts/`, or `apps/` paths (AC7). Cover the 9-section outline in plan Technical Approach §Edit surface 1: what a map is; canonical `docs/feature-map.md`; entry schema + fenced worked example (fence-markers warning); `## Deliberately unmapped` reasoned exemptions; consumer-parse constraints (line-anchored, no fences in the map); update contract; authoring guidance (prefix-pathspec + suffix-filter, POSIX-safe commands); keeping-it-fresh (refresh-on-run + five-arm lint sketch); edge cases.
- [x] 1.2 Verify AC1/AC2 greps on the written doc (`docs/feature-map.md`, `Deliberately unmapped`, `selectors:`, `expects:`, `update contract`, `lint`, `refresh`, `fenced` all present).

## Phase 2 — SKILL.md edits

- [x] 2.1 `plugins/soleur/skills/test-browser/SKILL.md` — §3 "Repo feature map first": generalize to the `docs/feature-map.md` convention with `[feature-map.md](./references/feature-map.md)` markdown link (never a backtick ref). Soleur path named as the noted exception. Fallback sentence names the file→route table as fallback for repos without a map AND for routes a partial map does not cover.
- [x] 2.2 `plugins/soleur/skills/test-browser/SKILL.md` — new `### 5b. Write or refresh the feature map` after `</test_pages>`, before `### 6.`: three producer arms (seed exercised-routes-only when absent+web+≥1 route; field-scoped refresh + append when present; skip non-web / zero-route), working-tree edit lands with the PR, Step-8 summary reports `written`/`refreshed`/`skipped`+reason.
- [x] 2.3 `plugins/soleur/skills/qa/SKILL.md` — replace line 132 with the plan's verbatim generalized line. Verify `wc -c` delta ≤ ~100 B; run `python3 scripts/lint-skill-body-budget.py --base origin/main` — must exit 0.
- [x] 2.4 `plugins/soleur/skills/ux-audit/SKILL.md` + `plugins/soleur/skills/reproduce-bug/SKILL.md` — same one-line generalization of each soleur-path citation to name `docs/feature-map.md`.

## Phase 3 — Verification

- [x] 3.1 AC3–AC5 grep battery: `docs/feature-map.md` count per file (test-browser ≥1, qa =1, ux-audit =1, reproduce-bug =1); `Write or refresh` heading present in test-browser.
- [x] 3.2 `bun test plugins/soleur/test/components.test.ts` green; negative control — on a scratch copy with the SKILL.md link removed, the reachability census reds naming `test-browser/references/feature-map.md`.
- [x] 3.3 `bash scripts/markdown-lint.sh` clean on all touched files.
- [x] 3.4 AC8: `git diff origin/main...HEAD -- plugins/soleur/docs/_data/skills.js 'plugins/soleur/skills/*/SKILL.md'` — no `description:` delta, no skills.js change.
