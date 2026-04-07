# Learning: npm transitive dependency security update mechanics

## Problem

Three Dependabot alerts targeted vite (transitive dep of vitest) in `apps/web-platform`. Updating from 7.3.1 to 7.3.2 required navigating three lockfile update failures before finding the correct approach.

## Solution

Use npm `overrides` in package.json to force transitive dependency resolution:

```json
{
  "overrides": {
    "vite": "^7.3.2"
  }
}
```

Then `npm install` updates `package-lock.json` correctly. For `bun.lock`, temporarily set `minimumReleaseAge = 0` in `bunfig.toml` when the security patch is newer than the age threshold, then restore after install.

## Key Insight

`npm update <pkg>` does not reliably update transitive dependencies even when the new version satisfies the parent's semver constraint. `npm install <pkg>@<version> --no-save` installs to disk but skips lockfile updates. The `overrides` field is the canonical npm mechanism for forcing transitive dependency versions in lockfiles.

For dual-lockfile projects (npm + bun), bun's `minimumReleaseAge` supply-chain defense can block legitimate security patches published within the age window. The workaround is a temporary age override -- acceptable because the security advisory itself validates the package's legitimacy.

## Session Errors

1. **`npm update vite` silent no-op** -- `npm update vite` reported success but left vite at 7.3.1. No error, no warning. Prevention: For transitive dep updates, go directly to `overrides` instead of `npm update`.
2. **`--no-save` blocks lockfile writes** -- `npm install vite@7.3.2 --no-save` installed 7.3.2 on disk but left the lockfile at 7.3.1. The flag prevents ALL persistence, not just package.json. Prevention: Never use `--no-save` for lockfile security updates. Use `overrides` instead.
3. **bun `minimumReleaseAge` blocks recent security patches** -- vite 7.3.2 published ~24h before the session; bun's 3-day threshold rejected it. Prevention: When updating a package for a security advisory, check publish date vs `minimumReleaseAge`. If blocked, temporarily set to 0 and restore after install.

## Tags

category: build-errors
module: apps/web-platform
