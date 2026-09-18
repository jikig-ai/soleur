---
title: "feat(workflow-fsm): single-source the edge set, widen the instrument, ratchet prompt weight"
date: 2026-09-18
slug: feat-workflow-fsm-remediation
branch: feat-workflow-fsm-remediation
issue: 8302
closes: 8302
lane: cross-domain
type: feature
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Soleur declares a workflow state machine in two disagreeing places, and nothing
that can refuse an action reads either one. States live in
`.claude/phase-surface-map.json`; transitions live in a TypeScript `switch` in
`plugins/soleur/lib/workflow-fidelity.ts`.

**This plan is v2, rewritten after a six-agent review.** v1 proposed a
record-mode transition gate and extracted the dominant heading-block from four
lifecycle skills. The review cut both, with the operator's assent — see
`## Plan Review Revisions`. What survives is smaller and load-bearing: one
declarative edge set, a widened incident read, an offline transition classifier
over telemetry that already exists, one genuinely-conditional extraction, and a
byte ratchet that can actually fail.

## Research Insights

### Premise Validation (Phase 0.6)

All cited references probed this session. `#8302` OPEN (the work target);
`#8303`/`#8304`/`#8305` OPEN (deferred children filed today); `#2866` CLOSED via
PR `#2876`; `#6794` CLOSED via PR `#6852`; `#8029` MERGED 2026-09-11
(`65d6a1584`). ADR-011, ADR-070, ADR-086, ADR-091, ADR-116, ADR-131, ADR-151,
ADR-179 all exist. ADR-131 is `status: proposed`, dated 2026-07-20.

### Mechanism Minimality — Property List (Phase 0.6b)

| # | Property | Bought by an existing mechanism? |
|---|---|---|
| P1 | Rule-fire events emitted from any worktree are collected | **Partly** — PR #8029 collects 2 roots; 32% still stranded |
| P2 | The "never fired" figure has a trustworthy denominator | No — depends on P1 |
| P3 | Data regenerates without human dispatch | **YES, fully.** ADR-091 local-producer: compound runs it every invocation |
| P4 | States and transitions have one definition; drift fails a test | No |
| P5 | An undeclared transition is observable | **Mostly** — `.claude/.skill-invocations.jsonl` already records skill + session_id + timestamp on every `Skill` call; only classification is missing |
| P6 | `review→work`, `ship→work`, `work→plan` are expressible | No — `mandatorySuccessors()` has zero back-edges |
| P7 | Invoking a lifecycle skill loads less text | No — but the `references/` mechanism exists and 7 of 12 existing directives are genuinely phase-gated |
| P8 | SKILL.md body bytes cannot grow silently | No — existing budget covers description words only |

### Cut List (Phase 0.6b + plan review)

**C1 — CUT: "restore the aggregation cadence."** Property P3, already bought.
The authority is the workflow's own header,
`.github/workflows/rule-metrics-aggregate.yml` lines 7–16: the weekly
`schedule:` "was REMOVED because a fresh-checkout CI run sees zero incident data
and committed an all-zero (97/97 unused) snapshot every week, **clobbering the
real local aggregate.**" Restoring it re-introduces the defect #6042 fixed.
Confirmed empirically: this session's compound run regenerated the aggregate
with 23,805 events and no human dispatch.

**C2 — NARROWED: Track B is an application, not a new mechanism.** All four fat
skills already carry a `references/` directory in active use.

**C3 — CUT (review): the record-mode transition gate.** Property P5 is
substantially bought by `.claude/.skill-invocations.jsonl`, and the gate's
output would dead-end — see `## Plan Review Revisions` R1.

**C4 — CUT (review): extraction of `work` and `review` bodies.** Both are
core-path; extraction buys two reads for identical bytes. See R2.

**C5 — CUT (review): the stall investigation as a phase.** One grep answers it:
`grep -rn 'emit_incident' plugins/soleur/skills/*/SKILL.md` returns **zero**
call sites across 98 skills — only prose mentions. Instructing an agent, in
prose, to source a bash library never became a call site in five months. The
finding is recorded here; it needs no phase. It also refutes the v1 approach of
raising emission coverage the same way, which is why that phase is gone too.

### Value-Proposition Measurement (Phase 0.6c)

