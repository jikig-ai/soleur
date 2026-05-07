---
date: 2026-05-07
type: feat
component: web-platform-release
issues: [3408, 3409]
parent_issue: 3398
priority: p3-low
complexity: medium
detail_level: more
requires_cpo_signoff: false
domains_relevant: [engineering]
---

# Deploy-Pipeline Hardening — Pre-Rerun Lock Probe (#3408) + Build-SHA Verification (#3409)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Reconciliation table, Acceptance Criteria, Phase 3, Risks, Sharp Edges (verification-grounded edits inline below the headings).
**Verification artifacts produced (live, not from memory):**

```bash
$ grep -n "BUILD_VERSION\|github.sha" .github/workflows/reusable-release.yml
440:            ${{ inputs.docker_image }}:${{ github.sha }}
451:            BUILD_VERSION=${{ steps.version.outputs.next }}

$ grep -n "ARG BUILD_VERSION\|ENV BUILD_VERSION" apps/web-platform/Dockerfile
56:ARG BUILD_VERSION=dev
57:ENV BUILD_VERSION=$BUILD_VERSION

$ grep -n "extends HealthResponse" apps/web-platform/server/health.ts
49:export interface InternalMetricsResponse extends HealthResponse {

$ git grep -l "uses: ./.github/workflows/reusable-release.yml" .github/workflows/
.github/workflows/version-bump-and-release.yml   # plugin component, NO docker_image input
.github/workflows/web-platform-release.yml       # web-platform component, docker_image set

$ gh label list --limit 200 | grep -E "^(domain/engineering|chore|priority/p3-low)\b"
priority/p3-low      Nice-to-have, no time pressure              #F9D0C4
domain/engineering   Plugin code, CI/CD, infra, docs site (CTO)  #0075CA
chore                Maintenance and configuration tasks         #c5def5
```

### Key Improvements

1. **Confirmed `${{ github.sha }}` is the load-bearing source of truth.** The reusable-release.yml docker-build step at line 440 already tags every image with `${{ github.sha }}` — the deploy job inherits the same SHA via the `push: branches: [main]` trigger. No `actions/checkout` needed in the deploy job. The plan's claim is verified.
2. **Reusable-workflow blast radius is even more bounded than originally stated.** The plan said "Buildx ignores unknown build-args." Live verification: the OTHER consumer of `reusable-release.yml` is `version-bump-and-release.yml` (plugin component) which does NOT pass `docker_image` — and the docker-build step is gated on `inputs.docker_image != ''`. So the new `BUILD_SHA=${{ github.sha }}` build-arg only ever fires for the web-platform component path. Zero blast radius on the plugin path.
3. **Phantom rule reference flagged.** `cq-align-ci-poll-windows-with-adjacent-steps` is cited in the existing workflow comments (lines 238 + 315), the prior 3398 plan, three learnings, and the plan body — but is NOT defined in `AGENTS.md` or `scripts/retired-rule-ids.txt`. It is a load-bearing-by-convention invariant that has no machine-enforcement layer. The new probe's `IN_FLIGHT_CEILING_S` constant cross-link comment (Phase 3.1) should reference the absolute workflow line numbers and the constant relationship explicitly, NOT the phantom rule ID — otherwise the comment compounds the unenforceable-rule debt.
4. **Test pattern correction.** Original plan said "mirrors the existing version-coverage style" — there is no dedicated version test. The pattern to mirror is `health.test.ts:63 "includes standard health fields"` which uses `expect(response).toHaveProperty("version")`. The new tests should mirror that property-style assertion plus an env-var override case, not invent a new style.
5. **`HealthResponse` field-ordering pin.** The plan said "positioned after `version`" — refined: positioned exactly between `version: string;` (line 37) and `supabase: string;` (line 38). The grouping convention in the file is `[identity fields → backend health fields → process fields]`; `build_sha` is an identity field and belongs immediately adjacent to `version`.
6. **`InternalMetricsResponse` requires no edit, confirmed live.** Line 49 `extends HealthResponse` — TypeScript inheritance picks up `build_sha` automatically. The plan's claim is verified.

### New Considerations Discovered

