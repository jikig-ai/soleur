---
title: "feat: property-based-testing guidance in shipped workflow (Epic #10397 child 3)"
date: 2026-10-20
slug: feat-property-testing-guidance
branch: feat-one-shot-10400-pbt-guidance
issue: 10400
---

## Overview

Ship property-based-testing (PBT) guidance to Soleur plugin users: accept `property` as a RED-layer option in the `work` skill's TDD gate, add "state the property" guidance to `plan`'s Test Scenarios templates, and add a short shipped reference teaching the pattern (pure-function first, plain-English property, minimized-counterexample regression, language→tool map). Repo-side machinery (fast-check + `scripts/lib/property-harness.*`, ADR-293) already merged via #10398; this change is docs-only on the two shipped skill surfaces plus one reference file.

## Enhancement Summary

Plan deepened via `soleur:deepen-plan` (inline execution — subagent context): the Observability section was added (the `plugins/*/skills/` `.md` files do not qualify for the pure-docs exemption in deepen-plan §4.7's trigger test, and the diff extends a CI gate suite — a shipped-behavior surface); the 118-byte `work/SKILL.md` body-ceiling headroom was measured and budgets the edit form; all halt gates pass.

### Deepen-Gate Verdicts (all pass)

User-Brand §4.6: PASS (threshold `none`; no sensitive-path files — `plugins/soleur/**` is outside the canonical regex). Observability §4.7: PASS (5 fields non-placeholder; `grep` allowlisted verb; literal `expected_output`; <15s probe; no `ssh`). PAT §4.8: PASS (no token-shaped vars — grep clean). UI-wireframe §4.9: SKIP (no UI surface in Files lists). Encryption §4.10: SKIP (no store/connection — detection regex empty). Guard Contract §4.11: PASS (`lint-guard-contract.py` green — 1 entry, ≥3 matrix rows incl. own-dispatch + must-PASS rows). Scope Check §4.12: PASS (single live `## Scope Check`; 7/7 asks mapped; `Recommendation: single PR` present). Network-outage §4.5: SKIP (no trigger patterns). Downtime §4.55: SKIP (docs-only). Precedent-diff §4.4: pin extension mirrors the file's own `found "$WORK_SKILL" …` assertion idiom; reference file mirrors `work-test-harness-sharp-edges.md` conventions (no frontmatter, `# Title`, markdown links). Founder check §2.13: N/A (headless run — no block written, per `plan-founder-check.md`).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10400 --json state` → `OPEN`; no `closedByPullRequestsReferences`. Premise live.
- Epic #10397 `OPEN`; sibling #10398 (monorepo machinery) `CLOSED` via PR #10624, merged 2026-10-20 — matches the pipeline brief ("PBT machinery merged 2026-10-20").
- Issue evidence claim verified on `origin/main`: `git grep -il fast-check -- plugins/soleur/skills plugins/soleur/agents` → **zero hits** (machinery lives in `apps/web-platform/test/`, `scripts/lib/`, `knowledge-base/` — none of it is shipped plugin content). The shipped-guidance gap the issue asserts is real.
- `work/SKILL.md` prescribes `RED(unit|integration|e2e)` (TDD task-title convention) and never names `property` — confirmed.
- `plan` Test Scenarios guidance lives in `plugins/soleur/skills/plan/references/plan-issue-templates.md` (exactly 3 `## Test Scenarios` blocks, one per detail-level template; the SKILL.md body only references the heading) — confirmed.
- ADR-corpus check for the proposed mechanism (`knowledge-base/engineering/architecture/decisions/`): ADR-293 *sanctions* PBT as a third test class — the mechanism is an already-decided direction being propagated, not a rejected alternative resurfacing. No ADR conflicts.
- Sibling-child premise: child 1's `decision-challenges.md` records the `@trailofbits/skills/property-based-testing` community-plugin decision as deferred with an explicit note that "re-evaluation [is] natural under epic sibling #10400" — this plan carries that row forward.

### Property List (Phase 0.6b)

Discrete properties the ask decomposes to (observable outcomes):

1. `work`'s RED-task vocabulary accepts `property` alongside `unit|integration|e2e`, with guidance on when a generated-input oracle is the right RED form.
2. `plan`'s Test Scenarios templates tell the planner to state properties that must never break, in plain English.
3. A shipped reference teaches the pattern: start with a pure function, state the property before the cases, shrink the counterexample into a permanent regression fixture, and name the per-language tool (fast-check / Hypothesis / proptest).
4. The reference is discoverable — linked from the edited surfaces — and self-contained for plugin users (no repo-internal links).
5. README component counts unchanged (a reference is not a component).

### Cut List (Phase 0.6b)

- **Install the community `@trailofbits/skills/property-based-testing` plugin as the delivery vehicle** — buys properties 1-3 wholesale, but child 1 already deferred plugin adoption as `operator (scope)` and this issue's scope is Soleur-authored guidance fitted to the RED/Test-Scenarios vocabulary. Cut as a mechanism; persisted to `decision-challenges.md` for the operator per the carry-forward note.
- **A dedicated PBT skill** (`skills/property-testing/`) — buys nothing over a `work/references/` file: the TDD gate is the decision point the guidance must reach, and a skill would sit unloaded until invoked. The issue sized this as a reference; cut.
- **Editing `test-design-reviewer.md` to add a `property` pyramid row** — `property` is an oracle class, not a pyramid layer; `*.property.test.ts` already classifies `unit` by the agent's path table (verified). Cut — wrong axis.

### Repo Research

- **`plugins/soleur/skills/work/SKILL.md`** — TDD task-title convention at the "Create Todo List (TDD-First Structure)" step (`RED(unit|integration|e2e): Write failing test for [feature]`); the TDD Gate (HARD GATE) block in Phase 2 prescribes the failing-test properties. Both are the edit surface.
- **`plugins/soleur/skills/plan/references/plan-issue-templates.md`** — three `## Test Scenarios` blocks (MINIMAL/MORE/A LOT templates), each already carrying the pyramid-layer label sentence ("`unit`, `integration`, or `e2e`" + `pyramid-justified:` marker rule). The "state the property" guidance lands inside all three blocks (per-block — `test-pyramid-fixtures.test.sh` asserts every block carries its marker lines).
- **`plugins/soleur/test/test-pyramid-fixtures.test.sh`** — DRIFT pin asserting `RED\(unit\|integration\|e2e\)` presence in `work/SKILL.md`. **CTO-corrected evidence (2026-10-20):** the pin is a full-literal ERE including the closing `\)`, so the widened form `RED(unit|integration|e2e|property)` does NOT satisfy it — extending the pin is FORCED, not optional. Also pins `^## Test Scenarios` count == 3 and per-block `pyramid layer`/`pyramid-justified` markers — all edits stay inside existing blocks.
- **Consumer census for the widened vocabulary** (hr-type-widening-cross-consumer-grep): no code path parses `RED(<layer>)` task titles (repo-wide `RED\(` grep outside markdown returns only unrelated shell identifiers). Prose consumers that restate the vocabulary: `review/SKILL.md` + `review.workflow.js` (pyramid marker restatements — e2e-specific, unaffected), `test-design-reviewer.md` (layer *classification* of files — orthogonal axis, unaffected), `qa/SKILL.md`/`reproduce-bug/SKILL.md` (seam/layer prose — unaffected), cursor/opencode/manifest stubs (description text only — unaffected).
- **`plugins/soleur/skills/work/references/`** — existing convention: plain `# Title` files, no frontmatter, Read on demand via markdown links from SKILL.md (e.g. `[work-test-harness-sharp-edges.md](./references/work-test-harness-sharp-edges.md)`).
- **No orphan-reference census** — `harness-parity.test.ts` classifies by path policy and scans for harness-form tokens only; no suite censuses `references/` membership.

### Machinery On Disk (merged via #10398)

- `scripts/lib/property-harness.sh` + `scripts/lib/property-harness.md` — seeded generated-input loop (`PROP_SEED` replay, `PROP_RUNS` budget), token-alphabet generator rule, shell property shapes, counterexample→fixture convention, placement-is-registration table, anti-vacuity obligations.
- `apps/web-platform/test/**/*.property.test.ts` (4 suites) + `apps/web-platform/test/README.md` §"Property-based tests" — vitest conventions: real oracles only, negative-control `it` per file, `// regression fixture: fast-check seed <seed> path <path>` labels, never commit `{ seed }` params.
- `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` — PBT as sanctioned third test class; ToB strength ordering (no crash → type preservation → invariant → idempotence → round-trip/oracle); tautology/vacuity anti-pattern.
- `knowledge-base/project/learnings/best-practices/2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md` — v4 API substitutions (`fc.dictionary`+`fc.jsonValue`, `fc.string({unit})`), canonicalized JSON oracles, negative-control requirement.
- `knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md` — the first-yield defect (suffix-strip exposing trailing whitespace) — a concrete "why this pays" example the reference can cite generically.

### Learnings / Conventions Applied

- `cq-union-widening-grep-three-patterns` / `hr-type-widening-cross-consumer-grep` — census done above; only the drift pin restates the widened token set.
- Constitution: reference files take no frontmatter; markdown links for file references; kebab-case filenames.
- fast-check `4.10.2` (npm, installed matches), Hypothesis `6.170.5` (PyPI), proptest `1.12.0` (crates.io) — verified 2026-10-20 against the live registries (hr-third-party-content-grep-on-undertaking / CLI-verification gate).

### Community Discovery (Phase 1.5/1.5b)

- Stack scan: no `Cargo.toml`/`mix.exs`/`go.mod`/`Package.swift`/`build.gradle`/`composer.json`/`pubspec.yaml` at repo root — no uncovered stacks; agent-finder skipped.
- Functional overlap (inline — no Task spawn in subagent context): `@trailofbits/skills/property-based-testing` (covers fast-check/Hypothesis/proptest conventions + shrunk-counterexample triage) and `@jeremylongshore/.../property-based-test-helper` — same findings child 1's functional-discovery returned. Neither installed; adoption is `operator (scope)` and persists to `decision-challenges.md` (re-evaluation was explicitly deferred to this child).

### External Research Decision (Phase 1.6)

Skipped — strong local context. The taxonomy, tool versions, anti-patterns, and naming conventions are already on disk from child 1 (ADR-293 + ToB catalog vocabulary it cites); registry versions re-verified live above. Docs-only change; external research adds nothing.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (one-shot path; no brainstorm ran). Reconciling the *issue's* claims against the tree instead:

| Issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "`git grep -il fast-check plugins/soleur/skills plugins/soleur/agents` returns zero" | Holds — machinery is all outside `plugins/soleur/` | Plan proceeds; the gap is real. |
| "`work` SKILL.md prescribes RED(unit\|integration\|e2e) but never property tests" | Holds (`RED(unit|integration|e2e)` task-title convention; no `property` token) | Edit the vocabulary + TDD gate guidance. |
| "`plan` (Test Scenarios — 'state the property' guidance)" | Test Scenarios content lives in `plan/references/plan-issue-templates.md` (3 template blocks), not in `plan/SKILL.md` itself | The "`plan`" edit lands in the templates file where the guidance actually lives — a file-location nuance, not a scope change. |
| "Sized as edits to 2 SKILL.md + 1 new reference" | Real edit set is 1 SKILL.md + 1 templates file + 1 new reference (+1 recommended pin-suite line) | Track the drift-pin consumer explicitly; the sizing intent (small) holds. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` against the four touched paths → one hit:

- **#4133 — follow-through(#4116): Schema parity test for `## Observability` block** — **Acknowledge.** Same file (`plan-issue-templates.md`) but a disjoint concern: it proposes a parity test over the `## Observability` 5-field schema; this plan edits only the `## Test Scenarios` blocks and adds no schema fields. Folding a new parity suite into a docs PR would grow scope; the issue stays open for its own cycle.

## Problem Statement

Soleur's shipped workflow teaches example-based testing only. The `work` TDD gate prescribes `RED(unit|integration|e2e)` — generated-input property tests are not an offered option — and `plan`'s Test Scenarios templates ask for Given/When/Then examples but never ask for the *property* behind them. Meanwhile the machinery to write property tests exists and is proven (ADR-293, four vitest suites, a shell harness, a real first-yield defect), but none of it is reachable by a plugin user's agent: `git grep -il fast-check plugins/soleur/` returns zero. An agent that only knows example tests writes N hand-picked cases where a generator could hunt thousands — the audit's measured gap (#10397) and the highest-leverage self-verification improvement available.

## Proposed Solution

Three small documentation deliverables, all inside `plugins/soleur/`:

1. **`work` RED-layer accepts `property`.** Widen the TDD task-title vocabulary to `RED(unit|integration|e2e|property)` and add one line of selection guidance at both the todo-structure step and the TDD gate: pick `property` when the behavior is a contract over an input domain (invariant, idempotence, round-trip) — typically a pure function — where a generator plus shrinking outperforms hand-picked examples. A `property` RED still lands at whatever pyramid layer its test file lives at (usually unit) — `property` names the oracle class, not a fourth layer.
2. **`plan` Test Scenarios states the property.** In all three `## Test Scenarios` template blocks, add the guidance: when a scenario asserts a contract that must hold for every input, state the *properties that must never break* in plain English alongside the example cases — `soleur:work` can then choose the `property` RED form.
3. **A shipped reference** — `plugins/soleur/skills/work/references/property-testing.md` (~150 lines), linked from the `work` TDD gate, teaching the pattern end to end: start with a pure function, state the property in plain English before writing cases, the four property shapes by strength, the generator/alphabet idea, counterexample → minimized permanent regression fixture (never pin seeds), anti-vacuity obligations, and a language→tool map.

## Technical Approach

### Edit surface 1 — `plugins/soleur/skills/work/SKILL.md`

**Byte-ceiling constraint (measured 2026-10-20):** `work` is a lifecycle skill with a per-file body ceiling enforced by `scripts/lint-skill-body-budget.py` against the merge base — ceiling `359,189` B vs current `359,071` B → **118 B total headroom for the whole diff** (ceilings ratchet down only; raising one is a separate reviewed PR, out of scope). This caps what "a PBT section in `work`" can physically be:

- **Budgeted form (fits):** widen `"RED(unit|integration|e2e): Write failing test for [feature]"` → `RED(unit|integration|e2e|property)` (+9 B) at the todo-structure step, and append one markdown link + a ≤ ~100 B clause at ONE site: `… see [property-testing.md](./references/property-testing.md)` — e.g. "or `property` for a generated-input contract test" + link. Total ≈ 110 B. ALL selection guidance, shapes, and the tool map live in the reference (no ceiling), not in SKILL.md.
- **If the technical ruling wants fuller prose:** the diff must pay delta-neutral trims — name a removable sentence of equal bytes in work/SKILL.md at implementation time (the TDD gate's mega-bullet prose is the candidate region). Record the ruling outcome in `decision-challenges.md`.
- **Link form is load-bearing:** `plugins/soleur/test/components.test.ts` pins two conventions — every `references/*.md` must be *named* from its skill's files (reachability guard; `property-testing.md` would be an orphan otherwise), and `references/...` paths must appear as **markdown links, never backticked** (`[property-testing.md](./references/property-testing.md)` — a backticked `references/property-testing.md` mention fails the "No backtick file references" suite).
- No `description:` frontmatter change (Phase 1.8 budget check: not triggered — routing text unchanged).

### Edit surface 2 — `plugins/soleur/skills/plan/references/plan-issue-templates.md`

All three `## Test Scenarios` blocks (MINIMAL/MORE/A LOT) gain the same sentence family, placed immediately after the existing pyramid-layer guidance sentence:

> When a scenario asserts a contract that must hold for *every* input — an invariant, an idempotence, a round-trip — also state the **properties that must never break** in plain English (e.g., "`f(f(x)) == f(x)`"), not only the example cases; `soleur:work` can then write the RED as a `property` test.

Per-template phrasing adapts to each block's shape but the literal phrase `properties that must never break` appears in all three (issue AC; gives `grep -c 'must never break' == 3` a stable assert target). Edits stay inside the existing blocks — the `test-pyramid-fixtures.test.sh` pins (`^## Test Scenarios` count == 3, per-block marker presence) are unaffected.

### New file — `plugins/soleur/skills/work/references/property-testing.md`

~150 lines, `# Property-based testing` title, no frontmatter (references convention). Content outline:

1. **What it is / when to reach for it** — a property test runs a generated stream of inputs against an always-true statement and *shrinks* any counterexample to a minimal case. Reach for it when the SUT is a pure function with a contract over a domain; don't reach for it to test one hand-picked edge (an example test is cheaper) or for "does not throw" (vacuous).
2. **The workflow** — (a) start with a pure function; (b) state the property in plain English *first*, before any case ("for every input, X is always true"); (c) pick the property shape by strength: output-contract/invariant < idempotence (`f(f(x)) == f(x)`) < round-trip (`decode(encode(x)) == x`) < oracle twin (`f(x) == reference(x)`); (d) write the generator over the input alphabet, biased toward the boundaries the SUT transforms; (e) keep it honest — a negative control asserting a deliberately-false property fails.
3. **When a counterexample lands** — it is a defect in the SUT *or* an over-claiming property; triage first. Then shrink and pin the minimal case as a permanent named regression fixture; never commit a seed parameter — the stream must keep moving or coverage silently narrows.
4. **Language → tool map** — JS/TS `fast-check` (`npm i -D fast-check`, verified 4.10.2), Python `hypothesis` (`pip install hypothesis`, verified 6.170.5), Rust `proptest` (`cargo add proptest`, verified 1.12.0), JVM `jqwik`, Haskell `QuickCheck`, .NET `FsCheck`.
5. **A minimal worked example** — one `fast-check` snippet (`fc.assert`/`fc.property`/`fc.string` — API verified against the installed 4.x surface) and the Hypothesis `@given` equivalent, each ~10 lines.
6. **House conventions where they exist** — one short paragraph: repos that adopt the class commonly name suites `*.property.test.*` and label pinned counterexamples `// regression fixture: <seed>`; this monorepo's own conventions live in `apps/web-platform/test/README.md` and `scripts/lib/property-harness.md` (named as text, not linked — repo-internal paths do not exist in plugin installs).

### Edit surface 3 — `plugins/soleur/test/test-pyramid-fixtures.test.sh` (pin extension)

Extend the DRIFT-pin block so the new vocabulary member is itself pinned: update the canonical `RED\(unit\|integration\|e2e\)` pattern to cover `\|property` (or add a `found "$WORK_SKILL" 'e2e\|property'` assertion) and update the suite's header vocabulary sentence. **CTO-corrected evidence (2026-10-20):** the existing `RED\(unit\|integration\|e2e\)` pin does NOT survive the widening — the literal includes the closing `\)`, so this is a forced repair, not an optional extension. Update `MIN_ASSERTIONS` floor accordingly.

### Implementation Phases

#### Phase 1: Reference first (the shared vocabulary source)

- 1.1 Write `plugins/soleur/skills/work/references/property-testing.md` per the outline above.
- 1.2 Lint: markdownlint clean; verify every named tool/CLI token against the verification record in Research Insights (no fabricated API names — `fc.jsonObject`/`fc.stringOf` do not exist in fast-check v4 and must not appear).

#### Phase 2: Wire the two skill surfaces

- 2.1 `work/SKILL.md`: widen the RED vocabulary + add the selection line + reference link at both sites (todo-structure step, TDD gate).
- 2.2 `plan-issue-templates.md`: add the "properties that must never break" sentence to all three `## Test Scenarios` blocks.
- 2.3 `test-pyramid-fixtures.test.sh`: extend the DRIFT pin + floor.

#### Phase 3: Verify

- 3.1 Run `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` — green.
- 3.2 Run the AC grep battery (below) — every literal assert target hit.
- 3.3 markdownlint on touched files; `git diff origin/main...HEAD -- README.md plugins/soleur/README.md` empty (component counts unchanged by construction — a reference is not a component).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Ship a dedicated `skills/property-testing/` skill | Rejected — a skill sits unloaded until invoked; the decision point is the TDD gate, which is inside `work`. Cut in Phase 0.6b. |
| Install `@trailofbits/skills/property-based-testing` instead of authoring | Deferred `operator (scope)` — child 1's ruling; re-evaluation persists to `decision-challenges.md` per its explicit carry-forward note. |
| Teach PBT inside `test-design-reviewer.md` | Rejected — wrong axis: the reviewer classifies files by pyramid layer; `property` is an oracle class and `*.property.test.ts` already classifies `unit`. |
| `RED(unit,property)` two-axis title form instead of a widened token | Alternative noted for the technical-ruling row — preserves the layer signal explicitly but invents a composite title grammar no other token uses. Default assumed: the issue's literal `RED(unit|integration|e2e|property)` widening. |
| `RED(property)` as a separate alternative form (keeping `RED(unit\|integration\|e2e)` verbatim) | Rejected — two spellings of the same enum invites drift; one canonical form plus the updated pin is cleaner. |

## Observability

The shipped surface is documentation consumed by agents; "observability" here is whether the landed guidance is mechanically discoverable in the tree (the pin suite is the enforcement layer; this block is the declared probe).

```yaml
liveness_signal:
  what: "the `property` token is present in work/SKILL.md's RED-layer naming and the reference file is linked"
  cadence: "per-PR via test-pyramid-fixtures.test.sh DRIFT pin; CI on every diff touching plugins/soleur/"
  alert_target: "CI check failure (plugin test shard)"
  configured_in: "plugins/soleur/test/test-pyramid-fixtures.test.sh (extended in this diff)"
error_reporting:
  destination: "CI job log + suite FAIL line naming the missing vocabulary member"
  fail_loud: "yes — the pin suite exits non-zero and names the missing member"
failure_modes:
  - mode: "`property` token silently dropped from work/SKILL.md later"
    detection: "extended DRIFT pin assertion in test-pyramid-fixtures.test.sh"
    alert_route: "CI red on the next diff touching the plugin shard"
  - mode: "reference file orphaned (nothing names it)"
    detection: "components.test.ts references-reachability guard"
    alert_route: "CI red — orphan reference files are a suite failure"
  - mode: "a Test Scenarios block loses the property guidance"
    detection: "AC2 grep count == 3 in this diff's verification; the per-block tpl_blocks pin already covers marker lines"
    alert_route: "review-time AC check"
logs:
  where: "CI job log (test-pyramid-fixtures.test.sh assertion lines)"
  retention: "GitHub Actions retention"
discoverability_test:
  command: "grep -l 'property-testing.md' plugins/soleur/skills/work/SKILL.md"
  expected_output: "work/SKILL.md"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** plugin agents still never see `property` as a test option (silent gap persists), or — worse — mispelled guidance teaches a fabricated tool/API name and the agent burns a cycle discovering it doesn't exist.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — docs-only change inside shipped skill prose; no credentials, no user data, no runtime behavior.
- **Brand-survival threshold:** none

## Guard Contract

### Guard 1 — RED-vocabulary drift pin covers the widened token set

**Property.** `plugins/soleur/test/test-pyramid-fixtures.test.sh` reports FAIL when `work/SKILL.md`'s RED-task layer naming loses any member of the sanctioned set `{unit, integration, e2e, property}` — the pin's window covers the whole vocabulary, not only the three members that existed when it was written.

**Assembly.** The pin's chokepoint is the DRIFT-pin block in `plugins/soleur/test/test-pyramid-fixtures.test.sh` (the `found "$WORK_SKILL" …` assertion over the RED-task naming line); `work/SKILL.md` "Create Todo List (TDD-First Structure)" is the single canonical spelling site.

**Mutation matrix** (written before the edit, per the gate's ordering rule):

| # | Edit to the system under test | Expected |
|---|---|---|
| 1 | Delete the `|property` member from `work/SKILL.md`'s RED naming | Guard RED |
| 2 | Rename `property` to `fuzz` in `work/SKILL.md` | Guard RED |
| 3 | Delete the pin's `property` assertion from `test-pyramid-fixtures.test.sh` (guard's own dispatch — a pin that checks nothing) | Guard RED against a tree where `property` is absent |
| 4 | Revert the entire `work/SKILL.md` vocabulary edit (restore `RED(unit\|integration\|e2e)`) | Guard RED |
| 5 | Harness row: neuter `found()` to always print `1` | Suite's instrument self-test RED |
| 6 | Must-PASS input: add a *fifth* unrelated sentence to `work/SKILL.md` elsewhere | Guard stays GREEN — the pin keys on vocabulary, not file identity |

## Files to Create

- `plugins/soleur/skills/work/references/property-testing.md` — the shipped PBT reference (~150 lines).

## Files to Edit

- `plugins/soleur/skills/work/SKILL.md` — widen `RED(unit|integration|e2e)` → `RED(unit|integration|e2e|property)`; selection guidance + reference link at the todo-structure step and the TDD gate.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — "properties that must never break" sentence in all three `## Test Scenarios` blocks.
- `plugins/soleur/test/test-pyramid-fixtures.test.sh` — extend the DRIFT pin to cover `property`; bump `MIN_ASSERTIONS`; header vocabulary sentence.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add a PBT section to `work` (TDD gate — properties as a RED layer option)" [issue #10400] | FR-1 / Phase 2.1 / Files-to-Edit `work/SKILL.md` | mapped |
| 2 | "and `plan` (Test Scenarios — \"state the property\" guidance)" [issue #10400] | FR-2 / Phase 2.2 / Files-to-Edit `plan-issue-templates.md` | mapped |
| 3 | "plus a short reference (e.g. `skills/work/references/property-testing.md`) covering: start-with-pure-function, plain-English-property-first, minimized-case regression, language→tool map" [issue #10400] | FR-3 / Phase 1 / Files-to-Create `property-testing.md` | mapped |
| 4 | "`work` RED-layer accepts `property` alongside unit/integration/e2e." [issue #10400] | AC1 | mapped |
| 5 | "`plan` Test Scenarios guidance includes \"properties that must never break\"." [issue #10400] | AC2 | mapped |
| 6 | "Reference file exists and is linked; README component counts unchanged (reference, not skill)." [issue #10400] | AC3, AC5 | mapped |
| 7 | "Sized as edits to 2 SKILL.md + 1 new reference (~150 lines)." [issue #10400] | Constraint — honored in intent: 1 SKILL.md + 1 templates file (where the `plan` guidance actually lives) + 1 reference (~150 lines) + 1 pin-suite line | mapped — location nuance recorded in Research Reconciliation |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `work/SKILL.md` vocabulary + guidance edits | asks 1, 4 | asked |
| `plan-issue-templates.md` Test Scenarios edits | asks 2, 5 | asked |
| `work/references/property-testing.md` | ask 3 | asked |
| `test-pyramid-fixtures.test.sh` pin extension | — | inferred — justification: the DRIFT pin exists to pin the RED vocabulary; widening the vocabulary without extending the pin leaves the new member unpinned and silently rottable (enforcement contract needs it) |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 4 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `work/SKILL.md` RED-task naming accepts `property` alongside the existing layers: `grep -nE 'RED\([^)]*property' plugins/soleur/skills/work/SKILL.md` returns a hit on the RED-task naming line (spelling per the technical-ruling outcome — default `unit|integration|e2e|property`), and the TDD gate names when to choose it + links `references/property-testing.md`.
- [ ] AC2 — `grep -c 'properties that must never break' plugins/soleur/skills/plan/references/plan-issue-templates.md` returns `3` (one per `## Test Scenarios` block — the issue's literal phrase).
- [ ] AC3 — `plugins/soleur/skills/work/references/property-testing.md` exists and is referenced from `work/SKILL.md` (`grep -n 'property-testing.md' plugins/soleur/skills/work/SKILL.md` hits); the file names `fast-check`, `hypothesis`, and `proptest`.
- [ ] AC4 — `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` exits 0 after the pin extension, and the extended pin asserts `property` membership (visible in the file's DRIFT-pin block).
- [ ] AC5 — `git diff origin/main...HEAD -- README.md plugins/soleur/README.md` is empty (component counts unchanged — the addition is a reference file, not a skill/agent/command).
- [ ] AC6 — markdownlint clean on all touched `.md` files.
- [ ] AC7 — No fabricated tool/API tokens: the reference's named symbols exist in the cited tool versions (`fc.assert`, `fc.property`, `fc.string`, `@given`, `proptest!`); `fc.jsonObject`/`fc.stringOf` do not appear (known v4 traps — see learnings).

## Test Scenarios

Label each scenario's pyramid layer — `unit`, `integration`, or `e2e` — and prefer the lowest layer that exercises the behavior.

- **AC verification battery (unit — grep asserts):** Given the merged diff, when the AC1–AC3/AC5 grep commands run, then each returns its expected hit/count.
- **Pin mutation (unit):** Given the extended DRIFT pin, when `|property` is removed from `work/SKILL.md`'s RED naming, then `test-pyramid-fixtures.test.sh` exits non-zero naming the missing member (Guard 1 matrix row 1).
- **Guard self-mutation (unit):** Given the pin block, when the `property` assertion is deleted from the pin itself, then the suite reds against a tree lacking the token (matrix row 3 — the pin's own dispatch).
- **Regression sweep (unit):** `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` + `bun test plugins/soleur/test/` touched suites green; `^## Test Scenarios` count remains `3`; per-block `pyramid-justified` markers intact.
- **Docs hygiene (unit):** markdownlint on touched files; no `description:` frontmatter delta (skill description budget untouched).

## Domain Review

**Domains relevant:** Engineering, Product (fail-closed expansion — Product/UX tier resolved NONE below)

### Engineering

**Status:** reviewed (inline — subagent context, no Task spawn)
**Assessment:** Blast radius is prose-only: the change extends a shipped vocabulary surface (`RED(...)` token set) and three template blocks. The one structural risk is consumer drift on the widened enum — censored by the cross-consumer grep in Research Insights: no parser consumes `RED(<layer>)`; the only mechanical restatement is the drift pin, which this plan extends. The oracle-class-vs-layer ambiguity (`property` names a test *class*, not a pyramid layer) is the residual design fork — recorded as a technical decision row for the pipeline's CTO gate; default assumed per the issue's literal AC wording.

### Product/UX Gate

**Tier:** none — no UI surface in Files to Create/Edit (mechanical override does not fire; the change is agent-guidance prose)

No Product/UX pipeline runs at NONE tier.

## Success Metrics

- `git grep -il 'fast-check\|property-based' plugins/soleur/skills plugins/soleur/agents` returns ≥2 files post-merge (today: 0).
- First plugin-user `RED(property)` task created in the wild is unmeasurable internally — proxy: the vocabulary appears in both decision surfaces (plan-time property statement, work-time RED token).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| `property` token read as a fourth *pyramid layer* rather than an oracle class | Guidance text states the axis split explicitly ("`property` names the oracle class; the file still lives at a pyramid layer"); technical-ruling row flags it for CTO confirmation. |
| Vocabulary widening breaks a mechanical consumer | Census in Research Insights — none exist; the one prose pin is extended in this diff. |
| Reference teaches a fabricated API (`fc.jsonObject`/`fc.stringOf` are the known v4 traps) | AC7 forbids them; the learnings file is cited as the API-surface authority; only verified symbols appear. |
| Template edits silently break the `test-pyramid-fixtures.test.sh` per-block pins | Edits stay inside existing blocks; Phase 3 runs the suite; AC4 asserts it green. |
| `work/SKILL.md` additions exceed the 118 B body-ceiling headroom and the lint reds at ship | Budgeted form capped at ~110 B (token widening + one link clause); fuller prose requires the delta-neutral trim path — technical-ruling row in `decision-challenges.md`; `lint-skill-body-budget.py --base origin/main` is the verify command at Phase 3. |
| Reference bloats into a second `property-harness.md` | Issue sizes it ~150 lines; outline caps it at 6 short sections; repo-internal machinery is named, not duplicated. |

## Documentation Plan

The deliverable IS documentation. No README/AGENTS.md changes (component counts unchanged per AC5); no CHANGELOG entry authored in this plan (release flow owns it). The `ship` flow's PR body carries the feature summary.

## References & Research

### Internal References

- Issue: [#10400](https://github.com/jikig-ai/soleur/issues/10400); epic [#10397](https://github.com/jikig-ai/soleur/issues/10397); sibling machinery PR #10624 (issue #10398).
- ADR-293: `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md`
- Machinery docs: `scripts/lib/property-harness.md`, `apps/web-platform/test/README.md` §"Property-based tests"
- Learnings: `knowledge-base/project/learnings/best-practices/2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md`, `knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md`
- Child-1 artifacts: `knowledge-base/project/specs/archive/20261020-034022-feat-one-shot-10398-property-based-testing/` (decision-challenges.md carry-forward rows), `knowledge-base/project/plans/archive/20261020-034022-2026-10-19-feat-property-based-testing-adoption-plan.md`

### External References

- fast-check — [fast-check.dev](https://fast-check.dev/) (v4.10.2 verified via `npm view fast-check`)
- Hypothesis — [hypothesis.works](https://hypothesis.works/) (v6.170.5 verified via PyPI)
- proptest — [crates.io/crates/proptest](https://crates.io/crates/proptest) (v1.12.0 verified via crates.io API)
- Trail of Bits property taxonomy — as cited by ADR-293 (`@trailofbits/skills/property-based-testing`, evaluated not installed)

### Related Work

- Epic siblings: #10401 (differential-migration testing), #10402 (feature-map convention), #10403 (flake-quarantine guidance), #10404 (verification-scaffold) — independent; no ordering constraint.
- Open overlap: #4133 (Observability-schema parity test) — acknowledged, disjoint concern.
