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
a closing-message arm, and the ship gate.

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
   session model may auto-decide, not who rules. `decision-challenges.md` items gain a mandatory `Class:` line.
4. **Ship gate** (`technical-ruling-gate.sh` + suite): reads the artifact and the PR body; blocks an item with no
   `Class:`, a `Class: technical` item with no `Ruled by` line, and any "Owner decision needed" label not carried by
   `Class: operator (<category>)`. Remedy text: spawn the CTO now, write the Ruled-by line, re-run. Step 2.5 files the
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
   Categories used verbatim by the `Class:` line: `money | scope | priority | schedule | irreversible |
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
6. **`decision-challenges.md` item schema:** `Class: technical` (must carry the Ruled-by line; a headless subagent that
   cannot spawn the CTO writes it without the line and ship's gate spawns the CTO) or `Class: operator (<category>)`.
   A bare `Class: operator` is invalid. The section ends with one canonical example item that the suite feeds to the
   gate (producer/consumer contract).
7. **The moved text:** the `work` CTO and CLO HARD GATE bullets and `review` step 4 are moved here (their `Why`
   lines and learning links preserved), generalised from "architecture fork" to "technical ruling".

### Files to Edit

- `AGENTS.rules.md` (rule body, tag), `.claude/rule-body-hashes.txt` (`python3 scripts/lint-rule-bodies.py --write`),
  `.claude/rule-weakening-acks.txt` (append one ack, reason "NOT a weakening - strictly additive ...")
- `.claude/hooks/pre-ask-technical-fork-gate.sh` and `.claude/hooks/pre-ask-technical-fork-gate.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` (§Precedence rewrite, `Class:` schema)
- `plugins/soleur/skills/go/SKILL.md`, `one-shot/SKILL.md`, `plan/SKILL.md`, `work/SKILL.md`, `review/SKILL.md`,
  `ship/SKILL.md`, `brainstorm/SKILL.md` (pointers; see byte-funding table)
- `plugins/soleur/test/components.test.ts` (new wiring block, modelled on "Decision-principles taxonomy wiring")
- `plugins/soleur/test/skill-body-budget.json` (ceilings for work, review, ship lowered to the new sizes; none raised)
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` (amend)
- `knowledge-base/project/learnings/2026-10-11-<slug>.md` (compound learning; slug chosen at compound time)

### Files to Create

- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`
- `plugins/soleur/skills/ship/references/decision-challenges-render.md` (moved step 2.5 body + the gate's remedy procedure)
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh`
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
the `work`/`review`/`ship` text about to move (no test pins were found at plan time for the CTO/CLO bullet text;
confirm).

**Phase 1 - RED.** Write, and watch fail, in this order: (a) hook cases R1-R9 (Test Scenarios) incl. the reason
assertions; (b) `technical-ruling-gate.test.sh` + fixtures against a script that does not exist yet; (c) the
components.test.ts wiring block; (d) a byte test for the rule line (`lint-agents-rule-budget.py` run).

**Phase 2 - Reference and taxonomy.** Create `technical-ruling-delegation.md`; rewrite `decision-principles.md`
§Precedence (technical rulings route to the CTO in both modes; NEVER-Mechanical classes decide auto-decide eligibility,
not who rules; add the `Class:` schema; link the new reference, which also satisfies the reachability test).

**Phase 3 - Ship gate.** Implement `technical-ruling-gate.sh` (modes: `<path>`, `--branch`, `--pr-body <file>`; exit
0 pass, 1 fail with `[FAIL] <path>:<item>: <reason> - <remedy>`, 2 usage/IO/unparseable, missing artifact = pass). Move
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

**Phase 4 - Skill pointers.** Apply the byte-funding table; `go`/`one-shot` get the inline three-line rule;
`work`/`review` have their bullets replaced by pointers. Re-run `python3 scripts/lint-skill-body-budget.py --base
$(git merge-base origin/main HEAD)` and lower the work, review and ship ceilings.

**Phase 5 - Hook arm.** Add the ruling arm after the expert arm and before `AUTHORITY_RE`; deny reason names
`soleur:engineering:cto` and `technical-ruling-delegation.md`, instructs "split the item; ask the operator only the
authorization"; escape hatch and carve-outs unchanged. Update the header contract paragraph (a second inversion of the
polarity, stated where the first one is).