Command: `wc -c` per file; `awk` summing bytes per `## ` heading.

| Skill | Total bytes | ≈ tokens | Largest H2 | Share |
|---|---|---|---|---|
| `review` | 430,453 | ~107,600 | `## Code Review Complete` — 341,800 B | 79% |
| `work` | 326,015 | ~81,500 | `## Execution Workflow` — 281,975 B | 86% |
| `plan` | 258,003 | ~64,500 | `## Sharp Edges` — 150,469 B | **58%** |
| `ship` | 248,183 | ~62,000 | `## Phase 5.5` + `## Phase 7` | 68% |

**Growth over the 36 days since the source audit:** `review` 322→430 KB (+34%),
`work` 257→326 KB (+27%), `ship` 187→248 KB (+33%). A level is arguable; a rate
is not. **The ratchet, not the extraction, is what bends this curve** — only
`plan`'s `## Sharp Edges` is genuinely consult-on-demand.

### Key implementation facts

- **The plugin does not ship `.claude/`.** `.claude-plugin/marketplace.json`
  declares `source: "./plugins/soleur"`; `plugins/soleur/.claude/` does not
  exist. `apps/web-platform/server/phase-surface-map.ts`'s header states it
  outright: the bundled TS copy exists *because* `.claude/` is absent from the
  container. **Any runtime read of the canonical JSON from plugin code is a
  customer-machine failure.** This is the single most important constraint on
  the edge-set design.
- **Transition data already exists.** `.claude/hooks/skill-invocation-logger.sh`
  appends `{timestamp, skill, session_id, hook_event}` to
  `.claude/.skill-invocations.jsonl` on every `Skill` call (10,246 records at one
  path). Classification is the only missing piece.
- **`mandatorySuccessors()` is prompt text, not a transition set.** Its result
  renders as "When standalone, invoke next: /X, /Y"
  (`workflow-fidelity.ts:233-236`). Permitted back-edges and mandatory
  successors are different concepts and must not share a function.
- **Reference loads that work are gated.** Of 12 existing directives, 7 carry an
  explicit condition ("Skip if no uncovered stacks detected"; the Tier A/B/C
  fall-through chain in `work`; "if explicitly requested"). 5 are unconditional,
  one of which says "always runs".
- **Ratchet precedent and its warning.** `components.test.ts:21` holds
  `SKILL_DESCRIPTION_WORD_BUDGET = 2442`; its comment is a changelog of **15
  bumps**, most "against a N/N zero-headroom baseline".
- **ADR ordinal:** ADR-225 free across all 90 remote refs. Provisional.

### Institutional learnings that bound this plan

- **ADR-070 two-tier rule** — deny-by-default only on re-fetching layers.
- **ADR-086 line 23** — the hint hook stays `PostToolUse`.
- **ADR-151** — conditional loading of rule *content* caused two "appears
  enforced, is absent" incidents (#3681, #3808).
- **ADR-116 line 96** — advisory→blocking promotion has never happened here.
- **#6794** — the "unused" figure swings 94↔101. Do not prune on it.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (measured) | Plan response |
|---|---|---|
| FR2 "restore aggregation cadence" | Removed deliberately by #6042/ADR-091 | **Dropped** (C1) |
| "mute at three layers" | Two: emission and collection | Corrected |
| "16 of 99 skills" | 98 carry a `SKILL.md`; `flag-bootstrap/` does not | **16 of 98 = 16.3%** |
| "32% stranded" | Confirmed, counting rotated `.gz` | Carried into FR1 |
| FR7 gate in `.claude/hooks/` | Output dead-ends; data already exists | **Replaced** by an offline classifier (R1) |
| FR9 extract 4 skills | 2 of 4 are core-path | **Narrowed to 1** (R2) |
| `model.c4:117` "98 workflow skills" | Verified correct | No C4 edit |

## Open Code-Review Overlap

**#4133** — *follow-through(#4116): Schema parity test for `## Observability`
block* — names `plugins/soleur/skills/plan/SKILL.md`. **Disposition:
Acknowledge.** #4133 targets the Observability schema under `### 2.9`; this plan
extracts `plan`'s `## Sharp Edges`. Non-intersecting; #4133 stays open.

## Implementation Phases

### Track A — single-source the edge set and widen the instrument

