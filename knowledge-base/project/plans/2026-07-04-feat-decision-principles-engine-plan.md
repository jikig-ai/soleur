---
plan: decision-principles-engine
issue: 5984
epic: 5983
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVE-WITH-CHANGES (folded below)
pr: 5982
detail_level: MORE
brainstorm: knowledge-base/project/brainstorms/2026-07-04-gstack-capability-adoption-brainstorm.md
spec: knowledge-base/project/specs/feat-gstack-capability-adoption/spec.md
---

# Plan: Decision-Principles Engine (Wave 1 · FR1 · #5984)

## Overview

Adapt gstack `autoplan`'s decision engine into Soleur: a committed **decision-principles reference doc** that classifies every intermediate agent decision as **Mechanical / Taste / User-Challenge**, plus the 2 auto-answer principles that actually drive surface-vs-auto (blast-radius, bias-to-action). It formalizes the existing soft guidance (`brainstorm-techniques:66-69` "if they seem decided, don't interrogate") and gives autonomous runs a principled, operator-legible **surface vs. auto-answer** rule that never adds a mid-pipeline pause.

Prompt/skill-instruction only — one new reference doc, four SKILL.md edits, one ADR, one drift-guard test. No product code, schema, infra, UI, or external vendor. It **consumes ADR-083's scoped `fable`→`opus` consult as one of its two signals** (it does not extend the consult mechanism) and stays inside the all-Claude policy (ADR-053).

**This plan was revised after a 5-agent review panel (architecture, simplicity, CPO, spec-flow, fable consult).** Their P0/P1 findings are folded in; the "Review Reconciliation" section records each.

## Research Reconciliation — Spec vs. Codebase (verified)

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Wire the headless record into `work` (it authors the PR body)" | **FALSE.** `work` has no `gh pr edit/create --body` (only `gh issue create`, `work:837,964`). `ship` is the **sole** PR-body author and **full-replaces** the body from diff analysis (`ship:1196,1242`; :1214 "always pass BOTH --title and --body"). A block written earlier is clobbered. | **Detect+persist in `plan`/`work` → a durable artifact; render in `ship`.** Mirrors ADR-083's own edit sites (`plan` Step 4.5 **+** `ship` Phase 5.5). Add `ship/SKILL.md` to Files-to-Edit. |
| "Interactive = brainstorm/plan; Headless = one-shot/work" (skill-name mode key) | **FALSE.** one-shot spawns `plan`+`work` **inside Task subagents** (text-only, `one-shot:70,81`); `plan` Step 4.5 consult itself runs in a subagent. A subagent cannot `AskUserQuestion` (`2026-05-12-task-subagent-prompt-text-only.md`; guarded at `plan:330`). | **Mode = execution context, not skill name.** Interactive ⟺ a real operator TTY is attached (direct `/brainstorm` or `/plan`, no `HEADLESS_MODE`, not a plan-file arg, **not inside a Task subagent**). Any subagent/one-shot context = headless → record branch. |
| gstack "Taste = reasonable people disagree" → surface | Solo-operator learning: unilateral pauses for **technical-only** findings are friction ("Soleur users will have no clue"). | Surface criterion narrowed to **user-visible OR compliance/money**, classified **by consequence not surface-flavor** (4 never-Mechanical classes below). |
| gstack "both models agree" (Claude+Codex) | all-Claude (ADR-053); the ADR-083 consult fires at exactly **2 gates** (`plan` 4.5, `ship` 5.5). | "Both signals" = session model + ADR-083 consult, **only at those 2 gates**. Elsewhere (e.g. `work`): session model + surface criterion, single signal. **No new per-decision consult** (avoids ADR-083 scope/cost creep). |
| `## Decision Challenges` in the PR body is "async review" | **Unreachable by the operator.** `operator-digest` ingests merged-PR title/labels/mergedAt only + `action-required`-labelled **issues** (`operator-digest:76,110-114`); never PR bodies. one-shot auto-merges. | Render the block in `ship` **and** open an `action-required` issue (the digest surface). Section name must avoid the `ship-operator-step-gate` operator-action-bullet regex. |

## Implementation Phases

### Phase 0 — Ground truth (verification, no writes)
Re-confirm anchors before editing (`hr-always-read-a-file-before-editing-it`): `ADR-083:22-24,51`; `plan:564-572` (Step 4.5); `ship:296-298` (5.5) + `ship:1196,1242` (Phase 6 body author); `work:857-868` (handoff/headless-detect), `work:142` (CTO HARD GATE), `work:837` (issue-create pattern); `brainstorm-techniques:66-69`; `one-shot:70,81,172`; `operator-digest:76,110-114`; `.claude/hooks/ship-operator-step-gate.sh` deny regex; `components.test.ts:226-236` (backtick-ref) + `:242-277` (sentinel-test precedent).

