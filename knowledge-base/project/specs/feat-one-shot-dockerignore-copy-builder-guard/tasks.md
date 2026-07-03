# Tasks — Generic `COPY --from=builder` / builder-`RUN` / `.dockerignore` re-include guard

Plan: `knowledge-base/project/plans/2026-07-03-feat-dockerignore-copy-builder-guard-plan.md`
Lane: single-domain · Threshold: none

> Deepened 2026-07-03: evaluator simplified to Set+prefix (no glob engine); functions inline in the
> test file (no `lib/` module); builder-`RUN .sh` leg added; classification tests trimmed.

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm build context root `apps/web-platform` (`web-platform-release.yml:50`).
- [ ] 0.2 Re-confirm git-tracked classification: context = `public`, `scripts/sandbox-canary.mjs`,
      `infra/sandbox-canary-argv.json`, 25 host-scripts, `scripts/assert-dev-signin-eliminated.sh`
      (builder RUN arg); build-generated = `.next`, `dist/server`, `next.config.mjs`.
- [ ] 0.3 Confirm suite discovery under `bun test plugins/soleur/` (bunfig ignores only `.worktrees/**`, `apps/web-platform/**`).

## Phase 1 — RED (failing test first)

- [ ] 1.1 Create `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` with the 4 functions
      inline as stubs (`findReincludeViolations` returns `[]`).
- [ ] 1.2 Fixture test (a): synthetic `COPY --from=builder /app/infra/new-baked.sh` + `infra/` excluded,
      no re-include, tracked → expect non-empty violations.
- [ ] 1.3 Fixture test (b): synthetic builder `RUN bash scripts/new-run.sh` + `scripts/` excluded,
      no re-include, tracked → expect non-empty violations.
- [ ] 1.4 Run the suite → both fixture tests RED (stub returns `[]`). Commit.

## Phase 2 — GREEN (implement functions inline)

- [ ] 2.1 `parseBuilderCopySources`: join `\`-continuations; locate `COPY (?:--\w+=\S+ )*--from=\S+`;
      last token = dst; keep `/app/`-prefixed srcs (strip `/app/`); record line.
- [ ] 2.2 `parseBuilderRunScriptSources`: slice `FROM … AS builder`→next `FROM`; per `RUN`, extract
      `(?:bash|sh|source|\.)\s+(\S+\.sh)\b`.
- [ ] 2.3 `dockerignoreExclusionModel`: excludedDirPrefixes (non-`!`/non-`#`/non-glob, trailing `/`
      stripped) + exact `!<path>` reincludes Set.
- [ ] 2.4 `findReincludeViolations`: union both parsers; skip non-tracked srcs (build-generated);
      flag context-sourced src iff an excluded prefix is its ancestor AND src ∉ reincludes.
- [ ] 2.5 Real tracked set via `git ls-files apps/web-platform` (strip prefix → Set).
- [ ] 2.6 Real-repo test: 0 violations against real Dockerfile + `.dockerignore`.
- [ ] 2.7 Non-vacuity + false-positive tests: parser finds ≥1 `/app/infra/…` + ≥1 `/app/public` +
      `scripts/assert-dev-signin-eliminated.sh`; `.next` skipped (untracked, under `.next/`).
- [ ] 2.8 Minimal evaluator unit tests: dir-prefix exclude→violation, exact `!`-reinclude→none,
      un-excluded top-level (`public`)→none.
- [ ] 2.9 Run suite → GREEN. Commit.

## Phase 3 — Regression + docs

- [ ] 3.1 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → green (unchanged).
- [ ] 3.2 Optional one-line "subsumed by generalized guard" comment in the size test (skip if risky).
- [ ] 3.3 `bun test plugins/soleur/` full shard → green.

## Acceptance verification

- [ ] All Pre-merge ACs in the plan pass; no Dockerfile/.dockerignore behavior change (repo already clean).
- [ ] RED fixture commit precedes GREEN implementation commit (`cq-write-failing-tests-before`).
