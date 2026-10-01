---
title: "chore(plan): scope check at plan time — map every user ask to a plan item and split multi-subsystem briefs"
date: 2026-10-01
slug: chore-plan-time-scope-check
branch: feat-one-shot-9398-plan-scope-check
issue: 9398
type: chore
lane: cross-domain
closes: 9398
brand_survival_threshold: none
---

# chore(plan): plan-time scope check — ask mapping, quote-challenge, split recommendation

## Overview

The `soleur:plan` skill gains an always-on scope check. Every plan it emits carries a
`## Scope Check` section with (1) an ask-mapping table pairing each user ask to a plan item,
flagging asks with no item and items with no ask; (2) a provenance check that rejects any
default or escalation rung citing "operator direction" without a verbatim quote; and (3) a
split recommendation fired when the planned diff spans many subsystems or crosses file/line
thresholds. `soleur:deepen-plan` gains a mirror halt gate so a plan with an unjustified
unmapped item cannot be deepened — the block the acceptance criterion requires.

Observed on PR #9339 (disk-leak fix, merged 2026-10-01): the brief listed tasks a–f; the plan
added a destructive `--attest` rung nobody asked for, and the diff grew to 101 files,
+6175/−195 lines. Three of seven plan reviewers cut the rung only after the plan was written
and deepened — the catch cost an 11-seat review, several fix rounds, and about eight CI
cycles. The defect class is "plan invents scope" + "plan outgrows the brief"; both are
detectable at plan time for near-zero cost.

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** Observability (added — gate applies per deepen-plan §4.7's
not-pure-docs detect), Implementation Phases (telemetry parity, measured trim bytes),
Research Insights.
**Research agents used:** none spawnable — this run is a one-shot planning subagent with no
Task tool; all deepen fan-outs (skill matching, learnings, per-section research, review
agents) were performed inline by the same agent and are disclosed rather than claimed. The
reviewer lenses were applied as a self-review pass, not as independent seats.

### Key Improvements (deepen-pass findings)

1. **`## Observability` is REQUIRED, not skippable** — deepen-plan §4.7's pure-docs
   exemption is `\.md$` *outside* `plugins/*/skills/`; this plan's file list sits inside
   that path, so the gate applies and the plan would HALT without the section. Added below.
2. **§4.12 halt must emit `SOLEUR_RULE_APPLIED` telemetry on fire** — sibling halts
   (4.5/4.6/4.8) all emit for the weekly aggregator; the spec now prescribes it.
3. **`<thinking>`-block trims measured, not estimated** — the three blocks at plan/SKILL.md
   lines 274/429/845 are 201/135/121 bytes (457 B total), comfortably covering the ~340 B
   pointer with ~117 B net negative.

### New Considerations Discovered

- The deepen quality-check list (§9) verified: all cited issue/PR numbers resolve to
  artifacts matching their cited semantic roles; no rule-IDs are cited; the
  negative-mechanism claim survives a sweep across ALL skills + AGENTS.rules.md (zero hits);
  `lint-guard-contract.py` passes this plan (1 guard entry, matrix ≥3 rows); the PAT sweep
  (§4.8) is clean; no sensitive path is touched (§4.6 scope-out not required).

## Problem Statement / Motivation

The plan skill has gates that check mechanisms against properties (Phase 0.6b) and gates that
check file lists against open scope-outs (Phase 1.7.5), but no gate checks the plan against
the *user's own words*. Nothing today enumerates "what was asked" as a distinct artifact, so
an added rung rides the same prose as the asked-for work, and nobody can answer "which ask
does this item serve?" without re-reading the issue. The split half is the same shape: the
diff-size signal is computable from `## Files to Edit`/`## Files to Create` the moment they
are drafted, but no phase computes it.

## Proposed Solution

The full gate spec lives in a NEW reference file —
`plugins/soleur/skills/plan/references/plan-scope-check.md` — because `plan/SKILL.md` is at
its byte ceiling (see Budget Measurement below; 14 B headroom against 120000 B). SKILL.md
gets only a pointer-phase line in the established "Read <ref> now" convention used by
`plan-community-discovery.md` / `plan-functional-overlap.md`, plus a compensating prose trim.
`deepen-plan/SKILL.md` (3414 B headroom) takes a compact `### 4.12. Scope Check Halt`. The
section schema lands in all three tiers of `plan-issue-templates.md` (uncapped reference
file). One bun contract/parity test pins the contract across all surfaces. One ADR records
the invariant. Deliberately NO new `lint-*.py` and no new CI job (ADR-131's gate-moratorium
class covers linters/probes/scheduled checks; a skill-internal halt + a test delivers the
same enforcement without a new perpetual CI surface).