### Phase 1 — Author the reference doc (the primitive)
Create `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` (pattern: `brainstorm/references/brainstorm-domain-config.md`; cross-skill reference-by-path is established — `deepen-plan` reads `plan/references/*`, `ux-audit` reads `ship/references/*`). Contents:

1. **2 surfacing principles** (only the ones that drive surface-vs-auto): **blast-radius** (in radius AND `<1 day`/`<5 files`/no-new-infra → auto-decide-eligible) and **bias-to-action** (never a mid-pipeline pause). For code-taste once a decision is auto-decided, one-line pointer to `constitution.md`/YAGNI — do NOT re-import gstack's completeness/pragmatic/DRY/explicit (already covered, out of scope for *surfacing*).
2. **Classification by CONSEQUENCE, not surface-flavor.** Mechanical / Taste(user-legible) / User-Challenge. Surface criterion = **user-visible OR money/compliance**, where money/compliance explicitly includes: new external sub-processor, new recurring cost, new data egress, lawful-basis change. **Four NEVER-Mechanical classes even when they present as technical:** (a) dropping/deferring operator-requested scope; (b) onboarding a new sub-processor / paid dependency; (c) new recurring operational cost; (d) irreversible/destructive ops on user data.
3. **Precedence carve-out (CTO gate):** engineering/architecture-fork decisions route to the `cto` agent per `work:142` and are **NOT** User-Challenges even when user-visible. The taxonomy governs **product/scope/preference** decisions only.
4. **Mode-branched resolution** (columns keyed on execution context):

   | Class | Operator attached (real TTY) | Headless (no attached operator — incl. any Task subagent / one-shot) |
   |---|---|---|
   | Mechanical | auto-decide silently | auto-decide silently |
   | Taste (user-legible) | auto-decide + recommend; fold into the **existing** gate if one remains, else append to the output artifact (brainstorm decisions / plan `## Decisions Auto-Made`) — never a new pause | auto-decide + **persist to the challenges artifact** (rendered by `ship` + `action-required` issue) |
   | User-Challenge | `AskUserQuestion` at the existing final gate (plan: the post-`plan-review` confirmation), 5-line frame | keep operator's **stated direction (default)** + **persist to the challenges artifact**; a subagent returns it as structured text to its parent; **never pause** |

5. **User-Challenge 5-line frame:** what you said / what both signals recommend / why / what context we might be missing / if we're wrong the cost is. Operator's direction is the default; signals must make the case for change.
6. **"Both signals" scope:** = session model + ADR-083 consult, only at `plan` Step 4.5 / `ship` Phase 5.5. **Disagreement branch:** signals disagreeing promotes a Taste item to the recorded/surfaced tier; the operator's direction stays the default either way. No new per-decision consult elsewhere.
7. **Fail-safe defaults (ambiguity):** unsure Mechanical-vs-Taste AND user-visible/money/compliance → **Taste**; unsure Taste-vs-User-Challenge → **User-Challenge** (bias to the more-surfaced class — cost of over-recording is now one label).
8. **Security/feasibility exception — the SOLE sanctioned deviation from no-pause.** Trigger: introduces an auth/secret/data-exposure regression, or makes the stated approach technically infeasible (not a mere preference). Headless resolution: **terminal halt before merge** (not a mid-pipeline pause) + an `action-required` + `security` issue. Interactive: urgent-framed `AskUserQuestion`. State in ADR-084 that this is the only exception to the no-pause invariant.

### Phase 2 — Wire the consumers (markdown-link pointers; no restatement)
All pointers use **markdown-link** form (not backtick paths — `components.test.ts:226-236`).
- `brainstorm-techniques/SKILL.md` (technique 5, `:66-69`): one-line link — classify each candidate question via the doc before asking; only user-legible Taste / User-Challenge surface.
- `plan/SKILL.md` Step 4.5: consult guidance that **contradicts the operator's stated direction** is a User-Challenge — surface per the taxonomy, don't silently apply; when headless (subagent), **persist to the challenges artifact** instead of asking.
- `work/SKILL.md`: emergent Phase-0 decisions classified via the doc; **detect + persist** user-legible-Taste and User-Challenge to `knowledge-base/project/specs/<branch>/decision-challenges.md` (alongside the `session-state.md` convention). Reconcile with the `work:142` CTO HARD GATE (arch forks → CTO, not the taxonomy).
- `ship/SKILL.md` **(new consumer — the render site)**: Phase 6, before `gh pr edit --title … --body …` (`:1196`/`:1242`), read `decision-challenges.md`; if non-empty, fold a block into the canonical body under a name **outside** the operator-step-gate regex (candidate: `## Model Dissents (informational)` — no `Operator`/`Post-merge`/`Follow-up` token, no operator-action bullets), AND `gh issue create --label action-required --label decision-challenge` with a plain-language title linking the PR. Idempotent (skip if the issue already exists for this branch).
- `one-shot/SKILL.md`: **no edit** — inherits via plan/work/ship, mirroring ADR-083:24/:51.

