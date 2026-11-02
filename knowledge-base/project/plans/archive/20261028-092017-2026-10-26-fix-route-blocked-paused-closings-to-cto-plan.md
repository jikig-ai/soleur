---
title: "fix: route a technical decision in a Blocked/Paused closing to the CTO before the turn ends"
date: 2026-10-26
slug: route-blocked-paused-closings-to-cto
branch: feat-one-shot-cto-routing-blocked-paused-closings
pr: 11254
type: fix
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: route a technical decision in a Blocked/Paused closing to the CTO before the turn ends

Spec lacks valid lane: no spec.md exists for this branch, so `lane:` defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Phases 0-3, both Guard Contract entries, Research Insights, Dependencies & Risks, Acceptance Criteria
**Agents and passes used:** plan-review (DHH-lens, Kieran-lens, per-mechanism simplicity), a catalogue verification pass over the whole sharp-edges file, architecture-strategist,
test-design-reviewer, security-sentinel, the deepen-plan halt gates (4.5-4.13: all pass or skip), and a scratch prototype of the final design run against 36 fixture sentences. No further CTO spawn
(cto_spawns=2 of 2).

### Key improvements

1. The prototype found three plan errors before any code: the G1-8b anchor needs a re-pin, the first cover rule was wider than CTO A3, and the first LP3 could not see a deleted phrase gate.
2. Every fixture now names the single veto or release that decides it (LP1a/LP2/LP5b-LP5e/LP10), each mutation anchor is fixed and asserted unique, and the mutation set grew from 8 to 16 rows
   (V6 floor 51) so each copied veto, both phrase alternatives, the cover capture and both self-check clauses have a killing row.
3. The ralph reminder now carries the closed operator-only list, the CLO and the plugin-relative path to section 8.1, is tested against a literal oracle on four state files, and the suite gets a floor.

### New considerations discovered

- The pre-ask hook shares `tfc_self_check`, so an emptied label variable fails its ruling arm open too; its ML3 row gains the two variables (one existing row).
- Residuals are now stated and pinned: final-sentence-only judging, a forged category prefix, veto words and synonyms, first-Stop-only, and the `unkept-promise-hook.sh` text that teaches the label.
- `affected-tests.sh` does not select the pre-ask or ralph suites from these edits; they run explicitly and their pass lines go in the PR body.

## Overview

A `soleur:one-shot` session ended a turn with a paragraph that handed the founder a technical call and a
final sentence beginning `Blocked:` that asked for a ruling on whether a transient CI failure counts as
evidence. The closing-message Stop hook (`.claude/hooks/pre-closing-technical-fork-gate.sh`) stayed silent.
Founder instruction, 2026-10-26: "ask the CTO not me and improve the workflow and skills to ensure the CTO
gets invoked for technical decisions".

The measured reasons are three, not the two the brief named (see Research Insights): the hook's cue
vocabulary has no phrase for "needs your ruling"; the hook's pre-filter never reaches a closing whose only
hand-off carries no question mark and no existing phrase; and a final-sentence `Blocked:`/`Paused:` label
then exempts everything before it. The CTO ruled the minimum robust design on 2026-10-26 (cto_spawns=2 of the
two allowed, both recorded in `decision-challenges.md`): one label-scoped cue in a new function, a constant
reminder in the ralph block's model-visible text, and the real control moved to the skills, where the
decision is written, as one extension of section 8.1 of the delegation reference plus one-sentence pointers.

## Problem Statement

1. **The closing.** The paragraph "Your call, since the plan names the due date and any ruling on this slot as
   yours: accept slot A as a transient infra failure and proceed on slot B plus CI, or hold until a clean pair
   of slots exists and let the 2026-10-27 date slip." was followed by the final sentence "Blocked: slot A
   (2026-10-26T18:00Z) read `error` on a CI run, so marking the Sentry routing PR ready needs your ruling on
   whether this transient Doppler CLI install failure counts." Whether a transient infrastructure failure
   counts as evidence is a technical ruling (delegation reference, section 2); only the date slip is the
   operator's (schedule).
2. **Why the hook passed it** (measured 2026-10-26 against the worktree HEAD, the verbatim closing fed to the
   real hook): (a) the label exemption, hook lines 166-178, exits 0 before any unit is judged; (b) the label
   sentence matches no cue, because `TFC_CL4_PHRASE_ERE` is `your call|up to you|you (decide|choose|pick)`;
   (c) a closing with no `?` reaches the unit stage only if a CL4 candidate phrase is in the window, and the
   incident passed that pre-filter only because the paragraph above said "your call" (the label sentence alone
   returns exit 0 at the pre-filter, before units exist); (d) the paragraph above is a CL4 hit
   ("your call" plus "ruling") but is vetoed by the business words `plan` and `date`; (e) inside a ralph loop
   only the first Stop of a chain is judged, and the incident was a first Stop, so (e) was not the cause here
   but remains real for later Stops.
