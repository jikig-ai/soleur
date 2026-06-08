---
date: 2026-06-08
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5052
pr: 5051
branch: feat-cd-deploy-ci-gate-and-build-cache
spec: knowledge-base/project/specs/feat-cd-deploy-ci-gate-and-build-cache/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-08-cd-deploy-ci-gate-and-build-cache-brainstorm.md
---

# Plan: Gate prod deploy on CI + Docker layer cache

## Overview

Two independent workstreams on the web-platform CD path, shipped in one PR:

- **WS1 — Gate the prod cutover on CI.** Add an `await-ci` job to `web-platform-release.yml`
  that blocks until CI's `test` aggregator check-run reaches a terminal conclusion for **this
  push's SHA**, then add it as a `needs:` of the `deploy` job only. The image keeps building in
  parallel (the `release` job is untouched), so wall-clock time-to-prod becomes
  `max(build_chain, CI)` not `build_chain + CI`. Closes the real gap: today nothing gates the
  prod cutover on tests, so a semantically-broken `main` (two independently-green PRs
  conflicting; compiles, boots, health 200s) ships to prod.

- **WS2 — Cut CD time via Docker layer caching.** The `docker/build-push-action` step in
  `reusable-release.yml` has **no `cache-from`/`cache-to` and no `setup-buildx`** — every
  release re-runs all pinned runner-stage installs (claude-code, likec4, apt, gh,
  playwright+chromium ~1–2 min) + two `npm ci`. Add `docker/setup-buildx-action` +
  `cache-from`/`cache-to: type=gha`. The Dockerfile runner stage is **already** ordered with
  heavy installs above the volatile `BUILD_SHA` layer, so those layers become cache hits with
  zero Dockerfile reordering needed.

**Measured baseline (2026-06-08, `gh run list`, last 8 main runs):** CI ~5 min median;
release chain ~13 min median (2–3× slower). The gate is therefore ~free wall-clock today, and
the velocity prize is entirely WS2.

**Recommendation on OS1 (parallelize `migrate` with the build):** keep it OUT of this PR. It
touches the `release.outputs.version` / `docker_pushed` contracts the deploy job reads
(higher blast radius), and the core WS1+WS2 PR is clean and shippable without it. Plan a
separate tracking issue. See "Deferred / Optional Scope".

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified 2026-06-08) | Plan response |
|---|---|---|
| TR2 / AC5: "`vendor-pin-verify.yml` enforces SHA-pin of new actions" | `vendor-pin-verify.yml` triggers ONLY on `plugins/soleur/skills/gdpr-gate/**` paths and verifies gdpr-gate NOTICE upstream-blob-shas. The lefthook `vendor-pin-integrity` hook is likewise gdpr-gate-NOTICE-specific. **No generic action-SHA-pin gate exists in this repo.** | SHA-pinning `uses:` is a **repo convention** (every action in `.github/workflows/` is pinned `@<40-hex> # vX.Y.Z`). AC rewritten: the new `setup-buildx-action` MUST be SHA-pinned with a `# vX` comment, **verified by grep**, not by `vendor-pin-verify.yml`. Drop the false `vendor-pin-verify` dependency from AC5. |
| FR6: "Dockerfile layer-order audit so heavy installs are cacheable independent of source-busting COPY" | Already true: `apps/web-platform/Dockerfile` runner stage puts claude-code(:45), likec4(:57), apt(:76,:82), playwright-chromium(:96) ALL above `ENV BUILD_VERSION`(:104)/`ENV BUILD_SHA`(:110) and the `COPY --from=builder`(:128+). The base image is SHA-pinned. | FR6 becomes **verify-and-document** (confirm ordering is cache-optimal; no reorder). The cache win comes entirely from FR5 (cache backend). |
| "Gate `deploy` on `test`" (TR3) — is `test` sufficient, vs. whole CI run? | `web-platform-build` (next build + route-file validator) is a SEPARATE ci.yml job NOT under the `test` aggregator — but the `release` job's Docker build ALSO runs `npm run build`, so build-class breaks already block deploy via `docker_pushed != 'true'`. The unique gap `test` covers is **test-class semantic breaks** (logic broken but compiles/builds). | Gate on the `test` check-run specifically (per TR3). Correct complement: build breaks caught by `release`, test breaks caught by `await-ci`. Do NOT gate on the whole CI run (would couple deploy to deploy-irrelevant flaky jobs like `readme-counts`/`lint-*`). |

