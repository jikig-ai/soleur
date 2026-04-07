# Tasks: fix Dependabot Vite Security Alerts

## Phase 1: Update Lockfiles

- [ ] 1.1 Run `npm update vite` in `apps/web-platform/` to update `package-lock.json` (scoped to vite only -- do NOT run bare `npm update`)
- [ ] 1.2 Verify vite resolves to `>= 7.3.2` in `package-lock.json`
- [ ] 1.3 Run `bun install` in `apps/web-platform/` to update `bun.lock`
- [ ] 1.4 Verify vite resolves to `>= 7.3.2` in `bun.lock`
- [ ] 1.5 Verify `git diff --stat` shows only vite-related lockfile changes (no unintended package updates)

## Phase 2: Verify

- [ ] 2.1 Run `npm ci` in `apps/web-platform/` to validate lockfile integrity
- [ ] 2.2 Run `npm run typecheck` in `apps/web-platform/`
- [ ] 2.3 Run `npm run test` in `apps/web-platform/` to confirm vitest works with updated vite

## Phase 3: Ship

- [ ] 3.1 Commit lockfile changes
- [ ] 3.2 Push and create PR
- [ ] 3.3 After merge, verify Dependabot alerts #26, #27, #28 auto-close
