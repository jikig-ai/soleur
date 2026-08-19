---
title: "chore: migrate apps/web-platform from `next lint` to the ESLint CLI with a flat config"
date: 2026-08-19
slug: chore-eslint-flat-config-migration
branch: feat-one-shot-1327-eslint-flat-config
issue: 1327
closes: 1327
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Overview

`apps/web-platform` runs `"lint": "next lint"`. Next.js 16 removes `next lint`, so this script
is the stated blocker on the Next 15→16 major (#7594). Replace it with a direct ESLint 9 flat
config.

Two things make this bigger than a script swap, both measured rather than assumed:

1. There is **no ESLint config anywhere in the repo** and **no CI job runs lint**. So this is not
   a port of a working gate — it is standing one up for the first time, on ~2000 files that have
   never been linted. The issue's prescribed codemod has nothing to convert.
2. **ESLint's glob layer is currently broken in this package.** A blanket npm `overrides` entry
   pins `brace-expansion` to `^5.0.9`; `minimatch@3.1.5` — which `eslint`, `@eslint/config-array`,
   `@eslint/eslintrc`, `eslint-plugin-import`, `eslint-plugin-jsx-a11y` and `eslint-plugin-react`
   all depend on — requires `^1.1.7`. v5 exports an object where v1 exported a function, so any
   brace glob dies with `TypeError: expand is not a function`. Fixing that is a precondition,
   not a nice-to-have.

`lane:` defaulted to `cross-domain` (TR2 fail-closed) — no `spec.md` existed for this branch.

## Research Reconciliation — brief vs. codebase

Measured 2026-08-19 in this worktree against `origin/main` `ff4eed6e5`.

| Claim | Measured reality | Plan response |
|---|---|---|
| Issue step 1: run `next-lint-to-eslint-cli` codemod | Nothing to convert — `git ls-files` finds **0** `.eslintrc*` / `eslint.config.*` and no `eslintConfig` key in any `package.json` | Author the flat config directly; do not run the codemod |
| Issue step 4: "remove `eslint-config-next` once direct ESLint config is working" | Backwards. It is the dependency vehicle supplying `@typescript-eslint/parser` 8.60.1, `@typescript-eslint/eslint-plugin` 8.60.1, `eslint-plugin-react` 7.37.5, `-react-hooks` 5.2.0, `-import` 2.32.0, `-jsx-a11y` 6.10.2, `@next/eslint-plugin-next` 15.5.19 | Keep it (Decision 2). Removing it removes every rule source and the parser |
| Issue step 3: "verify lint output is equivalent" | Unverifiable — `next lint` has no config, so it prompts interactively and exits 1. There is no baseline to be equivalent to | Replaced by a pinned finding-count AC (AC4) |
| "`next lint` shows a deprecation warning" (issue Context) | It does not get that far: no config → interactive prompt → exit 1 | Noted; the script is already non-functional, not merely deprecated |
| Brief: "the `brace-expansion` breakage is local install drift; CI unaffected" | **FALSE — my own claim, falsified.** A fresh `npm install` in a clean worktree reproduced `5.0.9`. The cause is a committed blanket `overrides` entry, so `npm ci` reproduces it and CI is affected | Decision 3 fixes it in-scope |
| Brief: "four `package-lock.json` files exist despite the one-lockfile-of-record consolidation" | **FALSE — my own claim, falsified.** ADR-191 means *npm, not bun*. All four `package-lock.json` files (root, `apps/web-platform`, `pencil-setup/scripts`, `spike`) are deliberate and are all gated by `lockfile-sync` | No action; the four-lockfile layout is by design |
| `@next/eslint-plugin-next` needs a `FlatCompat` shim | It exposes a native `flatConfig` export (`recommended`, `coreWebVitals`) | No shim needed |

### The `brace-expansion` defect, measured

`apps/web-platform/package.json` carries a **blanket** override:

```json
"overrides": { "brace-expansion": "^5.0.9", ... }
```

The repo root carries the **correct** form for the same CVE: `"brace-expansion": "^1.1.16"`.

npm `overrides` deliberately override transitive constraints, so the blanket entry rewrites
every consumer's requirement. But this tree needs four brace-expansion majors simultaneously:

| minimatch | requires | consumers |
|---|---|---|
| 3.1.5 | `^1.1.7` | `eslint`, `@eslint/config-array`, `@eslint/eslintrc`, `eslint-plugin-import`, `-jsx-a11y`, `-react` |
| 9.0.9 | `^2.0.2` | `rimraf` |
| 10.2.4 | `^5.0.2` | `@typescript-eslint/typescript-estree`, `glob` |
| 10.2.5 | `^5.0.5` | `readdir-glob` |

A blanket override to any single version necessarily breaks the majors it does not match. The
current `^5.0.9` satisfies the minimatch@10 consumers and breaks minimatch@3 and minimatch@9.

The API break is direct: v5 exports `{ EXPANSION_MAX, EXPANSION_MAX_LENGTH, expand }`, while
`minimatch/minimatch.js:10` does `var expand = require('brace-expansion')` and calls it. Object,
not function → `TypeError: expand is not a function at Minimatch.braceExpand`.

It is silent today only because nothing in the repo runs ESLint.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 1327` → `OPEN`, no closing PRs; milestone `Post-MVP / Later`. Premise holds.
- `gh issue view 7594` → `OPEN`. It names #1327 as a hard prerequisite. Premise holds.
- Collision probes for both refs (linked-issue, body-text, title, `git log --grep`) returned zero
  after retrying two that failed on TLS timeout. No existing branch or worktree matches.
- Mechanism vs ADR corpus: no ADR decides lint tooling. **ADR-191** (npm single lockfile of
  record, accepted 2026-08-16) governs the lockfile surface this plan touches and is consistent
  with Decision 3 — it gates all four `package-lock.json` files through `lockfile-sync`.
- Capability claims verified rather than asserted: `@next/eslint-plugin-next` `flatConfig` export
  read off the installed package; every plugin/parser version read from `node_modules`.

### Property List (Phase 0.6b)

1. `next lint` is no longer invoked anywhere, so the Next 16 upgrade is not blocked by it.
2. Lint runs non-interactively and terminates with a deterministic status.
3. The finding count is known and pinned, so a regression is visible.
4. ESLint's glob layer works, so a config using ordinary patterns does not crash.
5. The repo's own guidance about the lint gate matches what actually ships.

### Cut List (Phase 0.6b)

| Mechanism | Property | Why cut |
|---|---|---|
| `next-lint-to-eslint-cli` codemod | (1) | Nothing to convert — zero eslintrc files exist |
| `@eslint/eslintrc` `FlatCompat` shim | (1)(2) | `@next/eslint-plugin-next` ships a native `flatConfig` export |
| New devDependencies | (2) | Parser + all five plugins already present transitively via `eslint-config-next` |
| A brace-free-glob lint rule + guard test | (4) | Superseded by Decision 3 — fixing the override removes the constraint the guard would police. Guarding a self-inflicted breakage instead of removing it is the worse trade |
| Sweeping ~18 historical learnings/plans mentioning `next lint` | (5) | Point-in-time records; only operative guidance is corrected (Decision 4) |

### Relevant institutional learnings

- `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md` —
  `lockfile-sync` regenerates all four lockfiles under npm@11 and diffs; the override edit must
  regenerate byte-identically under that same runner.
- `knowledge-base/project/learnings/2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative.md`
  — the record this change falsifies; gets an addendum, not a rewrite.

## Hypotheses

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | ESLint brace-glob crash is local install drift | **REFUTED** | Fresh `npm install` in a clean worktree reproduced `brace-expansion@5.0.9` |
| H2 | The lockfile is corrupt / hand-edited | **REFUTED** | It is exactly what npm@11 produces from the committed `overrides`; ADR-191 verified byte-identical regeneration |
| H3 | A blanket `overrides` entry forces an incompatible major | **CONFIRMED** | `overrides["brace-expansion"] = "^5.0.9"` in `apps/web-platform/package.json`; root uses `^1.1.16` for the same CVE |
| H4 | The override is still required for CVE remediation | **REFUTED** | Every major line's natural `^` range already lands on a patched release (`^1.1.7` → 1.1.18 ≥ 1.1.12 patched). Verified per-line in AC7 |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — lint is a developer-facing
gate with no runtime surface. The indirect effect is a red required check on unrelated PRs if a
lint job is wired too aggressively, which is why Decision 1 keeps it non-blocking.

**If this leaks, the user's data is exposed via:** no new exposure path. No secrets, no runtime
code, no persistent store. The `overrides` change touches build-time dependency resolution only.

**Brand-survival threshold:** `none` — developer tooling with no user-facing surface and no
regulated-data path. No sensitive-path scope-out bullet is required: the diff touches
`package.json`, a lockfile, an ESLint config, one workflow, one skill doc and one learning file.

## Files to Edit

- `apps/web-platform/package.json` — `"lint"` script → ESLint CLI; scope/remove the
  `brace-expansion` override.
- `apps/web-platform/package-lock.json` — regenerated under npm@11 (`lockfile-sync` gates this).
- `.github/workflows/ci.yml` — add a **non-blocking** lint job (Decision 1).
- `plugins/soleur/skills/work/SKILL.md` — correct the operative bullet asserting there is no
  eslint config and that lint is non-functional.
- `knowledge-base/project/learnings/2026-06-05-web-platform-lint-gate-is-non-functional-tsc-vitest-are-authoritative.md`
  — append a dated addendum; do not rewrite the body.

## Files to Create

- `apps/web-platform/eslint.config.mjs` — the flat config.
- `apps/web-platform/test/eslint-config.test.ts` — the guard suite (see Guard Contract).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned 64 issues; a
`jq contains` probe for each planned path returned zero matches.

## Decisions

### Decision 1 — ship a CI lint job, non-blocking, not a required check

Nothing runs lint today, so a `lint` script alone buys property (3) only for whoever remembers to
run it. Wire a job in `ci.yml` that runs the CLI and reports.

It is **not** added to `scripts/required-checks.txt` or the required-status-check ruleset. The
config is new, the finding set is ~195 across 85 files on a codebase never linted, and making it
merge-blocking on day one converts every unrelated PR into a lint-triage session. Requiring it is
a deliberate follow-up once the count is driven to zero and has held.

**Rejected:** required-from-day-one (blocks unrelated work on a first-run baseline);
no CI job at all (buys no enforcement, leaves the script decorative).

### Decision 2 — keep `eslint-config-next` as the dependency vehicle

It is the only declared dependency supplying the parser and all five plugins. The flat config
consumes `@next/eslint-plugin-next`'s `flatConfig` export directly rather than the legacy
eslintrc shareable config, so `eslint-config-next` is present for its dependency closure, not its
config content. Record this in a comment so a future reader does not "clean up" an apparently
unused dependency — that is exactly what the issue's step 4 proposed.

**Rejected:** promoting all six packages to direct devDependencies (larger diff, six new version
surfaces for Dependabot, no behavioural gain in this PR).

### Decision 3 — remove the blanket `brace-expansion` override rather than working around it

The override is the defect. Removing it lets npm nest each major independently, which is what it
does correctly for every other multi-major dependency in the tree.

The CVE remediation survives removal because each consumer's own `^` range already lands on a
patched release — verified per-line by AC7, which asserts every resolved `brace-expansion` is at
or above its line's patched version (1.1.12 / 2.0.2 / 3.0.1 / 4.0.1 per the advisory). If any line
resolves below its floor, the remedy is a **scoped** override (the shape the repo root already
uses for `gray-matter` → `js-yaml`), never a blanket one.

**Rejected:** brace-free globs plus a guard test forbidding brace patterns. It leaves `rimraf`'s
minimatch@9 broken, leaves a live trap for the next contributor, and polices a self-inflicted
constraint instead of removing it. **Also rejected:** filing it as a separate issue — it is a hard
blocker for this PR's own acceptance criteria, and at 2 files it is well inside the cost-of-filing
threshold for inline work.

### Decision 4 — correct operative guidance in place, append to the dated record

`plugins/soleur/skills/work/SKILL.md` carries a bullet agents act on, asserting there is no eslint
config and that `tsc` + vitest are the authoritative gates. That becomes false and is corrected in
place. The 2026-06-05 learning file is a dated record, so it gets `## Addendum — 2026-08-19
(#1327)` citing the original rather than an edit to its body.

The ~18 historical learnings/plans that merely mention `next lint` are point-in-time records and
are left alone.

## Implementation Phases

### Phase 0 — preconditions

1. Re-derive the baseline finding count with `languageOptions.globals` configured, since the
   probe's 98 `no-undef` hits are suspected to be a globals artifact rather than real defects.
2. Confirm no new dependency is required (parser + five plugins resolvable from `node_modules`).

### Phase 1 — repair the dependency tree (blocks everything)

Remove/scope the `brace-expansion` override, regenerate `package-lock.json` with
`npx --yes npm@11 install`, validate with `npm ci --ignore-scripts`, and confirm a brace glob no
longer crashes ESLint. Verify per-line patched floors (AC7).

### Phase 2 — the flat config (RED first)

Write `test/eslint-config.test.ts` asserting the Guard Contract properties, watch it fail, then
author `eslint.config.mjs`: `@eslint/js` recommended, `@typescript-eslint/parser` for `.ts/.tsx`,
`@next/eslint-plugin-next` `flatConfig.coreWebVitals`, node/browser globals, and the ignores set.

### Phase 3 — rule dispositions

Drive the finding set to a deterministic state. Each rule ships as `error`, `warn`, or `off` with
a stated reason. Rules turned off are turned off explicitly and individually — never a blanket
disable to reach zero. The 13 pre-existing unused `eslint-disable` directives are removed.

### Phase 4 — script + CI

`"lint": "eslint ."`. Add the non-blocking `ci.yml` job per Decision 1.

### Phase 5 — propagation sweep

Decision 4's two sites. Grep for the OLD claim, not the new one.

## Guard Contract

### Guard 1 — the lint script is non-interactive and terminates

**Property.** `npm run lint` in `apps/web-platform` completes without waiting on stdin and exits
with a deterministic status, for any working tree state.

**Assembly.** The `lint` script in `package.json` plus the config file it resolves. The chokepoint
is the script definition; the guard asserts the script's first token is `eslint` (never `next`),
because `next lint` is precisely the form that prompts.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Revert `"lint"` to `next lint` | The defect being fixed; a green suite here discriminates nothing |
| 2 | Delete `eslint.config.mjs` | ESLint with no config errors out — the script no longer terminates cleanly |
| 3 | Point the script at a second config path that does not exist | **Guard's own dispatch.** A guard that resolves no config must not report success |
| 4 | Add a `--no-eslintrc`-style flag that silently disables all rules | Config present but inert; the count assertion (Guard 2) must catch it |

**Harness rows.**
- Must-RED: delete the assertion body, leaving the test name and its `expect` count intact → the
  suite must fail rather than pass a test asserting nothing.
- Must-PASS: a config that legitimately reports **non-zero findings** still satisfies Guard 1 —
  terminating with findings is a pass for this property, not a failure.

### Guard 2 — the finding set is pinned

**Property.** The lint run's finding count equals a committed baseline, so a regression or a
silent rule-disable is visible.

**Assembly.** The config's full rule set as applied to the tracked file set — not a sampled
subset. The guard runs ESLint over the same scope CI runs and compares against the baseline.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Blanket-disable a rule class to reach zero | The anti-pattern Decision 3/Phase 3 forbids; the count moves and must be caught |
| 2 | Add a second ignore entry that excludes a linted directory | **Second member after a compliant first** — the guard must quantify over the whole scope, not stop at the first ignore |
| 3 | Widen `ignores` to `**` | **Guard's own dispatch.** Zero files linted must fail, not pass as "zero findings" |
| 4 | Introduce a new violation in a tracked file | The regression case the baseline exists to catch |

**Harness rows.**
- Must-RED: replace the baseline comparison with `expect(count).toBeGreaterThanOrEqual(0)` — a
  predicate any constant satisfies → the suite must fail, proving it discriminates.
- Must-PASS: a file added under an ignored path does not move the count.

**Anti-vacuity floor.** The suite asserts it linted a **minimum file count** (derived from the
as-written config, not a prose estimate), so a run that silently scanned nothing cannot report
"0 findings, all good". This is the ADR-193 floor contract applied to this suite.

## Observability

```yaml
liveness_signal:
  what: "the ci.yml lint job's conclusion on pull requests touching apps/web-platform"
  cadence: "per matching pull request"
  alert_target: "GitHub Actions check status (non-blocking, reported not required)"
  configured_in: ".github/workflows/ci.yml"

error_reporting:
  destination: "GitHub Actions job log (observability layer 5 — CI). This surface runs only on
                GHA runners and emits no SOLEUR_* markers to Better Stack; the load-bearing
                signal is the job conclusion plus ESLint's own stdout."
  fail_loud: true

failure_modes:
  - mode: "ESLint cannot resolve its config"
    detection: "eslint exits non-zero with a config-resolution error; Guard 1 mutation 3"
    alert_route: "lint job reports failure on the PR"
  - mode: "a rule class is silently disabled to reach zero findings"
    detection: "Guard 2 baseline comparison moves"
    alert_route: "the guard suite fails under the required test check"
  - mode: "the config silently lints nothing (over-wide ignores)"
    detection: "Guard 2 anti-vacuity minimum-file-count floor"
    alert_route: "the guard suite fails under the required test check"
  - mode: "the brace-expansion override is reintroduced"
    detection: "AC7 per-line patched-floor assertion plus a brace-glob smoke case"
    alert_route: "the guard suite fails; lockfile-sync also diffs the regenerated lockfile"

logs:
  where: "GitHub Actions job logs"
  retention: "GHA default (90 days)"

discoverability_test:
  command: "bash -c 'cd apps/web-platform && npm run lint'"
  expected_output: "eslint runs to completion and prints its findings summary; exit status is
                    deterministic and the process never waits on stdin"
  credentials_required: "none — no network, no secrets"
```

## Architecture Decision (ADR/C4)

**No new ADR.** This introduces no architectural decision: it replaces one lint invocation with
another inside an already-decided CI surface, and repairs a dependency-resolution defect. Nothing
in the existing ADR corpus is reversed or extended — **ADR-191** governs the lockfile surface and
this change is consistent with it (the lockfile is regenerated under npm@11 and remains gated by
`lockfile-sync`). Decision 1 deliberately does **not** touch the required-status-check ruleset, so
no ruleset ADR is implicated.

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
- **External human actors:** unchanged — no new correspondent, reviewer or recipient.
- **External systems / vendors:** unchanged — no new vendor edge. GitHub Actions is already
  modelled as the CI surface; this adds a job to an existing workflow, not a new integration.
- **Containers / data stores:** unchanged — lint is a build-time step, not a modelled container.
- **Access relationships:** unchanged — no actor gains or loses access to any surface.

## Encryption Posture

**Skipped — detection did not fire.** No persistent store is introduced (no `.tf`, no
`supabase/migrations/*.sql`, no `cloud-init*.yaml`, no `docker-compose*.yaml` in the file lists)
and no new cross-component connection.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** No server, service, secret, vendor account, DNS record or
persistent runtime process. The only workflow change adds a job to an existing `ci.yml`.

## GDPR / Compliance

**Skipped.** The canonical regulated-surface regex does not match — no schema, migration, auth
flow, API route or `.sql` file. None of the (a)–(d) expansion triggers fire: no LLM/external-API
processing of operator data, threshold is `none`, no cron reads knowledge-base artifacts, and no
new artifact-distribution surface.

## Domain Review

**Domains relevant:** engineering

The 8-domain sweep finds no user-facing surface, pricing or positioning implication, legal
document change, revenue or pipeline effect, and no support-facing change. Developer tooling only.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire — no path in Files to
Create/Edit matches the UI-surface term list or glob superset (`package.json`, a lockfile, an
`.mjs` config, a `.test.ts`, a workflow, a `SKILL.md`, a learning file). Product tier **NONE**.

**Agents invoked:** none — see Constraint note below
**Skipped specialists:** none required at tier NONE
**Pencil available:** N/A (no UI surface)

### Constraint note

This plan was produced without subagents. `wg-zero-agents-until-user-confirms` and this session's
standing instruction bar agent spawns, so the Phase 1 research fan-out, the Phase 2.5 domain
leaders, the Phase 4.5 advisor consult and the `plan-review` panel were all executed inline by the
planning session instead. What that costs is independent adversarial review — every finding here
comes from one perspective. The Guard Contract's mutation matrices are the compensating control,
and a review panel should be run before merge if agent spawning is authorised.

## Acceptance Criteria

1. `grep -c 'next lint' apps/web-platform/package.json` returns `0`.
2. `apps/web-platform/eslint.config.mjs` exists and is loaded by a bare `eslint .` from that
   directory (no `--config` flag needed).
3. `cd apps/web-platform && npm run lint` completes non-interactively with a deterministic exit
   status, with stdin closed (`</dev/null`) to prove it never prompts.
4. The finding count equals the committed baseline, and that baseline is a real number derived
   from the as-written config — not a prose estimate.
5. `npm ci --ignore-scripts` succeeds in `apps/web-platform` from the regenerated lockfile.
6. A brace glob (`"**/*.{ts,tsx}"`) in the config does **not** crash ESLint — the
   `TypeError: expand is not a function` failure is gone.
7. Every resolved `brace-expansion` in `apps/web-platform/package-lock.json` is at or above its
   own major line's patched floor (1.1.12 / 2.0.2 / 3.0.1 / 4.0.1). Asserted per line, not in
   aggregate — an aggregate check passes while one line sits below its floor.
8. `rimraf`'s `minimatch@9` resolves a `brace-expansion@2.x`, proving the fix is not scoped only
   to the ESLint stack.
9. Guard 1 and Guard 2 mutation matrices each drive the suite RED for every listed row, and the
   unmutated control is GREEN. Rows that survive are labelled either "fixture gap" or "equivalent
   mutant" — never left unlabelled.
10. The `ci.yml` lint job exists, runs on pull requests touching `apps/web-platform`, and is
    **absent** from `scripts/required-checks.txt` and the required-status-check ruleset JSON.
11. `plugins/soleur/skills/work/SKILL.md` no longer asserts there is no eslint config or that
    `npm run lint` is non-functional; its replacement text matches what actually ships.
12. The 2026-06-05 learning file carries `## Addendum — 2026-08-19 (#1327)` and its original body
    is byte-identical to `origin/main`.
13. `bash scripts/lint-dual-lockfile.sh` still passes (no `bun.lock` reintroduced) and
    `lockfile-sync`'s regeneration of all four lockfiles is byte-identical.
14. `TEST_GROUP=webplat bash scripts/test-all.sh` passes, and the shards the diff touches are
    named explicitly when the gate is reported green.
15. `Closes #1327` appears in the PR body. #7594 is referenced as unblocked but **not** closed.

## Test Scenarios

| # | Test | Fixture | Asserts |
|---|---|---|---|
| T1 | Lint script is non-interactive | `npm run lint </dev/null` | terminates; never blocks on stdin |
| T2 | Config resolves without an explicit flag | bare `eslint .` | the config file is discovered |
| T3 | Finding count matches baseline | the tracked tree | count equals the committed number |
| T4 | Brace glob does not crash | a config using `**/*.{ts,tsx}` | no `expand is not a function` |
| T5 | Per-line patched floors | the regenerated lockfile | every `brace-expansion` ≥ its line's floor |
| T6 | Anti-vacuity floor | a config with `ignores: ["**"]` | the suite FAILS rather than reporting zero findings |
| T7 | Ignored paths do not move the count | a new file under an ignored dir | count unchanged |
| T8 | Rule disable is visible | one rule flipped to `off` | count moves; guard catches it |

Fixtures synthesized per `cq-test-fixtures-synthesized-only`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Removing the override regresses the CVE remediation | AC7 asserts per-line patched floors; if any line falls short the remedy is a **scoped** override, the shape the repo root already uses |
| The regenerated lockfile churns widely | `npm ci --ignore-scripts` (AC5) plus `lockfile-sync`'s byte-identical regeneration (AC13) bound it |
| A first-run lint job creates noise on unrelated PRs | Decision 1 keeps it non-blocking and off the required-check list |
| The baseline count is stale by merge time | Re-derive it at implementation exit rather than trusting this plan's figure; the plan's ~195 is a Phase 0 input, not an AC value |
| No adversarial review panel ran | Guard Contract mutation matrices are the compensating control; flagged in Domain Review |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Run the `next-lint-to-eslint-cli` codemod | Nothing to convert — zero eslintrc files exist |
| Remove `eslint-config-next` per the issue's step 4 | It supplies the parser and all five plugins; removing it removes every rule source |
| Brace-free globs + a guard forbidding brace patterns | Leaves `rimraf`'s minimatch@9 broken and polices a self-inflicted constraint instead of removing it |
| File the `brace-expansion` defect as a separate issue | It hard-blocks this PR's own acceptance criteria and is 2 files — inside the cost-of-filing threshold |
| Make the lint job a required check now | Merge-blocking on a first-run baseline of ~195 findings across a never-linted codebase |
| Bundle the Next 15→16 upgrade | Out of scope; #7594 stays open and this PR only removes its stated blocker |
