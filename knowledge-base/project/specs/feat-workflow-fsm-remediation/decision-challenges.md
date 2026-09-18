# Decision challenges — feat-workflow-fsm-remediation (#8302)

Recorded per ADR-084. These are places where evidence gathered during
implementation bears on a decision the operator already made. The operator's
stated direction is the default and has been implemented as stated; these are
surfaced, not acted on.

## 1. `postmerge -> work` was rejected, but it occurs

**Your decision.** When choosing legal back-edges you selected
`review -> work`, `ship -> work` and `work -> plan`, and explicitly rejected
`postmerge -> work` as redundant with `ship -> work`.

**What the data says.** Running the new classifier over 10,260 real invocation
records (1,334 sessions, ~16 months), `postmerge -> work` occurs **7 times**. It
is not the largest undeclared transition — `brainstorm -> compound` (123),
`compound -> plan` (97) and `review -> ship` (46) are all larger — but it is not
zero either, which is what "redundant" would predict.

**Why this is not a reversal.** Seven occurrences over sixteen months is
consistent with either reading: a genuinely-used recovery path, or seven
sessions that should have gone through `ship`. The classifier cannot tell those
apart, and nothing here establishes that your call was wrong.

**What was implemented.** Your decision, as stated. `postmerge -> work` is NOT
declared, and `declaredTransitions("postmerge")` returns `[]`.

**What would settle it.** Reading the seven sessions. If they are post-merge
verification failures that legitimately returned to implementation, the edge is
real and should be declared; if they are sessions that skipped `ship`, the
absence is correctly catching them.

## 2. The undeclared-transition count is dominated by three edges you did not rule on

`brainstorm -> compound` (123, skipping both `plan` and `work`) and
`compound -> plan` (97) together are half of all 427 violations. Neither was
part of the back-edge question you answered, because neither was proposed. They
may be legitimate lifecycle shapes the declared set is simply missing, rather
than violations. No action taken; recorded so the first reading of the
classifier's output is not mistaken for 427 defects.
