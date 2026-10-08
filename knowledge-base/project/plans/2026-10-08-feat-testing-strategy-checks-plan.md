---
title: "feat: testing-strategy checks (test pyramid, fast-feedback budget) in Soleur's test review"
date: 2026-10-08
slug: feat-testing-strategy-checks
branch: feat-one-shot-9762-testing-strategy
issue: 9762
closes: 9762
type: feat
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-08
**Mode:** inline deepen (no Task/Workflow spawn in this harness — research agents, skill-application agents, and review seats were executed as inline passes by the orchestrator)
**Sections enhanced:** Functional Requirements (fixture realism, verdict-block isolation), Guard Contract (lint-conformant field shape), Observability (single-token `expected_output`), Domain Review, Test Scenarios.

### Key Improvements (deepen pass)

1. Fixture paths corrected to repo conventions: e2e is `apps/web-platform/e2e/*.e2e.ts`, unit tests live flat in `apps/web-platform/test/` — the layer table must name both surface conventions (`e2e/` dir AND `*.e2e.ts`/`*.spec.ts`).
2. Guard Contract reformatted to `lint-guard-contract.py` field shape (`**Property.**`/`**Assembly.**`/`**Mutation matrix.**` at line start); lint now green (1 entry, 7 matrix rows).
3. Observability `discoverability_test.expected_output` reduced to single token `present` — a multi-word value tokenizes to one whitespace-containing token and is rejected as prose by Phase 4.7 / preflight Check 10.
4. Pyramid verdicts live in a separate `### Pyramid` block — never folded into the weighted Farley score (score semantics preserved).

### New Considerations Discovered

- Sibling-boundary lock: measured per-test/suite budgets are #9763's scope; this mechanism flags *cost signals* only — the boundary line is mandatory in the agent text.
- All cited issues/PRs verified live: #9762/#9763/#8659/#7942/#3531/#4133/#8593/#3216/#9771 OPEN; #9751 MERGED.
- Halt gates checked: 4.6 User-Brand (threshold `aggregate pattern` — pass), 4.7 Observability (5 fields, allowlisted verb `grep`, <15 s command — pass), 4.8 PAT (clean), 4.9 UI wireframe (no UI surface — skip), 4.10 Encryption (no store/connection — skip), 4.11 Guard Contract (lint green — pass), 4.12 Scope Check (all asks mapped — pass).

## Overview

Soleur's review pipeline scores test quality per-test (Farley's eight properties, via `test-design-reviewer`) but nothing checks a diff's test *mix*: whether new tests sit at the right pyramid layer, whether a new end-to-end test carried a justification, or whether a new test looks expensive enough to break the fast-feedback budget the owner set (a ~25-minute local `ship` battery on PR #9751 motivated this). This plan adds a pyramid/budget check to the existing test-review lane and a layer-naming instruction at plan/work time — the two cheapest candidates in issue #9762 — plus a committed fixture pair that proves the mechanism fails an unjustified slow-E2E diff and passes a fast unit-test diff.

Spec lacks valid `lane:` — no spec.md existed at plan time; defaulted to cross-domain (TR2 fail-closed).

## Decision (issue AC 2)

