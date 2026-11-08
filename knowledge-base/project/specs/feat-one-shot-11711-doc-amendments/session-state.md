# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-docs-key-rotation-dispatch-ruling-amendments-plan.md
- Plan artifact: complete (selector=branch)
- Status: complete

### Errors
- collision-precheck.sh self-hit on own draft PR #12391 (expected, not a duplicate)
- proc.sh sibling-session check could not run (exit 1) — disclosed in plan Premise Validation

### Decisions
- Runtime-prose sweep included as inferred scope (scripts/inngest-key-rotate.sh, scripts/key-rotate.sh, inngest-a5-a6-owner-ask-10136.sh + pinned test)
- Second stale claim found: inngest-server.md calls infra-privileged "required-reviewer approval"; live env has branch_policy only — corrected under ask (g)
- A5 reviewer click stays owner-human only; dispatch authority = fresh per-command in-session go
- Frontmatter issue: 11711 with NO closes: — PR body must say "Ref #11711" (epic rows remain)
- No prose-drift lint shipped (CTO-ruled)

### Components Invoked
- soleur:plan, soleur:deepen-plan (sequential-fallback in subagent), gh api env checks, collision-precheck.sh

## Post-Plan Re-probe (2026-11-08)
- #11711 OPEN; linked:issue → PR #12387 OPEN (feat-one-shot-11294-clo-reassessment — different scope/files, sibling session on CLO item; NOT a collision)
- in:body open probe: only #12387
- Anchor probe over planned edit set: zero open PRs touch the files
- Overlap preflight: exit 0 (prs=none) at start; will re-run --files pre-merge

## Sibling work (main context, not this PR)
- #12392 filed: kk_cmd_clear readback race (meta/machinery)
- Rescan in progress: 173 post-census run logs + 96 infra-drift issues for residual raw random_id lines
- Found: 4 comments on #10835 with raw random_id values still live (missed by 2026-11-01 redaction)

## Operator Constraints

- constraint: Agent may dispatch key-rotate.yml/inngest-key-rotate.yml rotate|converge ONLY under a fresh, per-command, in-session owner go naming the exact full command (CTO ruling). The reviewer click (key-rotate-approval env, deruelle) is NEVER delegated.
- constraint: The approval tap should land inside a measured release-quiet stretch - apply re-checks in-flight itself, so a parked run CAN still refuse post-approval.
- constraint: Merge queue is slow (~2-8h/PR under churn). Armed PRs can silently drop from the queue with a stale autoMergeRequest - disarm+re-arm to re-enqueue. Commits MUST author as jean.deruelle@jikigai.com (cla-check). pr-body-vs-diff: file paths outside backticks must >=50% appear in the diff.
- constraint: File work only in linked worktrees (worktree-manager.sh create) - never the bare root.

## Technical-Ruling Gate
- technical-ruling-gate.sh --branch: PASS (6 rows; fixed one bad-ruling-shape — missing date on the dispatch ruling row)
- cto_spawns=0 (rulings recorded inline via sequential-fallback; dispatch ruling itself predates this PR)
