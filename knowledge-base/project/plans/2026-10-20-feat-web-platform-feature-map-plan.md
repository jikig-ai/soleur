---
title: "feat: maintained feature map for web-platform (Epic #10397 child 2)"
date: 2026-10-20
slug: feat-web-platform-feature-map
branch: feat-one-shot-10399-webplat-feature-map
issue: 10399
closes: 10399
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Ship a committed, user-POV feature map for `apps/web-platform` so the `test-browser`, `qa`, `ux-audit`, and `reproduce-bug` skills navigate the running app by feature (route -> selectors -> expected outcome -> gotchas) instead of ad-hoc file-to-route inference at runtime. The deliverable is one maintained markdown artifact covering the dashboard's primary routes, plus an advisory CI drift check that flags a newly added `app/**/page.tsx` lacking a map entry, plus a `test-browser` citation that makes the map the navigation source when present.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10399` → OPEN, `enhancement`/`type/feature`/`domain/engineering`/`priority/p3-low`; epic `gh issue view 10397` → OPEN. Premise is live, not stale.
- `git grep -il "feature map\|feature-map"` → zero hits outside this plan — the issue's "Evidence today" claim holds.
- `test-browser` `file_to_route_mapping` block exists at `plugins/soleur/skills/test-browser/SKILL.md:131` — the ad-hoc runtime mapping the issue describes is real.
- Consumer skills `qa`, `ux-audit`, `reproduce-bug` all exist under `plugins/soleur/skills/`.
- `apps/web-platform/app/**/page.tsx` → 32 files; the gate's quantifier set is real.
- ADR corpus grep (`feature map`, `drift gate`, `advisory`, `lint`) → no ADR rejected or decided this mechanism; ADR-071 (L1 constraint gates) and the `lint-bot-statuses` advisory job establish the *pattern* the gate follows.

### Property List (Phase 0.6b)

1. A committed, user-POV inventory of `apps/web-platform` features exists covering the dashboard's primary routes — each entry naming route path, stable selectors, expected outcome, auth/fixture needs, and gotchas.
2. `test-browser` (and secondarily `qa`/`ux-audit`/`reproduce-bug`) can navigate by feature from the committed map instead of ad-hoc file→route inference.
3. Drift is surfaced: a new `app/**/page.tsx` with no corresponding map entry produces an advisory CI signal (not silent staleness, not a merge block).

### Mechanism vs. Existing (Phase 0.6b)

| Proposed mechanism | Property | Existing coverage |
|---|---|---|
| Committed map artifact (`apps/web-platform/test/feature-map.md`) | 1, 2 | Partial: `plugins/soleur/skills/ux-audit/references/route-list.yaml` inventories 11 routes but is ux-audit-scoped, plugin-side (not app-side), and its schema is `{path, auth, fixture_prereqs, viewport}` — no selectors, no expected outcomes, no gotchas. It is a screenshot-queue config, not a navigation map. Gap remains. |
| Advisory CI drift gate (new `page.tsx` without map entry) | 3 | None. But the advisory-gate *pattern* exists: `lint-bot-statuses` job in `.github/workflows/ci.yml` (absent from `scripts/required-checks.txt`) carries advisory lint steps; `scripts/lint-*.sh` + companion `.test.sh` mutation battery + `run_suite` registration in `scripts/test-all.sh` is the canonical shape. Reuse it; do NOT build a new workflow/job. |
| `test-browser` SKILL.md cites map as navigation source | 2 | None — the mapping block is generic (Rails-oriented table). A pointer amendment is the mechanism. |

### Cut List (Phase 0.6b)

- Route→map generator script (auto-emitting map entries from `page.tsx` sources): buys no new property — the AC requires entries with selectors + expected outcomes, which cannot be generated; a scaffold would produce empty-shaped rows the gate then certifies. Cut.
- Map in YAML with schema validation (extending `route-list.yaml`): rejected — MD is the maintainable author-facing format for prose outcomes/gotchas; a YAML re-schema of ux-audit's file would couple two consumers' drift rates. The map links to `route-list.yaml` for auth/fixture detail instead of duplicating it.
- Blocking (required-check) gate: the AC says "advisory first"; promotion is a deliberate follow-up per the repo's own advisory→required path (#6883/ADR-139 note in ci.yml).
- Wiring `qa`/`ux-audit`/`reproduce-bug` SKILL.md edits: out of AC scope (`test-browser` is the only required citation); noted as optional follow-through, not plan deliverables.

