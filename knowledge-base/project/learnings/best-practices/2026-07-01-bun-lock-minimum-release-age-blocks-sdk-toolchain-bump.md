---
date: 2026-07-01
category: best-practices
module: ci-cd
tags: [bun, lockfile, dual-lockfile, minimum-release-age, model-launch, supply-chain, ci-gate, frozen-lockfile]
issue: 5849
pr: 5849
---

# Learning: a model-launch SDK bump leaves bun.lock un-updatable for 3 days — regenerate it with `--minimum-release-age=0` so CI's frozen install stays green

## Problem

`apps/web-platform/` is a **dual-lockfile** directory: both `package-lock.json`
(npm) and `bun.lock` are committed, and CI runs `bun install --frozen-lockfile`
in many jobs (`ci.yml`, `web-platform-release.yml`, `tenant-integration`, `e2e`,
`produce`, `main-health-monitor.yml`, `cla-evidence.yml`, `validate-vector-config.yml`).

Every per-Anthropic-model-release migration bumps the toolchain in `package.json`
(`@anthropic-ai/claude-code`, `@anthropic-ai/claude-agent-sdk`, `@anthropic-ai/sdk`).
Those releases are **hours-to-days old** when the migration is authored. Both
`bunfig.toml` files set:

```toml
[install]
minimumReleaseAge = 259200   # 3 days — supply-chain defense, issue #1174
```

So a plain `bun install` (or `--lockfile-only`) **cannot resolve the new
versions** and aborts:

```
error: No version matching "@anthropic-ai/claude-code" found for specifier
"2.1.197" (blocked by minimum-release-age: 259200 seconds)
```

The migration therefore updates `package-lock.json` (npm has no age policy) but
silently leaves `bun.lock` on the OLD versions. Because `bun.lock` now diverges
from `package.json`, CI's `bun install --frozen-lockfile` is forced to
re-resolve, hits the same age wall, and **every bun-based CI job fails at the
install step** (~15-45s, before any test runs). Waiting 3 days does NOT
self-heal it: `--frozen-lockfile` refuses to update a stale lock, so `bun.lock`
must be regenerated regardless.

PR #5849 (Sonnet-5 migration, `2.1.197`/`0.3.197`, both <3 days old) shipped
green on npm/`tsc`/vitest (which use already-installed `node_modules`, not a
frozen install) but turned every bun-based CI check red.

## Fix

Regenerate `bun.lock` with the age gate bypassed *only for the lock-generation
step*, so the committed lock matches `package.json`:

```bash
cd apps/web-platform
bun install --lockfile-only --minimum-release-age=0
```

Then **prove it against what CI actually runs** — a frozen install with NO
override:

```bash
bun install --frozen-lockfile   # must print "Checked N installs ... (no changes)"
```

This passes because a lock that **matches** `package.json` needs no
re-resolution, and bun's age gate only fires during *resolution* — the frozen
install reads pinned versions straight from the lock. Commit the regenerated
`bun.lock` alongside the `package.json` + `package-lock.json` bump.

## Why the override is safe here

The `--minimum-release-age=0` bypass is scoped to lock generation, not a policy
change:

- The versions are legitimate first-party Anthropic releases, already pinned +
  integrity-verified in `package-lock.json` (which npm CI installs).
- The committed `bun.lock` is byte-identical to what a plain `bun install` would
  produce once the packages age past 3 days — the override only shifts *when*,
  not *what*.
- `bunfig.toml`'s `minimumReleaseAge` is untouched; the guard still applies to
  every future un-pinned install.

## How to prevent recurrence

- **When the model-launch migration bumps the Anthropic SDK toolchain, update
  BOTH lockfiles in the same PR.** `bun.lock` won't take the <3-day-old versions
  via plain `bun install` — use `bun install --lockfile-only --minimum-release-age=0`,
  then confirm `bun install --frozen-lockfile` (no override) is clean.
- CI's `lockfile-sync` job only regenerates + diffs `package-lock.json` (npm@11).
  It does NOT cover `bun.lock`. The frozen-install jobs are the ones that break;
  they fail as an install-step error, not a lockfile-diff error — so don't look
  for it in `lockfile-sync`.
- Cheapest local pre-ship check for any dual-lockfile dir:
  `git diff --name-status origin/main...HEAD -- '*/package-lock.json' '*/bun.lock'`
  — if only one side moved, the other is stale (`/soleur:preflight` Check 3 also
  flags this).
