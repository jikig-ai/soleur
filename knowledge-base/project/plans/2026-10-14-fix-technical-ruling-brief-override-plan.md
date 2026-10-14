---
title: "fix: a brief's 'ask the operator' wording on a technical fork triggers the CTO"
date: 2026-10-14
slug: technical-ruling-brief-override
branch: feat-one-shot-technical-ruling-brief-override
issue: 9217
type: fix
lane: cross-domain
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-14
**Sections enhanced:** Research Insights (deepen findings), Risks and Sharp Edges
**Research and verification used:** the real hook driven in a scratch copy (fixture verdicts, 30 KB input timing); the deepen halt gates 4.6, 4.8, 4.11 and 4.12 run mechanically; rule-id, issue and path citation sweeps; the CTO agent (two rulings) and a four-seat plan review (DHH, Kieran, simplicity, CTO devex) already folded in.

### Key Improvements

1. The final cue design was re-measured end to end after plan review (inside the weak block on `$asked`, no ownership arm, no money conjunct) before it was written down.
2. A linear-time check on the new regexes with a 30 KB question (0.2 s) closes the "regex over model-controlled text" concern.
3. Every cited rule id, issue and path was checked live.

### New Considerations Discovered

- The two-sentence split ("Run these as a new pipeline now. Or record them as not fixed?") misses the cue because the halves land in different sentences; stated as residual in the hook header.

## Overview

A resume brief told the agent to ask the operator once and then act on a scope and ownership question about
roadmap items, offered as "(a) run as new pipeline or (b) record not fixed". The agent put it to the operator
through the question tool, although the hard rule on technical forks and the routing skill's sharp edge both
forbid that. The operator's answer was: "ask the CTO not me and improve the workflow and skills to ensure this
is the case in the future for such technical questions".

The failure carrier is the brief's own wording. Two earlier carriers (an artifact pipeline on 2026-10-11, the
closing message on 2026-10-12) each needed their own enforcer; this one has none, because a hook cannot read
a brief and the skill text only covers a brief that says "surface it, do not decide it". The plan closes it in
four layers:

1. **The hook** denies the disposition shape "run as a new pipeline" together with "record as not fixed"
   (measured: all synthesized variants of the incident question were ALLOWED by the current hook; three of the
   five are DENIED after the change and the rest are an accepted, stated residual).
2. **The delegation reference** (canonical home of the rule) states that a brief's "ask the operator" /
   "OPEN DECISION" wording on a technical fork is the trigger to spawn the CTO, and classifies the
   scope-worded disposition shape as technical.
3. **The routing skill and the one-shot inline copy** carry the same trigger where a brief is read.
4. **A learning** records the carrier and the prevention rule.

## Technical Rulings

Premise: the operator named this shape technical in their own words, so no item below was put to them. All were
ruled by the CTO agent in this planning run (headless, binding), including the follow-up after plan review.

- **H1 (hook).** Ruled by CTO agent, 2026-10-14: add a narrow deny cue for the "disposition of items the brief
  already named" shape, defined in the shared lib as a NEW group `shared+ask` (never in `shared`, which the closing
  hook also judges), constants named `TFC_ASK_*` (suite row L2 forbids a `RULING_*_RE=` definition outside the lib).
  The cue never reads the word `scope`. Rejected: skill text only, an inline hook arm, widening `shared`, removing
  `scope` from `AUTHORITY_RE`. Dissent: the cue is lexical, so a paraphrase slips through.
- **H1b (the OWN arm).** Ruled by CTO agent, 2026-10-14 (after three reviewers measured a false deny): cut
  `TFC_ASK_OWN_RE` entirely; the cue is `ROUTE` AND `RECORD` only. Variants that rely on ownership wording alone
  ("Who owns the remaining roadmap items?", "Which of the two roadmap items does this PR own?") become the stated
  residual, covered by skill text. Dissent: a ledger sample showing PR-ownership phrasing as the dominant carrier
  flips this; then add only the artifact-subject alternative, never the person-shaped `who owns`.
- **H1c (structure).** Ruled by CTO agent, 2026-10-14: the check lives inside the lib's existing weak-cue block on
  `$asked` (the last sentence of each interrogative segment, already gated on `?` and the operator-vocabulary
  veto), guarded by `ask -eq 1`, placed after the `ab` cue and before the permission exemption; the
  `RULING_MONEY_RE` conjunct is dropped (the operator-vocabulary veto already holds the money words that matter).
- **H2 (skill text).** Ruled by CTO agent, 2026-10-14: edit the Sharp Edge in `plugins/soleur/commands/go.md` (the
  authority) and add one pointer sentence to `plugins/soleur/skills/go/SKILL.md` (a harness shim); extend section 5
  of the reference; add the classification rule to section 1 next to the `scope` bullet; add a worked-table row to
  section 7. Rejected: leaving the shape unclassified, reclassifying all scope questions as technical.
- **H3 (learning).** Ruled by CTO agent, 2026-10-14: the Key Insight is that the brief wording is the carrier (the
  third after the artifact pipeline and the closing message) and the hook cannot see a brief; one Prevention rule.

