---
date: 2026-05-12
category: best-practices
problem_type: ci_performance
component: github-actions-playwright-gate
tags:
  - github-actions
  - playwright
  - container
  - critical-css-gate
  - deploy-docs
  - vendor-pinning
related_prs:
  - "#3624"
  - "#3654"
related_learnings:
  - 2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md
  - 2026-03-20-playwright-shared-cache-version-coupling.md
---

# CI Playwright gates: prefer official container image over `actions/cache` + `playwright install-deps`

## Problem

The `critical-css-gate` job in `.github/workflows/ci.yml` was taking 4–5 minutes wall-clock (19 s best case, 4:01 worst case observed on PR run 25726234757) on a `ubuntu-latest` bare runner. The dominant cost was the install step pair:

```yaml
- name: Install Playwright + http-server (cache miss)
  if: steps.playwright-cache.outputs.cache-hit != 'true'
  run: |
    npm install --no-save playwright@1 http-server@14
    npx playwright install --with-deps chromium
- name: Install Playwright + http-server (cache hit)
  if: steps.playwright-cache.outputs.cache-hit == 'true'
  run: |
    npm install --no-save playwright@1 http-server@14
    npx playwright install-deps chromium
```

Both branches ran `npm install` (~30 s) and apt-installed Chromium OS deps (`libnss3`, `libgtk-3-0`, `libgbm1`, `libasound2`, etc.). The apt latency on GitHub-hosted runners swings from 30 s to 3+ min depending on which mirror the runner draws. `actions/cache` for `~/.cache/ms-playwright` was added in PR #3624 to amortize the cost but had two structural problems (see related learning [2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash](2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md)):

1. The cache key (`hashFiles('package-lock.json')`) was invariant to Playwright version because root `package-lock.json` had zero `playwright` entries (the install was `--no-save`).
2. Even on cache hit, the apt step ran unconditionally, so the dominant variable cost survived the cache.

## Solution

Replace the bare runner with the official Playwright container, pinned by tag AND multi-arch manifest-list digest:

```yaml
critical-css-gate:
  runs-on: ubuntu-latest
  container:
    image: mcr.microsoft.com/playwright:v1.60.0-jammy@sha256:e1529a04087193966ea15d4a1617345bdaa0791690a24ab2c42b65f9ce5b2cdc
  defaults:
    run:
      shell: bash
  steps:
    - uses: actions/checkout@<sha>
    - run: npm ci
    - run: npx @11ty/eleventy
    # ... static gates ...
    - name: Install Playwright + http-server
      run: npm install --no-save playwright@1.60.0 http-server@14
    - name: Screenshot gate
      run: node plugins/soleur/docs/scripts/screenshot-gate.mjs
```

The container ships Chromium binary at `/ms-playwright/chromium-1223/`, all OS deps, Node 24, and bash 5.1. The entire `actions/cache` + dual-install-step apparatus collapses to one `npm install --no-save playwright@<exact-version> http-server@14`. Apply the same change to `.github/workflows/deploy-docs.yml`'s post-merge `deploy` job for parity (`cq-eleventy-critical-css-screenshot-gate`).

**Empirical**: local end-to-end gate (Eleventy build of 84 files + 20-route screenshot gate) ran in 9.8 s inside the pinned digest. Expected GHA wall-clock 45–65 s including ~20–40 s container pull, comfortably under 90 s.

## Key Insights

### 1. The cache-key fix from PR #3624 was a workaround; the container is the structural fix

When the apt install on cache-hit is the dominant variable cost, caching the binary saves only the smaller npm-package fetch. The bug class isn't "stale binary in cache" — it's "we're installing OS deps at gate-time instead of build-time." Containers move the install to build-time (image bake) at the cost of a one-time per-runner pull. On Microsoft-to-Microsoft network, pull is fast and consistent.

### 2. Pin container images by tag AND digest, mutate them in lockstep

The container image tag (`v1.60.0-jammy`), the manifest-list digest (`sha256:e152…cdc`), and the npm package version (`playwright@1.60.0`) must stay byte-identical across both workflows (4 places total). Playwright's browser-binary lookup is exact-revision (see [2026-03-20-playwright-shared-cache-version-coupling](../2026-03-20-playwright-shared-cache-version-coupling.md)) — a `playwright@^1.60.0` npm pin will silently drift off the container's Chromium revision. Comments at all 4 sites must spell out: `no ^, no ~, no floating tag`. Future Playwright bumps require updating all 4 places atomically.

