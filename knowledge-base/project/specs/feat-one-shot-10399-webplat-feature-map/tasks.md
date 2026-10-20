---
plan: knowledge-base/project/plans/2026-10-20-feat-web-platform-feature-map-plan.md
branch: feat-one-shot-10399-webplat-feature-map
issue: 10399
---

# Tasks — maintained feature map for web-platform

Derived from `2026-10-20-feat-web-platform-feature-map-plan.md` (MORE detail level). TDD order: battery RED → guard GREEN → map → wiring.

## Phase 1 — Guard battery (RED)

- [ ] 1.1 Create `scripts/lint-feature-map-coverage.test.sh`: scratch fixture repo via `mktemp -d` + `git init` + `trap … EXIT` cleanup (do NOT source `plugins/soleur/test/test-helpers.sh` — avoids the #8659 un-composed-trap class); root seam matching `SOLEUR_LINT_GATES_ROOT` convention.
- [ ] 1.2 Encode all 12 Guard-Contract matrix rows as battery cases (uncovered route, map missing, second unmapped member, renamed dir, reason-less exemption, zero-route producer, tombstone entry, stripped `expects:`, contradictory classification, de-headed entry, and the two must-PASS rows for route-group stripping and exempted-with-reason + `###` subsection non-counting).
- [ ] 1.3 Confirm battery runs RED (lint absent/stub).

## Phase 2 — The guard

- [ ] 2.1 Create `scripts/lint-feature-map-coverage.sh`: `#!/usr/bin/env bash`, `set -euo pipefail`, `export LC_ALL=C`, `MAP_FILE=apps/web-platform/test/feature-map.md` single constant at top, `REPO_ROOT` override seam; header docstring = WHY + ADVISORY level + companion-suite pointer (mirror `lint-integration-env-gates.sh` header contract).
- [ ] 2.2 Producer: `git ls-files 'apps/web-platform/app/**/page.tsx'`; derive route = strip `apps/web-platform/app/`, drop `/page.tsx`, remove `(...)` route-group segments, empty→`/`; no early-exit pipe consumers under pipefail.
- [ ] 2.3 Consumer parse: mapped set = `^##`+backtick-slash headings only; exempted set = `- \`/route\` — <reason>` bullets under `## Deliberately unmapped` (reason required); entry completeness = `selectors:` + `expects:` lines inside each mapped entry body.
- [ ] 2.4 Arms: coverage (route unmapped+unexempted → RED naming it), staleness (mapped/exempted route with no backing page.tsx → RED), completeness (missing field → RED), contradiction (route in both sets → RED), vacuity (map absent or producer=0 → RED). Fail-closed throughout; count-comparison grep forms (no bare `! grep -q` rc-2 folding).
- [ ] 2.5 Battery → GREEN; live run against this repo → RED (map not yet written; expected).

## Phase 3 — The map

- [ ] 3.1 Create `apps/web-platform/test/feature-map.md`: header (purpose, consumers, update contract "new/renamed route → update this file or Deliberately-unmapped in the same PR", link to `route-list.yaml` for auth/fixture detail).
- [ ] 3.2 One `## \`/route\`` entry per `app/(dashboard)/**` route (22) plus /, /login, /signup, /accept-terms; fields route/entry/selectors/expects/auth/gotchas — selectors from data-testid + role/text anchors per `e2e/nav-states-shell.e2e.ts:389-419` vocabulary; `/dashboard/admin/analytics` carries its admin-role gotcha.
- [ ] 3.3 `## Deliberately unmapped` bullets with reasons for `/setup-key`, `/connect-repo`, `/internal/github-app-init`, `/shared/[token]`, `/invite/[token]`.
- [ ] 3.4 `bash scripts/lint-feature-map-coverage.sh` → exit 0.

## Phase 4 — Wiring + citation

- [ ] 4.1 `.github/workflows/ci.yml`: add step `run: bash scripts/lint-feature-map-coverage.sh` to `lint-bot-statuses` with ADVISORY comment block + `if: ${{ !cancelled() }}`; job stays absent from `scripts/required-checks.txt`.
- [ ] 4.2 `scripts/test-all.sh`: add `run_suite "scripts/lint-feature-map-coverage-live" bash scripts/lint-feature-map-coverage.sh` and `run_suite "scripts/lint-feature-map-coverage-battery" bash scripts/lint-feature-map-coverage.test.sh` adjacent to the `lint-integration-env-gates` pair (~line 5456).
- [ ] 4.3 `plugins/soleur/skills/test-browser/SKILL.md`: paragraph inside `<file_to_route_mapping>` — map is the navigation source of truth when `apps/web-platform/test/feature-map.md` exists; generic table is the fallback (body-only edit, no `description:` change).
- [ ] 4.4 `apps/web-platform/test/README.md`: one-line index entry for `feature-map.md`.

## Phase 5 — Verify

- [ ] 5.1 `bash scripts/lint-feature-map-coverage.sh` exit 0 on committed tree.
- [ ] 5.2 `bash scripts/lint-orphan-test-suites.sh` green (battery registered).
- [ ] 5.3 `bash scripts/test-all.sh` — the two new suites pass.
- [ ] 5.4 `npx markdownlint-cli2` clean on `feature-map.md` + this `tasks.md` + the plan file.