**Extend `test-design-reviewer` + add the `plan`/`work` layer instruction — no new skill.** This is the issue's proposals 1+2 combined. Proposal 3 (standalone `testing-strategy` skill) is deferred to #9771 per the issue's own ordering ("only if 1–2 prove insufficient"). Recorded on the issue at https://github.com/jikig-ai/soleur/issues/9762#issuecomment-6063533523.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #9762 OPEN; motivating PR #9751 MERGED; sibling issue #9763 OPEN — #9763 owns *measured* budgets on the local tier (`scripts/test-all.sh`, per-suite caps). This plan's boundary is *diff-time review of newly added tests*; no overlap.
- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` exists on `origin/main` (verified: Farley 8-property weighted scorer, `model: inherit`).
- "No test pyramid in repo" verified: `grep -rn "test pyramid|test-pyramid|testing-strategy" plugins/ knowledge-base/engineering/ scripts/` → zero hits.
- ADR corpus check for the proposed mechanism (extend an agent prompt): nearest neighbors are ADR-238 (TEST_GROUP taxonomy = CI matrix topology — a *sharding* axis, not a pyramid layer; no conflict), ADR-262 (path-gates self-test mutation batteries to CI — consistent direction), ADR-177 (runner result taxonomy). No ADR's Alternatives-Considered rejected "extend a review agent". No ADR is needed in return: no ownership/substrate/trust-boundary change.
- "Soleur's only test-quality agent is `test-design-reviewer`" verified — it is the test-quality seat (review/SKILL.md conditional agent 13).

### Property List (Phase 0.6b)

- P1: a diff adding an unjustified slow e2e test produces a *failing* review verdict.
- P2: a diff adding a fast unit test passes the review.
- P3: pyramid-layer intent is declared at plan/work time, not only judged at review time.
- P4: the external-skill question is answered by an evidence-producing discovery run, recorded on the issue.
- P5: the fixture pair is committed and pinned so the mechanism stays re-verifiable after merge.

### Cut List (Phase 0.6b)

- Standalone `testing-strategy` skill → P1–P3 are covered by the reviewer extension + instruction pair (the issue's own ordering makes it conditional on insufficiency) → deferred to #9771.
- Deterministic lint script (`lint-test-pyramid.*`) → P1 is already bought by the review lane; a second enforcement mechanism duplicates the judgment path and the issue sizes this at ~150 lines — a script + fixtures + registry wiring does not fit and buys nothing the checklist doesn't.
- Measured per-test runtime enforcement → owned by #9763 (the reviewer cannot measure runtime at review time; it flags *cost signals* instead — an explicit boundary).
- New plugin component / README table updates → none added; `test-design-reviewer` is edited, not created.

### Community Discovery (Phase 1.5 + 1.5b — satisfies issue AC 1)

- **Stack-gap check (agent-finder trigger):** repo signatures are bun/TypeScript + bash, all covered by built-in agents; no uncovered stacks → `agent-finder` had no gap to query.
- **functional-discovery run** (three registries, query `test pyramid` / `testing strategy`, 2026-10-08):
  - `api.claude-plugins.dev`: `testability` (@different-ai, ~160★), `testing-patterns` (@groupzer0, ~147★), `test-automation-strategy` (@proffesor-for-testing) — SKILL.md bodies fetched for the top two: both are *authoring guidance* (teach the pyramid/TDD when writing tests).
  - `claudepluginhub.com`: `test-automation-expert` (@curiositech, 242★), `ordis-quality-engineering` (@tachyon-beep — pyramid distribution analysis, flaky-test diagnosis, anti-pattern review).
  - `anthropics/claude-plugins-official` (315 plugins): only `42crunch-api-security-testing` matched — unrelated.
  - **Verdict:** no external skill is a review-time *enforcement* mechanism that fails a diff for an unjustified slow e2e test; all candidates are advisory/educational. Adopting one would not satisfy AC 3. Run recorded on #9762 (comment link above).

### Repo findings

- Review spawn site: `plugins/soleur/skills/review/SKILL.md` "If PR contains test files" block → agent 13 (`test-design-reviewer`), spawn patterns `*.test.ts|js`, `*.spec.ts|js`, `test_*.py`, `*_test.rb`, `__tests__/`, `spec/`, `test/` dirs. The workflow port pins the same seat at `plugins/soleur/skills/review/workflows/review.workflow.js` (`'test-design'` entry, `lens:` string).
- Fixture convention: `plugins/soleur/test/fixtures/vendor-drift/*.diff` are committed unified diffs consumed by `plugins/soleur/test/vendor-drift-classify.test.sh`, which sources `plugins/soleur/test/test-helpers.sh` (`assert_file_exists` etc.).
- Suite registration: `scripts/test-all.sh` `SUITE_GLOBS` auto-registers `plugins/soleur/test/*.test.sh`. Affected selection is declared in `scripts/lib/test-affected-paths.sh`: `ALWAYS_ON_SUITES` for tree-global verdicts, `AFFECTED_<LABEL>_PATHS` blocks for edge-selected suites (label = registration label uppercased, non-alnum → `_`). The name-stem convention will NOT reach this suite's real deps (fixture dir + agent file), so an explicit `AFFECTED_` block is required; per file header, every edge set self-includes `scripts/lib/test-affected-paths.sh`.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` has three `## Test Scenarios` template blocks (MINIMAL/MORE/A LOT); `plugins/soleur/skills/work/SKILL.md` Phase 1 creates RED/GREEN/REFACTOR tasks ("Write failing test for [feature]").
- Agent compliance: `description:` updates stay within the ~2500-word cumulative budget (measured 1590 words across `plugins/soleur/agents/`); no SKILL.md `description:` is edited, so `SKILL_DESCRIPTION_WORD_BUDGET` does not fire.
- CLAUDE.md conventions applied: `agents/` holds only agent definitions (checklist text lives in the agent body, not a sibling reference); skills flat; no `version` keys anywhere.

### Institutional learnings applied

- `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` — verbose-gated lines invisible under test redirect; instrument before asserting.
- #8659 / #7942 (open, see overlap below) — new suite must use the test-helpers composed EXIT trap (no incident-sandbox leak) and must NOT be named `*.mutation.sh` (ungated naming).
- #3531 — keep the suite's per-assertion work well under hook/test timeouts (pure greps; sub-second).

### Related issues / PRs

- #9751 (merged) — the 25-minute `ship` battery that raised this.
- #9763 (open) — measured local-tier budgets; sibling, out of scope here.
- #8322 / ADR-238 / ADR-262 — affected-selection model and suite registration this plan plugs into.
- #9771 (filed) — deferred standalone-skill revisit.

### External research decision (Phase 1.6)

**Skipped.** The issue body embeds the primary-source research (Fowler CI / Practical Test Pyramid / Test Pyramid bliki, quoted verbatim), and the community-skill question is answered by the discovery run above. No external research adds signal.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "Nothing checks layer proportions or run-time budget" | Confirmed — `test-design-reviewer` scores Farley properties only; no pyramid gate exists. | FR-1 adds the check to that seat. |
| "a flag on any new test whose measured run time exceeds a per-test cap" | At review time there is no runtime measurement to read; measured budgets are #9763's scope. | Reviewer flags *cost signals* (browser boot, fixed delays, real services), never estimated seconds — stated verbatim in the agent text. |
| "Fix-Size: 150 lines / 4 files" | ~230 lines / 7 files — the fixture pair + pin suite + affected-index edit are the AC-3 mechanism, which the estimate didn't count. | Deviation recorded; still single-PR sized. |

## Functional Requirements

- **FR-1 — Pyramid & Fast-Feedback check in `test-design-reviewer`.** Add a `## Pyramid & Fast-Feedback Check` section to `plugins/soleur/agents/engineering/review/test-design-reviewer.md`: a layer-classification table (unit / integration / e2e — path, import, and cost signals), a justification-marker convention (`pyramid-justified: <reason>` in the added test file, or a `## Test Pyramid` block in the PR body), and three verdict rules that produce findings in a **separate** `### Pyramid` verdict block — never folded into the weighted 8-property score (the score's semantics stay Farley-only): **FAIL** when a diff adds an e2e-layer test with no justification marker; **WARN** when a new test carries fast-feedback cost signals (`waitForTimeout`/`sleep`/fixed delays, real browser or server boots, external network) with no stated necessity; **WARN** when coverage achievable at a lower layer is exercised only at e2e. The `### Pyramid` block lists one row per added test file — layer · signals · verdict. The section must state that review-time sees no measured runtimes (per-suite budgets are #9763's scope).
- **FR-2 — Layer naming at plan/work time.** (a) `plugins/soleur/skills/plan/references/plan-issue-templates.md`: in each of the three `## Test Scenarios` template blocks add one line — label each scenario's pyramid layer (unit / integration / e2e); prefer the lowest layer that exercises the behavior. (b) `plugins/soleur/skills/work/SKILL.md` RED-task creation block: each RED task names the test's pyramid layer in its title (`RED(unit): …`).
- **FR-3 — Fixture pair + pin suite.** Create `plugins/soleur/test/fixtures/test-pyramid/slow-e2e-no-justification.diff` (adds `apps/web-platform/e2e/checkout-flow.e2e.ts` — this repo's e2e convention is `*.e2e.ts` under `apps/web-platform/e2e/`, verified; `@playwright/test` import, `page.goto`, `page.waitForTimeout(15000)`, no marker) and `fast-unit.diff` (adds `apps/web-platform/test/order-total.test.ts` — unit tests live flat under `apps/web-platform/test/`, verified; pure unit test, no e2e signals). The reviewer's layer table must name BOTH e2e surface conventions (`e2e/` dir AND `*.e2e.ts`/`*.spec.ts` extensions) plus the generic signals (playwright/cypress/puppeteer import, real browser or server boot). Create `plugins/soleur/test/test-pyramid-fixtures.test.sh` (sourcing `test-helpers.sh`, composed EXIT trap per #8659 convention): **censuses** `plugins/soleur/test/fixtures/test-pyramid/*.diff` (glob count `== 2` — a census, not a name list, so a third fixture arriving unasserted goes red) and asserts per fixture: it parses as a unified diff adding a test file; the e2e fixture carries e2e-layer + slow signals and NO `pyramid-justified` marker; the unit fixture carries neither signal; and `test-design-reviewer.md` still defines the marker token and layer vocabulary the fixtures key on (drift pin). Instrument self-check: assert helper counters moved both directions.
- **FR-4 — Seat description accuracy.** `plugins/soleur/skills/review/SKILL.md` agent-13 bullet and `plugins/soleur/skills/review/workflows/review.workflow.js` `'test-design'` `lens:` string: append the pyramid/budget scope so routing text is truthful.
- **FR-5 — Recorded verification run (AC 3).** During work: apply the extended reviewer to each fixture (the harness reads the agent body and evaluates the fixture diff), record both verdicts — FAIL on `slow-e2e-no-justification.diff`, PASS on `fast-unit.diff` — in `knowledge-base/project/specs/feat-one-shot-9762-testing-strategy/fixture-verdicts.md` and as an issue comment.

## Implementation Phases

### Phase 1 — Reviewer extension + skill instructions (FR-1, FR-2, FR-4)

1. Extend `test-design-reviewer.md` per FR-1; update its `description:` to mention pyramid/fast-feedback (stays 1–3 sentences, no examples).
2. Land the two instruction edits per FR-2.
3. Land the two seat-description edits per FR-4.

### Phase 2 — Fixtures + pin suite + registration (FR-3)

1. Write the two `.diff` fixtures.
2. Write `test-pyramid-fixtures.test.sh` with instrument self-check; run it standalone → green.
3. Register the affected edge: `AFFECTED_PLUGINS_SOLEUR_TEST_TEST_PYRAMID_FIXTURES_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh` covering the agent file, the fixture dir, the suite itself, and the index file (self-inclusion contract).
4. Prove selection: `bash scripts/test-all.sh --print-selection` on this diff shows the suite selected.

### Phase 3 — Verification + records (FR-5)

1. Apply the extended checklist to both fixtures; record verdicts in `specs/feat-one-shot-9762-testing-strategy/fixture-verdicts.md` and comment on #9762.
2. Mutation-check the pin suite per `## Guard Contract` (at least rows M1–M3 + the harness row) — each must red the suite.
3. Run the new suite's affected selection and the suites referencing edited files (`rg -l 'test-design-reviewer|plan-issue-templates' plugins/soleur/test plugins/soleur/skills/*/test`).

## Files to Edit

- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` — new `## Pyramid & Fast-Feedback Check` section; `### Pyramid` output block; `description:` updated (FR-1)
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — layer line in all three `## Test Scenarios` blocks (FR-2a)
- `plugins/soleur/skills/work/SKILL.md` — RED-task titles name pyramid layer (FR-2b)
- `plugins/soleur/skills/review/SKILL.md` — agent-13 bullet gains pyramid/budget scope (FR-4)
- `plugins/soleur/skills/review/workflows/review.workflow.js` — `'test-design'` `lens:` string gains pyramid/budget scope (FR-4)
- `scripts/lib/test-affected-paths.sh` — `AFFECTED_PLUGINS_SOLEUR_TEST_TEST_PYRAMID_FIXTURES_TEST_SH_PATHS` block (FR-3 step 3)

