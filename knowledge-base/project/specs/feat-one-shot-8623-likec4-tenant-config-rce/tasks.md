# Tasks: C4 re-render must never load a tenant's likec4 config (#8623)

Plan: `knowledge-base/project/plans/2026-09-24-fix-c4-render-tenant-likec4-config-execution-plan.md`

## Phase 1: Measure (RED on current code)

- [ ] 1.1 `.github/workflows/ci.yml` `test-webplat`: add `npm install -g likec4@1.50.0` (literal) and `LIKEC4_REQUIRED: "1"` on the "Run webplat tests (vitest --shard)" step env
- [ ] 1.2 Write `apps/web-platform/test/c4-render-tenant-config.test.ts` against the current `renderC4Model(workspacePath)`: tracked config, untracked config, untracked symlinked dir rows; sentinel outside every render temp dir; H1 control; binary resolution (`LIKEC4_BIN`/PATH; throw under `LIKEC4_REQUIRED`, else skip with install command); set `LIKEC4_BIN` before a dynamic import
- [ ] 1.3 Run it → RED; record the pre-fix commit SHA and the failing assertion lines (sentinel only) for the PR body; do not push Phase 1 alone

## Phase 2: Stage module (TDD)

- [ ] 2.1 `apps/web-platform/test/helpers/fake-github-trees.ts`: in-memory `{ path: { mode, bytes } }` map via `vi.mock("@/server/github-api")`; `?ref=`/`?recursive=1`; real `GitHubApiError` 404 shape; Contents lists symlinks/submodules as `"file"`; overrides (truncated, stall, 404-once, PUT 409); header records the verifying `gh api` commands and date
- [ ] 2.2 `apps/web-platform/test/c4-stage-sources.test.ts` (write first): H3; 9 config names top level + nested; nested symlink file/dir; `diagrams` symlink/submodule; symlinked parent (non-array); gitlink; truncated; 201 sources; >16 MiB of sources; path escape → io_error; 404-once; stall → deadline; refusals make zero blob GETs, no `<dir>/src`, return relative `path` + `more`
- [ ] 2.3 Implement `apps/web-platform/server/c4-stage-sources.ts` (`stageCommittedC4Sources`, result type per plan Shape; `wx`/`0600` writes; under-root assertion; `modelSha` from the listing)

## Phase 3: Wire the render

- [ ] 3.1 `apps/web-platform/server/c4-render.ts`: `renderC4Model(stage)`; mkdtemp → stage `<dir>/src` under a 10 s deadline before `acquire()`; `runLikeC4(<dir>/src, <dir>/model.likec4.json)`; widen `RenderReason` with `unsafe_source`; rewrite the SECURITY comment
- [ ] 3.2 `apps/web-platform/server/c4-writer.ts`: `RerenderInput` + `commitSha`; missing-sha path; build `stage`; `warnSilentFallback` for `unsafe_source` with `extra.refusalClass`; diagnostics per the plan table; model PUT with the listing's model sha + 409/422 re-list (retry once or superseded); `buildRerenderDiagnostic` takes the render result
- [ ] 3.3 `apps/web-platform/server/c4-concierge-tools.ts` description + `apps/web-platform/server/cc-dispatcher.ts` `c4PromptAddendum`: relay `rerenderDiagnostic`, no refresh promise then, unsupported files are changed in the GitHub repository
- [ ] 3.4 Update `apps/web-platform/test/c4-render.test.ts` (fake `stage`, cwd/-o assertions, stage-failure mapping, stalled-stage slot row)
- [ ] 3.5 Update `apps/web-platform/test/c4-writer-rerender.test.ts` (commitSha, missing sha, each diagnostic verbatim, warn vs report, PUT sha, 409 retry vs superseded)
- [ ] 3.6 Switch the acceptance suite to `renderC4Model(stage)` with the fake from the same fixture map; tracked-config refusal; benign `{u, s}`; `TMPDIR` config row; H1 control
- [ ] 3.7 `apps/web-platform/test/c4-render-boundary.test.ts`: no `"knowledge-base"` literal and no `readdir(`/`opendir(`/`lstat(` in `c4-render.ts` / `c4-stage-sources.ts`; `LIKEC4_BIN` only in `server/c4-render.ts`
- [ ] 3.8 `./node_modules/.bin/tsc --noEmit` — fix every `RenderReason` consumer it reports

## Phase 4: Records

- [ ] 4.1 ADR-050 amendment (2026-09-24, #8623); ADR-235 2026-09-23 residual bullet → closed
- [ ] 4.2 Append the re-render clause to the `api -> github` edge in `model.c4`; `bash scripts/regenerate-c4-model.sh`; run `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`
- [ ] 4.3 Exposure assessment `knowledge-base/legal/audits/2026-09-24-8623-c4-render-exposure-assessment.md` + `knowledge-base/legal/breach-register.md` row (limbs L1 Flagsmith, L2 GitHub App scan; INCONCLUSIVE with reason if not runnable; no tenant identifiers)

## Phase 5: Verify

- [ ] 5.1 `./node_modules/.bin/vitest run test/c4-stage-sources.test.ts test/c4-render.test.ts test/c4-writer-rerender.test.ts test/c4-render-tenant-config.test.ts test/c4-render-boundary.test.ts test/c4-likec4-version-pin.test.ts` (with `LIKEC4_BIN` → likec4@1.50.0)
- [ ] 5.2 `tsc --noEmit` clean
- [ ] 5.3 Record the likec4 install time per `test-webplat` shard in the PR body
- [ ] 5.4 Non-gating: measure whether a sandboxed agent can write `.git/hooks/*` / `.git/config`; writable → private GitHub Security Advisory; denied → evidence in the PR body
