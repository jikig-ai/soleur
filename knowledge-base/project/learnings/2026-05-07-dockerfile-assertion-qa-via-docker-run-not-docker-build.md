---
title: QA Dockerfile build-time assertions via `docker run -v`, not `docker build`
date: 2026-05-07
category: best-practices
module: apps/web-platform/Dockerfile
related_pr: "#3435"
related_issue: "#3422"
tags: [docker, qa, ci, dockerfile, build-assertions]
---

# QA Dockerfile build-time assertions via `docker run -v`, not `docker build`

## Problem

A PR adds a build-time assertion to `apps/web-platform/Dockerfile`:

```dockerfile
RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"
```

The plan's Test Scenarios are docker-build outcomes ("happy path: docker build succeeds"; "negative path: docker build aborts when pdfjs-dist is missing"). Running a full `docker build -f apps/web-platform/Dockerfile apps/web-platform/` to verify them is expensive and over-scoped:

- Requires CI-only build context: `apps/web-platform/_plugin-vendored/` (created by `reusable-release.yml`'s "Vendor plugin into build context" step), Sentry source-map upload tokens, NEXT_PUBLIC_* args.
- ~5-10 min wall-clock on a workstation.
- Most build steps (next build, esbuild server compile, apt-get install of bubblewrap/socat/qpdf) are unrelated to the assertion under test.

## Solution

Run the assertion's exact predicate inside the same pinned base image via `docker run -v`. This isolates the regression class the assertion targets (deps missing from the runner stage's `node_modules`) from the rest of the build.

### Positive path (assertion succeeds when deps are present)

```bash
docker run --rm \
  -v "$(pwd)/apps/web-platform/package.json:/app/package.json:ro" \
  -v "$(pwd)/apps/web-platform/package-lock.json:/app/package-lock.json:ro" \
  -w /app \
  node:22-slim@sha256:4f77a690...4f4589e9ed5bfaf3d \
  bash -c "npm ci --omit=dev --silent && node -e \"require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp'); console.log('OK')\""
```

`npm ci --omit=dev` mirrors the Dockerfile's runner-stage dep install line for line. The `node -e` payload is the literal assertion. Wall-clock: ~30s (most of which is `npm ci`).

### Negative path (assertion fails when a dep is missing)

```bash
docker run --rm node:22-slim@sha256:4f77a690...4f4589e9ed5bfaf3d \
  node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs')"
# → Cannot find module 'pdfjs-dist/legacy/build/pdf.mjs'
# → exit 1
```

Wall-clock: <2s. Proves the assertion exits non-zero — exactly what aborts `docker build` in CI.

## Key Insight

A Dockerfile RUN's correctness is a property of the predicate it executes, not of the build pipeline that invokes it. If the predicate's correctness can be verified in isolation against the same base image and the same `npm ci` invocation, you don't need to rebuild the entire image to QA it.

This is specifically a fit for **build-time assertion lines** (`RUN <command-that-only-fails-or-passes>`) — `node -e "require.resolve(...)"`, `RUN test -f ...`, `RUN [[ "$VAR" =~ ^... ]]`, etc. It is NOT a fit for steps that mutate the image (apt installs, file COPYs, multi-stage artifact transfers) — those need a real `docker build`.

The pinning of `node:22-slim@sha256:...` matters: the digest pin makes the smoke test bit-identical to what CI will run.

## When to use

- Adding/modifying a `RUN <assertion>` line to a Dockerfile.
- The assertion's success or failure depends only on filesystem state established by an earlier RUN (typically `npm ci`).
- You want signal in seconds, not minutes, before pushing.

## When NOT to use

- The change touches `apt-get install`, `COPY --from=builder`, multi-stage artifact transfer, or anything image-shape-altering. Use a real `docker build` (or push to CI).
- The assertion depends on builder-stage outputs that aren't replicable via `docker run -v` mounts (e.g., Next.js `.next/` directory, esbuild server bundle).

## Tags

category: best-practices
module: apps/web-platform/Dockerfile
references: [#3422, #3435, #3410]