The classification rule the reference carries (verbatim from H2): "A scope question is the operator's only when it
asks to DROP, DEFER or ADD something the operator themselves asked for; routing or ownership of an
already-identified gap that the brief named (run leftover items as a new pipeline vs record them as not fixed, who
owns them) is technical and goes to the CTO."

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference: `#9217` (the operator directs `Ref #9217` only, never
`Closes`; it is OPEN with an unrelated pipefail-sweep title, consistent with a `Ref`-only link, not re-scoped). The
hooks, lib, reference and skills named in the brief exist on this branch. The claim that the hook may not deny the
incident shape was MEASURED: five synthesized variants through the real hook all returned allow. Mechanism vs ADR
corpus: ADR-084's 2026-10-12 addendum rejected "one flat cue list that also widens the pre-ask hook"; this plan
does not revive it, it adds a separate group so `shared` stays byte-identical, and corrects the addendum's
sentence "The pre-ask hook calls the same function with group `shared`, so its behaviour is unchanged", which this
change falsifies.

**Property List (Phase 0.6b).**

- P1. An `AskUserQuestion` that asks to run items the brief named as a new pipeline or record them as not fixed is
  denied with a reason whose first imperative is to spawn `soleur:engineering:cto`.
- P2. A genuine operator ask (drop, defer or add something the operator asked for; money; schedule; a
  permission-shaped authorization; an assignment ask) is not denied by the new cue.
- P3. The Stop closing hook and the `shared` group are behaviourally unchanged.
- P4. A reader of the reference, the routing skill or the one-shot inline copy learns that a brief's "ask the
  operator" / "OPEN DECISION" wording on a technical fork is the CTO trigger, with the closed list unchanged.
- P5. The next occurrence is findable: a learning records the carrier, the detector and the residual.

**Cut List (Phase 0.6b).**

- A new enforcer script or gate for briefs -> P1/P4 -> a hook cannot read a brief; the reference already carries
  the override clause. Cut.
- A new hard rule or an AGENTS*.md edit -> P4 -> forbidden by the brief; the rule exists. Cut.
- Editing `work/SKILL.md`, `plan/SKILL.md` -> P4 -> forbidden; they already link the reference.
- An ownership-only cue (`TFC_ASK_OWN_RE`) -> P1 -> measured false deny of an assignment ask; cut by H1b.
- A money conjunct on the new cue -> P2 -> already covered by the operator-vocabulary veto; cut by H1c.
- A cue for "Is the scope of this fix limited to item 1, or does it include items 3 and 4?" -> P1 -> textually
  identical to a real scope ask; residual, skill text only.
- Executable mutants for every matrix row, and a four-file content pin -> reviewers cut them as restating the
  fixtures; only the mutants that need the closing suite's tree machinery are committed (see Guard Contract).
- A bump of `plugins/soleur/test/skill-body-budget.json` -> none needed: `go` is not a row and `one-shot` has 1235
  bytes of headroom for a ~90-byte edit.

**Relevant learnings (Glob-verified).**
`knowledge-base/project/learnings/2026-10-12-the-closing-message-was-the-third-carrier-the-rule-had-no-reader-for.md`
(shared lib, group argument, miss-cue-fixture loop),
`knowledge-base/project/learnings/2026-10-11-the-rule-existed-and-the-carrier-was-an-artifact-pipeline-the-hook-never-saw.md`
(find the carrier before strengthening the enforcer), and
`knowledge-base/project/learnings/workflow-patterns/2026-06-15-architectural-fork-decisions-route-to-cto-not-operator.md`.

**Measurements the plan stands on (scratch copy of `.claude/hooks`, never the tree).** With the final design
patched in (cue inside the weak block on `$asked`, group `shared+ask`, no OWN, no MONEY): the five incident
variants split 3 deny / 2 allow (the two allows are the stated residual); every near-miss in the fixture list
allows, including "Who should own the remaining items, Alice or Bob?"; the pre-ask suite stays 145/145; in the
closing suite the G2-2 row FAILS (the hook now asks for `shared+ask`, so its mutant on the `shared)` line no
longer widens it) and V6 reports 23 killed against its floor of 24. P1/C1/C3 failures in the scratch run were
layout artifacts of running outside the repo tree; the unmodified baseline in-tree is 130/130.

**Deepen findings (2026-10-14).**

- Halt gates: 4.6 User-Brand Impact present with a valid threshold (`none`, and no sensitive path: `.claude/hooks/**` and `plugins/**` do not match `SENSITIVE_PATH_RE`); 4.7 not applicable (the Phase 2.9 code-class path set is not touched; stated in Domain Review); 4.8 no PAT-shaped variable; 4.9 and 4.10 not triggered; 4.11 `lint-guard-contract.py` passes with one entry; 4.12 exactly one unfenced `## Scope Check`, no `status: BLOCKED`.
- Citation sweeps: rule ids `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only` are active in `AGENTS.md`; `wg-architecture-decision-is-a-plan-deliverable` is a migrated-but-active id (`scripts/migrated-rule-ids.txt`), canonical home `plan` Phase 2.10. `#9217` and `#8593` are OPEN; the closing-hook work is merged as #10104 and the delegation reference as #10049 (`git log --grep`).
- Linear-time check: the final lib patched into a scratch copy, a 30 KB question made of the routing and record phrases returned in about 0.2 s (the regexes use bounded gaps and no nested quantifier).
- Verify-the-negative: the plan's negative claims were checked against the code. "The cue is unreachable from the closing hook" holds (`shared+closing` never sets `ask`; mutant row 3 pins it). "`scope` stays in `AUTHORITY_RE`" holds (the plan does not edit that line). "The permission exemption runs after every cue" holds (`tfc_is_fork` evaluates it after the hit is set).
- `go-routing` block projection hash measured equal on the unedited tree, so AC5's compare is a real before/after check.

