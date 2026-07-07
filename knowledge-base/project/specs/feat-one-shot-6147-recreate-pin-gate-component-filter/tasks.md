# Tasks — fix(infra): web-2-recreate pin-gate resolves from /health (#6147)

Derived from `knowledge-base/project/plans/2026-07-07-fix-web2-recreate-pin-gate-component-filter-plan.md`.
Lane: procedural. Brand-survival threshold: none.

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Confirm `app.soleur.ai` is still a single A record hard-pinned to web-1
      (`apps/web-platform/infra/dns.tf:13-20`); multi-host rewire (#5274) not yet landed. If it has
      landed, STOP — the resolver must target a web-1-pinned health path instead.
- [ ] 0.2 Confirm `/health` `.version` is a bare semver and public/no-CF-Access
      (`apply-deploy-pipeline-fix.yml:599-608`, `web-platform-release.yml:667`).
- [ ] 0.3 Confirm the release pipeline pushes strict `vX.Y.Z` (`reusable-release.yml:597,686`) so
      the strict `^v[0-9]+\.[0-9]+\.[0-9]+$` guard rejects no legitimate tag.
- [ ] 0.4 Confirm the `pin` step env (`apply-web-platform-infra.yml:1016-1022`) lacks `DOPPLER_TOKEN`
      and that the job authenticates doppler elsewhere (SENTRY_DSN check, coherence preflight).

## Phase 1 — Resolver script (TDD: test first)

- [ ] 1.1 Write `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` with fixture cases:
      (a) `1.2.3` → `v1.2.3`; (b) `""` → non-zero; (c) `dev` → non-zero; (d) `1.2.3-rc1` → non-zero.
      Follow the seam/convention of `deploy-status-fanout-verify.test.sh`. (RED)
- [ ] 1.2 Create `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — pure resolver:
      input = `/health` version string (arg/stdin), prepend `v`, validate
      `^v[0-9]+\.[0-9]+\.[0-9]+$`, print on stdout or exit non-zero with a diagnostic naming the
      rejected version + remediation. No network I/O. (GREEN)
- [ ] 1.3 `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` passes all cases.

## Phase 2 — Wire the workflow pin step

- [ ] 2.1 In `apply-web-platform-infra.yml` `pin` step: add `DOPPLER_TOKEN` to `env:`.
- [ ] 2.2 Resolve `APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE --plain 2>/dev/null || echo "soleur.ai")`.
- [ ] 2.3 Replace the deploy-status `.tag` retry loop with a bounded retry loop that curls
      `https://app.${APP_DOMAIN_BASE}/health` (NO CF-Access headers), extracts `.version`, and
      passes it to the resolver. Remove the `.component`/`exit_code`/`.tag` deploy-status logic from
      the pin path.
- [ ] 2.4 Add a callsite comment citing `dns.tf:13` (app→web-1 hard-pin) and naming **#5274
      (multi-host rewire) as the revisit trigger**.
- [ ] 2.5 Keep the downstream digest resolution + coherence preflight unchanged (`:1077-1089`).

## Phase 3 — CI registration & validation

- [ ] 3.1 Add an explicit `run: bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh`
      step to `.github/workflows/infra-validation.yml` (mirror `:205`).
- [ ] 3.2 `actionlint .github/workflows/apply-web-platform-infra.yml .github/workflows/infra-validation.yml`
      is clean. Validate embedded `run:` shell via `bash -c` extraction (NOT `bash -n` on the `.yml`).
- [ ] 3.3 *(optional)* Append a one-line reader-inventory bullet to ADR-079 noting the pin-gate now
      uses the #5955 `/health` source (`#6147`).

## Phase 4 — Ship

- [ ] 4.1 PR body: `Ref #6147` (NOT `Closes` — closure is post-merge after a green recreate).
      Surface `decision-challenges.md` (pure-/health vs component-filter) as an `action-required` item.
- [ ] 4.2 Post-merge (operator, automatable via `gh`): dispatch
      `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason="verify #6147"`;
      confirm the pin step resolves from `app/health` (no `got 'latest'` abort). Then
      `gh issue close 6147` and note on `#6090`.