**Phase A1 — Widen incident-log collection.** Enumerate sibling worktrees in
`scripts/rule-metrics-aggregate.sh` via `git worktree list --porcelain`.
Four non-obvious requirements, each from review:

1. **Canonicalise every root** (`pwd -P`) and dedupe by inode before the merge
   loop. `git worktree list` includes the **main** worktree, which the existing
   block already adds — an un-deduped union double-counts one file silently, and
   counts are a commutative reduce so the inflation is invisible.
2. **`INCIDENTS_DIRS[0]` must stay pinned to `$REPO_ROOT/.claude`.** Rotation
   (`AGGREGATOR_ROTATE=1`) truncates element 0. Appending siblings is safe;
   prepending or sorting would truncate another worktree's live log.
3. **Add `|| true` to the live-log `cat`.** Under `set -euo pipefail` it is the
   last command in an `&&` list, so an unreadable sibling aborts the whole
   aggregation. Widening the root set makes unreadable paths reachable for the
   first time.
4. Read-widen only — **no new write site** (CLO condition;
   `hr-write-boundary-sentinel-sweep-all-write-sites`).

**Phase A2 — One declarative edge set, bundled not read.**
Add `declaredTransitions()` to `plugins/soleur/lib/workflow-fidelity.ts`, backed
by a **TypeScript const in the plugin tree** — never a runtime read of
`.claude/phase-surface-map.json`, which the plugin does not ship. Mirror the
existing bundled-copy pattern. `mandatorySuccessors()` keeps its current
forward-only semantics and its signature; the back-edges live in
`declaredTransitions()` alone.

The edge set, written here verbatim so it is reviewable:

```
brainstorm -> plan, one-shot
plan       -> work
work       -> review, compound, ship, plan        (work->plan is a back-edge)
review     -> compound, work                      (review->work is a back-edge)
compound   -> ship
ship       -> postmerge, work                     (ship->work is a back-edge)
postmerge  -> (none)
```

`plan -> ship` is deliberately **absent** — it is the path that lets an agent
skip `review`, which is the operator-facing loss this work exists to make
visible.

**Phase A3 — Offline transition classifier.** A script that reads the existing
`.claude/.skill-invocations.jsonl`, groups by `session_id`, walks each session's
skill sequence, and reports transitions absent from `declaredTransitions()`.
Run on demand; no new hook, no `settings.json` entry, no PreToolUse surface.
It must apply the same canonicalisation as A1 — the invocation log has the same
per-root fragmentation as the incident log.

**Phase A4 — ADR-229.** The substantive decision is the packaging boundary:
the canonical edge set is a bundled TS const because the plugin does not ship
`.claude/`; the JSON is a derived view kept honest by a parity test; and
classification is offline because `PreToolUse` cannot deny here (ADR-070) and a
record-mode event has no consumer.

### Track B — one extraction and a ratchet that can fail

**Phase B1 — Extract `plan`'s `## Sharp Edges`** (151,209 B — 150,469 was a
character count, 58%) into
`plugins/soleur/skills/plan/references/plan-sharp-edges.md`, behind a load
directive. Text moves verbatim. *Revised at review:* the directive is
unconditional and placed as the last step before Plan Review, not conditional
on a phase — the catalogue is plan-hygiene that applies to every plan, and the
saving is per-turn (late load), not per-invocation; see ADR-229 Consequences
and decision-challenges §3.

**Phase B2 — Byte ratchet.** One ceiling per lifecycle `SKILL.md`, asserted
against the **merge base**. Three requirements from review:

1. **It cannot live in the `bun` shard.** `components.test.ts` runs under
   `scripts/test-all.sh` in a CI job with no `fetch-depth`, so at depth 1
   `origin/main` is not a fetched ref and the base read fails on every run — and
   any working-tree fallback is permanently fail-open. Place it in a diff-style
   job with `fetch-depth: 0`.
2. **Base-missing is a hard RED**, never an accept. On the introducing PR the
   ceiling file has no base version; that bootstrap arm is explicit and
   time-boxed to this PR, with a mutation row proving deletion reddens.
3. **Seed with ~10% headroom**, not at post-extraction size. A zero-headroom
   seed guarantees the first bump PR within a week — the exact ritual
   `SKILL_DESCRIPTION_WORD_BUDGET` has performed 15 times.

