# Tasks — feat-one-shot-8065-dep-audit-advisories

Derived from `knowledge-base/project/plans/2026-09-29-chore-deps-resolve-root-js-yaml-and-liquidjs-audit-advisories-plan.md`.
Issue: #8065 · PR: #9223 · Branch: `feat-one-shot-8065-dep-audit-advisories`

**Golden constraint:** every `package-lock.json` write goes through
`npx --yes npm@11 …`. No `package.json` edits on the primary path.

## Phase 1 — Lockfile bump (root)

- [ ] 1.1 From the worktree root, run `npx --yes npm@11 update liquidjs`.
  Expected: `node_modules/liquidjs` `10.27.0 → 10.29.0` (floor `>= 10.27.2`,
  inside `@11ty/eleventy`'s `^10.25.0`). No other package's entries change;
  lockfile `"name"` stays `"soleur"`.
- [ ] 1.2 If `npm update` silently no-ops (resolved version still `< 10.27.2`),
  apply Fallback A: surgical 3-field edit of `node_modules/liquidjs` —
  `version: "10.29.0"`, `resolved:
  https://registry.npmjs.org/liquidjs/-/liquidjs-10.29.0.tgz`, `integrity:
  sha512-pCVOhs6FLAR8su3ItJ07diN26t6W5dHQRnmTMy8HPyTFuv1+oSCVJIGp5pGjfQyOZfh50KswvKtMTp6p4JEIdw==`
  — then `npx --yes npm@11 ci --ignore-scripts`.
- [ ] 1.3 Fallback B only if A cannot hold: add `"liquidjs": "^10.27.2"` to
  root `package.json` `overrides` + `npx --yes npm@11 install
  --package-lock-only`; record the temporary-override rationale in the PR
  body.

## Phase 2 — Drain-guard ratchet (`scripts/assert-dependabot-drain.py`)

- [ ] 2.1 `REQUIRED`: ratchet the four js-yaml rows — `("web-platform",
  "js-yaml", 3)` → `"3.15.2"`, `("web-platform", "js-yaml", 4)` → `"4.3.2"`,
  `("root", "js-yaml", 3)` → `"3.15.2"`, `("root", "js-yaml", 4)` →
  `"4.3.2"` — and add `("root", "liquidjs", 10, "10.27.2")`.
- [ ] 2.2 `WATCHED_PACKAGES`: add `"liquidjs"`.
- [ ] 2.3 `FLOOR_ANCHORS`: `("js-yaml", 3)` → `"3.15.2"`, `("js-yaml", 4)` →
  `"4.3.2"`, add `("liquidjs", 10): "10.27.2"`. (Anchors key per
  (package,major) across manifests — all four js-yaml rows must move
  together or the anchor check REDs the untouched sibling.)
- [ ] 2.4 Update the `MIN_ROWS`/`MIN_RESOLVED` comments so their row
  arithmetic reflects 21 rows; the floor VALUES stay `20` (lower bounds).

## Phase 3 — Drain-guard test (`scripts/assert-dependabot-drain.test.sh`)

- [ ] 3.1 `build_fixture`: add `("liquidjs", 10)` to the `rt` fixture package
  list so the new REQUIRED row resolves rather than printing `(absent)`.
- [ ] 3.2 Extend the FLOOR_ANCHORS source-grep `spec` list with
  `"js-yaml:3:3.15.2" "js-yaml:4:4.3.2" "liquidjs:10:10.27.2"`.

## Phase 4 — Verify

- [ ] 4.1 `npx --yes npm@11 ci --ignore-scripts` (integrity-validated install).
- [ ] 4.2 `npm audit --json` on root → `total: 0` (js-yaml absent because
  `4.3.2`/`3.15.2` are at GHSA-2883's patched versions; liquidjs absent
  because `>= 10.27.2`). Any residual → document the upstream constraint in
  the PR body per the issue AC.
- [ ] 4.3 `npm run docs:build` succeeds (exercises eleventy + liquidjs).
- [ ] 4.4 `python3 scripts/assert-dependabot-drain.py` → 21 rows, all OK.
- [ ] 4.5 `bash scripts/assert-dependabot-drain.test.sh` → all assertions pass.
- [ ] 4.6 Assert-floors `node -e` probe (plan §Research Insights) prints `OK`.
- [ ] 4.7 Idempotency, post-commit or before/after on the regenerated file:
  `npx --yes npm@11 install --package-lock-only` leaves `git diff` clean.
- [ ] 4.8 `git diff --quiet origin/main...HEAD -- '**/package.json'` and
  `git status --short -- '**/package.json'` — both empty (unless 1.3 fired).
- [ ] 4.9 Root checks: `bash scripts/test-all.sh` locally, or record that the
  required `test` CI context is the backstop (precedent: #9198 deferred the
  battery under machine contention — PR body records which ran).

## Phase 5 — Ship

- [ ] 5.1 Commit `package-lock.json` + both `scripts/assert-dependabot-drain.*`
  files together (conventional commit, e.g. `chore(deps): bump liquidjs
  10.27.0→10.29.0 + ratchet drain-guard floors for js-yaml/liquidjs`).
- [ ] 5.2 PR #9223 body: advisory table (GHSA → vulnerable range → patched →
  resolved), `Closes #8065`, explicit note that js-yaml was resolved by #7970
  and this PR carries the guard ratchet (no js-yaml lockfile diff exists).
  Labels: `type/security`, `type/chore`, `domain/engineering`,
  `dependencies`.
- [ ] 5.3 Mark ready → `gh pr merge --squash --auto` per
  `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Post-merge

- [ ] 6.1 On `main`: `npm ci --ignore-scripts && npm audit --json` → zero
  vulnerabilities; `python3 scripts/assert-dependabot-drain.py` green.
