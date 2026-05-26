# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-22-fix-ci-lockfile-sync-npm-version-pin-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause confirmed via local reproduction: committed `apps/web-platform/package-lock.json` is in npm 11.x shape (no `"dev": true` on optional transitive entries); CI's `actions/setup-node@v4.4.0` ships npm 10.9.x with Node 22, which adds `"dev": true` on regeneration. Diff is purely 17 added flag lines; not a version/integrity/optional-platform drift.
- Fix shape: pin npm to `npm@11` major-only inside the `lockfile-sync` job via `npm install -g npm@11` (verified live that `actions/setup-node@v4.4.0` has no `npm-version` input, so this is the only available pin mechanism). Choose npm 11 over npm 10 because committed lockfile is already npm 11 shape (no lockfile regeneration needed; zero-diff verification under npm 11 confirmed locally).
- Rejected `npm ci --dry-run` substitution: does not catch the `bun add`-updates-package.json-but-not-lockfile defect class that the original 2026-04-03 gate exists to catch. Kept the regenerate-and-diff form; fixed the npm-version skew underneath.
- Docker side untouched: `node:22-slim` ships npm 10.9.4 and `web-platform-build` job (`npm ci`) is green on every failing run — `npm ci` tolerates the `"dev": true` flag difference, only the regenerate-and-diff strict check trips. Fix is one-sided.
- Two-recurrence framing: explicitly identifies this as the second instance (PR #4014 patched it with operator-side `npx npm@10`; PR #4334 re-introduced it without codifying the pin in the gate). Plan codifies the durable fix in the workflow itself and updates the 2026-04-03 learning to invalidate its "no version skew concerns" claim.
- Threshold = `none` with non-sensitive-path scope-out justification; no CPO sign-off required; no GDPR/IaC gate (skipped silently — pure workflow YAML + lockfile regeneration; no schema/auth/API surface; no new infra).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
