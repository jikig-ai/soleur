# Tasks — Durable agent-surface git-strand heal (#5733)

Plan: `knowledge-base/project/plans/2026-06-30-fix-durable-agent-surface-rev-parse-strand-heal-plan.md`
Lane: cross-domain (no spec.md on one-shot path → defaulted, fail-closed).
Threshold: single-user incident → CPO sign-off + `user-impact-reviewer` at review.
Deepened 2026-06-30 (8 review lenses). Mechanism: host `rev-parse` confirm for
`dir-valid` shapes (A) + agent-context observability backstop (C2), one shared helper.

## Phase 0 — GATING shape confirmation + preconditions (no code)
- [x] 0.1 Confirm 754ee124's live on-disk `.git` shape (read-only probe) — branch:
      corrupt-dir-valid (A heals) / object-store residual (C2 only) / pointer. If the
      live workspace is unreachable from the work env, proceed building A+C2 (C2 makes
      the plan shape-robust) and confirm post-merge (AC11).
- [x] 0.2 Verify `git rev-parse --is-inside-work-tree` semantics + `GIT_CEILING_DIRECTORIES`
      (abs, symlink-resolved parent) no-ascension incl. a symlinked `/workspaces`
      component. Pin output.
- [x] 0.3 Read hardened spawn precedent `git-auth.ts:283-309`; locate the C2 hook at
      the agent-Bash onToolUse mirror (`tool-labels.ts:198` "Unknown Bash verb"); read
      the sync `gitDirValid` seam `cc-dispatcher.ts:1886`.
- [x] 0.4 Grep `rm(` in `ensure-workspace-repo.ts`: exactly two `.git` sites (`:174`,
      `:236`); `:354` is tmp-clean (exclude).

## Phase 1 — Probe + shared helper + failing tests (RED)
- [x] 1.1 Add `hostGitRevParseOutcome(workspacePath)` → `"worktree"|"not-a-worktree"|"inconclusive"`:
      `execFileAsync("git",[array])`, hardened env (`GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL=/dev/null`/`GIT_TERMINAL_PROMPT=0`,
      NO install token), ~2s timeout + `maxBuffer` + `killSignal` (AC1, AC2).
- [x] 1.2 Add shared `evaluateAgentReadiness(workspacePath, ctx)` → `"ready"|"block"`:
      dir-valid confirm, inconclusive re-probe + FAIL-OPEN, self-stop emit on
      not-a-worktree (AC3, AC4).
- [x] 1.3 RED tests `test/server/agent-ready-git-worktree.test.ts`: worktree→ready,
      not-a-worktree→block+emit, inconclusive(×2)→ready(fail-open)+breadcrumb, ceiling
      incl. symlinked parent, env asserts no token, no stderr/path in `extra`.

## Phase 2 — Cold gate (cc-dispatcher) GREEN
- [x] 2.1 Call `evaluateAgentReadiness` after the existing lstat self-heal; `"block"` →
      `RepoNotReadyError` (re-probe AFTER `resolveRepoReadinessWithSelfHeal` returns
      `healed.ok=true`; do NOT replace the sync `gitDirValid` seam).
- [x] 2.2 Update the stale `:1802-1806` "adds no subprocess" comment (AC9).

## Phase 3 — Warm gate (cc-reprovision) GREEN
- [x] 3.1 Call the helper; `"block"` → `"failed"` outcome (no spawn). **No memoization.**

## Phase 4 — Reconcile gate (workspace-reconcile-on-push) GREEN
- [x] 4.1 Swap `:357` gate AND `:368` `recovered` re-probe to the helper verdict.
- [x] 4.2 Emit on unrecovered/benign-skip (`:384-398`); assert ONE spawn per event (AC8).

## Phase 5 — C2 backstop + event widening + ADR
- [x] 5.1 Wire C2 emit at the agent-Bash mirror on in-sandbox rev-parse not-a-worktree
      (distinct source tag) (AC5, AC7).
- [x] 5.2 Widen `reportAgentReadinessSelfStop` with `gitRevParseValid`; NO subprocess
      stderr/path in `extra`; update all emit sites + tests (type-widening grep).
- [x] 5.3 Amend ADR-044 — **supersede** AC7 zero-await for connected cold (not
      "retained"); dir-valid-only confirm + rejected bwrap-reproduction in Alternatives;
      destroy unchanged (AC9).
- [x] 5.4 Write-boundary test: exactly two `.git`-targeting `rm` (`:174`,`:236`),
      `:354` excluded (AC6).

## Phase 6 — Verify
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run` (real runner) (AC10).

## Post-merge (operator / automatable)
- [ ] P1 Confirm 754ee124's actual on-disk shape on the live prod surface (AC11).
- [ ] P2 Exercise RECONCILE/WARM (not COLD-only); confirm no strand + queryable
      self-stop (host pre-heal OR C2). PR body Ref #5733; `gh issue close 5733` after
      repro (AC12).

## Review-time
- [ ] R1 `user-impact-reviewer` (un-pushed-work-loss + raw-identifier/stderr-leak modes).
- [ ] R2 `observability-coverage-reviewer` (self-stop layer citation; C2 + all 3 gates).
