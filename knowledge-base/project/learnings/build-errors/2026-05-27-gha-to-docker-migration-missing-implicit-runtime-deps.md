---
title: GHA-to-Docker migration missing implicit runtime dependencies
category: build-errors
tags: [dockerfile, gh-cli, inngest, migration]
date: 2026-05-27
severity: medium
module: apps/web-platform
---

# Learning: GHA-to-Docker migration missing implicit runtime dependencies

## Problem

`cron-follow-through-monitor` Inngest function raised `spawnSync gh ENOENT` in production. The function was migrated from a GitHub Actions workflow (TR9 PR-2, #4063) where `gh` is pre-installed on the runner. The migration preserved `spawn("gh", ...)` and `execFileSync("gh", ...)` call sites verbatim but did not add `gh` to the production Docker image.

Sentry ID: `4a02599747374741a90c6aa06307c049`

## Solution

Added `gh` CLI to the Dockerfile's runner stage via the official GitHub apt repository. Pinned to `gh=2.92.0` for reproducible builds, consistent with existing version-pinning patterns for `claude-code` and `playwright` in the same file.

## Key Insight

When migrating from GHA runners to Docker containers, audit every binary the workflow invokes — GHA runners include `gh`, `jq`, `curl`, `python3`, etc. by default. The Dockerfile must explicitly install each one. Grep for `spawn`, `execFileSync`, `execSync`, and `spawnSync` in the migrated code to enumerate runtime binary dependencies.

## Session Errors

1. **Docker verification curl error 77** — `docker run node:22-slim` test failed because `ca-certificates` was not included in the isolated test (the real Dockerfile installs it in a preceding RUN block). Recovery: added `ca-certificates` to the test command. **Prevention:** When testing Dockerfile additions in isolation via `docker run`, replicate all preceding RUN block dependencies that the new block depends on (especially `ca-certificates` for any HTTPS fetch).

## Tags

category: build-errors
module: apps/web-platform