## Files to Create

- `plugins/soleur/test/fixtures/test-pyramid/slow-e2e-no-justification.diff` (FR-3)
- `plugins/soleur/test/fixtures/test-pyramid/fast-unit.diff` (FR-3)
- `plugins/soleur/test/test-pyramid-fixtures.test.sh` (FR-3)
- `knowledge-base/project/specs/feat-one-shot-9762-testing-strategy/fixture-verdicts.md` (FR-5)
- `knowledge-base/project/specs/feat-one-shot-9762-testing-strategy/tasks.md` (pipeline artifact — listed so a diff-scope accounting stays honest)

## Open Code-Review Overlap

5 open `code-review` issues touch the planned paths; dispositions:

- **#8659** (33 suites replace the composed EXIT trap) — **acknowledge**: the new suite sources `test-helpers.sh` and does NOT hand-roll traps, so it does not become the 34th offender; the issue stays open for the existing suites.
- **#7942** (`*.mutation.sh` suites run in no gate) — **acknowledge**: naming constraint adopted — the suite is `test-pyramid-fixtures.test.sh`, registered via `SUITE_GLOBS`.
- **#4133** (Observability-block schema parity test for `plan-issue-templates.md`) — **acknowledge**: our edit touches only `## Test Scenarios` lines; the `## Observability` schema is untouched. Different concern; remains open.
- **#3531** (beforeAll hook-timeout flake) — **acknowledge**: `.test.sh` suite, no `bun test` hooks; constraint noted (keep assertions sub-second greps).
- **#8593 / #3216** (probe-gate window; old review findings) — **acknowledge**: no shared mechanism; noted for awareness.

