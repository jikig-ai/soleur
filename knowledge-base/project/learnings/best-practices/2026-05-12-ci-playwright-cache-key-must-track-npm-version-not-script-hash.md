---
module: System
date: 2026-05-12
problem_type: best_practice
component: ci
symptoms:
  - "critical-css-gate fails on PRs that do not touch docs (Playwright chromium binary missing)"
  - "browserType.launch: Executable doesn't exist at /home/runner/.cache/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell"
  - "actions/cache restores a stale Playwright browser tree across Playwright version bumps"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [ci, playwright, cache-key, workflow-conditional, paths-filter, github-actions]
---

# CI Playwright Cache Key Must Track npm Version, Not Consumer Script Hash

## Problem

Two independent bugs in `.github/workflows/ci.yml`'s `critical-css-gate` combined to fail PRs that had no business running the gate at all:

1. **No path filter on the job.** The gate ran on every PR — including server-only or test-only diffs — paying ~50 s of CI time per irrelevant run and (on staleness) failing them outright.
2. **Cache key invariant to Playwright version.** The cache key hashed `screenshot-gate.mjs` (the consumer script), which never references the Playwright version. The cache-hit branch ran only `npx playwright install-deps chromium` (OS deps, not the binary), so when upstream Playwright shipped a new chromium revision (`chromium_headless_shell-1223` → next), the cached binary went stale and every cache-hit run failed with `Executable doesn't exist at /home/runner/.cache/ms-playwright/...`. No one would notice until the next time someone edited `screenshot-gate.mjs` (which busted the cache and forced a fresh install).

PR #3602 (a server-only diff to `apps/web-platform/server/cc-dispatcher.ts`) hit both failures simultaneously: the gate had no business running, but it ran, and it failed on the stale binary. `/soleur:ship` Phase 7 correctly refused to bypass the failure, blocking auto-merge.

## Two Lessons

### Lesson 1 — Workflow-level `paths:` gates ALL jobs; use a per-job conditional when one workflow houses unrelated jobs

`ci.yml` houses 11+ jobs (`test`, `e2e`, `lint-*`, `web-platform-build`, `critical-css-gate`, …). A workflow-level `on.pull_request.paths` filter would orphan required checks (`test`, `e2e`, `CodeQL`, `skill-security-scan PR gate`) on non-docs PRs. The correct shape is a small `detect-changes` job emitting a boolean output, then `needs: detect-changes` + `if: needs.detect-changes.outputs.docs == 'true'` on the single job that should be conditional.

The in-repo precedent is `.github/workflows/infra-validation.yml:24-52`, which uses the same hand-rolled `actions/checkout@<pin>` + `fetch-depth: 0` + `git diff --name-only "origin/${BASE_REF}...HEAD"` shape (with a matrix-shaped output instead of a single boolean). Adopting `dorny/paths-filter@v3` was considered but rejected: it would have been the first usage of that action in the repo, triggering a vendor-pin obligation, when the hand-rolled pattern already works.

**`fetch-depth: 0` is mandatory.** Default `fetch-depth: 1` (shallow clone) makes `git diff --name-only "origin/${BASE_REF}...HEAD"` return nothing — the filter would silently always-skip on PRs.

### Lesson 2 — Playwright cache key must include something that advances with the Playwright version

Playwright's browser binaries are versioned by chromium revision (`chromium_headless_shell-1223`), not by npm package version directly. But the npm package version IS the source of truth — bump `playwright@1.X.Y` → npm install pulls a new binary; lockfile hash changes. So the cache key must include the lockfile (or any file whose hash advances on a Playwright bump).

| Pattern | Cache key behavior | Verdict |
|---|---|---|
| `hashFiles('screenshot-gate.mjs')` | Invariant to Playwright version | **Wrong** — went stale silently |
| `hashFiles('package-lock.json')` | Advances on every Playwright bump | **Right** — caches refresh on bump |
| `hashFiles('apps/web-platform/bun.lock')` | Right for the `e2e` job (bun-mediated install) | Wrong here — the critical-CSS gate installs via `npm install --no-save playwright@1` against the root `package-lock.json` |
| Drop cache entirely (match `deploy-docs.yml`) | Zero invariant drift risk; +30-40 s per run | Acceptable fallback if cache-key realignment shows residual failures |

**Cache-hit vs cache-miss install diverge by design** (`ci.yml:236-246`): cache-miss runs `npx playwright install --with-deps chromium` (binary + OS deps); cache-hit runs only `npx playwright install-deps chromium` (OS deps only). When the cache key advances on a Playwright bump, the cache-miss branch fires on first hit and reinstalls the new binary. When the key is invariant, the cache-hit branch reuses a stale binary forever.

## Resolution

Single PR (#3624 fix) edits `.github/workflows/ci.yml` only:

1. Insert a `detect-changes` job (mirrors `infra-validation.yml:24-52`) that emits `outputs.docs` as `'true'` or `'false'` based on a regex anchor list mirroring `deploy-docs.yml`'s `paths:`. Push events to `main` and `workflow_dispatch` always run the gate.
2. Add `needs: detect-changes` and `if: needs.detect-changes.outputs.docs == 'true'` to `critical-css-gate`.
3. Realign the cache key: `hashFiles('plugins/soleur/docs/scripts/screenshot-gate.mjs')` → `hashFiles('package-lock.json')`.

The static `check-critical-css-coverage.mjs` step continues to run unconditionally whenever the job runs (the path filter governs whether the job runs at all, not which steps within it run). `deploy-docs.yml` continues to run the same gate post-merge without caching as the load-bearing safeguard.

## Generalizable Pattern

When wiring a cache for an external tool that ships native binaries (Playwright browsers, bun, deno, foundry forge, etc.) in a workflow that already installs via a package manager:

- **Cache key = `hashFiles('<lockfile>')`** — the lockfile is the canonical version-anchor.
- **Never** key on a downstream consumer script unless that script directly encodes the tool version.
- **Cache-hit branches must not bypass binary install** — only OS-level setup. Anything that touches the cached path itself must run on cache miss too.
- **When one workflow houses required + non-required jobs**, scope conditionals per-job via a `detect-changes` upstream, not workflow-level `paths:`. Workflow-level `paths:` orphans every required check on non-matching diffs.
