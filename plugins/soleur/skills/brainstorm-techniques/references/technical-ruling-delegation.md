# Technical-Ruling Delegation — who rules, how, and where it is recorded

Canonical home of hard rule `hr-technical-fork-is-not-an-operator-question`. Skills link here instead of restating it.
"The operator" is whoever runs the skill: the founder in this repository, a Soleur end user elsewhere. The same rule
binds both, so neither is ever the one asked a technical question.

## 1. Operator-only list (closed)

Only these reach the operator. The burden of proof sits on "operator": an item is technical unless it names one of
these categories. The Class cell of the Decision Classes table (section 6) uses the category word verbatim:

`money | scope | priority | schedule | irreversible | production-mutating | legal-risk | brand`

- **money** — spend, price, a recurring cost, a new paid dependency or sub-processor.
- **scope** — dropping, deferring or adding what the operator asked for.
- **priority / schedule** — what goes first, when it ships.
- **irreversible / production-mutating** — the AUTHORIZATION to run the act (merge, dispatch, delete, rotate, apply).
- **legal-risk** — accepting regulatory or legal exposure (the legal posture itself goes to the CLO, see section 3).
- **brand** — what the product looks and sounds like.

## 2. Everything else is a technical ruling

Including a threshold or evidence bar (even when it guards a destructive step), which of two designs, whether the
evidence suffices, and a status flip. Consequence is not the test: a decision can be consequential and still be
the CTO's to make. The four NEVER-Mechanical classes in
[decision-principles.md](./decision-principles.md) decide whether the session model may auto-decide, never who rules.

- **WHAT to build is the operator's (a product-direction choice is `taste` or `operator (scope)`); HOW to build it is technical.**
  The brainstorm skill's "which approach do you prefer" about product direction stays a question to the operator.
- A **mixed item is split** into one technical ruling and one operator authorization. The threshold that guards a
  destructive step is technical; the authorization to run the step is the operator's, and names the ACTION.
- An **ADR status flip whose criterion the ADR itself states** is mechanical: run the grader, cite its output, flip.
  No ruling is needed.
- **Fail-safe default** when user data is at stake: the CTO rules for the stricter option.
- **De minimis bound.** A choice that is reversible within the diff and sets no durable contract (an abstraction, a
  query shape, a test helper) stays **Mechanical**: auto-decide, write no row. Spawn the CTO when the model would
  otherwise ask someone, persist the item to `decision-challenges.md`, or record a dissent; and for a threshold or
  evidence bar, a design with a durable consequence (schema, contract, security model, substrate, status flip), or
  anything an ADR reader would need the rationale for. Rule of thumb: if you would write the item down or ask, it goes
  to the CTO; if you would just write the code, it does not.

## 3. The delegation step

When a phase reaches a technical ruling, spawn the owner of the domain and continue with what it returns:

- Engineering and architecture: `soleur:engineering:cto` (`Agent` tool, `subagent_type: soleur:engineering:cto`).
- Legal posture (published-claim scope, lawful basis, balancing test, Art. 30 entry, Art. 13-14 notice adequacy,
  retraction versus scoping, notice versus instrument asymmetry, whether a compliance condition can be discharged):
  `soleur:legal:clo`. Require **drafted replacement wording** back, not only a verdict.
- Other domains: the domain leader through the existing domain-leader pattern.

Copy this brief, filling the angle brackets (a CTO that is not told the shape returns an options menu, which is not a ruling):

```text
Rule on this technical question. Do NOT use AskUserQuestion. Choose ONE option; do not return a menu.
Question: <the question>
Evidence (file:line, command output): <evidence>
Options and trade-offs: <options>
Brand-survival threshold: <the plan's value>
Facts that would DISQUALIFY the option not preferred: <facts>
Reply with exactly these four headings: Decision: / Rationale: / Rejected alternatives: / Dissent:
```

For legal posture add the governing records (determination, Art. 30 / 30(2) registers, LIA, any instrument) and the binding
constraints to the brief, and require drafted replacement wording back. Qualified-counsel review is a different act with a
different cost: it goes through the threshold catalog, never as an inline question. Implement exactly what it returns. This is a routing rule, not an
approval gate, so it fires in pipeline mode too. **Weight is not a routing signal**: a decision feeling consequential
is the reason to route it to its owner, never past it. A headless Task subagent that has the `Agent` tool spawns the
leader itself; one that does not returns the row as `pending - assumed: <default>` and its parent obtains the ruling
(one-shot right after the plan phase, otherwise `ship` Phase 5.5). **One batched spawn carries ALL pending rows**; the two-spawn cap counts spawns, not rows, and each spawn is added to the pipeline tally (`incr agent_rounds`).

