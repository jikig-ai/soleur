---
title: "feat: #9771 re-evaluation — residual testing-strategy machinery (no standalone skill)"
type: feat
date: 2026-10-19
slug: feat-testing-strategy-residual-machinery
branch: feat-one-shot-9771-testing-strategy-skill
issue: 9771
closes: 9771
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: #9771 re-evaluation — residual testing-strategy machinery (no standalone skill)

## Overview

Issue #9771 deferred a standalone `testing-strategy` skill behind a re-evaluation
trigger ("revisit after #9762 ships"). Both blockers shipped — #9762 via merged
PR #9766 (pyramid + fast-feedback check in `test-design-reviewer`), #9763 via
committed weights (`scripts/suite-durations.tsv` + `regenerate-shard-manifest.py`)
— and the follow-on #9855 arc closed with its machinery critiques adjudicated.

The re-evaluation question the issue asks is answered on evidence: **none of the
three trigger conditions hold, so no standalone skill is built.** Ruled by the
CTO role (inline sequential-fallback on this harness), recorded in
`knowledge-base/project/specs/feat-one-shot-9771-testing-strategy-skill/decision-challenges.md`
item 1. What remains is the residual machinery the issue comments explicitly
carry: the `*.test.sh` one-way unit ratchet's unweighed-new-suite gap, an
unwritten `test/<area>/` placement convention, and no written flaky-test policy.
This plan ships exactly those, in the existing lanes.

## Problem Statement / Motivation

The issue's own re-evaluation list:

1. *"Review findings recur where per-diff judgment is insufficient and a
   deterministic gate or standalone workflow is needed"* — does not hold. Where
   the arc needed determinism it shipped a lint script through the existing lane
   (`scripts/lint-integration-env-gates.sh`, registered in `scripts/test-all.sh`),
   and the five classifier defects were one-off bugs, all verified fixed on
   `origin/main`.
2. *"The pyramid check grows beyond what a reviewer's checklist can hold"* —
   does not hold. `test-design-reviewer.md` is 147 lines and absorbed every
   clarification; budget math lives in the #9763 weights machinery; suite-shape
   recurrence is guarded mechanically.
3. *"Founders' repos need a callable strategy skill independent of the review
   lane"* — does not hold. No demand signal exists in issues or comments.

The residual asks that DO remain (all quoted from issue comments):

- A new `*.test.sh`/`test-*.sh` spawning real subprocesses classifies unit
  forever ("one-way ratchet"); `regenerate-shard-manifest.py` auto-tables absent
  suites at the floor weight (~1.2 s), so a 155 s proxy suite is silently
  mispriced until measured runs accumulate. A review-time WARN is the cheapest
  signal that fits the #9763 boundary (no measured runtime at review).
- The `test/app/` namespaced route-test shape the parallel branch introduced is
  now dominant practice (617 subdir files vs ~238 flat under
  `apps/web-platform/test/`) but no written convention canonizes it.
- No written flaky-test policy exists, though the machinery pieces do
  (Playwright `retries: 1` on CI; scheduled-leg red → `ci/integration-suites`
  auto-filing).

## Research Insights

**Premise validation (Phase 0.6).** Every cited premise verified against
`origin/main`: #9762 CLOSED (PR #9766 MERGED 2026-10-09); #9763 CLOSED;
#9855 CLOSED; PR #9861 closed unmerged (superseded WIP draft). All four
"parallel implementation" machinery diffs from branch
`feat-9855-pyramid-audit-remediation` (commit `e22b2ef752`, present locally, no
branch contains it — superseded) are **already adopted on main**, verified
byte-present: `hasTests`/`TEST_RE` narrowed to `\.e2e\.[jt]sx?$`
(`review.workflow.js:152`, `fix-round-seats.sh:94`); `mu1.integration.test.ts`
rename; the named fixture-dir carve-out and `*.test.sh` declared exception at
`test-design-reviewer.md` layer table. Stale premises: the issue comment's
"dormant env-gated integration suites" deferral is **already shipped** —
`.github/workflows/scheduled-integration-suites.yml` (nightly 04:30 UTC, all
eight env gates) plus the `lint-integration-env-gates.sh` dormancy guard.

**Property List (Phase 0.6b).**

