---
title: "Platform reported 'disabled' despite creds in Doppler → check the spawn-env allowlist, not the secret store"
date: 2026-06-03
category: integration-issues
module: apps/web-platform/server/inngest
tags: [inngest, spawn-env, allowlist, community-monitor, credentials, doppler]
---

# Learning: a platform reported "disabled" in a spawned-subprocess digest, despite creds being present in Doppler

## Problem

The 2026-06-03 scheduled community-monitor digest reported **X/Twitter = disabled** even though all four
X credentials (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) were verified
present in Doppler config `soleur/prd_scheduled`. The other platforms (Discord/Bluesky/LinkedIn) were enabled.

## Root cause

The community monitor runs as the Inngest function `cron-community-monitor.ts`, which spawns `claude --print`
behind an explicit **spawn-env allowlist** (`buildSpawnEnv()`). The allowlist forwarded the
Discord/Bluesky/LinkedIn vars but **omitted the four `X_*` vars** (a miss in the original "PR-11 bucket-ii
authorization" addition). The spawned subprocess runs `community-router.sh`, whose `check_auth()` marks a
platform `disabled` the moment any required env var is empty — so even though the creds were in the parent
process's `process.env` (from Doppler), they never crossed the spawn boundary.

## Key Insight

When a credential-gated capability is reported **disabled inside a spawned subprocess** but the credentials
are confirmed present in the secret store, suspect the **in-process forwarding boundary** (the spawn-env
allowlist), not the secret store. An explicit allowlist (the correct security posture — no `...process.env`
spread) silently drops any var not enumerated, and adding a new platform's creds to Doppler does nothing if
the allowlist that forwards env to the subprocess was never widened. Grep the spawn point (`buildSpawnEnv`,
`env: { ... }` on `spawn`/`execFile`) and compare its key set against the consumer's required-var list.

Read-only vs write boundary: the monitor deliberately forwards only the four X **read** creds and NOT
`X_ALLOW_POST` (the posting guard, armed only in the publisher). A negative-class test asserts `X_ALLOW_POST`
stays absent from the function body so a future careless edit can't enable posting from a read-only path.

## Session Errors

1. **Plan args named a wrong test-file path** (`server/inngest/...test.ts` vs actual `test/server/inngest/...test.ts`).
   Recovery: plan subagent's premise validation corrected it. Prevention: covered by `hr-when-a-plan-specifies-relative-paths` — verify a cited path resolves on disk before passing it into a subagent prompt.
2. **One-shot collision gate aborted the first invocation** — `#4880`, an auto-generated scheduled-digest
   issue, was framed as a `Closes #N` work-target in the one-shot args; it had already CLOSED when its digest
   PR auto-merged, so the closed-issue gate fired correctly. Recovery: re-launched with the `#N` ref scrubbed
   to descriptive phrasing. Prevention: covered by `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`
   — scrub closed contextual `#N` citations from one-shot prose args; only OPEN work-targets belong in `#N` form.