**"Lifecycle skill" is defined as a machine-readable set** — the seven keys of
`declaredTransitions()` — so the unclassified bucket is neither vacuous nor
reddening on 94 unrelated files.

## Files to Edit

- `scripts/rule-metrics-aggregate.sh` — canonicalised multi-root read
- `scripts/rule-metrics-aggregate.test.sh` — union, dedupe, unreadable-root cases
- `plugins/soleur/lib/workflow-fidelity.ts` — add `declaredTransitions()`
- `plugins/soleur/test/workflow-fidelity.test.ts` — edge-set + absence assertions
- `.claude/phase-surface-map.json` — derived `transitions` view
- `apps/web-platform/server/phase-surface-map.ts` — lockstep with the above
- `plugins/soleur/skills/plan/SKILL.md` — conditional extraction directive
- `.github/workflows/ci.yml` — ratchet job with `fetch-depth: 0`

## Files to Create

- `scripts/classify-workflow-transitions.sh` — offline classifier (A3)
- `plugins/soleur/test/skill-body-budget.json` — seeded ceilings
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-of-truth.md`
- ~~`scripts/followthroughs/workflow-fsm-transition-baseline-8302.sh`~~ (created, then deleted at review — see ADR-229 Consequences)

## User-Brand Impact

**If this lands broken, the user experiences:** a `/soleur:plan` session whose
Sharp Edges never load — the skill appearing to run while skipping guidance that
was moved. ADR-151's "appears enforced, is absent" in a new place. In Track A,
a customer-install `mandatorySuccessors()` returning `[]` and silently emitting
no next-step directive.

**If this leaks, the user's workflow is exposed via:** the rule-incident log,
whose events carry `command_snippet` — the triggering shell command verbatim
(1024 chars), including absolute paths and git/gh identity (ADR-091). This plan
does **not** raise emission coverage, so volume is unchanged from today.

**Brand-survival threshold:** `single-user incident`.

## Guard Contract

Two guards. (v1's Guard 1 went with the gate.)

### Guard 1 — edge-set parity

**Property.** The bundled TS edge set, the derived JSON view, and the web
copy are structurally equal; no commit can change one without the others.

**Assembly.** The bundled const and its one mirrored view. *Revised at
review:* the census over readers was built, then deleted at the simplification
pass — parity keeps the view correct for every reader, so a census guards only
the accuracy of a comment; and the ratchet no longer reads the view at all.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Add an edge to the TS const only | RED |
| 2 | Add an edge to the JSON view only | RED |
| 3 | Add an edge to the web copy only | RED |
| 4 | ~~Add a **second** reader left unlisted~~ | N/A at review — the census was deleted (see Assembly); the view has one reader |
| 5 | Stub the test's read to return `{}` | RED — targets the guard's own dispatch |
| 6 | Add `plan -> ship` to the edge set | RED — the absence assertion is the product requirement |

**Harness rows.** Must-PASS (non-canonical): adding an edge to all three in one
commit is green. Must-RED: replacing `toEqual` with `toBeDefined`.

**Anchor.** `grok-fidelity-gate.sh` runs `workflow-fidelity.test.ts` as a
mandatory pre-push gate, and `phase-surface-map-parity.test.ts` gates the web
copy — both outside the files this plan edits.

### Guard 2 — SKILL.md body-byte ratchet

**Property.** No lifecycle `SKILL.md` exceeds its pinned ceiling, and a ceiling
can only be lowered.

**Assembly.** Every key **and every destination** of the declared view, read
from the merge base *and* the working tree, resolved to
`plugins/soleur/skills/<name>/SKILL.md`, **plus a red unclassified bucket** in
both directions (a node with no row; a row with no node). Eight nodes at
introduction (`one-shot` is destination-only). Bootstrap is legal only when the
lint is also absent at the base.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Append 1 KB to `review/SKILL.md` | RED, naming that file and its number |
| 2 | Raise a ceiling in the same diff | RED — merge-base anchor rejects it |
| 3 | Delete a row from the ceiling file | RED via the unclassified bucket |
| 4 | **Delete the ceiling file entirely** | RED — the bootstrap arm is not an escape hatch |
| 5 | Add a **second** oversized file after a compliant first | RED — reports both |
| 6 | Make the discovery glob match zero files | RED via `MIN_CASES` |
| 7 | Run the job at `fetch-depth: 1` | RED — base-unavailable is a hard failure, never an accept |
| 8 | Add a ceiling row for a name that is not a node | RED — orphan row (review) |
| 9 | Add a destination-only node with no ceiling row | RED — keys AND destinations (review) |
| 10 | Bloat a file AND drop its node from the view in the same diff | RED — base ∪ working-tree node set (review) |
| 11 | `git mv` the ceiling file + edit `BUDGET_REL` in one diff | RED — bootstrap refused when the lint exists at base (review) |

**Harness rows.** Must-PASS (non-canonical): a file 1 byte under its ceiling is
green. Must-RED: delete the `expect` while keeping the `it()` name.

**Anchor.** The merge-base read — the ceiling comes from `origin/main`, not the
working tree, so a same-diff raise cannot self-certify. Row 7 is what keeps the
anchor real; without it the guard degrades to the
`SKILL_DESCRIPTION_WORD_BUDGET` changelog.

## Observability

```yaml
liveness_signal:
  what: emit_incident events reaching .rule-incidents.jsonl (volume unchanged by this plan)
  cadence: per skill invocation (local); aggregated on every compound run (ADR-091)
  alert_target: none — local-only by design; no egress (ADR-179 decision 4)
  configured_in: .claude/hooks/lib/incidents.sh
