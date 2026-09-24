# Tasks: C4 re-render must never load a tenant's likec4 config (#8623)

Plan: `knowledge-base/project/plans/2026-09-24-fix-c4-render-tenant-likec4-config-execution-plan.md` (deepened 2026-09-24)

## Phase 0: Staging-root precondition (gating)

- [x] 0.1 Measure whether a sandboxed agent can write the server's `os.tmpdir()` and the proposed `C4_RENDER_STAGING_ROOT` (test over `buildAgentSandboxConfig` output in `apps/web-platform/server/agent-runner-sandbox-config.ts`; dev-session probe if the SDK adds implicit writable temp paths); record in the PR body
- [x] 0.2 Pick the root (default `path.join(os.homedir(), ".cache", "soleur-c4-render")`, env-overridable); if the sandbox can read it, add it to `denyRead` with a test

## Phase 1: Measure (RED on current code)

- [x] 1.1 `.github/workflows/ci.yml` `test-webplat`: add `npm install -g likec4@1.50.0` (literal) and `LIKEC4_REQUIRED: "1"` on the "Run webplat tests (vitest --shard)" step env
- [x] 1.2 Write `apps/web-platform/test/c4-render-tenant-config.test.ts` against the current `renderC4Model(workspacePath)`: tracked config, untracked config, untracked symlinked dir rows; sentinel via `writeFileSync` to an absolute path outside every render dir; H1 control; binary resolution (throw under `LIKEC4_REQUIRED`, else skip with the install command); `vi.stubEnv` + `vi.resetModules()` + dynamic import; `vi.unstubAllEnvs()`; timeout ≥ 30 s
- [x] 1.3 Run it → RED; record the pre-fix commit SHA and the failing assertion lines (sentinel only) for the PR body; do not push Phase 1 alone

## Phase 2: Stage module (TDD)

- [x] 2.1 `apps/web-platform/test/helpers/fake-github-trees.ts`: in-memory map via `vi.mock("@/server/github-api")`; measured Contents behaviours (dir symlink `"symlink"`, file symlink `"file"`, path through dir symlink 404, submodule `"file"`); real git blob hashes, blobs served by sha; reported `size` without bytes; commits + HEAD with PUT `sha` precondition (409 stale, 422 missing); overrides (truncated, stall, 404-once, 403/429); concurrency recorder; header records the verifying `gh api` commands and date
- [x] 2.2 `apps/web-platform/test/c4-stage-sources.test.ts` (write first): every row in plan Phase 2.2 (H3 with >4 MiB / >50 non-source entries, identical-content sources, 9 config names top + nested, config-named directory staged, `node_modules` skipped, symlinks/submodule/through-symlink 404, gitlink, truncated, 51 sources, >4 MiB sources, size mismatch, path escape, 404-once, 403/429, stall → deadline with no leftover `<dir>`, ≤ 8 in flight, refusal invariants, no foreign `ref=`)
- [x] 2.3 `apps/web-platform/server/github-api.ts`: optional `{ signal }` on `githubApiGet` (`AbortSignal.any` with the per-attempt timeout; no retry after caller abort); `rg -n 'githubApiGet\(' apps/web-platform` to confirm no caller breaks
- [x] 2.4 Implement `apps/web-platform/server/c4-stage-sources.ts` (`stageCommittedC4Sources`, result type per plan Shape; non-recursive `mkdir(<dir>/src)`; abort check before every write; `wx`/`0600`; under-root assertion; `modelSha` from the listing)

## Phase 3: Wire the render

