# Learning: CI lockfile sync check prevents dual-lockfile desync

## Problem

Projects using dual lockfiles (`bun.lock` for dev/CI, `package-lock.json` for Docker `npm ci`) silently desync when developers run `bun install` but not `npm install`. PR CI passes (bun), release Docker build fails (npm). This caused two production outages (#1275, #1306).

## Solution

Added a `lockfile-sync` CI job that runs `npm install --package-lock-only` (regenerates lockfile without writing `node_modules`) then checks `git diff --exit-code` on the lockfile. If the regenerated lockfile differs from the committed one, the job fails with a clear remediation message.

Key technical detail: `npm install --package-lock-only` uses the same Arborist resolver as `npm ci`, ensuring detection parity. No `.npmrc` or version skew concerns when both CI and Docker use the same Node version.

## Key Insight

For dual-lockfile projects, add a CI check that regenerates the secondary lockfile and diffs it against the committed version. This is cheaper than running the full Docker build in CI and catches the exact failure class (stale lockfile) at PR time.

## Session Errors

1. **Wrong script path for setup-ralph-loop.sh** — Used `./plugins/soleur/skills/one-shot/scripts/` instead of `./plugins/soleur/scripts/`. Recovery: corrected path immediately. Prevention: the one-shot skill instructions specify the correct path; this was a misread.

## Tags

category: integration-issues
module: ci