error_reporting:
  destination: stderr; SOLEUR_RULE_METRICS_NO_INCIDENTS marker on a null read
  fail_loud: true — absence prints a null-reading marker, never an all-zero summary
failure_modes:
  - mode: multi-root read double-counts a root
    detection: union count equals the distinct-inode sum, asserted in rule-metrics-aggregate.test.sh
    alert_route: CI red
  - mode: unreadable sibling root aborts aggregation
    detection: fixture with a mode-000 sibling root; aggregation completes
    alert_route: CI red
  - mode: edge set drifts between TS, JSON and web copy
    detection: Guard 1 rows 1-3
    alert_route: CI red via grok-fidelity-gate.sh (pre-push)
  - mode: ratchet silently fail-open on a shallow checkout
    detection: Guard 2 row 7
    alert_route: CI red
  - mode: extracted Sharp Edges never loaded
    detection: the load directive is unconditional at a named step (6.5, before Plan Review) with a STOP-and-report arm if the file is absent; a reachability guard in components.test.ts reds if references/plan-sharp-edges.md stops being named from plan/SKILL.md
    alert_route: CI red (bun shard)
  - mode: the transition probe runs where the log cannot exist (hosted sweeper, fresh checkout)
    detection: measured at review — FAIL on every sweep; the probe is operator-run and NOT enrolled
    alert_route: none by design; ADR-229 Alternatives table records why
logs:
  where: .claude/.rule-incidents.jsonl and .claude/.skill-invocations.jsonl (gitignored, 0600, machine-local)
  retention: rotated to *.gz; both live and rotated files are read
discoverability_test:
  command: bash scripts/classify-workflow-transitions.sh --summary
  expected_output: a table of session transitions with an undeclared-transition count, exit 0
