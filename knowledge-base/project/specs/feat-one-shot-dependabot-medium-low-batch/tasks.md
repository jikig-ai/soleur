# Tasks — chore(deps): drain the open Dependabot medium/low npm batch in one PR

Plan: `knowledge-base/project/plans/2026-11-01-chore-batch-dependabot-medium-low-drain-plan.md`

## 0. Pre-flight verification

- [ ] 0.1 Re-run `gh api 'repos/jikig-ai/soleur/dependabot/alerts?state=open&per_page=100'`
      — confirm the open set still matches the plan's 15-row table; absorb or defer
      any new alert per severity and note in the PR body.
- [ ] 0.2 `cd apps/web-platform && npx vitest run test/cla-evidence/roster-entry-gate.test.ts`
      — verified green 23/23 at plan time; if RED at work time, fix in a DISTINCT
      commit on this branch before the batch commit (per the brief).

## 1. In-range transitive updates (npm@11)

- [ ] 1.1 `cd apps/web-platform && npx --yes npm@11 update hono @hono/node-server
      ip-address fast-uri vitest` — hono → ≥4.13.11, @hono/node-server → 2.1.x
      (MCP SDK range `^1.19.9 || ^2.0.5` admits), ip-address → ≥10.7.4,
      fast-uri → ≥3.1.9, vitest → 4.1.12 (pins @vitest/mocker 4.1.12 exactly).
- [ ] 1.2 `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 update
      @hono/node-server ip-address` — same MCP SDK chain → 2.1.x, 10.7.4+.

## 2. Overrides for no-patched-same-major packages

- [ ] 2.1 `apps/web-platform/package.json` `overrides` += `"rimraf": {"glob": "^14.0.2"}`,
      `"@sentry/bundler-plugins": {"glob": "^14.0.2"}`, `"minimatch": "^11.0.1"`
      (blanket — see decision-challenges row 1).
- [ ] 2.2 `package.json` (root) `overrides` += `"markdownlint-cli": {"minimatch": "^11.0.1"}`,
      `"@11ty/recursive-copy": {"minimatch": "^11.0.1"}`.
- [ ] 2.3 `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json`
      `overrides` += `"minimatch": "11.0.1"` (exact pin, undici precedent comment).

## 3. Lockfile regeneration + census verification

- [ ] 3.1 `npx --yes npm@11 install --package-lock-only` in each edited directory;
      then regenerate ALL FIVE lockfiles (lockfile-sync diffs all five).
- [ ] 3.2 Census (python over every `packages` key, unbounded — no top-level grep,
      no head-truncation): zero minimatch <11.0.1, zero glob in 9.0.0–14.0.1,
      no @hono/node-server on major 1, every ip-address ≥10.7.4, fast-uri ≥3.1.9,
      hono ≥4.13.11, @vitest/mocker ≥4.1.12.
- [ ] 3.3 Verify every lockfile `"name"` field byte-identical to `origin/main`
      (learning 2026-05-27).
- [ ] 3.4 `npm ci --ignore-scripts` in `apps/web-platform` — clean reproduce.

## 4. Drain-guard ratchet (scripts/assert-dependabot-drain.{py,test.sh})

- [ ] 4.1 `WATCHED_PACKAGES` += `minimatch`, `glob`, `@vitest/mocker`.
- [ ] 4.2 `REQUIRED`: retarget the two @hono/node-server major-1 rows to major 2
      floor `"2.1.3"`; raise hono→4.13.11, ip-address→10.7.4, fast-uri→3.1.9 on
      web-platform+pencil-setup and pen-cli @hono/node-server→2.1.3; add the five
      new rows (minimatch×3 @11.0.1, glob @14.0.2, @vitest/mocker @4.1.12).
- [ ] 4.3 `FLOOR_ANCHORS`: update hono:4→4.13.11, ip-address:10→10.7.4,
      fast-uri:3→3.1.9, @hono/node-server:2→2.1.3; DELETE ("@hono/node-server",1)
      with the evacuation comment; add minimatch:11:11.0.1, glob:14:14.0.2,
      @vitest/mocker:4:4.1.12 with GHSA comments.
- [ ] 4.4 `MIN_ROWS`/`MIN_RESOLVED` 36→41 (comment updated in style).
- [ ] 4.5 `.test.sh`: fixture mirrors (+minimatch11 on web/root/pencli, +glob14,
      +@vitest/mocker4 on web, @hono/node-server 1→2 on web/pen); floor specs
      36→41; anchor spec list update + six adds; mutate-arm substrings 36→41;
      MIN_ASSERTIONS ratcheted to the new arm count in the same commit.
- [ ] 4.6 `python3 scripts/assert-dependabot-drain.py` exit 0;
      `bash scripts/assert-dependabot-drain.test.sh` green.

## 5. Verification gates

- [ ] 5.1 `cd apps/web-platform && npm run lint` — green under the blanket
      minimatch@11 override (the @eslint/config-array/eslintrc compat canary).
- [ ] 5.2 `cd apps/web-platform && npx vitest run` — mocker-dependent shard +
      representative slice green; full test:ci is the outer net.
- [ ] 5.3 `cd apps/web-platform && npm run typecheck` + `npm run build` — green.
- [ ] 5.4 `bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh`
      — green under the minimatch@11.0.1 pin.
- [ ] 5.5 `bash scripts/lint-dual-lockfile.sh`, `scripts/verify-lockfile-guards.sh`,
      `scripts/lint-workflow-install-sites.sh` — all exit 0; no bun.lock (ADR-191).

## 6. Ship shape

- [ ] 6.1 PR body: #11646-shape table (bump/package/from→to/manifest/method) naming
      all 15 npm alerts; note #302 (Pillow) already `fixed` on main; note open
      Dependabot PR #11468 superseded; `## Changelog` section.
- [ ] 6.2 No `.ts`/`.tsx`/`next.config.ts`/`middleware.ts` changes in the diff
      (amend in-PR if the override-compat fallback forces a devDep graph change).
