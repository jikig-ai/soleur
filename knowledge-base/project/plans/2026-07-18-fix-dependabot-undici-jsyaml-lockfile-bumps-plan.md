<!-- iac-routing-ack: plan-phase-2-8-reviewed (lockfile-only change; introduces no infrastructure) -->
---
title: "fix(security): remediate 8 Dependabot alerts — undici + js-yaml lockfile bumps"
date: 2026-07-18
type: fix
lane: single-domain
brand_survival_threshold: none
labels: [type/security, dependencies]
status: planned
---

# fix(security): Remediate 8 Dependabot alerts — undici + js-yaml lockfile bumps 🔒

## Overview

Eight open Dependabot alerts on `main` (numbers #115–#123, verified live via
`gh api repos/:owner/:repo/dependabot/alerts?state=open`) are all **transitive**
npm dependencies. Remediation is **lockfile-only** — every affected transitive
version is already reachable within the existing `package.json` ranges, so **no
direct `package.json` edit is required**. Deliver ONE security PR labeled
`type/security` + `dependencies`.

Two packages, resolved to their patched versions:

| Package | Affected node | Current | Patched (Dependabot `first_patched_version`) | Manifest(s) |
|---|---|---|---|---|
| `undici` | `node_modules/undici` (via `jsdom`, a **devDependency**) | `7.24.6` | `7.28.0` | `apps/web-platform/package-lock.json` |
| `js-yaml` | `node_modules/gray-matter/node_modules/js-yaml` (the **3.x** node) | `3.14.2` | `3.15.0` | **both** `package-lock.json` (root) **and** `apps/web-platform/package-lock.json` |

The 8 alerts map as: 6× undici (2 HIGH `GHSA-hm92-r4w5-c3mj` / `GHSA-vmh5-mc38-953g`;
2 MODERATE `GHSA-pr7r-676h-xcf6` / `GHSA-p88m-4jfj-68fv`; 2 LOW
`GHSA-35p6-xmwp-9g52` / `GHSA-g8m3-5g58-fq7m`) + 2× js-yaml (MODERATE
`GHSA-h67p-54hq-rp68`, one per lockfile). All six undici alerts share the same
`first_patched_version` = **7.28.0**; both js-yaml alerts share
`first_patched_version` = **3.15.0**.

### Premise Validation (Phase 0.6)

All 8 alerts confirmed **OPEN** via the live Dependabot API (not stale). The
patched versions **exist on npm** (`npm view undici@7.28.0` → `7.28.0`;
`npm view js-yaml@3.15.0` → `3.15.0`). No cited GitHub issue/PR to re-validate
(this is a Dependabot-alert-driven task, not an issue-driven one). The four
unrelated open `type/security` issues (#6604, #6588, #6490, #6487 — LUKS, pg
`search_path`, Doppler DSN) are **explicitly out of scope** — they are
substantive engineering work, not lockfile bumps, and MUST NOT be bundled.

## Research Reconciliation — Spec vs. Codebase