- **Phantom-rule documentation debt (TWO instances).** The deepen pass found that `cq-align-ci-poll-windows-with-adjacent-steps` is cited as if enforced but isn't defined in `AGENTS.md` or `scripts/retired-rule-ids.txt`. A second phantom rule, `cq-ci-steps-polling-json-endpoints-under`, is referenced at `web-platform-release.yml:327` and is also undefined. Both are load-bearing-by-convention citations spanning learnings, prior plans, and workflow comments. This is out of scope for the current PR (don't fold in a doc cleanup that touches 6+ files), but worth filing as a follow-up issue at ship time. The current plan must NOT introduce a third such citation — Phase 3.1 was edited above to use direct constant references instead.
- **Operator-surface log-line drift.** The current `Verify deploy health and version` step's success log is `"Deploy verified: version $VERSION running, supabase connected"`. Phase 3.2 prescribes appending `, build_sha=$DEPLOYED_SHA`. The Discord release notification + Better Stack monitor scrape this log via no canonical contract — a string drift here is operator-surface only (no machine consumer), so additive append is safe.
- **`InternalMetricsResponse` exposure.** Adding `build_sha` to `HealthResponse` automatically exposes it on `/internal/metrics` (loopback-gated) too. That's the desired behavior — the loopback-gated metrics endpoint is the local diagnostic surface, and SHA there is at parity with the public surface, no inconsistency.
- **Sentry startup-message spread.** `server/index.ts:118` already emits `Sentry.captureMessage(\`Server startup v${process.env.BUILD_VERSION || "dev"}\`, "info")`. Consider including the SHA in the same message at implementation time — out of scope for #3409 strictly, but a one-line Phase 3.x extension worth flagging. Defer to implementer judgment.

## Overview

Two surgical hardening fixes for `.github/workflows/web-platform-release.yml`, both deferred from #3398 (the 900s poll-ceiling raise that landed in PR #3391/#3398 follow-up). They ship in one PR because they touch the same workflow file and are both about narrowing the deploy step's failure modes:

- **#3408 — Pre-rerun lock probe.** Before the `Deploy via webhook` step POSTs `/hooks/deploy`, GET `/hooks/deploy-status` and short-circuit the workflow if the prior invocation is still in its critical section (`exit_code == -1`). The advisory `flock -n` in `ci-deploy.sh` already rejects concurrent POSTs (writes `reason=lock_contention` and exits 1), but the rejection masks the original deploy's actual fate. A pre-flight probe surfaces "still running" up-front instead of after a 900s downstream-step timeout.
- **#3409 — Build-SHA verification.** Extend the `/health` JSON contract to include `build_sha` (the git commit the image was built from) and assert it in `Verify deploy health and version` against `git rev-parse HEAD` from the workflow checkout. Defense-in-depth against a bad `tag → image` association: the existing version+supabase gates would pass even if the wrong commit's image were tagged with the right semver.

Neither fix is load-bearing on its own. Together they close two recurrence vectors flagged in the `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` learning's "Re-evaluation criteria" section.

## Research Reconciliation — Spec vs. Codebase

The issue bodies cite paths and contracts that don't all match the repo. Reconciled before planning to avoid paraphrase-without-verification drift (per the planning skill's gate):

