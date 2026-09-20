# Decision challenges — feat-one-shot-8325-fsm-decision-challenges (#8325)

Recorded per ADR-084 at `plan` Step 4.5 (headless: the one-shot pipeline runs
`plan` inside a Task subagent, so nothing pauses). The operator's stated
direction is the default and is what the plan implements; this is surfaced,
not acted on. `ship` Phase 6 renders it into the PR body and files it as an
`action-required` issue.

## 1. The §3 decision rule fires on a median with no floor on n

- **What you said:** "If the measured median k is ≥ 2× break-even, state in the
  ADR that the extraction is kept on measured evidence and close §3 with it; if
  it is below, leave a one-line follow-up issue asking the operator to choose
  keep/revert with the number in hand."
- **What both signals recommend:** apply the rule only when the post-extraction
  sample is at least 5 runs (`post >= 5`); below that, record the numbers in
  ADR-229 as "measured, inconclusive at n=<N>", file the follow-up issue
  unconditionally with a re-measure date, and do not write "kept on measured
  evidence".
- **Why:** local transcript retention is three days (30 sessions, 702 subagent
  transcripts, 2026-09-17 → 2026-09-19). Enumerated at plan time by grouping
  every `Skill soleur:plan` invocation in `~/.claude/projects/<slug>/**/*.jsonl`
  with the SKILL.md text the harness loaded next: 25 plan runs; **23 loaded the
  pre-extraction SKILL.md** (the operator's plugin checkout had not pulled
  `50af0436f` yet — that was checked, not assumed: the loaded text names
  `references/plan-sharp-edges.md` in exactly 2 runs, both on 2026-09-19T18);
  1 of those 2 has the catalogue Read (k=36), the other is this pipeline's own
  plan run. A "kept on measured evidence" sentence written from n=1–2 would
  carry the authority of a measurement while being one sample; ADR-229's
  "plausibly large and unmeasured" is more honest than "measured at n=1".
- **What context we might be missing:** you may already accept n=1–2 as enough
  because k=36 sits 4.5× above break-even and the pre-extraction proxy k'_ac
  (median 45, n=17 — turns to the Write that lands `## Acceptance Criteria`,
  which is where the pass runs) corroborates it; or you may prefer the follow-up
  issue to be the place where n grows. Both are consistent with your ruling.
- **If we're wrong, the cost is:** one extra `action-required` issue that you
  close after reading a number you had already accepted; the ADR sentence is
  edited once more when n reaches the floor.

> **Confirmed at review, 2026-09-19 (#8382 design pass).** The precision half of
> this challenge was borne out within hours. A re-run of the same script on the
> same machine, the same day, gave n = 7 (not 2) and median k = 73 (not 61) —
> because `k` is right-CENSORED: a plan run still in flight has no catalogue
> Read yet and scores `post_skipped`. All four runs the first reading recorded
> as `post_skipped` later scored `post`, with k ∈ {38, 73, 81, 125}. Two
> consequences were applied to ADR-229 rather than deferred: the sentence
> asserting "4 of the 6 extracted runs skipped the pass … a finding against
> 'loads on ~95% of plan runs'" was FALSE and has been removed (it read a
> measurement artifact as a finding), and the ADR now rests the keep decision
> on every individual k clearing break-even by ≥ 3.9×, not on a two-sample
> median. The n-floor itself remains the operator's call; what the data settled
> is that a single reading of this rolling window must not be quoted as final.

**What was implemented.** Your rule, as stated: the ADR states n and the
retention window beside the median, and the follow-up issue is filed only when
the median is below 16. The plan's Phase 4 names the number of post-extraction
runs in the ADR sentence so the reader can weigh it.

## 2. `sub_steps` is generic by design, and two more entries are visible in the data

- **What you said:** §2 — "Collapse `compound` as a brainstorm SUB-STEP in the
  classifier … `BRAINSTORM_SUB_STEPS = ["compound"]` … mirror it (e.g. a
  `sub_steps: {"brainstorm": ["compound"]}` key)".
- **What both signals recommend:** keep the map keyed by node, as planned, with
  the single `brainstorm` entry — and record that the same designed shape exists
  for two other nodes, so the next reading is not mistaken for defects:
  `plan → compound` (31 undeclared rows) is `plan`'s exit gate
  (`plugins/soleur/skills/plan/SKILL.md`: "Run `skill: soleur:compound` to
  capture learnings from the planning session"), followed by `work` in 13 of the
  16 cases with a successor; `postmerge → compound` (11) is `postmerge`'s
  closing step (`plugins/soleur/skills/postmerge/SKILL.md`). Adding
  `plan: ["compound"]` and `postmerge: ["compound"]` would remove roughly 57 more
  undeclared rows (`plan → compound` 31, `postmerge → compound` 11, and the
  `compound → work` 15 that follow them) with no edge-set change.
- **Why:** the map form was chosen precisely because the classifier is generic
  over `sub_steps[<previous kept node>]`; the ruling names one entry, and the
  data shows the other two are the same class. Enumeration that produced it:
  the live classifier's row output (`bash scripts/classify-workflow-transitions.sh`)
  grouped by edge, and a jq walk over the main checkout's invocation log for the
  node following each `plan compound` pair (`work` 13, `ship` 3).
- **What context we might be missing:** you may want each sub-step entry argued
  separately (the brainstorm one was argued on 106 of 125 handoffs continuing to
  `plan`); or you may consider `plan → compound → ship` (3 cases, a review skip
  that the collapse would expose as `plan → ship`) reason enough to add the
  entry, since the collapse exposes rather than hides it.
- **If we're wrong, the cost is:** 42 rows that are designed handoffs keep
  reading as undeclared until a later PR adds two one-line entries; nothing
  ships wrong.

**What was implemented.** Your direction, as stated: one entry, `brainstorm`.
The plan corrects ADR-229's interpretation bullet so `plan → compound` is no
longer described as second-feature chaining, and the map's "To add an entry"
comment on the TS const makes the two-line follow-up mechanical.