## Test Scenarios

Each scenario names its pyramid layer per FR-2 (this plan dogfoods the instruction).

- **unit** — Given the pin suite and intact fixtures, when `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` runs, then it exits 0 and prints `0 failed`.
- **unit** — Given the `pyramid-justified` token deleted from `test-design-reviewer.md`, when the pin suite runs, then it exits non-zero (M1).
- **unit** — Given the marker inserted into the slow-e2e fixture, when the pin suite runs, then it exits non-zero (M2).
- **integration** — Given this branch's diff, when `bash scripts/test-all.sh --print-selection` runs, then output selects `plugins/soleur/test/test-pyramid-fixtures.test.sh` (AFFECTED_SELECTED 1).
- **review-lane** — Given the extended reviewer and `slow-e2e-no-justification.diff`, when the checklist is applied, then the verdict is FAIL citing the missing e2e justification (recorded in `fixture-verdicts.md`).
- **review-lane** — Given `fast-unit.diff`, when the checklist is applied, then the verdict is PASS with the file classified `unit` (recorded in `fixture-verdicts.md`).

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong test-review verdict on their PR — either a FAIL finding on a legitimate e2e test (friction; overridable via the `pyramid-justified` marker or PR-body block) or a silent pass (status quo ante). Concrete artifact: a false blocking-severity bullet in a `soleur:review` report.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the change is prompt text and committed test fixtures; no runtime path reads user data.
- **Brand-survival threshold:** aggregate pattern — a systematically-wrong check ships to every install via plugin update and degrades every test-touching review at once; per-incident severity is low and recoverable (advisory findings, explicit justification escape hatch), so no CPO sign-off gate. `user-impact-reviewer` will see the diff at review time regardless via the conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: pin suite green in test-all affected selection; verdict presence in reviews that touch test files
  cadence: per PR (affected run) / per test-touching review
  alert_target: suite failure reddens the gate; missing `### Pyramid` block is a review-visible absence
  configured_in: scripts/lib/test-affected-paths.sh (registration), plugins/soleur/agents/engineering/review/test-design-reviewer.md (checklist)