| Spec claim (issue body) | Repo reality | Plan response |
|---|---|---|
| #3409 cites `apps/web-platform/app/api/health/route.ts` as the "current /health implementation" | No such file exists. `/health` is served by the **custom Bun/Node server** at `apps/web-platform/server/index.ts:53` via `buildHealthResponse()` exported from `apps/web-platform/server/health.ts:91`. App Router is mounted via `app.getRequestHandler()` only as the catch-all on the same server — `/health` is intercepted before that. | Plan edits `apps/web-platform/server/health.ts` (the response builder) and adds tests in `apps/web-platform/test/server/health.test.ts`. The workflow assertion edit is in `.github/workflows/web-platform-release.yml`. The orchestration in `server/index.ts` does NOT need to change — it already returns whatever `buildHealthResponse()` produces. |
| #3408 cites `/hooks/deploy-status` as the probe endpoint and `.exit_code` / `.tag` as the gate fields | Confirmed: `apps/web-platform/infra/ci-deploy.sh:54-65` defines `write_state` emitting `{start_ts,end_ts,exit_code,component,image,tag,reason}`. The endpoint is invoked exactly as the existing `Verify deploy script completion` step already does. | No infra-side change needed. The probe re-uses the existing HMAC-signed-empty-body GET pattern from lines 248-258 of the workflow. |
| #3409 prescribes `git rev-parse HEAD` from the workflow runner | Confirmed feasible: the deploy job runs on `ubuntu-latest` but does NOT currently `actions/checkout` — it only POSTs HMAC-signed payloads. `git rev-parse HEAD` would not work without a checkout. **However**, `${{ github.sha }}` is already injected by Actions and is the load-bearing source of truth (the docker-build step at `.github/workflows/reusable-release.yml:441` already tags the image with `${{ github.sha }}`). | Use `${{ github.sha }}` directly in the env block of the deploy job — no `actions/checkout` needed. This also keeps the deploy job's permissions surface unchanged (no `contents: read`). |
| #3409 implies `BUILD_VERSION` is the only build-arg pathway | Confirmed: `apps/web-platform/Dockerfile:56-57` declares `ARG BUILD_VERSION=dev` + `ENV BUILD_VERSION=$BUILD_VERSION`. `reusable-release.yml:441-451` passes `BUILD_VERSION` via `build-args`. | Mirror the same pattern for `BUILD_SHA`: add a Dockerfile `ARG BUILD_SHA=dev` + `ENV BUILD_SHA=$BUILD_SHA`, add a `BUILD_SHA=${{ github.sha }}` line to the docker-build step's `build-args`, and read `process.env.BUILD_SHA` in `buildHealthResponse()`. |

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing breakage. A misconfigured pre-rerun probe could spuriously block legitimate deploys (regression: workflow refuses to POST when `/hooks/deploy-status` returns transient noise). A misconfigured build-sha gate could cause `Verify deploy health and version` to never satisfy (regression: green container in prod, red workflow run, on-call paged). Both regressions present as **deployment-time failures the operator sees in CI logs immediately** — not silent prod incidents.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. The probe only reads existing CF-Access-gated webhook state. The `build_sha` field exposes the public git commit SHA — already in every release tag, every Discord release announcement, every public docker image tag. No new exposure.

**Brand-survival threshold:** none

Reason for `none`: Workflow-only change. No credentials, no auth, no data, no payments, no user-owned resources. The diff touches exactly two file classes: a CI workflow (operator surface) and a `/health` route that already exposes `version`, `uptime`, `memory`. Adding `build_sha` is monotonic with the existing surface.

- `threshold: none, reason: sensitive-path regex matches three planned edits (apps/web-platform/server/health.ts, .github/workflows/web-platform-release.yml, .github/workflows/reusable-release.yml) but each diff is additively scoped — health.ts adds one string field with no auth/PII semantic; the workflow edits add a CI gate and a build-arg without touching secret handling, auth headers, or runtime config — net new exposure surface is zero.`

## Domain Review

**Domains relevant:** engineering

This is an infrastructure/CI hardening change. No CMO, CPO, CLO, COO, CHRO, or product surface implications. CTO assessment carried below.

### Engineering (CTO)

**Status:** reviewed (single-pass inline)
**Assessment:** Both fixes are surgical, mechanically simple, and follow patterns already established in the repo:

- The pre-rerun probe re-uses the exact HMAC-empty-body GET pattern from the existing `Verify deploy script completion` step (lines 248-258 of the workflow). No new auth/signing surface.
- The build-sha extension follows the existing `BUILD_VERSION` pathway end-to-end (Dockerfile ARG → ENV → `process.env.X` → `buildHealthResponse()` → workflow gate). The mental model the operator already has for version-mismatch logs extends to sha-mismatch logs without surprise.
- Neither fix mutates a load-bearing defense; both *add* a defense in front of an existing one. Per the `2026-05-05-defense-relaxation-must-name-new-ceiling.md` learning, the "name the ceiling" cost only applies when relaxing — additions don't carry that cost.

**Sharp edge surfaced:** The pre-rerun probe is itself a network call that can fail transiently (CF tunnel hiccup, deploy-status webhook cold-start, HTTP 502 from the edge). The probe MUST be tolerant of non-JSON / no-response (re-using the existing fall-through behaviour at workflow lines 260-272), otherwise it becomes a new false-negative class. Plan addresses this in Phase 2.

### Product/UX Gate

