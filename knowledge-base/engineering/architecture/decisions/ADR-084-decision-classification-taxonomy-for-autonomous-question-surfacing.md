# ADR-084: Decision-classification taxonomy (Mechanical/Taste/User-Challenge) governing autonomous question surfacing

- **Status:** Accepted
- **Date:** 2026-07-04
- **Issue:** #5984 (Wave 1 of the gstack-capability-adoption epic #5983)
- **Relationship to ADR-083:** **consumes** ADR-083's scoped `fable`→`opus` consult as one of two signals at the two gates where it already fires (`plan` Step 4.5, `ship` Phase 5.5). It does not extend the consult mechanism. For the "one-shot inherits, not edited" rationale it **references** ADR-083 §Decision-2/§Alternatives ("Edit one-shot too → Rejected", CONTINUATION-GATE) rather than re-deciding it.
- **Relationship to ADR-053:** stays inside the all-Claude model policy — "both signals" is the session Claude model + the ADR-053-compliant `fable`/`opus` consult. No external vendor.

## Context

gstack `autoplan` classifies every intermediate decision Mechanical / Taste /
User-Challenge and auto-answers all but User-Challenge, surfacing the rest at a
final interactive gate. Soleur wants the same decision discipline but has two
hard constraints gstack does not: (1) the operator is **non-technical** — unilateral
pauses for technical-only findings are friction (`2026-05-25-solo-operator-signoff-gate-defaults-to-noop.md`);
(2) mid-pipeline pauses are an anti-pattern (`2026-05-12-mid-plan-pause-gates-and-operator-step-pushback.md`),
and the autonomous `one-shot`/`work` path has **no operator to ask** (Task
subagents are text-only). A naive port would either bug the operator with
questions they can't answer or hang the pipeline on `AskUserQuestion`.

## Decision

