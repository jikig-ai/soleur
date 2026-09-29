# Tasks — feat-one-shot-dependabot-alerts

Derived from `knowledge-base/project/plans/2026-09-29-fix-dependabot-fast-uri-ip-address-alerts-plan.md`.

## Phase 1 — Bump `apps/web-platform/package-lock.json` (npm@11)

- [ ] 1.1 `cd apps/web-platform && npx --yes npm@11 update fast-uri ip-address`
- [ ] 1.2 Verify resolved versions: `node_modules/fast-uri` = `3.1.8` (≥3.1.7), `node_modules/ip-address` = `10.7.2` (≥10.5.1) in `apps/web-platform/package-lock.json`
- [ ] 1.3 If `npm update` silently no-ops (peer-installed copies), apply the surgical 3-field entry edit (version/resolved/integrity) using the verified hashes in the plan's Phase 1 fallback, then validate with `npx --yes npm@11 ci --ignore-scripts`

## Phase 2 — Bump `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` (npm@11)

- [ ] 2.1 `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 update ip-address`
- [ ] 2.2 Verify `node_modules/ip-address` = `10.7.2` (≥10.5.1); `fast-uri` remains ≥3.1.7 (currently 3.1.8)

## Phase 3 — Verify (prod-fidelity install + tests)

- [ ] 3.1 `cd apps/web-platform && npx --yes npm@11 ci --ignore-scripts`
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/vitest run`
- [ ] 3.4 `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 ci --ignore-scripts`
- [ ] 3.5 `bash scripts/test-all.sh`
- [ ] 3.6 Confirm no `package.json` modified: `git status --short -- '**/package.json'` → empty

## Phase 4 — Assert resolution + lockfile-sync idempotency

- [ ] 4.1 Run the plan's assert-floors node script against both lockfiles → both print `OK`
- [ ] 4.2 `npx --yes npm@11 install --package-lock-only` in each touched dir → `git diff --exit-code` clean
- [ ] 4.3 Map each resolved version ≥ Dependabot `first_patched_version` (fast-uri 3.1.8 ≥ 3.1.7; ip-address 10.7.2 ≥ 10.5.1)

## Phase 5 — Ship ONE security PR

- [ ] 5.1 Commit only the two lockfiles (planning artifacts committed separately by pipeline)
- [ ] 5.2 Open PR with labels `type/security` + `dependencies`; body maps all 9 alert numbers → GHSAs → resolved versions; states `Supersedes #9191` / `Supersedes #9192`; names #8065 and #8857 as excluded
- [ ] 5.3 Post-merge: after one Dependabot rescan, confirm `gh api repos/:owner/:repo/dependabot/alerts?state=open` returns 0 fast-uri/ip-address alerts; close #9191/#9192 with a `Superseded by` comment if still open