Skipped — Product domain not relevant. No new pages, no new components, no copy, no flow. CI workflow + Bun-server route handler.

## Open Code-Review Overlap

None. Ran:

```bash
gh api 'repos/:owner/:repo/issues?labels=code-review&state=open&per_page=100' \
  > /tmp/open-review-issues.json
for path in .github/workflows/web-platform-release.yml \
            apps/web-platform/server/health.ts \
            apps/web-platform/server/index.ts \
            apps/web-platform/Dockerfile \
            plugins/soleur/skills/postmerge/references/deploy-status-debugging.md \
            apps/web-platform/test/server/health.test.ts; do
  jq -r --arg p "$path" '.[] | select(.body//"" | contains($p)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

Result: zero matches across 69 open code-review issues. No fold-in / acknowledge / defer decisions needed.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/server/health.ts` — `HealthResponse` interface includes `build_sha: string`.
- [x] `apps/web-platform/server/health.ts` — `buildHealthResponse()` populates `build_sha` from `process.env.BUILD_SHA || "dev"`.
- [x] `apps/web-platform/Dockerfile` — declares `ARG BUILD_SHA=dev` + `ENV BUILD_SHA=$BUILD_SHA`, mirroring the `BUILD_VERSION` block (same location, same comment style).
- [x] `.github/workflows/reusable-release.yml` — docker-build step `build-args` block adds `BUILD_SHA=${{ github.sha }}` line. **Reusable workflow caveat:** every consumer of `reusable-release.yml` will inherit this build-arg expression at YAML parse time. Verified zero blast radius during deepen: the only other consumer is `version-bump-and-release.yml` (component=`plugin`), which does NOT pass `docker_image` — and the docker-build step is gated `if: steps.version.outputs.next != '' && inputs.docker_image != ''` (`reusable-release.yml:433`). The build never runs for the plugin path, so the new build-arg is never evaluated there. Confirmed via `git grep -l "uses: ./.github/workflows/reusable-release.yml" .github/workflows/`.
- [x] `.github/workflows/web-platform-release.yml` — new step `Pre-rerun lock probe` inserted as the FIRST step of the `deploy` job, before `Deploy via webhook`. Probe behaviour:
  - GET `/hooks/deploy-status` with HMAC-empty-body signature (same pattern as `Verify deploy script completion`).
  - Tolerant of non-JSON and HTTP-error responses — treats them as "no prior state, proceed" (degraded-permissive, log-only).
  - Refuses to proceed (`exit 1` with `::error::`) ONLY when the JSON body parses cleanly AND `.exit_code == -1` AND `.start_ts` indicates the prior run is younger than 900s (matches the verify-completion ceiling). A `.exit_code == -1` reading older than 900s implies a stuck/abandoned state file (the matching downstream step already gave up) and MUST NOT block the new deploy.
  - Logs the prior `.tag` and `elapsed=$(date +%s)-$start_ts)s` so the operator sees the in-flight deploy at a glance.