**Code-review overlap (Phase 1.7.5).** #8593 mentions `plugins/soleur/test/components.test.ts` in passing.
Disposition: **Acknowledge** (a different concern, a preflight probe gate; needs its own cycle).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "soleur:go (plugins/soleur/skills/go/SKILL.md, outside the eval-gated go-routing block) and the brainstorm-techniques reference technical-ruling-delegation.md must state that a brief's \"ask the operator\" / \"OPEN DECISION\" wording on a technical fork is itself the trigger to spawn the CTO (legal: CLO) and record \"Ruled by CTO agent\", with the closed operator-only list unchanged" [brief] | Phase 3 (reference sections 1, 5, 7; `commands/go.md` Sharp Edge; `skills/go/SKILL.md` pointer) | mapped |
| 2 | "check whether .claude/hooks/pre-ask-technical-fork-gate.sh denies this AskUserQuestion shape (scope/ownership of roadmap items, \"(a) run as new pipeline or (b) record not fixed\") and extend it plus its test if it does not" [brief] | Phase 1 (RED rows) + Phase 2 (lib group, hook call, reason) | mapped |
| 3 | "add a learning" [brief] | Phase 4 (learning file) | mapped |
| 4 | "Do NOT edit AGENTS*.md, plugins/soleur/skills/work/SKILL.md, plugins/soleur/skills/plan/SKILL.md, scripts/test-all.sh, scripts/lib/test-affected-paths.sh, scripts/lib/scratch-root.sh, plugins/soleur/test/skill-body-budget.json, or any .github workflow" [brief] | Files to Edit excludes every named path (AC9) | mapped |
| 5 | "PR body: Ref #9217 only, never Closes; labels semver:patch and app:web-platform; commits end with Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>; PR body ends with the Claude Code generated-with line" [brief] | Quality Gates (ship-time) | mapped |
| 6 | "Filing issues about Soleur's own guards needs the meta/machinery label. Merging needs review evidence via emit-review-trailer.sh --findings <n> as its own command, then push, then gh pr merge." [brief] | Quality Gates (ship-time) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.claude/hooks/lib/technical-fork-cues.sh` (group `shared+ask`, `TFC_ASK_*`) | "extend it plus its test if it does not" | asked (ask 2) |
| `.claude/hooks/pre-ask-technical-fork-gate.sh` (call, reason lead, header comments) | "extend it plus its test if it does not" | asked (ask 2) |
| `.claude/hooks/pre-ask-technical-fork-gate.test.sh` | "extend it plus its test if it does not" | asked (ask 2) |
| `.claude/hooks/pre-closing-technical-fork-gate.test.sh` (retarget G2-2, three committed mutants, one allow row) | — | inferred — justification: G2-2 targets the `shared)` case line and goes red the moment the pre-ask hook asks for another group (measured); the mutants need that suite's `mk_tree` machinery, the pre-ask suite has none |
| `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` | "the brainstorm-techniques reference technical-ruling-delegation.md must state that a brief's" | asked (ask 1) |
| `plugins/soleur/commands/go.md` Sharp Edge | "soleur:go (plugins/soleur/skills/go/SKILL.md, outside the eval-gated go-routing block)" | inferred — justification: `skills/go/SKILL.md` is a thin harness shim whose own text names `commands/go.md` as "the AUTHORITY"; the existing Sharp Edge lives in `commands/go.md`, and `components.test.ts` wires `go` through that file; editing only the shim would leave the authority contradicting it |
| `plugins/soleur/skills/go/SKILL.md` pointer sentence | "soleur:go (plugins/soleur/skills/go/SKILL.md, outside the eval-gated go-routing block)" | asked (ask 1) |
| `plugins/soleur/skills/one-shot/SKILL.md` inline copy (one clause) | — | inferred — justification: the inline copy is the only part of the rule a headless Task subagent receives (`components.test.ts` "one-shot inline copy") and it says only "surface it, do not decide it"; ~90 bytes against 1235 bytes of headroom, no ceiling edit |
| `plugins/soleur/test/components.test.ts` (three content anchors) | — | inferred — justification: without a pin the next prose edit silently drops the trigger sentence; the file already pins the sibling sentences |
| `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` (corrected sentence plus short addendum) | — | inferred — justification: the 2026-10-12 addendum says the pre-ask hook "calls the same function with group `shared`, so its behaviour is unchanged"; this change falsifies it, and `wg-architecture-decision-is-a-plan-deliverable` makes the correction part of this PR |
| learning file under `knowledge-base/project/learnings/workflow-patterns/` | "add a learning" | asked (ask 3) |
| `knowledge-base/project/specs/feat-one-shot-technical-ruling-brief-override/decision-challenges.md` + `tasks.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | asked (inline rulings block of the brief) |