### 3. `actions/setup-node` inside a container with Node is wasteful

The Playwright `v1.60.0-jammy` image ships Node 24. Adding `actions/setup-node` inside the container either no-ops or wastes ~5 s replacing the runtime. If future maintainers need a specific Node version, they should bump the Playwright image tag (newer tags bundle newer Node) rather than re-adding the action.

### 4. `defaults.run.shell: bash` is mandatory in container jobs

GitHub Actions container `run:` steps default to `/bin/sh`. On Jammy, that's `dash`, not `bash`. Current screenshot-gate step bodies use `$(seq 1 30)`, `kill … 2>/dev/null || true`, `set +e`/`set -e` — all POSIX-compatible — but future steps may use `[[ ]]`, arrays, `read -r`, etc. The explicit `shell: bash` removes a future dash-vs-bash drift class.

### 5. Run the container as root (don't add `--user`)

`actions/checkout` issue #956 documents the constraint: container jobs must run as root or face UID mismatch against `/__w/_temp` (the runner-owned dir mounted into the container). Microsoft's Playwright image runs as root by default — that is the supported `actions/checkout` path. Adding `options: --user 1001` breaks the checkout step.

### 6. Pages-deploy actions work inside container jobs

`actions/configure-pages` v4, `actions/upload-pages-artifact` v3, and `actions/deploy-pages` v4 all work inside a container. The OIDC token is env-injected by the runner (`ACTIONS_ID_TOKEN_REQUEST_URL/TOKEN`), not filesystem-dependent — survives the container boundary cleanly.

## Prevention

When a CI gate's install step swings 30 s → 4 min on cache hit, the bug is structural (the install is variable in the wrong dimension), not configuration (the cache key is wrong). Check for an official container image from the tool vendor before adding `actions/cache`. Container images cost a ~3 GB pull per runner; for tools where the binary needs OS deps (browsers, headless renderers, native libs), the container pull is faster and more deterministic than apt-installing on every gate run.

## Session Errors

1. **Stale bare-repo file read before worktree creation.** I ran `Read .github/workflows/ci.yml` from the bare-repo root early in the session and got a 36-line file (the bare repo's stale synced copy from a prior session). The actual `main` ci.yml is 326 lines. Recovered with `git show main:.github/workflows/ci.yml`. **Prevention:** existing rule `hr-when-in-a-worktree-never-read-from-bare` covers the worktree side of the trap, but the same hazard exists when reading from the bare-repo root itself before any worktree is created. Generalize the mental model: in `core.bare=true` repos, any working-tree file Read is reading a stale synced copy regardless of CWD — prefer `git show <ref>:<path>` for any file read whose freshness is load-bearing (workflow files, schemas, configs the plan reasons about).

2. **Plan AC vs Out-of-Scope contradiction.** Plan AC #4.3 prescribed `git grep -E 'ms-playwright|playwright-cache|install-deps chromium' .github/workflows/{ci,deploy-docs}.yml` returns nothing, but the plan's Out-of-Scope section explicitly excluded the `e2e` job in ci.yml (lines 185–235) — which still uses exactly those patterns. Whole-file grep against ci.yml returns 5 matches from `e2e`. Resolved by running a section-scoped grep (`awk '/^  critical-css-gate:/,0' .github/workflows/ci.yml | grep ...`) on the section under change and documenting the AC's over-broad framing in the commit message. **Prevention:** when writing AC verifications for files that contain multiple top-level targets (workflow files with N jobs, configs with N stanzas, schemas with N tables), scope the verification command to the section under change. The deepen-plan phase should re-verify that the AC's grep matches the plan's intent — if Out-of-Scope names a section in the same file, the verification grep must be section-scoped or it will fail-broad.

3. **PreToolUse Edit hook noise on workflow files.** The `security_reminder_hook.py` PreToolUse hook printed a security advisory the first time I called `Edit` on each workflow file. The second identical retry landed cleanly. The hook is advisory (prints warning + workflow-injection examples) but interrupts the first attempt. **Prevention:** not a workflow change — the hook is functioning as designed (educate-then-allow). Noting only so future sessions don't mistake the first-attempt failure for a blocking error and abandon the edit.

## Related

- [2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash](2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md) — the cache-key learning that this container migration supersedes
- [2026-03-20-playwright-shared-cache-version-coupling](../2026-03-20-playwright-shared-cache-version-coupling.md) — exact-revision browser-binary lookup
- PR #3624 — the cache-key fix that preceded this container migration
- PR #3654 — this container migration
