# Tasks — chore(deps): batch critical and high Dependabot alerts into one PR

Plan: `knowledge-base/project/plans/2026-10-31-chore-batch-dependabot-critical-high-fixes-plan.md`

## 1. Direct pins + overrides (apps/web-platform)

- [ ] 1.1 In `apps/web-platform/package.json`: `"next": "~16.3.8"` → `"~16.4.1"`.
- [ ] 1.2 In `apps/web-platform/package.json`: `"@sentry/nextjs": "^10.59.0"` → `"^10.75.2"`.
- [ ] 1.3 In `apps/web-platform/package.json` `overrides` block, add scoped entries:
      `"inngest": { "zod": "^4.6.6" }` and `"@likec4/core": { "zod": "^4.6.6" }`.
      (Removes the two nested `zod@3.25.76` copies; see decision-challenges fork.)

## 2. Lockfile regeneration (npm@11 — `npx --yes npm@11`)

- [ ] 2.1 `cd apps/web-platform && npx --yes npm@11 install --package-lock-only`
      (resolves new pins + overrides).
- [ ] 2.2 `cd apps/web-platform && npx --yes npm@11 update body-parser --package-lock-only`
      — required: plain regen keeps `body-parser@2.3.0` (it satisfies express's
      `^2.2.1`). Verify resolved ≥2.4.0.
- [ ] 2.3 `cd spike && npx --yes npm@11 update zod` → verify ≥4.6.6.
- [ ] 2.4 `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 update zod`
      → verify ≥4.6.6.
- [ ] 2.5 Regenerate root + `plugins/soleur/skills/pencil-setup/scripts/pen-cli`
      lockfiles (`npm install --package-lock-only`) — the lockfile-sync gate diffs
      all five; revert if the diff is empty-noise only.
- [ ] 2.6 Verify every lockfile `"name"` field is byte-identical to `origin/main`
      (worktree name-drift guard; learning 2026-05-27).

## 3. Drain-guard ratchet

- [ ] 3.1 `scripts/assert-dependabot-drain.py`: add `next`, `@sentry/nextjs`,
      `body-parser`, `zod` to `WATCHED_PACKAGES`.
- [ ] 3.2 Add the nine `REQUIRED` rows (per plan Group 3 — includes the
      completeness-forced pen-cli/pencil-setup body-parser+zod rows).
- [ ] 3.3 Add the four `FLOOR_ANCHORS` with GHSA comments.
- [ ] 3.4 `MIN_ROWS` 27→36, `MIN_RESOLVED` 27→36 (update the counting comments).
- [ ] 3.5 `scripts/assert-dependabot-drain.test.sh`: extend anchor spec list
      (`next:16:16.4.1`, `@sentry/nextjs:10:10.75.2`, `body-parser:2:2.4.0`,
      `zod:4:4.6.6`) and floor specs `MIN_ROWS:36`, `MIN_RESOLVED:36`.
- [ ] 3.6 `python3 scripts/assert-dependabot-drain.py` exits 0;
      `bash scripts/assert-dependabot-drain.test.sh` green.

## 4. Verification

- [ ] 4.1 `cd apps/web-platform && npm ci --ignore-scripts` reproduces from the
      committed lockfile.
- [ ] 4.2 `npm run typecheck` green (validates `next.config.ts` against `NextConfig`).
- [ ] 4.3 `npm run build` (`next build`) green.
- [ ] 4.4 `npx vitest run` green for: `test/next-config-image-optimizer-scope.test.ts`,
      `test/c4-*.test.*` (likec4-on-zod-4 canary — a RED here escalates to the
      likec4-1.60 pin-train fallback per decision-challenges),
      `test/server/inngest/**` + `test/helpers/inngest-step-harness.test.ts`,
      `test/sentry-*.test.ts`.
- [ ] 4.5 `bash scripts/lint-dual-lockfile.sh` + `bash scripts/verify-lockfile-guards.sh`
      + `bash scripts/lint-workflow-install-sites.sh` all exit 0.
- [ ] 4.6 Full-lockfile census: zero `zod` <4.6.6 (no 3.x copy), every
      `body-parser` ≥2.4.0, `next` ≥16.4.1, `@sentry/nextjs` ≥10.75.2 across all
      five lockfiles.

## 5. Ship

- [ ] 5.1 PR body carries the #11646-shape bump table naming all eight alerts +
      a `## Changelog` section; note `Closes`-style references where applicable.
- [ ] 5.2 No `.ts`/`.tsx`/`next.config.ts`/`middleware.ts` edits in the diff
      (AC-12) — unless the likec4 fallback fired, in which case the pin-train
      file set is amended in.
- [ ] 5.3 If the zod override shipped (Option A), file follow-up issue
      `chore(deps): likec4 1.60 pin-train bump` referencing this PR.