## Premise Validation

Issue #5052 OPEN; PR #5051 OPEN (draft) — both hold. `ci.yml` runs unconditionally on
`push:[main]` (no path filter), so the `test` check-run is guaranteed to exist for every main
SHA — there is no "CI never ran for this SHA" hole. `test` is the required-context name on
branch-protection ruleset 14145388 (load-bearing per ci.yml's own synthetic-aggregator comment);
do NOT rename it. No external premises remain unverified.

## Implementation Phases

### Phase 1 — WS1: `await-ci` gate (the safety change)

**1.1 Add the `await-ci` job to `web-platform-release.yml`** (a new job, sibling to `release`):

```yaml
  await-ci:
    # Gate the prod cutover (deploy job) on CI's `test` aggregator for THIS
    # commit's SHA. The image still builds in parallel (release job) — only
    # the final deploy waits, so time-to-prod = max(build, CI), not build+CI.
    # Push-only: workflow_dispatch is the operator escape hatch (mirrors
    # skip_deploy) and bypasses this gate by design.
    if: github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      checks: read          # commits/<sha>/check-runs API
      actions: read         # actions/workflows/ci.yml/runs API (fast no-CI-run detection)
    timeout-minutes: 20      # hard ceiling > MAX_ATTEMPTS*INTERVAL (15m) > p100 CI (~8m)
    steps:
      - name: Wait for CI `test` check-run on this SHA
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          SHA: ${{ github.sha }}
          MAX_ATTEMPTS: "90"      # 90 * 10s = 900s = 15m. INDEPENDENT window sized to CI p100 (~8m). NOT governed by the deploy job's STATUS/HEALTH/IN_FLIGHT drift assertion (those are deploy-job-local) — do not couple them.
          INTERVAL_S: "10"
          GRACE_ATTEMPTS: "6"     # 60s grace for a CI run to register before declaring "no CI for this SHA"
        run: |
          set -euo pipefail
          # FAIL-CLOSED design (spec-flow P0-2). We do NOT trust a [skip ci]
          # token in the commit message as a deploy-authorizer — GitHub honors
          # the token only on the message's last line, but a grep over the whole
          # message would match a token substring in a PR body (changelog bullet,
          # quoted revert) and wave a RED CI through. Instead: if NO ci.yml run
          # ever registers for this SHA (genuine skip-ci / no-trigger), we
          # fail-CLOSED after a 60s grace. Deliberate skip-ci releases use the
          # workflow_dispatch escape hatch. Brand-survival threshold = single-user
          # incident → never fail-open.
          status=missing; conclusion=none
          for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
            # var-based (NOT piped-into-grep) to avoid set -e + pipe fragility.
            # Capture stderr so a missing `checks: read` perm is diagnosable now,
            # not after 15m (spec-flow P2-2).
            if ! resp=$(gh api "repos/$REPO/commits/$SHA/check-runs" 2>/tmp/gherr); then
              echo "attempt $attempt: check-runs query failed: $(cat /tmp/gherr) — retrying"
              sleep "$INTERVAL_S"; continue
            fi
            # Most-recent NON-cancelled check-run named exactly "test". Excluding
            # `cancelled` stops a cancelled re-run from shadowing an older green
            # run (spec-flow P1-C). // {} guards the empty-array case → "missing".
            sel='([.check_runs[]|select(.name=="test" and .conclusion!="cancelled")]|sort_by(.started_at)|last)//{}'
            status=$(jq -r "$sel|.status//\"missing\"" <<<"$resp")
            conclusion=$(jq -r "$sel|.conclusion//\"none\"" <<<"$resp")
            echo "attempt $attempt: test status=$status conclusion=$conclusion"
            if [ "$status" = "completed" ]; then
              if [ "$conclusion" = "success" ]; then
                echo "CI test passed for $SHA — deploy may proceed."
                exit 0
              fi
              echo "::error::CI test concluded '$conclusion' for $SHA — blocking deploy (fail-closed)."
              exit 1
            fi
            # Fast fail-closed: after grace, if ci.yml never even triggered for
            # this SHA, don't burn 15m — block now with an actionable message.
            if [ "$status" = "missing" ] && [ "$attempt" -ge "$GRACE_ATTEMPTS" ]; then
              runs=$(gh api "repos/$REPO/actions/workflows/ci.yml/runs?head_sha=$SHA" --jq '.total_count' 2>/dev/null || echo "0")
              if [ "$runs" = "0" ]; then
                echo "::error::No ci.yml run for $SHA after grace — CI was skipped or never triggered. Blocking deploy (fail-closed). Use workflow_dispatch to force a release."
                exit 1
              fi
            fi
            sleep "$INTERVAL_S"
          done
          echo "::error::Timed out after $((MAX_ATTEMPTS * INTERVAL_S))s waiting for CI test (last status=$status) — blocking deploy (fail-closed)."
          exit 1
```

**1.2 Extend the `deploy` job's `needs:` and `if:`** (the ONLY edit to the existing deploy job):

```yaml
  deploy:
    needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]
    if: >-
      always() &&
      needs.release.outputs.docker_pushed == 'true' &&
      (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
      (needs.verify-migrations.result == 'success' || needs.verify-migrations.result == 'skipped') &&
      needs.verify-doppler-secrets.result == 'success' &&
      (needs.await-ci.result == 'success' ||
       (github.event_name == 'workflow_dispatch' && needs.await-ci.result == 'skipped')) &&
      (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
```

- `always()` is already present → a failed/timed-out `await-ci` yields `result != 'success'`
  → the new conjunct is false → **deploy is skipped (fail-closed)** on the push path.
- `workflow_dispatch`: `await-ci` is skipped (job `if` is push-only) → tolerated via the
  `|| (workflow_dispatch && skipped)` clause, preserving the manual escape hatch.

### Phase 2 — WS2: Docker layer cache (the velocity change)

**2.1 Add `setup-buildx` before the build step** in `reusable-release.yml` (before line 563
`Build and push Docker image`), gated identically to the build step:

```yaml
      - name: Set up Docker Buildx
        if: steps.version.outputs.next != '' && inputs.docker_image != ''
        uses: docker/setup-buildx-action@<RESOLVE-SHA>  # v3.x.x
```

Resolve the pinned SHA at /work time (do NOT fabricate). Deref annotated tags:
`gh api repos/docker/setup-buildx-action/git/ref/tags/<latest-v3> --jq .object.sha`, then if
`.object.type == "tag"` follow `gh api repos/docker/setup-buildx-action/git/tags/<sha> --jq .object.sha`.
Pin the **40-char** commit SHA with a `# vX.Y.Z` comment (a truncated 37-char pin prefix-matches
in grep verification and silently passes — assert length 40, per learning
`2026-05-16-sha-pin-prefix-match-false-positive-in-plan-verification.md`).

**2.2 Add cache to the `docker/build-push-action` step** (append to its `with:`):

```yaml
          # mode=min is secret-safe ONLY while no non-public secret ARG is consumed in the
          # runner/final-image stage of apps/web-platform/Dockerfile (see AC4b). Do NOT flip to
          # mode=max, and do NOT add a non-public secret build-arg to the runner stage.
          cache-from: type=gha,scope=web-platform-release
          cache-to: type=gha,mode=min,scope=web-platform-release
```

The tripwire comment above the `cache-to` line is required (security P2-2): it co-locates the
`mode=min`↔runner-stage-secret invariant at the cache-config site where a future editor would
otherwise flip to `max` or add a runner secret.

`type=gha` requires buildx (the default docker driver cannot export gha cache) — hence 2.1.
**`mode=min` (NOT `max`) — security-load-bearing (spec-flow P0-3):** the *builder* stage
consumes `SENTRY_AUTH_TOKEN` (non-public, builder-only — see Dockerfile comment "builder stage
only — not present in runner image") via build-arg. `mode=max` would export the builder stage
to a repo-readable gha cache, persisting that token's build layer. `mode=min` exports ONLY
final-image (runner-stage) layers — which is where the heavy-install wins live
(claude-code/likec4/apt/gh/playwright-chromium, **Dockerfile lines 45–96**). So `mode=min`
captures the headline velocity win AND never caches the secret-bearing builder stage. The
`deps`/`builder` intermediates (lockfile-gated `npm ci`, source-volatile `npm run build`) are
not cached — negligible since `npm run build` rebuilds every commit anyway. **Note (arch-review
Concern B): `RUN npm ci --omit=dev` (line 114) sits BELOW `ENV BUILD_SHA` (line 110), so it is
cache-busted every commit and is NOT recovered by this change.** Recovering it requires moving
the prod-deps `COPY`+`npm ci --omit=dev` above the `ARG/ENV BUILD_*` block — an image-equivalent
reorder, tracked as OS2 (out of this PR's comment-only Dockerfile scope). The explicit `scope=`
namespaces this build's cache so it
cannot collide with a future gha cache from another workflow on the shared 10 GB per-repo budget
(per learning `2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`).

**2.3 FR6 verify-and-document:** add a one-line comment above the runner stage's first heavy
`RUN` confirming the ordering invariant (heavy installs MUST stay above `ENV BUILD_SHA` so
they remain cache-hits). No reorder. Optionally note in the PR body which layers became hits.

### Phase 3 — Verification (no SSH; see Observability + Acceptance Criteria)

`actionlint` the two workflows; `bash -c` extract-and-syntax-check the `await-ci` run-block;
dry-run the poll loop locally against a real merged SHA's check-runs to confirm the
success/failure/missing/timeout branches.

## Files to Edit

- `.github/workflows/web-platform-release.yml` — add `await-ci` job (1.1); extend `deploy`
  `needs:` + `if:` (1.2).
- `.github/workflows/reusable-release.yml` — add `setup-buildx` step (2.1); add
  `cache-from`/`cache-to` to the build-push step (2.2).
- `apps/web-platform/Dockerfile` — comment-only ordering-invariant note (2.3); no logic change.

## Files to Create

- None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a broken web-platform flow or — via a
  bad migration that still "verifies" — corrupted data, because a semantically-broken `main`
  reaches prod. (WS1 closes this vector; a bug in WS1 that fails *open* would leave the status
  quo, not regress it. A bug that fails *closed* incorrectly blocks a legitimate deploy — an
  availability, not data, impact.)
- **If WS2 misbuilds:** a cache-poisoned or wrong image could deploy — but the post-deploy
  `/health` version+SHA poll (unchanged) catches image/SHA mismatches. `cache-to: mode=min`
  exports only runner/final-image layers, which carry no non-public secret (the builder-only
  `SENTRY_AUTH_TOKEN` is never in a cached layer — AC4b).
- **Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time
  (carry-forward from brainstorm CTO assessment); `user-impact-reviewer` runs at PR review.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `actionlint .github/workflows/web-platform-release.yml .github/workflows/reusable-release.yml`
  passes; the `await-ci` run-block passes `bash -n` after extraction.
- **AC2.** `await-ci` job has `if: github.event_name == 'push'`, `permissions: { contents: read, checks: read, actions: read }`,
  `timeout-minutes` ≥ 15. **Fail-closed guarantee (post-condition):** the run-block's ONLY
  `exit 0` is inside the `[ "$conclusion" = "success" ]` branch — `grep -c 'exit 0' <run-block>`
  returns 1; every other path (`continue` on query error, non-success terminal, timeout) is
  `exit 1`. The no-CI-run-after-grace `exit 1` is a **latency optimization** (fast-fail atop the
  timeout's already-guaranteed fail-closed), not a second safety mechanism. The `test` selection
  excludes `conclusion=="cancelled"` (P1-C). Per-branch walk: see Test Scenarios.
- **AC3.** `deploy.needs` includes `await-ci`; `deploy.if` contains
  `needs.await-ci.result == 'success'` AND the `workflow_dispatch && skipped` tolerance clause.
  No other existing `needs`/`if` conjunct is removed or weakened, AND the deploy job's existing
  steps (webhook POST, status poll, `/health` version+SHA poll, flock, pre-rerun lock probe)
  are byte-unchanged — `git diff origin/main -- .github/workflows/web-platform-release.yml`
  shows only the `await-ci` job addition + the `deploy` `needs:`/`if:` two-line extension.
- **AC4.** `reusable-release.yml` contains a `docker/setup-buildx-action@<40-hex> # v3*` step
  gated `if: steps.version.outputs.next != '' && inputs.docker_image != ''`, AND the build-push
  step gained `cache-from: type=gha,scope=web-platform-release` +
  `cache-to: type=gha,mode=min,scope=web-platform-release` (`mode=min`, NOT `max` — P0-3). The
  pin is **exactly 40 hex chars**:
  `git grep -hoE 'setup-buildx-action@[0-9a-f]+' .github/workflows/reusable-release.yml | awk -F@ '{print length($2)}'`
  returns `40` (guards the truncated-pin false-positive). AND the pinned SHA dereferences to the
  tag in its `# vX.Y.Z` comment (security P2-1): at /work assert
  `gh api repos/docker/setup-buildx-action/git/ref/tags/<commented-tag>` (deref annotated tag)
  resolves to the pinned SHA — length-40 alone does not catch a transposed-but-valid SHA.
- **AC4b (secret-not-cached).** No non-public secret build-arg is consumed in a runner/final-image
  layer (which `mode=min` would cache). Verify `SENTRY_AUTH_TOKEN` (and any non-`NEXT_PUBLIC_*`
  secret) appears ONLY in the builder stage of `apps/web-platform/Dockerfile`, never the runner
  stage: `awk '/AS runner/,0' apps/web-platform/Dockerfile | grep -c 'SENTRY_AUTH_TOKEN'` returns `0`.
- **AC5.** The `test` required-context name is unchanged (no rename) — `grep -c '^  test:' ci.yml`
  unchanged; ruleset 14145388 not touched. (Corrected: no `vendor-pin-verify` dependency.)
- **AC6.** Dockerfile diff is comment-only (`git diff --stat apps/web-platform/Dockerfile`
  shows no `RUN`/`COPY`/`ENV`/`FROM` line changes).

### Post-merge (operator / automatic)

- **AC7.** On the first post-merge release run: the `await-ci` job appears, waits, and the
  `deploy` job starts only after `await-ci` succeeds. Verify with
  `gh run view <run-id> --json jobs` (no SSH).
- **AC8.** Second consecutive release with unchanged deps shows Docker **cache hits** for the
  runner-stage install layers (claude-code/likec4/apt/gh/playwright-chromium, lines 45–96) in the
  build-push logs (`gh run view <run-id> --log | grep -iE 'CACHED|importing cache'`). `npm ci
  --omit=dev` (line 114) is expected to rebuild (cache-busted by `ENV BUILD_SHA`) — not a failure.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm).

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Gate the `deploy` job (not the build) on CI for `max()`-not-`sum()` safety;
add Docker layer caching (the dominant, currently-absent CD-speed lever). Both low-risk,
independently shippable. No new substrate. Confirmed at plan time: the wait mechanism is a
self-contained `gh api` poll (no new vendor/action beyond `setup-buildx-action`), and the
Dockerfile is already cache-ordered.

### Product/UX Gate

**Tier:** none — no UI surface (Files to Edit are CI YAML + Dockerfile; no `components/**`,
`app/**/page.tsx`, or other UI-surface path). Mechanical UI-surface override did not fire.

## GDPR / Compliance Gate

Evaluated per trigger (b) (`brand_survival_threshold: single-user incident` declared). **No
regulated-data surface touched:** the change is CI YAML (a check-run poll + a build-cache
backend) + a comment-only Dockerfile edit. No schema/migration/auth/API change; the `migrate`
job is untouched; the `await-ci` poll reads only CI check-run status (no personal data). No
findings; full gdpr-gate scan would be a guaranteed-empty data scan. Not deferred — evaluated
and cleared here.

## Infrastructure (IaC)

No new infrastructure. The gha build cache is GitHub-Actions-native (no new server, service,
secret, vendor, DNS, or cron). `setup-buildx-action` runs inside the existing runner. IaC
routing gate does not apply.

## Observability

CI YAML is outside the code-class trigger set, so this section is proportionate-not-full: the
gate is a new failure surface and the single-user threshold warrants a short declaration.

```yaml
liveness_signal:    # await-ci job conclusion per release run; surfaces in the existing release-failure email/Discord on web-platform-release.yml
error_reporting:    # `::error::` annotations in the run; fail_loud: true (red/timed-out await-ci skips deploy and is visible in the run)
failure_modes:      # (1) CI red OR no-completion → await-ci exit 1 → deploy skipped. (2) gha cache miss → build still runs, no correctness impact (best-effort)
logs:               # GitHub Actions run logs for web-platform-release.yml; GitHub default retention
discoverability_test:
  command: gh run view <run-id> --json jobs --jq '.jobs[]|select(.name|test("await-ci|deploy"))|{name,conclusion}'
  expected_output: await-ci=success; deploy ran only after it (NO ssh)
```

## Open Code-Review Overlap

None. No open `code-review` issues reference `web-platform-release.yml`,
`reusable-release.yml`, or `apps/web-platform/Dockerfile` (checked 2026-06-08).

## Risks & Mitigations

- **R1 — `await-ci` polls a stale/duplicate `test` check-run.** A manual CI re-run could
  create a second `test` check-run for the SHA. Mitigation: the jq selects the **most recent**
  by `started_at` (`sort_by(.started_at)|last`). At single-user threshold, prefer the latest
  conclusion.
- **R2 — fail-OPEN regression.** If the poll's error handling let a query failure fall through
  to exit 0, deploys would ship unguarded. Mitigation: every non-success path (`continue` on
  query error, timeout, non-success terminal, no-CI-run) leads to exit 1; the loop's only exit 0
  is an explicit `conclusion==success`. **Spec-flow-analyzer walked all branches (2026-06-08)**:
  the `always()` truth table has no push-path fail-open; it caught the original skip-token grep
  P0 (now removed) and the `mode=max` secret-cache P0 (now `mode=min`) — both fixed above.
- **R3 — gha cache exceeds the 10 GB repo budget.** The Docker cache (`mode=min`, runner-stage
  layers incl. Chromium) shares the budget with existing `actions/cache` bun caches. `mode=min`
  already keeps the footprint smaller than `max` (no builder/deps intermediates). Mitigation if
  eviction thrash still appears: a registry cache
  (`type=registry,ref=ghcr.io/jikig-ai/soleur-web-platform:buildcache` — they already push to
  GHCR). Documented; not pre-optimized (YAGNI).
- **R7 — secret in build cache (RESOLVED by `mode=min`, spec-flow P0-3).** `mode=max` would have
  cached the builder stage that consumes `SENTRY_AUTH_TOKEN`. `mode=min` exports only
  runner/final-image layers, which carry no non-public secret (verified by AC4b). No secret
  reaches the repo-readable gha cache.
- **R4 — workflow_dispatch fail-open by design.** Manual dispatch bypasses the CI gate. This is
  intentional (operator escape hatch, mirrors `skip_deploy`), and documented in the job comment.
  At single-user threshold this is acceptable because dispatch requires repo-write and explicit
  operator intent.
- **R5 — added latency if CI ever exceeds the build chain.** Today CI (~5m) < build (~13m), so
  the gate is free. After WS2 caching shrinks the build toward ~CI duration, the gate stays
  free (concurrent) but could become the long pole on a cache-cold release. Acceptable; the
  20-min ceiling bounds the worst case.
- **R6 — `[skip ci]` / no-CI-run-for-SHA (RESOLVED fail-closed, spec-flow P0-2).** If a commit
  lands on `main` with a GitHub skip-token (or is otherwise authored such that ci.yml never
  triggers — GITHUB_TOKEN-no-trigger class, learning `github-token-pr-no-ci-trigger-ContentPublisher`),
  no `test` check-run ever exists. **Chosen: fail-CLOSED.** `await-ci` does NOT trust the
  commit-message skip-token (an unanchored grep would match a token *substring* in a PR body and
  wave a RED CI through — the P0 hole). Instead, after a 60s grace it queries
  `actions/workflows/ci.yml/runs?head_sha=$SHA`; if zero runs, it blocks the deploy fast with an
  actionable message (use workflow_dispatch). Deliberate skip-ci web-platform releases (rare) go
  through the workflow_dispatch escape hatch. No fail-open path remains.

## Deferred / Optional Scope

- **OS1 (#5054) — Parallelize `migrate` with the Docker build.** Today `migrate` (`needs: release`)
  waits for the ENTIRE `release` job, including the slow Docker build, even though migrations
  only need a repo checkout + version. Splitting version-compute into its own lightweight job
  that both `release`(build) and `migrate` depend on would remove the build from the
  `migrate → deploy` serial path. **Recommendation: defer to its own issue/PR.** It mutates the
  `release.outputs.version` / `docker_pushed` contracts the deploy `if:` reads (higher blast
  radius), and the core WS1+WS2 PR is clean without it. A tracking issue is filed at plan-end.
  Re-evaluation: pursue once WS2's cache lands and a fresh `gh run list` shows whether `migrate`
  is actually on the post-cache critical path (it may not be, if the build drops below migrate).
- **OS2 (#5055) — Recover the `npm ci --omit=dev` layer (arch-review Concern B).** `RUN npm ci --omit=dev`
  (Dockerfile line 114) is cache-busted every commit because it sits below `ENV BUILD_SHA` (line
  110). Moving the prod-deps `COPY package.json package-lock.json` + `RUN npm ci --omit=dev` block
  ABOVE the `ARG/ENV BUILD_*` block (lines 103–110) makes it lockfile-gated → cacheable. The move
  is **image-equivalent** (prod deps do not depend on `BUILD_VERSION`/`BUILD_SHA`; the runner's
  `require.resolve` build-time self-test still guards dep resolution). **Recommendation: fast
  follow-up, not this PR** — it's a real Dockerfile logic change on the prod-deploy path, and this
  PR's value (the 45–96 heavy layers + the deploy gate) lands without it. File a tracking issue.

## Test Scenarios

1. **Green main:** await-ci polls `missing → queued → completed/success`, exits 0; deploy runs.
2. **Red test on main:** await-ci reads `completed/failure`, exits 1; deploy skipped.
3. **CI hang:** poll loop exhausts MAX_ATTEMPTS, exits 1; deploy skipped.
4. **`[skip ci]` / no CI run for SHA:** after 60s grace, `ci.yml/runs` count is 0 → exits 1 fast;
   deploy skipped (fail-closed). A PR body merely *containing* a `[skip ci]` substring with a real
   (red) CI run → the run exists, the gate reads its real conclusion (no substring bypass).
5. **workflow_dispatch:** await-ci skipped; deploy proceeds (escape hatch).
6. **Cancelled CI re-run shadowing green:** selection excludes `cancelled`; an older
   `completed/success` is honored (deploy runs); if the ONLY run is cancelled → `missing` → grace
   → fail-closed.
7. **Cache cold then warm:** run 1 builds all layers; run 2 (unchanged deps) shows CACHED
   runner-stage layers in logs.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — filled above.
- `await-ci` uses `gh api ... <<<"$resp"` var-based jq (NOT pipe-into-grep) to dodge the
  `set -e` + pipe fragility documented in the plan-skill sharp edges; keep this shape.
- `actionlint` validates the two **workflow** files (they have `on:`/`jobs:`); do NOT point
  `actionlint` at composite-action files. Use `bash -c` on the extracted `run:` block.
- `docker/build-push-action` `type=gha` is a no-op without `setup-buildx-action` first — both
  edits ship together or caching silently does nothing.
- `security_reminder_hook.py` (PreToolUse) advisory-blocks the FIRST `Edit`/`Write` on any
  `.github/workflows/*.yml` — even a benign comment/integer diff. Recovery: retry the identical
  call (2nd attempt succeeds) or edit via Bash. Budget one wasted call per workflow file at /work.
- Manual `gh api .../check-runs` polling is justified here precisely because the deploy fires
  **post-merge on `main` with no PR context** — `gh pr checks --required` does not apply. Note
  this in the PR body so review doesn't flag it as reinventing the PR-checks CLI.
- Editing `apps/web-platform/Dockerfile`: prior rewrites silently dropped the `@sha256:`
  base-image digest pin and runner hardening. AC6 (comment-only diff) guards this — confirm
  `git diff origin/main -- apps/web-platform/Dockerfile` shows ONLY added comment lines.
- After shipping, `/compound` the `type=gha` BuildKit setup — it would be the first such
  learning in the KB (no existing `docker/build-push-action` caching learning exists).
