---
title: "feat: route technical rulings to the CTO agent, not the founder or the Soleur end user"
date: 2026-10-11
slug: route-technical-rulings-to-cto-agent
branch: feat-one-shot-cto-technical-rulings
issue: none
---

## Overview

Technical rulings reached the founder twice on 2026-10-11 (how strict an evidence bar must be before a
cleanup retires constants that guard a destructive step, and whether an ADR's status moves from
`adopting` to `accepted`). The existing rule `hr-technical-fork-is-not-an-operator-question` was in
force and did not catch either. This plan finds the real routing path that carried them, then closes it
in the rule corpus, one shared delegation reference, the skills that reach such forks, the pre-ask hook,
and a script-backed ship gate (a closing-message arm was considered and cut).

## Research Insights

### Premise Validation (Phase 0.6)

Checked: PR 10049 is the open draft for this branch (holds). Issue 7462 (origin of the pre-ask hook) is CLOSED
(history only, nothing to resolve). Issue 9642 ("Decide how strict the web-2 emptiness evidence must be ...") is
OPEN, authored by the owner, labelled `action-required` + `decision-challenge` + `type/question`: it is the
live artifact of the failure, not a blocker for this plan. No open issue covers this work (`gh issue list
--search` returned none). Cited symbols confirmed on disk: the hook, its test, the rule line, the work/review
CTO bullets, ship step 2.5.

**Four hypotheses from the brief, verified against code, with two corrections and one new root cause:**

| # | Brief hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | The hook sees only AskUserQuestion; chat prose, issues and PR-body lines are invisible | Holds | `pre-ask-technical-fork-gate.sh`: `[[ "$HOOK_TOOL_KIND" == "AskUserQuestion" ]] \|\| exit 0`; registered only for matchers `AskUserQuestion` / `^ask_user_question$` in `.claude/settings.json`. The Stop hook `plugins/soleur/hooks/unkept-promise-hook.sh` is the only component that sees closing chat text and it has no ruling arm. |
| H2 | The hook vocabulary targets investigation paths; a ruling has no signal; the deny names no CTO | Holds, with a worse detail | `INVESTIGATIVE_RE` is "read the / check whether / ask the owner ..."; a ruling question ("how strict ...", "flip adopting to accepted") matches neither it nor `AUTHORITY_RE`, so it falls to `exit 0` (allowed). Worse: `AUTHORITY_RE` contains bare `delete`, so the observed question (a threshold before a cleanup "deletes" constants) is short-circuited as an authorization even before the investigative test. No deny text anywhere names `soleur:engineering:cto`. The hook is repo-local (`.claude/`), so Soleur end users never had it. |
| H3 | No skill carries the rule | **Partly false** | `work/SKILL.md` (Phase 1 bullets "Architectural-fork decisions route to the CTO agent" and the CLO sibling) and `review/SKILL.md` Step 1 item 4 already route binding forks to the CTO/CLO and forbid AskUserQuestion. `decision-principles.md` §Precedence carries a CTO carve-out. The gap is scope (architecture forks only, in two skills) and absence from `go`, `one-shot`, `plan`, `ship`, `brainstorm`, `compound`. |
| H4 | The operator's brief can instruct the agent to surface a ruling and the agent obeys it literally | Holds | `decision-challenges.md` of the web-2 branch: "Surfaced, not decided, as directed". The plan table row 4 of the sibling plan: "Surfaced, not decided ... listed neutrally". Nothing in the rule says a brief cannot override routing. |
| **H5 (new, the real carrier)** | The ADR-084 decision pipeline itself routes consequence-heavy technical items to the founder | **Holds, root cause** | `decision-principles.md` classifies by consequence and lists four NEVER-Mechanical classes, one being "irreversible or destructive operations on user data". Headless runs persist such items to `decision-challenges.md`; `ship/SKILL.md` Phase 6 step 2.5 renders it into the PR body and files an `action-required` + `decision-challenge` issue "because operator-digest harvests action-required issues". Issue 9642 is that exact output, including the words "Decision needed from the owner". The taxonomy answers "may the session model auto-decide this" and was silently reused as "who rules this". |

### Why the existing rule did not catch it

Three independent bypasses compose: (1) the hook is AskUserQuestion-only and repo-local; (2) the ruling was
carried by an artifact pipeline (plan persist, then ship render, then a GitHub issue), no tool call to gate;
(3) the brief authorised the surfacing and the rule has no override clause. The two skills that do route to the
CTO are the two that run late (work, review), after plan has already persisted the ruling as an owner item.

### Constraints discovered that shape the design

- **SKILL.md byte ceilings are at zero headroom and cannot be raised in the same PR.**
  `plugins/soleur/test/skill-body-budget.json` ceilings, enforced against the merge base by
  `scripts/lint-skill-body-budget.py`. Measured now (ceiling minus size): plan 2, review 19, ship 0, work 0,
  brainstorm 125, compound 110, deepen-plan 103, one-shot 4236, postmerge 5122, qa 8. `go` and `plan-review` are
  not in the ledger. Consequence: every SKILL.md edit in plan, review, ship, work, brainstorm and compound must be
  byte-neutral or negative, funded by moving existing prose into the shared reference and leaving a pointer. A ceiling
  may be lowered in the same PR (driving a number down never reds).
- **Rule-body edits are human-gated.** `scripts/lint-rule-bodies.py --check` (CI job `rule-body-lint`) blocks any
  change to an `hr-*`/`wg-*` body unless `.claude/rule-body-hashes.txt` is regenerated (`--write`) and a matching
  ack line is appended to `.claude/rule-weakening-acks.txt` (CODEOWNERS-owned). Precedent acks read "NOT a weakening -
  strictly additive". `AGENTS.rules.md` is also CODEOWNERS `@deruelle`, so the PR needs the owner's review anyway.
  This is the one genuine operator-class item in this work (authorising a change to a hard rule), and it is asked
  as an authorization, not a technical question.
- **AGENTS budget.** Rule line is 314 bytes of a 600 cap; always-loaded payload measured 43166 (lint) against warn
  44000 and reject 46000: 834 bytes of headroom to the warn line. The amended body must stay at or under about 590
  bytes (cq-agents-md-why-single-line: one-sentence Why).
- **Skill description word budget is at 0 headroom** (2413/2413, `SKILL_DESCRIPTION_WORD_BUDGET`). This plan edits
  no `description:` and adds no skill or agent, so counts in README/plugin.json/docs do not move; the budget test is
  a verification step, not an edit.
- **Reference files must be linked, not backticked** (`components.test.ts`: "No backtick file references in
  skills", "references/ files are reachable from their skill", and the "Decision-principles taxonomy wiring"
  block, which is the template for a new wiring block).
- **The pre-ask hook's classifier history is a minefield** (header + D4..D9, V3 in its suite): authorization-never-blocked
  polarity, question-text-only exemptions, and a V3 subset assertion between `AUTHZ_VERB_RE` and `AUTHORITY_RE`.
- **`unkept-promise-hook.sh` documents an over-block incident** (an earlier arm blocked 13 of 15 rule-mandated
  operator gates) and the `stop_hook_active` once-per-chain bound. A new arm there must be narrow and fail toward
  permitting.
- **The CTO agent has no ruling-mode contract** (`agents/engineering/cto.md` mentions neither AskUserQuestion nor a
  ruling output shape), so the delegation prompt, not the agent file, must carry "do NOT use AskUserQuestion" and
  the required output shape.

### Institutional learnings applied

`2026-06-15-architectural-fork-decisions-route-to-cto-not-operator.md` and `2026-08-09-legal-decisions-route-to-clo-not-operator.md`
(routing rule, not an approval gate; weight is not a routing signal; require drafted wording back);
`2026-07-04-plan-persisting-a-record-into-the-pr-body-must-target-ship-not-work.md` (ship is the sole PR-body
author; section names must avoid the `ship-operator-step-gate` deny tokens `Operator`/`Post-merge`/`Follow-up`; the
digest harvests issues, not PR bodies); `2026-08-03-i-asked-the-operator-to-approve-a-premise-i-had-not-enumerated.md`;
`2026-08-02-a-guard-that-derives-authority-must-use-the-authoritys-own-parser.md` (reuse the corpus parser);
`2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md` (an ack in the same diff certifies nothing
without the CODEOWNERS review: say so); `2026-05-29-command-detection-hook-self-interception-and-heredoc-fp.md` and
`2026-06-12-command-detection-hook-fp-sweep-and-fixtures-as-latent-bug-detectors.md` (quoted phrases in commit
messages and fixtures trip phrase-class hooks; pipefail no-match fail-open); `2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md`
(the hook re-gates `tool_name` in its body; both registries); `plan-sharp-edges.md` first bullet (CTO brief must list
facts that disqualify the rejected option).

### Property List and Cut List (Phase 0.6b)

**Properties the ask buys** (each observable):

- P1. A technical question never reaches the founder or a Soleur end user as a question, an issue, or a PR-body
  line; only authorization, money, scope, priority/schedule, legal-risk acceptance and brand do.
