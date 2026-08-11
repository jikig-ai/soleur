---
title: "feat: Guard Contract at plan time, class-scoped fixes at work time, structural enumeration at review time"
date: 2026-08-11
slug: feat-guard-contract-assembly-and-pipeline-friction
branch: feat-one-shot-guard-contract-assembly
lane: procedural
type: enhancement
issue: 5095
closes: [5095, 5097]
priority: p1
domain: engineering
brand_survival_threshold: none
---

## Overview

The preflight Check 10 execution-boundary work (merged 2026-08-10) absorbed five adversarial
review rounds. Each round found real defects inside the previous round's fixes, and roughly twenty
findings collapse to a single class:

> A guard's WINDOW, CHOKEPOINT, or IDENTIFIER SET was narrower than the property it named.

Those were not five discoveries. They were one enumeration nobody performed, found five times by
different means, at roughly 880k subagent tokens and five CI cycles.

The root cause sits at plan time. That plan specified CONTROLS ("a bubblewrap sandbox with these
mounts") and thirteen Test Scenarios all of the shape "command X produces terminal Y". None had the
shape "mutation M drives guard G red". For a change whose deliverable WAS guards, the test scenarios
exercised the thing being guarded rather than the guards. The guards were therefore written as
assertions about the implementation as it happened to be shaped, and `sandboxWindow()` — a helper
invented at work time — silently became the operative definition of "the mount set".

This plan moves the correction upstream. It introduces a **Guard Contract**: before a guard is
written, its author names the property, enumerates the structural ASSEMBLY the property quantifies
over, and derives a mutation matrix. Members drift; assembly is structural. The assembly field is
the one whose absence cost the five rounds.

It then carries the same insight into `/work` (fix the class, not the instance), `/review`
(one structural-enumeration seat instead of N adversarial seats each finding one instance), and a
mechanical gate for the specific recurring idiom.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Codebase reality (verified 2026-08-11) | Plan response |
|---|---|---|
| Rule corpus at WARN, `B_ALWAYS=44400` | `lint-agents-rule-budget.py` reports `B_ALWAYS=44478 >= 44000`, ratchet 46000 | Confirmed WARN. All edits land in skill BODIES; zero `AGENTS.rules.md` additions. Minor numeric drift is immaterial — the tier is what governs. |
| ADR ordinal collisions are recurring | Max ordinal on `main` is **176**; `check-adr-ordinals.sh:41` carries `ALLOWED_COLLISIONS=(ADR-027 ADR-030 ADR-031 ADR-033 ADR-038)` | Confirmed. Five grandfathered collisions are encoded in the guard itself. Scope decision below. |
| #5095/#5097 propose pre-applying the `secret-scan-allow-rename` label | Both OPEN. `git grep -ln "secret-scan-allow-rename" -- plugins/soleur/skills/` returns **zero** — the fix has not landed and #5097's own event-grep close criterion is unmet | Confirmed unfixed. But see next row — the proposed remedy is the weaker of the two options. |
| "decide between pre-applying the label vs exempting archival destinations" | `rename-guard.sh:78-86` tests **only the rename TARGET** against the gitleaks allowlist. `archive-kb.sh:166` does `git mv <artifact> <same-dir>/archive/<ts>-<name>`. The allowlist regex `knowledge-base/(?:plans\|project/(?:plans\|specs))/.*\.md$` matches **both** source and destination (`.*` spans `archive/`) | **Neither option as filed.** A third, strictly better fix: exempt renames whose SOURCE is already allowlisted. Rationale below. |
| D should be "a review bullet, a lint, or both" | `review/SKILL.md:1177` already documents this class *and* its disposition: *"the disposition for a recurring documented class is a mechanical gate, not another learning"* | The repo's own guidance answers it: **both**, lint primary. |
| A broad window/closure lint is feasible | Naive predicate (window idiom + closure assertion co-occurring) matches **30+** test files — overwhelmingly false positives | Narrow the predicate to named window helpers: **7 helpers across 3 files** repo-wide. Tractable, with a grandfather set. |

### Why the source-allowlist exemption beats pre-applying the label

gitleaks does not scan files matching a path allowlist. `rename-guard` exists because gitleaks
evaluates the allowlist against the rename DESTINATION and does not re-scan content against the
source path — so `git mv server/secrets.ts knowledge-base/project/plans/x.md` launders a real secret
past the gate.

That laundering requires the source to be OUTSIDE the allowlist. When both source and destination are
allowlisted — precisely what `archive-kb` does on every one-shot run — the content was already
unscanned before the rename. No new unscanned surface is created, so there is nothing to launder.

Pre-applying the label (as #5095 proposes) **disarms the guard for the entire pull request**,
including any genuine outside→allowlist rename that happens to share the PR. The source-allowlist
exemption is evaluated per rename pair and preserves the guard's actual property.

This is the same defect class the rest of this plan addresses, pointing the other way: the guard's
chokepoint (target-only) is WIDER than the property it names (no NEW laundering), so it fires on a
population that cannot be a laundering vector. Fixing it with the new Guard Contract is the
dogfooding proof that the contract works on a real guard.

## Scope Decision (made at plan time, not assumed)

**A–D and F ship in this PR. E splits to its own tracked issue.**

**A–D together.** One insight, four owning skills, and the edits are mutually referential — `/work`'s
class-scoped rule and `/review`'s enumeration seat are both derivable from the plan-time assembly
field. Splitting them would produce three PRs each carrying a partial statement of one idea.

**F rides along.** Three reasons, in ascending order of weight: it is small (one predicate plus its
test); it closes two open issues, making net-issue-flow negative even after E's new issue; and
decisively, **F is an instance of the very class A–D exists to catch**. Applying the new Guard
Contract to a real, independently-filed guard defect in the same PR is the strongest available
evidence that the contract is usable rather than ceremonial.

**E splits.** Recorded reasoning, because this reverses part of the brief:

1. E shares no conceptual surface with the guard-contract insight. Bundling it makes one PR argue two
   unrelated theses, which is exactly the review-surface bloat that made the originating work
   expensive.
2. E is not small. "Ship assigns the ordinal and sweeps refs" requires enumerating across **all**
   `origin/*` refs (not `origin/main` — a branch-claimed ordinal is invisible to a `main`-scoped
   check), renaming the ADR file, rewriting its internal references, and sweeping code AND docs. The
   brief itself cites a 36-reference sweep.
3. That sweep is itself guard-shaped work whose failure mode is a narrow window — a sweep that
   reaches the ADR body and code but misses plans/specs/ACs is the documented #5990 defect. It
   deserves its own Guard Contract and mutation matrix, which means its own plan.
4. E touches `ship/SKILL.md` (2382 lines), the largest skill in the repo, on its merge-critical path.

Net issue flow: **-2** (close #5095, #5097) **+1** (filed E as #7446) = **-1**.

This is a judgment call on scope, not on merit — E is worth doing and the design sketch is recorded
in the filed issue so no analysis is lost.

## Guard Contract

This PR is guard-shaped work about guard-shaped work, so the contract applies to
itself. It did not hold on the first revision: review found all three guards
narrower than the properties below, and the corrected assemblies are recorded
here with the evasions that falsified the originals.

### Guard 1 — `scripts/lint-guard-contract.py`

**Property.** Every plan file declaring a Guard Contract has, for every guard
entry in every such section, a non-placeholder property, a non-placeholder
assembly, and a mutation matrix of at least three rows.

**Assembly.** The property quantifies over:

- Every `.md` under `knowledge-base/project/plans/` **recursively**, excluding
  any path with an `archive/` component. The original non-recursive glob missed a
  plan one directory deeper, and one such plan exists in the repo today.
- **Every** `## Guard Contract` section in a file, not the first, matched by
  prefix rather than exact string equality — `## Guard Contract (3 guards)`
  previously exempted a whole file.
- **Every** `### Guard` entry in each section, plus explicit rejection of
  mis-levelled or indented entries, which previously folded into the predecessor
  and inflated its matrix row count.
- The mutation-matrix table's **own span**, not any table in the entry.
- Fenced code blocks, masked out, so a pasted template is not a real entry.
- The lint's own dispatch: the sweep's file count and its exit path.
- Its wiring in `scripts/test-all.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the Assembly check | RED (MB-1) |
| 2 | Delete the matrix-row floor | RED (MB-2) |
| 3 | Delete the placeholder check | RED (MB-3) |
| 4 | Delete the zero-entry floor | RED (MB-4) |
| 5 | Delete the own-dispatch floor | RED (MB-5) |
| 6 | Delete the heading-level check | RED (MB-6) |
| 7 | Revert matrix counting to entry-wide | RED (MB-7, semantic) |
| 8 | Add a second non-compliant entry after a compliant first | RED (TS-6, fixture) |
| 9 | Neuter `fail()` to increment `PASS` | RED (TS-21, harness control) |

### Guard 2 — `scripts/lint-window-closure-assertion.py`

**Property.** A closure assertion fed by a named window helper carries a
per-helper declaration naming what the window is complete against, with a real
justification.

**Assembly.** The property quantifies over:

- Every `*.test.ts(x)` and `*.spec.ts(x)` under three roots —
  `apps/web-platform/`, `plugins/soleur/test/` and the repo-root `test/` — by
  directory walk, excluding vendored trees. The original walk read one suffix
  under two roots and included `node_modules`.
- **Every** helper per file across all declaration forms: `const/let/var`,
  `function`, `async`, `export default`, object properties, class methods and
  additional declarators.
- The closure-assertion set: array literals, `new Set([…])`, `toMatchObject`,
  `deepStrictEqual`, and a named SCREAMING_CASE const.
- The grandfather allowlist, keyed per helper, including its stale entries.
- The lint's own dispatch.

**Known-narrower than the property, deliberately:** the chokepoint is a
rebindable NAMING CONVENTION, so a rename silences the gate; an imported helper
is out of reach; a marker inside a string literal is not distinguished from a
comment. The `/review` bullet carries the wider judgement half.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the declaration check | RED (MB-1) |
| 2 | Delete the zero-dispatch floor | RED (MB-2) |
| 3 | Delete the justification requirement | RED (MB-3) |
| 4 | Delete the stale-allowlist check | RED (MB-4) |
| 5 | Truncate the walk to its first file | RED (TS-20, two-file fixture) |
| 6 | Relocate a fixture one directory deeper | still found (TS-8) |

### Guard 3 — `apps/web-platform/scripts/rename-guard.sh`

**Property.** A rename fails only when it moves content into a path whose
gitleaks exemption scope is **wider** than the source's — i.e. when it creates
newly-unscanned surface.

**Assembly.** The property quantifies over:

- Every rename and copy pair emitted by `git log --diff-merges=first-parent
  --diff-filter=RC --find-renames=5% --find-copies=5%`, with
  `core.quotePath=false`. The original scan missed merge-commit diffs entirely,
  classified a rename-plus-edit as D+A, and could not match quoted non-ASCII
  destinations.
- The `ALLOW_RES` array, consulted for BOTH source and target through one shared
  resolver, compared as **sets** rather than as booleans. The original boolean
  test conflated gitleaks' one global allowlist with its eighteen per-rule
  allowlists and exempted a genuine laundering rename.
- Both override paths (label, trailer) and the parser-failure and
  empty-allowlist exits, the latter now fail-closed.

**Known-narrower than the property, deliberately:** a rename whose similarity is
effectively zero is a delete-plus-add and cannot be classified as a rename by
git at any threshold; a plain add of a secret at an allowlisted path was never in
scope. Both are documented in `secret-scanning.md`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the scope-subset exemption | RED (MB-1, archival case becomes a violation) |
| 2 | Give the source a set matching everything | fails OPEN on TS-1 (MB-2) |
| 3 | Delete the low-similarity rename flags | RED (MB-3) |
| 4 | Delete the trailer override | RED (MB-4) |
| 5 | Revert to the old boolean source test | re-opens TS-10 (MB-5, semantic) |

## User-Brand Impact

**If this lands broken, the user experiences:** a `/plan` run that halts with a Guard Contract error
on a plan that has no guards in it, blocking the pipeline on a false gate; or, for F, a
`rename-guard` that stops failing on a genuine secret-laundering rename.

**If this leaks, the user's data is exposed via:** F's exemption is the only leak-adjacent surface. An
exemption written too wide (for example, exempting on the TARGET containing `archive/` rather than on
the SOURCE being allowlisted) would let `git mv server/secrets.ts <allowlisted>/archive/x.md` through
the gate. Mutation row 1 and row 4 exist specifically to pin this.

**Brand-survival threshold:** none — this is developer-workflow tooling with no end-user surface and
no personal data. F touches a security guard, so its mutation matrix is mandatory rather than
advisory, but a defect surfaces as a CI result on a maintainer's own PR, not as a user incident.

## Open Code-Review Overlap

- **#4133** — `follow-through(#4116): Schema parity test for ## Observability block`; names
  `plan/SKILL.md` and `deepen-plan/SKILL.md`. **Disposition: acknowledge.** It concerns schema parity
  for the `## Observability` block; this plan adds a new, disjoint section and a new halt gate and
  does not touch the Observability schema. The issue remains open and is not made harder to close.

No other open `code-review` issue (64 scanned) names any file in this plan's edit set.

## Architecture Decision (ADR/C4)

### ADR

Create one ADR: *Guard Contract as a plan-time deliverable* — recording that a change whose
deliverable includes a guard must declare the property, the structural assembly, and a mutation
matrix before the guard is written, and that assembly is enumerated structurally rather than by
membership.

The ordinal is **provisional**. Max on `main` is 176 at plan time. Per this skill's own Sharp Edge,
re-derive it at ship across **every** `origin/*` ref, not `origin/main`, and re-run that probe
immediately before merge. If the renumber fires, sweep this plan, `tasks.md`, and every AC naming the
ordinal in the same edit.

### C4 views

**No C4 impact.** Basis, stated precisely rather than as a blanket "read three files":

- `spec.c4` (54 lines) and `views.c4` (70 lines) read in full. `spec.c4` declares the element kinds
  the model can represent (`actor`, `system`, `container`, `database`, `component`) plus the
  `external` / `selfhosted` tags.
- `model.c4` (660 lines): every `#external`-tagged element and every element declaration scanned;
  the `plan`, `work`, and `review` component blocks (`model.c4:111-122`) read in full.

Enumeration for this feature:

- **External human actors:** none added. No new correspondent, reviewer, or recipient role.
- **External systems / vendors:** none added. No new webhook, outbound API, or third-party store.
- **Containers / data stores:** none added. The change adds repo-local CI lint scripts and skill
  prose; CI scripts are not modeled.
- **Actor↔surface access relationships:** none changed. No ownership or sharing semantics move.

**Descriptions checked for falsification** — the modeled components this PR edits are
`platform.plugin.{plan,work,review}` (rendered in the L3 components view, `views.c4:51-53`):

| Component | Current description | Falsified? |
|---|---|---|
| `plan` | "Creates implementation plans with research and domain review" | No — a Guard Contract gate is another plan-time gate |
| `work` | "Executes plans with incremental commits and test-first" | No — the class-scoped rule constrains how a fix is scoped, not the execution model |
| `review` | "Multi-agent code review with 8 parallel reviewers" | No — the structural-enumeration seat is CONDITIONAL, joining the existing conditional block (agents 9-14). The always-on count stays 8 |

No `.c4` edit is therefore in scope. Should the review seat later become always-on, `review`'s
description would need updating in the same PR.

## Observability

`rename-guard.sh` is CI-executing code, so the F change declares a posture. The two new lints run
only in CI and locally.

```yaml
liveness_signal:
  what: the three lint suites appear in scripts/test-all.sh output as named run_suite lines
  cadence: every CI run and every local test-all.sh invocation
  alert_target: CI job status on the pull request
  configured_in: scripts/test-all.sh
error_reporting:
  destination: stderr with a non-zero exit; surfaced as a failing required check
  fail_loud: true — every lint exits non-zero on violation and on its own internal failure
failure_modes:
  - mode: lint dispatches zero checks and exits 0 (vacuous pass)
    detection: each lint prints a checked-count and fails when the count is zero
    alert_route: CI job failure
  - mode: lint becomes an orphan suite that never runs
    detection: scripts/lint-orphan-test-suites.sh already fails on any scripts/*.test.sh not wired
    alert_route: CI job failure
  - mode: rename-guard exemption written too wide, admitting a laundering rename
    detection: rename-guard.test.sh mutation rows 1 and 4
    alert_route: CI job failure
logs:
  where: CI job logs and local terminal
  retention: GitHub Actions default
discoverability_test:
  command: bash scripts/test-all.sh
  expected_output: all registered suites pass, including the three new lint suites by name
```

## Implementation Phases

Phase order is dependency-directed. The contract's producer (A) lands before its verifier
(deepen-plan halt), and each guard's failing test lands before its implementation.

### Phase 0 — Preconditions

1. Confirm `TMPDIR=/var/tmp` is exported for every command in the session.
2. Detect sibling `test-all.sh` runs by resolving `/proc/<pid>/cwd`, never by process name — a bash
   script's process name is `bash`, so a name-based search finds nothing. Shard with
   `TEST_GROUP=bun|scripts` if a sibling run is active.
3. Capture a green unmutated control run before any mutation work begins.

### Phase 1 — (A) Guard Contract in `/plan`

1. Add a `### 2.12. Guard Contract Gate` phase to `plugins/soleur/skills/plan/SKILL.md`, placed after
   the Encryption Posture Gate so it sits with the other conditional plan-deliverable gates. Detection
   fires when the plan's deliverable includes a guard, gate, lint, drift-check, or anti-vacuity
   control. Required fields per guard: the property in one sentence; the ASSEMBLY, enumerating every
   code path, array, and file that contributes; and a mutation matrix of at least three edits that
   must go RED, derivable from the design rather than from the implementation.
2. Add the `## Guard Contract` template to
   `plugins/soleur/skills/plan/references/plan-issue-templates.md`.
3. State the load-bearing distinction explicitly in both places: **members drift, assembly is
   structural**. An assembly enumerated as a list of current members is not an assembly.

### Phase 2 — (A cont.) deepen-plan verification

Add `### 4.11. Guard Contract Halt (Conditional)` to `plugins/soleur/skills/deepen-plan/SKILL.md`,
mirroring the 4.6/4.10 halt pattern: locate the heading, validate each guard entry has a non-empty
ASSEMBLY and a mutation matrix with at least three rows, halt with a copy-pasteable remedy otherwise.

### Phase 3 — (D) `lint-guard-contract.py` — RED first

1. Write `scripts/lint-guard-contract.test.sh` with fixtures covering all five mutation rows.
2. Confirm RED.
3. Implement `scripts/lint-guard-contract.py`.
4. Wire `run_suite` into `scripts/test-all.sh`.
5. Mutation-prove all five rows on sandbox copies under `/var/tmp`, each verified with `diff -q`
   against a pristine backup.

### Phase 4 — (D cont.) `lint-window-closure-assertion.py` — RED first

Same RED-first sequence, including the grandfather allowlist of the 5 measured files. Mutation-prove
all five rows.

### Phase 5 — (B) `/work` class-scoped fixes

Add to `plugins/soleur/skills/work/SKILL.md` Phase 2: when a finding says "X can be added at site A",
enumerate all sites {A,B,C} that can reach the same sink BEFORE writing the fix. Record the
enumeration and the method that produced it. State the measured failure plainly: the `/home` re-bind
was fixed inside the array and validated four ways while three further entry points existed outside
it. A mutation protocol validates a fix; it never tells you the fix's population is right.

### Phase 6 — (C) `/review` structural-enumeration seat

Add a conditional agent seat to `plugins/soleur/skills/review/SKILL.md`: for guard-shaped PRs, spend
one seat on STRUCTURAL ENUMERATION — "enumerate every path by which a mount, token, or write reaches
the sink" — rather than N adversarial seats each finding one instance. Four agents independently
finding four instances of one structural gap is the signal that the seat was misallocated.

### Phase 7 — (D cont.) `/review` bullet

Add the closure-assertion bullet to the Defect Classes section, cross-referencing the lint so the
prose and the mechanical gate cite each other rather than restating each other.

### Phase 8 — (F) rename-guard source-allowlist exemption

1. Extend `apps/web-platform/scripts/rename-guard.sh` so a rename is a violation only when the target
   matches `ALLOW_RES` and the source does NOT. Both tested against the same array.
2. Extend the existing rename-guard test with all five mutation rows.
3. Add a one-line pointer in `plugins/soleur/skills/compound/SKILL.md` and
   `plugins/soleur/skills/archive-kb/SKILL.md` noting that archival renames are exempt by
   construction and require no label, citing
   `knowledge-base/engineering/operations/secret-scanning.md`.
4. Update that runbook to document the exemption.

### Phase 9 — (E) file the split issue

File the ADR-ordinal-allocation-at-ship issue carrying the full design sketch: `ADR-NEXT` placeholder
at plan time; ship assigns max+1 derived across all `origin/*` refs (never a presence check against
`main`); ship sweeps every reference across code, plans, specs, and ACs; the sweep needs its own Guard
Contract because its failure mode is a narrow window.

## Acceptance Criteria

### Pre-merge

1. `plugins/soleur/skills/plan/SKILL.md` contains a `Guard Contract` gate naming all three required
   fields, and the phrase distinguishing structural assembly from drifting membership.
2. `plugins/soleur/skills/plan/references/plan-issue-templates.md` contains a `## Guard Contract`
   template with the three fields.
3. `plugins/soleur/skills/deepen-plan/SKILL.md` contains a Guard Contract halt gate following the
   4.6/4.10 pattern.
4. `plugins/soleur/skills/work/SKILL.md` contains the enumerate-all-sites-before-fixing rule.
5. `plugins/soleur/skills/review/SKILL.md` contains the structural-enumeration seat AND the
   closure-assertion bullet.
6. `scripts/lint-guard-contract.py` and `scripts/lint-window-closure-assertion.py` exist, are wired
   into `scripts/test-all.sh` via `run_suite`, and each has a `.test.sh` sibling.
7. Each new lint fails when dispatched over zero inputs — no vacuous pass. Verified by mutation row 4
   / row 3 respectively.
8. All fifteen mutation rows across the three guards are proven RED on sandbox copies, each landing
   verified with `diff -q` against a pristine backup rather than against HEAD.
9. `bash apps/web-platform/scripts/rename-guard.sh` exits 0 for an allowlist→allowlist rename and
   exits 1 for an outside→allowlist rename with no override.
10. This plan's own `## Guard Contract` section passes `scripts/lint-guard-contract.py`.
11. `bun test plugins/soleur/test/components.test.ts` passes.
12. `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` reports no worse than the
    pre-change tier — this PR adds zero rule bodies.
13. `bash scripts/check-adr-ordinals.sh` passes.
14. `bash scripts/test-all.sh` is green, with the preamble and epilogue banners read rather than the
    exit code alone, and no `SIBLING_RUN_DETECTED` banner present.
15. `git grep -ln "secret-scan-allow-rename" -- plugins/soleur/skills/` returns at least one hit,
    satisfying #5097's own event-grep close criterion.
16. PR body carries `Closes #5095` and `Closes #5097`.
17. The E issue is filed (#7446) and its number recorded in the PR body.

### Post-merge

18. `scripts/check-adr-ordinals.sh` still passes on `main` after the ADR lands, with the ordinal
    re-derived across all `origin/*` refs immediately before merge.

## Test Scenarios

Deliberately mutation-shaped. The originating plan's thirteen scenarios were all "command X produces
terminal Y"; for a change whose deliverable is guards, that tests the guarded thing rather than the
guard.

| # | Mutation applied | Guard | Expected |
|---|---|---|---|
| 1 | Strip ASSEMBLY from a fixture guard entry | lint-guard-contract | RED |
| 2 | Shrink a mutation matrix to 2 rows | lint-guard-contract | RED |
| 3 | ASSEMBLY body set to `TBD` | lint-guard-contract | RED |
| 4 | Lint dispatch forced to always exit 0 | lint-guard-contract.test.sh | RED |
| 5 | Second non-compliant entry after a compliant first | lint-guard-contract | RED |
| 6 | New window helper + closure assertion, no completeness assertion | lint-window-closure-assertion | RED |
| 7 | Completeness assertion removed from compliant fixture | lint-window-closure-assertion | RED |
| 8 | Lint dispatch forced to always exit 0 | its `.test.sh` | RED |
| 9 | Second non-compliant helper after a compliant first | lint-window-closure-assertion | RED |
| 10 | Fixture relocated one directory deeper | lint-window-closure-assertion | still found |
| 11 | outside→allowlist rename, no override | rename-guard | exit 1 |
| 12 | allowlist→allowlist rename | rename-guard | exit 0 |
| 13 | Source-allowlist check deleted | rename-guard | scenario 12 reverts to exit 1 |
| 14 | Source and target checked against different regex sets | rename-guard | scenario 11 still exit 1 |
| 15 | Parser forced to fail | rename-guard | exit 2, unchanged |

Control: a green unmutated run precedes the battery. Every mutation is applied to a sandbox copy
under `/var/tmp` and proven landed with `diff -q` against a pristine backup.

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md`
- `plugins/soleur/skills/plan/references/plan-issue-templates.md`
- `plugins/soleur/skills/deepen-plan/SKILL.md`
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/skills/review/SKILL.md`
- `plugins/soleur/skills/compound/SKILL.md`
- `plugins/soleur/skills/archive-kb/SKILL.md`
- `apps/web-platform/scripts/rename-guard.sh`
- `knowledge-base/engineering/operations/secret-scanning.md`
- `scripts/test-all.sh`

## Files to Create

- `scripts/lint-guard-contract.py`
- `scripts/lint-guard-contract.test.sh`
- `scripts/lint-window-closure-assertion.py`
- `scripts/lint-window-closure-assertion.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-178-guard-contract-as-plan-time-deliverable.md`

## Domain Review

**Domains relevant:** none

No cross-domain implications — developer-workflow tooling with no user-facing surface, no persistent
store, no regulated data, and no new infrastructure. Product/UX gate does not fire: the Files to
Create and Files to Edit lists contain no UI-surface path.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The Guard Contract gate fires on plans with no guards, blocking the pipeline | Detection is conditional on guard-shaped deliverables; the deepen-plan halt is conditional, matching the 4.9/4.10 conditional pattern rather than the 4.6 always-on pattern |
| The window lint's grandfather allowlist becomes a permanent escape hatch | The allowlist is an explicit, enumerated 7-entry list, not a pattern; adding an entry is a visible diff |
| F's exemption is written on the wrong axis (target contains `archive/`) and admits laundering | Mutation rows 1 and 4 pin the correct axis; row 3 proves the exemption is load-bearing |
| The ADR ordinal collides during the pipeline | Re-derive across all `origin/*` refs immediately before merge; sweep plan, tasks, and ACs in the same edit if it moves |
| A sibling worktree's `test-all.sh` yields a false RED | Detect siblings by resolving `/proc/<pid>/cwd`; shard with `TEST_GROUP` |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Put the Guard Contract in `AGENTS.rules.md` | Domain-scoped insight belonging to the owning skills; the corpus is at WARN (44478/46000), so the placement gate and the budget agree |
| D as a review bullet only | `review/SKILL.md:1177` states the disposition for a recurring documented class is a mechanical gate, not another learning. The class has already recurred repeatedly with prose in place |
| D as a broad heuristic lint | Measured: 30+ false-positive files. Narrowed to named window helpers: 7 across 3 files |
| F by pre-applying the label (#5095 as filed) | Disarms the guard for the whole PR including genuine laundering renames in the same PR; the source-allowlist exemption is per-rename and preserves the property |
| F by exempting `archive/` destinations | Wrong axis — it keys on the destination shape rather than on whether new unscanned surface is created, and would admit `git mv server/secrets.ts <allowlisted>/archive/x.md` |
| Bundle E | See Scope Decision — unrelated thesis, non-trivial sweep needing its own contract, touches the largest skill on its merge path |