error_reporting:
  destination: suite failure prints FAIL lines to test-all stdout; review findings land in the review report
  fail_loud: pin suite exits non-zero on fixture/checklist drift
failure_modes:
  - mode: checklist vocabulary renamed in agent body while fixtures unchanged
    detection: pin suite's marker-token assertion
    alert_route: test-all red suite
  - mode: fixture edited to no longer exercise the FAIL path
    detection: pin suite's fixture-content assertions (M2/M3 shape)
    alert_route: test-all red suite
  - mode: reviewer silently skips the check (prompt lost in a rewrite)
    detection: review output lacks `### Pyramid` block on a test-touching diff
    alert_route: review-phase human/agent read; pin suite cannot see this — honest gap, recorded
logs:
  where: test-all stdout; fixture-verdicts.md for the AC-3 recorded run
  retention: repo / spec dir
discoverability_test:
  command: grep -q 'Pyramid & Fast-Feedback' plugins/soleur/agents/engineering/review/test-design-reviewer.md && printf 'present'
  expected_output: present
```

## Guard Contract

### Guard 1 — test-pyramid fixture pin suite

**Property.** The committed fixture pair remains valid evidence for the reviewer's pyramid check: the e2e fixture still exercises the FAIL path (adds an e2e-layer test carrying slow signals and no `pyramid-justified` marker), the unit fixture still exercises the PASS path, and the checklist vocabulary the fixtures key on is still defined in `test-design-reviewer.md`.

**Assembly.** Every `*.diff` under `plugins/soleur/test/fixtures/test-pyramid/` — discovered by **glob census** with a `== 2` count floor (not a name list; a third fixture landing unclassified reds the suite) — plus the `## Pyramid & Fast-Feedback Check` section's marker/layer vocabulary in the agent body. Chokepoint: every assertion flows through the suite's helpers sourced from `test-helpers.sh`.