**Budget measurement (sharp edge: SKILL.md byte ceilings, `skill-body-budget.json`).**
`plan`: 120000 ceiling, 119986 current → **14 B headroom** — the pointer MUST be paired with
a compensating trim of ≥ (pointer bytes − 14). `deepen-plan`: 80000 ceiling, 76586 current →
**3414 B headroom** — keep §4.12 ≤ ~3000 B. Verified with
`python3 scripts/lint-skill-body-budget.py --base origin/main` → OK today.

### Section schema (emitted into every plan; canonical copy in the reference file + templates)

```markdown
## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "<ask, quoted>"     | FR-2 / Phase 2 / Files-to-Edit entry | mapped |
| 2 | "<ask, quoted>"     | —        | descoped — justification: <reason> |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| <item>    | "<quote>"                         | asked   |
| <item>    | —                                 | inferred — justification: <reason> |

### Split Assessment

- Subsystems touched: <N> — <subsystem roots>
- Planned files: <N> | Estimated changed lines: <N>
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR | split — <proposed PR boundary>
```

Rules (full text in the reference file):

- An ask with no mapped plan item is `unmapped`; an unmapped ask (or an `inferred` item with
  an empty justification) blocks the plan until justified or descoped. Interactive: resolve
  via AskUserQuestion (justify / descope / rework). Headless or pipeline context: write
  `status: BLOCKED` in the section and append the unmapped rows to
  `specs/<branch>/decision-challenges.md`.
- "Per operator direction", "the user asked", "as requested", and every default/rung phrase
  must embed the verbatim quote it answers. No quote → the item is `inferred`, and inferred
  requires a justification naming the dependency or safety reason.
- Split assessment is computed from `## Files to Edit` + `## Files to Create` once drafted;
  subsystem root = `apps/<x>` / `plugins/<x>` for two-segment roots, first path segment
  otherwise.
- Placement: the pointer phase sits at `### 2.4.` — after Step 2 produces the file lists
  (Phase 1.7.5 already relies on that ordering) and **before** the Phase 2.5 domain fan-out,
  so a BLOCKED verdict or split recommendation fires before the expensive machinery.

deepen-plan `### 4.12. Scope Check Halt (Always)` mirrors the 4.11 shape: detect (always —
every plan has asks) → locate (`grep -q '^## Scope Check' <plan-file>`) → mechanical verify
(table present, ≥1 data row, no `unmapped`/`inferred` row with an empty justification cell,
`### Split Assessment` present with a `Recommendation:` line) → adequacy read (justifications
substantive, not boilerplate; the split assessment actually counted the file lists) →
pass-through. Any failure HALTs with instructions to re-run `soleur:plan`.

## Research Insights

**Research mode:** local only (Phase 1.6 — internal plugin machinery; no external research
value). The repo-research-analyst, learnings-researcher, functional-discovery and spec-flow
fan-outs were performed inline by the planning subagent — this process has no Task/spawn
tool, so agent invocations were substituted with direct greps/reads and are disclosed here
rather than claimed as independent runs. Same for the Phase 4.5 advisor consult: judgement
applied inline, disclosed.

**Premise Validation (Phase 0.6):** PR #9339 verified via `gh pr view` — state MERGED
(2026-10-01T18:59:18Z), 101 changed files, +6175/−195 — the "small core, large diff" premise
holds. The cited artifact `plugins/soleur/skills/plan/SKILL.md` exists on this branch. No
external premise was stale. ADR corpus check (Phase 0.6 step 4): the proposed mechanism
(a plan-time gate emitting a required section + a deepen-plan halt) matches the established
pattern of ADR-176 (plan checkpoint) and ADR-180 (guard contract) — neither ADR rejects it.
**ADR-131 (`status: proposed`, undecided) proposes a moratorium on new gates/linters/probes;**
it is not adopted policy, but its tail-cost argument is load-bearing for this design and is
the reason enforcement is prose-halt + contract test rather than a new `lint-*.py`/CI gate.
The tension is recorded in `specs/<branch>/decision-challenges.md` for ship-time surfacing.

