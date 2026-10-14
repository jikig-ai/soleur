---
title: "feat(wave1): named multi-dimensional plan-review panel (CEO/design/devex)"
date: 2026-07-04
type: feat
issue: 5985
epic: 5983
wave: 1
fr: FR2
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
source_brainstorm: knowledge-base/project/brainstorms/2026-07-04-gstack-capability-adoption-brainstorm.md
depends_on: decision-principles classifier (#5984, ADR-084 — MERGED to main as commit 7e5fb720a)
---

# ✨ feat(wave1): named multi-dimensional plan-review panel (CEO/design/devex)

> **Note:** `lane:` defaulted to `cross-domain` — no `spec.md` exists for this branch to carry `lane:` from (TR fail-closed default).

## Overview

`plan-review` today spawns three **engineering** reviewers (DHH, Kieran, code-simplicity), escalating to five (`+architecture-strategist +spec-flow-analyzer`) when the plan declares the single-user-incident brand-survival threshold. Every lens is engineering-shaped: simplicity, convention, correctness, blast-radius, flow. A plan can be technically immaculate and still be a **product / market / design / developer-experience** mistake — and nothing reviews for that.

This FR wires the **existing** `cpo` / `cmo` / `cto` / `ux-design-lead` agents into `plan-review` as a **named CEO/design/devex panel**, alongside (not replacing) the eng panel. Adapted from gstack's `plan-ceo` / `plan-eng` / `plan-design` / `plan-devex` review split, narrowed for Soleur's non-technical solo-founder operator.

The **load-bearing constraint** (issue AC): the named panel's findings are frequently **taste** — user-visible / money / compliance choices where reasonable operators could disagree. Those MUST route through the **decision-principles classifier** (Mechanical / Taste / User-Challenge — `decision-principles.md`, ADR-084), **never silently auto-applied**. `plan-review` classifies each consolidated finding; the consumer (`plan`) auto-applies only **Mechanical** findings and **surfaces** Taste / User-Challenge ones through the *existing* legible-surface machinery (operator-attached: the "Apply these changes?" gate, User-Challenge with the 5-line frame; headless: persisted to `decision-challenges.md`, which `ship` Phase 6 renders + files as an `action-required` issue). No new pause, no new PR-body author, no new operator-notification path.

### What this is NOT (scope discipline)

- **NOT a duplicate of plan Phase 2.5 Domain Review.** Phase 2.5 runs *during authoring* as a forward **relevance assessment** (which domains matter; spawn leaders to shape the plan). This panel runs *after the plan is finalized* as an adversarial **critique of the finished artifact** through business/design/devex lenses. Different timing, different function (assess vs. review) — the gstack split exists for exactly this reason. The panel **reuses** Phase 2.5's output (the plan's `## Domain Review` section) as its relevance gate rather than re-deriving relevance.
- **NOT always-run.** The named panel is **relevance-gated** off signals already written into the plan file, so a pure-infra plan pays for at most the devex lens, not four idle C-suite sessions (token-frugal for a solo founder — ADR-053 all-Claude, no new sub-processor).
- **NOT a new classifier.** It **consumes** ADR-084's taxonomy (becomes its 5th linked consumer); it does not fork or extend the taxonomy's logic.

## Premise Validation (Phase 0.6)

