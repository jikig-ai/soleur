# socat is load-bearing for the Agent SDK bwrap sandbox (not just networking)

**Date:** 2026-04-19
**PR:** #2646
**Issue:** #2634
**Files:** `apps/web-platform/Dockerfile`, `apps/web-platform/server/agent-runner.ts`

## TL;DR

`socat` is **required for any bwrap-wrapped command** in the Claude Agent
SDK sandbox — not just for HTTP/SOCKS bridging. Removing it from the
production image silently disables Tier-4 sandboxing if
`sandbox.failIfUnavailable: true` is NOT set, and crashes every agent
session at startup if it IS set. PR #2646 set `failIfUnavailable: true`,
making removal of `socat` a hard startup failure rather than a silent
unsandboxed run.

## Why this is non-obvious

A casual reader looking at `apt-get install ... bubblewrap socat ...` might
assume `socat` is for an unrelated network utility (the SDK does enforce a
managed-domains allowlist via `network.allowManagedDomainsOnly: true`, so
"socat handles the network bridge" is a plausible-but-wrong mental model).

Empirical capture (2026-04-19, via strace on a session host) showed the
SDK's bwrap argv unconditionally includes a socat-backed shell-script
listener inside the bwrap process tree, regardless of network
configuration. Excerpt of captured argv:

```
socat TCP-LISTEN:3128,fork,reuseaddr UNIX-CONNECT:<sandbox-http-sock>
```

This means: even with the tightest `network` config, `socat` is invoked.
Without it, the bwrap shell script aborts and the SDK either (a) silently
falls back to unsandboxed `/bin/bash -c ...` (default), or (b) refuses to
start (with `failIfUnavailable: true`).

## What survives this learning

1. `apps/web-platform/Dockerfile` — extended comment block above the
   `apt-get install ... socat ...` line names `socat` as load-bearing and
   references this learning.
2. `apps/web-platform/server/agent-runner.ts` — `sandbox.failIfUnavailable: true`
   makes accidental removal a startup failure, not a silent fallback.
3. `apps/web-platform/test/agent-runner-sandbox-config.test.ts` — pins the
   flag against a future config edit that drops it.

## Triggers for a future cleanup PR

If you are minimizing apt deps, dropping `socat` from `Dockerfile`, or
auditing the production image footprint:

- **Do not remove `socat`** without first reading this learning AND
  confirming whether the Agent SDK has changed its bwrap argv.
- Re-run `strace -f -e execve` against a sandboxed `query()` call to
  re-verify before any removal.
- Remember that the regression test pins the SDK config flag, **not** the
  presence of `socat` in the image. The deploy-time signal for missing
  `socat` is an SDK startup throw — visible in Sentry but only after a real
  user starts a session.

## Related

- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — guides the broader
  "no silent failure modes" principle.
- `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`
  — earlier work on bwrap inside Docker.
- `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md`
  — full strace output from the 2026-04-19 capture.
