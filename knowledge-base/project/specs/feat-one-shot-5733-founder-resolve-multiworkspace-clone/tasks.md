---
title: "Tasks — agent-readiness absent-.git strand heal/block + observable backstop + per-workspace ready-clone (Ref #5733)"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-agent-readiness-absent-git-strand-and-per-workspace-clone-plan.md
issue: 5733
---

# Tasks — Ref #5733 (absent-.git strand heal/block + observability + per-workspace clone)

Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT bun test)
PR body: `Ref #5733` (NOT Closes — soak-gated).

## Phase 0 — Preconditions
- [ ] 0.1 Confirm new test paths sit under `apps/web-platform/test/` (vitest `include:` glob).
- [ ] 0.2 Baseline `tsc --noEmit` green.
- [ ] 0.3 Read all three `.c4` files; confirm no-C4-impact citing actors/systems/relationships checked.

## Phase 1 — Deliverable 3 (C2 detector empty-output) — TDD
- [ ] 1.1 RED: `test/in-sandbox-revparse-strand.test.ts` — empty output → strand; `"false\ntrue"` → not strand; `"true\nfalse"` → not strand; keep `fatal:`/`not a git repository`/`false` green.
- [ ] 1.2 GREEN: `server/tool-labels.ts:35-46` — work-tree probe with no standalone `true` token → strand; keep `isWorkTreeProbe` command guard.
- [ ] 1.3 Verify `test/tool-labels.test.ts` + `test/cc-dispatcher-self-heal-observability.test.ts` still green.

## Phase 2 — Deliverable 2 (absent/dir-invalid → emit + block) — TDD
- [ ] 2.1 RED: `test/agent-readiness-absent-git.test.ts` — absent + dir-invalid → `"block"` + `reportAgentReadinessSelfStop({gitKind, gitRevParseValid:false, source:"host-pre-heal"})`; dir-valid+worktree → ready; inconclusive×2 → ready.
- [ ] 2.2 GREEN: `server/git-worktree-validity.ts:401-433` — shape-aware routing; absent/dir-invalid → emit + block; preserve `!connected||!dbReady` and file-pointer behaviour.
- [ ] 2.3 Verify cold (`cc-dispatcher.ts:2010`), warm (`cc-reprovision.ts:145`), reconcile (`workspace-reconcile-on-push.ts:372`) map block → honest RepoNotReadyError / skip (3 assertions).

## Phase 3 — Deliverable 1 (per-workspace clone hardening) — TDD
- [ ] 3.1 RED: `test/ready-clone-per-workspace.test.ts` — two workspaces, one installation, distinct repo_urls → each resolves own repo_url+CWD, clones independently.
- [ ] 3.2 RED: extend `test/ensure-workspace-repo.test.ts` — connected+absent+malformed-url → `"failed"`; not-connected malformed → `"ok"`.
- [ ] 3.3 GREEN: `server/ensure-workspace-repo.ts:252-260` — scope benign-skip; return `"failed"` only when connected AND `.git` absent.

## Phase 4 — Docs + gates
- [ ] 4.1 Amend ADR-044 dispatch-readiness consequence (§line 552) for absent/dir-invalid + empty-output backstop.
- [ ] 4.2 Add `scripts/followthroughs/agent-readiness-absent-strand-observable-5733.sh` (Sentry-rate soak; mirror reconcile-ff-only-sentry-4977.sh) + tracker directive on #5733.
- [ ] 4.3 `tsc --noEmit` green; Phase-4 vitest suite list green (incl. cc-dispatcher*, repo-readiness*, cc-reprovision*, workspace-reconcile* orphan suites).
- [ ] 4.4 Open Code-Review Overlap check (gh issue list --label code-review, two-stage jq).

## Exit
- [ ] PR with `Ref #5733`; `## Acceptance Criteria` split Pre-merge / Post-merge; CPO sign-off recorded (single-user-incident threshold).
