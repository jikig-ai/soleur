---
title: "feat: property-based testing adoption for soleur monorepo (Epic #10397 child 1)"
type: feat
date: 2026-10-19
slug: property-based-testing-adoption
branch: feat-one-shot-10398-property-based-testing
issue: 10398
closes: 10398
lane: single-domain
---

# feat: property-based testing adoption for soleur monorepo

## Overview

Adopt property-based testing in the soleur monorepo (Epic #10397 child 1, issue #10398). Add `fast-check` to `apps/web-platform` devDependencies, ship four property suites covering the round-trip, invariant, and idempotency classes against existing pure functions, land a seeded generated-input harness for the `.test.sh` shell corpus with one reference suite and a documented pattern, and verify the new suites are reached by the repo's affected-suite selection machinery. Scope is deliberately small per the issue ("start small — do not boil the ocean"): no mass rollout, no SUT changes, no CI workflow edits.

## Research Insights

### Premise Validation (Phase 0.6)

- `git grep -l fast-check origin/main` → **zero hits** (verified 2026-10-19). Issue claim holds.
- `git grep -l "property-based\|fast_check\|fc\.assert" origin/main` → 2 prose hits (`apps/web-platform/server/abort-classifier.ts`, one archived plan) — no property-testing machinery anywhere. Issue claim holds.
- `scripts/ci-pr-selection.sh` exists on `origin/main` (444 lines) — but it is the *driver* of the `pr-selection` job, not the affected-suite registry. It calls `scripts/test-all.sh --print-selection` / `--enumerate-commands`; suite membership lives in `scripts/test-all.sh` (`SUITE_GLOBS` at lines 96-109, `run_suite` chokepoint) and in `apps/web-platform` vitest project config + `vitest related` narrowing (`apps/web-platform/scripts/vitest-related.sh`). See Research Reconciliation below.
- `.test.sh` corpus: 715 shell suites, registered via `SUITE_GLOBS` (`plugins/soleur/test/`, `plugins/soleur/skills/*/test/`, `plugins/soleur/scripts/`, `.claude/hooks/`, `.claude/hooks/lib/`, `apps/cla-evidence/scripts/`, `apps/web-platform/scripts/`, `apps/web-platform/scripts/lib/`, `scripts/lib/`) plus explicit `run_suite` lines. Repo-root `scripts/*.test.sh` is deliberately NOT globbed (`scripts/test-all.sh:6707` — "an unregistered suite runs in zero runners and stays green forever").
- `apps/web-platform` uses vitest 4.x (`"vitest": "^4.1.11"`, `"test:ci": "vitest run"`), `unit` project includes `test/**/*.test.ts` + `lib/**/*.test.ts` (`vitest.config.ts:87`), placement convention is `test/<area>/` mirroring the SUT (`test/README.md` §"Test file placement").
- Prior generated-input art: `test/server/inngest/cron-community-publication.test.ts` (mulberry32 "deterministic fuzz"), `test/rls-fuzz/` (randomUUID-driven authz fuzz). Generated inputs exist; a property library with arbitraries + shrinking does not. The premise "no property-based testing" holds; the plan acknowledges the seeded-PRNG precedent and adopts it as the shell-side model.
- Epic #10397 is OPEN; #10398 is OPEN and unblocked. Milestone "Post-MVP / Later" — consistent with a tight, non-boiling scope.

### Property List (Phase 0.6b)

The asks, restated as observable properties:

1. A real property-testing library (arbitraries, shrinking, seed replay) is usable from the vitest suite in `apps/web-platform`.
2. At least three property suites exist covering round-trip, invariant, and idempotency classes against real pure functions.
3. A documented, repeatable pattern exists for adding generated-input (property-style) cases to `.test.sh` shell suites, including a reproducibility story (seeded) and a regression-fixture convention for found counterexamples.
4. The new suites actually run in CI under the existing affected-selection machinery — no orphan registrations.
5. Counterexamples found by the harness are preserved as permanent regression fixtures.

### Cut List (Phase 0.6b)

- **Custom TS property runner** — property 1 is fully bought by `fast-check` (npm 4.10.2, node >=12.17, zero peer deps, framework-agnostic `fc.assert`). Cut: do not build one.
- **Edits to `scripts/ci-pr-selection.sh`** — its stage-2 consumer reads the `test-all.sh` enumerate stream generically; suite membership derives from registration, not from ci-pr-selection internals. Cut: zero edits there (verified below — the file needs no per-suite knowledge).
- **Edits to `scripts/test-all.sh`** — placing the shell suite under `scripts/lib/` makes glob presence the registration; a `run_suite` line is unnecessary and editing the runner hits the ci-pr-selection TRIGGER LIST (`is_trigger_path` covers `scripts/test-all.sh`). Cut.
- **Property-testing the SQL twin of `normalizeRepoUrl`** — `repo-url-sql-parity.test.ts` already covers parity; extending PBT into Postgres is out of the stated scope. Deferred (see Non-Goals).
- **Installing the community `@trailofbits/skills/property-based-testing` plugin** — registry search found it (covers fast-check conventions + shrunk-counterexample triage). Not needed to satisfy the ACs; acquisition is a scope decision persisted to `decision-challenges.md`. Cut from this plan.

### Repo Research

- Round-trip SUT: `apps/web-platform/server/codex-app-server-jsonl.ts` — `encodeCodexJsonl` / `decodeCodexJsonlLine` / `decodeCodexJsonlStream` (pure; closed error-code taxonomy `codex_rpc_frame_invalid|codex_rpc_frame_too_large`; 1 MiB frame bound `MAX_CODEX_FRAME_BYTES`).
- Invariant SUT: `apps/web-platform/lib/plan-limits.ts` — `effectiveCap` (raise-only), `nextTier` (ladder), `PLAN_LIMITS`, `PLATFORM_HARD_CAP`.
- Idempotency SUTs: `apps/web-platform/lib/repo-url.ts` — `normalizeRepoUrl` (header documents idempotency intent + coupling to `supabase/migrations/031_normalize_repo_url.sql`); `apps/web-platform/lib/log-sanitize.ts` — `sanitizeForLog` (strip set + length cap).
- Shell SUT: `scripts/lib/legal-normalise.sh` — `collapse` (deterministic `sed|awk|awk` cross-normaliser; header explains the one-definition-site rationale that also justifies a shared property-harness lib).
- Affected-selection machinery: `run_suite`/`_suite_affected` (`scripts/test-all.sh:1697`, classify rungs at ~2711-2735: group > always_on > edge:consumed > edge:declared > edge:derived > unclassified-selects-anyway); `vitest related` narrowing in `apps/web-platform/scripts/vitest-related.sh` (falls back to full project on empty/zero-resolution — fail-safe).
- Shell-test conventions: `.claude/hooks/README.md` (hook contract doc), `scripts/lib/*.test.sh` glob = presence registration; direct-execution guard convention for sourced libs (see `legal-normalise.sh:28-33`).

### Learnings / Conventions Applied

- `test/README.md` §"Test file placement": new tests under `test/<area>/`, not flat `test/` root.
- `cq-before-pushing-package-json-changes`: deps go in the app-level `package.json`; `package-lock.json` regenerated via `npx --yes npm@11 install --package-lock-only` (npm@11 pin; ADR-191 — npm is the only lockfile of record; `scripts/lint-dual-lockfile.sh` fails on any `bun.lock`).
- `lint-workflow-install-sites.sh`: install sites use `--ignore-scripts`.
- `scripts/test-all.sh:6707`: never add a shell suite outside `SUITE_GLOBS` without an explicit `run_suite` — an unregistered suite stays green forever.
- `cq-test-fixtures-synthesized-only`: generated fixtures are synthesized in-suite (no captured production data).
- fast-check verified: `npm view fast-check` → 4.10.2, engines node >=12.17, no peerDependencies — compatible with vitest 4.x projects (2026-10-19).
- External convention source: `@trailofbits/skills/property-based-testing` SKILL.md (property catalog — roundtrip/inverse/oracle/idempotence/invariant; strength ordering "no crash → type preservation → invariant → idempotence → roundtrip/oracle"; tautology + vacuity anti-patterns). Fetched 2026-10-19 for vocabulary; not installed.

### Community Discovery (Phase 1.5/1.5b)

- Stack check: TypeScript + bash only — no uncovered stacks (flutter/rust/elixir/go/swift/kotlin/php signatures absent). agent-finder skipped.
- Functional overlap: registry search (`api.claude-plugins.dev`, `claudepluginhub.com`, official marketplace) found `@trailofbits/skills/property-based-testing` (1.2.2; covers Hypothesis/fast-check/proptest) and `@jeremylongshore/.../property-based-test-helper`. Neither is installed — adoption decision deferred to `decision-challenges.md` (headless pipeline cannot prompt; the feature's goal is met by fast-check alone).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "CI runs them in the affected-suite selection (`ci-pr-selection.sh`)" | `ci-pr-selection.sh` holds no per-suite knowledge; it consumes `test-all.sh --print-selection`/`--enumerate-commands`. Membership derives from `SUITE_GLOBS`/`run_suite` registrations + `vitest related` import-graph narrowing. | Wire by *placement*: vitest suites under `test/**/*.test.ts` (unit project) auto-select when their SUT changes; the shell suite under `scripts/lib/` registers by glob presence and derives edges from its `source` closure. Zero edits to `ci-pr-selection.sh` and `test-all.sh`; AC asserts selection empirically (AC9). |
| "no property-based testing anywhere" | True for libraries, but `mulberry32` deterministic fuzz exists in `test/server/inngest/cron-community-publication.test.ts` and `test/rls-fuzz/` does generated-input authz fuzz. | Cite both as prior art; the shell harness formalizes the seeded-PRNG idiom they hand-rolled. |
| "target ~3 pure functions first: a parser, a formatter, a pricing/serialization util" | `codex-app-server-jsonl` (serialization), `plan-limits` (pricing/limits), `repo-url` (parser/normalizer) + `log-sanitize` (formatter-class bonus) are all pure and importable by `test/` vitest files. | Four suites: the three AC classes plus a second idempotency subject — all chosen for *strong* properties (round-trip/idempotence/invariant), not "no crash". |

## Open Code-Review Overlap

Checked 2026-10-19 (`gh issue list --label code-review --state open`, bodies scanned for every planned path):

- **#8659** "review: 33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs" — mentions `scripts/test-all.sh`. **Acknowledge:** unrelated concern (test-helpers trap composition); this plan does not edit `test-all.sh` or `test-helpers`.
- **#7942** "Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate" — mentions `scripts/test-all.sh`. **Acknowledge:** the same "registered nowhere" class this plan deliberately avoids by placing the shell suite under the `scripts/lib/*.test.sh` glob; different file set, not folded in.

No other open scope-outs touch the planned files.

## Problem Statement

Every test in the repo is example-based: each asserts one hand-picked point of an input domain. Two hand-rolled generated-input suites exist (`mulberry32` fuzz, RLS fuzz) but neither shrinks counterexamples, neither uses declarative arbitraries, and neither is a repeatable *pattern* other suites can adopt — the epic audit (#10397) measured this as a gap against the agentic-verification practice of letting a generator hunt for the "must never happen" violation. The fix is not more examples; it is an oracle class: round-trip, invariant, and idempotence properties the generator tries to falsify across the whole domain.

## Proposed Solution

1. **Vitest side:** adopt `fast-check` (the standard JS/TS property library; arbitraries + integrated shrinking + seed replay) as a devDependency in `apps/web-platform`, and write `*.property.test.ts` suites under `test/<area>/` mirroring SUT paths. They run in the existing `unit` project with zero config changes; `vitest related` selects them when their SUT's import graph changes.
2. **Shell side:** a small sourced helper `scripts/lib/property-harness.sh` (seeded `RANDOM` loop + `prop_pick`/`prop_fail`/`prop_pass` reporting + `PROP_SEED` replay), a canonical pattern doc `scripts/lib/property-harness.md`, a pointer in `.claude/hooks/README.md`, and one reference suite `scripts/lib/legal-normalise-property.test.sh` asserting `collapse` idempotence + residue-freedom over generated legal-doc-shaped inputs.
3. **Record the convention** in `apps/web-platform/test/README.md` (placement + regression-fixture convention) and in a new ADR (property-based testing as a sanctioned third test class).

## Technical Approach

### Architecture

```text
Vitest arm (apps/web-platform)
  test/server/codex-app-server-jsonl.property.test.ts ─┐
  test/lib/plan-limits.property.test.ts                ├─ unit project (test/**/*.test.ts)
  test/lib/repo-url.property.test.ts                   │   → test-webplat CI leg
  test/lib/log-sanitize.property.test.ts               ┘   → `vitest related` narrowing on SUT diffs
        fast-check devDep (npm, package-lock, --ignore-scripts, npm@11 lock regen)

Shell arm (repo tooling)
  scripts/lib/property-harness.sh          ← sourced lib (direct-exec guard), PRNG + report API
  scripts/lib/property-harness.md          ← pattern doc (seed, generators, fixtures, failure triage)
  scripts/lib/legal-normalise-property.test.sh ← reference suite (scripts/lib/*.test.sh glob = registration)
  .claude/hooks/README.md                  ← pointer paragraph (README/AGENTS pointer per AC)
```

### Implementation Phases

#### Phase 1: Dependency + shell harness foundation

- `cd apps/web-platform && npm install --ignore-scripts --save-dev fast-check@^4.10.2`
- Regenerate lockfile per repo convention: `cd apps/web-platform && npx --yes npm@11 install --package-lock-only`
- Write `scripts/lib/property-harness.sh`: `prop_init` (seeds `RANDOM`; `PROP_SEED` env override; prints `PROP_SEED=<n>`), `prop_rand <n>` (`$RANDOM`-uniform), `prop_pick <items...>` (echo one), `prop_fail <label> <detail>` (prints `PROP_FAIL <label> seed=<s> iter=<i> <detail>`, exits 1), `prop_pass <label> <runs>` (prints `PROP_PASS <label> runs=<n> seed=<s>`); `#!/usr/bin/env bash`, `set -u` (NOT `-e` — it is a sourced lib), direct-execution guard + double-source guard mirroring `legal-normalise.sh`, bash-3.2-safe (no `declare -A`/namerefs), `LC_ALL=C` at source like the SUT it serves.
- Write `scripts/lib/property-harness.md`: the pattern — seeded input loop, generator functions over a token alphabet, property shapes for shell (round-trip = emit→parse, idempotence = transform twice, invariant = output contract per iteration), `PROP_SEED` replay, the regression-fixture convention (a found counterexample is saved into the suite as a pinned named case), failure triage (wrong property vs real bug — cite the ToB catalog).
- Success criteria: `bash -c 'source scripts/lib/property-harness.sh && prop_init t && prop_pass t 1'` prints `PROP_PASS`; two runs with `PROP_SEED=42` produce identical streams.

#### Phase 2: Vitest property suites (4 files)

- `test/server/codex-app-server-jsonl.property.test.ts` — **round-trip class**:
  - `decodeCodexJsonlLine(encodeCodexJsonl(m))` deep-equals `m` for `fc.jsonObject()`-generated objects (object arbs are size-bounded so serialized frames stay well under `MAX_CODEX_FRAME_BYTES`; the >1 MiB path is the separate example `it`).
  - `decodeCodexJsonlStream` over `concat(encode(m₁..mₙ))` split at arbitrary string offsets into arbitrary chunks yields `[m₁..mₙ]` in order (chunking-invariance; buffer is string-append so mid-codepoint splits reassemble losslessly).
  - Rejection: `fc.oneof(fc.array(...), fc.constant(null), fc.string())` non-object inputs → `encodeCodexJsonl` throws `codex_rpc_frame_invalid`; arbitrary non-JSON/blank/non-object lines → `decodeCodexJsonlLine` throws.
  - One `it` example (not a property): a message serializing > `MAX_CODEX_FRAME_BYTES` throws `codex_rpc_frame_too_large` (generation to the bound is deliberately an example — property-driving to 1 MiB wastes CI time).
- `test/lib/plan-limits.property.test.ts` — **invariant class**:
  - `effectiveCap(tier, override) ∈ {PLAN_LIMITS[tier ?? free], override}` and `≥ base` (raise-only never demotes).
  - `effectiveCap` is monotone non-decreasing in `override`.
  - `nextTier` climbs `TIER_LADDER` strictly (index +1) and returns `null` only at the top; `PLAN_LIMITS[nextTier(t)] ≥ PLAN_LIMITS[t]`.
  - Every `PLAN_LIMITS[t]` for `t ≠ enterprise` is `≤ PLATFORM_HARD_CAP`.
- `test/lib/repo-url.property.test.ts` — **idempotency class**:
  - `normalizeRepoUrl(normalizeRepoUrl(x)) === normalizeRepoUrl(x)` over `fc.string()` and structured URL-ish arbs (`fc.webUrl()` + suffix perturbations `.git`, `.GIT`, `/`, `.git/`, `.git.git`).
  - Output contract: equals its own `trim()`, never ends in `/` or `(\.git)+$` (case-insensitive) when non-empty.
  - For URL-parseable inputs: scheme+host lowercased, path case preserved.
- `test/lib/log-sanitize.property.test.ts` — **idempotency class**:
  - `sanitizeForLog(sanitizeForLog(x, n), n) === sanitizeForLog(x, n)` for arbitrary `x`, `n ∈ int(0, 2000)`.
  - Output invariants: `length ≤ n`; contains no `[\x00-\x1f\x7f\u2028\u2029]`.
- Each file: one `describe` per property; `fc.assert(fc.property(arb, pred))` with default `numRuns` (100) unless a property justifies more; one negative-control `it` per file — `expect(() => fc.assert(fc.property(arb, () => false))).toThrow()` — proving the harness actually detects violations (anti-vacuity).
- File headers carry the convention: on failure, shrink → save the counterexample as a permanent `it()` fixture labelled `// regression fixture: fast-check seed <seed> path <path>`.
- Update `apps/web-platform/test/README.md` — "Property-based tests" section: naming `test/<area>/<subject>.property.test.ts`, the classes, fixture convention, link to `scripts/lib/property-harness.md`.
- Success criteria: `cd apps/web-platform && npx vitest run --project unit test/server/codex-app-server-jsonl.property.test.ts test/lib/plan-limits.property.test.ts test/lib/repo-url.property.test.ts test/lib/log-sanitize.property.test.ts` exits 0.

#### Phase 3: Shell reference suite + doc pointers

- `scripts/lib/legal-normalise-property.test.sh`: sources `legal-normalise.sh` + `property-harness.sh`; generates docs from a token alphabet (all `collapse` LHS link forms, template vars `{{ stats.* }}`/`{{ agents.departmentList }}`, `[0-9]+ AI agents`/`skills` counters, `across <word> domains`, dept lists, blank-line runs 0–5, free-text lines); asserts per generated doc (a) `collapse(collapse(d)) == collapse(d)` and (b) collapsed output matches none of the LHS regexes (residue-free). Default `PROP_RUNS=100`, env-overridable.
- `.claude/hooks/README.md`: add a "Property tests" pointer paragraph naming `scripts/lib/property-harness.md` + the reference suite (satisfies the README/AGENTS-pointer AC).
- Success criteria: `bash scripts/lib/legal-normalise-property.test.sh` exits 0, prints `PROP_PASS` lines; `PROP_SEED=<n>` makes runs reproducible.

#### Phase 4: Selection verification (no CI edits)

- Prove vitest-side selection: `WEBPLAT_RELATED` containing `server/codex-app-server-jsonl.ts` → `bash apps/web-platform/scripts/vitest-related.sh unit` reports `outcome=related` and runs the property file.
- Prove shell-side registration + edge derivation: `bash scripts/test-all.sh --print-affected-set` lists `scripts/lib/legal-normalise-property.test.sh` with an `edge:` class (derived via its `source scripts/lib/legal-normalise.sh`); a fabricated diff touching `scripts/lib/legal-normalise.sh` selects it under `--print-selection` (or `--affected` on a fixture repo, matching `test-all-affected.test.sh` conventions).
- `bash scripts/lint-orphan-test-suites.sh` stays green (glob presence = registration).
- Success criteria: all three probes pass; no edit to `scripts/ci-pr-selection.sh`, `scripts/test-all.sh`, or `.github/workflows/*.yml`.

#### Phase 5: Decision record

- Author `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` (provisional ordinal — ship re-verifies next-free against `origin/main`; if renumbered, sweep `grep -rn 'ADR-293' knowledge-base/project/{plans,specs}/feat-one-shot-10398-property-based-testing/`): decision "property-based testing is a third sanctioned test class — fast-check for vitest `unit`, seeded-loop `property-harness.sh` for `.test.sh`", alternatives (example-only status quo, per-suite hand-rolled PRNG, install ToB community plugin).
- No C4 edit (see Architecture Decision section).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Hand-rolled seeded PRNG in TS (mulberry32 precedent) | Duplicates fast-check's arbitraries + shrinking poorly; the point of the audit gap is the oracle + shrink machinery, not random inputs. The mulberry32 pattern IS adopted — on the shell side where no dep is acceptable. |
| Property-test *everything* (broad rollout) | Issue says "start small — do not boil the ocean". Four vitest suites + one shell suite establishes the pattern with real oracles. |
| Install `@trailofbits/skills/property-based-testing` community plugin | Adds a plugin-acquisition decision orthogonal to the AC; the reference doc + ADR carry the needed conventions. Deferred — persisted to `decision-challenges.md` as an `operator (scope)` item. |
| Edit `ci-pr-selection.sh` / `test-all.sh` to "wire" the suites | No per-suite knowledge lives in either file; placement achieves wiring. Editing `test-all.sh` also trips the trigger list, forcing full batteries on unrelated doc-only PRs' stage-2 path. |
| Property-testing `normalizeRepoUrl`'s SQL twin | `repo-url-sql-parity.test.ts` already owns the parity property; extending PBT into Postgres is a separate scope (deferred — see Future Considerations). |
| Put the shell suite under `.claude/hooks/` | `collapse` is a `scripts/lib` function, not a hook; the glob covers both, and `scripts/lib/` keeps suite beside SUT. The doc pattern explicitly covers hook suites. |

**Deferred items (tracking):** none material enough for a standalone issue in this PR; the community-plugin install and SQL-side PBT are recorded in `decision-challenges.md`/Future Considerations rather than filed issues (re-evaluation: after this lands, epic #10397 children #10400/#10404 reconsider the plugin-shipping path anyway).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is a flaky-red or silently-absent test suite inside Soleur's own CI, i.e. contributors see a red leg or a coverage gap, not a product defect.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — all subjects are pure functions over synthesized inputs; `fast-check` is a devDependency never shipped to the plugin or the deployed app.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is test machinery + docs only — no runtime path, credential, user data, or production surface is touched, so the next tier (`single-user incident`) does not apply.

## Observability

The deliverable is verification machinery; its "liveness" is registration + selection, not a runtime signal. A silently-unregistered suite is the failure mode (`scripts/test-all.sh:6707` documents it).

```yaml
liveness_signal:
  what:            # property suites execute in their CI legs (test-webplat unit project; test-scripts scripts/lib glob)
  cadence:         # per-PR via affected selection; every full run otherwise
  alert_target:    # red CI leg on the PR
  configured_in:   # apps/web-platform/vitest.config.ts (unit include); scripts/test-all.sh SUITE_GLOBS entry scripts/lib/*.test.sh
error_reporting:
  destination:     # vitest/suite stderr on the PR leg
  fail_loud:       # a red vitest file or a red .test.sh fails its leg; PROP_FAIL line names seed+iteration
failure_modes:
  - mode:          # suite file exists but is never registered (renamed off the glob/include)
    detection:     # scripts/lint-orphan-test-suites.sh (.test.sh side); repo-wide-containment + vitest related fail-safe full run (vitest side)
    alert_route:   # red lint/test leg on the PR
  - mode:          # property runs zero cases (vacuous generator)
    detection:     # per-file negative-control `it` asserting a deliberately-false property throws; PROP_PASS prints run counts
    alert_route:   # red leg on the PR
  - mode:          # property finds a counterexample on the current SUT
    detection:     # fast-check shrink report (seed+path) / PROP_FAIL seed+iter
    alert_route:   # red leg on the PR — the suite working as designed
logs:
  where:           # CI leg stdout (vitest reporter; suite PROP_* markers)
  retention:       # GitHub Actions run retention (90 days)
discoverability_test:
  command: grep -rl 'fast-check' apps/web-platform/test
  expected_output: apps/web-platform/test/lib/repo-url.property.test.ts
```

## Architecture Decision (ADR/C4)

### ADR

- Create `ADR-293-property-based-testing-adoption` (provisional ordinal; highest on `origin/main` at plan time is ADR-292). One-line decision: property-based testing is a sanctioned third test class — `fast-check` for vitest `unit`, seeded-loop `property-harness.sh` for `.test.sh` suites — with `*.property.test.ts` placement and the shrunk-counterexample fixture convention. Authored in Phase 5 via the `soleur:architecture` conventions; status `adopting` is acceptable at merge (soak is the suites living in CI).

### C4 views

No C4 impact — verified against all three model files (`model.c4`, `views.c4`, `spec.c4`) on 2026-10-19:

- **External human actors:** none new — the diff serves existing contributors/CI only (`untrusted contributor`, `founder` already modeled).
- **External systems/vendors:** none new — `fast-check` is a devDependency fetched through the same npm install path every existing devDep (vitest, happy-dom) already uses; npm-registry-as-install-source is not a modeled element for any devDep.
- **Containers/data stores touched:** none — test files, a sourced shell lib, docs, and a devDep manifest line; no container, store, or deployed component changes.
- **Actor↔surface access relationships changed:** none — no boundary, trust, or access change.

### Sequencing

The ADR is authored in this PR (Phase 5), not deferred — the convention is true once the suites land.

## Guard Contract

### Guard 1 — property suites falsify their SUT on violation

**Property.** Each property suite fails red when its subject violates the named property class, and never passes while running zero cases.

**Assembly.** Every `fc.assert` in `test/server/codex-app-server-jsonl.property.test.ts`, `test/lib/plan-limits.property.test.ts`, `test/lib/repo-url.property.test.ts`, `test/lib/log-sanitize.property.test.ts`, plus every `prop_*`-driven assertion in `scripts/lib/legal-normalise-property.test.sh`. Dispatch chokepoints: the `unit` project's `test/**/*.test.ts` include in `vitest.config.ts` and `vitest related` narrowing in `apps/web-platform/scripts/vitest-related.sh` (vitest arm); the `scripts/lib/*.test.sh` `SUITE_GLOBS` entry → `run_suite "$f"` loop in `scripts/test-all.sh` (shell arm). Two chokepoints, one per arm — both named.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `\.git` strip from `normalizeRepoUrl` (`lib/repo-url.ts`) | RED — idempotency fails on `.git.git`-class inputs |
| 2 | `effectiveCap` returns `override` unconditionally (`lib/plan-limits.ts`) | RED — raise-only invariant fails for `override < base` |
| 3 | `encodeCodexJsonl` drops its trailing `\n` (`server/codex-app-server-jsonl.ts`) | RED — stream reassembly yields wrong framing |
| 4 | Own-dispatch: set `numRuns: 0` (or replace an arbitrary with `fc.constant` over one passing value) in any suite | RED — the file's negative-control `it` (`fc.assert(prop(false))` must throw) plus a `numRuns>0` floor assertion catches a suite that can never fail |
| 5 | Second-member: add a second `.test.sh` suite under `scripts/lib/` after the reference suite | RED if the glob/`run_suite` loop stopped at the first member — both register (glob iterates every match, AC9 probe counts ≥1 for each) |
| 6 | Reorder: in `decodeCodexJsonlStream`, emit buffered tail before in-loop frames | RED — chunking-invariance property observes out-of-order yield |
| 7 | Harness: delete all `it`/`test` blocks from a property file | RED — vitest fails a suite file with zero tests |
| 8 | Harness: edit `collapse` so one RHS contains another rule's LHS (e.g., emit `(privacy-policy.md)`) | RED — shell idempotency property fails on any input reaching that RHS |
| 9 | Must-PASS: `https://GitHub.com/OWNER/Repo.git/` (mixed-case scheme/host, `.git` + slash, cased path) through `normalizeRepoUrl` | PASS — normalization, not rejection, is the contract |

### Guard 2 — suite-registration integrity

**Property.** Every property suite file lands inside its arm's registration chokepoint — a suite that runs nowhere cannot stay green.

**Assembly.** `apps/web-platform/vitest.config.ts` `unit` include `test/**/*.test.ts`; `scripts/test-all.sh` `SUITE_GLOBS` entry `scripts/lib/*.test.sh` + `lint-orphan-test-suites.sh` census; `test-all.sh --print-affected-set` receipts.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename `legal-normalise-property.test.sh` to `legal-normalise-property.sh` | RED — orphan lint flags an unregistered suite file |
| 2 | Own-dispatch: run `--print-affected-set` with the suite file absent | RED — AC9's presence assertion finds no `edge:` receipt for the label |
| 3 | Second-member: add `scripts/lib/other-property.test.sh`; diff touches only `legal-normalise.sh` | PASS for the other suite's derived class (each suite derives its own edges — Guard is per-member, not net-count) |
| 4 | Harness: drop the `source scripts/lib/legal-normalise.sh` line from the reference suite | RED on next `legal-normalise.sh` diff — its derived edge disappears and `--print-selection` no longer selects it |

## Files to Create

- `apps/web-platform/test/server/codex-app-server-jsonl.property.test.ts`
- `apps/web-platform/test/lib/plan-limits.property.test.ts`
- `apps/web-platform/test/lib/repo-url.property.test.ts`
- `apps/web-platform/test/lib/log-sanitize.property.test.ts`
- `scripts/lib/property-harness.sh`
- `scripts/lib/property-harness.md`
- `scripts/lib/legal-normalise-property.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` (provisional ordinal)

## Files to Edit

- `apps/web-platform/package.json` (+1 devDependencies line: `fast-check`)
- `apps/web-platform/package-lock.json` (regenerate via `npx --yes npm@11 install --package-lock-only`)
- `apps/web-platform/test/README.md` (+ "Property-based tests" section)
- `.claude/hooks/README.md` (+ pointer paragraph to `scripts/lib/property-harness.md`)

Explicitly **not** edited: `scripts/ci-pr-selection.sh`, `scripts/test-all.sh`, `apps/web-platform/vitest.config.ts`, `apps/web-platform/scripts/vitest-related.sh`, `.github/workflows/*`, `supabase/migrations/*`, and every SUT (`lib/repo-url.ts`, `lib/plan-limits.ts`, `lib/log-sanitize.ts`, `server/codex-app-server-jsonl.ts`, `scripts/lib/legal-normalise.sh`). A SUT edit enters scope only if a property exposes a real defect — disposition per Risk table.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Adopt `fast-check` for vitest (target ~3 pure functions first: a parser, a formatter, a pricing/serialization util)" | Phase 1 devDep + Phase 2 four suites (`codex-app-server-jsonl` serialization, `repo-url` parser/normalizer, `plan-limits` pricing/limits, `log-sanitize` formatter-class) | mapped |
| 2 | "define a property-harness pattern for `.test.sh` suites (e.g., generated-input loops over hook contracts)" | `scripts/lib/property-harness.sh` + `property-harness.md` + `legal-normalise-property.test.sh` reference suite | mapped |
| 3 | "Save minimized failing cases as regression fixtures." | Per-file regression-fixture convention (Phase 2 headers) + `property-harness.md` §fixtures + `test/README.md` section | mapped |
| 4 | "fast-check in `apps/web-platform` devDeps with ≥3 property suites (round-trip, invariant, idempotency classes)." | Phase 1 + Phase 2; AC1–AC6 | mapped |
| 5 | "Documented pattern in a README/AGENTS pointer for adding property tests to shell hook suites." | `scripts/lib/property-harness.md` + `.claude/hooks/README.md` pointer paragraph; AC8/AC10 | mapped |
| 6 | "CI runs them in the affected-suite selection (`ci-pr-selection.sh`)." | Phase 4 placement-verified selection (vitest `unit` + `vitest related`; `scripts/lib` glob + derived edges); AC9 | mapped |
| 7 | "Start small per the article — do not boil the ocean." | Scope constraint: 4 vitest suites + 1 shell suite; no mass rollout; AC14 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `fast-check` devDep | "Adopt `fast-check` for vitest" | asked |
| 4 `*.property.test.ts` suites | "≥3 property suites (round-trip, invariant, idempotency classes)" + "~3 pure functions first: a parser, a formatter, a pricing/serialization util" | asked (4th = `log-sanitize`, a second idempotency subject covering the same AC class) |
| `scripts/lib/property-harness.sh` + `.md` | "define a property-harness pattern for `.test.sh` suites" | asked |
| `scripts/lib/legal-normalise-property.test.sh` | "define a property-harness pattern ... (e.g., generated-input loops over hook contracts)" — a pattern with no reference implementation is unverifiable; `legal-normalise.collapse` is the cleanest pure SUT | inferred — justification: the AC demands a pattern; a shipped reference suite is the only proof the pattern works in CI |
| `.claude/hooks/README.md` pointer | "Documented pattern in a README/AGENTS pointer" | asked |
| `apps/web-platform/test/README.md` section | "Save minimized failing cases as regression fixtures" — the fixture convention must live where new-test conventions are documented | inferred — justification: placement/naming conventions are owned by this README; an undocumented convention drifts |
| ADR-293 | — | inferred — justification: Phase 2.10 gate; adopting a third test class is a convention decision a future engineer must find recorded, and sibling epic children (#10400, #10404) build on it |
| Phase 4 selection probes | "CI runs them in the affected-suite selection" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `scripts`, `.claude`, `knowledge-base`
- Planned files: 10 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — mechanical threshold hit on root count only: `.claude` contributes one pointer paragraph and `knowledge-base` carries plan artifacts + the ADR; the substantive diff is one cohesive change and splitting would strand the convention doc from its implementation. Single PR taken; recorded here as the advisory requires.

## Acceptance Criteria

- [ ] **AC1.** `jq -e '.devDependencies["fast-check"]' apps/web-platform/package.json` exits 0 and `cd apps/web-platform && npm ls fast-check` exits 0 with version `4.x`.
- [ ] **AC2.** `apps/web-platform/package-lock.json` contains a `fast-check` entry and was regenerated via `npx --yes npm@11 install --package-lock-only` (npm@11 pin); `git ls-files | grep -c 'bun.lock'` is 0.
- [ ] **AC3.** `test/server/codex-app-server-jsonl.property.test.ts`, `test/lib/plan-limits.property.test.ts`, `test/lib/repo-url.property.test.ts`, `test/lib/log-sanitize.property.test.ts` all exist and each contains ≥1 `fc.assert`.
- [ ] **AC4.** `cd apps/web-platform && npm run test:ci -- --project unit test/server/codex-app-server-jsonl.property.test.ts test/lib/plan-limits.property.test.ts test/lib/repo-url.property.test.ts test/lib/log-sanitize.property.test.ts` exits 0 with all properties passing, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (the new files typecheck — vitest/esbuild does not).
- [ ] **AC5.** Round-trip class: the codex suite asserts `decodeCodexJsonlLine(encodeCodexJsonl(m))` deep-equals `m` AND chunking-invariant stream reassembly; invariant class: `effectiveCap` raise-only + membership + monotonicity and `nextTier` ladder invariants; idempotency class: `f(f(x)) === f(x)` for `normalizeRepoUrl` and `sanitizeForLog` plus output-contract invariants.
- [ ] **AC6.** Each property file carries ≥1 negative-control `it` proving a deliberately-false property throws, and a header comment naming the regression-fixture convention (shrink → permanent `it()` with seed+path comment).
- [ ] **AC7.** `bash scripts/lib/legal-normalise-property.test.sh` exits 0 and prints `PROP_PASS`; `PROP_SEED=42` runs are deterministic on a given host/bash version (two runs print identical results — `RANDOM` seed streams are bash-version-specific, so replay claims are same-host).
- [ ] **AC8.** `scripts/lib/property-harness.md` exists and documents: seeded `RANDOM` loop, generator-over-token-alphabet pattern (the alphabet MUST enumerate every LHS transform the SUT applies — for `collapse`, all ~30 link/template-var/blank-line forms), the three property shapes for shell, `PROP_SEED` replay, the save-the-counterexample fixture convention, and **placement rules** for future property suites (`.claude/hooks/` for hook suites, `scripts/lib/` for repo-lib suites, `plugins/soleur/test/` for plugin suites — always a `SUITE_GLOBS` dir or an explicit `run_suite`); `.claude/hooks/README.md` links to it.
- [ ] **AC9.** Selection wiring holds with ZERO edits to `scripts/ci-pr-selection.sh` and `scripts/test-all.sh`: (a) `WEBPLAT_RELATED=$'server/codex-app-server-jsonl.ts' bash apps/web-platform/scripts/vitest-related.sh unit` (newline-separated file list env) reports `outcome=related` and runs the codex property file; (b) `bash scripts/test-all.sh --print-affected-set` lists `scripts/lib/legal-normalise-property.test.sh` with an `edge:` class; (c) a fabricated diff touching `scripts/lib/legal-normalise.sh` selects that suite under `--print-selection`/`--affected` fixture conventions; (d) `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] **AC10.** `apps/web-platform/test/README.md` documents `test/<area>/<subject>.property.test.ts` placement and the regression-fixture convention.
- [ ] **AC11.** `ADR-2*-property-based-testing-adoption.md` exists under `knowledge-base/engineering/architecture/decisions/` (provisional 293, renumbered on collision) and records the third-test-class decision + rejected alternatives.
- [ ] **AC12.** No `it.skip`/`it.only`/`fc.assert(..., { seed })` pinned seeds in the new files; `grep -n 'seed:' apps/web-platform/test/**/*.property.test.ts` returns only regression-fixture comments.
- [ ] **AC13.** `PROP_FAIL` and fast-check failure output both expose replay info (seed + iteration / seed + path) — verified by triggering one deliberate failure locally during implementation, then reverting.
- [ ] **AC14.** Diff scope guard: the PR adds no other `fast-check` suites, no new `run_suite` lines, no workflow edits — `git diff origin/main --name-only | grep -vE '(apps/web-platform/(package(-lock)?\.json|test/)|scripts/lib/|\.claude/hooks/README\.md|knowledge-base/)'` is empty.
- [ ] **AC15.** `bash scripts/test-all.sh --affected` (or the fixture equivalent in `test-all-affected.test.sh`) on a diff containing only the new files: selects the `apps/web-platform [unit]` registration for the `apps/web-platform/test/` additions (inside which `vitest related` narrows to the property files on SUT diffs), and `scripts/lib/legal-normalise-property.test.sh` for the `scripts/lib/` additions (argv-literal edge on the suite file itself).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given `apps/web-platform` with `fast-check` installed, when `vitest run --project unit` executes the four property files, then every property passes with ≥100 generated cases each. (unit)
- Given a deliberately broken `normalizeRepoUrl` (no `.git` strip), when the repo-url suite runs, then it reds with a shrunk counterexample. (unit — mutation target)
- Given a diff touching `scripts/lib/legal-normalise.sh`, when `test-all.sh --print-selection` evaluates it, then `AFFECTED_SELECTED` carries `scripts/lib/legal-normalise-property.test.sh` with `sel=1`. (integration)
- Given a `WEBPLAT_RELATED` listing `server/codex-app-server-jsonl.ts`, when `vitest-related.sh unit` runs, then `outcome=related` and the codex property file appears in the run. (integration)
- Given `PROP_SEED=42`, when the shell suite runs twice, then both runs produce identical `PROP_PASS` output. (unit)

### Regression Tests

- Given a found counterexample (implementation-time deliberate failure per AC13), when it is shrunk, then it lands as a permanent `it()`/`case` fixture with a `// regression fixture:` comment. (unit)

### Edge Cases

- Given `fc.webUrl()`+suffix arbs produce `bar.git.git/` and `x.Git/`, when `normalizeRepoUrl` runs, then output is idempotent and residue-free. (unit)
- Given `decodeCodexJsonlStream` receives a frame split mid-`\r\n` or at every single byte boundary, when decoded, then identical messages in order. (unit)
- Given `override` values of `null`, `0`, negative, `base`, `base+1`, and huge ints, when `effectiveCap` runs, then result ∈ {base, override} and ≥ base. (unit)
- Given `collapse` input containing only blank lines or starting with N blank lines, when collapsed twice, then outputs equal (leading-blank awk is idempotent). (unit)
- Given a generated doc whose free-text line literally contains `{{ stats.agents }}`, when collapsed, then it normalizes to `__AGENT_COUNT__` — and a second collapse changes nothing. (unit)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering-internal test tooling (devDependency + test files + shell test lib + docs + one ADR). Mechanical UI-surface scan of Files to Create/Edit: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` — Product/UX gate not triggered.

## Success Metrics

- `git grep -l 'fc\.assert' apps/web-platform/test` returns ≥4 files post-merge.
- `test-webplat` leg runtime delta < +15s on a full run (four suites of pure functions; measure via `TEST_TIMING_LOG` on the first full CI run).
- Zero orphan-suite findings from `lint-orphan-test-suites.sh` attributable to this change.

## Dependencies & Prerequisites

- npm registry access for `fast-check@^4.10.2` install + `npm@11` lockfile regen.
- No workflow, Terraform, credential, or Supabase changes required.
- Bash >= 3.2 compatibility for `property-harness.sh` (macOS default bash — same constraint as every `scripts/lib` consumer).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| A property finds a real SUT defect (e.g., `normalizeRepoUrl` is not idempotent on some input class) | Expected value, not failure: shrink → regression fixture; small SUT fix folds into this PR only if trivially contained, otherwise file a follow-up issue and pin the failing case as a known-defect fixture — never weaken the property to green. |
| Unseeded runs flake CI on rare generated edges | fast-check prints seed+path on failure; the fixture convention converts each find into a deterministic case. A "flaky" property is either a real bug or a wrong property — triage per `property-harness.md` (never a blind retry-bump; test/README.md flake policy applies). |
| `collapse` proves non-idempotent on some generated shape | Same disposition as above — real finding, fixture it. (Analysis suggests it is already idempotent; the property guards future sed additions.) |
| `fast-check` size/transitive deps | Zero-dependency package (verified `npm view`); devDep only, never in the shipped bundle (`build:server` externals + `dist/` exclude devDeps). |
| Shell PRNG portability | `RANDOM=` seeding is bash ≥3.2-correct; `property-harness.sh` pins `LC_ALL=C` and avoids `declare -A`/namerefs like `legal-normalise.sh`. |
| ADR ordinal collision with sibling PRs | Provisional 293; ship's ADR-Ordinal Collision Gate re-verifies; on renumber, sweep `ADR-293` across `knowledge-base/project/{plans,specs}/feat-one-shot-10398-property-based-testing/`. |

## Future Considerations

- Extend PBT to `normalizeRepoUrl`'s SQL mirror (`031_normalize_repo_url.sql`) — SQL-side generation + parity properties.
- Epic #10397 children: #10400 (PBT guidance in shipped workflow skills), #10404 (verification-scaffold to user repos) — this PR's `property-harness.md` + ADR are the foundation they cite.
- Consider the ToB `property-based-testing` community plugin for reviewer agents triaging shrunk counterexamples (deferred decision-challenges item).

## Documentation Plan

- `scripts/lib/property-harness.md` (new, canonical shell pattern doc).
- `.claude/hooks/README.md` (pointer paragraph).
- `apps/web-platform/test/README.md` (property-test placement + fixture convention).
- `ADR-29x` (decision record).
- `property-harness.sh` header docstring (API contract, mirroring `legal-normalise.sh` conventions).

## References & Research

### Internal References

- `apps/web-platform/vitest.config.ts:87` — `unit` project include `test/**/*.test.ts`.
- `apps/web-platform/scripts/vitest-related.sh` — `vitest related` narrow-or-full dispatch (#9815).
- `scripts/test-all.sh:96-109` — `SUITE_GLOBS`; `:6707` — unregistered-suite warning; `:1697` — `run_suite` chokepoint; `:6725-6753` — glob registration loop under `want_scripts`.
- `scripts/ci-pr-selection.sh:60-66` — stage-2 delegates to `test-all.sh` enumerate/selection streams.
- `scripts/lib/legal-normalise.sh` — sourced-lib conventions + `collapse` semantics.
- `apps/web-platform/test/server/inngest/cron-community-publication.test.ts:373-380` — mulberry32 seeded-fuzz precedent.
- `apps/web-platform/test/README.md` §"Test file placement", §"Flaky-test policy".
- `scripts/lint-dual-lockfile.sh` / `scripts/lint-workflow-install-sites.sh` — dep-install conventions.
- Issue #10398, epic #10397; open scope-outs #8659, #7942 (acknowledged, not folded).

### External References

- fast-check docs: [fast-check.dev](https://fast-check.dev/) — `fc.assert`/`fc.property`/`fc.jsonObject`/`fc.webUrl`, seed+path failure reporting.
- Trail of Bits `property-based-testing` skill (github.com/trailofbits/skills) — property catalog + tautology/vacuity anti-patterns + counterexample triage (fetched 2026-10-19).
- Osmani, *Agentic Verification* (2026-10-14) — the epic's motivating article.

### Related Work

- #10397 (epic), #10399–#10404 (siblings), #9815 (vitest-related narrowing), #8322 (affected classification), ADR-181/ADR-242/ADR-262 (selection machinery), ADR-191 (npm lockfile of record).
