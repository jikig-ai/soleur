---
title: "feat: per-app release pipelines for web-platform and telegram-bridge"
type: feat
date: 2026-03-19
---

# Per-App Release Pipelines

## Overview

Create independent versioning, release, build, deploy, and notification pipelines for `apps/web-platform/` and `apps/telegram-bridge/` using a reusable GitHub Actions workflow with per-app caller workflows. The existing plugin release workflow remains unchanged in this PR; refactoring it to use the reusable core is deferred to a follow-up (lower blast radius).

**Issue:** #739
**Brainstorm:** `knowledge-base/project/brainstorms/2026-03-19-app-versioning-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-app-versioning/spec.md`

## Problem Statement

Only `plugins/soleur/` has release automation. App-only PRs merged to main produce no version bump, no release, no Docker version tag, and no Discord notification. Deployed containers are identified only by git SHA, making rollback and audit difficult.

## Proposed Solution

A **reusable workflow** (`reusable-release.yml`) encapsulates: path change detection, PR extraction, semver bump computation, GitHub Release creation, Docker build+push, and Discord notification. Per-app **caller workflows** pass app-specific configuration and handle deploy steps (which differ structurally per app).

## Technical Approach

### Architecture

```
PR merges to main (push event)
      │
      ├── version-bump-and-release.yml (UNCHANGED — existing plugin workflow)
      │     └── continues to handle plugins/soleur/ releases independently
      │
      ├── web-platform-release.yml (new caller)
      │     ├── calls reusable-release.yml(component=web-platform, path=apps/web-platform/, tag_prefix=web-v)
      │     │     └── builds + pushes Docker image
      │     └── deploy step (caller-specific): SSH stop/rm/run with health check
      │
      └── telegram-bridge-release.yml (new caller)
            ├── calls reusable-release.yml(component=telegram-bridge, path=apps/telegram-bridge/, tag_prefix=telegram-v)
            │     └── builds + pushes Docker image
            └── deploy step (caller-specific): SSH stop/rm/run with health check
```

### Reusable Workflow Inputs

`.github/workflows/reusable-release.yml`:

```yaml
on:
  workflow_call:
    inputs:
      component:          # "plugin" | "web-platform" | "telegram-bridge"
        type: string
        required: true
      component_display:  # "Soleur" | "Soleur Web Platform" | "Soleur Telegram Bridge"
        type: string
        required: true
      path_filter:        # "plugins/soleur/" | "apps/web-platform/" | "apps/telegram-bridge/"
        type: string
        required: true
      tag_prefix:         # "v" | "web-v" | "telegram-v"
        type: string
        required: true
      docker_image:       # "" | "ghcr.io/jikig-ai/soleur-web-platform" | "ghcr.io/jikig-ai/soleur-telegram-bridge"
        type: string
        default: ""
      docker_context:     # "" | "apps/web-platform" | "apps/telegram-bridge"
        type: string
        default: ""
      docker_build_args:  # "" | "NEXT_PUBLIC_SUPABASE_URL=...\nNEXT_PUBLIC_SUPABASE_ANON_KEY=..."
        type: string
        default: ""
      bump_type:          # for workflow_dispatch: overrides label-based detection
        type: string
        default: ""       # empty = use PR labels; "patch"|"minor"|"major" = override
      force_run:          # for workflow_dispatch bypass of path check
        type: boolean
        default: false
    outputs:
      version:
        description: "The computed version (e.g., 0.1.1)"
        value: ${{ jobs.release.outputs.version }}
      tag:
        description: "The full git tag (e.g., web-v0.1.1)"
        value: ${{ jobs.release.outputs.tag }}
      released:
        description: "Whether a release was created"
        value: ${{ jobs.release.outputs.released }}
```

### Key Design Resolutions (from SpecFlow)

