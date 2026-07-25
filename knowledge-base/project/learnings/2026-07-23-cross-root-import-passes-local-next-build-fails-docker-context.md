---
title: "A cross-root import into repo-root scripts/ passes local `next build` but fails the Docker build context (which excludes it)"
date: 2026-07-23
issue: 6794
pr: 6852
hotfix_pr: 6875
tags: [docker, next-build, build-context, import-boundary, release, cross-root-import]
category: build-errors
---

# Cross-root import: green local `next build`, red Docker build

## Problem

#6852 (the #6794 work) added, in `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`:

```ts
import { stripFrontmatter } from "../../../../../scripts/lib/frontmatter-strip/strip";
```

— importing a module from **repo-root `scripts/`**, five levels up and outside
`apps/web-platform/`. This was flagged at review by `code-simplicity-reviewer`
(recommend inline) and `architecture-strategist` (cross-app-boundary import,
first of its kind), and surfaced as decision-challenge #6860; the plan defaulted
to #6794's literal "use `strip.ts` in the cron", and I honored that default
because the **hard build gate passed locally**: `cd apps/web-platform && npm run build`
(`next build`/webpack) exited 0, and `tsc --noEmit` was clean.

It shipped green through **all** PR CI (which builds locally, full repo present)
and merged. Then the `web-platform-release` Docker build failed:

```
#21 82.89 Module not found: Can't resolve '../../../../../scripts/lib/frontmatter-strip/strip'
> 52 | import { stripFrontmatter } from "../../../../../scripts/lib/frontmatter-strip/strip";
> Build failed because of webpack errors
ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1
```

(release run 29994907565, step 19 "Build and push Docker image"). `deploy` /
`live-verify` were skipped downstream → the new code never reached prod (prod
kept running the prior image; no user-facing outage, but the release pipeline
was red and the change undeployed).

## Root cause

The Next.js **Docker build context** copies only `apps/web-platform/` plus the
vendored plugin — **not** repo-root `scripts/`. Inside the container, `npm run build`
runs `next build` against that narrower tree, so the `../../../../../scripts/…`
specifier resolves to a path that does not exist in the image → webpack
`Module not found`.

A **local** `next build` runs against the full working tree, where repo-root
`scripts/` IS present, so the import resolves and the build is green. **The local
build is not a faithful proxy for the containerized build when an import escapes
`apps/web-platform/`.**

## Solution

#6875 adopted the reviewers' inline alternative: **inline the ~6-line
frontmatter strip** directly in `cron-compound-promote.ts`, contract-pinned to
`scripts/lib/frontmatter-strip/SPEC.md`. `strip.ts` stays as the parity-tested
third TS impl (strip.sh/py/ts three-way parity unchanged); the behavioral-equality
guarantee comes from the parity test regardless of import-vs-inline. The Docker
build then succeeded, deployed, and `live-verify` + prod `/health` were green.

Added a **repo-wide guard**,
`apps/web-platform/scripts/lib/no-cross-context-import.test.sh` (scripts shard):
it resolves every relative import in `apps/web-platform` production files and
fails if any resolves OUTSIDE `apps/web-platform/`. This moves the whole class
from "post-merge release failure" to "PR-time / touched-file test failure".

## Key Insight

**When a build gate has a narrower context than the local run, a green local
build is not proof.** A cross-root import (or any dependency that escapes the
containerized build context) passes local `next build` + `tsc` and every
context-blind PR check, then fails only at the release Docker build — the most
expensive place to discover it. Two durable defenses:

1. **Trust the reviewer's cross-boundary-import flag over the local build.** When
   review flags an import that crosses the app boundary, "local `next build`
   passes" does not clear it — the container context is the authority. The cheaper,
   lower-risk option (inline, contract-pinned) was right; the DRY win from importing
   was illusory because the anti-drift guarantee came from the parity test either way.
2. **Guard the build-context boundary mechanically**, so the class fails at PR time
   rather than at release. A `next build` in PR CI that used the *same* context copy
   as the Dockerfile would also catch it; the source-scan guard is the cheaper
   approximation.

Also: the plan's hard "build gate = `tsc` + `next build`" was necessary but
**insufficient** — it was satisfied by a build whose context differed from the one
that actually ships. A gate is only as good as the fidelity of its environment to
production (sibling of "run the un-mutated baseline in the same harness first").

Related: [[2026-07-23-mirror-measurement-authority-exactly-not-equal-under-a-current-invariant]] (the same #6794 work), and the decision-challenge #6860 that predicted this.