**Phase 6 - Rule and ADR.** Amend the rule body; `--write`; append the ack; run the three rule lints. Amend ADR-084
(Decision 1: the precedence carve-out generalises to technical rulings; Decision 5: ship renders by `Class:`; Decision 6:
"one-shot inherits, not edited" is superseded for the subagent-prompt rule only; Consequences; Alternatives: "route everything consequential to the operator" rejected, "a Stop-hook label matcher"
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
and narrowly supersedes Decision 6 ("one-shot inherits, not edited"): this plan adds one short inline rule to one-shot's
subagent prompts because a Task subagent reads prompt text only, so a link alone is not read. New text: a decision whose
substance is technical judgment is a *technical ruling*, routed to the CTO agent (CLO for legal) in both modes and
recorded `Ruled by CTO agent`; it is never persisted to `decision-challenges.md` as an owner item. The
NEVER-Mechanical classes govern whether the session model may auto-decide, not who rules. `decision-challenges.md`
items carry a mandatory `Class:` line; `ship` renders and files by class. Alternatives Considered gains: "route every
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

The `discoverability_test` runs from a repository checkout (preflight Check 10 at ship), so the fixture path under
`plugins/soleur/test/fixtures/` is available; it is a development-time probe, not a customer-install one.

```yaml
liveness_signal:
  what: "technical-ruling-gate.sh prints a [PASS] or [FAIL] verdict line per item and the ship skill emits a SOLEUR_RULE_APPLIED rule=hr-technical-fork-is-not-an-operator-question line when the gate runs"
  cadence: "once per /soleur:ship run, at Phase 5.5"
  alert_target: "the rule-application telemetry aggregated weekly (rule-metrics), and the ship transcript"
  configured_in: "plugins/soleur/skills/ship/SKILL.md (Technical-Ruling Gate) and plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh"
error_reporting:
  destination: "stderr of the gate script, surfaced in the ship transcript; exit 1 blocks PR-ready"
  fail_loud: "yes: exit 1 on an unruled technical item, exit 2 on an unparseable artifact (never a silent pass); a missing artifact is the only exit-0 no-op and prints [PASS] no decision-challenges artifact"
failure_modes:
  - mode: "a technical item is labelled operator to evade the gate"
    detection: "the script rejects a bare Class: operator and any category outside the closed list; the suite pins both"
    alert_route: "[FAIL] line in the ship transcript"
  - mode: "the gate is skipped because the SKILL.md section is deleted or unlinked"
    detection: "components.test.ts wiring block asserts the ship section heading, the script path and the reference link"
    alert_route: "CI red on the PR that deletes it"
logs:
  where: "ship transcript; SOLEUR_RULE_APPLIED line"
  retention: "session transcript plus the weekly rule-metrics aggregate"
discoverability_test:
  command: "bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh plugins/soleur/test/fixtures/technical-ruling-gate/pass-mixed.md"
  expected_output: "[PASS]"
```

## Guard Contract

Three guards ship in this change: the ship gate script, the pre-ask hook arm, and the wiring test. Matrices are
derived from the design, written before the guards (Phase 1 builds them first).

### Guard 1 — Technical-ruling ship gate (`technical-ruling-gate.sh`)

**Property.** No PR reaches ready with a `decision-challenges.md` item or PR-body line that asks the operator a
technical question: every item has a valid `Class:`, every `Class: technical` item carries a `Ruled by` line, and the
"Owner decision needed" / "Owner ruling needed" label appears only on `Class: operator (<category>)` items.

**Assembly.** Two surfaces and one producer: (1) every item in the branch's `decision-challenges.md`, whichever `##`
heading it sits under (items are numbered-list entries opening with a number and a period; headings that carry the owner label bind every item beneath);
(2) every label occurrence in the PR body after fenced blocks are stripped (spellings: Owner decision(s) needed, Owner
ruling(s) needed, Decision needed from the owner, case-insensitive); (3) the producer, ship step 2.5, which must route
by `Class:` and file the issue for operator-class only. The chokepoint is the script, called at Phase 5.5 (artifact) and after
the Phase 6 `gh pr edit` (PR body, the body ship actually wrote); both call sites are named in
`decision-challenges-render.md` and pinned by the wiring test, and a suite case asserts the body arm reads a rendered body,
not a template.
The closed category list lives in the script and in the reference; a suite case reads both and compares the sets.
Scope is deliberately the BRANCH's own artifact (`--branch`) and a PR-body file; there is no `--corpus` mode: a plan-time
count found 172 tracked non-archived `decision-challenges.md` files, none carrying `Class:` lines, so a corpus sweep would
red on history. An in-flight branch that rebases onto this gate adds `Class:` lines to its own artifact at ship time (cheap,
and the remedy text says so).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `Class:` line from item 2 of a fixture whose item 1 is compliant (a check that stops at the first item is the defect) | RED, reason `no-class`, names item 2 |
| 2 | Strip the `Ruled by CTO agent` line from a `Class: technical` item | RED, reason `unruled-technical`, remedy text names the CTO spawn |
| 3 | Replace the item scanner with one that finds zero items (dispatch vacuity) against a fixture of five items | RED: the script reports "0 items examined" as exit 2, never exit 0 |
| 4 | Write `Class: operator` with no category, then with `(vibes)` | RED, reason `bad-category`, both spellings |
| 5 | Put the label `## Owner decision needed` over a heading holding a `Class: technical` item | RED, reason `technical-labelled-owner` |
| 6 | PR body line `Owner ruling needed: ...` without `(operator: <category>)`; same line inside a fenced block | RED for the first, PASS for the fenced one |
| 7 | Remove one category from the script's list while the reference keeps it, and separately drop the word `brand` from the rule body | RED in the parity case (script vs reference by token; rule body by the root words money, scope, priorit, schedul, irreversible, production, legal, brand) |
| 8 | Feed the reference's canonical example item to the gate, then break its `Class:` spelling in the reference only | RED: producer/consumer contract |

**Harness rows.** Edit the suite's `run_case` to swallow the SUT's exit code -> the suite must red on its own floor
(a SUT-written execution marker count, as `unkept-promise-hook.test.sh` does). Must-PASS inputs that are not the
canonical fixture: an operator item with category `legal-risk`; an item whose `Class:` line is indented and bulleted
(a bulleted, indented `Class: operator (money)` line); a `Class: technical` item whose Ruled-by line is on the following line; an artifact
absent entirely.

**Anchor.** The stored value is the category list; what must also move for a weakening to pass is the reference file
(parity case) and a component-wiring assertion that names the script; a one-diff edit to the script alone reddens the
parity case, and an edit to both is visible in review as a change to the closed operator list, which is the thing the
CTO ruled must stay closed.

### Guard 2 — Technical-ruling arm in the pre-ask hook

**Property.** A technical-ruling AskUserQuestion is denied with a reason naming `soleur:engineering:cto`, and an
authorization question is never denied by this arm.

**Assembly.** The arm quantifies over the whole flattened corpus (every question and every option label and
description, all questions in the array) for the cue, and over the QUESTION text only for the exemption; it sits after
the expert arm and ahead of `AUTHORITY_RE`, so it must be evaluated on every input that reaches that point. Other arms
that can pre-empt it: the self-invocation allow and the expert arm (unchanged). The fail-open paths (jq missing, corpus
rc != 0) are unchanged and remain permit.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the arm below the `AUTHORITY_RE` short-circuit | RED: the observed-question fixture (carries "dispatched" and "deleted") flips deny to allow |
| 2 | Empty the cue regex (dispatch vacuity) | RED: every deny row reads allow; the suite has a floor of >= 4 deny rows that must hit this arm's reason |
| 3 | Put the cue in question 2 of a two-question payload whose question 1 is a compliant authorization | RED if the arm reads only the first question |
| 4 | Widen the exemption to the full corpus (a button labelled "Approve") | RED: the relabel-bypass fixture flips deny to allow |
| 5 | Add bare `delete|dispatch|deploy|merge` to the exemption | RED: the observed question flips to allow (the CTO's R2 flaw, pinned) |
| 6 | Make the exemption empty | RED: "May I dispatch the rebirth now?" and "Approve the stricter threshold?" flip allow to deny |

**Harness rows.** The existing A1-A5 authorization fixtures must stay green unmodified (they are the must-PASS set not
written for this arm); add two new must-PASS rows with different wording from any A-row ("Is it ok to go ahead and
flip the flag?", "What is the budget for the second host?"). Suite edit that must red: flip one new deny row's
expectation and require the suite to fail.

**Anchor.** Not applicable: the arm compares no stored value to a protected thing; its only stored data is a regex
literal, and the V3 subset assertion between `AUTHZ_VERB_RE` and `AUTHORITY_RE` is untouched. A new structural row (V4)
asserts the ruling arm's exemption regex shares no token with the bare-verb set the CTO ruled out.

### Guard 3 — Wiring test (`components.test.ts`, "Technical-ruling delegation wiring")

**Property.** Every skill that can reach a technical fork or persists `decision-challenges.md` links the shared
reference, and the shipped pieces it names exist.

**Assembly.** Consumers are derived, not listed: every `skills/*/SKILL.md` whose text contains `decision-challenges.md`
or `soleur:engineering:cto` must link the reference, plus the explicit seven the brief names (go, one-shot, plan, work,
review, ship, brainstorm). Also asserted: the reference exists; `ship/SKILL.md` has the `Technical-Ruling Gate`
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
| 3 | "Wire it into the skills where such forks arise (at least: go, one-shot, plan, work, review, ship, brainstorm, and the decision-challenge handling in one-shot/plan)" | Phase 4 byte-funding table; Phase 3 step 2.5 | mapped |
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
| `Class:` item schema | — | inferred — justification: CTO ruling R4/R6; without a parseable field the gate cannot distinguish a technical item from an operator one |
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
- [ ] AC4. `technical-ruling-delegation.md` exists, is linked (markdown link, not backticks) from every consumer, contains the closed list, the delegation step, the recording format, the override clause and the `Class:` schema; the moved `work`/`review` text keeps its `Why` lines.
- [ ] AC5. `bash plugins/soleur/test/technical-ruling-gate.test.sh` passes, including all eight Guard 1 mutation rows driven RED against a mutated copy of the script and a floor on SUT executions; `bash scripts/lint-orphan-test-suites.sh` reports the new suite as run (the `plugins/soleur/test/*.test.sh` glob is the registration; verify it, do not assume it); the suite places any owning EXIT trap before it sources `test-helpers.sh`.
- [ ] AC6. `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh` passes with the new cases; the observed-question fixture (R1) is denied with a reason containing `soleur:engineering:cto` and `technical-ruling-delegation.md`; A1-A5 and every pre-existing case are unchanged and green.
- [ ] AC7. `bun test plugins/soleur/test/components.test.ts` is green, including the new wiring block and the unchanged "Skill description budget" test (`SKILL_DESCRIPTION_WORD_BUDGET` untouched).
- [ ] AC8. `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0 and no ceiling in `skill-body-budget.json` increased (`git diff` of the file shows only decreases).
- [ ] AC9. `ship/SKILL.md` Phase 6 step 2.5 files the `action-required` issue only for `Class: operator` items; technical items render in a `### Ruled by CTO agent` sub-block of the existing `## Model Dissents (informational)` with the Ruled-by lines; no section name in the rendered body contains `Operator`, `Post-merge` or `Follow-up`.
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
| R4 | Two questions: first "Approve the merge of PR 9628?", second R1's text | deny on the second; and the same payload with only the first question allows |
| R5 | "May I dispatch the rebirth now?" | allow |
| R6 | "How strict should the evidence bar be? Approve the stricter threshold?" | allow (permission-shaped, exempt) |
| R7 | R1 with an option labelled "Approve" and no permission shape in the question | deny (button label never exempts) |
| R8 | "Is it ok to go ahead and flip the flag?" and "What is the budget for the second host?" | allow, allow |
| R9 | "Which of the two logo designs should the landing page use?" (brand) | allow (a brand choice; the cue set names technical nouns only, so "design" alone never matches) |
| R10 | The 2026-08-19 investigation fixture D1 | deny, with the investigation reason (not the ruling reason) |

### Ship gate script (suite cases)

Fixtures: `pass-mixed.md` (one technical item with Ruled-by and one operator item with a category), `no-class.md`,
`unruled-technical.md`, `bad-category.md`, `owner-label-over-technical.md`, `empty-items.md`,
`pr-body-label-bare.md`, `pr-body-label-fenced.md`; plus an absent-file case (`--branch` on a spec dir with no
artifact -> `[PASS] no decision-challenges artifact`, exit 0) and an unreadable-file case (exit 2).

### Integration verification (for `soleur:qa`)

Run `soleur:ship` Phase 5.5 against this branch's own `decision-challenges.md` (which carries `Class:` lines): the
gate prints `[PASS]`, and the rendered PR body has a `### Ruled by CTO agent` sub-block with the plan-time rulings and no
`Owner decision needed` label outside an operator-class item.

## Risks and Sharp Edges

- **Self-classification at the writer** (CTO R6). The model that mislabels an item can also write `Class: operator
  (scope)`. Mitigations: closed category list, bare `operator` invalid, the burden-of-proof sentence at the choke point,
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
