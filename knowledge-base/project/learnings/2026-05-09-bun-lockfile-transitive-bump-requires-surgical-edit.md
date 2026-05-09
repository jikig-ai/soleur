---
date: 2026-05-09
category: best-practices
module: dependency-management
tags: [dependabot, bun, npm, lockfile, security-hygiene]
related-pr: 3488
related-issues: [dependabot-alerts-batch-2026-05]
---

# Learning: bun.lock transitive bumps require surgical lockfile edits when "no package.json edits" is required

## Problem

PR #3488 closed 18 Dependabot alerts including a `fast-uri` high-severity bump in `apps/web-platform/`. The repo carries dual lockfiles: `package-lock.json` (used by `npm ci` in the production Dockerfile) and `bun.lock` (used by CI test jobs and local dev). The plan declared "lockfile-only bump (no `package.json` edits)" because the patched versions are reachable within existing semver ranges and the security goal is monotonic.

`npm update fast-uri` (scoped, in `apps/web-platform/`) cleanly bumped `fast-uri@3.1.0 → 3.1.2` in `package-lock.json` with a 3-line diff. **bun's equivalent has no clean transitive-only mode**, and three different bun invocations produced wrong outcomes:

1. **`bun update fast-uri`** — bumped bun.lock to 3.1.2 BUT also added `"fast-uri": "^3.1.2"` to `package.json` as a direct dependency. bun has no `--no-save` mode for transitive bumps (its `--no-save` flag means "don't save package.json OR lockfile" — useless here).
2. **`git checkout package.json` + `bun install`** — bun, finding fast-uri no longer in package.json, re-resolved bun.lock back to fast-uri@3.1.0, undoing the bump.
3. **`bun update` (bare, no package name)** — bumped 13 direct caret-ranged dependencies in `package.json` (e.g. `@sentry/nextjs ^10.46.0 → ^10.51.0`, `@supabase/supabase-js ^2.49.0 → ^2.105.3`, `react ^19.1.0 → ^19.2.5`) and produced a 324-line bun.lock churn. Catastrophically out of scope for a security-hygiene PR.

The contradiction: bun cannot bump a transitive dep in its lockfile without either (a) adding it as a direct package.json dep, or (b) bumping every direct dep in caret-range simultaneously. Both violate "lockfile-only".

## Solution

**Surgical lockfile edit** is the only path that respects "no package.json edits" for bun transitive bumps:

1. Locate the lockfile entry: `grep -n '"<pkg>":' apps/web-platform/bun.lock`
2. Replace the version + integrity sha:
   ```diff
   -    "fast-uri": ["fast-uri@3.1.0", "", {}, "sha512-iPeeDKJSWf4..."],
   +    "fast-uri": ["fast-uri@3.1.2", "", {}, "sha512-rVjf7ArG3LTk+..."],
   ```
3. Get the new sha by running `bun update <pkg>` once in a throwaway state and copying the resulting `bun.lock` line — then revert package.json + every other diff so only the lockfile line remains. Or fetch from `npm view <pkg>@<version>` (the integrity is the same algorithm).
4. Validate the edit with `bun install --frozen-lockfile` — bun verifies the sha against the registry tarball and refuses to install if the hash doesn't match. A successful install with the new version in `node_modules/<pkg>/package.json` confirms the lockfile is valid.

This worked for PR #3488: `apps/web-platform/bun.lock` ended with a 1-line surgical bump to fast-uri@3.1.2 that passed `--frozen-lockfile`, while `package.json` stayed pristine.

## Key Insight

**The dual-lockfile rule `cq-before-pushing-package-json-changes` ("regenerate both lockfiles when both exist") is conditioned on package.json changes**, not security bumps. For pure transitive security patches, `npm update <pkg>` works on the npm side, but `bun update <pkg>` cannot match the same semantics — it always elevates the target to a direct dep. The hygiene workaround is surgical hand-editing of `bun.lock` validated by `bun install --frozen-lockfile`.

This means: every future Dependabot fix that touches a `bun.lock`-bearing app (currently `apps/web-platform/`) and wants to stay "lockfile-only" must use the surgical pattern. There is no clean bun command for it.

## Prevention

- **For npm transitive-only bumps:** `cd <app> && npm update <pkg>` (scoped). Works clean.
- **For bun transitive-only bumps in dual-lockfile dirs:** surgical edit of `bun.lock` + `bun install --frozen-lockfile` validation. NEVER run `bun update <pkg>` (adds to package.json) or `bun update` bare (bumps 13+ direct deps).
- **Pre-commit gate:** before committing a dep-bump PR, `git diff --stat origin/main -- '*/package.json'` MUST return empty. If a `package.json` shows up in a "lockfile-only" PR, you accidentally invoked the wrong bun command.
- **For Dependabot alert closure specifically:** verify which manifest paths Dependabot actually cites for the alert (via `gh api repos/<owner>/<repo>/dependabot/alerts`). For PR #3488, fast-uri alerts only cited `apps/web-platform/package-lock.json` — bun.lock was not a tracked manifest for this alert, so even skipping bun.lock would have closed the alert. The bun.lock parity is dev/CI hygiene, not alert closure.

## Session Errors

1. **Ran `bun update fast-uri`, expected lockfile-only diff, got `package.json` line addition.** Recovery: `git checkout package.json`. Prevention: use surgical lockfile edit for transitive-only bumps (this learning).
2. **Ran `bun install` after reverting package.json; bun re-locked fast-uri to 3.1.0.** Recovery: surgical edit of bun.lock with new sha. Prevention: bun `install` respects existing locks; transitive resolution only changes when the constraint or a parent forces it.
3. **Ran `bun update` (bare) hoping it would bump fast-uri transitively.** It bumped 13 direct deps and 324 lines of bun.lock. Recovery: `git checkout origin/main -- package.json bun.lock`, re-apply surgical fast-uri edit, validate with `bun install --frozen-lockfile`. Prevention: NEVER run bare `bun update` on a security-hygiene PR.
4. **Plan narrative claimed PR #1805 "superseded `.plugin/`"; actually #1805 migrated unrelated agents.** `.plugin/` was orphaned because parent issue #1779 closed "won't do for now". Caught by git-history-analyzer in review. Recovery: corrected plan + commit message in a follow-up `review:` commit. Prevention: when a plan cites a supersedure PR for a dir-deletion rationale, verify via `gh pr view <N> --json files` that the cited PR actually touched the directory.

## Related

- AGENTS.md `cq-before-pushing-package-json-changes` — dual-lockfile rule (note: triggers on package.json changes, not security-only transitive bumps; this learning clarifies the gap for bun)
- PR #1699 — vite Dependabot precedent. Used `bun update vite` which worked because vite IS a direct dep, sidestepping the bun-no-transitive-only problem this learning documents
- PR #3488 — this learning's source PR
