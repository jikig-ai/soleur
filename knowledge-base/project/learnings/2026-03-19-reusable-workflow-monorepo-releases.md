# Learning: reusable workflow pattern for monorepo per-app releases

## Problem

A monorepo with `plugins/soleur/`, `apps/web-platform/`, and `apps/telegram-bridge/` needed independent versioning. The existing release workflow only handled the plugin. App-only PRs merged to main with no version bump, no release, no Docker tag.

## Solution

**Architecture: reusable workflow + per-app callers**

`reusable-release.yml` (shared logic via `workflow_call`):
- Path change detection, PR extraction, semver bump, GitHub Release, Docker build+push, Discord notification
- Parameterized via inputs: `component`, `path_filter`, `tag_prefix`, `docker_image`, `docker_build_args`, `bump_type`
- Outputs: `version`, `tag`, `released` (consumed by caller deploy jobs)

Per-app caller workflows (~50 lines each):
- Pass app-specific config to the reusable workflow
- Handle deploy steps inline (structurally different per app — SSH targets, volumes, ports)
- Each has its own `workflow_dispatch` with `bump_type` input

**Key design decisions:**
- Deploy lives in callers, NOT in the reusable workflow (deploy differs per app)
- `bump_type` input on the reusable workflow allows `workflow_dispatch` passthrough from callers
- Each component gets its own concurrency group (`release-web-platform`, `release-telegram-bridge`)
- Docker tags strip the component prefix: git tag `web-v0.1.0` → Docker tag `:v0.1.0` (avoids redundancy with image name)
- Shared `semver:*` labels + `app:*` labels (no per-component semver labels)

**Gotchas encountered:**
1. `permissions: contents: write, packages: write` must be set — `gh release create` and Docker push both fail without explicit permissions
2. Callers pass secrets via `secrets: inherit` (passes ALL secrets — acceptable for single-maintainer, revisit for multi-contributor repos)
3. The security_reminder_hook blocks the first write to each workflow file — plan for one retry per file

## Key Insight

For monorepo releases with 2-3 app components, the reusable workflow pattern is justified when the shared logic (bump computation, release creation, changelog extraction, Discord notification) is 6x the per-caller config. Keep structurally different steps (deploy) in callers. Do NOT refactor the existing working workflow in the same PR — reduce blast radius by deferring to a follow-up after the new workflows prove stable.

## Tags
category: implementation-patterns
module: ci-cd, github-actions, monorepo
severity: medium
