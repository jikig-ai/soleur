<!-- iac-routing-ack: plan-phase-2-8-reviewed (lockfile-only change; introduces no infrastructure) -->
# Tasks — undici + js-yaml Dependabot lockfile bumps (8 alerts)

Plan: `knowledge-base/project/plans/2026-07-18-fix-dependabot-undici-jsyaml-lockfile-bumps-plan.md`
Lane: single-domain • Threshold: none • Labels: `type/security` + `dependencies`

> **Golden constraint:** regenerate every `package-lock.json` with **npm@11**
> (`npx --yes npm@11 …`), never local npm — the CI `lockfile-sync` gate pins
> npm@11 and diffs. NO `package.json` edits (patched versions already satisfy
> existing ranges).

## Phase 1 — Bump package-lock.json (npm@11)

- [ ] 1.1 `cd apps/web-platform && npx --yes npm@11 update undici js-yaml` (undici 7.24.6→7.28.0; nested gray-matter js-yaml 3.14.2→3.15.0; top-level js-yaml 4.2.0→4.3.0 safe)
- [ ] 1.2 From repo root: `npx --yes npm@11 update js-yaml` (nested gray-matter js-yaml 3.14.2→3.15.0; top-level 4.2.0→4.3.0 safe)
- [ ] 1.3 `git status --short` shows only `*package-lock.json` (and later `*bun.lock`) changed — NO `package.json`

## Phase 2 — Regenerate bun.lock for parity

- [ ] 2.1 Preflight: confirm patched versions are past `bunfig.toml minimumReleaseAge` (published 2026-07-02/04 → OK); if bun rejects, do NOT `--force`
- [ ] 2.2 `cd apps/web-platform && bun update undici js-yaml`
- [ ] 2.3 From repo root: `bun update js-yaml`
- [ ] 2.4 Parity: resolved undici/js-yaml versions in each `bun.lock` == sibling `package-lock.json`; no `js-yaml@3.14.2` / `undici@7.24.6` remains

## Phase 3 — Restore prod-fidelity install & verify tests

- [ ] 3.1 `cd apps/web-platform && npx --yes npm@11 install` (restore npm node_modules; expect no further lockfile diff)
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w` — root has no `workspaces`)
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` (runner is vitest; bun test blocked by bunfig)
- [ ] 3.4 `bash scripts/test-all.sh` (root suite)

## Phase 4 — Verify GHSA resolution & alert auto-dismiss (deterministic)

- [ ] 4.1 Run the no-vulnerable-version assertion (plan §Research Insights `node -e` script) against BOTH `package-lock.json` → both print `OK`
- [ ] 4.2 Confirm each resolved version ≥ Dependabot `first_patched_version` (undici 7.28.0; js-yaml 3.15.0)
- [ ] 4.3 lockfile-sync idempotency: `cd apps/web-platform && npx --yes npm@11 install --package-lock-only && git diff --exit-code apps/web-platform/package-lock.json` → clean
- [ ] 4.4 `gh api "repos/:owner/:repo/dependabot/alerts?state=open" --jq '[.[]|select(.dependency.package.name=="undici" or .dependency.package.name=="js-yaml")]|length'` → 8 pre-merge (baseline)

## Phase 5 — Ship ONE security PR

- [ ] 5.1 Commit all four lockfiles: `package-lock.json`, `apps/web-platform/package-lock.json`, `bun.lock`, `apps/web-platform/bun.lock`
- [ ] 5.2 `gh label list` confirms `type/security` + `dependencies` exist (both verified present)
- [ ] 5.3 Open ONE PR with both labels; PR body maps 8 GHSAs → patched versions; note #6604/#6588/#6490/#6487 deliberately excluded; use `Ref` not `Closes` for any alert-tracking (alerts auto-dismiss post-merge, not at merge)

## Phase 6 — Post-merge (automatic Dependabot rescan)

- [ ] 6.1 After merge, Dependabot rescans the default branch and auto-dismisses all 8 alerts (#115–#123). Verify `gh api …dependabot/alerts?state=open` → 0 undici/js-yaml alerts (allow one rescan cycle). This is automatic — Dependabot dismisses on its own once the vulnerable versions leave the default-branch graph.