- [x] `.github/workflows/web-platform-release.yml` — `Verify deploy health and version` step adds a build-sha gate after the existing version-match check:
  - Asserts `build_sha == ${{ github.sha }}`.
  - Treats a missing `.build_sha` field as an in-flight rolling deploy (loops, doesn't fail) — safe rollout for the case where the new image build lands first but a stale image is still answering the LB during the swap window.
  - Treats a present-but-mismatched `.build_sha` as an actionable error: logs `expected=$EXPECTED_SHA got=$DEPLOYED_SHA tag=$VERSION` with `::error::` and exits 1.
- [x] `apps/web-platform/test/server/health.test.ts` — new test asserts `build_sha` is `"dev"` when `BUILD_SHA` env var is unset.
- [x] `apps/web-platform/test/server/health.test.ts` — new test asserts `build_sha` echoes `process.env.BUILD_SHA` when set.
- [x] `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — `Rerun Safety` section updated to note the new pre-rerun probe gate (the operator-side runbook stops conflating "still running" with "release-path leak" because the workflow now surfaces it pre-POST).
- [x] `bun run typecheck` passes (no new TS errors from the `HealthResponse` interface change).
- [x] `bun run test apps/web-platform/test/server/health.test.ts` — full suite green including the two new test cases.
- [ ] PR body uses `Closes #3408 / Closes #3409` (both deferred chores resolve in the same PR).

### Post-merge (operator)

- [ ] Trigger `web-platform-release.yml` via the next merge to `main` (or manual `workflow_dispatch`). Verify in the run logs:
  - The new `Pre-rerun lock probe` step appears, runs in <2s, and prints either "no prior state" / "prior deploy completed" / "prior deploy v<x.y.z> still running, age=<n>s" — and the workflow proceeds in the first two cases, halts in the third.
  - The `Verify deploy health and version` step's "Deploy verified" log line includes `build_sha=<short>` and matches `${{ github.sha }}` short-form.
- [ ] Delete the temporary verification rerun (or annotate the run as "post-merge verification of #3408+#3409"). Per `wg-after-merging-a-pr-that-adds-or-modifies`, a new workflow shape requires post-merge verification.
- [ ] No prod-side change required. `ci-deploy.sh` already emits `start_ts`; the probe consumes it. No SSH, no Terraform apply.

## Files to Edit

- `apps/web-platform/server/health.ts` — add `build_sha` to `HealthResponse`, populate from `process.env.BUILD_SHA || "dev"`.
- `apps/web-platform/Dockerfile` — add `ARG BUILD_SHA=dev` + `ENV BUILD_SHA=$BUILD_SHA` next to existing `BUILD_VERSION` block.
- `.github/workflows/reusable-release.yml` — append `BUILD_SHA=${{ github.sha }}` to docker-build `build-args`.
- `.github/workflows/web-platform-release.yml` — insert `Pre-rerun lock probe` step at top of `deploy` job; extend `Verify deploy health and version` step with build-sha gate.
- `apps/web-platform/test/server/health.test.ts` — add two test cases for `build_sha`.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — update `Rerun Safety` section to mention the workflow-level pre-rerun probe.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Test scaffolding (RED)

Per `cq-write-failing-tests-before`. Land failing tests first.

1. Edit `apps/web-platform/test/server/health.test.ts`:
   - Add `it("includes build_sha as 'dev' when BUILD_SHA is unset", …)` — asserts `(await buildHealthResponse()).build_sha === "dev"` after `delete process.env.BUILD_SHA`.
   - Add `it("includes build_sha from BUILD_SHA env var when set", …)` — sets `process.env.BUILD_SHA = "abc1234deadbeef"` and asserts `.build_sha === "abc1234deadbeef"`.
2. Run `bun run test apps/web-platform/test/server/health.test.ts` — expect both new cases to fail with TypeScript errors (the field doesn't exist yet on the interface) and runtime undefineds.

### Phase 2 — Build-sha pathway (GREEN for #3409)

1. `apps/web-platform/server/health.ts`:
   - Add `build_sha: string` to `HealthResponse` immediately after `version: string;` (current line 37) and before `supabase: string;` (current line 38). Identity-field grouping: `[status, version, build_sha]` then backend-health `[supabase, sentry]` then process `[uptime, memory]`.
   - In `buildHealthResponse()`, set `build_sha: process.env.BUILD_SHA || "dev"`. The `"dev"` fallback mirrors the `BUILD_VERSION` fallback at line 95 — preserves dev-server convention where the field surfaces but doesn't claim a real SHA.
2. `apps/web-platform/Dockerfile`:
   - Add `ARG BUILD_SHA=dev` + `ENV BUILD_SHA=$BUILD_SHA` immediately below the existing `BUILD_VERSION` block (lines 56-57). Same comment block.
3. `.github/workflows/reusable-release.yml`:
   - Append `BUILD_SHA=${{ github.sha }}` to `build-args` (line 451 area). Verify the diff is one new line; do not reorder existing args.
4. Re-run `bun run test apps/web-platform/test/server/health.test.ts` — both new cases now green.
5. Run `bun run typecheck` — no new errors. The `InternalMetricsResponse` interface extends `HealthResponse` so `build_sha` is automatically picked up; no separate edit needed (verified via grep of `extends HealthResponse`).

### Phase 3 — Pre-rerun lock probe (#3408)

1. `.github/workflows/web-platform-release.yml`:
   - Insert a new step at the top of the `deploy` job's `steps:` array, **before** `Deploy via webhook`. Skeleton:

     ```yaml
     - name: Pre-rerun lock probe
       env:
         WEBHOOK_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
         CF_ACCESS_CLIENT_ID: ${{ secrets.CF_ACCESS_CLIENT_ID }}
         CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}
         # In-flight ceiling matches the verify-completion ceiling (#3398, 900s).
         # A `.exit_code == -1` older than this implies the upstream step already
         # gave up; do NOT block a new deploy on stale state.
         IN_FLIGHT_CEILING_S: 900
       run: |
         SIGNATURE=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
         HTTP_CODE=$(curl -s --max-time 10 -o /tmp/preflight-body \
           -w '%{http_code}' \
           -H "X-Signature-256: sha256=$SIGNATURE" \
           -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
           -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
           "https://deploy.soleur.ai/hooks/deploy-status" || echo "000")
         BODY=$(cat /tmp/preflight-body 2>/dev/null || echo "")
         if [ -z "$BODY" ] || ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
           echo "Pre-rerun probe: non-JSON or empty body (HTTP $HTTP_CODE) — proceeding (degraded-permissive)"
           exit 0
         fi
         PRIOR_EXIT=$(echo "$BODY" | jq -r '.exit_code // -99')
         if [ "$PRIOR_EXIT" != "-1" ]; then
           echo "Pre-rerun probe: no in-flight deploy (exit_code=$PRIOR_EXIT) — proceeding"
           exit 0
         fi
         PRIOR_TAG=$(echo "$BODY" | jq -r '.tag // "?"')
         PRIOR_START=$(echo "$BODY" | jq -r '.start_ts // 0')
         ELAPSED=$(($(date +%s) - PRIOR_START))
         if [ "$ELAPSED" -gt "$IN_FLIGHT_CEILING_S" ]; then
           echo "Pre-rerun probe: prior deploy of $PRIOR_TAG marked running but elapsed=${ELAPSED}s exceeds ${IN_FLIGHT_CEILING_S}s ceiling — proceeding (state likely stale)"
           exit 0
         fi
         echo "::error::Prior deploy of $PRIOR_TAG still running (elapsed=${ELAPSED}s). Wait for completion or cancel manually before re-running."
         exit 1
     ```

   - Notes:
     - The `degraded-permissive` branch is critical — a CF tunnel hiccup or deploy-status webhook cold-start MUST NOT block deploys. The downstream `flock -n` rejection is the load-bearing safety net; this probe is just a fast-path UX improvement.
     - The 900s ceiling is hardcoded against `STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S` from the same workflow. If those values change later, this constant must change too. **Action:** add a comment in the new probe's env block AND in the verify-completion step's `STATUS_POLL_*` env block (currently lines ~237-243 of `web-platform-release.yml`) using **direct constant references**, e.g. `# IN_FLIGHT_CEILING_S below must equal STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S in the next step.` Do NOT cite `cq-align-ci-poll-windows-with-adjacent-steps` — the deepen pass found that rule is referenced across 5+ files but never defined in `AGENTS.md` or `scripts/retired-rule-ids.txt`. Citing it here compounds the unenforceable-rule debt; cite the constant relationship directly instead.

2. Extend `Verify deploy health and version` (around line 309):
   - After the `DEPLOYED_VERSION = $VERSION` and `SUPABASE_STATUS = connected` checks succeed, add a build-sha gate inside the same success branch:

     ```bash
     DEPLOYED_SHA=$(echo "$HEALTH" | jq -r '.build_sha // empty')
     EXPECTED_SHA="${{ github.sha }}"
     if [ -z "$DEPLOYED_SHA" ] || [ "$DEPLOYED_SHA" = "dev" ]; then
       # Rolling deploy: new image landed first but stale container still answering.
       # Loop, don't fail.
       echo "Attempt $i/$HEALTH_POLL_MAX_ATTEMPTS: version $VERSION + supabase ok, but build_sha is missing/dev — possibly mid-swap, retrying"
     elif [ "$DEPLOYED_SHA" != "$EXPECTED_SHA" ]; then
       echo "::error::version=$VERSION supabase=connected but build_sha=$DEPLOYED_SHA (expected $EXPECTED_SHA) — wrong image tagged with right version"
       exit 1
     else
       echo "Deploy verified: version $VERSION running, supabase connected, build_sha=$DEPLOYED_SHA"
       echo "$HEALTH" | jq .
       exit 0
     fi
     ```

   - The "wrong image with right version" error is **fail-fast and non-retryable**: this is the bad-tag-association case the gate exists to catch. Looping wouldn't help — the prod container is what it is.

### Phase 4 — Runbook update

1. `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`:
   - In the `Rerun Safety` section (line ~74), add a paragraph noting that the `web-platform-release.yml` deploy job now pre-probes `/hooks/deploy-status` before re-POSTing. The operator-side advice ("first poll `/hooks/deploy-status` directly") still applies for **out-of-workflow** scenarios (manual triggers, cross-component deploys), but in-workflow `gh run rerun --failed` will now self-gate.
   - Cross-link to issue #3408 in the section's reference list.

### Phase 5 — Verification

1. `bun run typecheck` — green.
2. `bun run test apps/web-platform/test/server/health.test.ts` — green.
3. `bun run test apps/web-platform/test/` — full server-test directory green (catches incidental regression).
4. `actionlint .github/workflows/web-platform-release.yml` if available locally; otherwise rely on lefthook + CI lint.
5. Visual diff review on the workflow file: confirm the new step is positioned correctly (top of `deploy` job, before `Deploy via webhook`), env block uses the same secret names as the sibling step, and yaml indentation is `      - name:` (six spaces, two-step nest).

## Test Strategy

- **Unit (vitest):** Two new cases in `health.test.ts` covering env-var presence/absence. Mirrors the existing `health.test.ts:63 "includes standard health fields"` pattern (`expect(response).toHaveProperty("version")` style) and adds the env-var override case alongside. Verified live during deepen — there is no dedicated `version` test, so the new `build_sha` cases also serve as the env-var-override test pattern that future fields can mirror.
- **Workflow:** No unit-test framework for the YAML — verification is post-merge runtime (Phase 5.5 of acceptance criteria). Per the `wg-after-merging-a-pr-that-adds-or-modifies` rule, a manual `workflow_dispatch` run on `main` after merge confirms the new step shape.
- **No new dependencies.** Vitest, jq, openssl, curl all already in use.

## Risks

| Risk | Mitigation |
|---|---|
| Pre-rerun probe blocks a legit deploy because of stale `-1` state from a long-killed prior run | The 900s elapsed-ceiling check fall-through. A stuck `-1` state only blocks for the matching window the verify-completion step would tolerate anyway. |
| `${{ github.sha }}` is the SHA of the workflow checkout, not necessarily the SHA of the image's source tree | False — `reusable-release.yml:441` already tags the image with `${{ github.sha }}` AND uses it as the docker-build context's commit. The release workflow runs `actions/checkout` once at the top of `release` job, and `${{ github.sha }}` is the merge commit on `main` (the deploy job runs on the same trigger). Same SHA, same source tree. |
| `BUILD_SHA` build-arg leaks into other reusable-release.yml consumers and breaks their builds | **Verified zero blast radius** during deepen. The other consumer of `reusable-release.yml` is `version-bump-and-release.yml` (component=`plugin`) which does NOT pass `docker_image`. The `if: steps.version.outputs.next != '' && inputs.docker_image != ''` gate at the docker-build step (`reusable-release.yml:433`) skips the build entirely on the plugin path. The `BUILD_SHA` build-arg only ever fires for the web-platform path. Buildx ignores-unknown semantic is the secondary defense; the primary defense is that the docker-build step never executes for the other consumer. |
| Probe adds 2-10s to every deploy job | Acceptable — the probe runs in parallel with no other latency-sensitive steps and saves the operator 900s on every false-rerun. Net positive. |
| `.build_sha` field rolls out to existing /health consumers (LB health probe, monitoring) | The field is **additive** on a JSON response. Every existing consumer (LB, Better Stack, manual curl) ignores extra fields. No coordination required. |

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Section is filled (`threshold: none` with a one-sentence rationale anchored to "no credentials/auth/data/payments/user-owned resources" and the additive-only nature of the `build_sha` field).
- **The 900s `IN_FLIGHT_CEILING_S` constant in the new probe step duplicates `STATUS_POLL_MAX_ATTEMPTS * STATUS_POLL_INTERVAL_S` from the verify-completion step.** Phase 3 prescribes a bidirectional cross-link comment so a future ceiling change in either place surfaces the other at edit time. If a future operator changes one without the other, the probe becomes desynchronized — but the failure mode is bounded (probe blocks for slightly too long or proceeds slightly too eagerly; flock is still the load-bearing safety).
- **`${{ github.sha }}` substitution:** the deploy job currently does NOT `actions/checkout`. Adding `git rev-parse HEAD` would require checkout. Use `${{ github.sha }}` directly via env-var substitution — matches the existing `VERSION: ${{ needs.release.outputs.version }}` pattern in the same step.
- **Bun-server vs Next route file:** the issue body's path was wrong. This is a *Bun-managed custom server* — not an App Router route. Editing `apps/web-platform/app/api/health/route.ts` would create a phantom file ignored by the runtime. The reconciliation table above flags this; implementer must edit `server/health.ts`.
- **Reusable workflow blast radius:** appending `BUILD_SHA` to `reusable-release.yml`'s `build-args` makes the build-arg available to *every* component using that reusable workflow, not just web-platform. Verified other consumers' Dockerfiles ignore unknown args (Buildx native behaviour). If a future consumer Dockerfile adds `ARG BUILD_SHA` for an unrelated meaning, that's a name collision the future consumer's PR review must catch — name is generic enough that a clearer alternative would be `WEB_PLATFORM_BUILD_SHA`, but the symmetry with `BUILD_VERSION` (also generic) outweighs.

## Out of Scope

- Adding `build_sha` to the docker image label set (`LABEL org.opencontainers.image.revision=...`). Useful for `docker inspect` triage but not load-bearing for #3409. Defer if needed; track via separate issue.
- Adding `build_sha` to the LB health-check contract beyond what the workflow asserts. Other consumers (Better Stack, etc.) read `.status` only.
- Replacing the workflow's existing `Verify deploy script completion` polling with a long-poll subscription. Out of scope; orthogonal to both #3408 and #3409.
- Sentry breadcrumb / structured log when the pre-rerun probe blocks. The `::error::` annotation is sufficient operator surface for a p3 chore. If observability is desired, file a follow-up.
- Refactoring `health.ts` into a versioned schema (`HealthResponseV2`). Adding a field is monotonic; consumers ignore unknown fields.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **#3408**: Probe `/hooks/deploy-status` from inside `Deploy via webhook` instead of as a separate step | A separate step shows up cleanly in the run log, has its own duration, and skips the deploy POST when blocked rather than wrapping it in a conditional. Easier to read in CI. |
| **#3408**: Treat any non-zero `prior_exit` as "blocked" | Wrong — `exit_code=0` means the prior deploy *completed successfully* and a new deploy is fine. Only `exit_code == -1` means in-flight. |
| **#3409**: Use `git rev-parse HEAD` after adding an `actions/checkout` to the deploy job | Adds checkout I/O for every deploy job; the SHA is already in `${{ github.sha }}`. No checkout needed. |
| **#3409**: Use the docker image digest instead of git sha | Image digest is opaque to the operator; matching it requires correlating with `docker manifest inspect`. Git SHA is already what the operator sees in PRs, releases, Discord notifications. |
| **#3409**: Defer `build_sha` indefinitely as the parent issue's "re-evaluation criteria" suggests | The parent recovery PR already touched the same workflow file; folding both fixes in one PR is the lower-friction path now. The "graduate when /health is being touched for another reason" criterion is satisfied by #3408. |
| **Bundle**: Ship #3408 and #3409 in separate PRs | They overlap on `web-platform-release.yml` and both belong to the same hardening theme. Single PR keeps the runbook update (Phase 4) in lock-step with the workflow change. |

## References

- Parent recovery: PR resolving #3398 — `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`.
- Sibling rule: `cq-align-ci-poll-windows-with-adjacent-steps` (the 900s alignment between probe and verify-completion).
- Schema authority: `apps/web-platform/infra/ci-deploy.sh:54-65` `write_state` JSON contract.
- Build-arg pathway template: `apps/web-platform/Dockerfile:56-57` + `.github/workflows/reusable-release.yml:441-451`.
- Bun-server route registration: `apps/web-platform/server/index.ts:53`.
- Runbook: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` `Rerun Safety` section.
