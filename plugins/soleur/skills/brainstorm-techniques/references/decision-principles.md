# Decision Principles — Mechanical / Taste / User-Challenge

How a Soleur skill decides, for each **intermediate** decision, whether to
**auto-answer** it or **surface** it to the operator — without ever adding a
mid-pipeline pause. Adapted from gstack `autoplan`, narrowed for Soleur's
non-technical solo-founder operator and all-Claude model policy (ADR-053).
Decision record: [ADR-084](../../../../../knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md).

Consumed by: `brainstorm-techniques`, `plan` (Step 4.5), `work` (emergent
decisions), and `ship` (Phase 6, which renders the headless record). `one-shot`
inherits via those skills and is deliberately not edited (mirrors ADR-083).

## The 2 surfacing principles

Only the principles that decide **surface vs. auto-answer** live here. Code-taste
(how to write the code once you've decided to auto-answer) is governed by the
[constitution](../../../../../knowledge-base/project/constitution.md) and YAGNI —
not restated here.

1. **Blast-radius** — a change that is in the plan's blast radius (files it
   touches + their direct importers) AND small (`< 1 day` / `< 5 files` / no new
   infra) is auto-decide-eligible. Outside the radius, or larger, lean toward
   surfacing.
2. **Bias-to-action** — flag concerns but do not block; **never** insert a
   mid-pipeline pause to ask. Surfacing happens at an *existing* gate or via a
   recorded artifact, never a new stop.

## Classification — by consequence, not surface-flavor

Classify each decision by what its outcome *costs the operator*, not by whether
it looks technical.

- **Mechanical** — one clearly-right answer, OR a purely-technical choice a
  non-technical operator cannot evaluate (which abstraction, which query shape,
  which test helper). **Auto-decide silently.**
- **Taste (user-legible)** — a **user-visible OR money/compliance** choice where
  reasonable operators could disagree. Auto-decide with a recommendation, and
  surface it (see the mode table). "Money/compliance" explicitly includes: a new
  external **sub-processor**, a new **recurring cost**, new **data egress**, or a
  **lawful-basis** change.
- **User-Challenge** — both signals (see below) agree the operator's **stated
  direction** should change (merge, split, add, or drop a feature/scope the
  operator specified). **Never auto-decided.** The operator's direction is the
  default; the signals must make the case for change.

### Four NEVER-Mechanical classes (even when they present as technical)

These *look* like implementation details but carry user-visible / money /
compliance consequence — they are never Mechanical:

1. **Dropping or deferring operator-requested scope** (a YAGNI/bias-to-action
   cut of something the operator asked for).
2. **Onboarding a new external sub-processor or paid dependency.**
3. **A new recurring operational cost** (a higher token/API tier, a new
   subscription).
4. **Irreversible or destructive operations on user data** (dropping a column,
   a lossy format change).

Blast-radius / bias-to-action **never** override these four — a small, in-radius
scope cut of operator-requested work is still a Taste/User-Challenge surface.

### Precedence — engineering/architecture forks go to the CTO, not the operator

Architectural-fork decisions (schema/audit substrate, data model, technology
choice, security model, which load-bearing module to disturb) route to the
`soleur:engineering:cto` agent per `work` Phase 1 (the CTO HARD GATE), in **both**
modes. They are **not** User-Challenges even when user-visible. This taxonomy
governs **product / scope / preference** decisions only — never *how* to build.

## Mode-branched resolution (keyed on execution context, not skill name)

**Mode = execution context.** *Operator-attached* means a real operator TTY is
present: a direct `/soleur:brainstorm` or `/soleur:plan` run, `HEADLESS_MODE`
unset, not invoked with a plan-file argument, and **not inside a Task subagent**.
Any Task-subagent context (a `plan` consult, all of `one-shot`) is **headless**
regardless of the parent skill — a subagent gets prompt text only and cannot call
`AskUserQuestion` ([task-subagent-prompt-text-only](../../../../../knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md); guarded at `plan` Step 2.5). A subagent
returns any surface-worthy decision to its parent as structured text.

| Class | Operator-attached (real TTY) | Headless (no attached operator, incl. any subagent / one-shot) |
|---|---|---|
| Mechanical | auto-decide silently | auto-decide silently |
| Taste (user-legible) | auto-decide + recommend; fold into the **existing** gate if one remains, else append to the run's output artifact (brainstorm decisions / plan `## Decisions Auto-Made`) — never a new pause | auto-decide + **persist to the challenges artifact** (see below) |
| User-Challenge | `AskUserQuestion` at the existing final gate (in `plan`, the post-`plan-review` confirmation), using the 5-line frame below | keep operator's **stated direction (default)** + **persist to the challenges artifact**; never pause |

### The challenges artifact + its legible surface

Headless Taste(user-legible) and User-Challenge decisions are **persisted**, not
paused on. The producer (`work`, or `plan` Step 4.5 in a subagent) appends to
`knowledge-base/project/specs/<branch>/decision-challenges.md` (alongside
`session-state.md`). At ship time, `ship` Phase 6 reads that artifact and:

1. Folds it into the canonical PR body under a heading **outside** the
   `ship-operator-step-gate` deny set (`Operator`/`Post-merge`/`Follow-up`) and
   with **no operator-action bullets** — informational statements only (e.g.
   `## Model Dissents (informational)`).
2. Opens **one** idempotent GitHub issue labelled `action-required` +
   `decision-challenge`, plain-language title linking the PR — because
   `operator-digest` harvests `action-required` *issues* (Section 4), never PR
   bodies. This is the surface the non-technical operator actually sees.

The PR-body block is the durable record; the `action-required` issue is the
legible surface. Both are required for a headless challenge.

### User-Challenge 5-line frame

When surfacing (attached) or persisting (headless) a User-Challenge, use:

- **What you said:** the operator's original direction.
- **What both signals recommend:** the proposed change.
- **Why:** the signals' reasoning.
- **What context we might be missing:** explicit blind-spot acknowledgment.
- **If we're wrong, the cost is:** what happens if the operator's original
  direction was right and we changed it.

## "Both signals" — scope, disagreement, and the security exception

**Both signals = the session model + the ADR-083 scoped `fable`→`opus` consult**,
and only at the two gates where that consult already fires: `plan` Step 4.5 and
`ship` Phase 5.5. Elsewhere (e.g. `work` emergent decisions) there is a **single**
signal — the session model + this surface criterion. **Do not add a new
per-decision consult** (that would balloon ADR-083's scoped 2-gate consult into
cost/latency creep).

- **Disagreement:** when the two signals disagree at a gate, promote the item to
  the recorded/surfaced tier (a Taste item becomes a persisted/surfaced one). The
  operator's stated direction stays the default regardless.
- **Ambiguity fail-safe defaults:** unsure Mechanical-vs-Taste **and** the
  decision is user-visible/money/compliance → treat as **Taste**. Unsure
  Taste-vs-User-Challenge → treat as **User-Challenge** (bias to the more-surfaced
  class; the cost of over-recording is one label).
- **Security/feasibility exception — the SOLE deviation from no-pause.** When a
  decision introduces an auth/secret/data-exposure regression, or makes the
  stated approach technically infeasible (not a mere preference): attached →
  urgent-framed `AskUserQuestion`; headless → **terminal halt before merge** (a
  stop, not a mid-pipeline pause) + an `action-required` + `security` issue. This
  is the only exception to bias-to-action's no-pause rule.