Checked, all held except one correction:
- **Issue #5985** — OPEN; body confirms "Wire the EXISTING cpo/cmo/cto/ux-design-lead agents … taste calls routed through the classifier, not auto-decided." Not stale.
- **Epic #5983** — OPEN ("epic: adopt 12 gstack capabilities …").
- **Dependency (decision-principles classifier)** — the brainstorm chains T1-3 → T1-4. T1-3 landed: `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` exists (8190 bytes), **ADR-084 is Accepted**, and `git log` shows `7e5fb720a feat(skills): decision-principles engine (#5984)` on main. **The dependency is satisfied** — this plan builds atop a real, merged classifier, not a promised one.
- **Mechanism vs. ADR corpus** — the mechanism (reuse ADR-084's `decision-challenges.md` → `ship` Phase 6 render, reuse the existing plan-review workflow, no new consult) is *endorsed* by ADR-084 §Consequences and ADR-083, not sitting in a rejected-alternatives table. The brainstorm's own D3/D4 explicitly reject building new mechanisms. Aligned.
- **Correction carried from brainstorm:** the all-Claude model policy is **ADR-053**, not ADR-083 (ADR-083 = scoped strong-model consult). This plan cites ADR-053 for the model policy and ADR-084 for the taxonomy.

## 🎯 User-Brand Impact

**If this lands broken, the user experiences:** a `plan-review` run that **silently auto-applies a taste/scope change the operator would have wanted to weigh in on** (e.g. cuts an operator-requested feature on a domain-leader's "YAGNI" say-so) — reshaping their plan without surfacing it — OR a `one-shot` pipeline that **hangs** because a domain-leader agent emitted `AskUserQuestion` in a headless Task subagent that cannot answer it.

**If this leaks, the user's workflow is exposed via:** the classifier-routing regression vector — a mis-classified Taste/User-Challenge finding applied as if Mechanical drops the operator's stated direction silently into the plan → tasks.md → work → PR, without the `decision-challenges.md` / `action-required` surface the operator actually reads. (No data/money egress: all reviewers are Anthropic-bound on operator-plan text already reviewed by the existing panel; no new sub-processor — CLO-confirmed.)

**Brand-survival threshold:** single-user incident.

*Rationale for the threshold (sharpened by CPO sign-off — honest, not ceremony):* the intrinsic blast radius of "a plan comes out subtly wrong" is normally recoverable downstream (review, QA, and — interactive — the "Apply these changes?" gate). What makes it a **single-user incident** is one specific path: **in a headless `one-shot` run there is no interactive apply-gate.** A mis-classified Taste finding that silently drops operator-requested scope rides Mechanical-auto-apply → plan → tasks.md → work → a merged PR that a non-technical founder cannot read-review; their requested capability vanishes, surfacing only at the weekly digest. That is a single-user incident by the exact brand definition. The threshold is earned by the **headless-autonomy × non-technical-operator** combination (which removes the human catch), and it is *honored* by CPO Conditions 1 & 2 (decorrelated activation + named-findings-default-to-Taste) — without them the threshold is asserted, not earned. It buys the 5-agent eng panel + `user-impact-reviewer` at review time. Not justified by data/money blast radius (there is none).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brainstorm) | Codebase reality (verified) | Plan response |
|---|---|---|
| "Wire cpo/cmo/cto/ux-design-lead into plan-review" | All 4 agents exist: `agents/product/cpo.md`, `agents/marketing/cmo.md`, `agents/engineering/cto.md`, `agents/product/design/ux-design-lead.md` | Reuse via `agentType` (workflow) / `@agent-…` mention (prose) — no new agents. |
| "taste calls routed through the classifier" | `decision-principles.md` exists; consumed by exactly 4 skills; drift-guarded by `components.test.ts` `CONSUMERS = ["brainstorm-techniques","plan","work","ship"]` (lines 287–310) | Add `plan-review` as the **5th** consumer: link the doc in `plan-review/SKILL.md` **and** add `"plan-review"` to `CONSUMERS`; amend ADR-084's consumer list (4→5). |
| plan-review has two surfaces | prose `SKILL.md` (default, invoked by `plan` line 667 via `/plan_review`) + opt-in `workflows/plan-review.workflow.js` (REVIEWERS registry, BASELINE_PANEL + THRESHOLD_PANEL) | Edit **both** (AGENTS.md: keep prose+workflow in sync). Prose is load-bearing (what `plan` calls); workflow is parity. |
| plan applies review findings | `plan/SKILL.md` "Plan Review (Always Runs)" (665–681): "Ask: Apply these changes? (Yes/Partially/Skip)" — **interactive-only, NO headless branch** | The classifier routing IS the missing headless branch: Mechanical→auto-apply; Taste/User-Challenge→surface (attached: gate; headless: `decision-challenges.md`). Fixes a pre-existing gap. |
| domain leaders can review a plan | cpo/cmo are **orchestrators** whose default mode may emit `AskUserQuestion`; the plan Phase 2.5 Product/UX gate already scopes cpo with "Output a structured advisory — do not use AskUserQuestion." | Reuse that pattern: every named-panel prompt instructs **structured advisory only, NO AskUserQuestion** (Task-subagent text-only; `2026-05-12-task-subagent-prompt-text-only.md`, `2026-04-10-anonymous-task-spawning-loses-agent-context.md`). |
| plan-review workflow model pins | `workflow-model-pins.test.ts` allows exactly `{"detect-threshold":"sonnet"}` | Named reviewers are C-suite / never-downgrade (ADR-053 tier 3) → stay `inherit`. **No pin changes.** Reuse the existing `detect-threshold` sonnet step to also read relevance (one detect call; no new allowlist entry). |

## Design

### Role → agent → lens mapping

| gstack role | Soleur agent(s) | Panel axis | Lens (what it reviews the finished plan for) |
|---|---|---|---|
| `plan-ceo` (business/strategy) | `cpo` + `cmo` | **CEO / business** | cpo: product strategy, positioning, scope-vs-roadmap fit. cmo: market/GTM implications, brand-voice, messaging risk. |
| `plan-design` | `ux-design-lead` | **design** | user-flow completeness, UX decay, design-taste risk in user-facing surfaces. |
| `plan-devex` | `cto` | **devex / eng-strategy** | developer/operator experience, maintenance/DX cost, build-vs-buy, ongoing engineering strategy — **distinct** from `architecture-strategist`'s blast-radius/structural lens. |
| `plan-eng` | DHH / Kieran / code-simplicity (+arch/spec-flow at threshold) | simplification + correctness | **unchanged** — the existing eng panel. |

### Relevance gate (INDEPENDENT assessment — decorrelated from the authoring miss)

**CPO Condition 1 (correlated-failure fix):** the named panel exists to catch what plan Phase 2.5 got wrong — so it MUST NOT trust Phase 2.5's `## Domain Review` verdict as its trigger. If Phase 2.5 mis-judges a UI plan `Product: NONE`, a panel that reads that verdict inherits the exact miss (the forward gate and the backward critique correlate-fail on the same misjudgment). Relevance is therefore computed by an **independent** assessment of the plan's actual content, with the Domain Review section used only as a *hint*, never as the sole gate:

1. **Mechanical UI-surface scan (independent):** scan the plan's `## Files to Create` + `## Files to Edit` against the UI-surface glob superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, and the shared UI-term list). Any hit → force `ux-design-lead` + `cpo` active regardless of the Domain Review verdict.
2. **Fresh relevance read (independent):** the Load-phase detect step judges relevance from the plan *body* (Overview, Files, User-Brand Impact), not by parsing "Domains relevant: none": product/scope language → `cpo`; market/GTM/brand/user-copy language → `cmo`; user-facing/flow/visual language → `ux-design-lead`; code/infra/tooling Files-to-Edit → `cto`.
3. **Threshold bias:** when `Brand-survival threshold: single-user incident` is declared, bias toward activating (the eng panel already escalated; stakes are high) — mirroring the existing 5-agent escalation that fires on the impact threshold *regardless* of Domain Review.
4. If **none** activate (trivial non-engineering docs plan), only the eng panel runs — preserving today's behavior.

*Worked example — THIS plan:* the independent scan finds no UI-surface file and no user-facing/product/market surface in the body (plugin-tooling only); it has plugin-tooling Files-to-Edit ⇒ only the **devex (`cto`)** lens activates. cmo/cpo/ux stay idle — reached via the *independent* path (not by trusting the "Product NONE" verdict), so a genuine Phase-2.5 misjudgment on some *other* plan would not be inherited here.

### Classifier routing (the load-bearing AC)

`plan-review` consolidation tags each consolidated decision with `decisionClass ∈ {mechanical, taste, user-challenge}` per `decision-principles.md`, routing through ADR-084's **four never-Mechanical classes** (dropping operator-requested scope; new sub-processor/paid dep; new recurring cost; irreversible data op) — NOT a fresh classification path (**CPO Condition 2**):

- Eng-panel correctness/simplification findings (bug, convention-drift, flow-gap, blast-radius) → **Mechanical** (one right answer / purely-technical) — **auto-appliable**. Exception: a `simplify-cut` of **operator-requested scope** is never-Mechanical (class 1) → Taste/User-Challenge.
- **Named-panel findings default to Taste** (fail-safe): a cpo/cmo/ux/cto finding touching **user-visible / money / scope** is Taste unless it is *clearly* Mechanical (a factual/typo/broken-link correction). Product/market/design findings are almost never Mechanical — the classifier must bias them to **surface**, never silently auto-apply. This is the single safety point of the whole feature; on ambiguity it fails toward `decision-challenges.md`.
- Any finding arguing the operator's **stated scope/direction** should change (drop/merge/split/add) → **User-Challenge** — never auto-decide; 5-line frame.
- **Security/feasibility regression** → the ADR-084 sanctioned exception: attached → urgent `AskUserQuestion`; headless → terminal halt before merge + `action-required`+`security` issue.

**Single-signal context (important):** `plan-review` is NOT one of ADR-084's two "both-signals" consult gates (`plan` Step 4.5, `ship` Phase 5.5). It classifies with a **single** signal (the consolidator's judgment). Per `decision-principles.md`, ambiguity biases to the more-surfaced class (unsure Taste-vs-User-Challenge → treat as User-Challenge). The full both-signals User-Challenge adjudication stays owned by `plan` Step 4.5, which fires the second signal and writes the *same* `decision-challenges.md` artifact — so plan-review's surfaced findings and Step 4.5's converge into one artifact `ship` renders. The plan-review edit does **not** add a second consult (no cost/latency creep — `decision-principles.md` §"Both signals").