### Phase 3 — ADR + drift guard
- Write **ADR-084** (provisional ordinal; `/ship` re-verifies). See below.
- Extend `plugins/soleur/test/components.test.ts` (precedent: the API-budget sentinel test at `:242-277`): assert (a) `decision-principles.md` exists, (b) each of the 4 consumer SKILL.md files links it (markdown-link regex), (c) `ship/SKILL.md` contains the `action-required`-issue emission for the challenges block (so the legible surface can't silently regress). **No content-presence assertions** (they pass by construction / false-fail on reword).

## Files to Create
- `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md`
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md`
- _(runtime, not committed by this PR)_ `knowledge-base/project/specs/<branch>/decision-challenges.md` — per-run persistence artifact.

## Files to Edit
- `plugins/soleur/skills/brainstorm-techniques/SKILL.md` (1 markdown-link pointer)
- `plugins/soleur/skills/plan/SKILL.md` (Step 4.5: contradiction→User-Challenge + headless-persist)
- `plugins/soleur/skills/work/SKILL.md` (emergent-decision classify + detect/persist; CTO-gate reconcile)
- `plugins/soleur/skills/ship/SKILL.md` (Phase 6: render challenges block + `action-required` issue)
- `plugins/soleur/test/components.test.ts` (drift-guard: existence + 4 links + ship emission)

_No `description:` frontmatter edits → Phase 1.8 skill-description budget check N/A._

## Architecture Decision (ADR/C4)

### ADR
**ADR-084 — Decision-classification taxonomy (Mechanical/Taste/User-Challenge) governing autonomous question surfacing** (provisional; `/ship` ADR-Ordinal Collision Gate re-verifies vs `origin/main` — 083 is current max). Records: taxonomy + 2 surfacing principles; classify-by-consequence + 4 never-Mechanical classes; **mode = execution context**; **no-mid-pipeline-pause** invariant + its **sole** security/feasibility exception (terminal halt); "both signals" = session + the **consumed** ADR-083 consult (depends-on, does not extend); the render-site = `ship` (not `work`, which cannot author the body); doc-home rationale. **References** ADR-083:24/:51 for the one-shot-inherit rationale (does not re-decide it). `## Alternatives Considered`: (a) record in `work` — rejected (`ship` full-replaces the body); (b) amend ADR-083 — rejected (distinct invariant; muddies an Accepted record); (c) mode-key on skill name — rejected (plan runs headless under one-shot → AskUserQuestion hang); (d) mid-pipeline pause on User-Challenge — rejected (anti-pattern); (e) surface all "taste" (gstack) — rejected (technical friction for non-technical operator).

### C4 views
**No C4 impact.** Checked all three `.c4` files: `founder` actor (`model.c4:8`) unchanged (still the decision-maker); `anthropic` external system (`model.c4:206`) already models the consult egress (`engine -> anthropic`, `claude -> anthropic`); no new external actor/system/container/data-store (the `decision-challenges.md` artifact is an internal repo file under an existing convention, not a C4 element); no element description falsified.

## User-Brand Impact
- **If this lands broken, the user experiences:** the autonomous loop bugs them with technical questions they can't answer (friction), OR silently auto-decides a user-visible/money choice it should have surfaced (invisible veto).
- **If this leaks, the user's [workflow] is exposed via:** N/A — no data surface; the only egress (curated payload → Anthropic `fable`/`opus`) is pre-existing under ADR-083.
- **Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` (CPO: APPROVE-WITH-CHANGES, all 3 required changes folded). `user-impact-reviewer` runs at PR review.

## Domain Review
**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO). Carry-forward + this plan's review panel.

### Engineering (CTO / architecture-strategist)
Render site must be `ship` (not `work`); mode = execution context; standalone ADR-084 consuming (not extending) ADR-083. Folded (see Review Reconciliation).

### Product/UX Gate
**Tier:** none — no UI-surface file (skill prose + ADR + test). **CPO sign-off: APPROVE-WITH-CHANGES** — the 3 required changes (legible `action-required` surface; extend it to the user-legible-Taste cell; classify-by-consequence + 4 never-Mechanical classes) are folded into Phases 1-3.

### Legal (CLO — carry-forward)
No new data surface / no new egress beyond the pre-existing ADR-083 consult. No sub-processor / DPA / Art.30 impact. (Note: the taxonomy's "new sub-processor" never-Mechanical class actively *strengthens* the sub-processor gate.)

## Observability
N/A — no code-class file (no `apps/*/server|src|infra`, no `plugins/*/scripts`). Skill prose + ADR + a test assertion; no new runtime error path, log, or failure mode.

## GDPR / Compliance disposition
No regulated-data surface. The only data flow is the **pre-existing** ADR-083 curated-payload consult to Anthropic `fable`/`opus`, governed by the existing Anthropic DPA posture; the taxonomy adds no new processing/egress. Full `/soleur:gdpr-gate` is a documented no-op here (recorded, not spawned, given zero data surface); trigger (b) single-user-incident satisfied by this disposition + `user-impact-reviewer` at review.

## Review Reconciliation (5-agent panel)
| Finding | Source | Resolution |
|---|---|---|
| P0 record wired to `work`, which can't author the body; `ship` full-replaces | architecture | Detect/persist in plan/work → artifact; **render in `ship`**; add `ship` to Files-to-Edit |
| P0 mode keyed on skill name → plan-under-one-shot hangs on AskUserQuestion | arch + spec-flow + fable | Mode = **execution context** (real TTY vs any subagent/headless) |
| P0 PR-body block unreachable by operator + auto-merge | CPO + spec-flow | `ship` also opens an `action-required` issue (digest Section 4 surface) |
| P0 security/feasibility exception vs no-pause | spec-flow | Sole exception = **terminal halt** before merge + `security` issue |
| classify by consequence; 4 never-Mechanical classes | CPO | Folded into §Classification |
| fail-safe defaults for ambiguity; disagreement branch | spec-flow + fable | Folded into §7 / §6 |
| consult scope creep (per-decision fable calls) | fable + simplicity | "Both signals" only at the 2 ADR-083 gates |
| CTO-gate collision (arch forks → CTO, not operator) | spec-flow | Precedence carve-out §3 |
| cut eval arm; trim test; cut 6 principles→2; markdown-link refs | simplicity | Folded (Phases 1,3) |
| standalone ADR-084, "consumes" not "extends", reference 083 for inherit | architecture | Folded (ADR section) |

## Risks & Sharp Edges
- **`ship` full-replaces the body** — the challenges render MUST happen inside `ship` Phase 6's body construction, not before it. A block written by `work` is clobbered.
- **Section name vs operator-step gate** — the challenges block must avoid `Operator`/`Post-merge`/`Follow-up` tokens and operator-action bullets, or `ship-operator-step-gate.sh` denies the PR. Use informational statements (`## Model Dissents (informational)`), not action-item bullets.
- **Markdown-link refs only** — backtick `references/…` paths in a SKILL body fail `components.test.ts:226-236`.
- **Empty `## User-Brand Impact` fails deepen-plan 4.6** — filled here.
- **Surface criterion is prose-enforced** — a model could still mis-classify; the fail-safe defaults (§7) bias toward surfacing, and the cost of over-recording is one label.

## Test Strategy
- **Structural (AC, pre-merge):** the Phase-3 drift-guard (existence + 4 markdown-links + `ship` `action-required` emission). `tsc`/lint/existing suite green.
- **Behavioral:** _out of scope this PR_ (eval-harness arm cut per simplicity — YAGNI on an unproven primitive; file a follow-up only if surfacing accuracy becomes a real question after usage).

## Acceptance Criteria
### Pre-merge (PR)
- [ ] `decision-principles.md` created: 2 surfacing principles + constitution pointer; 3 classes + classify-by-consequence + 4 never-Mechanical classes; CTO precedence carve-out; mode-branch table keyed on execution context; 5-line frame; "both signals" gate-scope + disagreement branch; fail-safe defaults; security exception (terminal halt).
- [ ] 4 consumers link the doc via **markdown links**; `ship` renders the challenges block (name outside the operator-step-gate regex) + opens an idempotent `action-required` issue; one-shot NOT edited.
- [ ] ADR-084 created; standalone; "consumes ADR-083" wording; references ADR-083:24/:51; `## Alternatives Considered` lists the 5 rejected options; C4 "no impact" cites the actor/system/store enumeration.
- [ ] Drift-guard test passes (existence + 4 links + ship emission); full suite + `tsc` green.
- [ ] `ship-operator-step-gate.sh` does NOT trip on the rendered challenges block (verify with a fixture).
### Post-merge (operator)
- [ ] None — pure prose change; `/ship` handles merge + deploy.
