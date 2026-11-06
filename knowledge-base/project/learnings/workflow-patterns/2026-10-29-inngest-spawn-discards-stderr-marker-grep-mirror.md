---
title: An env-var fallback was silent because the Inngest spawn discards script stderr
date: 2026-10-29
category: observability
tags: [workflow-patterns, observability, discord, content-publisher, inngest]
---

# Learning: An env-var fallback was silent because the Inngest spawn discards script stderr

## Problem

Blog posts went to Discord `#general` instead of `#blog` for weeks with zero
signal. Root cause was configuration — `DISCORD_BLOG_WEBHOOK_URL` existed only
in Doppler `ci`, never in `soleur/prd` — but the code made it invisible:
`scripts/content-publisher.sh` `post_discord()` resolves
`${DISCORD_BLOG_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}` (intended fallback,
see 2026-02-19 learning) and emitted nothing on the fallback path.

A stderr-only warning would NOT have fixed it: `spawnScriptCapture` in
`cron-content-publisher.ts` captures the script's stderr into `result.stderr`
and returns only `{ exitCode }` — captured stderr is dropped before any
observability layer can see it. The script's own `SKIP_REASON` comment
documents "The Inngest spawn discards stderr".

## Solution

Two coordinated value-free emits (PR #11504):

1. Script emits a fixed-string warning carrying a dedicated marker token
   (`SOLEUR_PUBLISHER_FALLBACK`) on stderr, placed AFTER the neither-set
   early-return so it fires only when the fallback is actually used
   (`[[ -z "${VAR:-}" ]]` matches `:-` resolution — unset and empty both warn).
2. The cron step greps `result.stderr` for the token via an exported pure
   helper and mirrors a FIXED message via `warnSilentFallback(null, …)`
   (null keeps `captureMessage` + `feature`/`op` tags; an `Error` arg loses
   them to `checkOrSetAlreadyCaught`, #8629 mechanism). The grep/mirror sits
   BEFORE the exit-code throw so a marker + hard-fail still reports, and the
   step return carries `discordBlogFallback` for the Inngest run record.

## Key Insight

For bash spawned by a harness that discards stderr, the observable contract is
a **marker token + grep + fixed-message mirror** — never forward raw stderr
(incidentals: response bodies, filenames) to Sentry. Pin the token literal in
tests on BOTH sides and pin the gate structure with regexes, not presence-only
anchors (a deleted `if (flag)` survives `toContain`).
