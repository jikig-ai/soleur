# Tasks — feat-one-shot-dependabot-adjacency

Plan: `knowledge-base/project/plans/2026-11-02-feat-dependabot-adjacency-follow-through-plan.md`

## Phase 1 — PR-1: likec4 1.60.0 pin-train bump (Closes #11696)

- [ ] 1.1 Re-verify live state on latest `origin/main` (main moves fast): pin sites still at 1.50.0; no concurrent likec4 PR; `npm view likec4@1.60.0 time --json` confirms publish 2026-10-15 → `--before=2026-10-16` (day-after-publish, ≥3 days old)
- [ ] 1.2 Bump `apps/web-platform/package.json`: `@likec4/core` + `@likec4/diagram` → `1.60.0`; delete `"@likec4/core": {"zod": "^4.6.6"}` override (KEEP the `inngest` scoped override — separate residual)
- [ ] 1.3 Bump install sites in the same commit: `apps/web-platform/Dockerfile:96`; `.github/workflows/ci.yml:1366,1586`; `.github/workflows/main-health-monitor.yml:199,380` — exact form `npm install -g likec4@1.60.0 --before=2026-10-16 --ignore-scripts`
- [ ] 1.4 Bump `plugins/soleur/scripts/render-c4-model.sh` `LIKEC4_VERSION`/`LIKEC4_BEFORE` + header comment; `plugins/soleur/lib/c4-from-components.ts` both consts + comments
- [ ] 1.5 Re-derive `LIKEC4_CONFIG_NAMES`/`LIKEC4_SOURCE_EXTENSIONS`/`LIKEC4_IGNORED_DIRS` in `apps/web-platform/server/c4-stage-sources.ts` against installed likec4@1.60.0 `dist/_chunks/{src,binary}.mjs`; update version comments (`c4-render.ts`, `.npmrc`, `c4-stage-sources.ts` headers)
- [ ] 1.6 `cd apps/web-platform && npm install --package-lock-only`; verify lockfile `name` field unchanged vs origin/main (worktree rewrite trap); `npm ci --ignore-scripts`
- [ ] 1.7 Regenerate `knowledge-base/engineering/architecture/diagrams/model.likec4.json` via `bash plugins/soleur/scripts/render-c4-model.sh`
- [ ] 1.8 Verify: `python3 scripts/assert-dependabot-drain.py` (0); `npx vitest run test/c4-likec4-version-pin.test.ts test/c4-config-name-parity.test.ts test/c4-stage-sources.test.ts test/c4-render-tenant-config.test.ts`; `bash plugins/soleur/test/c4-model-freshness.test.sh`; `npm audit --omit=dev` = 0
- [ ] 1.9 PR-1: `semver:patch` label; body `Closes #11696`; `git grep 'likec4@1\.50\.0'` residual-zero sweep (excluding fixture strings inside the pin test itself and knowledge-base)

## Phase 2 — PR-2: ad-hoc npm pin-table guard (Ref #11855)

- [ ] 2.1 Create `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts`: committed pin-table (site, package, pin|env-pin|carve-out, floor, justification) + census assertions in BOTH directions (site→row and row→site) + floor reconciliation + anti-vacuity site-count floor + FLOOR_ANCHORS-style cross-anchor constant
- [ ] 2.2 Implement the Guard-Contract mutation battery (rows 1–10 of the plan) as suite arms
- [ ] 2.3 Repin floating installs exact: `ci.yml:932` `npm@11`→`npm@11.21.1`; `npm-publish.yml:51` `npm@^11`→`npm@11.21.1`; `ci.yml:2486` + `deploy-docs.yml:174` `http-server@14`→`http-server@14.1.1`; `gdpr-gate-self-test.yml:104` `lefthook@2`→`lefthook@2.2.2` (re-derive latest-in-major at execution; ≥3 days old per `.npmrc`)
- [ ] 2.4 Table the divergent pair: `.mcp.json` + `plugins/soleur/.mcp.json` `@playwright/mcp@0.0.78` (dev-proxy, attestation-cited) and `cron-ux-audit.ts:343` + lockfile `0.0.75` (prod-cron, measurement-cited); NO pin value changes
- [ ] 2.5 Table manifest-only manifests: `packages/opencode-plugin` declared-range row (`yaml: ^2.8.3`, floor 2.8.3 / GHSA-48c2-rrv3-qjmp); `plugins/soleur/docs/package.json` + root `npx @11ty/eleventy` carve-out (resolves repo-root lockfile copy); `code-to-prd/test/fixture/package.json` carve-out (never installed); do NOT add a package-lock.json
- [ ] 2.6 Wiring: register the suite in `apps/web-platform/test/repo-wide-suites.ts` `REPO_WIDE_SUITES`; generalize `plugins/soleur/test/npm-publish-oidc.test.sh` `npm11-step` (literal `npm@^11` regex + m4/m11 variants) to accept exact `npm@11.x.y` ≥11.5.1 with the position rule intact; cross-reference lines in `assert-dependabot-drain.py` BOUNDARY + `lint-workflow-install-sites.sh` unreached-surfaces; dated ADR-191 addendum
- [ ] 2.7 Rebase on main after PR-1 merges (ci.yml disjoint regions)
- [ ] 2.8 PR-2: `semver:patch` label; body `Ref #11855` + disposition note; net-issue-flow check — this PR closes one scope-out and files one (item 4), net-zero

## Phase 3 — Issue bookkeeping (no PR)

- [ ] 3.1 Re-run `npm audit --omit=dev` against latest main lockfile; if 0 → close #10857 with the evidence comment (audit + fixed versions + drain-guard rows). If ANY entry resolves vulnerable → do NOT close; comment with the delta instead
- [ ] 3.2 Comment #11783: upstream issue #49587 still OPEN; v16.4.4 (2026-11-02) is LTS-backport without the fix; announced November security release is the next re-check; leave open
- [ ] 3.3 File `deferred-scope-out` tracking issue for #11855 item 4 (feed-reconcile spike, milestone `Post-MVP / Later`), then close #11855 citing items 1–3 landed + item 4 forwarded
- [ ] 3.4 Hono 2.x: confirm no open tracking issue (verified at plan time — re-check at execution; close it as resolved only if one exists)
