---
title: "Decision challenges — feat-one-shot-salvage-10117-artifacts"
date: 2026-10-14
branch: feat-one-shot-salvage-10117-artifacts
---

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Salvage shape (verbatim learnings + two bullet ports + timestamped archive set, then close draft PR 10190 unmerged) | technical | Ruled by CTO agent, 2026-10-14: prescribed this exact hybrid-salvage shape in the pipeline brief — do not re-open. Both delivery PRs (10237, 10242) merged 2026-10-14; only the documentation trail remains on the branch. |
| Archive destination filename shape under `*/archive/` | technical | Ruled by CTO agent, 2026-10-14: `<ts>-<basename>` retains the ORIGINAL filename including its `2026-10-13-` date prefix — `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` uses `${ts}-$(basename "$artifact")` and every existing entry under `plans/archive/` and `brainstorms/archive/` carries the double date. The brief's `<ts>-<name>` shorthand reads `<name>` = full original basename. |
| Content excluded from the port | technical | Ruled by CTO agent, 2026-10-14: do NOT port the branch's stale sibling-worktree-contention paragraph variant or its two `work/SKILL.md` deletions (the `6.8` sharp-edge bullet and the test-harness-sharp-edges pointer bullet) - verbatim from the brief's exclusion list; main's wording is newer, verified via merge-base diff `943ebacc`..`1219f7a0`, and both deleted items still live on main. |
| Plan `lane:` value | technical | Ruled by CTO agent, 2026-10-14: no `spec.md` exists for this branch, so the Save Tasks lane carry-forward finds no valid `lane:` — fail-closed `cross-domain` per `plan/SKILL.md` Save Tasks contract. Recorded; the fan-out it widens is moot because every domain sweep returns none. |
| Brand-survival threshold | technical | Ruled by CTO agent, 2026-10-14: `none` — the diff is KB docs plus two skill-doc bullets; zero matches against the canonical `SENSITIVE_PATH_RE` (preflight Check 6 Step 6.1). |
| Issue linkage (`closes:`) | technical | Ruled by CTO agent, 2026-10-14: issue 10117 already CLOSED 2026-10-14; the PR body cites the arc with `Ref` in prose only — never `Closes`/`Fixes`. Plan frontmatter omits `closes:`. |
| Mutation-vacuity bullet destination | technical | Ruled by CTO agent, 2026-10-14: port into `skills/work/references/work-test-harness-sharp-edges.md` as a `## ` section, not `work/SKILL.md`'s tail - `lint-skill-body-budget` pins work's SKILL.md at 359189 bytes and main sits at 359179 (10 B headroom), so the 1089-byte inline bullet cannot land without prose surgery on the corpus; the references file is the designed extraction home, is linked from SKILL.md §9 line 1187, and mutation-vacuity is literally a test-harness sharp edge. |
