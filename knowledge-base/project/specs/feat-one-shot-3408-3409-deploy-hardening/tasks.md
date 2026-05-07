# Tasks — feat-one-shot-3408-3409-deploy-hardening

Derived from `knowledge-base/project/plans/2026-05-07-feat-deploy-pipeline-hardening-3408-3409-plan.md` (deepened 2026-05-07). Resolves #3408 (pre-rerun lock probe) and #3409 (build-sha verification on /health). Both deferred from #3398.

**Deepen findings to honor at implementation time:**

- Phase 3.1 prescription: do NOT cite `cq-align-ci-poll-windows-with-adjacent-steps` in the new probe step's comments — that rule is referenced widely but never defined. Use direct constant references (`# IN_FLIGHT_CEILING_S below must equal STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S`) instead.
- Phase 3.2 prescription: position `build_sha: string;` between `version: string;` (line 37) and `supabase: string;` (line 38) in `HealthResponse`. Identity-field grouping convention.
- Phase 2 test pattern: mirror `health.test.ts:63 "includes standard health fields"` (the `expect(response).toHaveProperty(...)` style) — there is no dedicated `version` test to mirror.
- Phase 3.4 reusable-release.yml edit: only the web-platform path consumes the new `BUILD_SHA` build-arg. Plugin path is gated `if: inputs.docker_image != ''` at `reusable-release.yml:433`. Zero blast radius.

## 1. Setup

- [x] 1.1 Verify worktree on `feat-one-shot-3408-3409-deploy-hardening` branch.
- [x] 1.2 Read the plan in full before editing any file.
- [x] 1.3 Confirm `apps/web-platform/server/health.ts` and `apps/web-platform/server/index.ts:53` are the load-bearing /health surfaces (NOT `app/api/health/route.ts` — that path does not exist).

## 2. RED — Write failing tests first

- [x] 2.1 Edit `apps/web-platform/test/server/health.test.ts`:
  - 2.1.1 Add `it("includes build_sha as 'dev' when BUILD_SHA is unset", ...)` asserting `(await buildHealthResponse()).build_sha === "dev"` after `delete process.env.BUILD_SHA`.
  - 2.1.2 Add `it("includes build_sha from BUILD_SHA env var when set", ...)` setting `process.env.BUILD_SHA = "abc1234deadbeef"` and asserting `.build_sha === "abc1234deadbeef"`.
- [x] 2.2 Run `bun run test apps/web-platform/test/server/health.test.ts` — both new cases must FAIL (TS error: field not on interface; runtime undefined).

## 3. GREEN — #3409 build-sha pathway

- [x] 3.1 `apps/web-platform/server/health.ts`: add `build_sha: string` to `HealthResponse` (positioned after `version`).
- [x] 3.2 `apps/web-platform/server/health.ts`: in `buildHealthResponse()`, set `build_sha: process.env.BUILD_SHA || "dev"`.
- [x] 3.3 `apps/web-platform/Dockerfile`: add `ARG BUILD_SHA=dev` + `ENV BUILD_SHA=$BUILD_SHA` next to the existing `BUILD_VERSION` block (lines 56-57). Same comment style.
- [x] 3.4 `.github/workflows/reusable-release.yml`: append `BUILD_SHA=${{ github.sha }}` to the docker-build step's `build-args` block (around line 451). One new line; do not reorder existing args.
- [x] 3.5 Re-run `bun run test apps/web-platform/test/server/health.test.ts` — both new cases must now PASS.
- [x] 3.6 Run `bun run typecheck` — no new errors. Verify `InternalMetricsResponse` (which extends `HealthResponse`) compiles without explicit edit.

## 4. GREEN — #3408 pre-rerun lock probe

- [x] 4.1 `.github/workflows/web-platform-release.yml`: insert `Pre-rerun lock probe` step at the TOP of the `deploy` job's `steps:` array, before `Deploy via webhook`. Use the skeleton in plan Phase 3.1.
  - 4.1.1 Env block lists `WEBHOOK_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `IN_FLIGHT_CEILING_S: 900`.
  - 4.1.2 GET `/hooks/deploy-status` with HMAC-empty-body signature (mirror existing pattern from lines 248-258).
  - 4.1.3 Degraded-permissive on non-JSON / empty body (`exit 0` with log line).
  - 4.1.4 Block (`exit 1` with `::error::`) ONLY when `.exit_code == -1` AND `(now - start_ts) <= 900s`.
  - 4.1.5 Log `prior_tag`, `elapsed`, in success/block paths.
- [x] 4.2 `.github/workflows/web-platform-release.yml`: extend `Verify deploy health and version` step (line ~309) with a build-sha gate inside the existing success branch:
  - 4.2.1 `DEPLOYED_SHA=$(echo "$HEALTH" | jq -r '.build_sha // empty')` and `EXPECTED_SHA="${{ github.sha }}"`.
  - 4.2.2 Missing/`dev` value → loop with retry log line ("possibly mid-swap").
  - 4.2.3 Mismatch → fail-fast `exit 1` with `::error::version=$VERSION supabase=connected but build_sha=$DEPLOYED_SHA (expected $EXPECTED_SHA)`.
  - 4.2.4 Match → existing "Deploy verified" log line, augmented with `build_sha=$DEPLOYED_SHA`.
- [x] 4.3 Add a comment on the `STATUS_POLL_MAX_ATTEMPTS` env block in the verify-completion step cross-linking to the new probe's `IN_FLIGHT_CEILING_S` (bidirectional).

## 5. Runbook update

- [x] 5.1 `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`: in the `Rerun Safety` section (line ~74), add a paragraph noting that `web-platform-release.yml` deploy job now self-gates against in-flight POSTs.
- [x] 5.2 Cross-link issue #3408 in the section's reference list.

## 6. Verification

- [x] 6.1 `bun run typecheck` — green.
- [x] 6.2 `bun run test apps/web-platform/test/server/health.test.ts` — green (existing + 2 new cases).
- [x] 6.3 `bun run test apps/web-platform/test/` — full server-test directory green.
- [x] 6.4 `actionlint .github/workflows/web-platform-release.yml` if locally available; otherwise rely on lefthook + CI lint.
- [x] 6.5 Visual diff review of the workflow file: confirm step is positioned at top of `deploy` job, env block uses correct secret names, yaml indentation matches sibling steps.

## 7. Ship

- [ ] 7.1 PR body uses `Closes #3408` AND `Closes #3409` (both deferred chores).
- [ ] 7.2 Run `skill: soleur:compound` to capture any session learnings.
- [ ] 7.3 Run `skill: soleur:ship` for full lifecycle (review, preflight, merge).
- [ ] 7.4 Post-merge: trigger `workflow_dispatch` of `web-platform-release.yml` and verify in run logs:
  - Pre-rerun probe step appears, runs <2s.
  - "Deploy verified" log line includes `build_sha=<short>` matching `${{ github.sha }}` short-form.
- [ ] 7.5 Confirm both #3408 and #3409 close automatically on merge (PR-body `Closes` directives).
