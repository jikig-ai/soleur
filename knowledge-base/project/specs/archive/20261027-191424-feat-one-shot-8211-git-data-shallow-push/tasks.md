# Tasks — feat-one-shot-8211-git-data-shallow-push

Plan: `knowledge-base/project/plans/2026-10-27-fix-git-data-store-shallow-push-plan.md`
Issue: `Ref #8211` (never `Closes`)

## Phase 1 — Tests first (RED)

- [x] 1.1 Extend `apps/web-platform/test/git-data-remote-url-wrapper.test.ts`
  - [x] 1.1.1 Add `makeShallowClone(name)`: origin repo with ≥3 commits, then `git clone --depth 1 file://<origin>`; assert `git rev-parse --is-shallow-repository` is true
  - [x] 1.1.2 R-PUSH-SHALLOW: push `refs/heads/*:refs/soleur/worktrees/<WT>/heads/*` from the shallow clone through the real wrapper (`transportEnv()`); assert `push.status === 0` and the ref lands on the bare fixture repo (AC4)
  - [x] 1.1.3 R-FETCH-OVERLAY: re-mock `gitWithPrivateKeyAuth` as a real-git passthrough (`spawnSync("git", args, { cwd: opts.cwd, env: transportEnv() })`); fetcher is `--depth 1`; store ref tip sits below the fetcher's shallow boundary; call production `fetchFromGitData`; assert `refs/remotes/git-data/<branch>` resolves to the pushed sha (AC5)
- [x] 1.2 Extend `apps/web-platform/test/git-data-replication.test.ts` (AC6)
  - [x] 1.2.1 transient stderr `remote failure` → `gitPush` called 2×, returns `{status:"replicated"}`
  - [x] 1.2.2 `shallow update not allowed` → 1 call, rejects
  - [x] 1.2.3 fence reject (`stale lease generation`) → 1 call, rejects
  - [x] 1.2.4 two consecutive transients → 2 calls, still rejects
- [x] 1.3 Update `apps/web-platform/infra/git-data-transport-wrapper.test.sh` (AC7)
  - [x] 1.3.1 T2: receive-pack DRYRUN expectation gains `-c receive.shallowUpdate=true`
  - [x] 1.3.2 T11: literal-exec pin gains the new receive-pack branch line (generic line pin unchanged)
  - [x] 1.3.3 New case: upload-pack DRYRUN carries NO `receive.shallowUpdate`
  - [x] 1.3.4 Bump the exact floor to the new measured count

## Phase 2 — Implementation (GREEN)

- [x] 2.1 `apps/web-platform/infra/git-data-transport-wrapper.sh`: conditional `git-receive-pack` exec branch with `-c receive.shallowUpdate=true`; generic line preserved verbatim; DRYRUN branch mirrors each verb's argv; extend the `:125-131` comment (AC1, AC11)
- [x] 2.2 `apps/web-platform/server/git-data-client.ts`: `"--update-shallow"` immediately after `"fetch"` (~:250) (AC2)
- [x] 2.3 `apps/web-platform/server/git-data-replication.ts`: one-shot retry around the push (~:788-801), positive-match on `remote failure|failed to report status` in `err.stderr ?? err.message` (AC3)

## Phase 3 — Docs

- [x] 3.1 Runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` R3 row (~line 395): record 2026-10-27 re-run verdict FAILED (Better Stack `git-data replication push failed` hit, web-1 16:30:17Z; R4 stays blocked) + `git-data-host-replace`-only delivery note (AC8)
- [x] 3.2 Extend the `## Addendum — 2026-10-27 (#8211)` block in `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` (AC9)

## Phase 4 — Ship

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [x] 4.2 Run touched suites: vitest `git-data-remote-url-wrapper.test.ts` + `git-data-replication.test.ts`; `bash apps/web-platform/infra/git-data-transport-wrapper.test.sh`; `bash apps/web-platform/infra/git-data-cutover-access.test.sh` (parity arms must stay green)
- [ ] 4.3 PR body opens `Ref #8211`; no new issues; merge-safety proof stands (AC10)
