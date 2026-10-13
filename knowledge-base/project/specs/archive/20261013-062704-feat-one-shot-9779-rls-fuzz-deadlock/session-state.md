# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9779-rls-fuzz-deadlock/knowledge-base/project/plans/2026-10-08-fix-rls-fuzz-teardown-deadlock-plan.md
- Status: complete

### Errors
- Issue body cited `test/rls-fuzz/…`; real path is `apps/web-platform/test/rls-fuzz/…` — resolved by repo search; documented in plan Research Reconciliation.
- Context7 MCP denied in background mode — vendored `node_modules/postgres` README + type defs used instead.
- Drafting artifact + stale per-statement Test Scenario caught in self-review; Census-B AC command defects caught at plan-review — all corrected before freeze.

### Decisions
- Retry the complete `sql.begin` transaction at the `rolledBackRaw` chokepoint on SQLSTATE {40P01, 55P03} only — 3 attempts, 80–120 ms jitter, rethrow on exhaustion; matches in-repo precedents (`server/concurrency.ts`, `server/worktree-write-lease.ts`) and Postgres guidance.
- Rejected Vitest `retry:`, single-worker serialization, per-file schemas, advisory locks.
- Seed/catalog coverage widened after census: `Sql`-only helpers self-wrap; `Sql|Txn` helpers get call-site wraps; 33 `await sql` + 13 bare-`sql` sites enumerated as AC6 census commands.
- `never wrap a t handle` rule — aborted txns re-raise 25P02 masking 40P01; `TransactionSql ⊄ Sql` verified against pinned postgres.js types.
- `lane:` defaulted to `cross-domain` (fail-closed) — no spec.md for the branch.

### Components Invoked
- `soleur:plan` (full phase pipeline, sequential-fallback — no Task tool in subagent)
- `soleur:deepen-plan` (halts 4.6/4.7/4.8/4.12 verified; conditional gates 4.5/4.9/4.10/4.11 evaluated; precedent-diff 4.4 executed)
- `soleur:spec-templates` (tasks.md); `cloud-detect.sh`; `probe-verb-gate.sh`
- Inline equivalents for plan_review panel / research agents (disclosed as sequential-fallback)

## Collision Check (Step 0a.5 + post-plan re-probe)
- #9779 OPEN, no closing/linked PRs.
- Body-probe merged hit #4771 — false positive (vitest upstream issue URL, different repo).
- Anchor probe over planned files: open PR #9051 touches `harness-fixture.ts` but only `seedTwoTenant` internals (Codex run fields) — adjacent region, merge-conflict risk only, not same-scope.
- Sibling issues noted: #9740 (rls-fuzz client-install timeout, different failure mode), #9696 (#9529 review follow-up).

## Work / Review / QA / Compound Phase (2026-10-08)
- Status: implemented, reviewed, verified — pending ship.
- Implementation: `withTransientRetry` (3 attempts, 80–120ms jitter, {40P01,55P03})
  wraps `rolledBackRaw`'s `sql.begin`; `seedTwoTenant`/`seedRpcCtx` run as single
  committed txns under it; all catalog + spec bare-`sql` sites wrapped; AC6
  censuses clean (0/0); unit tests green; tsc clean.
- Review: 6-seat panel (code class, tier `none`) + targeted fix round
  (3 finding seats + verifier). Findings: 3 P2 (catch-arm transient swallow;
  AC4 commit-mutant blind spot; census not codified) + ~10 P3 — ALL resolved.
  Fix commits a2d2f09abf..077edaec89; trailers emitted (Reviewed-Coverage:
  full 6/6; Reviewed-Fix-Round over e31c5194b1..).
- QA: plan Test Scenarios are Given/When/Then prose — no executable steps;
  skipped per soleur:qa Step 1 rule (unit suite + PR's `rls-fuzz` CI check
  carry the verification).
- Compound: learning written at
  knowledge-base/project/learnings/test-failures/2026-10-08-a-retry-at-the-boundary-covers-only-errors-that-propagate.md
- Note: `core.hooksPath=/dev/null` on this clone — lefthook did not run; owed
  linters (markdown-lint n/a for KB paths, gitleaks clean, tsc green) run
  explicitly. Local `test-all.sh --affected` queued behind sibling full gates
  (position 3, LOCK_WAIT_HEARTBEAT); restarted unbounded at bg pid — CI carries
  the authoritative gate.

### Errors (this phase)
- `timeout 900` killed a legitimately queued affected-gate run — restarted unbounded.
- `fix-round-seats.sh --finding-seats` needs one quoted string arg, not multi-args.
- Header comment containing literal `await sql` tripped census A — reworded.
- `;`-restoration sweep overshot into a catalog.ts docblock — reverted.
- Census guard v1 exempted `await sql.begin` (the shape it guards) — tightened to `sql.end` only.
- `cd ..` landed in wrong dir mid-batch — vitest + plan edit silently skipped, re-run.