### Consumer routing (`plan` "Plan Review (Always Runs)" apply step)

- **Mechanical** → auto-apply to the plan file (both modes).
- **Taste + User-Challenge** →
  - *Operator-attached* (real TTY): present at the existing "Apply these changes?" gate; a User-Challenge uses the 5-line frame. (No new pause — the gate already exists.)
  - *Headless* (`HEADLESS_MODE`, no-TTY, `/soleur:one-shot`, `--headless`, OR plan-file-path arg): auto-apply Mechanical; **persist** Taste + User-Challenge to `knowledge-base/project/specs/<branch>/decision-challenges.md` (append); never pause. `ship` Phase 6 already renders it + files the `action-required` issue. Mirrors the existing Step 4.5 wiring at `plan/SKILL.md:574` and the mode predicate at `plan/SKILL.md:330`.

## Implementation Phases

Ordered **contract-producer before consumer** (`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`): plan-review produces classified findings; `plan` consumes them.

### Phase 1 — Drift-guard first (RED), then producer wiring (`plan-review` prose)
1. **(RED)** `plugins/soleur/test/components.test.ts` — add `"plan-review"` to the `CONSUMERS` array (line 291). Run the suite: the new `plan-review links decision-principles.md` case **fails** (plan-review/SKILL.md has no link yet).
2. **(GREEN)** `plugins/soleur/skills/plan-review/SKILL.md` — add, after the existing threshold paragraph:
   - A **Named CEO/design/devex panel** section: the role→agent→lens table, the **relevance gate** (read the plan's `## Domain Review` + Product/UX tier), and the instruction that every named-panel reviewer is prompted for **structured advisory only — NO `AskUserQuestion`** (Task-subagent text-only).
   - A **Classifier routing** paragraph: consolidation tags each finding `mechanical | taste | user-challenge` per **[decision-principles.md](../brainstorm-techniques/references/decision-principles.md)** (this markdown link satisfies the `CONSUMERS` guard); Taste/User-Challenge findings are **surfaced/persisted by the consumer, never auto-applied**; note the single-signal context + security/feasibility exception.
   - **Do NOT edit the `description:` frontmatter** (cumulative skill-description budget is ~1798/1800 words; adding words would require sibling-trim surgery — out of scope). Re-run `bun test plugins/soleur/test/components.test.ts` to confirm the word-budget test still passes after the body edit.

### Phase 2 — Consumer wiring (`plan` "Plan Review (Always Runs)")
3. `plugins/soleur/skills/plan/SKILL.md` (665–681) — rewrite the apply step to branch on `decisionClass`:
   - Present consolidated feedback (agreements first).
   - **Mechanical** findings → auto-apply.
   - **Taste / User-Challenge** → attached: surface at the "Apply these changes?" gate (5-line frame for User-Challenge); **headless** (reuse the mode predicate at `:330`): persist to `decision-challenges.md`, never pause.
   - Add the named panel to the reviewer bullet list (currently only DHH/Kieran/simplicity) with a one-line "relevance-gated" note.
   - Cross-reference the existing Step 4.5 `decision-challenges.md` wiring (`:574`) so the two converge on one artifact.

### Phase 3 — Workflow parity (`plan-review.workflow.js`)
4. `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`:
   - Add `cpo`/`cmo`/`cto`/`ux-design-lead` to the `REVIEWERS` registry (`panel: 'named'`, per-lens `lens` strings, distinct `cto` lens vs `architecture`).
   - Extend the **Load-phase `detect` step** (already `sonnet`-pinned, mechanical) to *also* return the relevance signals (`productRelevant`, `marketingRelevant`, `uxTier`, `engineeringRelevant`) read from the plan's `## Domain Review` — **one** detect call, no new pin/allowlist entry. Compute `NAMED_PANEL` from those signals.
   - Add `decisionClass` (enum `mechanical|taste|user-challenge`) to `REVIEW_SCHEMA.findings` and `CONSOLIDATION_SCHEMA.decisions`; extend `consolidatePrompt` with the classify + never-auto-apply-taste rule + the single-signal caveat.
   - Instruct named reviewers (in `reviewPrompt`) to emit **structured advisory only — no AskUserQuestion**.
   - Update `meta.description` and the **API-budget disclosure comment** for the new (relevance-gated, ≤ eng + 4 named + 1 consolidator) panel size; named reviewers stay `inherit` (never-downgrade).

### Phase 4 — ADR amendment
5. `knowledge-base/engineering/architecture/decisions/ADR-084-…md` — amend §Decision-1 and §Consequences: consumer list `brainstorm-techniques, plan, work, ship` → **+ `plan-review`** ("4 consumers" → "5 consumers"); one-line note that plan-review consumes the taxonomy to classify *review findings* (a finding-classification use, adjacent to the skills that classify their own intermediate decisions). Status stays Accepted (extension, not reversal).

## 📁 Files to Edit

- `plugins/soleur/test/components.test.ts` — `CONSUMERS` array `+= "plan-review"` (line 291). **RED first.**
- `plugins/soleur/skills/plan-review/SKILL.md` — named panel section + classifier-routing paragraph + `decision-principles.md` markdown link. **Do NOT touch `description:`.**
- `plugins/soleur/skills/plan/SKILL.md` — "Plan Review (Always Runs)" apply step: `decisionClass` branch + headless arm; add named panel to the reviewer list.
- `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js` — REVIEWERS registry, relevance detection, `decisionClass` schema fields, consolidate prompt, meta/budget comment.
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` — consumer list 4→5.

## 📁 Files to Create

- `knowledge-base/project/specs/feat-one-shot-5985-plan-review-panel/tasks.md` — generated by the plan skill's Save Tasks step (derived from this plan, post-review).
- *(this plan file)*

No new agents, skills, hooks, migrations, workflows, or infra.

## ✅ Acceptance Criteria (Pre-merge / PR)

1. `plugins/soleur/skills/plan-review/SKILL.md` names all four agents (`cpo`, `cmo`, `cto`, `ux-design-lead`) and maps them to the CEO/design/devex axes: `grep -c` for each agent token ≥ 1.
2. Named-panel activation is **relevance-gated** (not always-on): plan-review/SKILL.md prose states the gate reads the plan's `## Domain Review` + Product/UX tier, and the workflow computes `NAMED_PANEL` from the detect step's relevance fields. `grep -n "Domain Review" plugins/soleur/skills/plan-review/SKILL.md` returns ≥ 1.
3. Every named-panel reviewer is instructed **structured advisory only, no AskUserQuestion**: `grep -in "AskUserQuestion" plugins/soleur/skills/plan-review/SKILL.md plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js` shows the prohibition (a "do not / no AskUserQuestion" instruction), not a use.
4. `plan-review/SKILL.md` links `decision-principles.md` via a markdown link matching `/\]\([^)]*decision-principles\.md\)/`, AND `"plan-review"` is in the `CONSUMERS` array of `components.test.ts`. **`bun test plugins/soleur/test/components.test.ts` passes** (the `plan-review links decision-principles.md` case is GREEN).
5. `plan-review` consolidation output carries a `decisionClass` (mechanical|taste|user-challenge) per finding: the workflow `REVIEW_SCHEMA` and/or `CONSOLIDATION_SCHEMA` include a `decisionClass` enum property (`grep -n "decisionClass" …workflow.js` ≥ 1), and the prose states taste findings are never auto-applied.
6. `plan/SKILL.md` "Plan Review (Always Runs)" apply step branches on the class **and has a headless arm**: it auto-applies Mechanical and persists Taste/User-Challenge to `decision-challenges.md` in headless. `grep -n "decision-challenges\|Mechanical\|headless" plugins/soleur/skills/plan/SKILL.md` shows all three within the Plan-Review section.
7. **No new model pins**: `bun test plugins/soleur/test/workflow-model-pins.test.ts` passes with the allowlist unchanged (`plan-review` still only `{"detect-threshold":"sonnet"}`).
8. **Skill-description budget intact**: `bun test plugins/soleur/test/components.test.ts` word-budget assertion passes (no `description:` frontmatter was edited).
9. ADR-084 consumer list reads 5 consumers including `plan-review`: `grep -n "plan-review" knowledge-base/engineering/architecture/decisions/ADR-084-*.md` ≥ 1.
10. **Full suite green**: `bash scripts/test-all.sh` (or the repo's canonical suite) passes — catches any orphan drift-guard the named greps miss.
11. **Independent activation (deterministic, no live agents — CPO Condition 1):** the panel-composition computation is driven by an *independent* content scan, not by parsing the plan's `## Domain Review` verdict line. Fixture proof: a plan whose body declares `Product: NONE` but whose `## Files to Edit` contains a `components/**/*.tsx` path STILL activates `ux-design-lead` + `cpo` (the verdict does not suppress the mechanical UI-surface hit). A pure plugin-tooling fixture activates only `cto`.
12. **Each named lens is exercised (CPO Condition 3 — anti-rot):** across the fixtures, activation of **each** of the four named lenses (`cpo`, `cmo`, `cto`, `ux-design-lead`) is asserted at least once, so a broken REGISTRY entry or gate for any single lens fails CI — without spawning live agents.
13. **Classifier fail-safe (CPO Condition 2):** the consolidation prose/schema states that named-panel findings touching user-visible/money/scope **default to Taste** and are never tagged Mechanical on ambiguity; `grep -in "default to Taste\|never.*auto-appl\|never-Mechanical" plugins/soleur/skills/plan-review/SKILL.md` returns ≥ 1.

## 🧪 Test Scenarios

- **Pure-infra plan (Domain Review = none):** only eng panel + devex(`cto`) run; cmo/cpo/ux idle. Eng correctness findings classify Mechanical → auto-apply.
- **User-facing plan (Product + UX blocking):** full named panel activates. A cpo "cut this operator-requested feature" finding classifies **User-Challenge** → NOT auto-applied; headless → written to `decision-challenges.md`; attached → 5-line frame at the gate.
- **cmo "brand-voice risk in this user copy" finding:** Taste → surfaced, not auto-applied.
- **A named reviewer that would ask a question:** prompt forbids `AskUserQuestion`; agent returns structured text; pipeline does not hang.
- **Delete-over-fix still fires:** when the simplification panel and correctness panel both fire on one scope, consolidation still prefers delete (unchanged behavior; named panel is additive/orthogonal).

## Domain Review

**Domains relevant:** none (Engineering-internal tooling)

This is an orchestration change to the planning/review skills — no user-facing surface. Per the plan skill's own rule, "a plan that discusses UI concepts but implements orchestration changes (e.g., adding a UX gate to a skill) is NONE." The mechanical UI-surface override does not fire: Files-to-Create/Edit contain no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

### Product/UX Gate

**Tier:** none — no UI surface created or modified.

### CPO sign-off (threshold-driven — `requires_cpo_signoff: true`)

The brainstorm spawned CTO + CLO (not CPO — it scoped Product out as internal tooling). Because this plan declares `single-user incident`, the plan-time CPO sign-off gate fires. CPO was invoked in-session for a scoped sign-off on the four approach decisions.

**CPO verdict: approve-with-conditions.** The three conditions are **folded into this plan**:
- **Condition 1 (correlated-failure) → applied** in the revised Relevance gate: the panel computes relevance by an *independent* content scan, not by trusting Phase 2.5's `## Domain Review` verdict (which is the very authoring step it exists to catch).
- **Condition 2 (classifier is the single safety point) → applied** in the revised Classifier routing: named-panel findings **default to Taste** and route through ADR-084's four never-Mechanical classes, never a fresh path.
- **Condition 3 (lens rot) → applied** as AC12: the deterministic panel-composition fixtures must exercise activation of **each** of the four named lenses at least once, so a broken registry/gate for any lens fails CI without live agents.
- Condition 4 (operator-triage volume) and Condition 5 (cpo double-spend on product-heavy plans) are noted in Risks — flagged, accepted; no design change.

CPO also confirmed the threshold is **honestly warranted, not inflated** — earned specifically by the headless-autonomy × non-technical-operator path (see User-Brand Impact). CLO's brainstorm finding (Anthropic-only, no new sub-processor, no privacy-doc/Art.30/SCC churn) carries forward. CTO concerns (shared-surface blast radius) do not apply to FR2 (touches no hook/loader).

## 🏛️ Architecture Decision (ADR/C4)

### ADR
**Amend ADR-084** (do not author a new ADR): add `plan-review` to the consumer list (§Decision-1, §Consequences: "4 consumers" → "5 consumers"). This is an **extension** of an Accepted ADR (a new taxonomy consumer), not a new architectural decision or a reversal — the taxonomy logic, mode-branching, and both-signals scope are unchanged. Reusing the existing consult gates and `decision-challenges.md` artifact means no new substrate/trust/tenancy boundary is introduced. Amend in this feature's lifecycle (in-scope task, Phase 4) — **not** a deferred issue (`wg-architecture-decision-is-a-plan-deliverable`).

### C4 views
**No C4 impact.** Verified by reading all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumeration checked against the change:
- **External human actors:** none — no new human role (internal agent↔skill wiring for the existing solo-founder/agent).
- **External systems / vendors:** none — all-Claude (ADR-053), no new sub-processor (CLO-confirmed).
- **Containers / data-stores:** none new — `decision-challenges.md` is an existing artifact under `specs/`.
- **Access relationships:** none changed — no user↔surface access boundary moves.
- `plan-review` is **not** a modeled C4 component (the modeled skill components are `brainstorm/plan/work/review/compound/ship/one-shot/architecture` at `model.c4:95–123`; `review` at `:107` is the *code*-review skill's 8-reviewer component, unrelated). The model carries no per-reviewer wiring edge at this granularity, so wiring four existing agents into a non-modeled skill changes no view.

*Implementer note:* re-read all three `.c4` before concluding, and if any edit touches them, run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. Expected: no `.c4` edit needed.

### Sequencing
The ADR amendment is true immediately on merge (no soak gate). Author in Phase 4, same PR.

## 📡 Observability

**Gate does not fire** — Files-to-Edit are prose `SKILL.md` / `.md` (ADR) / a `test.ts` / a `.workflow.js` under `skills/*/workflows/` (not `plugins/*/scripts/`, not `apps/*/server|src|infra`), and no new infrastructure surface is introduced (Phase 2.8 trigger set does not match). No new server error path, cron, or runtime process.

The workflow's existing structured `log()` telemetry (panel composition, reviewers, findings, delete-over-fix outcome) is the discoverability surface; Phase 3 **extends** it to report the named-panel size + per-`decisionClass` counts (mechanical/taste/user-challenge). Discoverability test (no ssh): `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/workflow-model-pins.test.ts` — a green run confirms the wiring; the workflow report object surfaces the panel + class counts to any caller.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` cross-checked against every Files-to-Edit path (`plan-review/SKILL.md`, `plan-review.workflow.js`, `plan/SKILL.md`, `components.test.ts`, `ADR-084`, `decision-principles`) — zero matches.

## 🛡️ Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Correlated failure** — panel trusts the Phase-2.5 verdict it exists to catch | High | Independent content-scan gate (Relevance gate + AC11). |
| **Classifier mis-tags a taste finding Mechanical** → silent scope-drop in headless | High | Named findings default to Taste; route through ADR-084 four never-Mechanical classes; single-user-incident review + `user-impact-reviewer` (AC13). |
| **Operator-triage volume** (CPO Condition 4) — a chatty named panel files many `action-required` issues into the founder's weekly digest | Medium | Consolidation already dedupes into one decision set per scope; `ship` files **one** idempotent `decision-challenge` issue per branch (existing ADR-084 behavior). Flag only — if volume proves noisy post-adoption, add a per-run surface cap in a follow-up; do NOT design a cap now (YAGNI). |
| **cpo double-spend** (CPO Condition 5) — cpo runs at Phase 2.5 AND in the panel on product-heavy plans | Low | Accepted: assess-during-authoring vs. critique-finished-artifact catch different things; the post-hoc critique earns its cost at single-user-incident threshold. |
| **Named reviewer hangs `one-shot`** via `AskUserQuestion` | High | Prompt forbids it (structured advisory only); AC3 greps the prohibition. |

## ⚠️ Sharp Edges

- **`## User-Brand Impact` must stay filled** — an empty/placeholder section fails `deepen-plan` Phase 4.6 and `ship` preflight Check 6. It is filled above with `single-user incident`.
- **Skill-description budget is at the cap** (~1798/1800). Do NOT add any word to `plan-review/SKILL.md`'s `description:` frontmatter — all new prose goes in the body. Re-run the `components.test.ts` word-budget assertion after every SKILL.md edit.
- **Domain leaders self-answer `AskUserQuestion` in a subagent** — cpo/cmo default to orchestrator mode. Every named-panel prompt MUST carry the "structured advisory only, no AskUserQuestion" instruction *in the prompt text* (the agent `.md` body doesn't reach anonymous Task spawns — `2026-04-10-anonymous-task-spawning-loses-agent-context.md`). Omitting it hangs `one-shot`.
- **Persisting a challenge record targets `ship`, not `work`/`plan`** — `plan-review` and `plan` only *append* to `decision-challenges.md`; `ship` Phase 6 is the sole PR-body author and the sole filer of the `action-required` issue. Do not add a `gh pr edit --body` to plan-review/plan (`2026-07-04-plan-persisting-a-record-into-the-pr-body-must-target-ship-not-work.md`).
- **`decisionClass` is a single-signal classification here** — plan-review is not an ADR-083 both-signals consult gate. Do NOT add a per-review `fable`→`opus` consult (cost/latency creep; `decision-principles.md` §"Both signals" forbids new per-decision consults). The both-signals adjudication stays in `plan` Step 4.5.
- **Keep prose and workflow in sync** — both `plan-review/SKILL.md` and `plan-review.workflow.js` get the named panel + classifier routing (AGENTS.md plugin note). The prose is what `plan` actually invokes; the workflow is opt-in parity.
- **`cto` devex lens ≠ `architecture-strategist` structural lens** — give `cto` a distinct `lens` string (DX / maintenance / build-vs-buy / eng-strategy) so the two don't produce duplicate blast-radius findings.

## 🔀 Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Always-run the full 4-agent named panel | Wasteful for a solo founder — a pure-infra plan would spawn 4 idle C-suite sessions. Relevance-gating reuses signals the plan already carries. |
| Build a new operator-notification path for surfaced taste findings | ADR-084's `decision-challenges.md` → `ship` Phase 6 render + `action-required` issue already exists and is the only surface `operator-digest` harvests. Reuse it. |
| Add plan-review as an ADR-083 both-signals consult gate | Would balloon the scoped 2-gate consult into per-review cost/latency creep. Single-signal classification + `plan` Step 4.5's existing second signal suffice. |
| Author a new ADR for this feature | It extends ADR-084 (a new consumer), it does not make a new architectural decision. Amend, don't proliferate. |
| Fold the named lenses into plan Phase 2.5 instead of plan-review | Phase 2.5 is forward relevance-assessment during authoring; this is post-hoc critique of the finished plan. Different function; gstack separates them deliberately. |

## Non-Goals (deferred — file tracking issues per the plan checklist)

- Wave-1 siblings T1-3 (done, #5984) and T3-12 (operator velocity metrics) — separate FRs.
- Waves 2–4 (redaction hardening, context-injection, taste-learning, docs/PDF, canary/vitals) — separate issues under epic #5983.
- A dedicated content-presence drift-guard asserting the named-panel prose exists — **intentionally not added** (content-presence tests "pass by construction and false-fail on a good-faith reword" per the components.test.ts contract). The `CONSUMERS` link guard is the load-bearing gate.

## Resume

```
/soleur:work knowledge-base/project/plans/2026-07-04-feat-named-plan-review-panel-plan.md
Context: branch feat-one-shot-5985-plan-review-panel, issue #5985, epic #5983 Wave 1 FR2. Plan written; decision-principles dependency (#5984) already merged. Implementation next.
```