| Gap | Resolution |
|-----|-----------|
| **Semver ordering** | Use `git fetch --tags` after checkout (fetch-depth: 2 only has recent tags), then `git tag --list '<prefix>*' --sort=-version:refname \| head -1`. Git's `version:refname` sort is semver-aware. Falls back to `0.0.0` when no tags match. |
| **Deploy architecture** | Deploy stays in caller workflows, NOT in the reusable workflow. Apps have structurally different deploy commands (volumes, ports, env). Reusable workflow outputs `version`, `tag`, and `released` for callers to consume. |
| **`docker restart` bug** | Telegram bridge deploy.sh uses `docker restart` which does NOT apply the newly pulled image. Fix: use stop/rm/run pattern matching web-platform. |
| **Build args passthrough** | `docker_build_args` input as newline-delimited string, passed to `docker/build-push-action`'s `build-args`. |
| **GHCR org name** | Normalize telegram-bridge to `jikig-ai` (lowercase). Update deploy.sh and Terraform variables. |
| **Docker tag format** | Strip component prefix. Docker tags: `:v0.1.0`, `:<sha>`, `:latest`. Git tag: `web-v0.1.0`. No redundancy. |
| **Shared semver label** | One `semver:*` label applies to all components. Version inflation at pre-1.0 is acceptable. |
| **Missing telegram secrets** | Create `TELEGRAM_BRIDGE_HOST` and `TELEGRAM_BRIDGE_SSH_KEY` via `gh secret set` with values from Terraform state. |
| **`build-web-platform.yml`** | Keep for now; file separate issue to retire/repurpose. |
| **Shared semver label tradeoff** | One `semver:*` label applies the same bump to all components in a PR. Known tradeoff: a PR fixing a web bug (patch) and adding a plugin skill (minor) bumps both by minor. Acceptable pre-1.0; revisit with per-component labels post-1.0. |
| **Permissions** | Reusable workflow requires `permissions: contents: write, packages: write` for `gh release create` and Docker push to GHCR. |
| **Discord truncation** | Truncate release body to 1900 chars (Discord's 2000-char limit minus formatting). Carry over from existing plugin workflow. |
| **Discord per-component** | Separate notifications. Format: "Soleur Web Platform v0.1.0 released!" |

### Implementation Phases

#### Phase 1: Prerequisites and Cleanup

Tasks:

- [ ] **1.1** Normalize GHCR org in telegram-bridge: update `apps/telegram-bridge/scripts/deploy.sh` and `apps/telegram-bridge/infra/variables.tf` to use `ghcr.io/jikig-ai/soleur-telegram-bridge` (lowercase)
- [ ] **1.2** Fix `docker restart` bug in `apps/telegram-bridge/scripts/deploy.sh:16` — replace `docker restart soleur-bridge` with `{ docker stop soleur-bridge || true; } && { docker rm soleur-bridge || true; } && docker run -d --name soleur-bridge ...`
- [ ] **1.3** Create repository secrets via `gh secret set`:

  ```bash
  gh secret set TELEGRAM_BRIDGE_HOST --body "$(terraform -chdir=apps/telegram-bridge/infra output -raw server_ip)"
  gh secret set TELEGRAM_BRIDGE_SSH_KEY < ~/.ssh/telegram_bridge_key  # or appropriate key path
  ```

**Deferred to separate issues:**

- GitHub labels `app:web-platform` / `app:telegram-bridge` — created in Phase 4 alongside `/ship` changes (not a blocker for release workflows)
- Telegram-bridge Docker build test in CI — file as separate issue (out of scope for #739)

#### Phase 2: Reusable Release Workflow

- [ ] **2.1** Create `.github/workflows/reusable-release.yml` with the inputs defined above
- [ ] **2.2** Implement the release job with these steps:

```
Permissions: contents: write, packages: write

Steps in reusable-release.yml:

1. Checkout (fetch-depth: 2)
2. Fetch all tags:
   - git fetch --tags
   (fetch-depth: 2 only has tags on last 2 commits; we need all tags for version computation)
3. Path change detection:
   - git diff --name-only HEAD~1 -- ${{ inputs.path_filter }}
   - Skip if empty AND force_run is false
4. Secure temp files (mktemp for pr_body, release_notes, etc.)
5. Find merged PR:
   - gh api repos/{owner}/{repo}/commits/{sha}/pulls
   - Fallback: parse (#N) from commit title
6. Determine bump type:
   - If inputs.bump_type is non-empty (workflow_dispatch): use it directly
   - Else: read PR labels for semver:major > semver:minor > semver:patch
   - Default: patch
7. Get latest version (CRITICAL — semver-sorted):
   - git tag --list '${{ inputs.tag_prefix }}*' --sort=-version:refname | head -1
   - Strip prefix, split on '.', increment per bump type
   - Fallback: 0.0.0 when no tags exist
8. Idempotency check:
   - gh release view "$TAG" && skip
9. Extract changelog:
   - awk between '## Changelog' and next '##' from PR body
   - Fallback: PR title
10. Create GitHub Release:
    - gh release create "$TAG" --title "$TAG" --notes-file "$RELEASE_NOTES"
11. Docker build + push (conditional on docker_image != ""):
    - docker/login-action to GHCR
    - docker/build-push-action with tags: $IMAGE:v$VERSION, $IMAGE:$SHA, $IMAGE:latest
    - build-args from docker_build_args input
12. Discord notification:
    - "$COMPONENT_DISPLAY v$VERSION released!"
    - Webhook to DISCORD_RELEASES_WEBHOOK_URL
    - Truncate body to 1900 chars
```

- [ ] **2.3** Pin all GitHub Actions to commit SHAs with version comments
- [ ] **2.4** Sanitize all `$GITHUB_OUTPUT` writes with `printf` + `tr -d '\n\r'`
- [ ] **2.5** Set outputs: `version`, `tag`, `released`
- [ ] **2.6** Set concurrency: `group: release-${{ inputs.component }}`, `cancel-in-progress: false`

#### Phase 3: Caller Workflows

- [ ] **3.1** Create `.github/workflows/web-platform-release.yml`:

```yaml
# Caller structure:
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      bump_type:
        type: choice
        options: [patch, minor, major]
      skip_deploy:
        type: boolean
        default: false

jobs:
  release:
    uses: ./.github/workflows/reusable-release.yml
    with:
      component: web-platform
      component_display: "Soleur Web Platform"
      path_filter: "apps/web-platform/"
      tag_prefix: "web-v"
      docker_image: "ghcr.io/jikig-ai/soleur-web-platform"
      docker_context: "apps/web-platform"
      docker_build_args: |
        NEXT_PUBLIC_SUPABASE_URL=${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}
        NEXT_PUBLIC_SUPABASE_ANON_KEY=${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}
      bump_type: ${{ inputs.bump_type || '' }}
      force_run: ${{ github.event_name == 'workflow_dispatch' }}
    secrets: inherit

  deploy:
    needs: release
    if: needs.release.outputs.released == 'true' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
    runs-on: ubuntu-latest
    steps:
      - uses: appleboy/ssh-action@<sha>  # v1.x
        with:
          host: ${{ secrets.WEB_PLATFORM_HOST }}
          username: root
          key: ${{ secrets.WEB_PLATFORM_SSH_KEY }}
          script: |
            IMAGE="ghcr.io/jikig-ai/soleur-web-platform"
            TAG="v${{ needs.release.outputs.version }}"
            docker pull "$IMAGE:$TAG"
            { docker stop soleur-web-platform || true; }
            { docker rm soleur-web-platform || true; }
            docker run -d --name soleur-web-platform \
              --restart unless-stopped \
              --env-file /mnt/data/.env \
              -v /mnt/data/workspaces:/workspaces \
              -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
              -p 0.0.0.0:80:3000 -p 0.0.0.0:3000:3000 \
              "$IMAGE:$TAG"
            # Health check
            for i in $(seq 1 10); do
              if curl -sf http://localhost:3000/health; then exit 0; fi
              sleep 3
            done
            docker logs --tail 30 soleur-web-platform
            exit 1
```

- [ ] **3.2** Create `.github/workflows/telegram-bridge-release.yml`:

```yaml
# Same structure as web, with workflow_dispatch:
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      bump_type:
        type: choice
        options: [patch, minor, major]

jobs:
  release:
    uses: ./.github/workflows/reusable-release.yml
    with:
      component: telegram-bridge
      component_display: "Soleur Telegram Bridge"
      path_filter: "apps/telegram-bridge/"
      tag_prefix: "telegram-v"
      docker_image: "ghcr.io/jikig-ai/soleur-telegram-bridge"
      docker_context: "apps/telegram-bridge"
      bump_type: ${{ inputs.bump_type || '' }}
      force_run: ${{ github.event_name == 'workflow_dispatch' }}
    secrets: inherit

  deploy:
    needs: release
    if: needs.release.outputs.released == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: appleboy/ssh-action@<sha>
        with:
          host: ${{ secrets.TELEGRAM_BRIDGE_HOST }}
          username: root
          key: ${{ secrets.TELEGRAM_BRIDGE_SSH_KEY }}
          script: |
            IMAGE="ghcr.io/jikig-ai/soleur-telegram-bridge"
            TAG="v${{ needs.release.outputs.version }}"
            docker pull "$IMAGE:$TAG"
            { docker stop soleur-bridge || true; }
            { docker rm soleur-bridge || true; }
            docker run -d --name soleur-bridge \
              --restart unless-stopped \
              --env-file /mnt/data/.env \
              -v /mnt/data:/home/soleur/data \
              -p 127.0.0.1:8080:8080 \
              "$IMAGE:$TAG"
            for i in $(seq 1 10); do
              if curl -sf http://localhost:8080/health; then exit 0; fi
              sleep 3
            done
            docker logs --tail 30 soleur-bridge
            exit 1
```

**Deferred:** Refactoring `version-bump-and-release.yml` to use the reusable workflow is deferred to a follow-up PR. The existing 282-line plugin workflow continues to work unchanged, reducing blast radius. Once the reusable workflow proves stable through several app releases, it can be extracted as a caller.

#### Phase 4: `/ship` Skill Updates

- [ ] **4.0** Create GitHub labels (prerequisite for `/ship`): `gh label create "app:web-platform" --color "6f42c1" --description "PR touches web-platform app"` and `gh label create "app:telegram-bridge" --color "6f42c1" --description "PR touches telegram-bridge app"`
- [ ] **4.1** Update `plugins/soleur/skills/ship/SKILL.md` Phase 6 ("Semver Label and Changelog"):
  - After the existing plugin diff analysis, add app path detection:

    ```
    # Check for app changes
    git diff --name-only $MERGE_BASE...HEAD -- apps/web-platform/ | head -1
    git diff --name-only $MERGE_BASE...HEAD -- apps/telegram-bridge/ | head -1
    ```

  - Apply `app:web-platform` label if web paths changed
  - Apply `app:telegram-bridge` label if telegram paths changed
  - Keep existing `semver:*` logic — analyze ALL changed component dirs for the highest bump level
  - When ONLY app files changed (no plugin files), still apply `semver:*` based on app change significance:
    - New files added → `semver:minor`
    - Changes only → `semver:patch`

- [ ] **4.2** Update the `/ship` Changelog section to include app changes in the generated changelog body

#### Phase 5: Seed Releases and Verification

- [ ] **5.1** Create seed releases manually to establish the starting version for each app:

  ```bash
  gh release create "web-v0.1.0" --title "web-v0.1.0" --notes "Initial release tracking for Soleur Web Platform"
  gh release create "telegram-v0.1.0" --title "telegram-v0.1.0" --notes "Initial release tracking for Soleur Telegram Bridge"
  ```

  This sets the baseline so the first automated bump computes from v0.1.0.

- [ ] **5.2** After merging, trigger each workflow manually via `workflow_dispatch` and verify:

  ```bash
  gh workflow run web-platform-release.yml -f bump_type=patch -f skip_deploy=true
  gh workflow run telegram-bridge-release.yml -f bump_type=patch
  ```

  Poll with `gh run view <id> --json status,conclusion` until complete. Verify releases `web-v0.1.1` and `telegram-v0.1.1` are created.

- [ ] **5.3** Verify Docker images on GHCR have all 3 tags: `v0.1.1`, `<sha>`, `latest`

- [ ] **5.4** Verify Discord notifications posted correctly

## Acceptance Criteria

- [ ] PRs touching `apps/web-platform/` trigger a `web-vX.Y.Z` release when merged to main
- [ ] PRs touching `apps/telegram-bridge/` trigger a `telegram-vX.Y.Z` release when merged to main
- [ ] Docker images tagged with version `:v0.1.0`, SHA, and `:latest`
- [ ] Each app has independent version history in GitHub Releases
- [ ] `/ship` detects which app was modified and applies `app:web-platform` / `app:telegram-bridge` labels
- [ ] Monorepo PRs touching multiple components produce separate releases for each
- [ ] The existing plugin release workflow is not modified (deferred to follow-up PR)
- [ ] GHCR org name normalized to `jikig-ai` for telegram-bridge
- [ ] Telegram bridge deploy uses stop/rm/run (not restart)
- [ ] Health checks run post-deploy for both apps

## Test Scenarios

- Given a PR touching only `apps/web-platform/`, when merged, then only `web-vX.Y.Z` release is created (plugin and telegram skip)
- Given a PR touching `plugins/soleur/` AND `apps/web-platform/`, when merged, then both `vX.Y.Z` and `web-vX.Y.Z` releases are created independently
- Given no prior `web-v*` tags exist, when the first web-platform PR merges, then `web-v0.1.1` is created (bumps from seed `web-v0.1.0`)
- Given a PR with no `semver:*` label, when merged, then default `patch` bump is used
- Given `workflow_dispatch` with `bump_type=minor`, when triggered, then path check is skipped and minor bump is applied
- Given the deploy health check fails, when the workflow exits, then the workflow step fails with exit 1 and Docker logs are printed
- Given a PR touching only `docs/` or `.github/ci.yml`, when merged, then no releases are created (all 3 workflows skip)

## Dependencies & Prerequisites

| Dependency | Status | Blocker? |
|-----------|--------|----------|
| `TELEGRAM_BRIDGE_HOST` secret | Phase 1 (`gh secret set`) | Yes (for deploy only) |
| `TELEGRAM_BRIDGE_SSH_KEY` secret | Phase 1 (`gh secret set`) | Yes (for deploy only) |
| `NEXT_PUBLIC_SUPABASE_URL` secret | Already exists | No |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` secret | Already exists | No |
| `WEB_PLATFORM_HOST` secret | Already exists | No |
| `WEB_PLATFORM_SSH_KEY` secret | Already exists | No |
| `DISCORD_RELEASES_WEBHOOK_URL` secret | Already exists | No |
| `app:web-platform` label | Phase 4 (before `/ship` update) | No (release workflows don't use labels) |
| `app:telegram-bridge` label | Phase 4 (before `/ship` update) | No (release workflows don't use labels) |

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Semver sort fails on edge cases | Low | Medium | `git tag --sort=-version:refname` is well-tested. `git fetch --tags` ensures all tags available. `|| echo "0.0.0"` fallback. |
| `secrets: inherit` exposes all secrets | Low (solo repo) | Low | Acceptable for single-maintainer. Revisit if adding contributors. |
| First telegram-bridge CI build fails | Medium | Low | Test with `workflow_dispatch` first. Docker build has never run in CI — verify Dockerfile builds cleanly. |
| Deploy health check fails on first automated deploy | Medium | Medium | Use `skip_deploy=true` on first `workflow_dispatch` test. Verify manually first. |

## Future Considerations

- **Rollback automation:** Version-tagged Docker images enable `docker run $IMAGE:v0.1.0` for rollback. A `/rollback` skill could automate this.
- **`build-web-platform.yml` cleanup:** File a separate issue to retire or repurpose for PR preview builds.
- **Per-component semver labels:** If version inflation becomes a problem post-1.0, add `web-semver:*` / `telegram-semver:*` label namespaces.
- **Deploy notifications:** Add deploy-specific Discord notifications (distinct from release notifications) with server/health status.

## References

### Internal

- `.github/workflows/version-bump-and-release.yml` — existing plugin release workflow (unchanged in this PR; refactor deferred)
- `.github/workflows/build-web-platform.yml` — existing web Docker build (feature-branch only)
- `apps/telegram-bridge/scripts/deploy.sh:16` — `docker restart` bug
- `apps/telegram-bridge/infra/variables.tf:33` — mixed-case GHCR org
- `plugins/soleur/skills/ship/SKILL.md:283-317` — semver label detection logic
- `knowledge-base/project/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md` — tag-only versioning architecture
- `knowledge-base/project/learnings/integration-issues/github-actions-auto-release-permissions.md` — GITHUB_TOKEN cascade limitation
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — `{ ...; }` grouping for `|| true`
- `knowledge-base/project/learnings/2026-02-27-github-actions-sha-pinning-workflow.md` — SHA pinning requirement

### Learnings Applied

- **Tag-only versioning:** No committed version files. `git fetch --tags` + `git tag --sort=-version:refname` for semver-correct latest lookup (shallow clones miss older tags).
- **GITHUB_TOKEN releases don't cascade:** All steps in one workflow invocation.
- **Pin actions to SHAs:** Security hook blocks first edit — expect retry.
- **Sanitize `$GITHUB_OUTPUT`:** `printf` + `tr -d '\n\r'`.
- **Bash `{ ...; }` grouping:** Prevent `|| true` from masking earlier failures in SSH command chains.
- **`gh api commits/{sha}/pulls`:** Authoritative PR extraction, not commit message parsing.
