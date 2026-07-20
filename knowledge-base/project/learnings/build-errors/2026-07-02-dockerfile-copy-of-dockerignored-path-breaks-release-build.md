# Learning: a Dockerfile COPY of a file under a wholesale-excluded `.dockerignore` dir breaks the release build (not CI, not tsc)

category: build-errors
module: apps/web-platform (Docker image)
date: 2026-07-02
issue: 5875 (PR #5890 canary → hotfix #5894)

## Problem

PR #5890 (faithful sandbox canary) added two Dockerfile runner-stage lines to bake the payload + fixture into the image:

```dockerfile
COPY --from=builder /app/scripts/sandbox-canary.mjs ./scripts/sandbox-canary.mjs
COPY --from=builder /app/infra/sandbox-canary-argv.json ./infra/sandbox-canary-argv.json
```

Every pre-merge gate was green (vitest 15/15, `tsc --noEmit` 0 errors, infra shell tests, shellcheck, security + observability review). The PR merged — then the `Web Platform Release` build failed:

```
COPY --from=builder /app/scripts/sandbox-canary.mjs ... "/app/scripts/sandbox-canary.mjs": not found
ERROR: failed to build: failed to compute cache key ... not found
```

The failed release does **not** cut over, so prod silently kept running the prior image — a stale-prod outage that no local or PR-CI gate surfaces (PR CI runs `bun test`/`tsc`, not the Docker build).

## Root cause

`apps/web-platform/.dockerignore` excludes `scripts/` and `infra/` **wholesale** (they aren't needed in the runtime image). The builder stage's `COPY . .` therefore never copied the two new files into `/app`, so the runner stage's `COPY --from=builder /app/scripts/...` had nothing to copy. The Dockerfile edit and the `.dockerignore` are coupled, but nothing in the pre-merge gate set exercises that coupling.

## Solution

Add a per-file **re-include** (negation) after each wholesale exclusion — the exact pattern already in the file for `!scripts/assert-dev-signin-eliminated.sh` and `!infra/github-app-manifest.json`:

```
scripts/
!scripts/assert-dev-signin-eliminated.sh
!scripts/sandbox-canary.mjs           # ← the fix
infra/
!infra/github-app-manifest.json
!infra/sandbox-canary-argv.json       # ← the fix
```

Docker `.dockerignore` processes patterns in order; a later `!` re-includes a specific file even when its parent dir is excluded above. Shipped as hotfix #5894; the `Web Platform Release` recovered and prod redeployed healthy.

## Key insight

**A `COPY` of any path under a wholesale-excluded `.dockerignore` directory (`scripts/`, `infra/`, `supabase/`, `test/`, …) needs a matching `!re-include`, and the failure is invisible until the CI *release* build — `tsc`/vitest/local runs never touch the Docker context.** When adding a Dockerfile `COPY <path>` where `<path>`'s top dir appears (bare) in `.dockerignore`, add the re-include in the same change AND verify with a real build. Cheapest verification (no full multi-stage build): a busybox one-off against the real `.dockerignore` —

```bash
cd apps/web-platform
printf 'FROM busybox\nCOPY <path> /x\nRUN ls -l /x\n' | docker build -f - -t t . && docker rmi t
```

`rc=0` proves the file survives `.dockerignore` filtering; `not found` proves it doesn't.

## Session Errors

- **Dockerfile COPY of `.dockerignore`-excluded `scripts/`+`infra/` files broke the post-merge release build** (stale-prod until hotfix). — Recovery: per-file `!re-include` in `.dockerignore` (#5894), verified with a busybox build. — Prevention: when a Dockerfile `COPY`'s a path whose top-level dir is bare-excluded in `.dockerignore`, add the re-include in the same commit and run the busybox-build check before merge. Consider a ship-time gate that greps new `COPY` sources against `.dockerignore` excludes.

## Tags
category: build-errors
module: docker
related: [[2026-07-02-concurrent-session-collision-on-shared-worktree]]