```

No `credentials_required` — every probe is local and unauthenticated. First
token `bash` is on the Check 10 `PROBE_VERB_ALLOWLIST`.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-229 — "Workflow FSM: the edge set is a bundled const, and
classification is offline."** Three decisions:

1. **The canonical edge set is a TypeScript const inside `plugins/soleur/lib/`.**
   The plugin ships `./plugins/soleur` and does not carry `.claude/`; a runtime
   read of the repo-root JSON returns nothing on a customer install, and
   `mandatorySuccessors()` silently emits no directive. The JSON is a derived
   view with a parity test. *This is the decision a future reader would
   otherwise undo* — record it explicitly.
2. **Permitted transitions and mandatory successors are separate functions.**
   `mandatorySuccessors()` renders as "invoke next"; putting a back-edge there
   would instruct re-entry on every run.
3. **Classification is offline, not a gate.** ADR-070 forbids denial on this
   layer, and a record-mode event reaches no consumer — the aggregator files a
   non-corpus id under `summary.non_corpus_counts`, which nothing reads, and
   compound's Deviation Analyst filters to `{deny, bypass, hook_self_fault}`,
   none of which record-mode emits.

Ordinal **provisional** — verified free across all 90 remote refs; re-verify at
`/ship` Phase 5.5 and sweep plan, tasks and ACs if it moves.

### C4 views

**No C4 impact**, backed by the completeness enumeration:

- **(a) External human actors:** none added.
- **(b) External systems / vendors:** none added; the log remains egress-free.
- **(c) Containers / data stores:** none added.
- **(d) Access relationships:** unchanged — and v2 adds *no* hook at all, so the
  already-modelled Hook Engine (`model.c4:87`) is untouched.
- **Derived cardinalities:** `plugins/soleur/test/c4-count-parity.test.sh` passes
  **10/10**; none of C1–C7 measures hooks, rules, phases or skills. The ungated
  `model.c4:117` "98 workflow skills" was independently verified correct.

## Domain Review

**Domains relevant:** Engineering, Product, Legal — carried forward from the
brainstorm's `## Domain Assessments` (leaders ran this session).

### Engineering (CTO)

**Status:** reviewed. Block-mode is ADR-070-noncompliant; derived state beats
stored state; sub-phase normalization is orthogonal. Recommended an ADR
(adopted). At plan review, in the devex lens: cut the gate and cut the
`work`/`review` extraction — both adopted.

### Product (CPO)

**Status:** reviewed. The operator loses ~107k tokens of preamble per review and
a `plan→ship` path with no `review`. Weight is the higher-priority track.
Demanded the ratchet be demonstrated failing red before merge — kept as Guard 2
row 1, and strengthened by row 7.

### Legal (CLO)

**Status:** reviewed. Low exposure, no blocking legal work. Corrected a premise:
rule-fire events carry `command_snippet` verbatim. v2 does not raise emission
coverage, so the 2.4× volume increase v1 carried is gone. The one condition that
would change the verdict — emission on a customer machine — remains barred by
ADR-179 decision 4.

### Product/UX Gate

**Tier:** none. The mechanical UI-surface scan over Files to Edit/Create matched
no path in the term list or glob superset.

### GDPR / Compliance Gate (Phase 2.7)

Trigger (b) fired (`single-user incident`). Satisfied by **CLO carry-forward**:
the CLO read the incidents library and `.gitignore` this session, confirmed no
regulated-data surface and no register row. v2 reduces exposure further by
dropping the emission-coverage phase. Recorded, not silently skipped.

### Infrastructure-as-Code Gate (Phase 2.8)

Skipped — no server, secret, vendor account, DNS record, cert, firewall rule or
persistent runtime process. The scan found no remote-shell invocation, no
service-manager directive, no secret-store write command, no state-import call,
and no vendor-dashboard wording. The `.github/workflows/ci.yml` edit adds a test
job, not infrastructure.

### Encryption Posture Gate (Phase 2.11)

Skipped — no persistent store, no new cross-component connection.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — Aggregator runs from this worktree and from the shared checkout
      report the same `total_rules_tagged` and `rules_unused_over_8w`. *(v1 cited
      `events_total`, which is not among the 21 real `summary` keys.)*
- [ ] **AC2** — `rule-metrics-aggregate.test.sh` asserts the union over two
      sibling roots equals the **distinct-inode** sum — not a symmetric
      both-sides-equal check, which passes while both are doubled.
- [ ] **AC3** — A fixture root that is unreadable does not abort aggregation.
- [ ] **AC4** — `INCIDENTS_DIRS[0]` is `$REPO_ROOT/.claude` after enumeration;
      asserted directly, because rotation truncates element 0.
- [ ] **AC5** — `declaredTransitions()` exists and returns the edge set in
      Phase A2 verbatim.
- [ ] **AC6** — `declaredTransitions()` does **not** contain `plan -> ship`.
      This is the product requirement, asserted as an absence.
- [ ] **AC7** — `mandatorySuccessors()` is unchanged: `mandatorySuccessors("work")`
      does **not** contain `"plan"`, and the existing
      `workflow-fidelity.test.ts` assertions still pass unmodified.