**Existing-mechanism grep (authorities checked):** `grep -n "unmapped\|mapping table\|map
each\|split into\|PR split\|subsystems"` over `plan/SKILL.md`, `plan-review/SKILL.md`,
`deepen-plan/SKILL.md` → zero hits. No existing phase emits an ask↔item mapping or a split
recommendation; Phase 0.6b checks mechanism→property (invented machinery), not ask→item
coverage (dropped or invented scope) — the checks are complementary, not overlapping.

**Value-proposition measurement (Phase 0.6c):** the saving claim is "avoid the late,
expensive catch". Measured baseline for the incident: `gh pr view 9339 --json
changedFiles,additions,deletions` → 101 files, +6175/−195; the issue records ~11 review
seats and ~8 CI cycles. The new check's cost is one section emit per plan (prose, no
fan-out) plus one halt step in deepen-plan — asymptotically free against the class it
catches. A forward saving (cycles avoided) cannot be measured at plan time; the check's
value shows up as split/descope recommendations landing before review.

**Property List (Phase 0.6b):**

1. Every user ask is traceable to a plan item; unmapped asks are visible.
2. Every plan item, default, and rung is traceable to user words or carries a justification;
   invented scope cannot ride silently.
3. Oversize/multi-subsystem diffs surface a split recommendation at plan time.

**Cut List (Phase 0.6b):**

- `scripts/lint-plan-scope-check.py` (new lint) → cut: ADR-131 moratorium class; deepen-plan
  halt + contract test deliver enforcement without a perpetual lint surface.
- New CI job / scheduled check → cut: same class; nothing here needs CI cadence.
- Changes to `work`/`ship` skills → cut: not asked; the plan/deepen-plan boundary is where
  the issue's acceptance lives.
- Separate "scope-check" skill → cut: the check is cheap and phase-shaped; a sibling skill
  would add a dispatch seam for no property.
- Inlining the full gate body into `plan/SKILL.md` → cut by physics, not preference: 14 B
  headroom cannot host ~4 KB of gate prose; the reference-file pattern exists for exactly
  this.

**Applicable learnings:**

- `2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift.md` — the exact
  incident class (planning agent inventing scope).
- `2026-03-12-plan-review-scope-reduction.md` and
  `2026-03-05-plan-review-scope-reduction-and-hook-enforced-annotations.md` — plan review
  repeatedly cuts 50–96% of scope *after* the plan is written; this gate moves the same
  catch to plan time.
- `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — panels fix
  what the plan should never have contained.
- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — two-stage `--json` + `jq --arg` used for
  the Phase 1.7.5 overlap query.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`
  (via sharp-edges) — drove the reference-file placement and the explicit trim budget.

**Related issues/PRs:** #9339 (origin incident, merged); #4133 (open `code-review` — see
the `Open Code-Review Overlap` section below); ADR-176, ADR-180, ADR-131. ADR ordinal probe (all `origin/*`
refs, not just main — the #7418 collision class): highest claimed is ADR-264
(`origin/feat-one-shot-agent-runnable-operator-bootstrap`); ADR-265 is the provisional pick.

**Key file paths:** `plugins/soleur/skills/plan/SKILL.md` (gates §2.5–2.12 pattern at lines
457–811; reference-pointer convention at lines 310/314); `plugins/soleur/skills/deepen-plan/
SKILL.md` (halt-gate shape §4.11, lines 590–624);
`plugins/soleur/skills/plan/references/plan-issue-templates.md` (section schemas replicated
×3 — MINIMAL/MORE/A LOT); `plugins/soleur/test/observability-schema-parity.test.ts`
(parity-test precedent for a schema replicated across exactly these surfaces);
`plugins/soleur/test/skill-body-budget.json` + `scripts/lint-skill-body-budget.py` (byte
ceilings — see Budget Measurement).

## Research Reconciliation — Spec vs. Codebase

No `specs/feat-one-shot-9398-plan-scope-check/spec.md` exists (no brainstorm preceded this
run) — `lane:` defaults to `cross-domain` fail-closed per the carry-forward rule. Issue-body
claims were verified directly: PR #9339 size/merge state via `gh pr view`; "plan skill"
artifact existence via filesystem read; absence of an existing mapping/split mechanism via
the grep above.


## Implementation Phases

### Phase 1: `references/plan-scope-check.md` (foundation)

Create `plugins/soleur/skills/plan/references/plan-scope-check.md` carrying the full gate
spec: the `## Scope Check` section schema (canonical copy), the ask-extraction rule (for `#N`
invocations, discrete asks from `gh issue view <N> --json body` — task-list items,
numbered/bulleted requirements, acceptance bullets; for freeform invocations, from
`<feature_description>`; one row per ask, verbatim quote), both mapping directions, the
verbatim-quote rule for defaults/rungs/operator-direction phrases, the `unmapped`/`inferred`
verdicts and BLOCKED handling (interactive AskUserQuestion / headless `status: BLOCKED` +
`decision-challenges.md` append), the subsystem-root definition and the three split
thresholds, placement note (runs once `## Files to Edit`/`## Files to Create` are stable,
before the Phase 2.5 fan-out), and the `**Why:**` paragraph citing #9398/#9339 + learnings.

### Phase 2: plan/SKILL.md pointer phase + compensating trim

Insert between `### 2. Issue Planning & Structure` and `### 2.5. Domain Review Gate`:

```markdown
### 2.4. Scope Check Gate (Always)

[skill-enforced: plan Phase 2.4 + deepen-plan Phase 4.12]

**Read `plugins/soleur/skills/plan/references/plan-scope-check.md` now** — emit `## Scope
Check` (ask mapping, item provenance, split assessment) into the plan; an unmapped ask or
unjustified `inferred` item blocks the plan.
```

~340 B added. Compensating trim (≥ ~330 B) in the SAME file and SAME commit: remove all
three `<thinking>` scaffolding blocks — measured 201 B (line 274, `### 1.`),
135 B (line 429, `### 2.`), 121 B (line 845, `### 5.`) = **457 B total**, leaving ~117 B
net negative headroom after the pointer. These carry no load-bearing conditions (the
byte-ceiling learning warns only about compressing conditional prose). Verify with
`python3 scripts/lint-skill-body-budget.py --base origin/main` → must stay OK.

### Phase 3: deepen-plan/SKILL.md `### 4.12. Scope Check Halt (Always)`

Insert after `### 4.11.` and before `### 5. Discover and Run ALL Review Agents`, following
the 4.11 five-step shape, ≤ ~3000 B to respect the 3414 B headroom: Detect (always) → Locate
(`grep -q '^## Scope Check' <plan-file>`) → Mechanical verify (table present, ≥1 data row,
no `unmapped`/empty-justification `inferred` row, `### Split Assessment` + `Recommendation:`
line present) → Adequacy read (justifications substantive; counts derived from the plan's
file lists; quotes verbatim not paraphrase) → Pass-through. HALT text points back at
`soleur:plan` Phase 2.4 / `references/plan-scope-check.md`. On every fire (missing section
OR rejected row) emit the sibling-halt telemetry line so the weekly aggregator records the
enforcement event:
`echo 'SOLEUR_RULE_APPLIED rule=plan-scope-check-blocks-unmapped-asks note=...'` — a
halt-only line, none on pass, matching 4.5/4.6/4.8 convention.

### Phase 4: plan-issue-templates.md schema ×3

Add the `## Scope Check` block to all three tiers, placed immediately before
`## Acceptance Criteria` in each (matching where Domain Review places its sections).
MINIMAL keeps the same fields — the check is cheap and always-on; there is no "too small"
tier.

### Phase 5: plan-review consumer wiring (justified inferred item)

- `plugins/soleur/skills/plan-review/SKILL.md`: extend the code-simplicity feed sentence —
  feed `## Scope Check` (Ask Mapping + Plan-Item Provenance) alongside the Property List /
  Cut List so "which requirement does this mechanism satisfy?" has the verbatim ask list.
- `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`: update the
  code-simplicity `lens` string, or extend the existing documented-divergence note if the
  prompt text cannot be mirrored.

### Phase 6: Contract test `plugins/soleur/test/plan-scope-check.test.ts`

bun:test, modeled on `observability-schema-parity.test.ts`:

1. plan/SKILL.md contains `### 2.4. Scope Check` and a link/reference to
   `plan-scope-check.md`.
2. `references/plan-scope-check.md` exists and carries the emit-contract anchors
   (`## Scope Check`, `### Ask Mapping`, `### Plan-Item Provenance`, `### Split Assessment`,
   `Recommendation:`).
3. deepen-plan/SKILL.md contains `### 4.12. Scope Check Halt` with the `^## Scope Check`
   locate-grep and `HALT` text.
4. plan-issue-templates.md contains exactly 3 `## Scope Check` blocks, each carrying the
   three required subsections.
5. Parity: the required-subsection token set appears on all producer surfaces.

### Phase 7: ADR (provisional ADR-265)

Author `knowledge-base/engineering/architecture/decisions/ADR-265-<slug>.md` per the
`soleur:architecture` conventions: decision = every plan carries a Scope Check (ask mapping,
item provenance, split recommendation); enforcement = deepen-plan halt; alternatives
considered = lint script (rejected per ADR-131 tail-cost), review-time-only check (rejected —
the defect is cheapest at plan time), do-nothing (rejected — recurrence demonstrated).
Ordinal is provisional — ADR-264 is already claimed by
`origin/feat-one-shot-agent-runnable-operator-bootstrap` and siblings routinely race the
range: re-derive the next-free ordinal against freshly-fetched `origin/*` refs at merge time
(`git ls-tree` over `refs/remotes/origin/*`, not `origin/main` alone), and on ANY renumber
sweep `grep -rn 'ADR-265' knowledge-base/project/{plans,specs}/` + this file in the same edit
(the #5990 sweep class).

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md` — pointer phase `### 2.4.` + compensating trim
- `plugins/soleur/skills/deepen-plan/SKILL.md` — `### 4.12. Scope Check Halt (Always)`
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — `## Scope Check` ×3
- `plugins/soleur/skills/plan-review/SKILL.md` — feed Ask Mapping to code-simplicity-reviewer
- `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js` — lens string or divergence note

## Files to Create

- `plugins/soleur/skills/plan/references/plan-scope-check.md` — the canonical gate spec
- `plugins/soleur/test/plan-scope-check.test.ts` — contract/parity test
- `knowledge-base/engineering/architecture/decisions/ADR-265-*.md` — provisional ordinal

## User-Brand Impact

- **If this lands broken, the user experiences:** plans keep shipping invented scope and
  oversized diffs — the failure is silent (the gate that would flag it is absent), so the
  user-visible artifact is the next #9339-class 11-seat review churn.
- **If this leaks, the user's workflow is exposed via:** none — no data surface; the section
  quotes the operator's own asks back into a repo-local plan file.
- **Brand-survival threshold:** `none`

## Open Code-Review Overlap

One open `code-review` issue touches the planned files: #4133 (schema parity test for
`## Observability`, spanning plan/SKILL.md, deepen-plan/SKILL.md, plan-issue-templates.md).
**Disposition: Acknowledge** — #4133's deliverable (`observability-schema-parity.test.ts`)
already exists on this branch; the issue is stale-open for the Observability schema, a
different section. This plan's own parity test follows the #4133 precedent for the new
`## Scope Check` schema; #4133 remains open for its owner to confirm/close.

## Observability

```yaml
liveness_signal:
  what: contract test plan-scope-check.test.ts — the drift pin on the gate contract
  cadence: every scripts/test-all.sh run (pre-commit + CI)
  alert_target: red suite on the PR that breaks the contract
  configured_in: plugins/soleur/test/plan-scope-check.test.ts

error_reporting:
  destination: session transcript — deepen-plan §4.12 HALT text plus a SOLEUR_RULE_APPLIED telemetry line on fire
  fail_loud: deepen-plan refuses to proceed past §4.12 on a non-compliant plan; the halt is the error signal

failure_modes:
  - mode: gate spec / pointer / halt prose deleted or renamed
    detection: plan-scope-check.test.ts red (heading + token-set parity across surfaces)
    alert_route: CI failure on the PR that removes it
  - mode: a plan ships without ## Scope Check or with an unjustified unmapped row
    detection: deepen-plan §4.12 HALT before any fan-out spend
    alert_route: the halted session transcript (operator-visible)

logs:
  where: CI log + session transcript (SOLEUR_RULE_APPLIED line on halt fire)
  retention: CI artifact retention / session log lifetime

discoverability_test:
  command: grep -c '^## Scope Check$' plugins/soleur/skills/plan/references/plan-issue-templates.md
  expected_output: "3"
```

## Guard Contract

The deliverable includes a drift guard: the Phase-6 contract test pins a cross-file prose
contract (`## Scope Check` must exist and stay consistent across its surfaces).

### Guard 1 — plan-scope-check contract test

**Property.** The `## Scope Check` emit contract (section + three subsections + halt +
pointer) exists on every surface that produces or verifies it — the reference file (canonical
spec), the plan/SKILL.md pointer, the three template tiers, the deepen-plan halt — and no
surface may carry a stale subset.

**Assembly.** Six surfaces — the complete set of producers/consumers of the
section contract: the five pinned above plus `plan-review/workflows/plan-review.workflow.js`,
whose `code-simplicity` lens restates the contract inside a JS string (token-presence
assertion, not `carriesContract` — the tokens sit mid-line). The chokepoint is the test's
own surface table: a seventh surface added later
(e.g., a ship check, a lint) must be added to the table or it silently escapes — the test
must therefore also assert the `references/plan-scope-check.md` pointer exists in
plan/SKILL.md (the pointer is what makes the canonical file reachable, so deleting the
pointer orphans the spec).

**Mutation matrix.**

| # | Mutation (design-derived) | Expected |
|---|---------------------------|----------|
| 1 | Rename `## Scope Check` → `## Scope Audit` in `plan-scope-check.md` only | RED — heading drift across surfaces |
| 2 | Delete `### Split Assessment` from ONE template tier (MINIMAL) | RED — per-tier subset check |
| 3 | Remove the `### 4.12` halt body but keep the heading | RED — halt must carry the locate-grep + HALT text, not just the heading |
| 4 | Delete the `### 2.4` pointer from plan/SKILL.md (file keeps its size via padding) | RED — pointer is part of the contract |
| 5 | Weaken the test: anchor on a substring already present elsewhere (a bare `##` prefix) | RED — harness row: assertions must be section-anchored |
| 6 | Add a sixth compliant surface carrying the full token set | PASS — matrix permits growth with the same contract |

**Anchor.** All surfaces are files in the same PR — the guard proves consistency across the
commit, and the deepen-plan halt is the runtime backstop for plans that drift anyway.

## Architecture Decision (ADR/C4)

### ADR

Create provisional **ADR-265** — "every plan carries a Scope Check: ask mapping, item
provenance, split recommendation" (see Phase 7). Ordinal probe at plan time: highest claimed
across `origin/*` is ADR-264 (`feat-one-shot-agent-runnable-operator-bootstrap`); ADR-265
chosen; re-derive before merge per the sweep rule in Phase 7.

### C4 views

No C4 impact. Checked per the completeness mandate — read all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: (a) external
human actors — none new (operator/`founder`/`devin` already modeled); (b) external
systems/vendors — none (no new API, webhook, or store); (c) containers touched — the Soleur
Plugin `skills` container is already modeled at skill-family granularity ("workflow skills —
brainstorm, plan, work, review, compound, …"); this change alters prose *inside* `plan`'s and
`deepen-plan`'s SKILL.md, not a container boundary; (d) relationships — unchanged. No element
description is falsified.

## Scope Check

*(This plan dogfoods the section it specifies.)*

### Ask Mapping

| # | User ask (verbatim, from #9398) | Plan item | Status |
|---|---------------------------------|-----------|--------|
| 1 | "map each user ask to a plan item and flag anything unmapped" | `plan-scope-check.md` Ask-Mapping spec + `### 2.4.` pointer; deepen-plan §4.12 verifies it | mapped |
| 2 | "challenge a default or rung that quotes no user words ('per operator direction' must carry the quote)" | `### Plan-Item Provenance` quote rule; §4.12 rejects empty-justification rows | mapped |
| 3 | "warn and offer a split into several PRs when the planned diff spans many subsystems or exceeds a file/line threshold" | `### Split Assessment` + thresholds in `plan-scope-check.md` | mapped |
| 4 | "plan skill emits the mapping table and a split recommendation; an unmapped item blocks the plan unless justified" (acceptance) | templates schema (emit contract) + §4.12 halt (block) + contract test | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `plan/SKILL.md` pointer phase | asks 1–3 | asked |
| `references/plan-scope-check.md` | asks 1–3 | asked |
| `deepen-plan/SKILL.md` halt | "an unmapped item blocks the plan unless justified" | asked |
| `plan-issue-templates.md` schema | "emits the mapping table" | asked |
| `plan-scope-check.test.ts` | — | inferred — justification: the emit/halt contract needs a drift pin or it rots silently (precedent: `observability-schema-parity.test.ts`, filed as #4133) |
| `plan-review` feed of `## Scope Check` to code-simplicity-reviewer | — | inferred — justification: in #9339 it was the reviewers who cut the un-asked rung; the table is the artifact they were missing. Two-line change (SKILL.md + workflow.js lens note) |
| ADR (provisional 265) | — | inferred — justification: plan Phase 2.10; a new always-on plan invariant matches the ADR-180 precedent class |
| Compensating `<thinking>`-block trim in plan/SKILL.md | — | inferred — justification: byte ceiling arithmetic, not optional; without it the pointer cannot land |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur` (skills + test), `knowledge-base/` (ADR)
- Planned files: 12 edited/created (7 plugin surfaces + ADR + plan/spec artifacts) | Estimated changed lines: ~600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — under every threshold; the two subsystems are one coherent change (the gate and its record).


## Acceptance Criteria

- [ ] AC1: `plugins/soleur/skills/plan/SKILL.md` contains `### 2.4. Scope Check` between Step
  2 and Phase 2.5 with a reference to `references/plan-scope-check.md`, AND
  `python3 scripts/lint-skill-body-budget.py --base origin/main` stays OK (the pointer +
  compensating trim net within the 14 B headroom).
- [ ] AC2: `plugins/soleur/skills/plan/references/plan-scope-check.md` exists carrying the
  emit contract (`## Scope Check`, `### Ask Mapping`, `### Plan-Item Provenance`,
  `### Split Assessment`), the verbatim-quote rule, the BLOCKED/justify handling, the
  subsystem-root definition, and the three thresholds.
- [ ] AC3: `plugins/soleur/skills/deepen-plan/SKILL.md` contains `### 4.12. Scope Check Halt`
  between §4.11 and §5, which HALTs when `## Scope Check` is absent, when any ask is
  `unmapped` without justification, or when any `inferred` item lacks a justification — and
  the file stays under its 80000 B ceiling (3414 B headroom at plan time).
- [ ] AC4: `plan-issue-templates.md` carries the `## Scope Check` schema in all three tiers.
- [ ] AC5: `plugins/soleur/test/plan-scope-check.test.ts` exists, passes, and goes red under
  each Guard-Contract mutation row.
- [ ] AC6: `ADR-265-*.md` (or its renumbered successor) exists under
  `knowledge-base/engineering/architecture/decisions/`.
- [ ] AC7: `plan-review/SKILL.md` feeds the `## Scope Check` artifact to
  code-simplicity-reviewer.
- [ ] AC8: `bun test plugins/soleur/test/plan-scope-check.test.ts` green; `bash
  scripts/test-all.sh` green (or only pre-existing failures confirmed on origin/main).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — plugin orchestration machinery (markdown gates, a bun
test, an ADR). Mechanical UI-surface override checked: no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in the file lists → Product tier NONE. Domain-leader
spawns not applicable in this subagent context; the semantic sweep ran inline.

## Test Scenarios

- Given a plan missing `## Scope Check`, when deepen-plan §4.12 runs, then it HALTs naming
  plan Phase 2.4.
- Given a plan whose Ask Mapping has an `unmapped` row with an empty justification, when
  §4.12 runs, then it HALTs on the row.
- Given a plan file list spanning 4+ subsystem roots, when `### 2.4.` executes, then the
  `### Split Assessment` recommendation is `split` with a named boundary.
- Given `plan/SKILL.md`'s pointer heading renamed, when `bun test` runs, then the contract
  test fails (Guard Contract row 4).
- Given this plan, when read against its own `## Scope Check`, then all four asks map and
  recommendation is `single PR`.

## Risks and Mitigations

- **Byte ceiling on plan/SKILL.md (14 B headroom).** The dominant implementation risk: the
  pointer must land AND a compensating trim must cover it, or `lint-skill-body-budget` fails
  the PR. Mitigation: reference-file placement (uncapped), pre-identified `<thinking>`-block
  trims, AC1 pins the lint green. Do NOT compress conditional prose to fit — if the trims
  cannot cover the pointer, the remedy is a smaller pointer, never compressed conditions.
- **Thresholds are judgment values** (4 subsystems / 25 files / ~800 lines). Mitigation:
  declared as tunables in the reference file; first values chosen so #9339 (101 files) is
  clearly over and a typical machinery PR (≤7 files) is clearly under; tune on observed
  false positives rather than up-front precision.
- **Ask extraction is fuzzy** for freeform briefs. Mitigation: the reference file defines "an
  ask" as a discrete requested outcome (task-list item, numbered/bulleted requirement,
  acceptance bullet, or imperative sentence); §4.12's adequacy read rejects padding tables.
- **Gate fatigue / ADR-131 tail cost.** Mitigation: prose gate + one test; no new CI job, no
  lint script, no scheduled check; the check is per-plan cheap (one section emit). The
  ADR-131 tension is disclosed in decision-challenges.md for ship-time surfacing.
- **Vocabulary:** the issue's "rung" is used loosely for "added step/default"; the glossary
  sense is a fallback-ladder step. The reference file uses "default, rung, or added item" to
  cover both senses without redefining the glossary word.
- **Inferred items in THIS plan** (test, plan-review feed, ADR, trim): each carries a
  justification in `### Plan-Item Provenance` — a reviewer may still cut them; the plan is
  deliberately transparent about which items trace to asks and which do not.

## Alternative Approaches Considered

| Approach | Rejected because |
|----------|------------------|
| Full phase inlined in `plan/SKILL.md` | Physically impossible at 14 B headroom; raising the ceiling is a separate reviewed PR (ratchet rule) |
| New `scripts/lint-plan-scope-check.py` + CI wiring | ADR-131 moratorium class (linters); tail cost of a perpetual lint exceeds the benefit when a halt + test suffices |
| Review-time-only check (plan-review seat) | #9339 showed review catches it too late — after deepen, after fan-out; plan-time emit is the ask |
| Blocking PreToolUse hook on plan-file Write | A hook cannot parse "user asks" semantics; the check is inherently a read-the-brief judgment — prose gate + halt is the honest mechanism |
| Defer to roadmap / do nothing | The defect class recurs (#9339, and the scope-reduction learnings show it's systemic); issue filed deliberately |

## Non-Goals

- No changes to `work`, `ship`, `review`, `one-shot` skills.
- No retroactive backfill of `## Scope Check` onto existing plans (forward-only).
- No lint script, CI job, or hook.
- No `skill-body-budget.json` ceiling raise — a separate reviewed PR per the ratchet rule.
- No change to the `deferred-scope-out` machinery — different axis (review-time scope-outs).

## Sharp Edges

Applied the Phase-6.5 verification pass over `references/plan-sharp-edges.md`; the edges that
bound this plan:

- **SKILL.md byte ceiling** (the `#8647` edge): measured `skill-body-budget.json` ceilings
  and current sizes at plan time — drove the reference-file design and AC1/AC3's lint pins.
- **ADR ordinal provisional** (the `#7418`/`#7162` edges): probed all `origin/*` refs, found
  ADR-264 claimed on a sibling branch; picked 265 and prescribed re-derivation + a renumber
  sweep at merge.
- **Verify knowledge-base citations exist**: all `learnings/` paths cited above were opened
  during research (the four learnings and three ADRs named were read, not paraphrased).
- **markdownlint plan + tasks.md before summary** (`#8535` edge): prescribed as the last step
  before Session Summary in tasks.md; the plan file itself is lint-clean-checked at write.
- **ACs are post-conditions, not phase-output paraphrases** (`#2754` class A edge): every AC
  above asserts file state or command output.
- **Heading-anchored splices** (`#6488` edge): this plan's own body contains `## Scope
  Check`; any scripted edit of plan files must anchor on line-start headings and assert
  match counts — noted for the work phase.
- **Guard over prose/token surfaces** (the `#7493`/`#8274` vacuity family): the contract
  test's mutation matrix includes a must-PASS growth row and a harness row per the Guard
  Contract convention.