- P1 pyramid layering enforced at review → OWNED by `test-design-reviewer` (#9762).
- P2 measured budget enforcement → OWNED by `suite-durations.tsv` weights (#9763).
- P3 dormant-suite durability → OWNED by `lint-integration-env-gates.sh` + scheduled leg.
- P4 written flaky-test policy → PARTIAL: machinery exists, policy unwritten.
- P5 cost-shape awareness for new subprocess fan-out suites → PARTIAL: declared
  exception covers duration enforcement; the unweighed-NEW-suite nudge is missing.
- P6 written placement convention → UNOWNED (dominant in practice, unwritten).
- P7 callable strategy skill → trigger 3, no demand evidence.

**Cut List (Phase 0.6b).**

- Standalone `testing-strategy` skill → buys P7 (no demand) and nominally
  P4–P6, each closed cheaper in existing files → CUT.
- New pyramid layer / "subprocess fan-out" promotion vocabulary → violates the
  #9763 review-time boundary (no measured runtime); floor weights already
  auto-cover → CUT.
- Re-running the pyramid census/audit as a recurring mechanism → #9855 shipped
  the guards for recurrence → CUT.

**Relevant file paths.**

- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` — layer
  table + verdict rules (the edit target).
- `plugins/soleur/test/test-pyramid-fixtures.test.sh` — fixture pin suite:
  CENSUS (glob census over ALL entries — a new fixture reds it), PARSE, ROLE,
  DRIFT blocks.
- `plugins/soleur/test/fixtures/test-pyramid/` — currently exactly 2 `.diff`
  files (`fast-unit.diff`, `slow-e2e-no-justification.diff`); census pinned.
- `apps/web-platform/test/README.md` — env-gate table, dedicated-project
  guidance, teardown contract; no placement convention, no flaky policy.
- `scripts/suite-durations.tsv` — committed weights; header carries
  `default-weight-ms=1184`; generator floors unmeasured suites.
- `scripts/regenerate-shard-manifest.py` — "absent from every timing input is
  still tabled, at the floor weight".
- `apps/web-platform/playwright.config.ts:17` — `retries: process.env.CI ? 1 : 0`.

**Institutional learnings.**

- `2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md`
  — a new suite lands unpriced/mispriced until the next regen; motivates the
  honest-floor WARN.
- `2026-10-08-a-review-guard-that-cannot-be-spawned-on-its-own-target-class-fails-open.md`
  — trigger reachability precedes verdict correctness; the WARN's spawn
  predicate is `hasTests`/`TEST_RE`, which already matches `*.test.` — covered.
- `2026-10-09-e2e-demotion-destination-is-invocation-tests-not-a-harness.md` —
  "integration layer" is signal-defined, not directory-defined; census numbers
  in issue bodies are stale-by-default — re-verified all counts live.
- `2026-10-09-a-pyramid-marker-covers-a-files-tests-not-its-dominant-signal.md` —
  per-test classification, not dominant-signal tallies.

**Related issues/PRs.** #9762, #9763, #9855 (closed); PRs #9766 (merged),
#9861 (closed unmerged); commit `e22b2ef752` (superseded branch, adopted).

**Functional overlap (Phase 1.5b).** Ran for the parent scope under #9762
(functional-discovery, 3 registries): external skills are authoring guidance
only — none enforces at review. The residual items here are repo-internal
(reviewer rule + repo README); no community analog applies.

**Community discovery (Phase 1.5).** Internal machinery only; no uncovered
stack detected → skipped.

**Skill description budget (Phase 1.8).** No `SKILL.md` `description:` edit is
candidate → skipped.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "rls-fuzz named-dir over-classification" (needs fix) | Fixed — carve-out text live at `test-design-reviewer.md` ("engaged only for specs consuming the fixture's services") | Adopted; nothing to do |
| "`*.test.sh` one-way unit ratchet" — "remains #9771 scope" | Partially: declared exception owns runtime enforcement; the unweighed-new-suite gap is real (`default-weight-ms=1184` floor until regen measures) | FR-1 WARN rule |
| "hasTests regex wider than the classifier" | Fixed — `\.e2e\.[jt]sx?$` on main in both byte-pinned copies | Adopted |
| "mu1-integration.test.ts hyphen escape" | Fixed — renamed `mu1.integration.test.ts` on main | Adopted |
| "e2e/vitest/bun layers carry no committed weight" | Resolved — "formally stays #9763's boundary; no action" per issue comment; adjudicated (decision item 2) | No action |
| "dormant env-gated integration suites… testing-strategy scope" | Already shipped — `scheduled-integration-suites.yml` + `lint-integration-env-gates.sh` on main | No action; stale deferral |
| "`test/app/` vs flat — worth canonizing one shape" | Subdirs dominate 617:238 in practice; no written convention | FR-2 README convention |
| "flaky-test policy" (skill contents) | Machinery exists (CI retries=1, auto-filing); no written policy | FR-3 README policy |

## Proposed Solution

Three small, in-lane changes plus the issue bookkeeping:

- **FR-1** — `test-design-reviewer.md`: add a WARN verdict rule closing the
  unweighed-new-suite gap. A NEW `*.test.sh` or `test-*.sh` file added in the
  diff that carries subprocess-fan-out signals (spawned server/proxy/stub
  processes, `nohup`/`&` background procs, pgid-reaper plumbing, bound ports)
  AND whose suite label carries no `measured` or non-default `floor` row in
  the committed `scripts/suite-durations.tsv` (the reviewer greps the TSV for
  the label — an auto-tabled default-floor row does not satisfy this) → WARN:
  commit an honest `floor` estimate so shard legs do not price it at the ~1.2 s
  default until measured runs land. WARN-only; signals-not-seconds; consistent
  with the declared exception (the trigger is spawn signals + absent weight,
  never duration alone).
- **FR-2** — `apps/web-platform/test/README.md`: a "Test file placement"
  convention — new tests namespace under `test/<area>/` mirroring the SUT path
  (`test/app/` for `app/` routes/pages, `test/server/` for `server/`,
  `test/api/` for API handlers); flat `test/*.test.ts` is grandfathered, no
  mass move; `*.integration.test.*` keeps its suffix and env-gate table row.
- **FR-3** — same README: a "Flaky-test policy" section canonizing existing
  machinery — CI-only retry cap (`playwright.config.ts` `retries: 1`, never
  raised per-suite to mask a flake); a flake gets a filed issue and may be
  `fixme`/skipped only with the issue ref; the nightly leg auto-files
  `ci/integration-suites` on red and auto-closes on green.
- **FR-4** — extend `test-pyramid-fixtures.test.sh`: census covers the two new
  fixtures; ROLE assertions map `subprocess-fanout-unweighed.diff` → WARN role
  and `pure-sh-assertions.diff` → no-WARN role; DRIFT block pins the WARN
  vocabulary in the agent file.
- **FR-5** — bookkeeping: post the ruling + adjudication summary as a comment
  on #9771; PR body carries `Closes #9771` (re-open trigger named in the
  comment).

## Technical Considerations

- The WARN must never fire on duration alone — the declared exception owns
  that; the new condition is spawn-signals + absent weight row. Keep the
  exception text and the WARN rule cross-consistent (the exception already
  names `suite-durations.tsv`).
- The reviewer already scopes to "adds or modifies" — the rule inherits
  NEW-file-only reach; no edit can re-rate existing suites.
- Both sh-test spellings are covered (`*.test.sh` and `test-*.sh`) — the
  orphan lint's own header records the `test-*.sh` convention as a separate
  producer family; the ratchet exists for both.
- No `hasTests`/`TEST_RE` change needed — both already match `*.test.`; the
  `test-*.sh` convention is reachable via the `(^|/)tests?/` dir arm for
  `tests/scripts/` (verified: `TEST_RE` matches `(^|/)tests?/`). The workflow
  trigger is not widened.
- NFR impacts: none material — review-lane prompt text and repo docs; no
  runtime path changes.
- Invocation surfaces for `test-design-reviewer` (grepped 2026-10-19):
  `review/SKILL.md`, `review.workflow.js`, `fix-round-seats.sh`,
  `deepen-plan/SKILL.md`, `work/SKILL.md`, the `cursor/agents/` mirror and
  `agents.manifest.json` — all diff-shaped review contexts; the WARN bullet
  lives under the existing "When a diff adds or modifies test files" scope, so
  no non-diff fallback string is needed.
- Prescribed-command verification (run at plan time, 2026-10-19):
  `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` → ALL PASS, 50
  assertions, 0 failed on the pre-change tree.

## Files to Edit

- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` — FR-1 WARN
  rule in `### Verdict rules` + one cross-ref clause in the unit-row declared
  exception pointing at it.
- `apps/web-platform/test/README.md` — FR-2 + FR-3 sections.
- `plugins/soleur/test/test-pyramid-fixtures.test.sh` — FR-4 census/ROLE/DRIFT
  extension (census count moves 2 → 4; document the new roles in the header).

## Files to Create

- `plugins/soleur/test/fixtures/test-pyramid/subprocess-fanout-unweighed.diff` —
  unified diff adding a new `.test.sh` that boots a stub server (`&` + pgid
  reaper + bound port), carries no `suite-durations.tsv` row → WARN role.
- `plugins/soleur/test/fixtures/test-pyramid/pure-sh-assertions.diff` — unified
  diff adding a `test-*.sh` of pure greps/assertions, no spawn signals →
  no-WARN role (also exercises the second filename convention).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a
  missed or spurious WARN bullet in `soleur:review` output on a PR touching
  test files; the developer sees review noise, not product behavior.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — the diff is an agent prompt, a test README, and fixture
  files; no secrets, no runtime paths, no user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the deliverable is internal
  machinery + docs; the worst case is reviewer noise, which is why this is not
  single-user-incident.

## Observability

Skipped — the Files-to-Edit/Create list touches no code-class path under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and
introduces no infrastructure surface (agent prompt text, repo README, test
fixtures, a `.test.sh` pin suite). The pin suite IS the change's own
observability: it fails loudly in `test-all.sh` on drift.

## Encryption Posture

Skipped — no persistent data store and no new cross-component/network
connection is introduced.

## Guard Contract

### Guard 1 — test-pyramid fixture pin suite (extended)

**Property.** Every file under `plugins/soleur/test/fixtures/test-pyramid/`
parses as a unified diff adding exactly one test file, maps to a declared
verdict role, and the agent vocabulary each role keys on still exists in
`test-design-reviewer.md` — so a fixture drift or a vocabulary deletion is
caught, and an unclassified new fixture reds the census.

**Assembly.** The suite's case table plus its glob census over
`plugins/soleur/test/fixtures/test-pyramid/*` (all entries, not only `*.diff`
— a third+ file under any name reds). DRIFT asserts on
`test-design-reviewer.md` tokens (marker token, layer/verdict vocabulary,
FAIL rule, and the new WARN vocabulary) and the four restatement sites
(`review/SKILL.md`, `review.workflow.js`, `plan-issue-templates.md`,
`work/SKILL.md`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a fifth fixture file under `fixtures/test-pyramid/` without a census/role entry | RED — census glob counts all entries |
| 2 | Delete `subprocess-fanout-unweighed.diff` or strip its spawn-signal lines so the WARN-role content check cannot match | RED — PARSE/ROLE assertion fails |
| 3 | Remove the subprocess WARN vocabulary (the rule or its `suite-durations.tsv` anchor) from `test-design-reviewer.md` | RED — DRIFT token assertion fails |
| 4 | Narrow the census glob to `*.diff` present before this change (guard stops seeing new members) | RED — adding any member then passes unnoticed; own-dispatch row |
| 5 | Neuter the suite's `assert_eq` helper to always-pass | RED — the instrument self-test drives both verdict directions before assertions run (existing anti-vacuity block) |
| 6 | Must-PASS input: `pure-sh-assertions.diff` — a new `test-*.sh` with no spawn signals | PASS — proves the suite does not reject every member |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-evaluate when any of these hold: … deterministic gate or standalone workflow is needed … beyond what a reviewer's checklist can hold … callable strategy skill independent of the review lane" [issue #9771 body] | Overview ruling + decision-challenges.md item 1; AC-7 | mapped — triggers evaluated, none hold |
| 2 | "Adding a 'subprocess fan-out' promotion signal remains #9771 scope … a cost-signal heuristic would be the right shape for the strategy skill to design deliberately" [issue comment] | FR-1 / Phase 1 / `test-design-reviewer.md` edit | mapped |
| 3 | "Worth canonizing one shape in the machinery" (`test/app/` namespaced vs flat) [issue comment] | FR-2 / Phase 2 / `test/README.md` | mapped |
| 4 | "the dormant env-gated integration suites … deferred here as squarely testing-strategy scope" [issue comment] | — | descoped — justification: already shipped on main (`scheduled-integration-suites.yml` + `lint-integration-env-gates.sh`), premise stale |
| 5 | "Decide whether the manifest should cover them or formally remain #9763's boundary" (e2e/vitest/bun weights) [issue comment] | — | descoped — justification: resolved by the issue's own later comment ("formally stays #9763's boundary; no action"); adjudicated decision-challenges item 2 |
| 6 | "concrete diffs worth adopting or adjudicating here" (branch `feat-9855-pyramid-audit-remediation` `e22b2ef752`) [issue comment] | — | descoped — justification: every machinery diff verified already on `origin/main`; adjudicated decision-challenges item 3 |
| 7 | "flaky-test policy" [issue #9771 title] | FR-3 / Phase 2 / `test/README.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `test-design-reviewer.md` WARN rule | "the `*.test.sh` one-way unit ratchet" / "subprocess fan-out … remains #9771 scope" | asked |
| `test/README.md` placement convention | "Worth canonizing one shape in the machinery" | asked |
| `test/README.md` flaky-test policy | "flaky-test policy" (issue title) | asked |
| `test-pyramid-fixtures.test.sh` + 2 fixtures | — | inferred — justification: `cq-write-failing-tests-before` + the pin suite's census reds on any new fixture; the WARN rule needs committed coverage or the drift pin rots |
| #9771 comment + `Closes #9771` | "revisit after #9762 ships" / "Re-evaluate when any of these hold" | inferred — justification: the issue asked for the re-evaluation; posting the ruling and closing is how a re-evaluation resolves |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (agents + test), `apps/web-platform` (test README)
- Planned files: 5 | Estimated changed lines: ~160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: `plugins/soleur/agents/engineering/review/test-design-reviewer.md`
  carries a WARN verdict rule for a NEW `*.test.sh`/`test-*.sh` carrying
  subprocess-fan-out signals with no `floor`/`measured` row in
  `scripts/suite-durations.tsv`, WARN-only and consistent with the unit-row
  declared exception. Verify:
  `grep -n 'suite-durations' plugins/soleur/agents/engineering/review/test-design-reviewer.md`
  shows the anchor in the new rule.
- [ ] AC-2: `apps/web-platform/test/README.md` carries a "Test file placement"
  convention naming `test/<area>/` namespacing and the grandfathered-flat rule.
  Verify: `grep -n 'placement' apps/web-platform/test/README.md` hits.
- [ ] AC-3: `apps/web-platform/test/README.md` carries a "Flaky-test policy"
  section naming the CI retry cap, the issue-ref requirement for skip/fixme,
  and the `ci/integration-suites` auto-filing. Verify:
  `grep -n 'flaky' apps/web-platform/test/README.md` hits.
- [ ] AC-4: `plugins/soleur/test/test-pyramid-fixtures.test.sh` census covers
  exactly 4 fixture entries with roles declared for the two new diffs, and the
  DRIFT block pins the WARN vocabulary. Verify:
  `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` exits 0.
- [ ] AC-5: Both new fixtures parse as unified diffs adding exactly one test
  file (`--- /dev/null`, `+++ b/`, `@@` hunk); the WARN-role fixture carries
  spawn signals (`&`, reaper, port) and no weight row.
- [ ] AC-6: A comment on #9771 records the ruling (triggers do not hold), the
  adjudications, and the re-open trigger; the PR body carries `Closes #9771`.
- [ ] AC-7: The diff creates no `plugins/soleur/skills/testing-strategy*`
  path. Verify:
  `git diff --name-only origin/main...HEAD | grep -c 'skills/testing-strategy'`
  returns 0.

## Implementation Phases

1. **Reviewer WARN rule** — edit `test-design-reviewer.md` `### Verdict rules`
   (add the WARN bullet) + unit-row exception cross-ref. Failing test first:
   extend the pin suite's DRIFT block to pin the new vocabulary before writing
   the rule (cq-write-failing-tests-before ordering per tasks.md).
2. **README conventions** — add "Test file placement" and "Flaky-test policy"
   sections to `apps/web-platform/test/README.md`.
3. **Fixtures + pin** — write the two `.diff` fixtures; extend census (2→4),
   ROLE, DRIFT in `test-pyramid-fixtures.test.sh`; run the suite green.
4. **Bookkeeping** — `gh issue comment 9771` with the ruling + adjudications;
   PR body `Closes #9771`.

## Test Scenarios

- `unit` — Given a fixture diff adding a `.test.sh` that boots a stub server
  (`&`, pgid reaper, port bind) with no `suite-durations.tsv` row, when the
  pin suite runs ROLE checks, then the file maps to the WARN role and the
  agent md contains the WARN vocabulary. Command:
  `bash plugins/soleur/test/test-pyramid-fixtures.test.sh` → prints per-case
  pass lines, exits 0.
- `unit` — Given a fixture adding a `test-*.sh` of pure greps/assertions, when
  ROLE checks run, then it maps to the no-WARN role (must-PASS input).
- `unit` — Given a fifth unclassified file added under
  `fixtures/test-pyramid/` (mutation), when the census runs, then the suite
  reds (mutation matrix row 1).
- `unit` — Given the WARN vocabulary removed from the agent md (mutation),
  when DRIFT assertions run, then the suite reds (row 3).
- Verify — `grep -n 'suite-durations' plugins/soleur/agents/engineering/review/test-design-reviewer.md`
  hits inside the new WARN bullet.
- Verify — `grep -n 'placement\|flaky' apps/web-platform/test/README.md` hits
  both new sections.
- Verify — `git diff --name-only origin/main...HEAD | grep -c 'skills/testing-strategy'`
  returns `0`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal test-review machinery and
repo documentation. Product/UX gate: no UI-surface file in Files to
Create/Edit (mechanical override did not fire) → NONE.

## Open Code-Review Overlap

None — checked 2026-10-19: open `code-review` issues fetched via
`gh issue list --label code-review` and body-searched for every planned path
(`test-design-reviewer.md`, `test/README.md`, `test-pyramid-fixtures.test.sh`,
`fixtures/test-pyramid`, `suite-durations.tsv`); zero matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails deepen-plan Phase 4.6 — filled above.
- The census count pin (4) must be stated as a count, not an enumeration of
  names — names drift; the glob census is the authority.
- WARN rule wording must not re-open the `*.test.sh` ratchet the declared
  exception closed: trigger = spawn signals + absent weight row, never
  "duration alone".
- Do NOT paste the issue body verbatim anywhere it could read as a live
  `## Scope Check` heading.
- `test-*.sh` under `tests/` is a separate producer family than `*.test.sh`
  (orphan-lint header documents the gap) — the WARN covers both spellings;
  extending the orphan lint's producer is recorded as adjacent-out-of-scope,
  not silently folded in.

## Context

- Ruling record:
  `knowledge-base/project/specs/feat-one-shot-9771-testing-strategy-skill/decision-challenges.md`
  (items 1–3; CTO role executed inline — sequential-fallback, no Agent tool on
  this harness).
- The `test-*.sh` producer gap in `lint-orphan-test-suites.sh` (its own header
  records it as a known gap needing a second producer keyed on `test-*.sh`) is
  adjacent machinery but outside #9771's carried scope — noted here so it is
  not silently folded; a follow-up issue is the honest vehicle if it recurs.

## References

- Issue: #9771 (this re-evaluation); blockers #9762, #9763; audit arc #9855.
- Merged PR: #9766 (test-design-reviewer pyramid check).
- Superseded branch: `feat-9855-pyramid-audit-remediation` @ `e22b2ef752`.
- Learnings: `2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md`,
  `2026-10-08-a-review-guard-that-cannot-be-spawned-on-its-own-target-class-fails-open.md`,
  `2026-10-09-e2e-demotion-destination-is-invocation-tests-not-a-harness.md`,
  `2026-10-09-a-pyramid-marker-covers-a-files-tests-not-its-dominant-signal.md`.
