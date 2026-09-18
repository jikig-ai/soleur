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
records (1,334 sessions, ~4.5 months — the invocation logger was added 2026-05-04), `postmerge -> work` occurs **7 times**. It
is not the largest undeclared transition — `brainstorm -> compound` (123),
`compound -> plan` (97) and `review -> ship` (46) are all larger — but it is not
zero either, which is what "redundant" would predict.

**Why this is not a reversal.** Seven occurrences over four and a half months (~1.5/month) is
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

> **Superseded 2026-09-18 (#8301 review):** the figures above are from the
> raw-adjacency walk. Review found that walk laundered any lifecycle transition
> through a sub-skill hop (`plan -> deepen-plan -> ship` read as zero
> violations). Under the node-only walk now shipped: 604 undeclared of 4,922
> lifecycle pairs, 1,259 sessions, 10,268 records; `brainstorm -> compound` 125,
> `compound -> plan` 109, `review -> ship` 51, `ship -> plan` 50,
> `plan -> ship` 7 (was 2). `postmerge -> work` is unchanged at **7**, so the
> ruling above stands on the corrected numbers.

## 3. The `plan` Sharp Edges extraction does not save what you were told it saves

**Your decision.** At plan review you chose "Extract only plan's Sharp Edges;
keep the ratchet", on the plan's claim that the block is consult-on-demand and
that moving it saves ~150 KB (~37k tokens) per `plan` invocation.

**What the data says (review, performance seat).** The file is ~58k tokens by
the harness's own count, not 37k; it is read in three paginated Reads; and the
load fires on ~95% of `plan` runs, because the catalogue's entries are mostly
plan-hygiene rules that apply to every plan. Per invocation the extraction is
**+~1 KB and three extra tool turns**. The real benefit is per-turn — loading
58k tokens at the END of a run keeps them off every earlier turn — which is
plausibly large and unmeasured.

**What was done.** The extraction stands as you chose it; the directive is now
unconditional and placed as the final step before Plan Review (which is also
where a verification pass belongs), and ADR-225 records the honest ledger.

**Your call.** Keep it (the per-turn argument is the reason), revert it (the
per-invocation claim was false), or ask for the per-turn saving to be measured
before deciding. This is a User-Challenge per ADR-084: the direction you set
is implemented, and the premise you set it on was wrong.

> **Appended 2026-09-18 (#8301 review, coverage consult) to §2:** the cause
> of the largest edge is now known. `brainstorm/SKILL.md` invokes
> `skill: soleur:compound` as a designed sub-step, so `brainstorm -> compound`
> (125) is a node skill used as a sub-skill — the non-node filter cannot see
> it. Declaring the edge (`brainstorm: [plan, one-shot, compound]`) would make
> the classifier honest about it; that is an edge-set change you did not rule
> on, so it is recorded here rather than made.
