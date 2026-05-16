---
title: "fix(deps): bump Next.js to 15.5.18 to close 13 open Dependabot alerts"
date: 2026-05-16
type: fix
classification: security-hygiene
issue: dependabot-alerts-next-2026-05-16
branch: feat-one-shot-bump-next-15-5-18-dependabot
worktree: .worktrees/feat-one-shot-bump-next-15-5-18-dependabot
detail_level: MINIMAL
lane: single-domain
requires_cpo_signoff: false
---

# fix(deps): bump Next.js to 15.5.18 to close 13 open Dependabot alerts

## Overview

Close all **13 open Dependabot alerts** on `main` whose package is `next` by raising `apps/web-platform`'s pin from `^15.5.15` to `^15.5.18` and regenerating both lockfiles (`bun.lock` + `package-lock.json`). Co-bump `eslint-config-next` (`^15.5.14` → `^15.5.18`) to keep the Next.js lint config aligned with the runtime.

Per live `gh api repos/jikig-ai/soleur/dependabot/alerts` (2026-05-16), the 13 open alerts split:

- **7 high / 4 medium / 2 low** (severity counts match the issue body)
- **12 alerts patched in 15.5.16**, **1 alert (#78, GHSA-26hh-7cqf-hhc6 — "Middleware/Proxy bypass via segment-prefetch routes — incomplete fix follow-up")** patched in **15.5.18**

`15.5.18` is therefore the minimum 15.5.x version that closes EVERY open alert. The 15.5 line currently ranges 15.5.0 → 15.5.18 (15.5.17 was skipped — does not exist on npm). Latest `next` overall is 16.2.6, but the upgrade scope is "minimum to clear all alerts; stay on 15.x; avoid 16.x major" per the issue.

This is a **lockfile + caret-pin bump** (no source code changes, no config changes). Dependency tree diff between `next@15.5.15` and `next@15.5.18` is one line: `@next/env: 15.5.15 → 15.5.18`. Peer-dependency contract is unchanged (`react ^18.2.0 || ^19.0.0`, `react-dom ^18.2.0 || ^19.0.0`, `@playwright/test ^1.51.1`) and all currently-installed peers satisfy 15.5.18 unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** a failed `next build` or `next start` blocks the next production deployment of `app.soleur.ai`. Detection is immediate (`bun run build` + `bun run typecheck` + `npm ci` in CI), so blast radius is the open PR, not production. A worst-case rollback is a single revert commit.

**If this leaks, the user's workflow/data is exposed via:** the 13 underlying advisories are ALREADY leaking on `main` until this PR merges — middleware bypass (SSRF + cache-poisoning + auth-rule evasion), Image Optimization DoS, Server Component DoS via Cache Components, SSR XSS via CSP nonces / beforeInteractive scripts, cache poisoning in RSC responses. Anyone targeting `app.soleur.ai` could, in principle, chain these to bypass middleware-enforced auth (Soleur uses middleware for tenant routing) or exhaust the image optimizer. The realistic exposure today is **bounded** (no observed exploit), but every day on the unpatched chain accumulates risk.

**Brand-survival threshold:** none

Rationale: this PR shrinks the security blast radius. It does not change any user-facing behavior, schema, auth flow, or persistence path. Sensitive paths (`apps/web-platform/server/`, `apps/web-platform/lib/`, `supabase/migrations/`) are not modified. Patch-bump semver guarantees no breaking API change on the 15.5 line.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality (live verified 2026-05-16) | Plan response |
| --- | --- | --- |
| Current pin: `"next": "^15.3.0"` | Pin is `"next": "^15.5.15"`; lockfile resolves to `next@15.5.15` (per `apps/web-platform/bun.lock` line 1 of next entry) | Treat the current pin as `^15.5.15`. The bump is `^15.5.15` → `^15.5.18` (3 patch versions), not `^15.3.0` → `^15.5.18` (a much larger range). Smaller delta = lower risk; no plan change needed beyond pin edit. |
| Use `pnpm install` to verify resolution | App uses **bun** (`bun.lock`, `bunfig.toml`) for dev/CI **and** **npm** (`package-lock.json`) for Docker `RUN npm ci`. No `pnpm-workspace.yaml`, no `pnpm-lock.yaml`. | Use `bun install` (CI test path) AND `npm install --package-lock-only` (Docker path). Both lockfiles must be regenerated. The dedicated `lockfile-sync` CI job (`.github/workflows/ci.yml:124`) will FAIL the PR if `package-lock.json` is not regen'd; bun's `--frozen-lockfile` in CI fails if `bun.lock` is stale. |
| "patched in 15.5.18 on the 15.x line" (all 13) | **12 of 13 patched in 15.5.16; only #78 patched in 15.5.18**. Two-step verification: `gh api ... .security_vulnerability.first_patched_version.identifier | sort | uniq -c` → `12 15.5.16, 1 15.5.18`. | Target remains 15.5.18 (the minimum that clears ALL 13). Plan body and AC1 explicitly note "12 closed by 15.5.16, 1 closed only by 15.5.18" so the reviewer can verify the version choice. |
| 13 vulnerabilities | Live count: 13 open alerts where `dependency.package.name == "next"`. | Confirmed. AC1 asserts post-merge re-scan closes ALL 13 (using `gh api` to count `state == "fixed"` or `state == "dismissed"` not `state == "open"`). |
| Stay on 15.x; avoid 16.x major | `next@latest` is 16.2.6; `next@15` resolves to 15.5.18. | Target `^15.5.18` (caret-pin permits future 15.5.19/15.6.x patches but blocks 16.x). |

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grep'd for `apps/web-platform/package.json`, `apps/web-platform/bun.lock`, `apps/web-platform/package-lock.json`, `next.config.ts` — zero open scope-outs touch these files. The bump is uncontested terrain.

## Files to Edit

1. **`apps/web-platform/package.json`** — 2 lines:
   - `dependencies.next`: `"^15.5.15"` → `"^15.5.18"`
   - `devDependencies.eslint-config-next`: `"^15.5.14"` → `"^15.5.18"` (co-bump to align lint config with runtime; eslint-config-next@15.5.18 is published)
2. **`apps/web-platform/bun.lock`** — regenerated by `cd apps/web-platform && bun install`. Expect entries for `next@15.5.18`, `eslint-config-next@15.5.18`, `@next/eslint-plugin-next@15.5.18`, and `@next/env@15.5.18` to replace their 15.5.15 / 15.5.14 predecessors.
3. **`apps/web-platform/package-lock.json`** — regenerated by `cd apps/web-platform && npm install --package-lock-only`. Same four packages bump.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1: Version pins land at 15.5.18.** `jq -r '.dependencies.next, .devDependencies."eslint-config-next"' apps/web-platform/package.json` returns `^15.5.18` and `^15.5.18`.
- [ ] **AC2: Both lockfiles resolve next to 15.5.18.**
  - `grep '"next": \["next@' apps/web-platform/bun.lock` → contains `next@15.5.18` (and does NOT contain `next@15.5.15`).
  - `jq -r '.packages."node_modules/next".version' apps/web-platform/package-lock.json` → `15.5.18`.
- [ ] **AC3: `bun install --frozen-lockfile` succeeds.** Run from `apps/web-platform/`; exit code 0; no lockfile diff.
- [ ] **AC4: `npm ci` succeeds.** Run from `apps/web-platform/`; exit code 0. This mirrors the Dockerfile's deps + runner stages (`Dockerfile:5, Dockerfile:72`).
- [ ] **AC5: `bun run typecheck` succeeds.** From `apps/web-platform/` — `tsc --noEmit` exit code 0, zero new errors compared to `main`.
- [ ] **AC6: `bun run build` succeeds.** From `apps/web-platform/` — `next build` exit code 0. Sentry-instrumented build path included.
- [ ] **AC7: Web-platform test suite passes.** From `apps/web-platform/` — `bun run test:ci` (vitest) exit code 0; zero new failures compared to `main`.
- [ ] **AC8: CI `lockfile-sync` job passes.** Verifies `npm install --package-lock-only` produces no diff against the committed `package-lock.json` (per `.github/workflows/ci.yml:124-138`).
- [ ] **AC9: PR body references the issue with `Closes` keyword.** Per `wg-use-closes-n-in-pr-body-not-title-to`, the PR body (not title) contains `Closes #<alert-tracking-issue>` if an issue is filed, or — if no tracking issue exists — `Ref dependabot-alerts-next-2026-05-16` and a per-alert list of the 13 GHSA IDs.
- [ ] **AC10: PR is labeled.** `gh pr edit <N> --add-label dependencies --add-label domain/engineering --add-label priority/p1-high` (all three labels verified to exist via `gh label list`).

### Post-merge (operator-side, automated where possible)

- [ ] **AC11: All 13 open `next` Dependabot alerts close on the default-branch re-scan.** Verification command (run immediately after merge to `main` once Dependabot's post-merge scan completes — typically <10 minutes):

  ```bash
  gh api repos/jikig-ai/soleur/dependabot/alerts --paginate \
    -q '.[] | select(.state == "open" and .dependency.package.name == "next") | .number' | wc -l
  ```

  Expect: `0`. If non-zero after 30 minutes, investigate (most likely cause: a transitive next reference elsewhere in the monorepo — search `git ls-files | xargs grep -l "next@15"` for any missed lockfile).

- [ ] **AC12: Production health post-deploy.** The standard `/soleur:postmerge` skill verifies `app.soleur.ai` returns 200 on `/` and `/health` within 10 minutes of the post-merge deploy workflow. No additional steps needed beyond the normal ship lifecycle — this is a standard server-side library bump on a custom-server architecture (`server/index.ts` is the runtime entry; next is library, not runtime owner).

## Test Strategy

This is a library version bump on a `^` semver range. No new tests are required; the existing test surfaces are the verification gates:

- **Type contract** — `tsc --noEmit` (AC5) catches any `Next.js`-typed import that changed shape across 15.5.15 → 15.5.18. Diff inspection (npm view) shows zero type-impacting changes between these versions; this is a defense-in-depth check.
- **Build contract** — `next build` (AC6) exercises the App Router, custom-server bundling, Sentry instrumentation injection, and CSS pipeline. A failure here would surface SSR or compile-time regressions.
- **Lockfile contract** — `lockfile-sync` CI job + `bun install --frozen-lockfile` (AC8 + AC3) catch the dual-lockfile desync class (see `2026-04-03-lockfile-sync-ci-check-pattern.md`).
- **Test suite** — `bun run test:ci` (AC7) exercises route handlers, middleware, and component unit tests that import from `next/server`, `next/headers`, `next/navigation`. Any regression in next's runtime contract would surface here.
- **E2E (deferred to /qa skill, not gating AC):** `bun run test:e2e` runs the Playwright authenticated suite. If `/qa` triggers it (per the standard one-shot ship flow), this provides a third layer of confidence.

## Risks

1. **A peer-dependency contract changed silently between 15.5.15 and 15.5.18.** Live verification (`npm view next@15.5.18 peerDependencies`) shows the contract is byte-identical to 15.5.15. Mitigation: AC5 (typecheck) + AC6 (build) are the structural gates; a peer drift would surface as TS or build error.
2. **A consumer of an internal next type signature broke on the patch bump.** Internal-API drift on a patch release is exceedingly rare for Next.js (per their backport policy 15.5.16/15.5.18 are security-only). Mitigation: AC5 + AC7 catch this; the diff is `@next/env` version-string only.
3. **Lockfile desync between `bun.lock` and `package-lock.json`.** Bun's resolver and npm's Arborist can diverge on optional/peer deps; the dedicated `lockfile-sync` CI job (introduced after `2026-04-03-lockfile-sync-ci-check-pattern.md`) exists to catch this. Mitigation: run BOTH `bun install` AND `npm install --package-lock-only` in `apps/web-platform/`; commit both; AC8 verifies.
4. **Dependabot's post-merge re-scan races with the merge commit.** Dependabot typically rescans within 5-10 minutes of a default-branch push. Mitigation: AC11 polls the alert state; if any alert is still open after 30 min, run `gh workflow run dependency-review.yml` (or trigger a fresh push to main with an empty commit) to force a re-scan.
5. **The 15.5.17 gap is intentional, not a registry miss.** Confirmed via `npm view next@15.5.17 time` returning E404. Vercel skipped 15.5.17 internally; 15.5.16 → 15.5.18 is a legitimate consecutive bump on the release line.

## Sharp Edges

- **NEVER bump version files in this feature branch's PR.** Per `wg-never-bump-version-files-in-feature`: do NOT edit `plugin.json`, `marketplace.json`, or any release metadata. This PR touches ONLY `apps/web-platform/package.json` (the app's own package, not a release sentinel), `apps/web-platform/bun.lock`, and `apps/web-platform/package-lock.json`.
- **Before pushing `package.json` changes, both lockfiles MUST be regenerated** per `cq-before-pushing-package-json-changes`. The dual-lockfile pattern (bun for dev/CI, npm for Docker) means a single-lockfile bump silently breaks the OTHER install path. The /work skill MUST run both `bun install` AND `npm install --package-lock-only` in `apps/web-platform/` before `git add`.
- **Use `Closes #<N>` in the PR body, not the PR title** per `wg-use-closes-n-in-pr-body-not-title-to`. If a tracking issue is created for this batch, reference it in the body; otherwise list the GHSA IDs.
- **Ship-push gate** (`wg-ship-push-before-merge`): every local commit MUST be on `origin/<branch>` before `gh pr merge`. This is a hook-enforced rule; the /work skill will fail-closed if commits are unpushed.
- **The `## User-Brand Impact` section threshold is `none`.** Verify this aligns with the diff: it does — no regulated-data surface, no auth flow change, no schema. Preflight Check 6 will pass without a sign-off bullet.
- **GDPR gate is correctly skipped.** Per `hr-gdpr-gate-on-regulated-data-surfaces`: the diff touches `package.json` + 2 lockfiles — no migrations, no auth flow, no `.sql`, no LLM/external-API on operator-session-derived data, no new artifact distribution surface. None of (a)/(b)/(c)/(d) extended triggers fire. Skip is justified.
- **The post-merge alert-closure check (AC11) must use the live `gh api` paginated query, NOT a stale `gh security` cached view.** Dependabot's UI can lag the API by minutes; the API is authoritative.

## Domain Review

**Domains relevant:** none (engineering-only library bump; no product, marketing, legal, finance, operations, sales, support implications).

No cross-domain implications detected — security-hygiene patch on an existing dependency caret-pin. Engineering domain leader implicit (the engineer running this plan); no specialist agents required.

## Implementation Phases

### Phase 0 — Preconditions

- Confirm we're on the feature branch in the correct worktree: `git rev-parse --show-toplevel` must end in `.worktrees/feat-one-shot-bump-next-15-5-18-dependabot`.
- Confirm `node --version` ≥ 20.16 (per `package.json:engines`) and `bun --version` is the project's pinned major (whatever current CI uses).
- Snapshot the open-alerts list for the AC11 baseline:
  `gh api repos/jikig-ai/soleur/dependabot/alerts --paginate -q '.[] | select(.state == "open" and .dependency.package.name == "next") | .number' | sort > /tmp/pre-bump-open-alerts.txt`.

### Phase 1 — Bump

1. Edit `apps/web-platform/package.json`:
   - Set `dependencies.next` to `"^15.5.18"`.
   - Set `devDependencies."eslint-config-next"` to `"^15.5.18"`.
2. From `apps/web-platform/`:
   - `bun install` → regenerates `bun.lock`. Expect entries for `next@15.5.18`, `eslint-config-next@15.5.18`, `@next/eslint-plugin-next@15.5.18`, `@next/env@15.5.18`.
   - `npm install --package-lock-only` → regenerates `package-lock.json` without writing `node_modules` (mirrors the `lockfile-sync` CI job's check command exactly).

### Phase 2 — Local verification gates

From `apps/web-platform/`:

1. `bun install --frozen-lockfile` → AC3.
2. `npm ci` → AC4 (mirrors Dockerfile path).
3. `bun run typecheck` → AC5.
4. `bun run build` → AC6.
5. `bun run test:ci` → AC7.

If any gate fails, do NOT proceed to commit. Investigate; the most likely failure is a transitive lockfile mismatch (re-run `bun install` + `npm install --package-lock-only` in clean order) or a test that imported from a `next` private path that moved (extremely unlikely on a patch bump, but possible).

### Phase 3 — Commit, push, PR

1. `git add apps/web-platform/package.json apps/web-platform/bun.lock apps/web-platform/package-lock.json`.
2. `git commit -m "fix(deps): bump next to 15.5.18 to close 13 dependabot alerts"` (compound skill per `wg-before-every-commit-run-compound-skill`).
3. `git push -u origin feat-one-shot-bump-next-15-5-18-dependabot`.
4. Open PR; body includes:
   - One-line summary.
   - The 13 GHSA IDs (numbered list from the Phase 0 snapshot).
   - "Closes the 13 open `next` Dependabot alerts."
   - Note that 12 are patched in 15.5.16 and 1 (GHSA-26hh-7cqf-hhc6) is patched only in 15.5.18 — justifying the version choice.
5. Apply labels: `dependencies`, `domain/engineering`, `priority/p1-high` (AC10).

### Phase 4 — Review, QA, ship

Standard one-shot flow:

- `/soleur:review` — multi-agent code review; expected findings are minimal for a single-pin bump.
- `/soleur:qa` — runs the full functional QA including Playwright e2e where applicable.
- `/soleur:ship` — applies the `chore` semver label (patch bump on a dependency does not warrant minor/major release semantics for `apps/web-platform`), pushes, then `gh pr merge <N> --squash --auto` per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

### Phase 5 — Post-merge verification

1. Wait for the default-branch CI run to complete.
2. Wait up to 10 min for Dependabot's post-merge scan (it fires automatically on default-branch push).
3. Run AC11's query; assert count = 0.
4. If non-zero after 30 min, force a re-scan: `gh workflow run dependency-review.yml --ref main` or push an empty commit (`git commit --allow-empty -m "chore: trigger dependabot re-scan" && git push`).
5. `/soleur:postmerge` for production health check.

## Implementation Pseudocode (for /work)

```bash
# Phase 0: baseline
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-bump-next-15-5-18-dependabot
gh api repos/jikig-ai/soleur/dependabot/alerts --paginate \
  -q '.[] | select(.state == "open" and .dependency.package.name == "next") | .number' \
  | sort > /tmp/pre-bump-open-alerts.txt
wc -l /tmp/pre-bump-open-alerts.txt  # expect: 13

# Phase 1: bump
cd apps/web-platform
# Edit package.json: next → ^15.5.18, eslint-config-next → ^15.5.18
bun install
npm install --package-lock-only

# Phase 2: verify
bun install --frozen-lockfile  # AC3
npm ci                          # AC4
bun run typecheck               # AC5
bun run build                   # AC6
bun run test:ci                 # AC7

# Phase 3: commit
cd ../..
git add apps/web-platform/package.json apps/web-platform/bun.lock apps/web-platform/package-lock.json
# /compound first (wg-before-every-commit-run-compound-skill)
git commit -m "fix(deps): bump next to 15.5.18 to close 13 dependabot alerts"
git push -u origin feat-one-shot-bump-next-15-5-18-dependabot
gh pr create --label dependencies --label domain/engineering --label priority/p1-high \
  --title "fix(deps): bump next to 15.5.18 to close 13 Dependabot alerts" \
  --body "$(cat <<'EOF'
Bumps `next` from 15.5.15 → 15.5.18 and `eslint-config-next` from 15.5.14 → 15.5.18 in
`apps/web-platform`. Regenerates both `bun.lock` and `package-lock.json` per
`cq-before-pushing-package-json-changes`.

12 of the 13 advisories below are patched in 15.5.16; advisory #78 (GHSA-26hh-7cqf-hhc6 —
"Middleware/Proxy bypass via segment-prefetch routes — incomplete fix follow-up") is
patched only in 15.5.18, making 15.5.18 the minimum 15.5.x version that closes ALL 13.

Closes the following Dependabot alerts (verified open at PR time):

<list of 13 GHSA IDs from Phase 0 snapshot>

Ref: dependabot-alerts-next-2026-05-16
EOF
)"
```

## Why Not Higher Versions?

- **15.6.x** — does not exist on the 15.x line as of 2026-05-16 (`npm view next@15` resolves to 15.5.18). The next release after 15.5.18 jumps to 16.x.
- **16.x** — explicitly out of scope per the issue ("stay on 15.x; avoid 16.x major"). 16.0 introduces breaking changes that would warrant their own scoped upgrade plan (App Router behavior changes, middleware contract changes, deprecation removals). Doing this in a security-hygiene PR would conflate concerns.

## Why Not Lower (15.5.16)?

15.5.16 closes 12 of 13 alerts; advisory #78 (GHSA-26hh-7cqf-hhc6) requires 15.5.18. Targeting 15.5.16 would leave 1 high-severity alert open — failing the issue's "close all 13" success criterion.