- [ ] **AC8** — No plugin-tree file reads `.claude/phase-surface-map.json` at
      runtime: `grep -rn 'phase-surface-map' plugins/soleur/lib/` returns no
      read call.
- [ ] **AC9** — Edge-set parity across TS const, JSON view and web copy
      (Guard 1 rows 1–3 each demonstrated RED).
- [ ] **AC10** — `bash scripts/grok-fidelity-gate.sh` passes.
- [ ] **AC11** — `scripts/classify-workflow-transitions.sh` reports undeclared
      transitions from a synthetic two-session fixture, and attributes each to
      the correct `session_id`.
- [ ] **AC12** — Extraction is exact:
      `diff <(git show <base>:plugins/soleur/skills/plan/SKILL.md)
      <(reassembled SKILL.md + reference)` is empty modulo the load directive.
      *(v1's byte-sum check was content-blind and could pass on substituted text.)*
- [ ] **AC13** — `plan/SKILL.md` is under 120,000 bytes, and its load directive
      names an explicit gating condition.
- [ ] **AC14** — Ceilings carry ≥10% headroom over current sizes (re-seeded after the rebase onto a `main` that had grown `review`/`work`).
- [ ] **AC15** — The ratchet job declares `fetch-depth: 0`, and a shallow
      checkout produces a hard RED rather than a skip (Guard 2 row 7).
- [ ] **AC16** — **The ratchet is demonstrated RED.** The PR body carries the
      captured CI output from Guard 2 row 1, naming one file and one number.
- [ ] **AC17** — Deleting the ceiling file reddens (Guard 2 row 4).
- [ ] **AC18** — `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] **AC19** — `ADR-229-*.md` exists; ordinal re-verified across all `origin/*`
      refs immediately before merge.
- ~~[ ] **AC20** — the follow-through probe~~ Struck at review: the probe could
      not PASS where the sweeper runs and, operator-run, was a wrapper around
      `classify --summary`; deleted. The classifier warns on null and empty readings.
- [ ] **AC21** — No rule pruned: the rule-id count is unchanged at 98 and the
      retired-rule registry gains no row.

### Post-merge (operator)

None.

## Test Scenarios

Written as `mutation → guard reddens`.

1. Add an edge to the TS const only → parity RED.
2. Add an edge to the JSON view only → parity RED.
3. Add an edge to the web copy only → parity RED.
4. Add `plan -> ship` → absence assertion RED.
5. Put `"plan"` into `mandatorySuccessors("work")` → existing suite RED.
6. ~~New edge-set reader left unlisted → census RED.~~ (census deleted at review)
7. Two sibling roots sharing one inode → union equals distinct sum, not double.
8. Mode-000 sibling root → aggregation completes.
9. Enumeration that prepends a sibling → `INCIDENTS_DIRS[0]` assertion RED.
10. Append 1 KB to `review/SKILL.md` → ratchet RED naming that file.
11. Raise a ceiling in the same diff → ratchet still RED.
12. Delete the ceiling file → RED (bootstrap arm is not an escape hatch).
13. Run the ratchet job at `fetch-depth: 1` → hard RED, not skip.
14. Delete the `expect` from the ratchet test → harness RED, not `0 passed`.
15. Substitute equal-byte text during extraction → AC12 diff RED.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Extraction drops or substitutes text | AC12 exact diff against the git base, not a byte sum |
| Ratchet silently fail-open in CI | Guard 2 row 7 + AC15: base-unavailable is a hard RED; job pinned to `fetch-depth: 0` |
| Ratchet becomes the 15th budget bump | Merge-base anchor + 10% headroom seeding |
| Plugin-tree runtime read of `.claude/` | AC8 asserts no such read; ADR-229 decision 1 records why |
| Back-edge leaks into prompt text | AC7 keeps `mandatorySuccessors()` forward-only |
| Multi-root read inflates the denominator | AC2 distinct-inode assertion; AC4 pins element 0 |
| ADR-225 ordinal collides mid-pipeline | Verified across 90 refs; re-verified at ship with a full artifact sweep |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Record-mode `PreToolUse` gate (v1) | Output dead-ends: non-corpus id → `summary.non_corpus_counts`, which nothing reads; compound filters to `{deny,bypass,hook_self_fault}`. The data it would produce already exists in `.skill-invocations.jsonl` |
| Block-mode gate | ADR-070 forbids denial on a non-re-fetching layer; at 16/98 coverage it would false-deny `/go` |
| `mandatorySuccessors()` reads the canonical JSON | The plugin does not ship `.claude/`; returns `[]` on customer installs |
| Extract `work` / `review` bodies (v1) | Core-path: `work`'s Execution Workflow is lines 122–1281 of 1392. Two reads, identical bytes, new drift surface. The proven `references/` pattern runs at ~5% extraction, not 80% |
| Raise emission coverage via SKILL.md prose (v1) | Emission via SKILL.md is LIVE, not stalled: ADR-179 decision 9 (#7482, 2026-08-13) inverted the `source incidents.sh` form into `SOLEUR_RULE_APPLIED` markers captured hook-side — 21 sites across 7 lifecycle skills on `main`, 869 `applied` events in the live log. The audit's "4 of 10 skills" was a grep for the string `incidents.sh`, which the inverted transport no longer contains. Widening the remaining ~80 uncovered rules is a per-rule choice, not a mechanism gap, and out of scope here (corrected at review; the v1 reason "the mechanism does not stick" was false) |
| Restore a CI aggregator schedule | Cut (C1) — #6042 removed it because fresh checkouts clobber the real aggregate |
| Stored session state file | Fragmentation is a root-resolution property a stored file inherits identically |
| Normalize sub-phase grammars here | 4+ grammars; week+ migration → #8303 |

## Plan Review Revisions

Six reviewers (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO). Both panels fired on the same two scopes, so per
plan-review's own rule the resolution was delete rather than fix. The two cuts
touched operator-requested scope and were therefore surfaced as User-Challenges
and confirmed, not auto-applied.

- **R1 — cut the record-mode gate.** Traced dead-end confirmed against the
  aggregator and compound. Replaced by an offline classifier over existing
  telemetry. Removes: a hook, a `settings.json` entry, a test file, Guard 1,
  and four ACs.
- **R2 — narrow extraction to `plan` only.** `work` and `review` targets are
  core-path; the proven pattern operates at ~5%, not 80%.
- **R3 — edge set becomes a bundled TS const.** The plugin does not ship
  `.claude/`; a runtime read fails on customer installs (verified directly).
- **R4 — split `declaredTransitions()` from `mandatorySuccessors()`.** The
  latter renders as "invoke next"; a back-edge there instructs re-entry.
- **R5 — ratchet moved out of the bun shard.** No `fetch-depth` there, so the
  merge-base read fails every run and any fallback is permanently fail-open.
- **R6 — AC12 replaces the byte sum with an exact diff.**
- **R7 — ceilings seeded with 10% headroom**, not zero.
- **R8 — AC1 corrected**; `summary.events_total` does not exist.
- **R9 — follow-through is a named executable script**, not a date in prose.
- **R10 — cut the stall-investigation phase**; one grep answers it (C5).
- **R11 — "lifecycle skill" defined as the seven `declaredTransitions()` keys**,
  so Guard 2's unclassified bucket is neither vacuous nor over-broad.

Counts re-derived and confirmed correct under review: SKILL.md byte sizes, the
four dominant H2 blocks, 98 rule ids, 16 of 98 in `skill_to_phase`, and the
post-extraction reachability of the 120,000-byte target.

## Deferred

| Item | Issue | Re-evaluation trigger |
|---|---|---|
| Sub-phase grammar normalization + loader | #8303 | After Track A/B land |
| Linear-preflight regex matches `ADR-NNN` | #8304 | Next edit to brainstorm Phase 0.4 |
| SKILL.md body-weight growth report | #8305 | After the ratchet lands |
| Emission coverage beyond 19 of 98 | — | Needs a mechanism that sticks; prose sourcing demonstrably does not (C5) |
| Extraction of `work` / `review` bodies | — | After a measured base rate for whether agents follow reference directives |
| A blocking transition gate | ADR-229 | Only if ADR-070's two-tier rule changes |

> **Superseded 2026-09-18 (#8301, at ship):** the ordinal claims above were made about ADR-225. PR #8248 landed its own ADR-225 on main while this PR was in the merge queue, so this plan's ADR shipped as **ADR-229**; pointers in this document were updated to the new filename, the ordinal claims were left as written.