1. **A committed reference doc** — `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` — defines the taxonomy, 2 surfacing principles (blast-radius, bias-to-action), classify-by-consequence with 4 never-Mechanical classes, the CTO-fork precedence carve-out, the mode-branch table, the 5-line frame, the consult scope, and the security exception. Consumed by **5 skills**: `brainstorm-techniques`, `plan` Step 4.5, `work`, `ship`, and `plan-review` (#5985 — plan-review classifies its consolidated *review findings* with the taxonomy so named-panel taste findings are surfaced, never auto-applied; a finding-classification use adjacent to the skills that classify their own intermediate decisions).
2. **Classify by consequence, not surface-flavor.** Surface criterion = user-visible OR money/compliance (sub-processor / recurring cost / data egress / lawful-basis). Four classes are never Mechanical even when they look technical: dropping operator-requested scope; a new sub-processor/paid dependency; a new recurring cost; irreversible data ops.
3. **Mode = execution context, not skill name.** Operator-attached ⟺ a real TTY (direct brainstorm/plan, no `HEADLESS_MODE`, not a plan-file arg, not inside a Task subagent). Any subagent / one-shot context is headless — a subagent returns the decision to its parent as structured text.
4. **No-mid-pipeline-pause invariant**, with **one** sanctioned exception: a security/feasibility regression halts **terminally** before merge (a stop, not a per-phase pause) + an `action-required`+`security` issue.
5. **Headless record → `ship`, not `work`.** `work`/`plan` detect and persist challenges to `knowledge-base/project/specs/<branch>/decision-challenges.md`; `ship` Phase 6 renders it into the canonical PR body (under a heading outside the operator-step-gate deny set) AND opens an idempotent `action-required` issue — the surface `operator-digest` Section 4 actually harvests. `ship` is the sole PR-body author and full-replaces the body, so the render must live there (`work` cannot author the body).
6. **one-shot inherits, not edited** — via plan/work/ship, mirroring ADR-083.

## Consequences

- Autonomous runs get principled surface-vs-auto decisions with an operator-legible async surface, and never hang or pause mid-pipeline.
- A new SKILL.md-prose surface across 5 skills; drift-guarded by a `components.test.ts` assertion (doc exists + all consumers link it + `ship` emits the `action-required` issue).
- The doc home (`brainstorm-techniques/references/`) is semantically inverted (the load-bearing consumers are `work`/`ship`), accepted because cross-skill reference-by-path is an established pattern (`deepen-plan` reads `plan/references/*`, `ux-audit` reads `ship/references/*`) and the drift-guard mitigates the rename-orphan risk.
- Fully reversible: delete the doc + the 5 pointers + the ADR.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Record the headless challenge in `work` | `work` does not author the PR body; `ship` is sole author and **full-replaces** it — the block would be clobbered. |
| Amend ADR-083 instead of a new ADR | This is a distinct cross-cutting invariant (question surfacing), orthogonal to ADR-083's token-frugal model tiering; amending muddies an Accepted record. |
| Mode-branch keyed on skill name | `plan` runs headless under one-shot (in a subagent) → an interactive branch would hang on `AskUserQuestion`. |
| Mid-pipeline pause on User-Challenge | Anti-pattern (`2026-05-12-mid-plan-pause`); the operator is a solo non-technical founder. |
| Surface all "taste" decisions (gstack's rule) | Technical-taste questions are friction the non-technical operator can't evaluate. |

## Addendum — 2026-10-11 (#10055): consequence class is not authority class

A technical ruling reached the founder twice on 2026-10-11, through the pipeline this ADR defines: `plan` persisted it to `decision-challenges.md`, `ship` Phase 6 rendered it and filed an `action-required` issue "Decide how strict …". Decisions 2 and 5 above answer "may the session model auto-decide this?" and "where does an operator-legible record go?"; they were silently reused as "who rules this?". This addendum narrows them. The original text above stays as the dated record.

Ruled by CTO agent, 2026-10-11: amend this ADR rather than mint a new one; the rule `hr-technical-fork-is-not-an-operator-question` is amended in place; the chat-prose Stop-hook arm is not built (13-of-15 over-block record in `unkept-promise-hook.sh`); the plugin port of the pre-ask gate is deferred (subagents cannot call AskUserQuestion).

- **Decision 1 (precedence carve-out), generalised.** The CTO-fork carve-out covers every technical ruling (architecture fork, threshold or evidence bar, design A-vs-B, whether evidence suffices, a status flip), and legal posture goes to the CLO, in both modes. A technical ruling is never a User-Challenge and is never persisted as an owner item.
- **Decision 2, scoped.** The four NEVER-Mechanical classes decide whether the session model may **auto-decide**; they never decide **who rules**. The operator-only list is closed: money, scope, priority/schedule, irreversible or production-mutating authorization, legal-risk acceptance, brand. The burden of proof sits on "operator".
- **Decision 3, extended.** A headless subagent that has the Agent tool spawns the CTO itself; one that does not returns the row as `pending - assumed: <default>` and its parent (one-shot after the plan phase, otherwise `ship` Phase 5.5) obtains the ruling.
- **Decision 5, split by class.** `decision-challenges.md` carries a `## Decision Classes` table (`Item | Class | Ruling`). `ship` renders technical rows in a `### Ruled by CTO agent` sub-block with no issue, and files the `action-required` + `decision-challenge` issue for operator-class rows only. A script-backed gate (`ship/scripts/technical-ruling-gate.sh`) fails an unruled or mislabelled row and any owner-decision label not carried by `(operator: <category>)`; its remedy is bounded (two CTO spawns, then a draft PR and a `domain/engineering` issue, never an operator question).
- **Decision 6, narrowly superseded.** "one-shot inherits, not edited" no longer holds for one rule: one-shot's plan-subagent prompt carries a short inline copy, because a Task subagent reads prompt text only and a link alone is not read. A wiring test pins the copy's key tokens.
- **Consequences.** The drift guard "`ship` emits the `action-required` issue" now means operator-class rows only. The reference lives at `brainstorm-techniques/references/technical-ruling-delegation.md`; `components.test.ts` derives its consumers (every skill naming the CTO agent must link it). The gate checks form, never truth: a model that mislabels a decision can still write a plausible `operator (scope)` row, which review and the CODEOWNERS-reviewed rule body are the check on.
- **Alternatives considered.** (1) Route every consequence-heavy decision to the operator: rejected, it is the status quo that produced the failure. (2) A Stop-hook label matcher over closing chat text: rejected on the 13-of-15 over-block record and because the gate removes the label at its source. (3) A hook-only fix: rejected, the carrier was an artifact pipeline, not a tool call, and the hook is repo-local.
