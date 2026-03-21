# Learning: Cloud-init chown ordering: recursive before specific

## Problem

When setting up directory ownership in cloud-init `runcmd`, a recursive `chown -R deploy:deploy /mnt/data` placed after a specific `chown 1001:1001 /mnt/data/workspaces` silently overrides the specific ownership. The container running as UID 1001 then cannot write to its volume mount, but the error only surfaces at runtime — cloud-init exits 0.

## Solution

Apply ownership in **broadest-to-narrowest** order: recursive sweeps first, then targeted overrides.

### Wrong order

```yaml
runcmd:
  - chown 1001:1001 /mnt/data/workspaces   # specific first
  - chown -R deploy:deploy /mnt/data         # recursive wipes the line above
```

### Correct order

```yaml
runcmd:
  - chown -R deploy:deploy /mnt/data         # broad sweep first
  - chown 1001:1001 /mnt/data/workspaces     # specific override survives
```

## Key Insight

In any imperative permission setup (cloud-init, shell scripts, Dockerfiles), apply ownership in broadest-to-narrowest order. The most specific rule wins by being applied last. This is easy to miss because:

- Cloud-init runs commands sequentially; the ordering looks cosmetic
- Recursive chown exits 0 regardless — no warning that it overwrote deliberate permissions
- The failure surfaces much later at runtime, not during provisioning

Also applies: cloud-init creates all files as root. Any non-root user that needs write access to cloud-init-created files requires explicit `chown` transfer. Always add `chmod 600` to files containing secrets (`.env` with API keys).

## Session Errors

1. `git pull origin main` failed in bare repo root — used `git fetch` + `git worktree add` instead
2. Initial implementation had wrong chown ordering — caught by architecture-strategist review agent
3. Missing `.env` file ownership for deploy user — caught by review
4. Branch not synced with origin/main — would have silently reverted SSH host fingerprint verification from PR #824

## Tags

category: integration-issues
module: infrastructure