- [x] 3.1 `apps/web-platform/server/c4-render.ts`: `renderC4Model(stage)`; `mkdtemp` under `C4_RENDER_STAGING_ROOT`; stage before `acquire()` under an abortable 10 s deadline; `runLikeC4(<dir>/src, <dir>/model.likec4.json)`; widen `RenderReason` with `unsafe_source`; SECURITY comment (new boundary, non-TTY stdout keeps likec4's update check off, never `CI=true`)
- [x] 3.2 `apps/web-platform/server/c4-writer.ts`: `RerenderInput` + `commitSha`; missing-sha path; build `stage`; `warnSilentFallback` for `unsafe_source` with `tags: { reason, refusalClass, phase }` and no path in tags/extra; diagnostics per the plan table (path reduced to `[A-Za-z0-9._/-]`, ≤ 60 chars); model PUT with the listing's model sha + 409/422 re-list on (path, blob sha) sets, retry once, superseded at `logger.warn`, second 409 / re-list throw → `reportSilentFallback` op `commit-json`; `buildRerenderDiagnostic` takes the render result
- [x] 3.3 `apps/web-platform/server/c4-concierge-tools.ts` description + `apps/web-platform/server/cc-dispatcher.ts` `c4PromptAddendum`: relay the diagnostic as quoted data; no refresh promise then; fix unsupported files in the GitHub repository; never remove/shrink content or retry without confirmation; keep the no-diagnostic "will refresh" branch
- [x] 3.4 `apps/web-platform/test/c4-concierge-copy.test.ts` pinning both copies
- [x] 3.5 Update `apps/web-platform/test/c4-render.test.ts` (add `mkdir` to the fs mock; fake `stage`; cwd/-o assertions; stage-failure mapping; stall `POOL_SIZE` stages and assert a third render spawns)
- [x] 3.6 Update `apps/web-platform/test/c4-writer-rerender.test.ts` (commitSha, missing sha, each diagnostic verbatim, warn vs report + tags, PUT sha, reverse-order same-file saves, README-only retry, second 409 no loop, superseded warn)
- [x] 3.7 Switch the acceptance suite to `renderC4Model(stage)`: tracked-config refusal row; allowlist battery row (refusal disabled, still not staged, `{u, s}`); benign `{u, s}`; staging-root fixture row with recorded `destDir`; H1 via the real `runLikeC4`; H2 as a child vitest run
- [x] 3.8 `apps/web-platform/test/c4-render-boundary.test.ts`: comments stripped; `node:fs*` import allowlists; `expectTypeOf(renderC4Model).parameters`; `LIKEC4_BIN` only in `server/c4-render.ts`
- [x] 3.9 `./node_modules/.bin/tsc --noEmit` — fix every `RenderReason` consumer it reports

## Phase 4: Records

- [x] 4.1 ADR-050 amendment (2026-09-24, #8623: invariant, GitHub trusted only for modes/bytes at a fixed sha, staging root, residual → #8696); ADR-235 2026-09-23 residual bullet → closed
- [x] 4.2 Append the re-render clause to the `api -> github` edge in `model.c4`; `bash scripts/regenerate-c4-model.sh`; run `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`
- [x] 4.3 Exposure assessment `knowledge-base/legal/audits/2026-09-24-8623-c4-render-exposure-assessment.md` + `knowledge-base/legal/breach-register.md` row (L1 Flagsmith, L2 GitHub App scan; INCONCLUSIVE with reason if not runnable; no tenant identifiers)

## Phase 5: Verify

- [x] 5.1 `./node_modules/.bin/vitest run test/c4-stage-sources.test.ts test/c4-render.test.ts test/c4-writer-rerender.test.ts test/c4-render-tenant-config.test.ts test/c4-render-boundary.test.ts test/c4-concierge-copy.test.ts test/c4-likec4-version-pin.test.ts` (with `LIKEC4_BIN` → likec4@1.50.0)
- [x] 5.2 `tsc --noEmit` clean
- [x] 5.3 Record the likec4 install time per `test-webplat` shard in the PR body (run 35976476106: 10 s on 1/2, 9 s on 2/2)
- [x] 5.4 Non-gating: measure whether a sandboxed agent can write `.git/hooks/*` / `.git/config`; writable → private GitHub Security Advisory; denied → evidence in the PR body