### Relevant file paths

- `plugins/soleur/skills/test-browser/SKILL.md` — `file_to_route_mapping` at line 131; citation lands in/near this block.
- `plugins/soleur/skills/ux-audit/references/route-list.yaml` — 11-route inventory `{path, auth, fixture_prereqs, viewport}`; exclusion notes already list dynamic routes. The map cross-references it for auth/fixture, does not re-encode it.
- `plugins/soleur/test/ux-audit/route-list-prereqs.test.ts` — schema guard for that file.
- `apps/web-platform/test/README.md` — test-dir conventions; `feature-map.md` sits beside it.
- `apps/web-platform/e2e/nav-states-shell.e2e.ts:389-419` — canonical selector vocabulary (`getByTestId`, `getByRole`, rail/workbench testids: `workspace-context-band`, `conversations-rail`, `kb-rail-tree`, `settings-rail-nav`, `rail-secondary-slot`, `chat-index-resume`, `foundation-section-shimmer`, `disconnected-orphans-hint`, `first-run-attachment-label`, `drawer-back-to-menu`).
- `apps/web-platform/app/(dashboard)/dashboard/` — 19 page files (primary surface): `page.tsx`, `chat/page.tsx`, `chat/[conversationId]/page.tsx`, `inbox/page.tsx`, `inbox/email/[emailId]/page.tsx`, `kb/page.tsx`, `kb/[...path]/page.tsx`, `workstream/page.tsx`, `audit/page.tsx`, `audit/github/page.tsx`, `billing/page.tsx`, `releases/page.tsx`, `routines/page.tsx`, `crm/page.tsx`, `admin/analytics/page.tsx`, `settings/page.tsx` + 6 settings subroutes.
- `.github/workflows/ci.yml` — `lint-bot-statuses` advisory job (~line 437); new step lands here with an ADVISORY comment per the in-file convention.
- `scripts/lint-integration-env-gates.sh` + `scripts/lint-integration-env-gates.test.sh` — canonical lint + fixture-seam (`SOLEUR_LINT_GATES_ROOT`) + mutation-battery pair to mirror.
- `scripts/test-all.sh` (~line 5456) — `run_suite` registration site (live + battery pair).
- `scripts/required-checks.txt` — required-context list; absence = advisory (the file's own header warns against adding content gates it cannot synthesize).
- `scripts/lint-orphan-test-suites.sh` — auto-enforces `.test.sh` registration; the new battery MUST be registered in `test-all.sh` or this lint reddens.

### Institutional learnings applied

- `2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift` — an ABSENT map entry must never read as SKIP; the lint distinguishes "map file missing" / "route entry missing" / "entry present" as three states, and fails closed on the first.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing` — mutation matrix + must-PASS rows required (Guard Contract section).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous` — companion `.test.sh` mutates the tree underneath the guard (add unmapped page.tsx, remove map file, rename entry, etc.).
- `2026-07-04-bash-yaml-drift-guard-must-mutation-test-fail-open` — battery proves fail-open directions redden.
- `2026-04-28-plan-globs-must-be-verified-against-repo-structure` — `app/**/page.tsx` glob verified: 32 files tracked; producer is `git ls-files`/`git grep` over the tracked tree, not a directory walk.
- `2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail` — lint script avoids `git ls-files | head`-style early-exit consumers under `set -o pipefail`.
- `2026-05-12-task-subagent-prompt-text-only` — Task subagents receive prompt text only (relevant to pipeline context, not implementation).

### External research decision (Phase 1.6)

Skipped — strong local conventions cover every surface this plan touches (lint-script shape, advisory job, test registration, selector vocabulary, route-list precedent). Functional-discovery registry sweep (Phase 1.5b): `pathfinder` (codebase→flowchart mapper), `atris` (unrelated workflow system) — no functional overlap; nothing installed.

### Related issues / PRs

- #10399 (this issue), epic #10397 (agentic-verification gaps), sibling #10402 (feature-map convention *for plugin users* — explicitly out of scope here; this plan is self-codebase only).
- #2378 — origin of `route-list.yaml` ordering/exclusion rationale.
- #6883 / ADR-139 — advisory→required promotion path this gate would later follow.

## Problem Statement / Motivation

`test-browser` maps changed files to routes at runtime from a generic file→route table (`plugins/soleur/skills/test-browser/SKILL.md:131`) — Rails-oriented heuristics that know nothing about *this* app's actual routes, selectors, or expected outcomes. `git grep -il "feature map\|feature-map"` returns zero: no persistent, user-POV inventory exists. `ux-audit` owns a partial precedent (`route-list.yaml`, 11 routes, `{path, auth, fixture_prereqs, viewport}`) that is a screenshot-queue config — it carries no selectors, no expected outcomes, no gotchas, and no other skill consumes it. Meanwhile the epic (#10397) identifies "no maintained feature map" as a measured self-codebase gap: agents verifying the running app re-derive navigation on every session, and nothing notices when a new route ships unmapped.

## Proposed Solution

Three coupled deliverables, one PR:

1. **The map — `apps/web-platform/test/feature-map.md`.** Markdown, one `##`/route`` H2 entry per covered route carrying: `route:` path, `entry:` how an agent reaches it (nav link / direct URL / auth prerequisite), `selectors:` the stable anchors (prefer `data-testid` and `getByRole`/`getByText` vocabulary already used by `e2e/nav-states-shell.e2e.ts:389-419`), `expects:` the user-POV expected outcome, `auth:` anonymous | bot | admin, `gotchas:` free-text. Coverage: every `app/(dashboard)/**` route plus the anonymous funnel (`/`, `/login`, `/signup`, `/accept-terms`). A closing `## Deliberately unmapped` section lists each excluded route with a reason — this doubles as the lint's allowlist, so the exemption registry lives inside the artifact it exempts. Auth/fixture detail cross-references `route-list.yaml` rather than duplicating it.

2. **The drift gate — `scripts/lint-feature-map-coverage.sh` + companion `scripts/lint-feature-map-coverage.test.sh`.** Producer: `git ls-files 'apps/web-platform/app/**/page.tsx'` over the tracked tree → derive each route path by stripping `apps/web-platform/app/`, dropping `/page.tsx`, and removing `(...)` route-group segments (`internal/github-app-init` keeps its literal `internal` segment; `app/page.tsx` → `/`). Consumer: the map file — a `##`/route`` H2 heading marks a route *mapped*; a `- \`/route\` — <reason>` bullet under `## Deliberately unmapped` marks it *exempted*. Three arms (spec-flow additions): (a) **coverage** — every derived route is mapped or exempted; (b) **staleness** — every mapped/exempted route still derives from a real page.tsx file (a tombstone entry for a deleted route reds); (c) **entry completeness** — every mapped entry body contains `selectors:` and `expects:` lines (the issue's AC demands them, so presence-only coverage would certify a non-conformant map). Distinct failure states, never a silent skip: map file absent → RED ("map missing"); uncovered/stale/incomplete/contradictory (route in both sets) → RED naming each; producer yields zero `page.tsx` → RED (anti-vacuity — "0 checked" never exits 0). Advisory step added to the `lint-bot-statuses` job in `.github/workflows/ci.yml` (absent from `scripts/required-checks.txt` = advisory, per the in-file #6882 note). Companion battery registered in `scripts/test-all.sh` adjacent to the `lint-integration-env-gates` pair (~line 5456), live + battery `run_suite` lines, mirroring that pair's shape and its `SOLEUR_LINT_GATES_ROOT`-style fixture seam.

3. **The citation — `plugins/soleur/skills/test-browser/SKILL.md`.** A short paragraph inside the `<file_to_route_mapping>` block: when the repo carries `apps/web-platform/test/feature-map.md`, its route entries + selectors are the navigation source of truth; the generic table below remains the fallback for repos without a map. Body edit only — no `description:` change.

## Technical Considerations

- **Route derivation correctness** is the load-bearing transform: route groups `(auth)`, `(dashboard)`, `(public)` are non-path segments; `[param]`/`[...catchall]` stay literal in the map key (the map documents `/dashboard/chat/[conversationId]`, not a concrete id); `internal/` is a *literal* segment, not a group. The battery pins each edge shape.
- **Fail-open is the defect class** (learnings `2026-10-13`, `2026-09-08`, `2026-08-10`): map-file-absent, producer-zero, and unmapped-route are all RED; nothing reads absent as skip.
- **Consistent-by-construction is the goal state**: deleting a page.tsx *and* its map entry in one PR is correct, not drift — the property is coverage of what exists, not freeze of what existed.
- **`lint-orphan-test-suites.sh`** auto-enforces companion-test registration: the `.test.sh` MUST appear in `scripts/test-all.sh` or that lint reddens.
- **Battery trap hygiene** (#8659): the new `.test.sh` builds its scratch fixture repo via `mktemp -d` + `trap … EXIT`; if it sources `plugins/soleur/test/test-helpers.sh` it must NOT install a bare post-source EXIT trap without `_soleur_sb_cleanup` — simplest is not sourcing it at all.
- **CI step conventions:** ADVISORY comment block per the job's in-file convention; `if: ${{ !cancelled() }}` so the step still reports when an earlier advisory lint reds (same reason the folded steps carry it).
- **Heading-anchor strictness (advisor consult):** `## Deliberately unmapped` is itself an H2 — the mapped-set parse anchors on `^##`+backtick-slash, never a bare `^##`; entry ###` subsections are already excluded by the `^##` level match (matrix row 12 pins both shapes).
- **Single map-path constant (advisor consult):** `MAP_FILE=apps/web-platform/test/feature-map.md` is declared once at the lint's top and cited by symbol everywhere else — the path already repeats across the script, ci.yml step, SKILL.md, README, and the map's own header, so a rename must touch one constant, not five literals.
- **Architecture decision check (Phase 2.10):** none — a docs artifact + advisory lint following an established pattern; no substrate/trust-boundary/ownership change. Reading `model.c4`/`views.c4`/`spec.c4` is unnecessary: no external actor, system, container, or access relationship changes (no new user role, vendor, store, or edge). Explicitly no C4 impact.
- **Encryption posture (Phase 2.11):** skip — no persistent store, no cross-component connection.
- **Observability (Phase 2.9):** detection set (`apps/*/server|src|infra`, `plugins/*/scripts/`, new infra surface) not touched — the deliverable IS the detection surface; its own liveness is the CI step plus the companion battery.

## User-Brand Impact

- **If this lands broken, the user experiences:** a red `lint-bot-statuses` advisory step on an unrelated PR (noise, not a merge block), or a stale map silently steering a post-ship smoke test at the wrong route — an internal-signal defect, not a user-facing artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the map contains route paths and selectors already public in the repo's own source; no user data, credentials, or tenant information is captured.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** dev-tooling artifact plus advisory CI signal; no user data path touched and no blocking gate introduced — the blast radius of a defect is CI annotation noise or agent mis-navigation, both internal.

## Guard Contract

### Guard 1 — `lint-feature-map-coverage` (drift gate)

**Property.** The tracked `apps/web-platform/app/**/page.tsx` set and `apps/web-platform/test/feature-map.md` are bidirectionally consistent: every derivable route is mapped (a `##`/route`` entry containing `selectors:` and `expects:` lines) or reasoned-exempt (a `- \`/route\` — <reason>` bullet under `## Deliberately unmapped`), and every mapped/exempted route still derives from a real page.tsx file. A new unmapped page, a tombstone entry, or a field-stripped entry reddens the advisory CI step instead of silently widening drift.

**Assembly.** Two chokepoints, both enumerated: (a) the *producer* — `git ls-files 'apps/web-platform/app/**/page.tsx'` over the tracked tree, i.e. every file that can introduce a route; there is no second route-injection site (Next.js App Router routes are file-defined). (b) the *consumer* — the map file's `##`/…``-heading set, each heading's body fields (`selectors:`/`expects:`), and the `## Deliberately unmapped` bullet set; the map is the single parse target, there is no sibling inventory.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add `app/(dashboard)/dashboard/new-widget/page.tsx` with no map entry | RED (names `/dashboard/new-widget`) |
| 2 | Delete `apps/web-platform/test/feature-map.md` entirely | RED ("map missing" — fail-closed, not "0 checked") |
| 3 | After a compliant first page, add a SECOND unmapped `page.tsx` | RED listing both (guard does not stop at first) |
| 4 | Rename a `page.tsx` directory so its derived route no longer matches the map heading (e.g. `chat/` → `chatx/`) | RED on the new derived route |
| 5 | Move a route's map heading into `## Deliberately unmapped` *without* a reason phrase after the `—` | RED (exemption requires a recorded reason) |
| 6 | Neuter the route-derivation regex so `git ls-files` output parses to zero routes | RED ("producer yielded 0" — own-dispatch vacuity row) |
| 7 | Delete a `page.tsx` but keep its `##`/route`` map entry | RED (tombstone entry — map→route arm) |
| 8 | Strip the `expects:` line from one mapped entry, heading intact | RED (entry-completeness arm — presence is not conformance) |
| 9 | List a route under `## Deliberately unmapped` *and* keep its `##`/route`` heading | RED (contradictory classification) |
| 10 | (harness) Strip the `##` prefix from a map heading while keeping the path text | RED — a bare-token match would have passed; heading-anchor is the assertion |
| 11 | (must-PASS) `app/(dashboard)/dashboard/page.tsx` → `/dashboard` AND `app/page.tsx` → `/` AND `app/(public)/invite/[token]/page.tsx` → `/invite/[token]` each resolve through route-group stripping | PASS — non-canonical inputs the contract permits |
| 12 | (must-PASS) A route listed *only* under `## Deliberately unmapped` with a reason stays green; a `###` subheading inside an entry is not miscounted as a route heading | PASS — exemption is a first-class state; parse is `^##` not `^#` |

**Anchor.** The quantifier set is *derived* (`git ls-files` over the tracked tree at merge-base), not a stored manifest — so no single diff can weaken both sides at once: removing a route AND its entry is the *desired* consistency, while removing only the entry reds. The map file is the sole stored side; a PR that deletes the file outright is caught by row 2, and promotion to a required check (#6883/ADR-139 path) is the follow-up that would make the anchor merge-enforced rather than advisory.

## Implementation Phases

### Phase 1 — Guard battery, RED-first

- Author `scripts/lint-feature-map-coverage.test.sh`: builds a scratch fixture repo (`mktemp -d`, `git init`, `SOLEUR_LINT_GATES_ROOT`-style root seam), plants `app/**/page.tsx` + `test/feature-map.md` fixtures, and drives every mutation-matrix row above. Runs RED because the lint does not yet exist.
- Success: battery file exists, all rows fail against a stub/absent lint (proving the harness detects absence, not just violations).

### Phase 2 — The guard

- Author `scripts/lint-feature-map-coverage.sh`: `#!/usr/bin/env bash`, `set -euo pipefail`, `LC_ALL=C` export, root-override seam, header docstring stating WHY + ADVISORY level + companion-suite pointer (mirroring `lint-integration-env-gates.sh`'s header contract). Producer → derive → compare → print one line per uncovered route; exit non-zero on any of: map missing, uncovered route(s), zero derived routes. No early-exit pipe consumers under `pipefail` (`2026-10-02` learning).
- Success: battery green; live run against this repo reds (map does not exist yet — expected at this phase).

### Phase 3 — The map

- Author `apps/web-platform/test/feature-map.md` covering every `app/(dashboard)/**` route (22 entries) plus `/`, `/login`, `/signup`, `/accept-terms` — selectors lifted from `data-testid`/role/text anchors in the pages + `e2e/nav-states-shell.e2e.ts`; `## Deliberately unmapped` covering `/setup-key`, `/connect-repo`, `/internal/github-app-init`, `/shared/[token]`, `/invite/[token]` with reasons.
- Success: `bash scripts/lint-feature-map-coverage.sh` exits 0.

### Phase 4 — Wiring + citation

- `.github/workflows/ci.yml`: add step to `lint-bot-statuses` with ADVISORY comment + `if: ${{ !cancelled() }}`.
- `scripts/test-all.sh`: register live + battery `run_suite` lines adjacent to the `lint-integration-env-gates` pair.
- `plugins/soleur/skills/test-browser/SKILL.md`: add the navigation-source paragraph inside `<file_to_route_mapping>`.
- `apps/web-platform/test/README.md`: one-line index entry for `feature-map.md`.
- Success: `bash scripts/test-all.sh` new suites pass; `lint-orphan-test-suites` green; `git diff` shows the citation paragraph.

## Files to Create

- `apps/web-platform/test/feature-map.md` — the feature map (~26 mapped routes + 5 deliberately-unmapped rows).
- `scripts/lint-feature-map-coverage.sh` — the drift gate.
- `scripts/lint-feature-map-coverage.test.sh` — companion mutation battery.

## Files to Edit

- `.github/workflows/ci.yml` — one advisory step (+ comment block) in `lint-bot-statuses`.
- `scripts/test-all.sh` — two `run_suite` lines (live + battery).
- `plugins/soleur/skills/test-browser/SKILL.md` — navigation-source paragraph inside `<file_to_route_mapping>`.
- `apps/web-platform/test/README.md` — one-line index entry.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` (2026-10-20), bodies searched per planned path:

- **#8659** (test-helpers composed EXIT trap, touches `scripts/test-all.sh`): **acknowledge** — does not change scope; the new battery avoids the defect class by not sourcing `test-helpers.sh` at all (recorded in Technical Considerations). Issue remains open for the 33-file refactor.
- **#7942** (`*.mutation.sh` batteries run in no gate, touches `scripts/test-all.sh`): **acknowledge** — the plan already satisfies it: companion is `*.test.sh` and registered in `test-all.sh`.
- All other planned paths: no matches.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Feature map file exists covering the dashboard's primary routes with selectors + expected outcomes." | `apps/web-platform/test/feature-map.md` (Files to Create; Phase 3) | mapped |
| 2 | "A lint/CI gate flags a new `app/**/page.tsx` missing a map entry (advisory first)." | `scripts/lint-feature-map-coverage.sh` + ci.yml advisory step (Phase 2, 4) | mapped |
| 3 | "`test-browser` SKILL.md cites the map as its navigation source when present." | `plugins/soleur/skills/test-browser/SKILL.md` edit (Phase 4) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform/test/feature-map.md` | asks 1 (quote in row 1) | asked |
| `scripts/lint-feature-map-coverage.sh` | asks 2 (quote in row 2) | asked |
| `.github/workflows/ci.yml` step | asks 2 ("wired into CI", "advisory first") | asked |
| `plugins/soleur/skills/test-browser/SKILL.md` | asks 3 (quote in row 3) | asked |
| `scripts/lint-feature-map-coverage.test.sh` | — | inferred — justification: repo enforcement contract (`lint-orphan-test-suites.sh`) plus the guard-contract class ("a guard that cannot be driven red is vacuous"); the companion battery is how this repo proves a guard detects. |
| `scripts/test-all.sh` run_suite lines | — | inferred — justification: `lint-orphan-test-suites.sh` reddens on any unregistered `*.test.sh`; registration is mechanical, not optional. |
| `apps/web-platform/test/README.md` index line | — | inferred — justification: the map's value is discoverability; the README is the directory's index. One line, no structural change. |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `plugins/soleur`, `scripts`, `.github`
- Planned files: 7 | Estimated changed lines: ~600 (map ~350, lint ~120, battery ~200, wiring ~30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — root count is at threshold (4)
- Recommendation: single PR — the four roots are shallow touches (one CI step, two run_suite lines, one SKILL.md paragraph, one README line) and the deliverable is atomic: the lint certifies the map, the citation consumes it; splitting strands either an unregistered battery (lint-orphan red) or a citation to a nonexistent file.

## Acceptance Criteria

<!-- founder-stated check: ACs map 1:1 to issue #10399's Acceptance section. -->

- [ ] `apps/web-platform/test/feature-map.md` exists; every route derived from `git ls-files 'apps/web-platform/app/**/page.tsx'` appears either as a `##`/route`` entry carrying `selectors:` + `expects:` or as a reasoned bullet under `## Deliberately unmapped`.
- [ ] Map covers every `app/(dashboard)/**` route plus `/`, `/login`, `/signup`, `/accept-terms` (≥ 24 mapped entries), each naming at least one stable selector and one expected outcome.
- [ ] `scripts/lint-feature-map-coverage.sh` exits non-zero listing each uncovered route; exits non-zero when the map file is absent; exits non-zero when the producer derives zero routes; exits non-zero on a tombstone entry (mapped/exempted route with no backing `page.tsx`), an entry missing `selectors:`/`expects:`, or a route classified in both sets; exits 0 on a fully-consistent tree.
- [ ] `scripts/lint-feature-map-coverage.test.sh` drives every Guard-Contract matrix row (12 rows) and is registered in `scripts/test-all.sh` alongside a live run of the lint itself.
- [ ] `.github/workflows/ci.yml` `lint-bot-statuses` gains a step running `bash scripts/lint-feature-map-coverage.sh`; the job remains absent from `scripts/required-checks.txt` (advisory-first per the ask).
- [ ] `plugins/soleur/skills/test-browser/SKILL.md` `<file_to_route_mapping>` names `apps/web-platform/test/feature-map.md` as the preferred navigation source when present.
- [ ] `bash scripts/lint-feature-map-coverage.sh` exits 0 on the committed tree; `bash scripts/lint-orphan-test-suites.sh` stays green.

## Domain Review

**Domains relevant:** Engineering, Product (capability mandate — CMO omitted: operator-facing dev tooling, no external-facing surface).

### Engineering

**Status:** reviewed
**Assessment:** (CTO, in-process) Low technical risk — all three deliverables follow established repo patterns (`lint-*` + companion battery + advisory step + `run_suite` registration). Real risks are the recurring fail-open class (absent-map/producer-zero must RED), route-derivation edge shapes (route groups vs literal `internal/`, root `page.tsx`, dynamic segments stay literal), and duplicate-truth drift vs `route-list.yaml` (cross-reference, don't re-encode). No architectural decision — no ADR/C4 task. Complexity: small (~1 day). Capability gaps: none.

### Product

**Status:** reviewed
**Assessment:** (CPO, in-process) Internal tooling — no end-user surface. The map's `expects:` fields should be phrased user-POV (what the solo-founder ICP sees), consistent with TR7's 1440×900 baseline already used by `route-list.yaml`. Coverage choice endorsed: all `(dashboard)` routes (the ICP's working surface) + anonymous funnel, admin route carried with its role-gate gotcha. Tier: **none** — mechanical UI-surface scan of Files to Create/Edit finds no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`; the plan discusses UI navigation but implements docs + CI + skill prose (exempt per the gate's own rule).

## Test Scenarios

All `unit`-layer (the guard is a bash script; the battery is the test).

- **Given** a fixture repo with `app/(dashboard)/dashboard/x/page.tsx` and a map lacking `/dashboard/x`, **when** the lint runs, **then** it exits non-zero naming `/dashboard/x`.
- **Given** a fixture repo with `feature-map.md` deleted, **when** the lint runs, **then** it exits non-zero with the map-missing reason (not "0 checked").
- **Given** a fixture whose `page.tsx` set is fully mapped or reasoned-exempt, **when** the lint runs, **then** it exits 0.
- **Given** a second unmapped page added after a compliant first, **when** the lint runs, **then** both are listed (no first-member short-circuit).
- **Given** a deleted `page.tsx` whose map entry remains, **when** the lint runs, **then** it reddens naming the tombstone entry (staleness arm).
- **Given** a mapped entry stripped of `expects:` and a route present in both mapped and unmapped sets, **when** the lint runs, **then** each reds on the completeness and contradiction arms.
- **Given** a stripped `##`-prefix heading, a moved-without-reason exemption, and a neutered derivation regex, **when** each mutation applies, **then** the lint reddens on each.
- **Given** the committed tree after Phase 3, **when** `bash scripts/lint-feature-map-coverage.sh` runs, **then** exit 0.
- **Given** `scripts/test-all.sh`, **when** the new `run_suite` lines execute, **then** live + battery report pass and `lint-orphan-test-suites` stays green.

## Success Metrics

- `git grep -il "feature-map"` returns ≥1 hit (`apps/web-platform/test/feature-map.md`) — the evidence-today gap is closed.
- Advisory step reports green on `main`; a deliberately-unmapped test PR (if ever opened) shows a red annotation without blocking merge.
- `test-browser` sessions cite route+selector pairs from the map rather than re-deriving them.

## Dependencies & Risks

- **Map rot between lint runs** — advisory means a red step can be ignored; the map's header states the update contract ("new/renamed route → update this file or the Deliberately-unmapped list in the same PR"). Promotion to required is the deliberate #6883/ADR-139 follow-up, not this PR.
- **Route-derivation drift** — a future Next.js convention (e.g. `page.jsx`, `template.tsx`) is out of the producer's glob; the allowlist section documents the current rule and widening is a header-comment edit per `lint-integration-env-gates.sh` convention.
- **Selector rot** — selectors are citations, not assertions; the lint checks *route coverage*, not selector freshness (named non-goal: selector-liveness would need a browser).
- **#8659 adjacency** — battery must not reproduce the un-composed-EXIT-trap class (noted in Technical Considerations).
- **Deferred, tracked here (no issue filed from the planning subagent):** one-line map pointers in `qa`/`ux-audit`/`reproduce-bug` SKILL.md (consumers named in the issue's Scope; only `test-browser` citation is in the AC) — re-evaluate when the map has lived through one real navigation cycle; milestone: Post-MVP / Later (same as #10399). Advisory→required promotion is already tracked by the #6883/ADR-139 path.

## References & Research

- Issue: #10399 (ACs), epic #10397, sibling #10402 (plugin-side convention — out of scope).
- `plugins/soleur/skills/test-browser/SKILL.md:131` (`file_to_route_mapping`)
- `plugins/soleur/skills/ux-audit/references/route-list.yaml` + `plugins/soleur/test/ux-audit/route-list-prereqs.test.ts`
- `scripts/lint-integration-env-gates.sh` + `.test.sh` (canonical pair), `scripts/test-all.sh:5456` (registration site), `scripts/required-checks.txt` (advisory definition), `.github/workflows/ci.yml` `lint-bot-statuses` job
- `apps/web-platform/e2e/nav-states-shell.e2e.ts:389-419` (selector vocabulary), `apps/web-platform/test/README.md`
- Learnings: `2026-10-13` (absent-as-skip fail-open), `2026-09-08` (deleted-guard citation), `2026-08-13`/`2026-08-10` (vacuous guards), `2026-07-04` (mutation-test fail-open), `2026-04-28` (glob verification), `2026-10-02` (SIGPIPE under pipefail)

## Plan Review

Panel run in-process, sequential-fallback (Devin CLI harness — no Task tool; roles executed per their agent files): DHH (overengineering), Kieran (correctness/convention), code-simplicity (per-mechanism vs Property List), CTO devex lens (named panel — code/infra Files activate it; CPO/CMO/UX-design-lead not activated: no UI-surface files, no market/brand-copy content). Standing panel check `cq-ac-must-not-depend-on-concurrent-sessions`: all ACs assert tree state or fixture behavior — none measure ambient process state. **Result: no blocking findings, no auto-apply items, no Taste/User-Challenge items.**

## Deepen-Plan Enhancements

(pending — populated by `soleur:deepen-plan`)