**Mutation matrix.** Each row MUST drive the suite red (except the labelled must-PASS row); written from the design, pre-implementation:

| # | Mutation | Why it must red |
|---|----------|-----------------|
| M1 | Delete the `pyramid-justified` token from `test-design-reviewer.md` | vocabulary pin: fixtures key on a marker the checklist no longer defines |
| M2 | Insert `pyramid-justified:` into `slow-e2e-no-justification.diff` | the fixture stops exercising the FAIL path while its name still claims it |
| M3 | Repoint the e2e fixture's added path from `e2e/` to `test/` | mislabeled layer: the "e2e" fixture no longer classifies as e2e |
| M4 | Dispatch mutation: neuter the suite's own assert helper to always-pass | a guard that reports 0-checked-and-green is vacuous — instrument self-check must count both directions |
| M5 | Second-member row: truncate `fast-unit.diff` to a comment-only file (no `+++ b/` header) | the PASS fixture no longer parses as a diff — proves the suite checks each member, not just the first |
| M6 | Harness row (must-PASS variant): add a trailing comment line to `fast-unit.diff` | stays green — a harmless content addition is permitted; protects against an over-strict suite that rejects any edit |
| M7 | Harness row (must-RED): make the fail counter never increment in the suite itself | the instrument self-check exists precisely to catch a suite that can only ever pass |

**Order/lifetime note.** The property is about content, not ordering — a REORDER row is not applicable; the window the property defends is "the fixtures as committed", and every row observes that state directly.

