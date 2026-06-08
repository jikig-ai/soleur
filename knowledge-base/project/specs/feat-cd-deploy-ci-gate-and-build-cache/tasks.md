---
feature: cd-deploy-ci-gate-and-build-cache
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-08-feat-cd-deploy-ci-gate-and-build-cache-plan.md
issue: 5052
pr: 5051
---

# Tasks: Gate prod deploy on CI + Docker layer cache

> Source of truth is the plan. This is the execution checklist. Brand-survival
> threshold = single-user incident → WS1 fail-closed correctness is load-bearing.

## Phase 0 — Preconditions (verify before editing)

- [x] 0.1 Confirm `test` is the required-context on ruleset 14145388 (ci.yml synthetic
  aggregator comment) — do NOT rename it.
- [x] 0.2 Confirm `ci.yml` push trigger has NO path filter (CI always runs for every main SHA).
- [x] 0.3 Resolve `docker/setup-buildx-action` latest-v3 **40-char** SHA (deref annotated tag):
  `gh api repos/docker/setup-buildx-action/git/ref/tags/<v3.x.x> --jq .object.sha` (+ deref if
  `.object.type=="tag"`). Record SHA + `# vX.Y.Z`.
- [x] 0.4 Verify `SENTRY_AUTH_TOKEN` is builder-stage-only in the Dockerfile:
  `awk '/AS runner/,0' apps/web-platform/Dockerfile | grep -c SENTRY_AUTH_TOKEN` → `0` (gates mode=min safety / AC4b).
- [x] 0.5 Note: first Edit on any `.github/workflows/*.yml` may be advisory-blocked by
  `security_reminder_hook.py` — retry the identical call or edit via Bash.

## Phase 1 — WS1: `await-ci` deploy gate (safety; fail-closed)

- [x] 1.1 Add `await-ci` job to `.github/workflows/web-platform-release.yml` (plan §1.1 verbatim):
  - [x] 1.1.1 `if: github.event_name == 'push'`; `permissions: { contents: read, checks: read, actions: read }`; `timeout-minutes: 20`.
  - [x] 1.1.2 Poll loop: var-based jq (NOT pipe-into-grep); select most-recent NON-cancelled `test` check-run; `//{}`/`//"missing"`/`//"none"` guards; stderr captured to a file.
  - [x] 1.1.3 ONLY `exit 0` is inside the `conclusion=="success"` branch; all else `exit 1` (query-error→continue, non-success terminal, timeout, no-CI-run-after-grace).
  - [x] 1.1.4 Fast no-CI-run fail-closed after `GRACE_ATTEMPTS` via `actions/workflows/ci.yml/runs?head_sha=$SHA` count==0. (Latency optimization, NOT a 2nd safety mechanism.)
  - [x] 1.1.5 NO skip-token bypass, NO `head_commit.message` read. All dynamic values via `env:` + quoted `"$VAR"`.
  - [x] 1.1.6 Poll-window comment notes it is INDEPENDENT of the deploy-job STATUS/HEALTH/IN_FLIGHT drift assertion.
- [x] 1.2 Extend `deploy` job (plan §1.2): add `await-ci` to `needs:`; add
  `(needs.await-ci.result == 'success' || (github.event_name == 'workflow_dispatch' && needs.await-ci.result == 'skipped'))`
  conjunct to the existing `always() && …` `if:`. Touch NOTHING else in the deploy job.

## Phase 2 — WS2: Docker layer cache (velocity)

- [x] 2.1 Add `docker/setup-buildx-action@<40-hex SHA> # vX.Y.Z` step before the build-push step
  in `reusable-release.yml`, gated `if: steps.version.outputs.next != '' && inputs.docker_image != ''`.
- [x] 2.2 Add to the `docker/build-push-action` `with:`: `cache-from: type=gha,scope=web-platform-release`
  + `cache-to: type=gha,mode=min,scope=web-platform-release`, with the `mode=min`↔runner-secret
  tripwire comment immediately above `cache-to` (security P2-2).
- [x] 2.3 `apps/web-platform/Dockerfile`: add a comment above the runner stage's first heavy `RUN`
  documenting the ordering invariant (heavy installs stay above `ENV BUILD_SHA` to remain cache
  hits). **Comment-only** — no `RUN`/`COPY`/`ENV`/`FROM`/`ARG` logic change (AC6).

## Phase 3 — Verification (no SSH)

- [x] 3.1 `actionlint .github/workflows/web-platform-release.yml .github/workflows/reusable-release.yml` (AC1).
- [x] 3.2 Extract the `await-ci` run-block and `bash -n` it (AC1).
- [x] 3.3 Dry-run the poll jq against a real merged SHA's `check-runs` JSON: success / failure /
  missing / cancelled-exclusion branches behave per Test Scenarios.
- [x] 3.4 Run the AC greps: AC2 (`grep -c 'exit 0'`==1, success-guarded), AC3 (diff scope),
  AC4 (40-char + tag-deref), AC4b (`SENTRY_AUTH_TOKEN` not in runner), AC5 (`test` unchanged),
  AC6 (Dockerfile comment-only diff).

## Phase 4 — Ship

- [ ] 4.1 PR body: note manual check-runs polling is justified (post-merge, no PR context);
  `Closes #5052`. Mark PR ready.
- [ ] 4.2 Post-merge: verify AC7 (`await-ci` gates deploy), AC8 (2nd release shows CACHED lines
  45–96), AC9-equivalent (deploy steps unchanged) via `gh run view` — no SSH.
- [ ] 4.3 `/compound` the `type=gha` BuildKit setup (first such learning in the KB).

## Deferred (tracking issues filed at plan-end)

- [ ] OS1 (#5054) — parallelize `migrate` with the build (separate PR; touches release.outputs contracts).
- [ ] OS2 (#5055) — reorder prod-deps `COPY`+`npm ci --omit=dev` above the `BUILD_*` ARG/ENV block to
  recover the line-114 layer (image-equivalent; separate PR due to AC6 comment-only constraint).
