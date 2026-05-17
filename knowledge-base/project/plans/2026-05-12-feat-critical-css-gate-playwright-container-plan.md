---
plan_type: feat
classification: infrastructure
lane: single-domain
branch: feat-one-shot-critical-css-gate-playwright-container
requires_cpo_signoff: false
created: 2026-05-12
target_user_brand_impact_threshold: none
---

# feat: Run `critical-css-gate` inside the official Playwright container image

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview, Implementation Phases (Phase 2 + 3), Risks, Sharp Edges, Acceptance Criteria, Test Strategy.
**Research sources:** Microsoft Playwright Dockerfile (`Dockerfile.jammy`), playwright.dev/docs/ci, GitHub Actions docs (`jobs.<job_id>.container`), `actions/checkout` issue tracker (#956 — root user / UID mismatch), `actions/deploy-pages` + `actions/upload-pages-artifact` container-job compat, real-world Playwright-container benchmark (karmacomputing.co.uk), 2026-05-12 in-repo learning on cache-key invariance, 2026-03-20 in-repo learning on Playwright shared-cache version coupling, AGENTS.docs.md `cq-eleventy-critical-css-screenshot-gate` rule body, ruleset 14145388 live query, **direct container exec** verifying Node version + `/bin/sh` shell + `/ms-playwright/` layout + end-to-end gate wall-clock.

### Key Improvements

1. **Empirically verified end-to-end**: ran `npm ci + Eleventy build + npm install playwright@1.60.0 + http-server + screenshot-gate.mjs` inside `mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e152…cdc` locally — exit 0, **20 seconds wall-clock for 20 routes**.
2. **Corrected Node version claim** — image ships Node **24** (not 20 as initially assumed); verified via `docker run … node --version`. Plan body updated.
3. **Added `defaults.run.shell: bash`** to both container jobs — GitHub Actions container `run:` steps default to `/bin/sh` (which on Jammy is `dash`); current step bodies rely on bash-compatible idioms (`$(seq …)`, `kill … 2>/dev/null || true`). Explicit bash avoids dash-vs-bash drift.
4. **Documented the root-user constraint** — `actions/checkout` issue #956 confirms the Playwright image's default root user is the supported `actions/checkout` path; do NOT add `--user 1001` (would break `/__w/_temp` UID mapping).
5. **Added benchmark anchor** — karmacomputing.co.uk Playwright-container study documents `1m 2s` total / `47s` work for a comparable container-based job, calibrating the < 90s target against community data.
6. **Sensitive-path scope-out** — `.github/workflows/deploy-docs.yml` matches the canonical sensitive-path regex on `deploy`; added a `threshold: none, reason: …` scope-out bullet per `hr-weigh-every-decision-against-target-user-impact` + preflight Check 6 enforcement.

### New Considerations Discovered

- **Container pull cost is the dominant variable on GHA**. Image is ~3 GB compressed; GHA's `mcr.microsoft.com` pull on Microsoft-hosted runners typically takes 20–40 s. After pull, the actual work is < 30 s. Total wall-clock comfortably under the 90s target.
- **`actions/deploy-pages` + `actions/upload-pages-artifact` are documented to work inside container jobs** (real-world example: `davorg/perl-perlanet:latest` container deploying Pages successfully). The Pages OIDC token is env-injected by the runner, not filesystem-dependent — survives the container boundary.
- **The Playwright Docker image's Node version drifts with image age**: `Dockerfile.jammy` autogenerates `NODE_VERSION` from upstream Node releases. Pinning the image digest is what guarantees Node version stability across CI runs.

## Overview

The `critical-css-gate` job in `.github/workflows/ci.yml` currently takes 4–5 minutes wall-clock with high variance (19 s best case on `main` run `25725330777`, 4:01 on PR run `25726234757`). The dominant cost is the "Install Playwright + http-server" step which runs `npm install --no-save playwright@1 http-server@14` followed by `npx playwright install-deps chromium` (apt-installing libnss, libgtk, libgbm, etc.) on every run regardless of cache state.

The `actions/cache` for `~/.cache/ms-playwright` was added in #3624 to amortize that cost, but it is over-engineered for two reasons:

1. **The cache key (`hashFiles('package-lock.json')`) is invariant to the Playwright version.** Root `package-lock.json` contains zero `playwright` entries (verified via `grep -c 'playwright' package-lock.json` → `0`); the install is `--no-save`. The key never advances on a Playwright bump, so cache-hit runs reuse stale binaries until someone edits an unrelated lockfile entry. This recreates the exact bug the 2026-05-12 cache-key learning describes (`knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`) — that PR only moved the bug, not fixed it.
2. **Even on cache hit, `npx playwright install-deps chromium` runs unconditionally** (`ci.yml:289-292`), apt-installing OS deps. This is the dominant variable cost — apt latency on `ubuntu-latest` swings from 30 s to 3+ min depending on the GitHub-hosted mirror.

Replacing the bare runner with `mcr.microsoft.com/playwright:v1.60.0-jammy` (the official Playwright container) collapses the install dance to a single `npm install --no-save playwright@1.60.0 http-server@14`: Chromium binary (`/ms-playwright/chromium-1223/`), all OS deps (libnss/libgtk/libgbm/libasound2/etc.), and Node 24 are pre-installed in the image at the matching Playwright version. Expected runtime: ~60–80 s including container pull, with zero variance from apt latency. **Empirically verified at plan time**: end-to-end gate (npm ci + Eleventy build + npm install playwright + http-server + 20-route screenshot-gate.mjs) runs in 20 seconds locally inside `mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`. The `actions/cache` step disappears entirely — container layers are cached by the GHA runner's Docker layer cache automatically, and one real-world Playwright-container benchmark documents a total wall-clock of `1m 2s` with `47s` of actual work ([karmacomputing.co.uk](https://blog.karmacomputing.co.uk/make-playwright-faster-with-containers-and-build-caching-github-actions/)).

Parity edit applies to `.github/workflows/deploy-docs.yml`'s post-merge variant of the same gate, per `cq-eleventy-critical-css-screenshot-gate` (both pre-merge and post-merge variants must stay in sync).

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact. `critical-css-gate` is a CI gate that runs against the GitHub Actions runner, not against production traffic. A broken gate either (a) fails red — blocks the PR, operator notices immediately; or (b) silently passes false-green — same risk class as today's invariant-cache bug. The post-merge `deploy-docs.yml` gate is the load-bearing safeguard for FOUC reaching `https://www.soleur.ai`.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No user data touches this gate. The container image is pulled from `mcr.microsoft.com` (Microsoft Container Registry), pinned by SHA digest — supply-chain risk is bounded by Microsoft's signing and the operator-verified digest.

**Brand-survival threshold:** `none`. Reason: CI-only infrastructure change; no production code path, no production state mutation, no user data. The 20-route screenshot gate continues to assert the same FOUC contract.

- `threshold: none, reason: .github/workflows/deploy-docs.yml matches the sensitive-path regex on the substring "deploy", but this PR's edit to that workflow is CI-tooling only — wraps existing steps in a Playwright container and pins the image digest. No new secrets are read, no production environment variables are referenced, no auth flow is changed, no Doppler/Cloudflare/Stripe surface is touched. The Pages-deploy actions (configure/upload/deploy-pages) and their permissions block are byte-identical to current main. Risk surface is bounded to "Pages-deploy actions behave differently inside a container" — covered by the Risks section item 1 with a 1-line revert plan.`

## Research Reconciliation — Spec vs. Codebase

The feature description contains one factual claim that needs reconciliation:

| Spec claim | Reality | Plan response |
|---|---|---|
| "Resolve the exact Playwright npm version from `package-lock.json`" | Root `package-lock.json` contains **zero** `playwright` entries (verified: `grep -c 'playwright' package-lock.json` → 0). The install is `npm install --no-save playwright@1`, which resolves the floating major at runtime. Today (2026-05-12) `playwright@1` resolves to `1.60.0` (`npm view playwright@1 version`). The web-platform-internal `apps/web-platform/package-lock.json` pins `1.58.2`, but that lockfile is unrelated to the gate (the gate runs from repo root, `npm install --no-save` against root). | Pin to `playwright@1.60.0` (the currently-resolved version) explicitly in both the npm install AND the container image tag. Drop the floating `playwright@1` in favor of the pinned `playwright@1.60.0` to keep the npm package and the container binary on the exact same Playwright revision — required by Playwright's exact-revision matching (see `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`). Future bumps become a deliberate 3-edit change (image tag + image digest + npm version) in both workflows, not a silent drift. |
| "Use the digest (`@sha256:...`) form per `hr-mcp-tools-playwright-etc-resolve-paths`" | `docker buildx imagetools inspect mcr.microsoft.com/playwright:v1.60.0-jammy` returns top-level multi-arch manifest-list digest `sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` (covers both amd64 and arm64). GitHub Actions `container:` keys accept the `image@sha256:...` form for any registry that supports manifest pulls; `mcr.microsoft.com` does. | Pin the image to `mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`. Keep the human-readable tag alongside the digest so the version is greppable. |
| "Ruleset 14145388 — gate not in required set" | Verified: `gh api 'repos/{owner}/{repo}/rulesets/14145388' --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`. `critical-css-gate` is NOT in the required set. | No ruleset edit needed. AC verifies this again at plan-time and lifecycle-time (the ruleset can drift between plan-write and merge). |

## Files to Edit

- `.github/workflows/ci.yml` — `critical-css-gate` job: add `container:`, drop `Setup Node.js` step (Playwright image ships Node 24), drop `Cache Playwright browsers` step, replace dual install steps with single `npm install --no-save playwright@1.60.0 http-server@14`. Keep `actions/checkout`, `npm ci`, `npx @11ty/eleventy`, the CSP/SEO validators, the critical-CSS coverage check, and the screenshot-gate + stylesheet-swap step intact.
- `.github/workflows/deploy-docs.yml` — same container migration on the post-merge gate's screenshot-gate path (steps "Install Playwright (Chromium only) for screenshot gate" and below). The `deploy` job runs the full Eleventy build + SEO/CSP validators on the runner; the screenshot-gate step is what needs the container.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Resolve and pin the Playwright container digest

The version-and-digest tuple is the load-bearing artifact for this PR. Capture both as a single atomic edit so future readers can grep the version and verify the digest against the registry.

1. Run `docker buildx imagetools inspect mcr.microsoft.com/playwright:v1.60.0-jammy` (already done at plan-time: top-level digest `sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`).
2. Verify the same registry path resolves `npm view playwright@1.60.0 version` → `1.60.0` (already done at plan-time).
3. The chosen pin: `mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`.

### Phase 2 — Migrate `critical-css-gate` in `ci.yml`

Edit `.github/workflows/ci.yml`. Current job spans roughly lines 240–326. New shape:

```yaml
  # Pre-merge variant of the deploy-docs critical-CSS gate. Catches FOUC-class
  # regressions before merge, not after — see AGENTS.md cq-eleventy-critical-css-screenshot-gate.
  # Scoped to docs-touching PRs via detect-changes (see #3624).
  # Runs inside the official Playwright container so Chromium + OS deps are
  # pre-installed at the matching Playwright version — keep in sync with
  # deploy-docs.yml's screenshot-gate steps.
  critical-css-gate:
    needs: detect-changes
    if: needs.detect-changes.outputs.docs == 'true'
    runs-on: ubuntu-latest
    container:
      # Pinned by both tag (greppable version) AND digest (vendor-pin discipline,
      # per AGENTS.md hr-mcp-tools-playwright-etc-resolve-paths). Multi-arch
      # manifest-list digest. The Playwright image runs as root by default —
      # that is the supported path for actions/checkout (see
      # https://github.com/actions/checkout/issues/956). Do not add `--user 1001`
      # — it triggers UID-mismatch permission errors against /__w/_temp.
      image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc
    defaults:
      run:
        # GitHub Actions container `run:` steps default to `/bin/sh` (dash on
        # Jammy), not bash. Explicit bash avoids dash-vs-bash drift on any
        # future step that uses `[[ ]]`, arrays, `read -r`, etc. Bash 5.1 is
        # present at /usr/bin/bash in the image (verified empirically).
        shell: bash
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Install root dependencies
        run: npm ci

      - name: Build docs
        env:
          GITHUB_TOKEN: ${{ github.token }}
        run: npx @11ty/eleventy

      - name: Validate CSP (hashes + inline event-handler attributes)
        run: bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site

      - name: Validate SEO
        run: bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site

      - name: Static critical-CSS coverage check
        run: node plugins/soleur/docs/scripts/check-critical-css-coverage.mjs

      - name: Install Playwright + http-server
        # Container provides the Chromium *binary* + OS deps; the npm package
        # (used by `import { chromium } from "playwright"` in screenshot-gate.mjs)
        # must match the container's Playwright version EXACTLY — Playwright
        # browser-binary lookup is exact-revision (see learning
        # 2026-03-20-playwright-shared-cache-version-coupling.md).
        # Keep in sync with the container image tag above and with
        # deploy-docs.yml's matching step.
        run: npm install --no-save playwright@1.60.0 http-server@14

      - name: Screenshot + stylesheet-swap gates
        run: |
          npx http-server _site -p 8888 -a 127.0.0.1 -c-1 -s &
          SERVER_PID=$!
          UP=0
          for i in $(seq 1 30); do
            if curl -sf -o /dev/null http://127.0.0.1:8888/; then UP=1; break; fi
            sleep 0.5
          done
          if [ "$UP" -ne 1 ]; then
            echo "gates: http-server failed to come up within 15s" >&2
            kill $SERVER_PID 2>/dev/null || true
            exit 2
          fi
          set +e
          node plugins/soleur/docs/scripts/screenshot-gate.mjs
          GATE_EXIT=$?
          if [ "$GATE_EXIT" -eq 0 ]; then
            node plugins/soleur/docs/scripts/check-stylesheet-swap.mjs
            GATE_EXIT=$?
          fi
          set -e
          kill $SERVER_PID 2>/dev/null || true
          exit $GATE_EXIT

      - name: Upload screenshot-gate failure artifacts
        if: failure()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: screenshot-gate-failures-pr
          path: screenshot-gate-failures/
          if-no-files-found: ignore
          retention-days: 14
```

Deletions vs. current:

- `Setup Node.js` step — drop. The Playwright `:v1.60.0-jammy` image bundles **Node 24** (verified empirically: `docker run mcr.microsoft.com/playwright:v1.60.0-jammy node --version` → `v24.15.0`). The gate previously requested Node 20 via `actions/setup-node`; Node 24 is forward-compatible with everything the gate runs (`@11ty/eleventy@^3.1.5`, `screenshot-gate.mjs`'s standard ES-module + `node:fs`/`node:path` imports, `playwright@1.60.0`). Setting `actions/setup-node` inside a container that already has Node either no-ops or wastes ~5 s replacing the runtime; cleaner to drop. **If future maintainers need to pin a specific Node version, they should bump the Playwright image tag** (newer Playwright images bundle newer Node) rather than re-adding `actions/setup-node` — adding `actions/setup-node` inside a container is harmless but obscures the canonical version source.
- `Cache Playwright browsers` (`actions/cache@5a3ec84...`) — drop. The container image already ships the binary; layer-caching is the GHA runner's responsibility. Per spec ARGUMENT: "Don't add backwards-compat shims — delete the cache step + the dual-install steps, don't leave them as fallbacks."
- `Install Playwright + http-server (cache miss)` step — drop.
- `Install Playwright + http-server (cache hit)` step — drop. Replaced by single `npm install --no-save playwright@1.60.0 http-server@14`.

### Phase 3 — Mirror the migration in `deploy-docs.yml`

Edit `.github/workflows/deploy-docs.yml`. The `deploy` job is more complex than `critical-css-gate` — it also runs the apex-host gate, verifies build output, configures GitHub Pages, uploads the artifact, and deploys. We cannot move the entire job into the Playwright container without inheriting unrelated risk (Pages-deploy actions interact with the runner filesystem and runner-level metadata in ways that may not survive the container boundary cleanly).

**Two options analyzed:**

| Option | Description | Trade-off |
|---|---|---|
| A. Container-wrap entire `deploy` job | Add `container:` to the `deploy` job key | Simplest diff; co-locates everything in container. Risk: `actions/upload-pages-artifact`, `actions/configure-pages`, `actions/deploy-pages` may have container-incompatible behaviors (uid mapping, `_site` path, GitHub Pages OIDC token handling). Untested in this repo. |
| B. Split `deploy` into two jobs: a `gate` job (container) + a `pages-deploy` job that `needs: gate` and uses the runner directly | Mirrors `ci.yml`'s shape; isolates Playwright concern from Pages concern; gives the gate the speed-up while keeping Pages deploy untouched | More edits; introduces a second job and an artifact handoff (build `_site` once in gate, upload + re-download in deploy). |
| C. Keep `deploy` on the bare runner; replace the two Playwright-install + screenshot-gate steps in-place with container-equivalent shape | Smallest possible diff to `deploy-docs.yml`. The screenshot-gate step would still run on the bare runner with the old install dance | **Rejected**: violates `cq-eleventy-critical-css-screenshot-gate` parity — both gates must stay in sync. Defeats the perf goal for post-merge runs. |

**Chosen: Option A** with a verification step. The `actions/{configure,upload,deploy}-pages` actions are documented to work inside containers (`mcr.microsoft.com/playwright` runs as root, which is what these actions expect on a Pages runner; GITHUB_TOKEN + OIDC are env-injected by the runner, not filesystem-dependent). The `_site` directory is built and consumed inside the same job, so no uid/gid handoff is needed. Risk-mitigation: a single verification run after merge (post-merge gate is the load-bearing path) confirms the deployment completes successfully end-to-end.

Edit shape — add `container:` to the `deploy` job, remove the `Setup Node.js` step (same rationale), and collapse the `Install Playwright (Chromium only) for screenshot gate` step to `npm install --no-save playwright@1.60.0 http-server@14`. Keep every other step (apex-host gate, verify build output, configure pages, upload artifact, deploy) byte-identical.

```yaml
  deploy:
    if: github.event.workflow_run.conclusion == 'success' || github.event_name != 'workflow_run'
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    container:
      # Keep in sync with .github/workflows/ci.yml's critical-css-gate
      # container pin — both gates assert the same FOUC contract via the
      # same screenshot-gate.mjs script. See AGENTS.md
      # cq-eleventy-critical-css-screenshot-gate.
      image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc
    defaults:
      run:
        # GitHub Actions container `run:` steps default to /bin/sh (dash);
        # explicit bash matches deploy-docs.yml's existing step shapes
        # (`|| true`, `2>/dev/null`, `if [ "$UP" -ne 1 ]`).
        shell: bash
    steps:
      - name: Checkout
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Install dependencies
        run: npm ci

      - name: Build docs
        # … (unchanged)
      # … apex-host gate, CSP, verify build output, critical-CSS coverage unchanged …

      - name: Install Playwright (Chromium only) for screenshot gate
        # Keep in sync with ci.yml's "Install Playwright + http-server" step
        # and the container image pin above. See learning
        # 2026-03-20-playwright-shared-cache-version-coupling.md for why
        # the npm version must match the container tag exactly.
        run: npm install --no-save playwright@1.60.0 http-server@14

      # Screenshot gate, artifact upload, configure-pages, upload-pages-artifact, deploy-pages: unchanged.
```

### Phase 4 — Verify locally (best-effort)

- Run `docker pull mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` to confirm the digest is pullable.
- Run `docker run --rm --workdir /work -v "$(pwd):/work" mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc bash -c 'node --version && which chromium-headless-shell || ls /ms-playwright'` to confirm Node 24 and the Chromium binary are present at expected paths.
- Run the full gate locally: `docker run --rm --workdir /work -v "$(pwd):/work" --network host mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc bash -c 'npm ci && npx @11ty/eleventy && npm install --no-save playwright@1.60.0 http-server@14 && (npx http-server _site -p 8888 -a 127.0.0.1 -c-1 -s &) && sleep 2 && node plugins/soleur/docs/scripts/screenshot-gate.mjs'`. Confirm exit 0 and `< 60 s` wall-clock.

### Phase 5 — PR + observe

- Open the PR. Confirm `critical-css-gate` runs (PR touches `.github/workflows/ci.yml` which matches the docs path filter).
- Wall-clock the job. Target: `< 90 s`.
- After merge, observe the next `deploy-docs.yml` run on `main`. Confirm the screenshot-gate step still asserts the 20 routes and exits 0; confirm Pages deploy completes.

## Hypotheses

None — no SSH / network-outage / handshake-failure pattern in the feature description.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/ci.yml` — `critical-css-gate` job has `container.image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`.
- [ ] `.github/workflows/ci.yml` — `Cache Playwright browsers` step (the `actions/cache@5a3ec84...` block keyed on `~/.cache/ms-playwright`) is deleted (no fallback, no commented-out remnant).
- [ ] `.github/workflows/ci.yml` — `Install Playwright + http-server (cache miss)` and `Install Playwright + http-server (cache hit)` steps are deleted, replaced by a single `Install Playwright + http-server` step running `npm install --no-save playwright@1.60.0 http-server@14`.
- [ ] `.github/workflows/ci.yml` — `Setup Node.js` step inside `critical-css-gate` is deleted (container ships Node 24 — verified empirically). Other jobs in the workflow keep their `Setup Node.js` steps untouched.
- [ ] `.github/workflows/ci.yml` — `critical-css-gate` job has `defaults.run.shell: bash` to override GitHub Actions' container-default `/bin/sh` (which is `dash` on Jammy).
- [ ] `.github/workflows/ci.yml` — `critical-css-gate` `container:` block does NOT set `options: --user 1001` (or any non-root user). The Playwright image runs as root by default — that is the supported `actions/checkout` path. Verify: `grep -A3 'container:' .github/workflows/ci.yml | grep -v '^\s*image:' | grep -c -- '--user'` returns 0.
- [ ] `.github/workflows/ci.yml` — `needs: detect-changes` + `if: needs.detect-changes.outputs.docs == 'true'` on `critical-css-gate` are unchanged from current main (#3624 gating intact).
- [ ] `.github/workflows/deploy-docs.yml` — `deploy` job has `container.image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`.
- [ ] `.github/workflows/deploy-docs.yml` — `Setup Node.js` step is deleted; `Install Playwright (Chromium only) for screenshot gate` step is rewritten to `npm install --no-save playwright@1.60.0 http-server@14` (no `npx playwright install --with-deps chromium`).
- [ ] `.github/workflows/deploy-docs.yml` — `deploy` job has `defaults.run.shell: bash`.
- [ ] `.github/workflows/deploy-docs.yml` — `deploy` job `container:` block does NOT set `options: --user 1001`.
- [ ] Container image tag and digest match BYTE-FOR-BYTE between `ci.yml` and `deploy-docs.yml`. Verify with `git diff main -- .github/workflows/ci.yml .github/workflows/deploy-docs.yml | grep -c 'sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc'` → returns ≥ 2 added lines (one per workflow).
- [ ] Playwright npm version (`playwright@1.60.0`) matches the container's Playwright tag (`v1.60.0-jammy`) byte-for-byte. Verify with `git diff main -- .github/workflows/ci.yml .github/workflows/deploy-docs.yml | grep -cE 'playwright@1\.60\.0|v1\.60\.0-jammy'` → returns ≥ 4 (image + npm install in each of the two workflows).
- [ ] No grep hit for stale references to `~/.cache/ms-playwright`, `playwright-cache`, or `install-deps chromium` in `.github/workflows/ci.yml` or `.github/workflows/deploy-docs.yml`. Verify: `git grep -E 'ms-playwright|playwright-cache|install-deps chromium' .github/workflows/{ci,deploy-docs}.yml` returns nothing.
- [ ] Container digest is pullable from `mcr.microsoft.com`. Verify: `docker manifest inspect mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc` exits 0.
- [ ] CI run on the PR shows `critical-css-gate` wall-clock `< 90 s` (target ~60 s). Record the actual time in the PR body.
- [ ] CI run on the PR shows `critical-css-gate` exits green; the screenshot-gate step output lists the 20 routes from `plugins/soleur/docs/scripts/screenshot-gate-routes.json`, all asserted, no failures.
- [ ] Static checks pass: `Validate CSP`, `Validate SEO`, `Static critical-CSS coverage check`, `npx @11ty/eleventy` build all green inside the container.
- [ ] Required-status-checks ruleset 14145388 unchanged. Verify at PR-write time: `gh api 'repos/{owner}/{repo}/rulesets/14145388' --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns exactly `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate` (no `critical-css-gate`).
- [ ] PR body uses `Ref` (not `Closes`) for the linked learning, since the learning is not an issue.

### Post-merge (operator)

- [ ] Next `deploy-docs.yml` run on `main` succeeds end-to-end (workflow conclusion `success`, GitHub Pages deployment publishes).
- [ ] Screenshot-gate step in `deploy-docs.yml` exits 0 against the post-build `_site`.
- [ ] Wall-clock of `deploy-docs.yml`'s `deploy` job is within ±15 % of current baseline OR faster. Record in the post-merge verification commit message.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` was queried at plan time; no open code-review issue body references `.github/workflows/ci.yml`, `.github/workflows/deploy-docs.yml`, or `screenshot-gate`. None.

## Domain Review

**Domains relevant:** engineering (CI/infrastructure)

No cross-domain implications detected — CI-tooling change, no user-facing artifact, no copy, no data model, no auth surface. Product/UX Gate: NONE (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files touched).

## GDPR / Compliance Gate

Not applicable. Per `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex (schemas, migrations, auth flows, API routes, `.sql` files): no surface match. Per the four expansion triggers: (a) no new LLM/external-API processing of operator-session data, (b) brand-survival threshold is `none` not `single-user incident`, (c) no new cron/workflow READS from learnings or specs, (d) no new artifact distribution surface (this PR adds no plugin update, no public PR-body change, no package release).

## Research Insights

### Best Practices (Playwright + GitHub Actions container jobs)

- **Pin by digest, not just tag.** `mcr.microsoft.com/playwright:v1.60.0-jammy` is mutable on Microsoft's side; the SHA-256 digest of the multi-arch manifest list (`sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc`) is immutable. Per `hr-mcp-tools-playwright-etc-resolve-paths`, vendor-pin discipline requires both: tag for grep, digest for immutability.
- **Match npm package and container Playwright versions byte-for-byte.** Playwright's browser-binary lookup is exact-revision (see in-repo learning `2026-03-20-playwright-shared-cache-version-coupling.md`). The container provides the binary at `/ms-playwright/chromium-1223/`; `npm install playwright@<X.Y.Z>` provides the JS API. Version mismatch → "Executable doesn't exist at /ms-playwright/chromium-NNNN" at gate runtime.
- **No `--user 1001`.** Per `actions/checkout` issue #956, running container jobs as non-root triggers UID-mismatch permission errors against `/__w/_temp` (runner-owned dir mounted into container). Microsoft's Playwright image runs as root by default; that is the supported `actions/checkout` path on GitHub-hosted runners.
- **Explicit `shell: bash`.** GitHub Actions container `run:` steps default to `/bin/sh`. On Jammy, `/bin/sh` is `dash` (verified: `readlink /bin/sh` → `dash`). Current gate steps are POSIX-safe but future maintainers might add `[[ ]]` or array idioms. `defaults.run.shell: bash` at the job level pins all `run:` blocks to GNU bash 5.1.16 (verified present at `/usr/bin/bash`).
- **Skip image caching via `actions/cache`.** Real-world benchmarks ([karmacomputing.co.uk](https://blog.karmacomputing.co.uk/make-playwright-faster-with-containers-and-build-caching-github-actions/)) show direct `mcr.microsoft.com` pulls outperform `actions/cache` restore on GHA-hosted runners — the cache restore overhead (~17 s) exceeds network-pull savings. GitHub-Microsoft network path is fast.

### Performance Considerations

- **Empirically verified at plan time**: 20 s wall-clock for the full gate inside the container locally (npm ci + Eleventy build of 84 files + npm install playwright + http-server + 20-route screenshot gate).
- **Real-world Playwright container benchmark**: `1m 2s` total, `47s` excluding setup/teardown ([karmacomputing.co.uk](https://blog.karmacomputing.co.uk/make-playwright-faster-with-containers-and-build-caching-github-actions/)).
- **Expected GHA wall-clock breakdown**: container pull 20–40 s + npm ci 5 s + Eleventy build 3 s + CSP/SEO/critical-CSS static checks 1 s + npm install playwright + http-server 5 s + screenshot gate 7–10 s ≈ **45–65 s total**. Comfortably under the 90 s target.

### Edge Cases (verified or considered)

- **Container pull on first PR**: ephemeral GHA runners pull the image every run. The image is ~3 GB compressed but Microsoft↔Microsoft network is fast (~20–40 s observed).
- **Pages-deploy OIDC token in container**: `actions/deploy-pages` reads `id-token: write` via env (ACTIONS_ID_TOKEN_REQUEST_URL/TOKEN), not the filesystem — survives the container boundary. Real-world example: `davorg/perl-perlanet:latest` container deploying Pages successfully ([dev.to ref](https://github.com/marketplace/actions/deploy-github-pages-site)).
- **`actions/checkout` v4.3.1 inside container**: requires runner v2.329.0+ for authenticated git from a Docker container action; GitHub-hosted runners are well past this.
- **dash-vs-bash drift**: existing `Screenshot + stylesheet-swap gates` step bodies use `$(seq 1 30)`, `kill … 2>/dev/null || true`, `set +e`/`set -e` — all POSIX-compatible. `defaults.run.shell: bash` is belt-and-suspenders insurance against future steps.

### References

- [playwright.dev/docs/ci](https://playwright.dev/docs/ci) — canonical workflow example using `container.image`.
- [playwright.dev/docs/docker](https://playwright.dev/docs/docker) — image-tag matrix (jammy, noble) and version-pin guidance.
- [`microsoft/playwright/utils/docker/Dockerfile.jammy`](https://github.com/microsoft/playwright/blob/main/utils/docker/Dockerfile.jammy) — image source; `NODE_VERSION` is autogenerated from upstream Node releases (currently 24).
- [`actions/checkout` #956](https://github.com/actions/checkout/issues/956) — UID-mismatch context; root is the supported `container.image` path.
- [GitHub Docs — running jobs in a container](https://docs.github.com/en/actions/using-jobs/running-jobs-in-a-container) — official caveats (Linux-only, shell default = sh).
- [karmacomputing.co.uk Playwright-container benchmark](https://blog.karmacomputing.co.uk/make-playwright-faster-with-containers-and-build-caching-github-actions/) — `1m 2s` total / `47s` work.
- In-repo: `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`.
- In-repo: `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`.

## Risks

1. **`actions/{configure,upload,deploy}-pages` behavior inside a Playwright container is untested in this repo, but is documented to work upstream.** Real-world example: `davorg/perl-perlanet:latest` container successfully deploys Pages via `actions/upload-pages-artifact@v3` + `actions/deploy-pages@v4`. Soleur's `deploy-docs.yml` already uses `actions/upload-pages-artifact@56afc609…` (v3) + `actions/deploy-pages@d6db9016…` (v4.0.5), satisfying the GitHub Pages deprecation requirement (must use v3/v4+). Mitigation: the post-merge `deploy-docs.yml` workflow is the load-bearing path; if Pages deploy breaks under container, the failure surfaces on first run after merge (operator alarms, not user-visible). Recovery is a 1-line revert of the `container:` directive on the `deploy` job only — keeping the `critical-css-gate` migration intact since `ci.yml` does not call Pages actions.
2. **Container image digest can be rotated by Microsoft** — but a pinned digest is immutable by design; the registry would return a 404 (not silently substitute). If MCR ever deletes a tagged image, the workflow fails fast at container-pull and we update the pin. This is the intended fail-closed behavior.
3. **Playwright version-drift risk between workflows.** The `playwright@1.60.0` npm version, the `v1.60.0-jammy` container tag, and the `sha256:e152...` digest are three values that MUST stay in lockstep across BOTH workflows (4 places total). The AC's grep checks (≥ 2 digest hits, ≥ 4 version hits) catch out-of-sync edits at PR-write time. Future Playwright bumps require updating all four locations in a single PR.
4. **`apps/web-platform/package-lock.json` pins `playwright@1.58.2`** for the unrelated `e2e` job. The two gates run in different jobs with different lockfiles and never share a `~/.cache/ms-playwright/` — no cross-contamination. The `e2e` job continues to use bare `ubuntu-latest` + `actions/cache` keyed on `bun.lock` (unchanged by this PR). If someone later bumps `apps/web-platform`'s Playwright independently, the docs gate is unaffected and vice versa.
5. **The 2026-05-12 cache-key learning (`best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`) describes a bug class this PR eliminates entirely.** The cache step is deleted; there is no cache key to keep correct. The learning's "Drop cache entirely" fallback (Pattern row 4) is what this PR implements at the workflow level by collapsing to a container — even simpler than dropping just the cache step.

## Sharp Edges

- **Container image tag without digest is not vendor-pinned.** If the operator manually edits the workflow to use `mcr.microsoft.com/playwright:v1.60.0-jammy` (without `@sha256:...`), the floating tag will silently drift on Microsoft's side. The pin discipline (`hr-mcp-tools-playwright-etc-resolve-paths`) is load-bearing — keep BOTH the tag (for grep) AND the digest (for vendor-pin).
- **`npm install --no-save playwright@1.60.0` is exact-version-pinned (no `^`, no `~`).** Do not paraphrase this as `playwright@1` or `playwright@^1.60.0` when refactoring; the exact-revision matching that Playwright performs between npm-package and browser-binary requires the npm version to match the container's Playwright revision exactly (see `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`).
- **Future Playwright bumps require updating 4 places, atomically:** two image-pin lines (one per workflow) and two `npm install` lines (one per workflow), each containing both the tag and the digest, all matching `playwright@<X.Y.Z>` and `v<X.Y.Z>-jammy@sha256:<digest>`. The AC grep counts (`≥ 2` digest, `≥ 4` version) are the structural safeguard.
- **`actions/checkout` inside `mcr.microsoft.com/playwright:*-jammy` runs as root** (container default). This is fine for ephemeral CI but worth knowing if any step relies on file-mode bits being non-root. The current gate steps don't.
- **`actions/setup-node` was removed from the gate job.** If a future maintainer assumes a newer Node version is required, they should NOT add `actions/setup-node` back inside the container — instead, bump the Playwright image tag (newer Playwright images bundle newer Node). Adding `actions/setup-node` inside a container that already has Node is harmless but wastes ~5 s.
- **Container layers are cached by the GHA runner automatically** (`actions/runner` ships with a local image cache). No `actions/cache` is needed for the container itself. If pull times become problematic, the runner can be switched to a self-hosted with a warm-image cache — but that's a Phase-6 optimization not in scope here.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section declares `threshold: none` with a one-line non-empty rationale; the preflight Check 6 sensitive-path regex does not match `.github/workflows/*.yml`, so the scope-out bullet is not required.

## Test Strategy

No new test framework introduced (the gate is integration-tested by GitHub Actions itself — the screenshot-gate.mjs script and its 20 routes are the test surface, unchanged by this PR).

Verification is performed via:

1. **PR run of `critical-css-gate`** — green + `< 90 s` wall-clock is the primary signal.
2. **Post-merge run of `deploy-docs.yml`** — full Pages deploy through container.
3. **Plan-time `docker manifest inspect`** — pin verification.

No new bash scripts, no new node scripts, no test fixture changes. `screenshot-gate.mjs` and `screenshot-gate-routes.json` are explicitly out of scope (per ARGUMENT).

## Out of Scope

- Switching to a non-screenshot FOUC-detection strategy (e.g., headless lighthouse audits, CDP-based DOM snapshots).
- Removing the gate from PR CI entirely.
- Editing the 20-route list in `screenshot-gate-routes.json`.
- Editing `screenshot-gate.mjs` or `check-stylesheet-swap.mjs`.
- Bumping the unrelated `apps/web-platform` Playwright version (currently `1.58.2` in `apps/web-platform/package-lock.json` for the `e2e` job).
- Migrating the `e2e` job in `ci.yml` (lines 185–235) to a container. Different scope, different gate, different cache key story.

## PR Body Template

```
Speed up `critical-css-gate` (and the parity `deploy-docs.yml` post-merge gate) by running inside the official Playwright container image with Chromium + OS deps pre-installed. Collapses the install dance to a single `npm install --no-save playwright@1.60.0 http-server@14` and eliminates the `actions/cache` step (which had a documented invariant-key bug — see `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`).

Ref: knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md
Ref: knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md

## Numbers

- Before: 4–5 min (19 s best case, 4:01 worst case observed on PR run 25726234757)
- After: target < 90 s, expected ~60 s with zero variance from apt latency

## Verified

- Container digest pullable: `docker manifest inspect mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e152…cdc` → 0
- Playwright npm version matches container tag: `1.60.0` ↔ `v1.60.0-jammy`
- Required-status-checks ruleset 14145388 unchanged (`critical-css-gate` not in required set)
- AC grep counts: `sha256:e152…cdc` appears ≥ 2 times across both workflows; `playwright@1.60.0` / `v1.60.0-jammy` appears ≥ 4 times
```
