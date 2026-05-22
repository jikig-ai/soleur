---
title: Pin npm version inside lockfile-sync CI job — same Node major does not imply same npm
date: 2026-05-22
category: ci-cd
tags: [integration-issues, ci, lockfile, npm]
---

# Learning: Pin npm version inside lockfile-sync CI job — same Node major does not imply same npm

## Problem

The `lockfile-sync` CI gate (added 2026-04-03) regenerates `apps/web-platform/package-lock.json` under whatever npm version the runner ships, then `git diff --exit-code`s against the committed file. For two months that worked because operators and CI both happened to be on npm 10.

Two PRs flipped this — same `npm-major-skew between operator and CI` class, different shape facets:

- PR #4014 (2026-04 — first occurrence of this class). Lockfile diverged on the `libc` arrays facet (npm 10 emits no `libc` arrays on platform-specific optional deps where npm 11 emits them, or vice-versa). Patched by operator-side regen under `npx npm@10`. The workaround was not codified in the gate, so future contributors on a different npm major could re-introduce the skew.
- PR #4331 (2026-05-22 — second occurrence, the regression that prompted #4337). Introduced `flagsmith-nodejs` via `bun add`, which updates `package.json` but not `package-lock.json`. The hotfix PR #4334 ran `npm install --package-lock-only` on an operator-local npm 11 install and committed — correct shape for npm 11, but CI's npm 10 disagreed on regeneration. The diverging facet this time was `"dev": true` on optional transitive packages, not `libc` arrays. Three consecutive `main` runs failed with the same 17-line diff: pure `+      "dev": true,` additions on optional transitive entries (`@emnapi/runtime`, `@img/sharp-darwin-*`, `@img/sharp-linux-*`, `@img/sharp-linuxmusl-*`, `@img/sharp-win32-*`, `fsevents`).

The class (operator/CI npm-major skew producing a `git diff --exit-code` failure on the regenerate-and-diff gate) is recurrence-prone; the specific shape facet npm chooses to diverge on can change patch-by-patch. Every PR's auto-merge was blocked at the gate until #4337 landed.

## Root cause

`actions/setup-node@v4.4.0` with `node-version: 22` ships **npm 10.9.x** (currently 10.9.4 on `node:22-slim`; 10.9.8 on the GitHub-hosted Ubuntu runner). Operators who run `npm install --package-lock-only` against Node 23+ or after a `bun add` hotfix have npm 11.x (currently 11.15.0). The two npm majors disagree on whether to emit `"dev": true` on optional transitive packages — npm 10 emits it, npm 11 does not. `npm ci` tolerates the difference (production deploys are unaffected); only the regenerate-and-diff strict check trips.

`actions/setup-node@v4.4.0` does NOT expose an `npm-version` input (verified live via the action's manifest at SHA `49933ea`). Inputs are `node-version`, `node-version-file`, `architecture`, `check-latest`, `registry-url`, `scope`, `token`, `cache`, `package-manager-cache`, `cache-dependency-path`, `mirror`, `mirror-token`. The `npm install -g npm@<version>` pattern is the only workflow-side pin available.

## Solution

Add a `Pin npm version` step at the top of the `lockfile-sync` job:

```yaml
- name: Pin npm version
  run: npm install -g npm@11
```

`npm@11` resolves the latest 11.x at install time via semver range (there is no `latest-11` floating dist-tag on the npm registry). A future 11.x patch that changes lockfile shape would fail the gate loudly; the fix is a one-line tightening to `npm@11.<minor>`.

The narrow scope matters: only the `lockfile-sync` job is pinned. Every other job (`web-platform-build` running `npm ci` against `node:22-slim`'s npm 10.9.4, all scheduled workflows) keeps the bundled npm. This is one-sided by design — production deploys are not affected because the divergent flag is non-load-bearing for `npm ci`.

## Key Insight

For dual-lockfile projects using `actions/setup-node` + `npm install --package-lock-only` as a regenerate-and-diff gate:

1. **Pin the npm major-version inside the gate's job.** The Node major alone is insufficient — the npm major is a separate vector with its own shape-changing release cycle. Don't rely on the `actions/setup-node` default.
2. **Choose the operator-likely npm major as the pin.** Pinning npm 10 would require every contributor to remember `npx npm@10` — a maintenance burden that fails open. Pinning npm 11 leans on the natural drift of operator installs (Node 23+, fresh asdf/Volta, `bun add` flows). The lockfile's committed shape is the contract; the gate enforces it under whatever pin the workflow specifies.
3. **Name the pin in the error message.** When the gate fires, the operator should not have to read the workflow file to know which npm to use. `Run 'npx --yes npm@11 install --package-lock-only'` in the `::error::` message closes the diagnostic loop.
4. **Reject `npm ci --dry-run` as a substitute.** It validates lockfile-vs-node_modules consistency, NOT package.json-vs-lockfile consistency. The bun-add-updates-package.json-but-not-lockfile defect class (the exact recurrence-prone shape) would pass under `npm ci --dry-run` because the stale lockfile is internally consistent.
5. **Document the pin in operator-facing README.** Workflow-side pins are necessary but not sufficient; the README note prevents the next recurrence from contributors who skip the gate entirely (e.g., regenerate locally and force-push).

## Future direction

`actions/setup-node@v4.4.0` honors a top-level `"packageManager": "npm@<version>"` field in `package.json` via the `package-manager-cache` input. Adding that field would pin npm at the `package.json` level — stronger than the workflow-side pin because it covers contributor machines too (via Corepack). Out of scope here because it requires a separate rollout (Corepack on, all contributors run `corepack enable`). The future PR can swap the workflow's `npm install -g npm@11` for the `packageManager`-field approach without breaking anything.

## Session Errors

1. **Initial Edit blocked by plugin security-reminder hook.** First attempt to edit `.github/workflows/ci.yml` returned a `PreToolUse:Edit hook error` from `${CLAUDE_PLUGIN_ROOT}/hooks/security_reminder_hook.py`. The plugin hook (distinct from the project's same-named hook at `.claude/hooks/`) blocks the first edit per session as an advisory; retry succeeds. Recovery: re-issued the identical Edit. Prevention: documented in this learning so future edits to `.github/workflows/*.yml` know to expect the one-time block.

## Tags

category: integration-issues
module: ci
