# Learning: Verify env var consumption at code level before documenting requirements

## Problem

During documentation of `.env` provisioning for disaster recovery (#844), the plan's deepen phase listed `ANTHROPIC_API_KEY` as required by both `web-platform` and `telegram-bridge`. This was factually wrong. `web-platform` uses a BYOK model where API keys are stored per-user in Supabase and passed via `buildAgentEnv(apiKey)` at `server/agent-env.ts:36`. It never reads `process.env.ANTHROPIC_API_KEY` in production code. Only `telegram-bridge` consumes it from the environment (via `safeEnv` spread to the Claude CLI subprocess).

The error originated in plan-phase research that scanned infrastructure references (cloud-init, CI, Dockerfiles) and aggregated every env var mentioned across the stack into a single flat list, then attributed it to both containers without code-level verification.

## Solution

Before documenting any env var as "required by component X":

1. `grep` for `process.env.<VAR>` in the component's source code
2. Trace the code path from grep hit to actual runtime usage (a var may appear in tests but not production code)
3. Distinguish injection-site (cloud-init, CI, Compose) from consumption-site (application code)
4. Cross-check multi-component stacks individually -- do not union env vars across containers

The architecture-strategist review agent caught the error by reading `server/agent-env.ts` and tracing the BYOK key flow.

## Key Insight

Infrastructure artifacts (cloud-init, CI pipelines, Docker Compose) declare variables at the deployment boundary, not the application boundary. A variable present in a shared `.env` file may be consumed by one container and ignored by another. Plan-phase env var inventories are unreliable unless each variable is verified against actual `process.env` reads in the component's source code.

## Related

- `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` -- the `buildAgentEnv()` allowlist that makes web-platform independent of `process.env.ANTHROPIC_API_KEY`
- `2026-03-17-nextjs-docker-public-env-vars.md` -- another env var boundary distinction (build-time vs runtime)
- `2026-03-20-docker-nonroot-user-with-volume-mounts.md` -- prior plan-phase error that propagated contradictory instructions

## Tags

category: documentation-accuracy
module: apps/telegram-bridge, apps/web-platform