| Task framing (spec claim) | Codebase reality (verified) | Plan response |
|---|---|---|
| "js-yaml in both lockfiles needs a patched version" | The flagged node is the **nested** `gray-matter/node_modules/js-yaml@3.14.2`, patched on the **3.x** line by **3.15.0**. The **top-level** `js-yaml@4.2.0` (via `@eslint/eslintrc ^4.1.1`) is **already safe** — `4.2.0` is not in the advisory's `< 3.15.0` range. | Bump the nested 3.x copy to `3.15.0` in both lockfiles. Leave the top-level 4.x node; if `npm update js-yaml` incidentally bumps it `4.2.0 → 4.3.0` (latest 4.x), that is acceptable (both ≥ patched, within `^4.1.1`). |
| "undici bump" (no runtime scope stated) | `undici` reaches web-platform **only via `jsdom`, which is a `devDependency`** (`^29.0.1`). Prod image builds with `npm ci --omit=dev` (Dockerfile L107), so undici is **not in the prod runtime bundle** — the vuln's prod blast radius is ~none; this is CI/test-env + Dependabot-hygiene remediation. | Bump to `7.28.0` (the **latest** 7.x; `jsdom ^7.24.5` keeps it on the 7.x line, no major bump). |
| "just lockfile bumps to patched versions" (npm only) | **`bun.lock` exists in BOTH root and `apps/web-platform`** and both pin the vulnerable `js-yaml@3.14.2` (+ web-platform pins `undici@7.24.6`). `AGENTS.rest.md` `cq-before-pushing-package-json-changes` requires regenerating **both** `bun.lock` and `package-lock.json` when both exist. `gray-matter` is a **prod** dependency (`^4.0.3`), so its nested `js-yaml` **is** in the prod bundle — the js-yaml DoS patch is the materially load-bearing one. | Regenerate `bun.lock` in both dirs for parity (Phase 2). Dependabot dismisses on `package-lock.json` (the only manifest it tracks for these alerts), but bun.lock parity is required by the AGENTS rule and closes the vuln in the bun-installed tree too. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing — the affected packages
are a test-only (`jsdom`→`undici`) and a build-time frontmatter-parser
(`gray-matter`→`js-yaml`) transitive; any resolution error, `tsc`, vitest, or
`test-all.sh` failure is caught **pre-merge by CI** and blocks the merge. No
user-facing route, page, or behavior changes.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this PR
*removes* vulnerabilities (js-yaml quadratic-complexity DoS in the prod
frontmatter parser; undici TLS-cert-bypass / cookie-injection in the test env).
It introduces no new data surface.

**Brand-survival threshold:** none.
`threshold: none, reason: transitive lockfile-only security patch; no runtime data surface and no user-facing behavior change; package-lock.json / bun.lock are not sensitive-path files per preflight Check 6, and the change is CI-gated (lockfile-sync + tests) pre-merge.`

## Implementation Phases

> **Golden constraint (read first):** every `package-lock.json` regeneration MUST
> use **npm@11** via `npx --yes npm@11 …` — **never local npm**. The CI
> `lockfile-sync` job (`.github/workflows/ci.yml`) pins `npm install -g npm@11`
> then runs `npm install --package-lock-only` in `apps/web-platform` and
> `git diff --exit-code`. A lockfile regenerated with a different npm major has a
> divergent shape and **fails the gate** (`cq-before-pushing-package-json-changes`).
> **No `package.json` edits** in any phase — the patched versions already satisfy
> the existing ranges.

### Phase 1 — Bump `package-lock.json` (both dirs, npm@11)

1. `apps/web-platform`: `cd apps/web-platform && npx --yes npm@11 update undici js-yaml`
   - Expected resolution: `undici 7.24.6 → 7.28.0`; nested `gray-matter/node_modules/js-yaml 3.14.2 → 3.15.0`; top-level `js-yaml 4.2.0 → 4.3.0` (safe, within `^4.1.1`).
2. repo root: `npx --yes npm@11 update js-yaml`
   - Expected resolution: nested `gray-matter/node_modules/js-yaml 3.14.2 → 3.15.0`; top-level `js-yaml 4.2.0 → 4.3.0` (safe). (No `undici` in the root lockfile — confirmed.)
3. Confirm no `package.json` was modified: `git status --short` shows only `package-lock.json` files (and later `bun.lock`) changed.

### Phase 2 — Regenerate `bun.lock` for parity (both dirs)

Preflight: the patched versions were published 2026-07-02/04 — well past the
`bunfig.toml` `minimumReleaseAge` 3-day floor, so `bun` will not reject them.
(If a bump ever trips the floor, `bun install` fails loudly — do not `--force`.)

