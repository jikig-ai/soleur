<!-- iac-routing-ack: plan-phase-2-8-reviewed (lockfile-only change; introduces no infrastructure) -->
# Tasks — undici + js-yaml Dependabot lockfile bumps (8 alerts)

Plan: `knowledge-base/project/plans/2026-07-18-fix-dependabot-undici-jsyaml-lockfile-bumps-plan.md`
Lane: single-domain • Threshold: none • Labels: `type/security` + `dependencies`

> **Golden constraint:** regenerate every `package-lock.json` with **npm@11**
> (`npx --yes npm@11 …`), never local npm — the CI `lockfile-sync` gate pins
> npm@11 and diffs. NO `package.json` edits (patched versions already satisfy
> existing ranges).

## Phase 1 — Bump package-lock.json (npm@11)

- [x] 1.1 `cd apps/web-platform && npx --yes npm@11 update undici js-yaml` (undici 7.24.6→7.28.0; nested gray-matter js-yaml 3.14.2→3.15.0; top-level js-yaml 4.2.0→4.3.0 safe)
- [x] 1.2 From repo root: `npx --yes npm@11 update js-yaml` (nested gray-matter js-yaml 3.14.2→3.15.0; top-level 4.2.0→4.3.0 safe)
- [x] 1.3 `git status --short` shows only `*package-lock.json` (and later `*bun.lock`) changed — NO `package.json`

## Phase 2 — Regenerate bun.lock for parity (SURGICAL edit, NOT `bun update`)

> **Plan deviation (corrected inline):** the plan prescribed `bun update undici js-yaml`,
> but the work skill's [work-lockfile-bumps.md](../../../../plugins/soleur/skills/work/references/work-lockfile-bumps.md)
> bans `bun update <pkg>` for transitive-only bumps (it elevates the target to a direct
> `package.json` dep — verified: it added `js-yaml ^5.2.1` + `undici ^8.7.0`, overshooting
> to majors). Reverted and used the sanctioned surgical `bun.lock` edit (version + integrity
> sha per entry), validated with `bun install --frozen-lockfile`.

- [x] 2.1 Preflight: patched versions past `bunfig.toml minimumReleaseAge` (published 2026-07-02/04 → OK)
- [x] 2.2 Surgical edit `apps/web-platform/bun.lock`: js-yaml 3.14.2→3.15.0, undici 7.24.6→7.28.0, @eslint/eslintrc/js-yaml 4.2.0→4.3.0 (parity)
- [x] 2.3 Surgical edit root `bun.lock`: gray-matter/js-yaml 3.14.2→3.15.0, top-level js-yaml 4.2.0→4.3.0 (parity)
- [x] 2.4 Parity: resolved undici/js-yaml versions in each `bun.lock` == sibling `package-lock.json` (3.15.0 / 7.28.0 / 4.3.0); no `js-yaml@3.14.2` / `undici@7.24.6` remains; `bun install --frozen-lockfile` OK both dirs

## Phase 3 — Restore prod-fidelity install & verify tests

- [x] 3.1 `cd apps/web-platform && npx --yes npm@11 install` (restore npm node_modules; root package-lock `name` field restored to origin/main value after worktree drift)
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → EXIT 0
- [x] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run` → 1022 files / 12228 tests passed
- [x] 3.4 `bash scripts/test-all.sh` → EXIT 0, 191/191 suites passed

## Phase 4 — Verify GHSA resolution & alert auto-dismiss (deterministic)

- [x] 4.1 no-vulnerable-version assertion against BOTH `package-lock.json` → both print `OK`
- [x] 4.2 Each resolved version ≥ Dependabot `first_patched_version` (undici 7.28.0 ≥ 7.28.0; js-yaml 3.15.0 ≥ 3.15.0)
- [x] 4.3 lockfile-sync idempotency: `npx --yes npm@11 install --package-lock-only` did NOT modify committed lockfile (sha256 identical) → CI gate passes
- [x] 4.4 baseline `gh api …dependabot/alerts?state=open` → 8 pre-merge undici/js-yaml alerts confirmed

## Phase 5 — Ship ONE security PR

- [ ] 5.1 Commit all four lockfiles: `package-lock.json`, `apps/web-platform/package-lock.json`, `bun.lock`, `apps/web-platform/bun.lock`
- [ ] 5.2 `gh label list` confirms `type/security` + `dependencies` exist (both verified present)
- [ ] 5.3 Open ONE PR with both labels; PR body maps 8 GHSAs → patched versions; note #6604/#6588/#6490/#6487 deliberately excluded; use `Ref` not `Closes` for any alert-tracking (alerts auto-dismiss post-merge, not at merge)

## Phase 6 — Post-merge (automatic Dependabot rescan)

- [ ] 6.1 After merge, Dependabot rescans the default branch and auto-dismisses all 8 alerts (#115–#123). Verify `gh api …dependabot/alerts?state=open` → 0 undici/js-yaml alerts (allow one rescan cycle). This is automatic — Dependabot dismisses on its own once the vulnerable versions leave the default-branch graph.
