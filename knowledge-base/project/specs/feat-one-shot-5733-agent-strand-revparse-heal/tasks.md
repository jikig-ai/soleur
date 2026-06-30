# Tasks — Durable agent-surface git-strand heal (#5733)

Plan: `knowledge-base/project/plans/2026-06-30-fix-durable-agent-surface-rev-parse-strand-heal-plan.md`
Lane: cross-domain (no spec.md on one-shot path → defaulted, fail-closed).
Threshold: single-user incident → CPO sign-off + `user-impact-reviewer` at review.

## Phase 0 — Preconditions (no code)
- [ ] 0.1 Verify `git rev-parse --is-inside-work-tree` exit semantics + that
      `GIT_CEILING_DIRECTORIES=<parent>` blocks parent-`.git` ascension, with throwaway
      fixtures (escaping pointer / corrupt dir-valid / healthy clone). Pin output.
- [ ] 0.2 Read the injected-seam wiring (`cc-dispatcher.ts:1877/1886`) +
      `test/helpers/cc-dispatcher-harness.ts`.
- [ ] 0.3 Grep type-widening consumers of `reportAgentReadinessSelfStop`; re-confirm
      exactly two `.git` `rm` sites (`ensure-workspace-repo.ts:174`, `:236`).

## Phase 1 — Probe seam + failing tests (RED)
- [ ] 1.1 Add `hostGitRevParse(workspacePath)` (ceiling + bounded timeout, fail-closed)
      and `agentReadyGitWorkTree(workspacePath)` (UNION) to `git-worktree-validity.ts`.
- [ ] 1.2 Expose as an injectable seam for the three gates.
- [ ] 1.3 RED tests in `test/server/agent-ready-git-worktree.test.ts`: escaping pointer →
      false; corrupt dir-valid → false; healthy clone → true; non-escaping pointer → true;
      timeout → false (AC1, AC2).

## Phase 2 — Cold gate (cc-dispatcher) GREEN
- [ ] 2.1 Replace lstat `gitReady` verdict (`:1810-1838`, seam `:1886`) with `agentReady`,
      lstat pre-filtered + connected-gated (AC3).
- [ ] 2.2 Fire self-stop on `!agentReady` carrying `gitRevParseValid` (AC4).
- [ ] 2.3 Populated-corrupt branch → honest-block `RepoNotReadyError`, no destroy (AC6).
- [ ] 2.4 Await-before-query ordering test (`:1963` before `:2326`) (AC7).

## Phase 3 — Warm gate (cc-reprovision) GREEN
- [ ] 3.1 Compute `agentReady`; memoize positive per-workspace-per-process (invalidate on
      shape-change/disconnect).
- [ ] 3.2 Re-probe after heal; honest "failed" outcome (no spawn) if still `!agentReady` (AC5).
- [ ] 3.3 Fire self-stop on `!agentReady` (AC4).

## Phase 4 — Reconcile gate (workspace-reconcile-on-push) GREEN
- [ ] 4.1 Gate on `agentReady` (`:357`).
- [ ] 4.2 Fire self-stop on the unrecovered / benign-skip branch (`:384-398`) (AC3, AC4).

## Phase 5 — Observability widening + ADR
- [ ] 5.1 Widen `reportAgentReadinessSelfStop` with `gitRevParseValid`; update all emit
      sites + tests (type-widening cross-consumer grep) (AC4).
- [ ] 5.2 Amend ADR-044 — Amendment 2026-06-30 (lstat pre-filter retained; union confirm;
      warm memoization; destroy unchanged; union in Alternatives) (AC8).

## Phase 6 — Verify
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` green (real runner) (AC9).

## Post-merge (operator / automatable)
- [ ] P1 Assert 754ee124's actual on-disk `.git` shape (read-only probe) (AC10).
- [ ] P2 Exercise RECONCILE/WARM path (not COLD-only); confirm no strand + queryable
      self-stop. PR body Ref #5733; `gh issue close 5733` after repro (AC11).

## Review-time
- [ ] R1 `user-impact-reviewer` (un-pushed-work-loss + raw-identifier-leak modes).
- [ ] R2 `observability-coverage-reviewer` (self-stop layer citation on all 3 gates).
