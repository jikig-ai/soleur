# Learning: a facts bundle handed to the legal author carried my own framing, and the review panel found it

## Problem

The #6107 pipeline (an Art. 35 re-evaluation memo for the Compound Promotion Loop, #2720) had one author for the legal text, the CLO agent, and one author for the evidence it rests on, the work agent. The evidence was gathered correctly (zero loop-opened PRs by three searches, ten decoded outcome rows, symbol-level code anchors) but the facts bundle written for the CLO restated the loop's behaviour from the plan and from memory in several places. The CLO caught four of those itself (the output screen is not "the PII regex over the diff", the week cap is "2 minus open labelled PRs", phase 2 is a second call site, the marker is not the only sink). A six-seat panel then found what neither author had checked: a second public output surface (a comment carrying the model-derived diff on an unrelated open PR), a phase-1 prompt with no untrusted-data framing, the promotion log being merged-only evidence, a "four independent routes" count that was really two sources, and a criteria tally and an Art. 35(1) timing paragraph that the fleet screening and the 2026-05-11 record did not support.

A first fix round then introduced its own defect: a "balancing before the first PR" precondition that left the ongoing named-person transmission with no deadline.

## Solution

- The CLO fixed everything in two batched rounds (14 unique defect keys from about 70 raw findings), with every finding applied or rejected on the record.
- Claims were scoped to the evidence: causes stated only for the decoded window, "two sources" instead of "four routes", output surfaces listed as two, precondition split into a publication limb (before the first PR) and a named-person limb (dated action 2026-11-19 on the re-arm tracker #10676).
- A fresh verification seat checked the fix diff only, and found the one fix-introduced defect, which the second round closed.

## Key Insight

The evidence a legal memo rests on is itself prose-shaped review surface: every sentence the work agent writes into the facts bundle is a claim the legal author will inherit as established. Gather the figures with commands (done), but also verify each BEHAVIOURAL sentence of the bundle against the code before handing it over, and give the legal author the symbols to read rather than the summary. The cheapest probe is one question per sentence: which command would falsify this, and was it run?

## Session Errors

1. **The worktree guard refused compound shell commands and any command using variable expansion around git.** Recovery: split into plain single commands, used literal paths, wrote helper scripts to the scratchpad. **Prevention:** the planner already recorded this in the plan's Sharp Edges; keep wrapper scripts in the scratchpad for any multi-step probe.
2. **`technical-ruling-gate.sh` rejected the CPO sign-off row classed `technical` (bad-ruling-shape).** Recovery: reclassified the row as `taste` with a "Signed off by CPO agent" ruling. **Prevention:** only CTO and CLO rulings use the technical class; sign-offs by other leaders are `taste` rows.
3. **Facts bundle restated plan/memory claims about the loop's behaviour without falsification** (output screen, week cap, call-site count, marker sinks, "four independent routes"). Recovery: CLO fix rounds. **Prevention:** before spawning a legal author, run each behavioural sentence of the bundle against the code symbols it names and attach the symbols, not the paraphrase.
4. **`gh issue create` for the re-arm tracker was blocked by the filing gate (no user-visible consequence named).** Recovery: added `Mandated-By: wg-when-deferring-a-capability-create-a` on its own line. **Prevention:** a tracker filed because a deferral rule mandates it carries that line from the first draft.
5. **A positive control decode (`SOLEUR_CLAUDE_COST`) returned 0 against double-nested rows.** Recovery: read the raw shape and recorded the control as liveness only. **Prevention:** a control row count over the same window is liveness evidence; decode structurally before calling it a grade.
6. **First fix round introduced a mis-timed precondition.** Recovery: a verification seat over the fix diff found it and the second CLO round split the limbs. **Prevention:** run the one fresh verification pass over every fix round, as ADR-267 prescribes; a fix to a legal wording is as unreviewed as the wording it replaced.
7. **The session was interrupted by a transient network error (EAI_AGAIN).** One-off; resumed from the committed state on the branch.

## Tags

category: workflow-patterns
module: legal / compound-promote DPIA re-evaluation