**Anchor.** One diff CAN weaken both the fixtures and the checklist in the same commit — the pin proves consistency, not integrity. The out-of-commit anchor is the recorded AC-3 verdict pair (live checklist application posted to #9762 + `fixture-verdicts.md`), which a vocabulary drift cannot forge. Re-run the fixture review whenever the checklist section changes materially.

## Architecture Decision (ADR/C4)

**None required.** Detection reviewed: no ownership/tenancy move, no new substrate or integration pattern, no trust-boundary change, no ADR divergence. A prompt-level extension of an existing review seat is not architectural.

**C4 completeness check (all three files read):** `model.c4`/`views.c4`/`spec.c4` — enumerated per the mandate: (a) external human actors — none new (operator and contributor personas already modeled); (b) external systems/vendors — none (the community registries were queried at plan time for discovery only; the shipped mechanism makes no runtime calls); (c) containers/data-stores — none new; the `agents` container and `review` component (model.c4) already cover the edited surface; (d) access relationships — unchanged. The `review` component's description ("Multi-agent code review — panel scales to risk tier") remains true. Conclusion: no `.c4` edit needed.

## GDPR / Compliance Gate

Evaluated: no schema/migration/auth/API-route/`.sql` surfaces; none of the four extension triggers fire — (a) no LLM processing of operator-session data, (b) threshold is `aggregate pattern` not `single-user incident`, (c) no cron/workflow reading learnings/specs, (d) plugin-update is a *pre-existing* distribution channel carrying an edit, not a new surface. `soleur:gdpr-gate` not invoked.

## IaC / Encryption Posture

No infrastructure, no persistent store, no cross-component connection — Phase 2.8 and 2.11 skip by their own detection rules.

## Risks & Sharp Edges

- **False-positive FAIL on a legitimate e2e test** → mitigated by the `pyramid-justified:` marker (one comment) and the PR-body `## Test Pyramid` alternative; FAIL only for *missing* justification, never for layer choice alone.
- **Layer misclassification** → checklist carries path+import+cost signals and a confidence column; ambiguous cases degrade to WARN, not FAIL.
- **Review-time cannot measure runtime** → the agent text states this verbatim; measured budgets are #9763's scope — do not let the reviewer estimate seconds.
- **Suite conventions:** `test-helpers.sh` composed trap (#8659), NOT `*.mutation.sh` naming (#7942), sub-second greps only (#3531), `AFFECTED_` block not `ALWAYS_ON` (keeps the fast-feedback budget this feature exists to protect).
- **Issue's Fix-Size (150 lines / 4 files) exceeded (~230 / 10)** — the fixture pair, pin suite, and affected-index entry are the AC-3 mechanism itself; recorded as a deliberate deviation.
- **Resume prompt** for any stall: `soleur:work knowledge-base/project/plans/2026-10-08-feat-testing-strategy-checks-plan.md` on branch `feat-one-shot-9762-testing-strategy`, issue #9762.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Adopt a community skill (`testability`, `testing-patterns`, `test-automation-expert`, `ordis-quality-engineering`) | Rejected — all are authoring guidance, none fails a diff at review time (discovery run evidence above) |
| Standalone `testing-strategy` skill | Deferred → #9771; issue orders it "only if 1–2 prove insufficient" |
| Deterministic `lint-test-pyramid.*` script | Rejected at Phase 0.6b — duplicates the review lane's judgment for no property the checklist doesn't already buy |
| Do nothing / document-only | Rejected — the issue explicitly wants enforcement evidence, not prose |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a `functional-discovery` / `agent-finder` run recorded on the issue (does a suitable external skill already exist?)" | Research Insights §Community Discovery + issue comment 6063533523 | mapped |
| 2 | "a recorded decision — extend `test-design-reviewer`, new skill, or both" | `## Decision` + issue comment | mapped |
| 3 | "the chosen mechanism fails a review on a synthetic diff that adds a slow end-to-end test with no justification, and passes a diff that adds a fast unit test (a fixture pair, not a description)" | FR-3 fixtures + FR-5 recorded verdicts + Test Scenarios rows 5–6 | mapped |
| 4 | "plans and reviews tests against the test pyramid and a fast-feedback budget" | FR-1 (review) + FR-2 (plan/work) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `test-design-reviewer.md` edit | "Extend `test-design-reviewer` with a pyramid check" | asked |
| `plan-issue-templates.md` + `work/SKILL.md` edits | "A `plan`/`work` instruction that states the test layer for each acceptance criterion before writing the test" | asked |
| `review/SKILL.md` + `review.workflow.js` lens edits | — | inferred — justification: the seat's routing text must describe the new check or the spawn prompt lies about what the seat reviews |
| fixture `.diff` pair | "a fixture pair, not a description" | asked |
| `test-pyramid-fixtures.test.sh` | — | inferred — justification: committed fixtures with no consumer rot (repo convention: `vendor-drift` fixtures are consumed by `vendor-drift-classify.test.sh`); the pin also keeps the checklist vocabulary and the fixtures in lockstep |
| `test-affected-paths.sh` edit | — | inferred — justification: registration model (ADR-238/#8322) requires every suite classified; an unclassified suite is flagged RED by `lint-orphan-test-suites.sh` |
| `fixture-verdicts.md` | "recorded here" / "fails a review on a synthetic diff" | inferred — justification: AC 3 requires evidence of the verdicts, and the spec dir is the pipeline's artifact home |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/` (agent + skills + tests), `scripts/lib/` (affected index)
- Planned files: 6 edited + 4 created = 10 | Estimated changed lines: ~230
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC-1 (issue AC 1):** `functional-discovery`/`agent-finder` run recorded on #9762 — DONE at plan time (comment https://github.com/jikig-ai/soleur/issues/9762#issuecomment-6063533523); verify the comment exists and names the verdict.
- [ ] **AC-2 (issue AC 2):** the decision (extend `test-design-reviewer` + plan/work instruction; standalone skill deferred to #9771) is recorded on #9762 and in `specs/feat-one-shot-9762-testing-strategy/`.
- [ ] **AC-3 (issue AC 3):** the extended reviewer FAILs `slow-e2e-no-justification.diff` citing the missing justification, and PASSes `fast-unit.diff` with the file classified `unit`; both verdicts recorded in `fixture-verdicts.md` and posted to #9762.
- [ ] **AC-4:** `test-design-reviewer.md` contains `## Pyramid & Fast-Feedback Check` with the layer table, marker convention, FAIL/WARN verdict rules, and the no-measured-runtime boundary line.
- [ ] **AC-5:** all three `## Test Scenarios` template blocks in `plan-issue-templates.md` name pyramid layers; `work/SKILL.md` RED-task instruction names the layer.
- [ ] **AC-6:** `plugins/soleur/test/test-pyramid-fixtures.test.sh` exits 0 green standalone; Guard-Contract rows M1–M5 each drive it red (verified during work); `bash scripts/test-all.sh --print-selection` on this diff shows the suite AFFECTED-selected.
- [ ] **AC-7:** seat descriptions updated — `review/SKILL.md` agent-13 bullet and `review.workflow.js` `lens:` mention pyramid/budget.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed (inline — no subagent spawn available in this harness)
**Assessment:** Modest blast radius — extends an existing review seat's checklist rather than adding a component. Risks: (a) agent prompt growth on a per-PR seat (~55 lines added; acceptable), (b) layer misclassification → mitigated by a `confidence` column and WARN-vs-FAIL split (only the missing-justification case is FAIL), (c) boundary confusion with #9763 → resolved by the explicit "no measured runtime at review time" line in the agent text. No architecture change; no ADR.

### Product/UX Gate

**Tier:** none — no user-facing pages/flows; the mechanical UI-surface override does not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the file lists).
**Decision:** reviewed (inline)
**Agents invoked:** none — CPO-lens assessed inline per the new-capability mandate (this IS a new user-facing capability of the plugin): user benefit is faster-feedback discipline enforced at review; worst user outcome is a false FAIL, mitigated by the justification convention. CMO omitted with rationale: developer-facing pipeline tooling, no content/brand surface.
**Skipped specialists:** `soleur:marketing:copywriter` (no content surface) — `soleur:product:design:ux-design-lead` not required (no UI).
**Pencil available:** N/A (no UI surface)

#### Findings

No domain leader recommended specialists; nothing escalates.