1. `apps/web-platform`: `cd apps/web-platform && bun update undici js-yaml`
2. repo root: `bun update js-yaml`
3. **Parity check:** the resolved undici/js-yaml versions in each `bun.lock` MUST
   equal those in the sibling `package-lock.json` (both read the same
   `package.json` ranges → same latest-in-range resolution).

### Phase 3 — Restore prod-fidelity install & verify tests

`bun update` in Phase 2 leaves `node_modules` in bun's shape; restore the
npm/prod-fidelity tree before testing (prod uses `npm ci`).

1. `cd apps/web-platform && npx --yes npm@11 install` (reconciles `node_modules` to the committed `package-lock.json`; expect **no** further lockfile diff).
2. Typecheck (per the npm-workspaces Sharp Edge — the `-w` form fails, root has no `workspaces`): `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3. Web-platform tests (runner is **vitest**; bun test is blocked by `bunfig.toml`): `cd apps/web-platform && ./node_modules/.bin/vitest run` (or `npm run test:ci`).
4. Root tests: `bash scripts/test-all.sh` (root `package.json` `scripts.test`).

### Phase 4 — Verify GHSA resolution & alert auto-dismiss (deterministic, no dashboard)

1. **No vulnerable version remains** — assert against both lockfiles:
   - `undici`: every resolved `undici` entry in `apps/web-platform/package-lock.json` is `>= 7.28.0`.
   - `js-yaml`: **no** resolved `js-yaml` `< 3.15.0` in EITHER lockfile (i.e., no `3.14.x`); the 3.x nodes read `3.15.0`, the 4.x nodes read `>= 4.2.0`.
   - Command sketch: `node -e '…iterate lock.packages, assert semver floors…'` over each `package-lock.json` (and the same over `bun.lock` for parity).
2. **Map each patched version ≥ Dependabot `first_patched_version`:** undici `7.28.0 ≥ 7.28.0` (dismisses #115–#121); js-yaml `3.15.0 ≥ 3.15.0` and top-level `4.x` outside `< 3.15.0` (dismisses #122, #123). This is the requirement-5 "will auto-dismiss" gate — a pure lockfile-vs-patched comparison, no dashboard eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`).
3. **lockfile-sync idempotency** (mirror the CI gate exactly): `cd apps/web-platform && npx --yes npm@11 install --package-lock-only && git diff --exit-code apps/web-platform/package-lock.json` → clean.

### Phase 5 — Ship ONE security PR