### Split Assessment

- Subsystems touched: 3 — `.claude` (hooks), `plugins/soleur`, `knowledge-base`
- Planned files: 12 | Estimated changed lines: ~250 (suite rows ~100, lib ~12, hook ~20, reference ~20, skills ~8, test ~10, ADR ~10, learning ~40; plan artifacts excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `.claude/hooks/lib/technical-fork-cues.sh` — `shared+ask) ask=1 ;;` in the group `case` (leave `shared) ;;` untouched), `ask=0` in the `local` line, two `TFC_ASK_*` regexes, the one-line ask check in the weak block; update the header (line 4 caller list, the contract line "`<groups>` is `shared` or `shared+closing`", and the sentence "the pre-ask hook is NOT widened (group `shared` only)").
- `.claude/hooks/pre-ask-technical-fork-gate.sh` — the call becomes `tfc_is_fork "$__rq" shared+ask`; the ask-specific reason lead; header comments (the "asks for group `shared` only" paragraph and the second-carve-out list; state the residual and that the recall is fitted to synthesized phrasing).
- `.claude/hooks/pre-ask-technical-fork-gate.test.sh` — new rows, the NR1 comment ("pre-ask hook is NOT widened") corrected, V1 literal (3 sites: the `TOTAL -eq` check, its echo and `MIN_CASES`), V5 row list and floor.
- `.claude/hooks/pre-closing-technical-fork-gate.test.sh` — G2-2 retargeted, three committed mutants, one allow row, its header table at line 32 corrected, V6 floor, V1 literal (3 sites).
- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` — sections 1, 5, 7.
- `plugins/soleur/commands/go.md` — the first Sharp Edge bullet only (outside `eval-gate:block:go-routing`).
- `plugins/soleur/skills/go/SKILL.md` — one sentence with a markdown link to the reference (the `components.test.ts` consumer census adds any skill whose text names `soleur:engineering:cto`).
- `plugins/soleur/skills/one-shot/SKILL.md` — one clause in the inline `TECHNICAL RULINGS` copy.
- `plugins/soleur/test/components.test.ts` — three content anchors and one token in the existing inline-copy list.
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` — corrected sentence and a short dated addendum.

## Files to Create

- `knowledge-base/project/learnings/workflow-patterns/2026-10-14-<topic>.md` — the learning (directory and topic fixed here; the date prefix is the work-session date).
- `knowledge-base/project/specs/feat-one-shot-technical-ruling-brief-override/decision-challenges.md` and `tasks.md`.

## Open Code-Review Overlap

#8593 (`plugins/soleur/test/components.test.ts` named in passing). **Acknowledge** — different concern, needs its own cycle.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-084** (no new ADR; an extension of its 2026-10-12 cue-arm decision), via `soleur:architecture`:
(1) correct the sentence "The pre-ask hook calls the same function with group `shared`, so its behaviour is
unchanged while the lib is present" to name `shared+ask`, with `shared` unchanged; (2) add a short
`## Addendum — 2026-10-14` recording the carrier (the brief wording), the CTO rulings H1 to H1c, the residual
(ownership-only and scope-limited phrasings), and a budget for the new family: more than 3 `TFC_ASK_*` patterns, or
a second paraphrase miss, means stop widening and revisit (the existing tripwire counts CLOSING cues only, so this
family would otherwise escape it). A task in Phase 4, not a follow-up issue.

### C4 views

No C4 impact. Read all three model files (`model.c4` 962 lines, `views.c4` 129, `spec.c4` 54). Checked and found
already modeled: (a) external human actors — only `founder`, no new correspondent; (b) external systems — none added
(the hook is repo-local, no network call); (c) containers and stores — the `hooks` container ("Hook Engine",
`model.c4` line 160) already says the repo-local Stop gate "shares `lib/technical-fork-cues.sh` with the pre-ask
gate", which stays true; (d) actor-to-surface access relationships — unchanged. `bash
plugins/soleur/test/c4-count-parity.test.sh` was run on this branch and passed (Failed: 0); no derived cardinality moves.

### Sequencing

The ADR text describes the final state and ships in this PR.

## Guard Contract

### Guard 1 — the `ask` cue of the pre-ask technical-fork gate

**Property.** An `AskUserQuestion` whose question text proposes running named items as a new pipeline AND recording
them as not fixed is denied with the CTO-first reason, while every genuine operator ask (drop, defer or add something
the operator asked for; schedule; a permission-shaped authorization; an assignment ask) is allowed, and the Stop
closing hook and the `shared` group are unchanged.

**Assembly.** The chokepoint is `tfc_is_fork` in `.claude/hooks/lib/technical-fork-cues.sh`, reached by exactly two
callers: `pre-ask-technical-fork-gate.sh` (the only one asking for `shared+ask`) and
`pre-closing-technical-fork-gate.sh` (`shared+closing`). The members the property quantifies over: the two
`TFC_ASK_*` regexes, the weak-block gates they inherit (a `?` in the unit and no `RULING_OPVOCAB_RE` hit, both
read over the unit), the sentence extraction (`$asked`), the permission exemption (`RULING_PERM_RE`, evaluated after
every cue), the per-question loop in the hook (each question judged alone, question text only, never an option
label), the group `case`, and the deny reason. The AUTHORITY arm that follows the ruling arm is NOT a member:
`scope` stays in `AUTHORITY_RE` on purpose. There are two carriers (AskUserQuestion and the closing message); the
cue is deliberately reachable from the first only, and a committed mutant pins that.

**Mutation matrix:**

| # | Mutation | Expected | Committed? |
|---|---|---|---|
| 1 | In the lib, `shared+ask) ask=1 ;;` becomes `shared+ask) ;;` (the group is ignored) | RED: AK3 reads allow | yes (closing suite tree) |
| 2 | In the hook, `tfc_is_fork "$__rq" shared+ask` becomes `shared` (the arm's own dispatch is dead; it would report "0 checked" and allow everything) | RED: AK3 reads allow | yes |
| 3 | A SECOND member after a compliant first: the lib gets `shared+closing) closing=1; ask=1 ;;` (the Stop carrier widened) | RED: the closing allow row (AK3 text, which carries no closing-extra veto word) flips to block | yes |
| 4 | Retarget of the existing G2-2: `shared+ask) ask=1 ;;` becomes `shared+ask) ask=1; closing=1 ;;` | RED on the pre-ask row NR2a (a closing-only phrasing must stay allow) | yes (retarget, not a net new mutant) |
| 5 | Remove the `RULING_OPVOCAB_RE` veto from the weak block | RED: AL8 (the `launch` near-miss) flips to deny | run once by hand in Phase 5 |
| 6 | Change the `ROUTE and RECORD` conjunction to `ROUTE or RECORD` | RED: AL5 and AL6 (one half only) flip to deny | by hand |
| 7 | Make the permission exemption skip an `ask` hit | RED: AL7 flips to deny | by hand |

**Harness rows.** (i) A suite edit that must go RED: change the V1 literal without `MIN_CASES` (or the reverse); the
accounting floor fires. (ii) A must-PASS input that is not one of the canonical phrasings and differs in a way the
contract permits: AK5, lowercased and differently punctuated, must DENY; AL7, a permission-shaped near-miss with
both halves present, must ALLOW. A stub that denies everything fails the allow rows; one that allows everything
fails the deny rows. (iii) A reason row: AK1's decision AND its reason both contain the ask lead ("items the brief
already named"), so dropping the `TFC_HIT == ask` branch cannot hide behind the generic ruling reason.

**Anchor.** The stored values are the V1 inventory literal and `MIN_CASES`, which one diff can edit together with the
rows they count. What outside the commit must also move for a weakening to pass: `scripts/guard-vacuity-floor.test.sh`
builds its own mutants for any suite whose floor has the recognised `(( TOTAL < MIN_CASES ))` shape, so that shape
must be kept; set identity (not a count) is carried by V5's named witness list.

## Implementation Phases

### Phase 1 — RED first (`cq-write-failing-tests-before`)

1.1. In `.claude/hooks/pre-ask-technical-fork-gate.test.sh`, in the ruling-arm block (near the `qobj` builders), add
rows with `run_ruling "<name> ..." deny ruling "$(qobj "<q>" | mq_payload)"` (deny) or `... allow none ...` (allow).
Synthesized fixtures only (`cq-test-fixtures-synthesized-only`).

Must-DENY (decision and the ask reason):

- `AK1` "Roadmap items 3 and 4 were listed in the brief but the fix only covers item 1. Who owns items 3 and 4 - should they be run as a new pipeline, or recorded as not fixed?"
- `AK2` "Should the remaining roadmap items be handled in this PR, run as a new pipeline, or recorded as not fixed?"
- `AK3` "These remaining items are outside the original fix. Run them as a new pipeline now (a), or record them as not fixed (b)?"
- `AK4` "Should I start a new pipeline for the leftover items or leave them not fixed?"
- `AK5` "who owns the leftover items? run them as a separate pipeline, or note them as unfixed?"

Must-ALLOW (P2 witnesses; the mutation each kills is in the matrix):

- `AL1` "Drop item 3 from this release?" and `AL2` "Should I defer the billing change to next quarter?" (genuine scope and schedule asks)
- `AL3` "Approve running the new pipeline for items 3 and 4?" and `AL4` "Who should own the remaining items, Alice or Bob?" (an authorization and an assignment ask; neither reaches the cue, they pin P2 at the hook level)
- `AL5` "Do you want the remaining items run as a new pipeline, or should I drop them?" (ROUTE only)
- `AL6` "Should I record the migration as not fixed and tell the customers?" (RECORD only)
- `AL7` "Is it okay to run items 3 and 4 as a new pipeline instead of recording them as not fixed?" (both halves, permission exemption)
- `AL8` "Should I move the launch of items 3 and 4 into a new pipeline or mark them not fixed?" (both halves, vetoed by `launch`)
- `AL9` "Which of the two roadmap items does this PR own? Option A: both. Option B: only the first.", `AL10` "Who owns the remaining roadmap items?", `AL11` "Is the scope of this fix limited to item 1, or does it include roadmap items 3 and 4? Ask once then act." (the stated residual, pinned so a later session cannot claim it is covered)

1.2. `NR3` (new, one assertion row): a lib-sourcing probe where `tfc_is_fork "<AK3 lowercased>" shared` and
`... shared+closing` exit 1 and `... shared+ask` exits 0 with `TFC_HIT=ask`. Add a reason assertion on AK1 (see the
harness rows in the Guard Contract). No grep of the hook's call text (the deny rows break if it changes).

1.3. V5: add `AK1`..`AK5` to `v5_rows` and raise the `>= 36` floor by 5. V1 literal (the `TOTAL -eq` check, its echo,
and `MIN_CASES`: three sites) move together to `145 + N` in the pre-ask suite; count N by running.

1.4. In `.claude/hooks/pre-closing-technical-fork-gate.test.sh`: retarget G2-2 (matrix row 4) and say in a comment
beside it that a pre-ask group change reddens this suite; add the three committed mutants (rows 1 to 3) through a
pre-ask variant of the existing mutant row helper (it must keep the crash-diagnostic and byte-identical guards and
increment `KILLED`; the existing `mut_row` only drives the closing hook, so the pre-ask variant builds an
`AskUserQuestion` payload and compares the verdict across the pristine and mutated trees, as `preask_dec` does for
G2-2); add one closing allow row using the AK3 text; raise the V6 floor (24) by 3 and move the V1 literal and
`MIN_CASES` (130, three sites). Correct the header table at line 32.

1.5. Run both suites: RED.

### Phase 2 — the lib, the hook and its comments

2.1. Lib. The two regexes (ERE, lowercased single-spaced input), unchanged from the CTO ruling:

```
TFC_ASK_ROUTE_RE='(\b(as|in|via|into) (a |an )?(new|separate|fresh) (pipeline|one-shot|pr|run|issue)\b|\b(start|open|file|spin up)[a-z]* (a |an )?(new|separate|fresh) (pipeline|one-shot|pr|run|issue)\b)'
TFC_ASK_RECORD_RE='\b(record|note|mark|log|document|list|leave)[a-z]* [^?.;]{0,30}\b(not fixed|unfixed|not addressed|not done|known gaps?)\b'
```

The check is one line inside the weak-cue block, after the `ab` cue line and before the exemption:

```
if [[ -z "$hit" && "$ask" -eq 1 ]] && grep -qE "$TFC_ASK_ROUTE_RE" <<<"$asked" && grep -qE "$TFC_ASK_RECORD_RE" <<<"$asked"; then hit="ask"; fi
```

2.2. Hook. Change the call to `shared+ask`. When `TFC_HIT` is `ask`, replace the reason's lead (the first
"BLOCKED: ... TECHNICAL RULING" line and the explanatory paragraph that follows it) with:

> BLOCKED: this AskUserQuestion asks the operator to route items the brief already named (run them as a new pipeline vs record them as not fixed). That is a technical routing call: spawn soleur:engineering:cto first, record `Ruled by CTO agent`, and ask the operator only the authorization. If you are asking the operator to DROP, DEFER or ADD something they asked for, reword it as a permission ask ("Approve dropping ...?").

and keep every later paragraph of the existing reason (the "Delegate it" paragraph, the split instruction, the
"May I" reword, the closed list), so every existing substring assertion (L1 closed list; `ruling_check`'s
`soleur:engineering:cto`, `technical-ruling-delegation.md`, `split the item; ask the operator only the
authorization`, `May I`) still holds. The lead must not contain `SOLEUR_ACK_TECHNICAL_FORK`.

2.3. Header comments: state the residual (ownership-only and scope-limited phrasings stay allowed; a two-sentence
split such as "Run these as a new pipeline now. Or record them as not fixed?" misses because the halves fall in
different sentences) and that the recall is fitted to synthesized phrasing, so the miss, cue, fixture loop carries the rest.

2.4. Run both suites: GREEN.

### Phase 3 — skill text

3.1. Reference section 1 (the closed list): after the `**scope**` bullet add the H2 classification rule verbatim.
The list string `money | scope | priority | schedule | irreversible | production-mutating | legal-risk | brand`
is not edited.

3.2. Reference section 5 (Override clause): open with "A brief or an operator message that says \"surface it / do
not decide it\", \"ask the operator\", \"ask the operator once, then act\" or \"OPEN DECISION\" about a technical item is
itself the trigger to spawn the CTO (`soleur:legal:clo` for legal posture), record `Ruled by CTO agent, <date>:
<decision> - <rationale>`, and ask the operator only the authorization part, naming the action. The brief's wording
never moves a technical item onto the operator-only list in section 1." Add a second **Why:** `2026-10-14 — a
resume brief said "ask the operator once, then act" about whether leftover roadmap items run as a new pipeline or are
recorded as not fixed; the question reached the operator, who said the CTO should rule ("ask the CTO not me")`.

3.3. Reference section 7: add the worked row `| T4 run the leftover roadmap items as a new pipeline or record them as not fixed | technical | Ruled by CTO agent, 2026-10-14: ... |` inside the fenced example (kept parseable; it is extracted and fed to the gate by
`plugins/soleur/test/technical-ruling-gate.test.sh`, which must be re-run).

3.4. `plugins/soleur/commands/go.md`, first Sharp Edge bullet (outside the go-routing block): after "...even when the
brief says to surface it." add one sentence: "A brief's \"ask the operator\", \"ask the operator once, then act\" or
\"OPEN DECISION\" wording on a technical fork is itself the trigger to spawn the CTO, not a reason to call
`AskUserQuestion`." Keep the existing link; the classification rule is linked, not restated.

3.5. `plugins/soleur/skills/go/SKILL.md`, after "In every case the AUTHORITY is `commands/go.md`...": "That includes its
first Sharp Edge: a brief's \"ask the operator\" / \"OPEN DECISION\" wording on a technical fork is the trigger to spawn
the CTO, never a reason to ask ([technical-ruling-delegation.md](../brainstorm-techniques/references/technical-ruling-delegation.md))."

3.6. `plugins/soleur/skills/one-shot/SKILL.md` inline copy: change `A brief that says "surface it, do not decide it"
changes nothing for the technical part.` to `A brief that says "surface it, do not decide it", "ask the operator" or
"OPEN DECISION" about a technical item changes nothing: that wording is the trigger to spawn the CTO.` `wc -c` stays
below 52000 and the 1400-byte window still holds `soleur:engineering:cto`, `Ruled by CTO agent` and `surface it`.

3.7. `plugins/soleur/test/components.test.ts`, in `describe("Technical-ruling delegation wiring")`: add
`"OPEN DECISION"` to the inline-copy token list; add one test with three whitespace-normalized content anchors —
the reference's section 5 contains `OPEN DECISION` and `ask the operator`; the reference contains `routing or ownership
of an already-identified gap`; the first Sharp Edge bullet of `commands/go.md` contains `OPEN DECISION`. No block-hash
re-implementation (the eval gate owns that).

### Phase 4 — records

4.1. ADR-084 correction plus short addendum via `soleur:architecture` (see `## Architecture Decision (ADR/C4)`).