- P2. When a pipeline phase reaches a technical ruling it is decided by the CTO agent (CLO for legal), and the
  ruling plus rationale is recorded where the next reader looks ("Ruled by CTO agent, <date>").
- P3. An operator brief that says "surface it, do not decide it" does not change P1 for the technical part; the
  operator is asked only the authorization part.
- P4. A ruling that was not obtained blocks ship with a remedy that obtains it, not a bare stop.
- P5. The definition lives in one canonical place and the skills cite it rather than restate it.

**Mechanisms the ask names, and what already buys each property:**

| Mechanism in the ask | Property | Already on main? | Disposition |
|---|---|---|---|
| Amend the existing rule body | P1, P3, P5 | Rule exists (`AGENTS.rules.md`, tags: hook) | Keep: amend in place (CTO ruling R1) |
| Shared delegation reference | P2, P5 | Partial: `work` CTO/CLO bullets, `review` step 4, `decision-principles.md` §Precedence | Keep: generalise and MOVE those into one file; they become pointers |
| Wire skills | P1, P2 | 2 of 9 | Keep for the seven named skills as byte-neutral pointers (see Scope Check on the CTO's narrower cut) |
| Extend the pre-ask hook | P1 | Hook exists, wrong vocabulary | Keep, narrow, secondary (CTO ruling R2) |
| Lint prose-only surfacing | P1, P4 | `ship` step 2.5 renders everything; no class on items | Keep as the ship gate script (the deterministic form); chat-prose arm cut |
| Ship checklist / PR-body line rule | P1, P4 | Undeferred Operator-Step Gate (different property) | Keep as a new script-backed gate modelled on the PIR gate |
| Tests, budget parity, learning | all | patterns exist | Keep |

**Cut List (mechanisms removed before research):**

- Stop-hook prose arm in `unkept-promise-hook.sh` -> P1 for chat text -> cut: exact-label matching is brittle, the
  hook's own header records a 13-of-15 over-block, and once ship stops emitting the label (the gate) the surface it
  would catch has no producer. CTO ruling R3. Tracked as a deferral with a recurrence trigger.
- Port of the AskUserQuestion gate into the plugin -> P1 for end users -> cut: subagents cannot call
  AskUserQuestion, and the end-user surface is the skill text plus the ship gate, both in scope. CTO ruling R5.
- A ruling-mode section in `agents/engineering/cto.md` -> P2 -> cut: the delegation prompt in the shared reference
  carries the output contract; editing the agent file adds budget cost and a second copy.
- A `compound` pointer -> P2 -> cut: compound routes learnings, it never reaches a ruling fork, and its ceiling has
  110 bytes of headroom. It inherits transitively through `decision-principles.md`.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "grep found no skill that mentions the rule" | `work` Phase 1 and `review` Step 1 item 4 route architecture and legal forks to CTO/CLO; `decision-principles.md` §Precedence names the carve-out | Generalise and relocate the existing text; do not add a parallel rule |
| "The deny reason does not point at the CTO agent" | True; and the hook cannot see the observed carrier at all (an artifact pipeline, not a tool call) | Fix the carrier first (ship gate + taxonomy), the hook second |
| "extend the existing rule body ... respect the AGENTS budget" | Body edits to `hr-*` rules need a regenerated hash and a CODEOWNERS-owned ack line | Amend in place, ~590 bytes, record the ack as the one operator authorization item |
| "wire it into the skills ... at least go, one-shot, plan, work, review, ship, brainstorm" | Five of those SKILL.md files sit at 0-125 bytes under a merge-base-anchored ceiling that cannot be raised in the same PR | Every edit funded by moving existing prose into references; Phase 0 measures net bytes per file before any edit lands |
| "Soleur end users are never asked" | The AskUserQuestion hook is repo-local; end users get skills, `plugins/soleur/hooks/` and `ship` scripts only | The end-user guarantee rests on the skill text, the reference and the ship gate script (all shipped) |

## Problem Statement

On 2026-10-11 two technical rulings were put to the founder: how strict the evidence bar must be before a cleanup
retires constants guarding a destructive step (issue 9642), and whether an ADR's status moves from `adopting` to
`accepted` once its stated grader condition holds. The founder replied that the CTO should rule, not them and not
Soleur users. Hard rule `hr-technical-fork-is-not-an-operator-question` already said so. It did not fire because the
ruling travelled through the decision-challenge pipeline (H5), whose consequence-based classes answer "may the
session model auto-decide this" and were reused as "who rules this".

## Proposed Solution

One definition, one delegation step, and the three places a ruling can leak.

1. **Definition (closed list, burden on "operator").** Operator-only: money, scope, priority/schedule, authorization
   of an irreversible or production-mutating act, legal/regulatory risk acceptance, brand. Everything else is a
   technical ruling. A threshold that guards a destructive step is a technical ruling; the authorization to run the
   step is a separate operator question; a mixed item is split into one record of each. An ADR status flip whose
   criterion the ADR itself states is mechanical: run the grader, cite its output, flip, no ruling at all.
2. **Delegation step** (new `technical-ruling-delegation.md`, cited by skills): spawn `soleur:engineering:cto`
   (`soleur:legal:clo` for legal) with the evidence, the question, the facts that would disqualify the option not
   preferred, "do NOT use AskUserQuestion", and a required output of Decision / Rationale / Rejected alternatives /
   Dissent line. Record `Ruled by CTO agent, <date>: <decision> - <rationale>` (plus `Dissent:` when present) in the
   plan, spec, ADR or PR body. A brief that says "surface it" changes nothing for the technical part.
3. **Taxonomy fix** (`decision-principles.md` §Precedence): a technical ruling goes to the CTO in both modes and is
   never persisted to `decision-challenges.md` as an owner item; the four NEVER-Mechanical classes decide whether the
   session model may auto-decide, not who rules. `decision-challenges.md` gains a mandatory `## Decision Classes` table (one row per persisted decision: item, class, ruling).
4. **Ship gate** (`technical-ruling-gate.sh` + suite): reads the artifact's Decision Classes table and the PR body; blocks a
   row with no valid class, a `technical` row with no well-formed `Ruled by` cell, and any "Owner decision needed" label not
   carried by `(operator: <category>)`. Remedy text: spawn the CTO now (at most twice), write the Ruled-by cell, re-run. Step 2.5 files the
   `action-required` issue for operator-class items only.
5. **Hook** (secondary): a narrow ruling arm in the pre-ask hook, ahead of the authority short-circuit, exempting only
   permission-seeking shapes on the question text; deny reason names `soleur:engineering:cto` and the reference.

## Ruled by CTO agent, 2026-10-11 (plan-time ruling, brief on the design above)

Spawned `soleur:engineering:cto` with five measured facts (the hook's scope, the ADR-084 carrier, the brief's own
wording, the rule-body hash gate, the Stop-hook over-block record) and the proposed design D1-D5, "do NOT use
AskUserQuestion". Abridged substance of the ruling (R1-R6 are the CTO's numbering):

- **R1 Boundary and placement.** Boundary right with one inversion: the operator list is closed and everything else
  defaults to the CTO; the burden of proof sits on "operator". A threshold guarding a destructive step is technical,
  its authorization is a separate operator question, the CTO rules fail-safe (stricter) when user data is at stake,
  mixed items are split, an ADR flip with an ADR-defined criterion is mechanical. Amend the rule in place (migrating
  the body out of the corpus would remove it at the moment the model decides). Add a `[skill-enforced: ship
  Technical-Ruling Gate]` tag; keep `[hook-enforced]` only as far as true; ack wording "strictly additive".
- **R2 Hook.** Two flaws in the draft: an exemption list containing bare dispatch/deploy/merge/rotate/revoke/cost/budget/scope
  words would exempt the observed question (issue 9642 says "before the rebirth is dispatched ... before the volume is
  deleted"); and the cue set is overfit. Narrow the exemption to permission-seeking shapes (`may/can/should I|we <verb>`,
  `ok to`, `go-ahead`, `approve`, `authorize`, `ack-destroy`), money/scope/priority words exempt only as head nouns.
  Keep the cue set small and treat the hook as secondary: the observed carrier was a file and an issue, so the hook
  would not have fired on it.
- **R3 Stop-hook prose arm.** Do not implement. D4 removes the label at its source. Tracked deferral with a recurrence
  trigger. (If overridden: exact label, no `Ruled by` anywhere, no operator vocabulary, once per chain, fail-permit.)
- **R4 Ship gate.** Script plus a `*.test.sh` suite. Require `Class: operator (<category>)` with a category from the
  closed list; a bare `Class: operator` fails (stops self-labelling). The remedy is "spawn the CTO now, write the
  Ruled-by line, re-run", never a bare block. Unparseable fails closed; a missing file passes; step 2.5 files an issue
  for operator-class only; a split item yields one technical and one operator record.
- **R5 Port of the gate to the plugin.** Deferral accepted (subagents cannot call AskUserQuestion); file the tracked issue.
- **R6 Most likely failure.** Self-classification at the writer (the model that wrote "owner ruling needed" writes
  `Class: operator`), and one-shot subagents that never read the reference because Task subagents get prompt text only.
  Cheapest cut: move the burden to the single write choke point (technical unless it names a closed-list operator
  category, enforced by the D4 script); cite only choke points; inline a three-line rule plus the explicit override in
  one-shot's subagent prompt text; a subagent that cannot spawn the CTO writes `Class: technical` with no Ruled-by line and
  ship's gate spawns the CTO in the main context.
- **Dissent:** none on the core design; rejects D3 and the nine-skill citation sprawl.

**Adopted:** R1, R2, R3 (arm cut, deferral filed), R4, R5, R6 (burden-of-proof rule, one-shot inline; the `ruling-pending` spelling is folded into `unruled-technical`, which has the
same check and the same remedy, per plan review).
**Schema note (deepen, 2026-10-11):** the CTO's `Class:` line is realised as a row in one `## Decision Classes` table, because the
artifact has no single item shape (see Guard 1); the ruling's substance (closed categories, bare `operator` invalid, Ruled-by required)
is unchanged.

**Not adopted as ruled:** the cut of the skill citations. The brief names go, one-shot, plan, work, review, ship and
brainstorm as the places to wire; that is stated scope, and dropping it is a NEVER-Mechanical class (operator-requested
scope). Default taken: honour the brief with byte-neutral pointers; the CTO's choke-point-only form is the fallback
for any file where Phase 0 cannot fund the pointer. Recorded as a scope item in
`knowledge-base/project/specs/feat-one-shot-cto-technical-rulings/decision-challenges.md` (`Class: operator (scope)`).

## Technical Approach

### Candidate rule body (AGENTS.rules.md line for `hr-technical-fork-is-not-an-operator-question`)

Target at or under 590 bytes (measured with `wc -c`, cap 600). The candidate below measures 600 with the clause
"evidence sufficiency," and about 578 without it; Phase 5 takes the shorter form and measures:

> - Never ask the operator a technical question: an investigation path or a ruling (threshold strictness, design A-vs-B) [id: hr-technical-fork-is-not-an-operator-question] [hook-enforced: .claude/hooks/pre-ask-technical-fork-gate.sh] [skill-enforced: ship Technical-Ruling Gate]. Resolve it (issue, runbook, ADR, guard comments) or spawn `soleur:engineering:cto` (legal: CLO), record "Ruled by CTO agent"; a "surface it" brief changes nothing. Operator-only: money, scope, priority/schedule, irreversible/prod-mutating authorization, legal-risk acceptance, brand. **Why:** #9642.

The index line in `AGENTS.md` is unchanged (ids are immutable). Growth is about +265 bytes on 43239 loaded
(warn 44000). The `[skill-enforced: ship Technical-Ruling Gate]` unit must resolve to a ship heading
(`scripts/lint-agents-enforcement-tags.py`).

### Shared reference: `technical-ruling-delegation.md` (sections)

1. **Operator-only list (closed):** "the operator" is whoever runs the skill (the founder here, a Soleur end user
   elsewhere; same rule for both). money (spend, price, recurring cost, new paid dependency), scope, priority and
   schedule, authorization of an irreversible or production-mutating act, legal/regulatory risk acceptance, brand.
   Categories used verbatim by the Class cell: `money | scope | priority | schedule | irreversible |
   production-mutating | legal-risk | brand`.
2. **Everything else is a technical ruling,** including: a threshold or evidence bar (even when it guards a
   destructive step), which of two designs, whether evidence suffices, a status flip. Mixed items split into one
   ruling and one authorization. A status flip whose criterion the ADR itself defines is mechanical (run the grader,
   cite its output, flip).
3. **The delegation step** (the one block skills point at; headless: a Task subagent spawns the CTO itself when it has the Agent tool): when to spawn, who (`soleur:engineering:cto`;
   `soleur:legal:clo` for legal posture; the other domain leaders through the existing domain-leader pattern for their
   domains), what the brief contains (evidence with `file:line`, the question, options with trade-offs, the plan's
   brand-survival threshold, the facts that would DISQUALIFY the option not preferred, "do NOT use AskUserQuestion"),
   required return shape (Decision / Rationale / Rejected alternatives / Dissent line; drafted wording for legal).
4. **Recording format:** `Ruled by CTO agent, <date>: <decision> - <rationale>.` plus `Dissent: <line>` when present, in the
   plan, spec, ADR or PR body. Fail-safe default when user data is at stake: the stricter option.
5. **Override clause:** a brief or an operator message that says "surface it / do not decide it" about a technical
   item is routed to the CTO anyway; ask the operator only the authorization part, naming the action.
6. **`decision-challenges.md` classification table.** One `## Decision Classes` pipe table (columns Item, Class, Ruling)
   holds one row per persisted decision, whatever shape the free-form body uses. Class cell: `technical` or
   `operator (<category>)` (a bare `operator` is invalid). Ruling cell of a technical row: `Ruled by CTO agent, <date>:
   <decision> - <rationale>; conforms: yes|no|n/a (<note>)`, plus `Dissent: <line>` when present; a headless subagent that
   cannot spawn the CTO writes `pending - assumed: <default>` and the main context (one-shot after the plan phase, or ship's
   gate) obtains the ruling. Ruling cell of an operator row: the ACTION being authorised, citing the sibling technical row's
   item id when the item was split. A ruling or dissent that names user-data loss, an irreversible act, money or legal exposure
   adds an operator row. The section ends with one canonical example table that the suite feeds to the gate.
7. **The moved text:** the `work` CTO and CLO HARD GATE bullets and `review` step 4 are moved here (their `Why`
   lines and learning links preserved), generalised from "architecture fork" to "technical ruling".

### Files to Edit

- `AGENTS.rules.md` (rule body, tag), `.claude/rule-body-hashes.txt` (`python3 scripts/lint-rule-bodies.py --write`),
  `.claude/rule-weakening-acks.txt` (append one ack, reason "NOT a weakening - strictly additive ...")
- `.claude/hooks/pre-ask-technical-fork-gate.sh` and `.claude/hooks/pre-ask-technical-fork-gate.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` (§Precedence rewrite, Decision Classes table schema)
- `plugins/soleur/skills/plan/references/plan-scope-check.md` (its BLOCKED-rows append gains the Decision Classes row, `operator (scope)`)
- `plugins/soleur/skills/go/SKILL.md`, `one-shot/SKILL.md`, `plan/SKILL.md`, `work/SKILL.md`, `review/SKILL.md`,
  `ship/SKILL.md`, `brainstorm/SKILL.md` (pointers; see byte-funding table)
- `plugins/soleur/skills/plan-review/SKILL.md` (one link to the reference; no byte ceiling applies)
- `plugins/soleur/test/components.test.ts` (new wiring block, modelled on "Decision-principles taxonomy wiring"; and the existing test "ship renders the challenge record + files the action-required issue", which pins the tokens `decision-challenges.md`, `action-required` and `decision-challenge` in `ship/SKILL.md`: the step 2.5 pointer keeps all three, or the test is repointed to `decision-challenges-render.md` in the same commit)
- `plugins/soleur/test/skill-body-budget.json` (ceilings for work, review, ship lowered to the new sizes; none raised)
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` (amend)
- `knowledge-base/project/learnings/2026-10-11-<slug>.md` (compound learning; slug chosen at compound time)

### Files to Create

- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`
- `plugins/soleur/skills/ship/references/decision-challenges-render.md` (moved step 2.5 body + the gate's remedy procedure)
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh`
- one new file under `plugins/soleur/skills/plan/references/` receiving plan section 2.6's lifecycle-staging paragraph (byte funding)
- `plugins/soleur/test/technical-ruling-gate.test.sh` and `plugins/soleur/test/fixtures/technical-ruling-gate/*.md`
  (auto-registered by the `plugins/soleur/test/*.test.sh` glob in `scripts/test-all.sh`; `lint-orphan-test-suites.sh` confirms)
- `knowledge-base/project/specs/feat-one-shot-cto-technical-rulings/tasks.md`, `.../decision-challenges.md`

No new skill, agent or command is created, so README/plugin.json/docs counts and
`SKILL_DESCRIPTION_WORD_BUDGET` (0 headroom) are untouched; no `description:` is edited.

### Byte-funding table for SKILL.md edits (ceilings anchored to the merge base)

Phase 0 re-measures each size with `wc -c` and records the net; the rule is **net <= 0 per file**. Every pointer carries
its trigger inline (any threshold or evidence bar, design A-vs-B, status flip, "surface it" brief: spawn the CTO per the
reference), not only a link, because the moved bullets were the trigger text in the always-read file. Ceilings are lowered
only for the files that shrink materially (work, review, ship); the others keep their ceiling, so a concurrent PR touching
plan or brainstorm is not squeezed by this change.

| SKILL.md | Headroom now | Pointer cost (est.) | Funding |
|---|---|---|---|
| work | 0 | ~350 B (one bullet replaces three) | Move the CTO bullet (~2.5 KB) and CLO bullet (~2.9 KB) into the reference; net about -4.5 KB; the emergent-decisions bullet gains one sentence |
| review | 19 | ~200 B | Step 1 item 4 (~1.4 KB) becomes a pointer; net about -1 KB |
| ship | 0 | ~600 B gate section + ~500 B step 2.5 | Step 2.5 body (~1.9 KB) moves to `ship/references/decision-challenges-render.md`; net about -0.8 KB |
| plan | 2 | ~200 B (Plan Review step 2 and Step 4.5 each name the rule) | Move a real block, not a trim: section 2.6 "Sign-off lifecycle staging" (about 2 KB, Phase 0 measures it) into a new `plan/references/` file and leave a two-line pointer; also replace the stale `:574` / `:330` line-number pointers with content anchors. If the move is declined at review, the pointer is dropped in favour of the transitive `decision-principles.md` link |
| brainstorm | 125 | ~110 B | One sentence in Phase 0.5; trimmed words in the same bullet |
| one-shot | 4236 | ~400 B | Inline three-line rule + override in the plan and work subagent prompts (prompt text is the only channel a Task subagent reads; this is the one deliberate copy, pinned by the wiring test) |
| go | not in ledger | ~400 B | Added freely |
| compound, plan-review, deepen-plan | n/a | 0 | Inherit through `decision-principles.md` (already linked by plan-review); no edit |

### Implementation Phases (test-first, per `cq-write-failing-tests-before`)

**Phase 0 - Setup and measurements (no product edits).** `git fetch origin main`; record: `wc -c` of the eight
SKILL.md files, `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` (B_ALWAYS), `bun test
plugins/soleur/test/components.test.ts` (baseline green), `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh`
(baseline). Create the tracking GitHub issue for this work (`Closes #N` goes in the PR body only, never the title),
and file the two tracked deferrals (Deferral Tracking below). Measure with `wc -c` the exact blocks Phase 4 moves (the `work` CTO and CLO bullets, `review` step 1 item 4, `ship` step
2.5, and `plan`'s section 2.6 lifecycle-staging paragraph) and replace the estimates in the byte-funding table with those
numbers before RED. Grep `plugins/soleur/test` and `scripts` for anchors in
the `work`/`review`/`ship` text about to move (no test pins were found at plan time for the work/review CTO and CLO
bullet text; ONE pin exists for ship step 2.5, see Files to Edit; confirm both).

**Phase 1 - RED.** Write, and watch fail, in this order: (a) hook cases R1-R10 and Z1-Z4 (Test Scenarios) incl. the reason
assertions, the per-question payload builder, and the V1 inventory count and `MIN_CASES` raised by the number of new cases; (b) `technical-ruling-gate.test.sh` + fixtures against a script that does not exist yet; (c) the
components.test.ts wiring block; (d) a byte test for the rule line (`lint-agents-rule-budget.py` run).

**Phase 2 - Reference and taxonomy.** Create `technical-ruling-delegation.md`; rewrite `decision-principles.md`
§Precedence (technical rulings route to the CTO in both modes; NEVER-Mechanical classes decide auto-decide eligibility,
not who rules; add the Decision Classes table schema; link the new reference, which also satisfies the reachability test).

**Phase 3 - Ship gate.** Implement `technical-ruling-gate.sh` (modes: `<path>`, `--branch`, `--pr-body <file>`; exit
0 pass, 1 fail with `[FAIL] <path>:<row>: <reason> - <remedy>`, 2 usage/IO/unparseable/no table, missing artifact = pass; the
artifact is also looked up under `specs/archive/`). Phase 3's ship edits and Phase 4's ship funding (moving step 2.5 out)
land in ONE commit, because ship has no byte headroom and a Phase 3-only commit would red the budget lint. Move
step 2.5 into `decision-challenges-render.md`, rewrite it (both classes render under the existing `## Model Dissents (informational)` heading, technical items in a
`### Ruled by CTO agent` sub-block with their Ruled-by lines and no issue, operator-class items in the existing form with the
`action-required` issue; split items yield both; no new top-level PR-body heading, which keeps the diff and the
`ship-operator-step-gate` deny-token surface unchanged). Add `### Technical-Ruling Gate (mandatory)` to Phase 5.5
(after the Soak-Gated Follow-Through Enrollment Gate, before the ADR-Ordinal Collision Gate) modelled on the Undeferred
Operator-Step Gate and the PIR gate (telemetry line, detection via the script, remedy: spawn the CTO per the reference,
write Ruled-by, commit, re-run). The gate has TWO call sites because Phase 6 full-replaces the PR body: the artifact check
(`--branch`) runs at Phase 5.5, and the PR-body check (`--pr-body`) runs in Phase 6 immediately after the `gh pr edit`
that writes the final body (the step numbered "3. Update the PR") and before `gh pr ready`, reading `gh pr view --json
body`. Phase 6 step 2.5 (render) precedes both; the "Phase 6 step 5.5" KB-archival step is a different step and is not
touched.

**Phase 4 - Skill pointers.** Apply the byte-funding table; `go`/`one-shot` get the inline three-line rule, and one-shot calls the gate (`--branch`) once after the plan phase and before `work`, resolving `pending` technical rows with the CTO in its main context;
`work`/`review` have their bullets replaced by pointers. Re-run `python3 scripts/lint-skill-body-budget.py --base
$(git merge-base origin/main HEAD)` and lower the work, review and ship ceilings.

**Phase 5 - Hook arm.** Add the ruling arm after the expert arm and before `AUTHORITY_RE`; deny reason names
`soleur:engineering:cto` and `technical-ruling-delegation.md`, instructs "split the item; ask the operator only the
authorization"; escape hatch and carve-outs unchanged. Update the header contract paragraph (a second inversion of the
polarity, stated where the first one is).

**Phase 6 - Rule and ADR.** Amend the rule body; `--write`; append the ack; run the three rule lints. Amend ADR-084
(Decision 1: the precedence carve-out generalises to technical rulings; Decision 2: the four NEVER-Mechanical classes decide
auto-decide eligibility, not who rules; Decision 3: a subagent that has the Agent tool spawns the CTO itself, otherwise it
returns the row as `pending` to its parent; Decision 5: ship renders by class; Decision 6:
"one-shot inherits, not edited" is superseded for the subagent-prompt rule only; Consequences, including the drift-guard line
about `ship` emitting the issue, which step 2.5's move changes; Alternatives: "route everything consequential to the operator" rejected, "a Stop-hook label matcher"
rejected with the 13-of-15 evidence).

**Phase 7 - Verify and compound.** Full verification list in Acceptance Criteria; `soleur:compound` for the learning;
`ship`.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Mint a new rule id for technical rulings | Near-duplicate of `hr-technical-fork-is-not-an-operator-question`; the brief and `cq-rule-ids-are-immutable` both say amend |
| Migrate the rule body into the hook/skill per `cq-agents-md-tier-gate` | The rule binds at decision time on turns that never enter the enforcer; the migration candidate test fails on citation sweep (code cites the id); CTO R1 |
| Chat-prose Stop-hook arm | Brittle on labels, documented over-block history, no producer once ship stops emitting the label (CTO R3) |
| Hook-only fix | The observed carrier was an artifact pipeline; the hook is repo-local and sees only AskUserQuestion |
| Route every consequence-heavy decision to the operator (status quo of ADR-084 class 4) | Is the defect: consequence class was reused as authority class |
| CTO edits `cto.md` with a ruling mode | Second copy of the contract; the delegation prompt carries it |
| Copy the rule into each skill | Brief forbids it; byte ceilings make it impossible; drift |

## Deferral Tracking

Each gets a GitHub issue in Phase 0 with the milestone from `knowledge-base/product/roadmap.md`, a re-evaluation
trigger, and `deferred-scope-out` where the repo's label set uses it:

1. Port the technical-ruling pre-ask gate into `plugins/soleur/hooks/` so end users get it. Trigger: a subagent-capable
   harness gains AskUserQuestion, or a recorded end-user session shows the question reaching a user.
2. Chat-prose Stop-hook arm for the exact label. Trigger (event-grep): any issue or PR body created after this ships
   whose text carries "Owner decision needed" or "Owner ruling needed" without `(operator:`; re-evaluate on first hit.

## Open Code-Review Overlap

Two open code-review issues name files this plan edits: #4133 (`plan/SKILL.md`, Observability schema parity test) and
#8593 (`components.test.ts`, a probe-gate window). **Acknowledge** both: different concerns, own cycles; this plan adds a
test block to `components.test.ts` without touching the probe-gate describe block.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled at plan time, see "Ruled by CTO agent, 2026-10-11" above. Architecture-decision, observability and
guard-contract concerns are carried in the sections below. No product/UX surface (no `.tsx`, page, or component file), no
legal posture change (CLO not needed: the plan moves no data and changes no notice), no marketing copy.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-084** (`ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md`, Accepted), not a
new ADR: the decision extends its Decision 1 ("CTO-fork precedence carve-out") and Decision 5 (headless record to `ship`),
also reinterprets Decisions 2 and 3, and narrowly supersedes Decision 6 ("one-shot inherits, not edited"): this plan adds one short inline rule to one-shot's
subagent prompts because a Task subagent reads prompt text only, so a link alone is not read. New text: a decision whose
substance is technical judgment is a *technical ruling*, routed to the CTO agent (CLO for legal) in both modes and
recorded `Ruled by CTO agent`; it is never persisted to `decision-challenges.md` as an owner item. The
NEVER-Mechanical classes govern whether the session model may auto-decide, not who rules. `decision-challenges.md`
carries a mandatory `## Decision Classes` table; `ship` renders and files by class. Alternatives Considered gains: "route every
consequence-heavy decision to the operator" (the status quo; it produced issue 9642) and "a Stop-hook label matcher"
(rejected on the 13-of-15 over-block record in `unkept-promise-hook.sh`). This is a deliverable of this plan, not a
follow-up issue (`wg-architecture-decision-is-a-plan-deliverable`).

### C4 views

No C4 impact. Checked by reading the three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors:
the only actor involved is `founder` (already modelled, the same actor the Soleur end user maps to); no new one.
(b) external systems: none added (GitHub issues and the CTO agent are existing edges; no vendor). (c) containers/data
stores touched: `platform.plugin` -> Skills, Agents, Knowledge Base, and the Hook Engine container; all exist and their
descriptions do not state anything this change falsifies. (d) access relationships: unchanged. Derived cardinalities:
the Skills container says "103 workflow skills" and Agents "67 domain agents"; this plan adds no skill or agent, so
`plugins/soleur/test/c4-count-parity.test.sh` must stay green (run in Phase 7).

### Sequencing

The ADR amendment is authored in Phase 6 describing the target state; nothing is soak-gated, so no `adopting` marker.

## User-Brand Impact

**If this lands broken, the user experiences:** a founder or Soleur end user is asked a technical question they cannot
answer (the present failure), or, if the new hook arm over-fires, a genuine authorization question is denied and a
pipeline stalls until the escape hatch is used.
**If this leaks, the user's data / workflow / money is exposed via:** no data path; the changes read local markdown and
hook input. The one exposure is decision text: ship renders `decision-challenges.md` into a public PR body and issue,
which it already does, so the gate adds no new surface.
**Brand-survival threshold:** aggregate pattern.

## Observability

Scoped to the one new executable shipped to customer CLIs (`technical-ruling-gate.sh`, observability layer 7: it runs
on the user's machine, so the signal is the process's own exit and stderr, read by the `ship` skill).

The `discoverability_test` runs from a repository checkout (preflight Check 10 at ship, before the Phase 6 step that archives
the spec directory), and it points at this branch's own `decision-challenges.md`, which carries a valid Decision Classes table, so the
command exists in THIS PR's tree and prints a real verdict. It deliberately avoids a path under `plugins/soleur/test/`:
deepen-plan Phase 4.7's suite-shaped-command check flags any `/test/` segment (measured on the first draft of this block).
It is a development-time probe, not a customer-install one.

```yaml
liveness_signal:
  what: "technical-ruling-gate.sh prints a [PASS] or [FAIL] verdict line per item and the ship skill emits a SOLEUR_RULE_APPLIED rule=hr-technical-fork-is-not-an-operator-question line when the gate runs"
  cadence: "once per /soleur:ship run, at Phase 5.5"
  alert_target: "the rule-application telemetry aggregated weekly (rule-metrics), and the ship transcript"
  configured_in: "plugins/soleur/skills/ship/SKILL.md (Technical-Ruling Gate) and plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh"
error_reporting:
  destination: "stderr of the gate script, surfaced in the ship transcript; exit 1 blocks PR-ready"
  fail_loud: "yes: exit 1 on an unruled technical item, exit 2 on an artifact with no parseable Decision Classes table (never a silent pass); a missing artifact is the only exit-0 no-op and prints [PASS] no decision-challenges artifact"
failure_modes:
  - mode: "a technical item is labelled operator to evade the gate"
    detection: "the script rejects a bare operator class and any category outside the closed list, a technical row without a well-formed Ruled-by cell, and a conforms: no ruling; the suite pins each"
    alert_route: "[FAIL] line in the ship transcript"
  - mode: "the gate is skipped because the SKILL.md section is deleted or unlinked"
    detection: "components.test.ts wiring block asserts the ship section heading, the script path and the reference link"
    alert_route: "CI red on the PR that deletes it"
logs:
  where: "ship transcript; SOLEUR_RULE_APPLIED line"
  retention: "session transcript plus the weekly rule-metrics aggregate"
discoverability_test:
  command: "bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh knowledge-base/project/specs/feat-one-shot-cto-technical-rulings/decision-challenges.md"
  expected_output: "[PASS]"
```

## Guard Contract

Three guards ship in this change: the ship gate script, the pre-ask hook arm, and the wiring test. Matrices are
derived from the design, written before the guards (Phase 1 builds them first).

### Guard 1 — Technical-ruling ship gate (`technical-ruling-gate.sh`)

**Property.** No PR reaches ready with a `decision-challenges.md` or PR-body line that asks the operator a technical
question: every persisted decision has a valid row in the artifact's `## Decision Classes` table, every `technical` row
carries a well-formed `Ruled by` cell that does not contradict what was built, and the "Owner decision needed" / "Owner
ruling needed" label appears only with `(operator: <category>)`.

**Assembly.** Two surfaces, one producer set, one parser. (1) The artifact: its `## Decision Classes` table is the contract,
because real artifacts use at least four free-form item shapes (numbered entries, `DC-n` / `UC-n` headings, `Challenge n`,
`Taste` / `User-Challenge` sections) and a body scanner would either reject most of them or miss items; one pipe table is
shape-independent and is the only thing parsed. (2) The PR body, read AFTER the Phase 6 `gh pr edit` that writes it, fences
stripped; label spellings: Owner decision(s) needed, Owner ruling(s) needed, Decision needed from the owner, case-insensitive,
over the whole artifact and the whole body. (3) The producers that append to the artifact, all of which write a row: plan Step 4.5
and Plan Review (headless persist), `plan-review`, `work` emergent decisions, and the `plan-scope-check.md` BLOCKED-rows path
(each is an operator `scope` row). Chokepoints: the script's parser (one function, both call sites) and the three call sites
(one-shot after the plan phase and before work, ship Phase 5.5, ship Phase 6 after the body write), each named in
`decision-challenges-render.md` and pinned by the wiring test. The artifact is looked up at `specs/<branch>/` and, when
absent there, under `specs/archive/` for the same branch (`archive-kb` and compound Step E can move it early), so an
early archive cannot turn the gate into a silent pass. The closed category list lives in the script, the reference and (in prose
roots) the rule body; the parity case reads all three.

Scope is the BRANCH's artifact and a PR-body file; there is no corpus mode: a plan-time count found 172 tracked non-archived
`decision-challenges.md` files and none carries a `## Decision Classes` table, so a corpus sweep would red on history. An
in-flight branch that rebases onto this gate adds the table at ship time (the remedy text says so; it is a few rows).

**Termination and failure handling (spec-flow findings).** The gate's remedy is bounded: at most two CTO spawns per
artifact; a spawn that fails, times out, or returns without Decision and Rationale counts as a failed attempt; a ruling that
says the item is actually operator-class rewrites the row as `operator (<category>)` with the CTO's reason, once; after the
cap the terminal state is NOT an operator question: the PR stays draft and ship files one `domain/engineering` issue (never
`action-required`) carrying the question and the evidence. A `Ruled by` cell whose `conforms:` token is `no` (the ruling differs
from what a headless subagent assumed and built) fails ship with the remedy "re-enter `work` for the item, or record
`conforms: n/a (nothing built on the assumption)`"; a row left as `pending - assumed: <default>` fails as
`unruled-technical`, and one-shot's main context resolves those right after the plan phase (before `work`), so a wrong
assumption does not ride through work and review. A ruling or dissent that names user-data loss, an irreversible act, money or
legal exposure adds an operator row (`operator (irreversible)` etc.) that names the ACTION and cites the technical row's item
id, never restating the threshold (an `irreversible` row is where the observed question hid its technical half).

**Mutation matrix:**

Table-driven: one fixture per row.

| # | Mutation | Expected |
|---|---|---|
| 1 | Blank the Class cell of row 2 in a table whose row 1 is compliant (a check that stops at the first row is the defect) | RED, reason `bad-class`, names row 2 |
| 2 | Blank the Ruling cell of a `technical` row, and separately set it to `pending - assumed: x` | RED, reason `unruled-technical`, remedy text names the CTO spawn and the two-attempt cap |
| 3 | Replace the row scanner with one that finds zero rows (dispatch vacuity) over a five-row table | RED: exit 2 with "0 rows examined", never exit 0 |
| 4 | `operator` with no category, then `operator (vibes)` | RED, reason `bad-category`, both spellings |
| 5 | The label `Owner decision needed` in the artifact body without `(operator: <category>)` on the line | RED, reason `owner-label-unscoped` |
| 6 | PR body line `Owner ruling needed: ...` without `(operator: <category>)`; the same line inside a fenced block | RED for the first, PASS for the fenced one |
| 7 | Remove one category from the script's list while the reference keeps it; separately drop the word `brand` from the rule body | RED in the parity case (script vs reference by token; rule body by the root words money, scope, priorit, schedul, irreversible, production, legal, brand) |
| 8 | Feed the reference's canonical example table to the gate, then break its `Class` spelling in the reference only | RED: producer/consumer contract |
| 9 | A Ruling cell `Ruled by CTO agent, 2026-10-11: x` with no dash-separated rationale part, and another with no `conforms:` token | RED, reason `bad-ruling-shape` |
| 10 | A Ruling cell ending `conforms: no` | RED, reason `ruling-contradicts-assumed`, remedy names `work` re-entry |
| 11 | A compliant table that sits only inside a fenced block | RED: exit 2 (no table), a fenced table never counts |
| 12 | Move the artifact to `specs/archive/` before the gate runs | still examined (RED when its table is bad), never a silent pass |

Rows 1, 2, 4, 5, 6 can be driven RED from the design before the script exists; rows 3, 7, 8 need the script, so they are authored
as the script's first green-then-red rows and the suite's own floor (a SUT-written execution marker count, as
`unkept-promise-hook.test.sh` does) is checked first.

**Harness rows.** Edit the suite's `run_case` to swallow the SUT's exit code -> the suite must red on its own floor. Must-PASS
inputs that are not the canonical fixture: an operator row with category `legal-risk`; a table whose Ruling cell spells `CLO`;
a `technical` row ruled with `conforms: n/a (nothing built on the assumption)`; a table preceded by free-form items in the four
real shapes (numbered, `DC-n`, `Challenge n`, `Taste` sections), copied from tracked artifacts at the time the suite is written;
an artifact absent entirely.

**Anchor.** The stored value is the category list; what must also move for a weakening to pass is the reference file and the
rule body (the parity case), so a one-diff edit to the script alone reddens it, and an edit to all three is visible in review as
a change to the closed operator list, which is the thing the CTO ruled must stay closed. The table itself is written by the
same model that wrote the rows it classifies; the gate checks form, not truth (see Risks).

### Guard 2 — Technical-ruling arm in the pre-ask hook

**Property.** A technical-ruling AskUserQuestion is denied with a reason naming `soleur:engineering:cto`, and an
authorization question is never denied by this arm.

**Assembly.** The arm evaluates EACH question separately (its question text plus its own option labels and descriptions): the
cue over that question's flattened text, the exemption over that question's TEXT only, never over the concatenation of all
questions and never over option labels (a flattened corpus lets question 1's "Approve" exempt question 2's ruling, and a button
labelled "Approve" would be a one-word bypass). It sits after the expert arm and ahead of `AUTHORITY_RE`, so it is evaluated on
every input that reaches that point. It requires a new per-question jq extraction and a multi-question payload builder in the
suite (the existing `payload()` emits one question). Other arms that can pre-empt it: the self-invocation allow and the expert arm
(unchanged). The fail-open paths (jq missing, corpus rc != 0) are unchanged and remain permit.

Sketches to be tuned against the fixtures in Phase 1 (verified in this deepen pass with `grep -E` against R1-R10 and A1-A5):

```text
CUE   : how (strict|stringent|rigorous) | (stricter|strictness|stringen) | (evidence|proof|emptiness) (bar|threshold|ceiling|floor|standard)
        | (threshold|ceiling)s? | (is|are) (the )?(evidence|proof) (enough|sufficient) | adopting ... accepted | status (flip|move|change)
        | (approach|option|design|variant) [ab] | [ab] (or|vs) [ab]
PERM  : (may|can) (i|we) | is it (ok|okay|fine) to | ok to | go-ahead | approve | authori[sz]e | ack-destroy
```

`should I|we` is deliberately NOT in PERM (it would exempt "Should I use approach A or approach B", the exact ruling shape).
Verified: R1, R2, R3, R7 match CUE and not PERM (deny); R5, R6, R8, R9 allow; D1-D3 do not match CUE, so R10 falls through to the
investigation reason; A1-A5 match neither, so they are protected by cue absence and do not witness the exemption.

**Residual, stated where the contract is stated.** Appending a sentence such as "Approve the stricter threshold?" to a ruling
question exempts the whole question (R6 pins this on purpose): wrongly blocking an authorization is the worse failure the
header already names, so the arm evaluates the question, not the sentence. The ship gate and the skill text, not this arm, are the
primary defence.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the arm below the `AUTHORITY_RE` short-circuit | RED: R1 (carries "dispatched" and "deleted") flips deny to allow |
| 2 | Empty the cue regex (dispatch vacuity) | RED: the deny rows with DIFFERENT vocabulary (R1, R2, Z2, Z3) all read allow; the suite carries a floor of >= 4 deny rows that must hit this arm's reason |
| 3 | Put the cue in question 2 of a two-question payload whose question 1 is a compliant authorization | RED if the arm reads only the first question |
| 4 | Compute the exemption over the concatenation of all questions | RED: R4 (question 1 "Approve ...", question 2 a ruling) flips deny to allow |
| 5 | Widen the exemption to the full corpus (a button labelled "Approve") | RED: R7 flips deny to allow |
| 6 | Add bare `dispatch` to the exemption; separately bare `delete` | RED each: R1 flips via "dispatched"; a fixture carrying only "deleted" flips for `delete` (one fixture per verb, as D9(b) does) |
| 7 | Make the exemption empty | RED: Z1 ("May I raise the ceiling threshold to 5%?", cue AND permission shape) flips allow to deny; R5/R8 cannot witness this row because they carry no cue |
| 8 | Add `should (i\|we)` to the exemption | RED: Z2 ("Should I use approach A or approach B for the retry design?") flips deny to allow |

**Harness rows.** The existing A1-A5 authorization fixtures must stay green unmodified; they are protected by cue absence, so the
new must-PASS rows that actually witness the exemption are Z1 and "Approve raising the alert threshold to 5%?" (Z4), plus R5 and
R8 for cue-free authorizations. Deny rows must not share one vocabulary: R1 (strict/threshold), R2 (adopting/accepted), Z2
(approach A/B), Z3 ("Is the evidence sufficient to retire the guard?"). Suite edit that must red: flip one deny row's expectation.
The suite's inventory count (V1) and `MIN_CASES` rise by the number of new cases; Phase 1 updates both.

**Anchor.** Not applicable: the arm compares no stored value to a protected thing. V4 is a structural row defined like V3:
extract the exemption regex from the hook source, require >= 6 members (a non-vacuity floor), and assert none of the members is a
bare `delete`, `dispatch`, `deploy`, `merge`, `rotate`, `revoke`, `replace` or `destroy` alternative.

### Guard 3 — Wiring test (`components.test.ts`, "Technical-ruling delegation wiring")

**Property.** Every skill that can reach a technical fork or persists `decision-challenges.md` links the shared
reference, and the shipped pieces it names exist.

**Assembly.** Consumers are derived, not listed: every `skills/*/SKILL.md` whose text contains `soleur:engineering:cto`
must link the reference directly (at plan time that is plan, work, review and plan-review, so plan-review gains one
link; it has no byte ceiling), plus the explicit seven the brief names (go, one-shot, plan, work, review, ship, brainstorm).
The artifact's writers are a separate, explicit set: skills that append to `decision-challenges.md` (plan, plan-review, work,
ship) must link `decision-principles.md` (which carries the table schema and links the reference); a derived arm keyed on the bare
string `decision-challenges.md` was rejected because review, compound and archive-kb only mention it and have no reason to link. Also asserted: the reference exists; `ship/SKILL.md` has the `Technical-Ruling Gate`
heading and names the script; the script exists and is executable; `AGENTS.rules.md` rule body names
`soleur:engineering:cto`; and the one-shot inline rule (the one place the text is copied, because a Task subagent reads
prompt text only) contains `soleur:engineering:cto`, `Ruled by CTO agent` and the "surface it" override clause, so the copy
cannot drift from the reference's key tokens.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the link from `work/SKILL.md` | RED naming work |
| 2 | Add a new `skills/x/SKILL.md` that mentions `decision-challenges.md` without the link | RED (the derived arm, not the explicit list) |
| 3 | Make the glob over skills return zero files | RED: a floor of >= 7 consumers asserted |
| 4 | Rename the reference file | RED on existence and on every link |
| 5 | Delete the `Technical-Ruling Gate` heading from ship | RED |

**Harness rows.** A must-PASS skill that links via a different relative depth; a suite edit (empty the consumer list) that
must red on the floor of >= 7 consumers.

**Anchor.** Not applicable beyond Guard 1's parity case: the test reads the repository, not a stored value.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A definition of \"technical ruling vs operator decision\" in one canonical place (extend the existing rule body in AGENTS.rules.md and its index/tier entries" | Phase 6 rule amendment; reference §2-3; `decision-principles.md` | mapped |
| 2 | "A reusable delegation step in the shipped skills (one shared reference file, cited by the skills, not copy-pasted into each)" | Phase 2 `technical-ruling-delegation.md`; Phase 4 pointers | mapped |
| 3 | "Wire it into the skills where such forks arise (at least: go, one-shot, plan, work, review, ship, brainstorm, and the decision-challenge handling in one-shot/plan)" | Phase 4 byte-funding table (go, one-shot, plan Plan Review and Step 4.5, work, review, ship, brainstorm; one-shot also calls the gate); Phase 3 step 2.5; `plan-scope-check.md` row | mapped |
| 4 | "Make sure Soleur end users running these skills are never the ones asked the technical question" | reference §1 and §6; one-shot inline rule; ship gate | mapped |
| 5 | "Extend `.claude/hooks/pre-ask-technical-fork-gate.sh` (and its test file, test-first per cq-write-failing-tests-before)" | Phase 1(a), Phase 5, Guard 2 | mapped |
| 6 | "Decide, with evidence, whether prose-only surfacing can be caught mechanically" | Research H1/H5 + Cut List: artifact and PR-body form is deterministic (Guard 1); chat prose is not (R3) | mapped |
| 7 | "Update the PR-body / ship checklist so \"Owner decision needed: ...\" lines are only allowed for operator-class items" | Phase 3 gate and step 2.5 rewrite, Guard 1 | mapped |
| 8 | "Tests for every new gate, plugin component-count/description-budget parity (cq-skill-description-budget-headroom), and a compound learning" | Phase 1, Phase 7, Acceptance Criteria | mapped |
| 9 | "Keep the change minimal and reuse existing patterns; run the standard review." | Byte-funding rule, PIR-gate and wiring-block patterns; plan-review now, `soleur:review` at work | mapped |
| 10 | "Establish by reading the code why it was not caught" | Research Insights H1-H5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `AGENTS.rules.md`, hashes, ack | "extend the existing rule body in AGENTS.rules.md" | asked |
| `technical-ruling-delegation.md` | "one shared reference file, cited by the skills" | asked |
| `decision-principles.md` rewrite | asks 1 and 3 ("decision-challenge handling") | asked |
| go/one-shot/plan/work/review/ship/brainstorm pointers | "at least: go, one-shot, plan, work, review, ship, brainstorm" | asked |
| pre-ask hook arm + suite | "Extend `.claude/hooks/pre-ask-technical-fork-gate.sh`" | asked |
| `technical-ruling-gate.sh` + suite + fixtures | "a lint on skill text / PR-body templates for \"Owner decision needed\" without a \"Ruled by\" line" | asked |
| ship Technical-Ruling Gate section | "a technical one without a CTO ruling blocks ship" | asked |
| `components.test.ts` wiring block | "Tests for every new gate" | asked |
| compound learning | "and a compound learning" | asked |
| `ship/references/decision-challenges-render.md` | — | inferred — justification: ship/SKILL.md has a 0-byte headroom ceiling anchored to the merge base, so the step 2.5 body must move out for any addition to fit |
| `skill-body-budget.json` ceilings lowered | — | inferred — justification: the ratchet is one-sided; leaving a ceiling above the new size forfeits the guard's value, and lowering never reds |
| `## Decision Classes` table schema | — | inferred — justification: CTO ruling R4/R6; without a parseable field the gate cannot distinguish a technical decision from an operator one, and a table is the one shape every existing artifact format can carry |
| ADR-084 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the plan changes an existing ADR's routing contract |
| tracking issue and two deferral issues | — | inferred — justification: `wg-when-deferring-a-capability-create-a` and the brief's `Closes` instruction for an issue created for this work |
| `go` / `one-shot` inline three-line rule | — | inferred — justification: CTO ruling R6; Task subagents read prompt text only, so a link is not read |

### Split Assessment

- Subsystems touched: 4 — `.claude`, `AGENTS.rules.md`, `plugins/soleur`, `knowledge-base`
- Planned files: about 27 | Estimated changed lines: about 900 (reference ~150, gate script ~220, suite+fixtures ~260, hook arm+tests ~170, skill/ADR edits net negative)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split-ready. One PR with ordered commits: (1) carrier fix (reference, taxonomy, ship gate + step 2.5, skill pointers, rule + ADR); (2) the pre-ask hook arm and its suite last. If Phase 0 measures more than 800 changed lines or review needs a second round, commit 2 ships as its own PR (the CTO rated the hook secondary; the observed carrier was not a tool call), tracked by an issue cut at that point.

## Acceptance Criteria

### Functional Requirements

- [ ] AC1. `hr-technical-fork-is-not-an-operator-question` body names `soleur:engineering:cto`, the closed operator list and the "surface it" override; `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` exits 0 with the rule line <= 590 bytes and B_ALWAYS < 44000.
- [ ] AC2. `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exits 0 with one new ack line whose hash equals the new body and whose reason says "NOT a weakening - strictly additive"; the PR body names this ack as the single item needing the owner's CODEOWNERS review.
- [ ] AC3. `python3 scripts/lint-agents-enforcement-tags.py` and `python3 scripts/lint-rule-ids.py` exit 0 (the `[skill-enforced: ship Technical-Ruling Gate]` unit resolves).
- [ ] AC4. `technical-ruling-delegation.md` exists, is linked (markdown link, not backticks) from every consumer, contains the closed list, the delegation step, the recording format, the override clause and the Decision Classes table schema; the moved `work`/`review` text keeps its `Why` lines.
- [ ] AC5. `bash plugins/soleur/test/technical-ruling-gate.test.sh` passes, including all twelve Guard 1 mutation rows driven RED against a mutated copy of the script and a floor on SUT executions; `bash scripts/lint-orphan-test-suites.sh` reports the new suite as run (the `plugins/soleur/test/*.test.sh` glob is the registration; verify it, do not assume it); the suite places any owning EXIT trap before it sources `test-helpers.sh`.
- [ ] AC6. (Moves to the follow-up PR if the Scope Check split triggers.) `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh` passes with the new cases; the observed-question fixture (R1) is denied with a reason containing `soleur:engineering:cto` and `technical-ruling-delegation.md`; A1-A5 and every pre-existing case are unchanged and green.
- [ ] AC7. `bun test plugins/soleur/test/components.test.ts` is green, including the new wiring block and the unchanged "Skill description budget" test (`SKILL_DESCRIPTION_WORD_BUDGET` untouched).
- [ ] AC8. `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0 and no ceiling in `skill-body-budget.json` increased (`git diff` of the file shows only decreases).
- [ ] AC9. `ship/SKILL.md` Phase 6 step 2.5 files the `action-required` issue only for `operator` rows of the Decision Classes table; technical items render in a `### Ruled by CTO agent` sub-block of the existing `## Model Dissents (informational)` with the Ruled-by lines; no section name in the rendered body contains `Operator`, `Post-merge` or `Follow-up`.
- [ ] AC10. ADR-084 amended (Decision, Consequences, Alternatives); `bash scripts/check-adr-ordinals.sh` exits 0; `plugins/soleur/test/c4-count-parity.test.sh` is green.
- [ ] AC11. A compound learning exists under `knowledge-base/project/learnings/` naming the carrier-versus-hook finding (H5), the byte-ceiling constraint, and the self-classification risk.

### Non-Functional Requirements

- [ ] AC12. No file outside the Files to Edit / Create lists changes (`git diff --stat origin/main...HEAD`); no workflow dispatched, no terraform applied, no Doppler write, and no process is matched or killed by command-line pattern.
- [ ] AC13. The tracking issue and both deferral issues exist; the PR body carries `Closes #<tracking issue>` once, never in the title, and ends with the attribution line.

### Quality Gates

- [ ] AC14. The Observability `discoverability_test.command` was run once, locally, in Phase 7 and printed a line containing `[PASS]` in under 15 seconds; `npx markdownlint-cli2` is clean on the plan and `tasks.md`; `soleur:review` ran and its findings were fixed in-PR; `soleur:preflight` Check 10 executes the Observability `discoverability_test.command` and matches `[PASS]`.

## Test Scenarios

### Pre-ask hook (suite cases, written first)

| Id | Input (question; option text) | Expect |
|---|---|---|
| R1 | "How strict must the emptiness evidence be before the volume rebirth is dispatched and the plaintext volume deleted?" with options "Tighten the ceiling", "Keep the thresholds" | deny; reason names the CTO and the reference |
| R2 | "Should the ADR status move from adopting to accepted now that the grader passes?" | deny; the reason says a flip whose criterion the ADR states is mechanical (run the grader, cite it, flip) and otherwise the CTO rules |
| R3 | R1 plus a money word in an option description ("costs one more run") | deny (arm is ahead of the authority short-circuit) |
| R4 | Two questions: first "Approve the merge of PR 9628?", second R1's text | deny (each question is evaluated alone; the first question's "Approve" must not exempt the second); and the same payload with only the first question allows |
| R5 | "May I dispatch the rebirth now?" | allow |
| R6 | "How strict should the evidence bar be? Approve the stricter threshold?" | allow (the question carries a permission shape; this pins the stated residual that appending "Approve ...?" exempts the question) |
| R7 | R1 with an option labelled "Approve" and no permission shape in the question | deny (button label never exempts) |
| R8 | "Is it ok to go ahead and flip the flag?" and "What is the budget for the second host?" | allow, allow |
| R9 | "Which of the two logo designs should the landing page use?" (brand) | allow (a brand choice; the cue set names technical nouns only, so "design" alone never matches) |
| R10 | The 2026-08-19 investigation fixture D1 | deny, with the investigation reason (not the ruling reason) |
| Z1 | "May I raise the ceiling threshold to 5%?" (cue AND permission shape) | allow (witnesses the exemption; R5 and R8 carry no cue and cannot) |
| Z2 | "Should I use approach A or approach B for the retry design?" | deny (different vocabulary from R1; `should` is not an exemption) |
| Z3 | "Is the evidence sufficient to retire the guard?" | deny |
| Z4 | "Approve raising the alert threshold to 5%?" | allow |

### Ship gate script (suite cases)

Fixtures: `pass-mixed.md` (one technical item with Ruled-by and one operator item with a category), `no-class.md`,
`unruled-technical.md`, `pending-technical.md`, `bad-category.md`, `bad-ruling-shape.md`, `conforms-no.md`, `fenced-table-only.md`,
`owner-label-unscoped.md`, `empty-table.md`, `pr-body-label-bare.md`, `pr-body-label-fenced.md`, plus the four real free-form item shapes
copied from tracked artifacts; plus an absent-file case (`--branch` on a spec dir with no
artifact -> `[PASS] no decision-challenges artifact`, exit 0) and an unreadable-file case (exit 2).

### Integration verification (for `soleur:qa`)

Run `soleur:ship` Phase 5.5 against this branch's own `decision-challenges.md` (which carries a Decision Classes table): the
gate prints `[PASS]`, and the rendered PR body has a `### Ruled by CTO agent` sub-block with the plan-time rulings and no
`Owner decision needed` label outside an operator row.

## Risks and Sharp Edges

- **Self-classification at the writer** (CTO R6). The model that mislabels a decision can also write an `operator (scope)`
  row. Mitigations: closed category list, bare `operator` invalid, the burden-of-proof sentence at the choke point,
  and review reading the artifact. Residual: a determined mislabel with a plausible category passes. Accepted; the
  alternative (a classifier) was rejected as reward-hackable.
- **Byte ceilings** are the schedule risk: five files sit within 125 bytes of an un-raisable ceiling. Phase 0 measures
  net bytes per file before a single pointer lands; the fallback is the transitive link through `decision-principles.md`.
- **Over-firing hook arm.** The polarity is conservative by construction; the arm is secondary; every deny names the
  escape hatch. The V4 row pins that no bare action verb joins the exemption.
- **The moved `work` bullets are quoted by learnings and plans.** Citations point at the learning files, not the
  bullet text; Phase 0 greps for the anchors before the move and the reference keeps the same `Why` text.
- **Quoted phrases trip phrase-class hooks.** Commit messages and fixtures that contain "Owner decision needed" can be
  intercepted by command-detection hooks; write them via a file (`git commit -F`), per the 2026-05-29 learning. This
  planning run hit the same class: a heredoc quoting a forbidden process-matching flag was blocked by the bash guard.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one carries the threshold
  (`aggregate pattern`) with concrete artifact and vector lines.
- The stale `:574` and `:330` line-number pointers in `plan/SKILL.md` (found while researching) violate
  `cq-cite-content-anchor-not-line-number`; Phase 4 replaces them with content anchors in the paragraphs it already edits
  (this also funds plan's bytes).
- **P1 is enforced mechanically only for the artifact and PR-body surfaces.** At the writer it is a burden-of-proof rule plus
  a gate that checks the label's form (valid category, Ruled-by present), never its truth; the CODEOWNERS ack protects the rule
  body, not artifact labels. The end-user guarantee therefore rests on skill text plus the ship gate and is probabilistic, and
  the deferred plugin port of the pre-ask gate does not change that claim for subagents (they cannot ask). Behavioural
  coverage (a plan with a threshold fork must reach a CTO spawn, via `soleur:eval-harness`) is not built here; it is part of
  deferral 2's trigger (add it with the chat arm on the first recurrence).

## Plan Review (2026-10-11, headless; four seats)

Seats: DHH-lens, Kieran-lens, code-simplicity (per mechanism, against P1-P5 and the Scope Check), and a CTO devex-lens
advisory. Dispositions:

- **Applied (mechanical):** `ruling-pending` folded into `unruled-technical` (same check, same remedy); PR-body check moved
  to after the Phase 6 `gh pr edit` that writes the body, with exact insertion points named; ADR-084 amendment targets
  corrected to its real Decisions 1, 5 and 6; R2 reason text and R9 fixture corrected; Phase 0 now measures the exact blocks
  to move; "Phase 1.0" references renumbered to Phase 0; parity case widened to the rule body and a producer/consumer example
  case added; pointers carry their trigger inline; the one-shot inline copy is pinned by the wiring test; `plan` is funded by
  moving a real block; discoverability probe marked development-time.
- **Applied (taste, default taken):** mutation rows 8-9 reduced (rename-detection row cut, parity row kept and widened);
  the fenced-link harness row cut; reference sections merged from nine to seven; no new top-level PR-body headings (a
  `### Ruled by CTO agent` sub-block under the existing heading); one-shot inline copy shrunk to about 400 bytes; ceilings
  lowered only for work, review and ship.
- **Kept against a reviewer (already ruled or required):** the closed category list and bare-`operator` rejection (CTO R4);
  both deferral issues (CTO R3, R5); the telemetry line in the ship gate (the rule is `[skill-enforced]`); the derived-consumer
  arm of Guard 3 (the Guard Contract's "members drift" requirement).
- **User-Challenges, persisted not decided** (`decision-challenges.md` items 4 and 5): wiring in seven skills versus
  choke-point-only citation (three seats lean to the narrower form); making the hook arm its own PR by default (two seats).
  The owner's stated direction is the default; the split trigger in the Scope Check stays the fallback.

## Enhancement Summary (deepen-plan, 2026-10-11)

**Deepened on:** 2026-10-11. **Sections enhanced:** Guard Contract (1 and 2 rewritten), Technical Approach, Implementation Phases,
Files lists, Observability, Acceptance Criteria, Test Scenarios, Architecture Decision, Risks.
**Agents used:** `soleur:engineering:review:architecture-strategist`, `soleur:product:spec-flow-analyzer`,
`soleur:engineering:review:test-design-reviewer`, plus the halts below and a live-verification pass run by the planner.

**Halt gates (all pass after the edits recorded here):** 4.6 User-Brand Impact present, threshold `aggregate pattern`; 4.7
Observability present with five fields (the first draft's `discoverability_test.command` named a path under `plugins/soleur/test/`
and tripped the suite-shaped-command detector; repointed to this branch's own artifact, `probe-verb-gate.sh` exits 0); 4.8 no PAT
shapes; 4.9 no UI surface; 4.10 no new persistent store or connection (skipped); 4.11 `scripts/lint-guard-contract.py` green, three
guards, assemblies structural; 4.12 exactly one unfenced `## Scope Check`, no BLOCKED marker; 4.55 no downtime-inducing operation.

**Verified live in this pass:** rule ids cited are active or migrated (`wg-architecture-decision-is-a-plan-deliverable` is migrated,
active); issues 9628 MERGED, 9642 OPEN, 7462 CLOSED, 4133 and 8593 OPEN; every `knowledge-base/` path cited exists; B_ALWAYS 43166,
skill-body ceilings and `lint-skill-body-budget.py --base` green at plan time.

### Key improvements

1. **The gate parses one table, not free-form items.** Architecture review found four real item shapes in tracked artifacts
   (numbered entries, `DC-n` and `UC-n` headings, `Challenge n`, `Taste` sections) and one existing `**Class:**` field with a
   different vocabulary; a body scanner would have blocked most real artifacts at ship (mutation row 3 would fire on them). The
   contract is now a `## Decision Classes` table, shape-independent, with archive lookup so `archive-kb` cannot turn the gate into
   a silent pass.
2. **The remedy is bounded and the late-ruling hole is closed.** Spec-flow found an unbounded spawn loop, a ruling that could
   contradict code already built on an assumption, and a ruling arriving only at ship after work and review. Now: two spawns
   at most, a defined non-operator terminal state, a `conforms:` token, and one-shot resolves `pending` rows right after the plan
   phase.
3. **The hook arm evaluates per question** and its exemption no longer includes `should I|we`; deny fixtures use four distinct
   vocabularies; the exemption is witnessed by a cue-plus-permission row (the A1-A5 fixtures are protected by cue absence and
   cannot witness it).
4. **Funding and pin facts corrected:** an existing `components.test.ts` test pins three tokens in `ship/SKILL.md` (kept in the
   step 2.5 pointer); ship's edits land as one commit with the funding move; a new `plan/references/` file receives plan section
   2.6; `plan-scope-check.md` is a named writer.

### New considerations discovered

- Issue 9642 stays parked; its CTO ruling is being obtained separately (out of scope here). The SLA and digest consumers of the
  `decision-challenge` label (`action-required-sla-policy.ts`, `sla-issue-process.ts`, `operator-digest`) need no change: they key
  on the label, and operator rows keep it.
- A ruling or dissent that names data loss now produces an operator sibling row naming the ACTION; an operator-retained opt-in
  ("let me decide this one myself") is persisted as a User-Challenge for the owner (`decision-challenges.md` item 6), not built.
- The residual that "append `Approve ...?`" exempts a ruling question in the hook is stated where the hook's contract is stated.