3. **Skill side.** The final-report decision check (section 8.1) runs only when `soleur:review` or
   `soleur:work` writes a report. The one-shot Step 8 pointer is signage ("inside this loop no Stop hook backs
   it"). Ship's hold exit says "stop and name that condition" with no technical-ruling step. The text that
   assigned the ruling to the founder was written by the producing agent, not copied from a template (grep of
   plan, ship, one-shot, work, go: no template says "the owner's call").

## Research Insights

### Premise Validation (Phase 0.6)

No issue or PR is cited by reference. Cited artifacts verified on this branch (HEAD a13a08057a, 2026-10-26):
the hook, the lib, the suite, `plugins/soleur/hooks/stop-hook.sh`, section 8.1 of
`technical-ruling-delegation.md`, the one-shot Step 8 pointer, the go.md Sharp Edge, ship Phase 6 step 5 and
`operator-holds.md` all exist. The proposed mechanisms were checked against the ADR corpus: ADR-084 (the
2026-10-12 and 2026-10-14 addenda) already records a cue-based Stop arm, the ralph-loop inertness note, a
"Cue-growth tripwire" and a CTO ruling (Q2) that the `Paused:`/`Blocked:` leak is "documented". A label
*matcher* was rejected there; a label-*sentence cue* was not, and this plan stays inside that line. ADR-178
(repo reaching toward a plugin, not the reverse) bars the loop hook from calling the repo-local gate.

### Property List (Phase 0.6b)

- P1. A closing whose final `Blocked:`/`Paused:` sentence hands a technical ruling to the operator is stopped
  once, on the first Stop of a chain, with the CTO-routing reason.
- P2. A genuine operator-only blocker (money, scope, priority, schedule, irreversible, production-mutating,
  legal-risk, brand) is never stopped, and an ordinary waiting label ("Blocked: waiting on CI") is never stopped.
- P3. Every parse doubt still fails open with one stderr line.
- P4. Inside a ralph loop the model reads, on every iteration, an instruction to route technical decisions
  before ending a turn with the label.
- P5. Every pipeline skill that can end a turn with `Blocked:`/`Paused:` routes the technical part of the reason
  to the CTO first, from ONE definition.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | What already covers it, or why cut |
|---|---|---|
| Judge the paragraph above the label in the hook | P1 | Cut by the CTO ruling A1: the paragraph is vetoed by `plan`/`date` anyway; P5 covers it at the source |
| Cues `your call`, `owner's call`, `your ruling on whether` as separate cues | P1 | Cut by A2: measured 19 fires of 31 for bare `your call`, 12 of them operator-class; `your ruling` alone covers the incident (the on-whether form is a sub-pattern of the one phrase) |
| Extend `tfc_is_handoff`'s phrase list | P1 | Cut by A2: it is the pre-filter candidate for every sentence; a label-only function bounds the blast radius |
| Run the gate from the ralph stop hook (B1/B4) | P4 | Cut by B: the incident was a first Stop the hook did judge; B1 inverts ADR-178 and double-fires |
| Edit `AGENTS.md`/`AGENTS.rules.md` | P5 | Cut by C: `hr-technical-fork-is-not-an-operator-question` already covers it; ADR-151 byte budget |
| Edit ship/SKILL.md Phase 6 step 5 | P5 | Cut by headroom: ship/SKILL.md is 273913 of 273955 bytes; step 5 already links `operator-holds.md`, where the pointer goes |
| A clause in the `unkept-promise-hook.sh` block reason (the producer text that teaches `Paused:`/`Blocked:`) | P5 | Not added: outside the brief's pointer list and the CTO's ruling C (which names the skill pointers); the ADR addendum records that hook still exempts the label, and reopens it if a miss traces there |
| A new ADR | record | Cut by D: an addendum to ADR-084 amends its own exemption and cue budget |
| A second pre-filter variable (`TFC_LABEL_CANDIDATE_ERE`) | P1 | Cut by plan review (taste, adopted): the pre-filter greps the one phrase variable, which is exactly the function's first gate |
| A committed equivalence corpus row and its acceptance criterion | P2 | Cut by plan review (taste, adopted): the loops of LP3/LP5/LP6 cover it; the real differential is a dated measurement in the PR body |
| Fixtures for zero-width space, A8i again and the loop guard again | P2/P3 | Cut by plan review (taste, adopted): normalisation, A8i and the loop guard have their own rows |

### Measured 2026-10-26 (read-only, local session transcripts of this repository, nothing printed beyond counts)

- Population: 42,396 turn-ending assistant text messages; 11,421 end with a `Paused:`/`Blocked:` label; 10,695
  of those have the label at the start of the final sentence.
- Label neutralised ("Note:") and the CURRENT hook run on all 11,421: 3 blocks (a repeated stale-loop message
  carrying "tell me to start ..."). So the whole-window exemption hides almost nothing the current cues can see:
  the incident was a cue gap plus the pre-filter, not mostly a leak of the label.
- Candidate cues through the lib's real vetoes: `your ruling` 1 match, 1 fire (the incident), 0 elsewhere in
  10,695; the decision-on-whether phrase 7 matches, 6 fires (priority and production-write items among them);
  bare `your call` 31 matches, 19 fires, 12 of them operator-class or missed by the authorization list
  ("merging" is not "merge" in `TFC_CL4_AUTH_RE`).
- Prototype (scratch copy, not committed): the incident closing and the label-only sentence block; plain waiting
  labels, `Operator-only (...)` released closings, price/merge-vetoed and negated sentences and fixture A8i pass.
  Full-population differential with labels intact, base hook against prototype, same 11,421 messages: base 0
  blocks, prototype 1 block (the incident), 1 verdict flip in total.
- Deepen-pass prototype v3 (scratch, the plan's final design: label phrase and verb-bound negation with the `n't` and `no need for` forms, `fin_cover` per sentence, the awk `islabel`
  fold, `F<cover>` rows, the hit goes straight to the block output): 36 of 36 fixture sentences behave as Phase 0 states (LB1-LB4, LB6-LB8, LP11u and the covered-unrelated-question-unit row
  block; LP1a, all eight categories, LP2, LP2b, LP3q, LP4-LP4d, LP5b-LP5e, LP6, LP9, LP10, LP10b, LP11, LP12, A8i and a trailing space-only line pass); each copied veto line is unique in the
  lib, so the mutation anchors land on the new function. The prototype corrected three plan claims: G1-8b needs a re-pin (the original anchor is a one-line `if ... then exit 0; fi`); the first
  cover rule ("any `esc` set in the line") was wider than CTO A3 and let an unrelated covered question unit release a technical label (replaced by `fin_cover`); and the first LP3 could not
  kill a deleted phrase gate because the pre-filter exits first (LP3q adds a harmless question).
- Baseline suite (`bash .claude/hooks/pre-closing-technical-fork-gate.test.sh`): 175/175 passed in 29 s; V5 reports
  258 of 258 spawns; V6 reports 35 mutants killed against a floor of 35.
- Not measured: whether the ralph reminder changes model behaviour (signage efficacy is `unverified`; the flip
  condition is in the ADR addendum); Devin/Codex Stop payloads (the hook fails open there by design).

### Institutional learnings applied

- `2026-10-12-the-closing-message-was-the-third-carrier-the-rule-had-no-reader-for.md`: judge sentences not
  messages; fix a miss as miss, cue, fixture; watch the tripwire (it tripped: see A2t).
- `2026-10-11-a-plain-word-escape-hatch-needs-an-empty-label-exclusion.md`: the label escape needs the empty-label
  exclusion, a final-sentence anchor and bold-form rows; no angle-bracket text in any block reason.
- `2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-and-nothing-noticed-the-arms-could-be-deleted.md`
  and `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`: mutate placement as well as
  presence; floors are reported with printf and exit, set tight, and verified by deleting a block.
- `2026-03-04-sessionstart-hook-api-contract.md`: `systemMessage` is user-visible only; the model reads `reason`.
- `2026-10-19-a-fail-closed-gates-tests-asserted-the-safe-verdict-which-two-causes-produce.md`: each fail-open
  row asserts its own cause on stderr.

### Constraints found (they shape the edits)

- SKILL.md byte ceilings (`plugins/soleur/test/skill-body-budget.json`, enforced against the merge base):
  one-shot 52000 (file 51996), ship 273955 (273913), plan 120000 (119986). The one-shot Step 8 pointer line is
  430 bytes today (measure again with `wc -c` before editing): the rewrite must be no longer than 434 bytes and the
  file must stay at or under 51996 bytes; ship/SKILL.md and plan/SKILL.md are not edited.
- `components.test.ts` pins anchors in the reference and in review/work (the section 8 heading, the 8.1 and 8.2 openings,
  and the review/work sentence that links section 8.1 and ends "only operator-category items stay", its `LINK81`), the go Sharp Edge
  opening and its `OPEN DECISION` trigger, and the one-shot inline copy; none may move.
- Suite accounting: `V1` literal and `MIN_CASES` are both 175 and move together after the last added
  `TOTAL=$((TOTAL+1))` (V1 counts itself: take the number from a green run); the V6 floor equals the killed count
  (35); the `guard-vacuity-floor` recogniser needs the floor shape kept (literal bound directly above its `if`);
  V5 matches `D_NAMES` word by word, so each new must-block row's name starts with its token.
- Mutation rows are anchored on literal source text and `apply_mut` replaces the FIRST occurrence: the new
  function declares `local sentence="${1-}"` and writes every veto against `"$sentence"`, and is defined after
  `tfc_is_handoff`, so each new anchor is unique and G1-17/G1-21/G1-22 keep matching their current first
  occurrence. G1-8b MUST be re-pinned: its anchor is the whole one-line `if [[ -n "$CONTENT" ]] && ! [[ ... ]]; then exit 0; fi`, which becomes a multi-line block;
  the new anchor is the first line of that block (`if [[ -n "$CONTENT" ]] && ! [[ "$CONTENT" =~ ^(none|na|nothing|no|nil)$ ]]; then`, one occurrence), mutated to
  `if [[ -n "$FINAL_SENT" ]]; then`, and E3b still flips (the mutant enters the branch on `none.`, finds no hand-off and exits 0). G1-19's anchor line stays valid.
- Lib purity row C2: no `.claude/`, `CLAUDE_PROJECT_DIR`, `emit_incident`, `hcloud` or `g2` on a non-comment line;
  row C3: every `TFC_*_RE=` cue has exactly one definition site (the new variables are named `*_ERE`, like the CL4 ones).
- Reason text rows R1-R4: the block reason keeps the CTO/CLO names, the closed list, `Paused:` and `Operator-only (money):`,
  carries no angle brackets and none of the words promise, operator-gate, done.
- A mutated copy of `stop-hook.sh` sources `../scripts/resolve-git-root.sh`; a ralph mutant tree must mirror
  `hooks/` and `scripts/`, or the hook exits at "not in a git repo" and every redden is vacuous.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured or read) | Plan response |
|---|---|---|
| Two reasons: the label exempts the whole closing; a loop makes later Stops unjudged | Three more: no cue for "your ruling"; the pre-filter needs a CL4 phrase or a `?`; business words `plan`/`date` veto the paragraph. The incident was a first Stop | Label-scoped cue and pre-filter parity (Phase 1); loop reminder only (Phase 3) |
| A label must not exempt a closing whose labelled sentence or the paragraph above is a hand-off | CTO A1: label sentence only; the paragraph above is vetoed anyway and judging it flips fixture A8i for no recall | Label sentence judged; paragraph-level ask becomes the skill pre-check (`operator (scope)` row A1s) |
| Add cues "needs your ruling", "your ruling on whether", "owner's call", "your call" | `your ruling` alone fires 1 of 10,695; `your call` fires 19 with 12 operator-class | One cue; the others recorded as not added (`operator (scope)` row A2s) |
| Plan, ship, one-shot, work, go carry templates saying "the owner's call" | No such template exists (grep). The text came from the producing agent | Pre-check in section 8.1, pointers, one plan-sharp-edges bullet; no template to rewrite |
| Decide with the CTO whether the loop's stop hook runs the gate | CTO B: no. The hook is repo-local; plugin-to-repo coupling inverts ADR-178 | Reminder line in the model-visible block text, tested |
| Respect the AGENTS.md byte budget | Confirmed; also SKILL.md ceilings (one-shot 4 bytes of headroom, ship 42) | No AGENTS edit; one-shot pointer within +4 bytes; ship pointer lives in `operator-holds.md` |

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 0 writes the fixtures and mutation rows and shows them red
against the unchanged hook; Phases 1-5 make them green.

### Phase 0 — fixtures RED (suite `.claude/hooks/pre-closing-technical-fork-gate.test.sh`)

New rows (the count is taken from the suite's own TOTAL at the end of the work; about 49 with the mutation rows of Phase 2, the census row and the ledger row):

- Must-BLOCK (each name starts with its token and is added to `D_NAMES`, so V5 proves THIS hook's reason blocked it): LB1 the verbatim
  incident closing (status line, "Your call" paragraph, `Blocked:` sentence); LB2 the label sentence alone (no `?`, no CL4 phrase:
  proves pre-filter parity); LB3 bold `**Paused**:` with "awaiting your ruling on whether"; LB4 NBSP inside "your ruling";
  LB6 an `Operator-only (...)` sentence separated from the label by a blank line does not release; LB7 "pending your ruling on which design";
  LB8 "Blocked: your ruling on which design is still open." (the second phrase alternative only).
- Must-PASS. Every release fixture uses the two-line shape (the `Operator-only` sentence on line 1, a single newline, the label on line 2) and a label
  body byte-identical to LB2's, so LB2 is its blocking twin and the release is the only difference:
  LP1 all eight categories (loop, one case, as E2c does) and LP1a one category ("Operator-only (money): the second seat is a spend call." then the LB2 label) as its
  own row for the mutation; LP2 the inline form `Blocked: Operator-only (scope): needs your ruling ...` (the category must be one of money, scope, irreversible or
  legal-risk and the reason after the colon must carry no veto word: schedule, priority and brand are business words and production-mutating trips the authorization veto,
  so those would pass without the release and prove nothing); LP2b the bold inline form; LP3 ordinary waiting labels (loop: CI, merge queue, a third party has not
  replied, "waiting on your go-ahead to merge") and LP3q "Is CI green yet? Blocked: waiting on CI." (the `?` keeps the pre-filter open, so deleting the
  phrase gate would flip it); LP4 "Blocked: this is not awaiting your ruling, it only waits on CI." (only the negation veto releases it; "not blocked on your ruling" never
  matches the phrase list) plus LP4b "we are not waiting on your ruling", LP4c "this isn't awaiting your ruling" and LP4d "there is no need for your ruling on whether it counts";
  one single-veto sentence each: LP5b "Blocked: needs your ruling on whether to merge now." (authorization), LP5c "Blocked: it is ok to keep waiting, but it needs your ruling on whether
  the failure counts." (shared permission shape `ok to` only: a go-ahead is also an authorization verb and would be released twice), LP5e "Blocked: shall i arm slot b; it needs your
  ruling on whether the failure counts." (closing-only permission shape only), LP5d "Blocked: the feature needs your ruling on whether the failure counts." (closing-extra);
  LP6 the CTO's documented residual "Blocked: the plan needs your ruling on whether the date slips." (business veto only); LP9 the label is not the final sentence (no row
  kills it; it documents the residual); LP10 the phrase inside backticks in a non-label sentence ("Blocked: waiting on CI; the phrase the hook cues on is `needs your ruling on whether`.")
  so the span strip is what keeps it passing; LP10b the label on a `>` quote line; LP11 an `Operator-only (...)` sentence, then a label sentence that itself ends in a question mark,
  passes, and LP11u the same label sentence uncovered blocks; LP12 the label sentence split by a full stop ("Blocked: CI read error. It needs your ruling on whether that counts.") passes,
  documenting the residual; LP13 "Operator-only (money): ok? Blocked: needs your ruling ..." blocks (a cover consumed by an unrelated `?` unit does not carry over, CTO A3). A8i stays as it is.
- Fail-open: ML2 reuses ML1's tree with one lib copy per cause: (a) `tfc_is_label_handoff()` renamed so the function is missing, (b) `TFC_LABEL_PHRASE_ERE=''`, (c) `TFC_LABEL_NEG_ERE=''`;
  each is `cmp`-checked to differ from the pristine lib, the unmodified control blocks LB2, and each copy passes it with "cue lib missing or incomplete" on stderr.
- Reason: R5 the reason carries the substring "unless that sentence itself leaves a technical ruling" (so the sentence cannot drift).
- Ledger: LG2 after LB1 the last ledger row has the cue `label`, a `len=... sha256=...` snippet and none of the lowercase tokens ruling or doppler (the hash covers the normalised text
  after the label colon; the lib header says so).
- No H5: H1 already proves the instrument; the block-everything guard is killed by G1-34 (Phase 2).

### Phase 1 — lib and hook

- `.claude/hooks/lib/technical-fork-cues.sh` (new code after `tfc_is_handoff`, before `_TFC_COMPLETE=1`):

  ```text
  TFC_LABEL_PHRASE_ERE='\b(needs|needed|awaiting|awaits|requires|pending|waiting (on|for)) your ruling\b|\byour ruling (on|about|as to) (whether|if|which)\b'
  TFC_LABEL_NEG_ERE='(\b(not|no longer|never|without)\b|n'"'"'t) ([a-z]+ ){0,2}(needs?|awaiting|pending|requires?|waiting (on|for)) your ruling|\bno need for your ruling\b'
  ```

  and `tfc_is_label_handoff` declaring `local sentence="${1-}"`, setting `TFC_HIT=""`, returning 1 on an empty sentence, then: the phrase gate on its own line;
  EXTRA, BUSINESS, `TFC_CL4_AUTH_RE`, `RULING_PERM_RE`, `TFC_CLOSING_PERM_RE` vetoes (each its own physical line against `"$sentence"`); then the negation veto; then
  `TFC_HIT=label`, return 0. Each assignment is ONE physical line at column 0 (the pre-ask suite's ML3 blanks a variable with `sed s/^VAR=.*/VAR=''/`). Extend `tfc_self_check`
  (one line checking both variables non-empty, and one line for `declare -f tfc_is_label_handoff`). Header: the cue count is now 4 of 6 and this is the last cue; the next label miss
  adds no cue and opens the other remedy named in ADR-084 (A2t); the ledger hash for the label cue covers the normalised text after the label colon. `_TFC_COMPLETE=1` stays the last
  statement. No comment in the lib or the hook may repeat a mutation anchor.
- `.claude/hooks/pre-closing-technical-fork-gate.sh`:
  1. Pre-filter: `grep -E "$TFC_CL4_CANDIDATE_ERE|$TFC_LABEL_PHRASE_ERE"` (the label phrase is already the function's first gate, so the pre-filter cannot judge fewer sentences than
     the function accepts).
  2. Cover flag (CTO A3: the same cover flag the unit rows carry): in the awk, `fin_cover = esc` after each sentence is processed in `note_sentences` and after the `?`-unit's own `islabel`
     check, before `esc` resets; END folds the inline form with the awk's own `islabel()` on the final sentence's body (the text after the `Paused:`/`Blocked:` colon, emphasis stripped), so the
     eight-category list stays in ONE place, and prints `"F" cover "\t" s`. The reader becomes `grep -E "^F[01]${TAB}"` and `FINAL_SENT="${FINAL#F?"$TAB"}"` with `FINAL_COVER="${FINAL:1:1}"`.
     (A trailing space-only line does not lose the cover: `fin_cover` is assigned per sentence and never at END.)
  3. Move `HIT_UNIT=""; HIT_CUE=""` above the label branch. Keep the empty-label exclusion condition itself unchanged, as the first line of a now multi-line block
     (`if [[ -n "$CONTENT" ]] && ! [[ "$CONTENT" =~ ^(none|na|nothing|no|nil)$ ]]; then`; G1-8b is re-pinned to it); inside it, take `BODY="${FINAL_SENT#*:}"; BODY="${BODY# }"` and run, each on its own line:
     `[[ "$FINAL_COVER" == 1 ]] && exit 0`; `tfc_is_label_handoff "$BODY" || exit 0`; then `HIT_UNIT="$BODY"; HIT_CUE="$TFC_HIT"`. Wrap the two judging loops in
     `if [[ -z "$HIT_UNIT" ]]; then ... fi` so a label hit goes to the single block output with no fall-through (CTO A1).
  4. Reword the block reason's last paragraph to: "A final sentence beginning Paused: or Blocked: followed by what you are waiting on also ends
     this check, unless that sentence itself leaves a technical ruling to the operator; then route it to the CTO first." (no angle brackets;
     none of promise, operator-gate, done).
  5. Update the header's ESCAPES paragraph and the "mostly inert inside a ralph loop" note (the reminder, A2t, B3), and the "mirrors the plugin hook" comment.

### Phase 2 — suite accounting and mutation rows

Each new row first asserts its anchor occurs exactly once (`[[ "$(grep -cF -- "$old" "$f")" == 1 ]]`), then the existing guards (landed, parses, control gives the expected verdict, mutant differs,
mutant did not crash). Anchors, all single physical lines:

- G1-23 `tfc_is_label_handoff "$BODY" || exit 0` becomes `exit 0` (LB1, LB2 flip block to pass; never `:`, which would block everything).
- G1-24 `grep -E "$TFC_CL4_CANDIDATE_ERE|$TFC_LABEL_PHRASE_ERE"` becomes `grep -E "$TFC_CL4_CANDIDATE_ERE"` (LB2 flips: own dispatch).
- G1-25 the first `fin_cover = esc` (in `note_sentences`) becomes `fin_cover = 0` (LP1a flips pass to block).
- G1-26 the awk's inline fold `if (islabel(b)) cov = 1` becomes `if (0) cov = 1` (LP2 flips; never anchored on `islabel(`, whose first hit is the function definition).
- G1-27, G1-28, G1-29, G1-33 the new function's negation, BUSINESS, authorization and closing-extra veto lines, each replaced by `:` (LP4, LP6, LP5b, LP5d flip pass to block).
- G1-32 the `RULING_PERM_RE` veto line and G1-32b the `TFC_CLOSING_PERM_RE` veto line of the new function, each replaced by `:` (LP5c / LP5e flip).
- G1-30 delete the `tfc_self_check` line that requires both label variables (a custom row like G2-1: ML2's emptied-phrase copy flips from fail-open to block); G1-37 delete the
  `declare -f tfc_is_label_handoff` line (ML2's missing-function copy flips).
- G1-31 the existing G1-16 mutation (`if (line ~ /^ *$/) { esc = 0; next }` loses its reset) driven by LB6 (a second member after a compliant first; that line stays byte-identical).
- G1-34 delete the phrase gate line of the new function (LP3q flips pass to block: a label function that blocks any label sentence is seen).
- G1-35 the `fin_cover = esc` in the `?`-unit branch becomes `fin_cover = 0` (LP11 flips pass to block); G1-36 delete the second phrase alternative (LB8 flips block to pass).
- Census row C5 (the pattern of C1/C3): exactly one file defines `tfc_is_label_handoff` and the `TFC_LABEL_*_ERE` variables (the lib), and only the closing hook calls the function (C3's pattern
  `^TFC_[A-Z0-9_]*_RE=` does not match `*_ERE=`, so the new variables need their own row).
- Set `V1`'s literal and `MIN_CASES` to the exact new TOTAL in one edit; set the V6 floor to the exact new killed count (51 if all sixteen rows land: G1-23 to G1-37 plus G1-32b; take the number
  from a green run); extend `D_NAMES`; update the header MUTATION MATRIX comment; keep the floor shape.

### Phase 3 — loop reminder (`plugins/soleur/hooks/stop-hook.sh`, `plugins/soleur/test/ralph-loop.test.sh`)

- Before the final `jq` call define the constant on one physical line, single-quoted, with no backticks, apostrophes or angle brackets:

  ```text
  REMINDER='Before ending a turn with Blocked: or Paused:, class every decision the reason leaves to the operator. Send the technical ones to soleur:engineering:cto first (legal ones to soleur:legal:clo) and name only the operator-only remainder. Money, scope, priority, schedule, irreversible, production-mutating, legal-risk and brand decisions stay with the operator, and a CTO ruling never authorizes such an act. See section 8.1 of skills/brainstorm-techniques/references/technical-ruling-delegation.md in the Soleur plugin.'
  ```

  Emit `{"decision":"block","reason":($prompt + "\n\n" + $rem),"systemMessage":$msg}` from `jq -n --arg prompt ... --arg rem "$REMINDER" --arg msg ...` (never by editing `PROMPT_TEXT`:
  command substitution strips trailing newlines). `systemMessage` stays the `Ralph iteration N | ...` banner byte-for-byte and does not contain the reminder (CTO B3c; `systemMessage` is
  user-visible only). jq's pretty output is kept so the existing `"decision": "block"` assertions stay green. Loop control, the stuck/repeat/similarity detection (they hash `LAST_OUTPUT`) and the
  stored prompt are untouched.
- Tests (written first): four fresh state files made with the suite's `create_state_file` (iteration 1 and iteration 7, each with and without a completion promise; iteration N is never 1, so the
  iteration-2-only mutant cannot pass both), each holding the literal prompt `Line one` / blank line / `Line two ends here` and no `---` line. RL-B3a asserts `.decision == block` first (so zero emitted
  blocks cannot pass), then `.reason` equals the literal prompt, two newlines and the literal REMINDER text (a test-side copy: the oracle is the literal, not the hook's own extraction), and contains
  `soleur:engineering:cto`, `section 8.1` and `Blocked:`; RL-B3b `.systemMessage` equals the literal banner for NEXT_ITERATION and lacks `section 8.1`; the state file's prompt block (extracted with
  the awk) and `stuck_count` are compared before and after (the hook rewrites the frontmatter on every run, so the whole file is not compared). The suite finishes with `print_results <N>`, N taken from
  a green run, so deleting the RL-B3 block trips the anti-vacuity floor. The existing ralph rows stay green unchanged (an acceptance statement, not a row).
- Mutations, each applied with a first-occurrence applier that refuses an absent anchor and runs `bash -n`, in a mutant tree that mirrors `hooks/` and `scripts/` and whose control emits
  `"decision": "block"` first: delete the line from `reason`; exit 0 before the block is emitted (own dispatch: the only mutant that expects empty output, and it also requires stderr free of
  `line N:` diagnostics); add the reminder only when `NEXT_ITERATION` is 2 (second member); move it to `systemMessage` only; prepend instead of append. The other four must still emit
  `"decision": "block"` with the reminder missing or misplaced. Each reddens a row.

### Phase 4 — skills (one definition, pointers)

- `technical-ruling-delegation.md`: keep the 8.1 heading and the `LINK81`-pinned sentences byte-identical; add one paragraph after 8.1 that adds only the
  delta: "8.1 also runs before ANY turn in a pipeline skill ends with `Blocked:` or `Paused:`: the label's reason is a decision list. Technical items are
  ruled by the CTO first; the label names only the operator-only remainder. Technical: 'does a transient failure count as evidence', 'relax or keep a
  gate'. Operator-only (schedule): 'slip a date'. Backed by the label-sentence cue of the closing hook (a backstop; the paragraph above the label and
  vetoed words pass it) and the reminder in the loop block." (Class, batch, record and split are 8.1's existing text; they are not restated.)
- Pointers, one sentence each: one-shot Step 8 signage line, rewritten to cover the label and say what backs it, no longer than 434 bytes. The exact replacement (measured 2026-10-26: the line is 430 bytes now and this draft is 428; no test
  pins the dropped list item):

  ```text
  > **The Step 8 closing is a carrier too (signage; the loop reminds):** never end it, or a `Blocked:`/`Paused:` label, with a technical question to the operator ("Decision for you:"); spawn `soleur:engineering:cto` (legal: `soleur:legal:clo`), record `Ruled by CTO agent`, ask only the authorization. [technical-ruling-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/technical-ruling-delegation.md).
  ```

  The work phase re-measures with `wc -c` and keeps the file at or under 51996 bytes; go.md Sharp Edge 1 (append a clause; keep its opening and the `OPEN DECISION` trigger);
  `ship/references/operator-holds.md` one sentence under the section 2 exit table covering exit rows 1 and 2 (a hold that stands on an evidence
  judgement is a technical ruling: route it per section 8.1 before naming it; only an `Operator-reserved:` hold or a human-only condition goes to
  the operator); `plan/references/plan-sharp-edges.md` one clause-length bullet (a plan section that writes a technical outcome as "the owner's" or "the
  operator's" call is itself the defect; write the ruling or an `assumed:` default). No edit to ship/SKILL.md, plan/SKILL.md, AGENTS.md,
  AGENTS.rules.md or any SKILL.md description.

### Phase 5 — record

- ADR-084 addendum dated 2026-10-26, at most about 15 lines (it also states: the pre-ask ruling arm shares `tfc_self_check`, so an emptied label variable skips that arm with the stderr line, an accepted coupling covered by the pre-ask suite's ML3 row; and the label cue is first-Stop only): A1(i) and the narrowed Q2 residual, A2 (one cue, tripwire TRIPPED, its replacement and the
  next-miss rule), A3 with the question-mark-label edge, B3 with the `reason` channel in one sentence and the B1 flip condition, ADR-178 unchanged.
- Learning file under `knowledge-base/project/learnings/` (dated at write time, slug `a-label-escape-hid-a-hand-off-the-hook-had-no-phrase-for-and-the-prefilter-never-read`):
  the problem, the three measured reasons, and the pre-filter-parity trap (the first prototype passed for the wrong reason). The cue measurements go in the PR
  body; the channel trap is the 2026-03-04 learning and is cited, not restated.
- PR body: `## Measured` and `## Not measured` with dates (the list above plus the work-phase results and a re-run of the local differential), the
  `## Changelog` section, `Ruled by CTO agent` lines, no closing keyword for any other issue.

### Phase 6 — gates before ready

Run the suite, the ratchets for every touched file (Acceptance Criteria), the affected gate (`affected-tests.sh`, rc 6 is not a pass), and
`technical-ruling-gate.sh --branch` (exit 0). Merge-queue PRs that are BEHIND wait for the queue
(`plugins/soleur/scripts/ci-head-verdict.sh verdict <PR>`); never hand-sync a queued PR.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Judge the label sentence and the paragraph above it in the hook (the brief) | Rejected (A1): vetoed by `plan`/`date`, flips A8i, no recall gain |
| Drop the label exemption for the whole window | Rejected (A1): 3 blocks in 11,421, all stale-loop repeats |
| Cues `your call`, `owner's call`, decision-on-whether | Rejected (A2): 12 of 31 bare `your call` matches are operator-class |
| Extend `tfc_is_handoff`'s phrase list | Rejected (A2): changes the pre-filter for every sentence |
| Share one veto chain by extracting it from `tfc_is_handoff` | Not taken (taste): leaves a working function and the pre-ask suite untouched; the copy is pinned by its own mutation rows |
| Run the repo-local gate from the ralph stop hook (B1, B4) | Rejected (B): inverts ADR-178, double-fires, would not have caught this first-Stop miss |
| Skill text only (B2) | Rejected (B): no reminder at the carrier boundary inside the loop |
| Edit `AGENTS.rules.md` | Rejected (C): the rule already covers it; ADR-151 budget |
| A new ADR | Rejected (D): amends ADR-084's own exemption and budget |

## Files to Edit

- `.claude/hooks/lib/technical-fork-cues.sh`
- `.claude/hooks/pre-closing-technical-fork-gate.sh`
- `.claude/hooks/pre-closing-technical-fork-gate.test.sh`
- `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (one existing row: its fail-open loop over the lib's required variables gains the two label variables; TOTAL does not move)
- `plugins/soleur/hooks/stop-hook.sh`
- `plugins/soleur/test/ralph-loop.test.sh`
- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`
- `plugins/soleur/skills/one-shot/SKILL.md` (no larger than 51996 bytes)
- `plugins/soleur/commands/go.md`
- `plugins/soleur/skills/ship/references/operator-holds.md`
- `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md`

## Files to Create

- a learning file under `knowledge-base/project/learnings/` with the slug `a-label-escape-hid-a-hand-off-the-hook-had-no-phrase-for-and-the-prefilter-never-read` (dated when written)
- (this phase, already written) `knowledge-base/project/plans/2026-10-26-fix-route-blocked-paused-closings-to-cto-plan.md`,
  `knowledge-base/project/specs/feat-one-shot-cto-routing-blocked-paused-closings/{tasks.md,decision-challenges.md}`

## Open Code-Review Overlap

None. Checked 2026-10-26: 98 open `code-review` issues, none names any of the eleven files above.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-084 (an addendum, not a new ADR; CTO ruling D). One-line decision: the `Paused:`/`Blocked:` exemption is narrowed to
"label sentence judged, paragraph above exempt"; one final label cue; the cue-growth tripwire is tripped and replaced by the skill
pre-check plus the loop reminder. A task of Phase 5, not a follow-up.

### C4 views

No `.c4` edit. Checked 2026-10-26 by reading `spec.c4` and `views.c4` in full and the actor, engine, hook and plugin
sections of `model.c4` (the file is 255 KB; the sections read are the 65-120 actor block, 145-310 engine/hook/plugin blocks).
(a) External human actor: the founder/operator is modeled (`founder`); no new correspondent. (b) External system: none added; the
CTO agent is modeled (`plugin.cto`). (c) Container or data store: the Hook Engine (`platform.engine.hooks`) already names the
repo-local Stop arm, its fail-open behaviour, once-per-turn blocking and shared lib; the ledger is a local file already in scope.
(d) Actor-to-surface access: unchanged (the founder reads closing messages today). Derived cardinalities in edge prose are
unchanged; confirm with `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The addendum describes the target state now; nothing is soak-gated.

## Guard Contract

### Guard 1 — label-sentence hand-off arm of the closing gate

**Property.** A closing whose final `Paused:`/`Blocked:` sentence itself hands a technical ruling to the operator is stopped once, on the first Stop of a chain,
unless an `Operator-only (category):` sentence of the same paragraph (or the label body itself) releases it, and every parse doubt
passes.

**Assembly.** The property quantifies over every path that can end the hook on a label: the pre-filter in the hook (a closing with no
`?` and no CL4 phrase must still reach units when the label phrase is in the window); the awk emitter and its cover flag on the final
sentence; the label branch and its single cover-flag release line; the lib function with its phrase gate, five vetoes and negation veto; the self-check
that rejects an empty regex (fixture ML2 is its member); the single block output with the judging loops wrapped behind the hit; and the
fixtures' `D_NAMES` list that proves THIS hook blocked. The chokepoint is the label branch; the other members flow into it, and a mutation on
any of them must move a row.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | G1-23 delete the label judge (the branch always exits 0) | RED: LB1 and LB2 flip block to pass |
| 2 | G1-24 the pre-filter drops the label phrase (own dispatch: a closing with only the label cue never reaches units) | RED: LB2 flips |
| 3 | G1-25 break the carried-over cover (the awk `fin_cover` in `note_sentences` becomes 0) / G1-35 the same in the `?`-unit branch | RED: LP1a / LP11 flip pass to block |
| 4 | G1-26 delete the awk's inline `islabel` fold on the label body | RED: LP2 flips pass to block |
| 5 | G1-27 delete the negation veto | RED: LP4 flips pass to block |
| 6 | G1-28 / G1-29 delete the BUSINESS veto / the authorization veto in the label function | RED: LP6 / LP5b flip pass to block |
| 7 | G1-32 / G1-32b / G1-33 delete the shared permission veto / the closing-only permission veto / the closing-extra veto in the label function | RED: LP5c / LP5e / LP5d flip pass to block |
| 8 | G1-30 delete the `tfc_self_check` line that requires both label variables / G1-37 delete its `declare -f` line | RED: ML2's emptied-variable copy / missing-function copy flips from fail-open to block |
| 9 | G1-34 delete the phrase gate of the label function (a function that blocks any label sentence) / G1-36 delete the second phrase alternative | RED: LP3q flips pass to block / LB8 flips block to pass |
| 10 | second member after a compliant first: G1-31, the G1-16 mutation (never reset the cover on a blank line) driven by LB6 (an `Operator-only` sentence in an EARLIER paragraph, then the technical label) | RED: LB6 flips block to pass |

**Harness rows.** The must-PASS rows are not the canonical: LP3/LP3q and LP5b-LP5e differ from the incident in the way the contract permits (a different label content, a single
vetoed word), and every release row has LB2 as its blocking twin; G1-34 is the block-everything probe (H1 already proves the row helper). ML2 (three causes): a lib copy missing the
function or with an empty regex must fail open with the stderr cause, so a stub lib cannot satisfy the suite. LG2 pins the ledger cue name `label`.

**Anchor.** The suite stores a count (`V1`, `MIN_CASES`) and a mutant floor (V6). A weakening that deletes rows and one floor passes
inside one diff; what is outside the commit is `scripts/guard-vacuity-floor.test.sh`, which builds the neutered-counter and
lowered-floor mutants for any suite whose floor keeps the recognised shape, and the set identity of `D_NAMES` (a deleted must-block
row also drops its name from V5's required set).

### Guard 2 — loop reminder in the ralph block

**Property.** Every block the ralph stop hook emits carries, in the model-visible `reason`, the constant reminder after the unchanged
prompt, and the reminder never alters the stored prompt or loop control.

**Assembly.** The single `jq` call in `plugins/soleur/hooks/stop-hook.sh` that builds the block JSON (it follows both completion-promise
branches of the `SYSTEM_MSG` construction); the tally-capped and max-iteration exits emit no block and are out of scope.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete the reminder from `reason` | RED: RL-B3a |
| 2 | own dispatch: exit 0 before the block is emitted | RED: RL-B3a asserts `decision` is `block` before it reads the text, so zero checks cannot pass |
| 3 | second member: add the reminder only when `NEXT_ITERATION` is 2 | RED: RL-B3a on the other iteration |
| 4 | move the reminder to `systemMessage` only | RED: RL-B3a and RL-B3b (the model never sees it) |
| 5 | prepend instead of append (prompt no longer first) | RED: the prefix assertion |

**Harness rows.** Four fresh state files (iteration 1 and 7, with and without a promise), so both branches and a non-first iteration are exercised; the oracle is a literal expected string, not
the hook's own extraction; the stored-prompt row compares the state file's prompt block (not the whole file) before and after; the mutant tree asserts its control blocks before it is mutated;
the suite ends with `print_results <N>` so deleting the RL-B3 block trips a floor.

**Anchor.** The existing ralph rows stay green unchanged (they assert `"decision": "block"` and loop control, not the message text, so they are a statement and not a row);
no stored value is compared to the thing it protects.

## Observability

```yaml
liveness_signal:
  what: the label arm is wired (the hook calls tfc_is_label_handoff on the label body); at runtime each block writes one deny row to the local incident ledger (cue name "label", unit length, sha256, never the text)
  cadence: static wiring per commit; ledger row per blocked closing
  alert_target: none (local developer hook; the 30-day review counts rows by hook name per ADR-084)
  configured_in: .claude/hooks/pre-closing-technical-fork-gate.sh (_tfc_record), .claude/settings.json Stop entry
error_reporting:
  destination: stderr, one line per fail-open arm ("SKIPPED - <cause>")
  fail_loud: a fail-open arm never blocks; the suite asserts each cause (F1-F6, ML1, ML2)
failure_modes:
  - mode: the label cue blocks an operator-only sentence
    detection: ledger rows with cue label whose sha256 matches a closing the operator-only label should have released; the wrongful-block procedure in the lib header
    alert_route: reply "send it anyway" (repeat close passes) or place Operator-only (category): before the sentence
  - mode: the label cue stops matching (lib truncated or regex emptied)
    detection: tfc_self_check fails open with "cue lib missing or incomplete" on stderr; suite rows ML1 and ML2
    alert_route: suite red in CI
  - mode: the ralph reminder is dropped
    detection: ralph-loop.test.sh RL-B3a and RL-B3b; locally `grep -c 'Send the technical ones to soleur:engineering:cto first' plugins/soleur/hooks/stop-hook.sh` prints 1; a further in-loop miss (the B1 flip condition) is founder-reported only, no hook instruments later Stops of a chain
    alert_route: suite red in CI
logs:
  where: .claude/.rule-incidents.jsonl (local, gitignored ledger)
  retention: local, until the developer clears it
discoverability_test:
  command: grep -o -e 'tfc_is_label_handoff "$BODY"' .claude/hooks/pre-closing-technical-fork-gate.sh
  expected_output: tfc_is_label_handoff "$BODY"
```

## User-Brand Impact

**If this lands broken, the user experiences:** a wrongly stopped closing message (one extra turn, one line explaining why) or a
closing that still asks the founder a technical question they cannot answer; no data, money or workflow is touched.

**If this leaks, the user's data is exposed via:** nothing; the hook records only a cue name, a length and a sha256, and the
reminder line is a constant.

**Brand-survival threshold:** none

Threshold decision (challengeable): none; the touched paths are hook scripts, a plugin hook, reference prose and an ADR, none of
which matches the canonical sensitive-path expression (checked against the preflight Check 6 regex, 2026-10-26).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO ruled every fork of this plan in two spawns on 2026-10-26 (see `decision-challenges.md`): label-sentence-only
scope, one label cue in a new function, tripwire tripped and replaced by the skill pre-check plus a loop reminder, one ADR-084
addendum, and the `reason` field as the reminder's channel. No other domain is implicated: no UI surface (Product/UX tier NONE), no
brand, legal, spend or revenue surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ask the CTO not me and improve the workflow and skills to ensure the CTO gets invoked for technical decisions" | Phases 1, 3, 4 (hook cue, loop reminder, section 8.1 pre-check and pointers) | mapped |
| 2 | "A. Hook: a `Blocked:`/`Paused:` label must not exempt a closing whose labelled sentence or the paragraph above it is itself a technical hand-off to the operator" | Phase 1 (labelled sentence) | mapped (the paragraph-above half is carried by the skill pre-check, CTO ruling A1, `operator (scope)` row A1s) |
| 3 | "Add must-BLOCK fixtures reproducing the closing above and must-PASS fixtures for genuine operator-only blockers (money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand) and ordinary waiting labels; mutation-test the new arm" | Phases 0 and 2 | mapped |
| 4 | "keep the suite's accounting floor exact; run the suite and the repo ratchets for the files you touch" | Phase 2 (V1, MIN_CASES, V6) and Phase 6 | mapped |
| 5 | "B. Loop inertness: decide with the CTO whether the loop's stop-hook ... should also run the closing gate ... or whether the skill-level check (C) is the right mechanism; implement the chosen one with tests" | Phase 3 (CTO ruling B3) | mapped |
| 6 | "C. Skills: make the pipeline skills route a technical decision to the CTO BEFORE ending a turn with `Blocked:`/`Paused:`" | Phase 4 | mapped |
| 7 | "Keep edits minimal and single-sourced (one definition, pointers elsewhere); respect the AGENTS.md byte budget" | Phase 4 (one definition in 8.1, no AGENTS edit, one-shot line within +4 bytes) | mapped |
| 8 | "D. A learning file for the session and the standard PR body (measured / not measured, dated)" | Phase 5 | mapped |
| 9 | "Do not close, reference with a closing keyword, or comment on any other open or closed issue from this PR" | Acceptance Criteria (grep for closing keywords and foreign numbers) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Label-sentence cue and pre-filter parity (lib, hook) | "add the missing cues such as 'needs your ruling', 'your ruling on whether'" | asked |
| Release by `Operator-only (category):` | "unless it carries the existing `Operator-only (<category>):` label" | asked |
| Fixtures and mutation rows (suite) | "Add must-BLOCK fixtures reproducing the closing above" | asked |
| Loop reminder in `stop-hook.sh` and `ralph-loop.test.sh` | "implement the chosen one with tests. Do not weaken the ralph loop's own behaviour." | asked |
| Section 8.1 extension and pointers (reference, one-shot, go.md, operator-holds.md) | "extend section 8.1 of technical-ruling-delegation.md, the one-shot Step 8 pointer, the go.md Sharp Edges technical-ruling bullet, the ship time-gate/hold text" | asked |
| plan-sharp-edges.md bullet | "any plan-template wording that says 'the owner's call' for a technical outcome" | asked |
| ADR-084 addendum | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" (the recorded rulings D) | ruled (CTO ruling D: the addendum is the record; the 2026-10-12 addendum states the tripwire and Q2 ruling this plan changes) |
| Learning file and PR body | "A learning file for the session and the standard PR body" | asked |
| Population differential and prototype measurement | "the PR body states what was measured and what was not with dates" | asked |
| Reason-text reword in the hook | "a `Blocked:`/`Paused:` label must not exempt a closing whose labelled sentence ... is itself a technical hand-off" | asked (required by P1: the current reason says the label "also ends this check", which would be false for a hand-off label; fixture R5) |

### Split Assessment

- Subsystems touched: 3 — `.claude`, `plugins/soleur`, `knowledge-base`
- Planned files: 15 (11 edited, the learning file, the plan, tasks.md and decision-challenges.md) | Estimated changed lines: about 650 (suite rows and mutants about 330, hook and lib about 90, ralph tests about 90, prose about 80, ADR and learning about 60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 The verbatim incident closing makes the real hook print a block decision: suite row LB1 passes; the label-only sentence (LB2, no `?`, no CL4 phrase) also blocks.
- [ ] AC2 `bash .claude/hooks/pre-closing-technical-fork-gate.test.sh` prints `OK`; `V1`'s literal, `MIN_CASES` and the suite's TOTAL are the same exact number (taken from a green run, 175 plus the rows added); the V6 floor equals the killed count; V5 lists every new must-block name.
- [ ] AC3 Each new mutation row (G1-23 to G1-37 and G1-32b, sixteen rows) reports killed; deleting the label branch reddens LB1 and LB2 (shown in the PR body from a sandbox run).
- [ ] AC4 Must-PASS: all eight `Operator-only (category)` categories (two-line shape), the inline form (plain and bold), ordinary waiting labels (with and without a pre-filter-opening question), the four negation forms, each single-veto sentence (business, authorization, shared permission, closing-only permission, closing-extra), LP10/LP10b/LP11/LP12 and fixture A8i pass; LP11u and LP13 block.
- [ ] AC5 `bash plugins/soleur/test/ralph-loop.test.sh` is green, including RL-B3a and RL-B3b on all four state files, the five reminder mutations, and `print_results <N>` with a floor.
- [ ] AC6 `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/technical-ruling-gate.test.sh`, `bash plugins/soleur/test/cto-interface-selector.test.sh` and `bash plugins/soleur/test/boundary-prefix.test.sh` are green; `python3 scripts/lint-skill-body-budget.py --base origin/main` is green and `plugins/soleur/skills/one-shot/SKILL.md` is no larger than 51996 bytes.
- [ ] AC7 Ratchets for the touched files are green: `bash scripts/guard-vacuity-floor.test.sh`; `shellcheck` on the hook, lib, suite, `plugins/soleur/hooks/stop-hook.sh` and `plugins/soleur/test/ralph-loop.test.sh`; `python3 scripts/lint-guard-contract.py` on this plan; `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`; `bash plugins/soleur/test/fixture-relative-assert.test.sh` (new fixture operands in the ralph suite can move its baseline counts); `bash .claude/hooks/hook-suite-dep-unresolved.test.sh`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/lint-trap-tempfile-ownership.test.sh`; `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh` (the pre-ask hook calls the same `tfc_self_check`, so an emptied label phrase also fails ITS ruling arm open: accepted coupling, stated in the ADR addendum); `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] AC8 `bash plugins/soleur/scripts/affected-tests.sh` exits 0 (rc 6 is not a pass). It does not select `pre-ask-technical-fork-gate.test.sh` or `ralph-loop.test.sh` from these edits: AC5 and AC7 run them explicitly and their pass lines go in the PR body under `## Measured`.
- [ ] AC9 Section 8.1 of the reference carries the Blocked/Paused pre-check with its heading and pinned sentences byte-identical; the four pointers exist; `git diff --name-only origin/main...HEAD` lists neither `AGENTS.md` nor `AGENTS.rules.md` nor `ship/SKILL.md` nor `plan/SKILL.md`.
- [ ] AC10 ADR-084 carries a 2026-10-26 addendum recording the rulings, the tripwire disposition, the channel and the B1 flip condition; a learning file matching `knowledge-base/project/learnings/*-a-label-escape-hid-a-hand-off*.md` exists; `git diff origin/main...HEAD -- plugins/soleur/skills | grep -cE '^[-+]description:'` prints 0.
- [ ] AC11 `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0; every technical row carries a `Ruled by CTO agent` ruling.
- [ ] AC12 The PR body has `## Measured` and `## Not measured` (dated, including the local population differential as a measurement and not as a criterion), a `## Changelog`, and no closing keyword; `grep -rnE '#[0-9]{3,}' knowledge-base/project/plans/2026-10-26-fix-route-blocked-paused-closings-to-cto-plan.md knowledge-base/project/specs/feat-one-shot-cto-routing-blocked-paused-closings` prints nothing (the branch's own PR number appears only without a hash) and the PR body carries no closing keyword for another issue.

## Test Scenarios

- Given the incident closing, when the Stop hook runs with `stop_hook_active` false, then it blocks once with the CTO-routing reason.
- Given "Operator-only (money): the second seat is a spend call." directly above "Blocked: needs your ruling on whether the failure counts.", then it passes.
- Given the same two sentences separated by a blank line, then it blocks.
- Given "Blocked: waiting on CI.", then it passes; given "Blocked: none.", then it passes.
- Given a ralph loop on iteration 1 and on iteration N, then the block's `reason` is the stored prompt followed by the reminder, and the state-file prompt is unchanged.
- Given a lib with the label phrase emptied, then the hook fails open with "cue lib missing or incomplete".

## Dependencies & Risks

- Recall: first-Stop only (a label written after an `unkept-promise-hook.sh` block, or on a later Stop of a ralph chain, carries `stop_hook_active` true and is unjudged: the section 8.1 pre-check and the loop reminder are the only controls there, and the `unkept-promise-hook.sh` text that teaches `Blocked:` is unchanged); still cue-based; the paragraph above the label and words held back by the vetoes (`plan`, `date`, `merge`, ...) pass the hook. The CTO accepted this; the skill pre-check is the control and the ADR addendum states the next-miss rule.
- Residuals stated in the ADR addendum (each pinned by a documenting row where one exists): the arm judges only a final sentence that BEGINS with the label (a label sentence split by a full stop, or any sentence after the label, is unjudged: LP12); a one-sentence `Operator-only (category):` prefix in the same paragraph releases it without any check that the category is true (CTO A3); a veto word, a near-synonym ("needs your decision", "sign-off"), a split sentence, a forged category, the `<stop>` escape or `SOLEUR_ACK_TECHNICAL_FORK=1` all avoid it. The arm is a once-per-turn nudge, not a barrier; the control is the section 8.1 pre-check, and a miss opens the other ADR-084 remedy, never a synonym cue (A2t).
- The first prototype passed the incident for the wrong reason (the paragraph's "your call" kept the pre-filter open). LB2 and mutation G1-24 exist to keep that from recurring.
- One-shot SKILL.md has 4 bytes of headroom under its ceiling; the pointer edit must not grow it past 51996 bytes.
- The tripwire disposition rests on the CTO's reading of the recorded misses; the addendum cites an artifact for each (the 2026-10-12 and 2026-10-19 hook changes and their fixtures, this incident) and states that the loop-inertness condition is the addendum's own known-limitation note rather than a separately recorded incident.
- Reminder efficacy is unverified; B1 is deferred, not rejected, and reopens on a further in-loop miss.
- The CTO spawn budget of the pipeline run is spent at plan time (cto_spawns=2 of 2). A new technical fork found in `work`, `review`
  or `ship` is either Mechanical under the de minimis bound (no row), recorded as `pending - assumed: <default>` with the reason it
  could not be ruled, or hits the gate's bounded remedy (PR stays draft, one `domain/engineering` issue, never an operator question).

## References

- ADR-084 (2026-10-12 and 2026-10-14 addenda), ADR-157, ADR-178, ADR-151, ADR-229
- `.claude/hooks/pre-closing-technical-fork-gate.sh`, `.claude/hooks/lib/technical-fork-cues.sh`, `.claude/hooks/pre-closing-technical-fork-gate.test.sh`
- `plugins/soleur/hooks/stop-hook.sh`, `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`
- `knowledge-base/project/specs/feat-one-shot-cto-routing-blocked-paused-closings/decision-challenges.md`