- Commit all four lockfiles (`package-lock.json`, `apps/web-platform/package-lock.json`, `bun.lock`, `apps/web-platform/bun.lock`).
- Open ONE PR, labels **`type/security`** + **`dependencies`** (both verified to exist before `gh pr create --label`).
- PR body enumerates the 8 GHSAs → patched versions; note the four unrelated `type/security` issues (#6604/#6588/#6490/#6487) are **deliberately excluded**.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/package-lock.json`: resolved `undici` = `7.28.0` (or higher 7.x ≥ 7.28.0); no `undici < 7.28.0` node remains.
- [ ] Both `package-lock.json` files: **no** `js-yaml` node `< 3.15.0` (no `3.14.x`); nested 3.x node reads `3.15.0`.
- [ ] Both `bun.lock` files: resolved undici/js-yaml versions match their sibling `package-lock.json` (parity), and contain no `js-yaml@3.14.2` / `undici@7.24.6`.
- [ ] **No `package.json` file modified** (`git diff --name-only` lists only lockfiles + planning artifacts).
- [ ] lockfile-sync idempotency: `npx --yes npm@11 install --package-lock-only` in `apps/web-platform` produces **no** `git diff`.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` passes.
- [ ] `bash scripts/test-all.sh` passes.
- [ ] Every patched version ≥ its Dependabot `first_patched_version` (undici 7.28.0; js-yaml 3.15.0) — documented in PR body.
- [ ] PR carries **both** `type/security` and `dependencies` labels; the four unrelated security issues are NOT referenced with `Closes`.

### Post-merge (automatic)

- [ ] After merge to `main`, Dependabot's next default-branch rescan **auto-dismisses** all 8 alerts (#115–#123). Automation: this is automatic — Dependabot dismisses on its own once the vulnerable versions leave the default-branch dependency graph. Verify with `gh api repos/:owner/:repo/dependabot/alerts?state=open` returning 0 undici/js-yaml alerts (allow one rescan cycle).

## Observability

Skipped — Files-to-Edit are lockfiles only (`package-lock.json`, `bun.lock`); no
code-class file under `apps/*/server`, `apps/*/src`, `apps/*/infra`, or
`plugins/*/scripts`, and no new infrastructure surface. Per plan Phase 2.9 skip
condition (pure non-code change), no `## Observability` schema is required.

## Domain Review

**Domains relevant:** none

Mechanical security dependency-hygiene change (transitive lockfile bumps). No
UI surface (no `components/**`, `app/**/page.tsx`), no infra (Phase 2.8), no
regulated-data surface (Phase 2.7 GDPR — lockfiles are not schema/auth/API/.sql),
no architectural decision (Phase 2.10 ADR/C4 — a dependency bump does not mislead
a future engineer about the system). Product/UX Gate: NONE.

## Sharp Edges

- **npm@11 pin is load-bearing.** Regenerating any `package-lock.json` with local
  npm (10.x or other) diverges the lockfile shape and fails the CI `lockfile-sync`
  gate. Always `npx --yes npm@11 …`. See `cq-before-pushing-package-json-changes`
  and `knowledge-base/project/learnings/workflow-patterns/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md`.
- **The js-yaml target is the nested 3.x node, not the top-level 4.x.** The
  top-level `js-yaml@4.2.0` is already safe; only `gray-matter`'s nested
  `3.14.2` is vulnerable. Do not "upgrade js-yaml to 4.x" thinking the top-level
  is the problem — the fix is `3.14.2 → 3.15.0` (a backported 3.x security release).
- **`bun.lock` parity is easy to forget.** Both lockfile toolchains exist; the
  Dependabot alert only names `package-lock.json`, so a bun.lock left at
  `js-yaml@3.14.2` would silently keep the vuln in the bun-installed tree and
  drift from `cq-before-pushing-package-json-changes`. Regenerate both.
- **Typecheck/test commands:** `npm run -w apps/web-platform …` **fails** — root
  `package.json` has no `workspaces` field. Use `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` and `./node_modules/.bin/vitest run`. bun test
  is blocked by `bunfig.toml pathIgnorePatterns=["**"]`.
- **`gh pr create --label` fails on a nonexistent label.** Confirm `type/security`
  and `dependencies` both exist (`gh label list`) before creating the PR.
- **Do NOT bundle #6604/#6588/#6490/#6487** — separate substantive work, not
  lockfile bumps.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the
  threshold fails `deepen-plan` Phase 4.6 — this plan's section is complete
  (threshold `none` with reason bullet).

## Test Scenarios

1. **Resolution correctness:** after Phase 1, `undici` reads `7.28.0` and no
   `js-yaml < 3.15.0` remains in either `package-lock.json`.
2. **CI gate fidelity:** `npx --yes npm@11 install --package-lock-only` in
   `apps/web-platform` is idempotent (no diff) — proves the committed lockfile
   matches what CI regenerates.
3. **Prod-fidelity build:** `npx --yes npm@11 install` + `tsc --noEmit` + `vitest
   run` in `apps/web-platform` pass on the bumped tree (undici→jsdom test env;
   js-yaml→gray-matter frontmatter parsing).
4. **Root suite:** `bash scripts/test-all.sh` passes.
5. **Alert-dismiss precondition:** each resolved version ≥ Dependabot
   `first_patched_version`; post-merge rescan yields 0 open undici/js-yaml alerts.
