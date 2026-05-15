---
title: "Tasks: verify peer-plugin-audit sub-mode against travisvn/awesome-claude-skills"
plan: knowledge-base/project/plans/2026-05-15-chore-peer-plugin-audit-verification-travisvn-plan.md
issue: 2749
lane: procedural
---

# Tasks — peer-plugin-audit verification (`#2749`)

> Spec lacks valid `lane:` (no spec.md authored — this is a procedural follow-through). `lane: procedural` set explicitly per task nature (single-skill invocation against documented procedure branch).

## Phase 1 — Re-verify procedure preconditions

- 1.1 Probe target repo state.
  - 1.1.1 `gh repo view travisvn/awesome-claude-skills --json url,licenseInfo,description,isFork,parent,stargazerCount,forkCount` — capture star/fork counts at /work time (NOT plan-time).
  - 1.1.2 `gh api "repos/travisvn/awesome-claude-skills/git/trees/HEAD?recursive=1" --jq '.tree[].path | select(endswith("SKILL.md"))'` — confirm zero SKILL.md files. **If non-empty, abort the non-audit branch and run the full 4-section procedure instead.**
- 1.2 Confirm SKILL.md routing intact: `grep -nE "peer-plugin-audit" plugins/soleur/skills/competitive-analysis/SKILL.md` shows the routing branch is in place.

## Phase 2 — Invoke the sub-mode

- 2.1 Run the skill: `skill: soleur:competitive-analysis peer-plugin-audit https://github.com/travisvn/awesome-claude-skills`.
- 2.2 If the skill aborts unexpectedly (auth failure, gh CLI error), capture the error verbatim and stop — do not write a synthetic advisory entry.

## Phase 3 — Verify and refine the artifact

- 3.1 Read the diff to `knowledge-base/product/competitive-intelligence.md`.
- 3.2 Verify against AC5 / AC6 / AC7 / AC8 of the plan:
  - 3.2.1 No new Overlap Matrix row.
  - 3.2.2 Advisory entry contains: repo URL, license "not detected", audit date `2026-05-15`, auditor name, /work-time star/fork counts, awesome-list note.
  - 3.2.3 Frontmatter `last_updated` and `last_reviewed` set to `2026-05-15`.
  - 3.2.4 No file written under `knowledge-base/product/research/peer-plugin-audits/`.
- 3.3 If the agent invented a new tier heading or otherwise drifted from the procedure, refine inline (not regenerate) — append the missing metadata, remove the spurious row, restore the existing tier taxonomy.

## Phase 4 — Pre-merge correctness

- 4.1 `git diff --name-only main..HEAD` shows exactly: `competitive-intelligence.md` + the pipeline-emitted plan/spec/tasks artifacts (per AC9).
- 4.2 Commit with a descriptive message linking `#2749`.
- 4.3 Open PR with body including `Closes #2749` and a permalink to the modified line(s) of `competitive-intelligence.md` (per AC10).

## Phase 5 — Post-merge

- 5.1 Verify GitHub auto-closed `#2749` via `Closes #2749` (`gh issue view 2749 --json closedAt,closedByPullRequestsReferences`). No manual `gh issue close` needed.

## Phase 6 — Compound learning (if novel)

- 6.1 Capture a learning ONLY if the verification surfaces a procedure gap (e.g., the procedure prescribes a tier-routing decision that the awesome-list case did not anticipate). If the non-audit branch fires cleanly per spec, no new learning is owed — the procedure is already documented.
