# Lockfile Bumps — Surgical Pattern for `bun.lock` Transitive Updates

When a Dependabot security alert (or equivalent) calls for a transitive-only
bump in a directory that carries dual lockfiles (`package-lock.json` AND
`bun.lock`), npm's `npm update <pkg>` cleanly produces a transitive-only diff.
**bun has no equivalent clean transitive-only mode** — every bun command
either elevates the target to a direct `package.json` dep, re-resolves the
transitive back to its old version, or bumps every direct caret-ranged dep at
once. The first-attempt path is a surgical edit of `bun.lock`.

## When This Applies

- Diff is intended to touch ONLY `bun.lock` (no `package.json` changes).
- Target package is a transitive dep, not declared in `package.json`.
- Goal is a security/version bump within an existing semver range.

## Surgical Pattern

1. Locate the lockfile entry:

   ```bash
   grep -n '"<pkg>":' apps/web-platform/bun.lock
   ```

2. Replace the version string AND the integrity sha on that line:

   ```diff
   -    "<pkg>": ["<pkg>@OLD", "", {}, "sha512-OLDSHA..."],
   +    "<pkg>": ["<pkg>@NEW", "", {}, "sha512-NEWSHA..."],
   ```

3. Get the new sha. Two options (verified bun 1.3.11):

   - **`bun install --lockfile-only`** in a throwaway branch — regenerates
     `bun.lock` without installing dependencies. Copy the target line, revert
     the throwaway branch, apply surgically on the real branch.
   - **`npm view <pkg>@<version>`** — the integrity algorithm is the same
     across registries.

4. Validate the surgical edit:

   ```bash
   cd apps/web-platform && bun install --frozen-lockfile
   ```

   `--frozen-lockfile` refuses to install if the lockfile hash diverges from
   the resolved tree AND validates the integrity sha against the registry
   tarball during install. A passing run is positive evidence the edit is
   consistent.

5. Pre-commit gate — verify no unintended `package.json` drift:

   ```bash
   git diff --stat origin/main -- '*/package.json'
   ```

   Output MUST be empty. If `package.json` shows up, you accidentally invoked
   the wrong bun command — revert and retry the surgical pattern.

## Ban List (do NOT use for transitive-only bumps)

```bash
# DO NOT: elevates the transitive to a direct dep in package.json
bun update <pkg>

# DO NOT: bumps every direct caret-ranged dep (13+ packages, 300+ line churn)
bun update
```

## Related

- AGENTS.md `cq-before-pushing-package-json-changes` triggers on
  `package.json` changes only; transitive-only bumps don't fire it.
- Source learning:
  `knowledge-base/project/learnings/2026-05-09-bun-lockfile-transitive-bump-requires-surgical-edit.md`
- Precedent: PR #3488 (Dependabot dual-lockfile bump, 2026-05-09).