4.2. Learning under `knowledge-base/project/learnings/workflow-patterns/` (topic: the brief wording is the third
carrier of the technical-fork rule). Key Insight per H3: the carrier is the brief; a hook cannot see a brief;
enumerate the carriers (tool call, artifact, closing message, brief) before strengthening an enforcer. One
Prevention rule: when a brief's wording tells you to ask the operator about a technical fork, treat that wording as
the trigger to spawn `soleur:engineering:cto` first, record `Ruled by CTO agent`, and ask the operator only the
authorization from the closed list; a scope-worded question about routing or owning a gap the brief named is
technical. State the residual. Session Errors: the plan-time surprises (G2-2 goes red when the pre-ask group
changes; `skills/go/SKILL.md` is a shim and the authority is `commands/go.md`), each with a prevention.

4.3. `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.

### Phase 5 — verification (run every literal command once before the PR)

- Both hook suites end `OK`. `bash scripts/guard-vacuity-floor.test.sh` passes (floor shape recognised).
- Mutation rows 5 to 7 by hand against a scratch copy of the lib (record the three RED results in the PR body).
- `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/technical-ruling-gate.test.sh`, `bash plugins/soleur/test/go-routing-table-parity.test.sh`.
- go-routing block byte-identical: compare `node plugins/soleur/skills/eval-harness/scripts/extract-block.cjs <(git show origin/main:plugins/soleur/commands/go.md) go-routing | sha256sum` with the same command on the working file (measured equal on the unedited tree).
- `python3 scripts/lint-guard-contract.py`; `npx markdownlint-cli2` on every new or edited `.md`; `bash plugins/soleur/test/c4-count-parity.test.sh`.
- `wc -c plugins/soleur/skills/one-shot/SKILL.md` below 52000.
- Probe the real hook with a payload whose options are bare strings (the corpus shape the hook already handles).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Skill text only, no hook change | Leaves a measured gap after the operator already complained once; CTO H1 rejected it |
| Inline arm in the pre-ask hook | Breaks the one-definition-site rule and suite row L2 |
| The cue in the `shared` group | Widens the Stop closing carrier with no incident behind it |
| An ownership-only cue | Measured false deny of an assignment ask; cut by H1b |
| Deny every question containing `scope` | The disqualifying false deny: scope is operator-only |
| A new rule in `AGENTS.rules.md` | Forbidden by the brief and redundant: the rule exists |

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator is asked a technical routing question they cannot
  answer (the cue misses), or a genuine routing or authorization question is denied with a CTO-first reason (a wrong
  deny), forcing a reword to a permission ask.
- **If this leaks, the user's workflow is exposed via:** nothing leaves the machine; the hook reads one tool-call
  payload locally and writes a hashed incident row (cue name, length, sha256, never the text).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the failure is a stalled or mis-routed
  internal question in this repository's own sessions, the hook is repo-local and fail-open, and the worse failure (a
  wrong deny of an authorization) is bounded by the permission-shape exemption and the one-line reword the deny
  reason teaches. `threshold: none, reason: the touched paths are repo-local workflow tooling and prose, not a user-data or auth path.`

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled H1, H1b, H1c, H2 and H3 during this planning run (plan review then fed back
through a follow-up ruling); the plan implements them as returned. No other domain is implicated: no UI-surface
path in the Files lists (no Product/UX gate), no spend, no legal posture, no regulated data. Observability (Phase
2.9) does not apply: the files are `.claude/hooks/` and prose, outside the code-class path set, and no
infrastructure is introduced; the hook's telemetry already exists (`emit_incident`, ADR-205) and the new cue reuses
the existing "technical ruling put to a non-technical operator" label.

## Acceptance Criteria

### Functional

- [ ] AC1. The real hook DENIES AK1 to AK5 with the ask reason and ALLOWS AL1 to AL11 (AL9 to AL11 are the stated residual). Command: `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh`, final line `OK`.
- [ ] AC2. `tfc_is_fork "<AK3 lowercased>" shared` and `... shared+closing` exit 1; `... shared+ask` exits 0 with `TFC_HIT=ask` (row NR3).
- [ ] AC3. The closing hook suite is green with G2-2 retargeted, the three committed mutants and the closing allow row; the V6 floor is raised by exactly the net new mutants (3). Command: `bash .claude/hooks/pre-closing-technical-fork-gate.test.sh`, final line `OK`.
- [ ] AC4. The reference's section 5 names `ask the operator` and `OPEN DECISION` as the CTO trigger; section 1 carries the H2 classification rule verbatim next to the `scope` bullet; section 7 has the T4 row; the closed-list string is unchanged.
- [ ] AC5. `commands/go.md` Sharp Edge and `skills/go/SKILL.md` carry the trigger sentence (the shim sentence links the reference); the `go-routing` block hash equals the `origin/main` hash (Phase 5 command).
- [ ] AC6. The one-shot inline copy carries `OPEN DECISION` within its first 1400 bytes and `wc -c` stays below 52000.
- [ ] AC7. `components.test.ts` passes with the three anchors and the added token.
- [ ] AC8. ADR-084's false sentence is corrected and the short addendum exists; no deferred issue stands in for either.
- [ ] AC9. None of these paths appears in `git diff origin/main --name-only`: `AGENTS.md`, `AGENTS.rules.md`, `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/plan/SKILL.md`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, anything under `.github/workflows/`.
- [ ] AC10. The learning exists under `knowledge-base/project/learnings/workflow-patterns/` with Problem, Solution, Key Insight, Prevention, Session Errors and Tags.

### Quality Gates

- [ ] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] `python3 scripts/lint-guard-contract.py` passes; markdownlint passes on every new or edited `.md`.
- [ ] No pinned literal other than the V1 literals and `MIN_CASES` (both suites), V5's list and floor, and the V6 floor changes; V8 (`RULING_OPVOCAB_RE`), V4 (`RULING_PERM_RE`) and L2 are untouched.
- [ ] PR: labels `semver:patch` and `app:web-platform`; body carries `Ref #9217` and never `Closes`, ends with the Claude Code generated-with line; every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- [ ] Merge sequence at ship: `emit-review-trailer.sh --findings <n>` as its own command, then push, then `gh pr merge`. An issue about Soleur's own guards carries the `meta/machinery` label (verified to exist).

