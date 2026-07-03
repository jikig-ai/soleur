# Tasks — Generic `COPY --from=builder` / `.dockerignore` re-include guard

Plan: `knowledge-base/project/plans/2026-07-03-feat-dockerignore-copy-builder-guard-plan.md`
Lane: single-domain · Threshold: none

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm build context root `apps/web-platform` (`web-platform-release.yml:50`).
- [ ] 0.2 Re-confirm git-tracked classification of the 7 `COPY --from=builder` srcs
      (context: `public`, `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json`, 25 host-scripts;
      generated: `.next`, `dist/server`, `next.config.mjs`).
- [ ] 0.3 Confirm suite discovery under `bun test plugins/soleur/` (bunfig ignores only `.worktrees/**`, `apps/web-platform/**`).

## Phase 1 — RED (failing test first)

- [ ] 1.1 Create `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` importing `./lib/dockerfile-copy-parity`.
- [ ] 1.2 Add gap-demonstration fixture test: synthetic infra-baked COPY with no `!re-include` → expect a violation.
- [ ] 1.3 Add assertion that the old host-scripts-scoped regex does NOT match a single-line infra COPY.
- [ ] 1.4 Run `bun test plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` → confirm RED. Commit.

## Phase 2 — GREEN (implement helper)

- [ ] 2.1 Create `plugins/soleur/test/lib/dockerfile-copy-parity.ts`:
      `parseBuilderCopySources`, `isIgnoredByDockerignore`, `findBuilderCopyReincludeViolations`.
- [ ] 2.2 Parser: join `\`-continuation; strip `COPY`/`--from=`/`--chown=`/`--chmod=`; last token = dst; keep `/app/`-prefixed srcs; record line.
- [ ] 2.3 Evaluator: order-sensitive, negation-aware, trailing-slash-normalized, dir-prefix + `*`/`**` glob, last-match-wins.
- [ ] 2.4 Composed guard: skip non-tracked (build-generated) srcs; flag context-sourced srcs that evaluate excluded.
- [ ] 2.5 Build real tracked set via `git ls-files apps/web-platform` (strip prefix → Set).
- [ ] 2.6 Real-repo test: 0 violations against real Dockerfile + `.dockerignore`.
- [ ] 2.7 Classification tests (`.next`/`dist/server`/`next.config.mjs` skipped; sandbox-canary satisfied) + non-vacuity (7 statements).
- [ ] 2.8 Evaluator unit tests (dir-prefix exclude, exact negation re-include, ordering, un-excluded top-level).
- [ ] 2.9 Run suite → GREEN. Commit.

## Phase 3 — Regression + docs

- [ ] 3.1 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → green (unchanged).
- [ ] 3.2 Optional one-line "subsumed by generalized guard" comment in the size test (skip if risky).
- [ ] 3.3 `bun test plugins/soleur/` full shard → green.

## Acceptance verification

- [ ] All Pre-merge ACs in the plan pass; no Dockerfile/.dockerignore behavior change (repo already clean).