Reserve external escalation (qualified counsel, a vendor, a regulator) for what cannot be decided in-house, through
the threshold catalog in `knowledge-base/legal/recommended-tools.md` plus a tracked issue, never as an inline operator
question. Architectural forks found mid-work (a plan's mechanism structurally blocked or contradicted by the code,
traced from the ACTUAL producer) route here too; record the decision and the rejected alternatives in an ADR
(`soleur:architecture`).

**Why:** #5325 — the plan's `action_sends`-reuse mechanism was structurally blocked and the substrate choice (dedicated
WORM table vs gate-only vs full reuse) was first offered to the operator before the CTO ruled. See
`knowledge-base/project/learnings/workflow-patterns/2026-06-15-architectural-fork-decisions-route-to-cto-not-operator.md`.
**Why (legal):** #7347 — three legal-posture decisions were offered to the operator, who asked why the CLO was not
taking ownership. See `knowledge-base/project/learnings/workflow-patterns/2026-08-09-legal-decisions-route-to-clo-not-operator.md`.

## 4. Recording format

Write `Ruled by CTO agent, <date>: <decision> - <rationale>.` (CLO for legal) in the plan, spec, ADR or PR body, plus
`Dissent: <line>` when the agent returned one. A ruling or dissent that names user-data loss, an irreversible act,
money or legal exposure adds an operator row that names the ACTION and cites the technical row's item id.

## 5. Override clause

A brief or an operator message that says "surface it / do not decide it" about a technical item is still routed to the
CTO. Ask the operator only the authorization part, naming the action. **Why:** 2026-10-11 — a task brief said to surface
two technical rulings and not decide them; both reached the founder, who said the CTO should rule, not them and not
Soleur users (`decision-challenges.md` of that branch: "Surfaced, not decided, as directed").

## 6. The `decision-challenges.md` classification table

`knowledge-base/project/specs/<branch>/decision-challenges.md` carries at least one `## Decision Classes` pipe table with one row
per persisted decision, whatever shape the free-form body uses. Columns: `Item | Class | Ruling`.

- **Class:** `technical`, `taste`, or `operator (<category>)` with a category from section 1; a bare `operator` is
  invalid. `taste` is the user-legible Taste class of [decision-principles.md](./decision-principles.md): auto-decided
  with a recommendation and rendered under Model Dissents; it needs no ruling cell and files no issue. A user-visible
  *preference* is `taste`, never an operator category. A technical row that overrides a direction the operator STATED also
  gets an `operator (scope)` row naming that override, so the operator sees it.
- **Ruling, technical row:** `Ruled by CTO agent, <date>: <decision> - <rationale>` (`CLO` for legal; and `Dissent: <line>` when
  present). If the ruling differs from what a headless subagent assumed and built, re-enter `work` for the item.
- **Ruling, operator row:** the ACTION being authorised, citing the sibling technical row's item id when split.
- `pending - assumed: <default>` is the placeholder a subagent without the `Agent` tool writes; the main context
  replaces it before `work` (one-shot) or the gate fails it as `unruled-technical`.

`ship/scripts/technical-ruling-gate.sh` scans EVERY unfenced `| Item | Class | Ruling |` table (a later writer may add
its own), the file-wide `pending - assumed` placeholder and the owner-label lint, plus the PR body. An artifact with no
table is a `[WARN]` and exit 0 (legacy artifacts and in-flight branches are not blocked). **Stated residual:** the gate
checks form, never truth, so a technical question labelled `operator (scope)` passes; operator rows render in the PR
body and the `action-required` issue, which is where review and the operator see a mislabel. The gate's remedy is bounded: at most two CTO spawns per artifact; after that the PR stays draft and ship files one
`domain/engineering` issue, never an operator question. Procedure: [decision-challenges-render.md](../../ship/references/decision-challenges-render.md).

## 7. Canonical example

The test suite extracts the fenced block below and feeds it to the gate, so a drift between this schema and the parser
fails CI.

```text
## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 evidence bar before the cleanup deletes the guard constants | technical | Ruled by CTO agent, 2026-10-11: keep the thresholds, the gate is single-use and deleted - tightening protects nothing |
| T1a authorization to run the cleanup | operator (production-mutating) | Authorise merging the cleanup PR that deletes the guard (split from T1) |
| T2 wire seven skills or only the choke points | operator (scope) | Keep the seven skills the brief names |
| T3 which of two log wordings reads better | taste |  |
```