## Test Scenarios

- Given a question that proposes running leftover items as a new pipeline or recording them as not fixed, when it is sent through `AskUserQuestion`, then the hook denies with the CTO-first reason and the closed operator-only list in the text.
- Given "Drop item 3 from this release?" or "Who should own the remaining items, Alice or Bob?", then the hook allows it.
- Given "Is it okay to run items 3 and 4 as a new pipeline instead of recording them as not fixed?", then it is allowed (permission shape).
- Given the closing hook sees the same shape in a closing message, then it does not block (the cue is not in `shared+closing`).
- Given a lib that fails its self-check, then the ruling arm is skipped with the existing stderr line (ML1 unchanged).

## Risks and Sharp Edges

- **A wrong deny is the worse failure.** The cue needs both halves in one interrogative sentence, passes the full
  operator-vocabulary veto and the permission exemption; AL1 to AL8 are the guard. Tripwire: a false deny of a real
  operator ask flips H1 to skill-text only. The ledger stores only a cue name, a length and a sha256, so such a deny
  is found by hashing candidate sentences from the local transcript (the recipe in the 2026-10-12 learning), not by
  reading the ledger.
- **Lexical recall decay and fitted fixtures.** AK1 to AK5 are synthesized from a description of the incident, not
  the actual question, and the operator-vocabulary veto silences real questions that say "plan", "release" or "ship".
  Recall on the real carrier is unmeasured; the remedy is the miss, cue, fixture loop, never preemptive widening.
- **`go` shim vs authority.** Editing `skills/go/SKILL.md` alone would leave `commands/go.md` unchanged; both are edited.
- **Skill byte budget.** `go` is not a ceiling row; `one-shot` has 1235 bytes of headroom for a ~90-byte edit;
  `skill-body-budget.json` is not edited.
- **A plan whose `## User-Brand Impact` section is empty or carries placeholder text fails `deepen-plan` Phase 4.6.** Filled above.
- **Never name the new constants `RULING_*_RE`** in the hook (L2); the lib is the sole definition site.
- **Plan and `tasks.md` are linted by lefthook at commit time:** run markdownlint before the Session Summary.
