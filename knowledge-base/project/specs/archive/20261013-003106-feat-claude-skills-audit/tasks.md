# Tasks: peer-plugin-audit sub-mode in competitive-analysis

**Plan:** `knowledge-base/project/plans/2026-04-21-feat-peer-plugin-audit-sub-mode-plan.md`
**Issue:** `#2722` (primary), folds `#2728`
**PR:** `#2734` (draft)

## Phase 1 — Pre-flight (Measurement + Checklist Read)

- [ ] 1.1 Re-read `plugins/soleur/skills/competitive-analysis/SKILL.md`, `plugins/soleur/skills/agent-native-audit/SKILL.md`, `plugins/soleur/skills/growth/SKILL.md` (may have drifted).
- [ ] 1.2 Re-measure total skill description words via the Node one-liner in the plan's Research Insights. Confirm baseline matches 1800/1800 or record actual.
- [ ] 1.3 Read `plugins/soleur/AGENTS.md` Skill Compliance Checklist. Confirm Phase 4 changes satisfy: third person, ≤1024 chars, proper reference link markdown (no bare backticks), imperative body style.
- [ ] 1.4 Read full `knowledge-base/product/competitive-intelligence.md`. Confirm section order (Executive Summary → Tier 0 → Tier 3 → New Entrants → Recommendations → Cascade Results).

## Phase 2 — Verification guards

- [ ] 2.1 `bun test plugins/soleur/test/components.test.ts` — confirm GREEN at baseline.
- [ ] 2.2 (No custom smoke-test script — regression risks caught by `components.test.ts` + acceptance-criteria grep at review.)

## Phase 3 — Author `references/peer-plugin-audit.md`

- [ ] 3.1 Create directory `plugins/soleur/skills/competitive-analysis/references/`.
- [ ] 3.2 Author `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md` with:
  - [ ] 3.2.1 MIT attribution comment at top.
  - [ ] 3.2.2 Input validation section (github.com host, `gh repo view --json url,licenseInfo,description,isFork`, no-LICENSE default to "inspire only", fork note).
  - [ ] 3.2.3 Five-step procedure (WebFetch README+LICENSE / gh-api tree listing of SKILL.md paths / stratified sampling / Soleur catalog enumeration / Task spawn).
  - [ ] 3.2.4 Three worked overlap examples (senior-architect → arch-strategist+ddd+cto; financial-analyst → revenue-analyst+financial-reporter; content-creator → copywriter+content-writer).
  - [ ] 3.2.5 Inline Task prompt template for `competitive-intelligence` agent (includes repo metadata, Soleur catalog snapshot, CPO gate, CMO framing).
  - [ ] 3.2.6 Inline 4-section report template: Inventory Summary, High-Value Gaps (with "Founder outcome unblocked" column), Overlap Table, Architectural Patterns + Recommendations.
  - [ ] 3.2.7 Single-destination output routing (tier in competitive-intelligence.md only).
  - [ ] 3.2.8 Unbounded-output guards: explicit `| head -n 500` on every gh api, ls, find, WebFetch command.
  - [ ] 3.2.9 Error branches as one-liner notes (WebFetch rate-limit → gh api fallback, 401 → abort with gh auth status pointer, session-cached results note).
  - [ ] 3.2.10 All `#NNNN` references in the inline template wrapped in backticks per `cq-prose-issue-ref-line-start`.

## Phase 4 — Update `competitive-analysis/SKILL.md`

- [ ] 4.1 Re-read `plugins/soleur/AGENTS.md` Skill Compliance Checklist immediately before edit.
- [ ] 4.2 Replace `description:` with: `"This skill should be used when running competitive intelligence scans against tracked competitors, or auditing a peer skill-library repo via peer-plugin-audit. Produces structured knowledge-base reports."` (29 words).
- [ ] 4.3 Add Step 1 peer-plugin-audit branch *before* the `--tiers` detection (see plan Phase 4.3 for exact markdown).
- [ ] 4.4 Add "Sub-Modes" section to SKILL.md body (table with two modes).
- [ ] 4.5 Verify reference link uses proper markdown: `[peer-plugin-audit.md](./references/peer-plugin-audit.md)`.
- [ ] 4.6 Grep check: `grep -n 'peer-plugin-audit\|--tiers' SKILL.md` — peer-plugin-audit line < --tiers line.

## Phase 5 — Token budget surgery

- [ ] 5.1 Re-measure baseline total.
- [ ] 5.2 Edit `agent-native-audit/SKILL.md` description: old 37w → new 30w (exact text in plan Phase 5.2). Run measure.
- [ ] 5.3 Edit `growth/SKILL.md` description: old 37w → new 27w (exact text in plan Phase 5.3). Run measure.
- [ ] 5.4 Confirm total ≤ 1783 after both trims.
- [ ] 5.5 Apply competitive-analysis description expansion from 4.2 (+6w). Re-measure: expect ≤ 1789.
- [ ] 5.6 `bun test plugins/soleur/test/components.test.ts` — GREEN.

## Phase 6 — Seed Skill Library tier (folds `#2728`)

- [ ] 6.1 Locate insertion point (between `## Tier 3` and `## New Entrants`).
- [ ] 6.2 Insert new `## Skill Library Tier: Portable Skill Collections` section per plan Phase 6.2 (prose + Overlap Matrix + Tier Analysis subsections).
- [ ] 6.3 Confirm all `#NNNN` references wrapped in backticks (PR `#2734`, parent audit `#2718`, sub-mode `#2722`, tier issue `#2728`).
- [ ] 6.4 Update frontmatter: `last_updated: 2026-04-21`, `last_reviewed: 2026-04-21`, `tiers_scanned: [0, 3, "skill-library"]`.
- [ ] 6.5 Update PR #2734 body to include `Closes #2728`.

## Phase 7 — Smoke test end-to-end

- [ ] 7.1 Invoke `skill: soleur:competitive-analysis peer-plugin-audit https://github.com/alirezarezvani/claude-skills` in worktree.
- [ ] 7.2 Verify 4-section report written to Skill Library tier of `competitive-intelligence.md`.
- [ ] 7.3 Backwards-compat: invoke `skill: soleur:competitive-analysis --tiers 0,3` — flow completes unchanged.
- [ ] 7.4 If any smoke failure, stop and fix (no investigate-loop).

## Phase 8 — Validation & Ship prep

- [ ] 8.1 `bun test plugins/soleur/test/components.test.ts` — GREEN.
- [ ] 8.2 `npx markdownlint-cli2 --fix` on targeted paths only: competitive-analysis SKILL.md, competitive-analysis references/peer-plugin-audit.md, agent-native-audit SKILL.md, growth SKILL.md, competitive-intelligence.md.
- [ ] 8.3 `skill: soleur:review` — resolve P0/P1 findings inline.
- [ ] 8.4 PR #2734 body: `Closes #2722`, `Closes #2728`; add `## Changelog` section; `gh pr edit 2734 --add-label semver:minor`.
- [ ] 8.5 Mark PR ready for review.
