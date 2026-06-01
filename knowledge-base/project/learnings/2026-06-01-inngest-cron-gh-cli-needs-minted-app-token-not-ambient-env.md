# Learning: Inngest crons that shell out to `gh` need a minted GitHub App token, not ambient `process.env.GH_TOKEN`

## Problem

`cron-follow-through-monitor` (fnId `soleur-runtime-cron-follow-through-monitor`) threw on **every** `0 9 * * 1-5` run (Sentry `512e253141294ac1a808b2ef03a21289`, release `web-platform@0.102.0+14c06d9f`):

```
Error: Command failed: gh issue list --label follow-through --state open --json number,title,body --limit 100
To get started with GitHub CLI, please run:  gh auth login
Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
```

The `validate-predicates` step ran `execFileSync("gh", [...], { env: buildSpawnEnv() })`, and `buildSpawnEnv()` populated `GH_TOKEN` from `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN`. **Both are empty inside the production Next.js container** (there is no `gh auth login`, no PAT injected), so the fallback resolved to `undefined` and `gh` ran unauthenticated.

## Solution

Mint a short-lived GitHub App installation token in a dedicated first `step.run("mint-installation-token", …)` (memoized across Inngest replay), and inject it as `GH_TOKEN` into every `gh` subprocess env. `buildSpawnEnv()` becomes `buildSpawnEnv(installationToken: string)` returning `GH_TOKEN: installationToken`. This is the **exact established precedent** in `cron-bug-fixer.ts` (and ~22 peer crons), using the shared `mintInstallationToken({ tokenMinLifetimeMs })` helper in `_cron-shared.ts`. Satisfies hard rule `hr-github-app-auth-not-pat` (production authenticates via short-lived App token, never an ambient PAT / `gh auth login`).

## Key Insight

The bug is a **class**, not an instance. The canonical grep to find every cron with it:

```
grep -rn "GH_TOKEN: process.env.GH_TOKEN" apps/web-platform/server/inngest/functions/
```

At fix time this returned 2 hits — `cron-follow-through-monitor.ts` (the Sentry-cited one) and `cron-daily-triage.ts` (same root cause, but no server-side `execFileSync`, so its `gh` calls failed *inside* the spawned agent and never produced the exact server-side Sentry signature). **A function being silent in Sentry does NOT mean it is healthy** — daily-triage was equally broken. Both were folded into one PR (`wg-defer-only-after-inline-triage`). Changing `buildSpawnEnv` to *require* the token argument makes `tsc` flag every un-migrated call site, so the signature change is the cheapest way to guarantee the whole file is covered.

Test the *override*, not just the presence: a value-equality assertion (`GH_TOKEN === minted`) rides behind the mint-step-existence gate and is never independently RED. Seed a bogus ambient `process.env.GH_TOKEN` and assert the subprocess sees the **minted** token, not the ambient one — that is the actual incident vector and makes the assertion load-bearing.

## Session Errors

1. **Bash CWD non-persistence** — after `cd <worktree-root> && git commit`, the next `./node_modules/.bin/vitest run …` executed from the bare-repo root (`EXIT=127, No such file or directory`). **Recovery:** re-ran with explicit `cd apps/web-platform && …`. **Prevention:** chain `cd <abs-path> && <cmd>` in a single Bash call for every test/typecheck invocation in a worktree pipeline (already documented in work/SKILL.md and `2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`).
2. **TS tuple-index errors (TS2352 + TS2493)** — indexing `execFileSyncSpy.mock.calls[0][2]` on a `vi.fn(() => Buffer.from("[]"))` spy whose inferred call tuple has arity 0. **Recovery:** widen via `const execCall = spy.mock.calls[0] as unknown as unknown[];` before indexing the options arg. **Prevention:** when a typed `vi.fn()` spy's call tuple is indexed beyond its declared arity, widen with `as unknown as unknown[]` first (untyped `vi.fn()` spies like `spawnSpy` don't need this).
3. **Single Edit anchor miss** — a multiline handler-signature `old_string` failed to match. **Recovery:** used a shorter unique anchor (`}> {` + the following comment line). One-off; no rule warranted.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest/functions
