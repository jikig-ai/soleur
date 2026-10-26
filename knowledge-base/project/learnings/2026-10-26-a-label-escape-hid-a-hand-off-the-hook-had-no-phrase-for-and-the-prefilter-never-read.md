# Learning: a Blocked: label carried a technical hand-off past the closing hook, because the hook had no phrase for it and its pre-filter never read the label

## Problem

On 2026-10-26 a `soleur:one-shot` session closed a turn with a paragraph ("Your call, since the plan names the due date and any ruling on this slot as yours: accept ... or hold ...") and a final sentence beginning `Blocked:` that asked the founder to rule on whether a transient CI failure counts as evidence. The Stop hook `pre-closing-technical-fork-gate.sh` stayed silent and the founder said "ask the CTO not me and improve the workflow and skills to ensure the CTO gets invoked for technical decisions". The brief named two causes (the label exempts the whole closing; inside a ralph loop only the first Stop is judged). Feeding the verbatim closing to the real hook showed three, and the second one was not the brief's:

1. **No cue read the label sentence.** "needs your ruling on whether ..." matched none of the closing cues.
2. **The pre-filter never reached it.** A closing with no question mark only reaches the unit stage if a CL4 candidate phrase is in the window. The incident passed that pre-filter only because the paragraph above said "your call"; the label sentence alone exited at the pre-filter, before any unit existed. A first prototype that blocked the incident did so for that wrong reason.
3. **The label exempted the window** (the shared `Paused:`/`Blocked:` escape), and the paragraph above is vetoed by the business words `plan` and `date` anyway.

The ralph-loop inertness (only the first Stop of a chain is judged) was real but was not the cause here: the incident was a first Stop.

## Solution

- `tfc_is_label_handoff` judges only the final labelled sentence, with one phrase (`your ruling` after a waiting verb, or on/about/as to whether|if|which), the CL4 vetoes and a negation veto. The hook's pre-filter greps the same phrase variable, so it cannot judge fewer sentences than the function accepts (fixture LB2, the label alone, and mutation G1-24 pin that).
- A per-sentence cover flag rides on the final-sentence row, so an `Operator-only (category):` sentence of the same paragraph (or inline after the label colon) releases it, with the same flag the question rows carry; a cover consumed by an unrelated question unit does not carry over (LP13).
- The ralph stop hook does not run the repo-local gate (plugin hooks do not reach into the repo); it appends one constant reminder to the model-visible `reason` (the user-visible `systemMessage` keeps the banner), tested against a literal oracle on four state files with five mutants.
- The real control moved to where the decision is written: section 8.1b of the delegation reference (list the decisions the label's reason leaves to the operator, class each, one CTO spawn for the technical ones, the label names only the operator-only remainder), with one-sentence pointers.

## Key Insight

1. **A pre-filter is part of the cue.** A new phrase added to the verdict function is dead until the cheap gate in front of it reads the same phrase. Test the new cue on the sentence ALONE, not inside the incident message that happens to carry the old trigger.
2. **Measure the exemption before removing it.** Neutralising the label word on 11,421 local closings made the old hook block 3, so the label hid almost nothing the cues could see; the fix was a cue and a pre-filter, not a wider de-exemption. Measured cue candidates went through the real vetoes: `your ruling` fired once in 10,695 label sentences, bare `your call` 19 times with 12 operator-class.
3. **The cue-growth tripwire tripped, so the remedy changed.** Three founder-reported misses in 30 days: the control moves from adding phrases to the source of the decision (the skill pre-check) and the loop reminder. The next miss in a label sentence adds no cue.
4. **A channel is a contract.** `systemMessage` is shown to the user; the model reads `reason`. A reminder for the model in `systemMessage` is a reminder nobody acts on (the first ruling named the wrong field and a follow-up spawn corrected it).
5. **Pin both ends of an anchored mutation.** Every new mutation row asserts its anchor occurs exactly once before the first-occurrence applier runs, and a self-check mutant is killed by the stderr cause disappearing, because deleting the check does not always flip the verdict.

## Session Errors

- The first prototype blocked the incident for the wrong reason (the paragraph's "your call" kept the pre-filter open); caught by testing the label sentence alone.
- A line-number-keyed exemption in the boundary-prefix census followed a moved suite line; re-pinned in the same PR.
- The worktree directory vanished between the plan and work phases (not this session's doing); re-attached with `git worktree add` to the pushed branch head, nothing lost.
