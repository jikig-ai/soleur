# Learning: /proc sandbox deny list fix

## Problem

Agent sandbox `denyRead` config in `agent-runner.ts` did not include `/proc`, allowing potential cross-tenant information leakage via `/proc/<pid>/environ`, `/proc/<pid>/maps`, etc. Three defense-in-depth layers already blocked `/proc` (workspace path check, canUseTool callback, bash regex), but the OS-level bubblewrap enforcement was missing.

## Solution

Added `"/proc"` to the `denyRead` array in `apps/web-platform/server/agent-runner.ts:346`. Added a test in `sandbox-hook.test.ts` verifying the hook layer also denies `/proc/1/environ`. Created follow-up issue #1285 for `/sys` hardening (out of scope for #1047).

## Key Insight

When multiple defense layers exist, ensure the lowest-level enforcement (OS/kernel) is configured first. Higher-level checks (application hooks, regex patterns) are defense-in-depth but can be bypassed if the OS-level boundary is missing.

## Session Errors

1. **Ralph loop script path wrong** — `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` does not exist; correct path is `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Prevention:** The one-shot skill hardcodes this path; it should be verified against the actual file structure.
2. **vitest not found via npx** — `npx vitest run` failed with rolldown module resolution error in worktrees. Required `bun install` in `apps/web-platform/` then using `./node_modules/.bin/vitest` directly. **Prevention:** Already covered by AGENTS.md rule "Ensure all dependencies are installed at the correct package level."
3. **bun.lock drift** — `bun install` produced lockfile changes unrelated to the fix. **Prevention:** Expected behavior when lockfile is not frozen; no action needed.

## Tags

category: security-issues
module: web-platform/agent-runner
