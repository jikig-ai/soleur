# Decision challenges — feat-one-shot-10904-pbt-methodology

Plan: `knowledge-base/project/plans/2026-10-25-content-pbt-methodology-spoke-plan.md`
Context: one-shot pipeline plan phase on Devin CLI subagent — no Agent/Task tool, so
technical rulings are recorded as `pending - assumed:` defaults per the pipeline's
technical-ruling convention, and no named review panel could be spawned (self-review only).

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Publish date / filename date for the spoke post — the brief says "blog scheduled (not with-merge); spoke of the arc hub (#10902)" but names no date | operator (schedule) | pending - assumed: 2026-10-29 (Thursday of the arc's publish week, two days after the sibling spoke's 2026-10-27 slot, keeping spacing between arc spokes; other unwritten arc children such as #10636's post may claim nearby slots). If the operator wants a different slot, filename + frontmatter date + redirect-pair key move together (plan AC11); the post is live on merge regardless of the date field |
| Final title — brief's working title 1 ("A Property Test That Cannot Fail Teaches Nothing") vs title 2 ("We Taught the Agent Property Testing. Its First Example Could Never Fail.") vs a founder-first re-angle per the Blog note | taste | pending - assumed: keep working title 1 as default; the content-writer step may re-angle per the Blog note (unattended runs always re-angle); slug is pinned either way |
| Closing technical link — the post-mortem learning doc vs the shipped property-testing guidance doc (the artifact readers' agents actually consume) | taste | pending - assumed: the learning doc — it is the write-up of record for the post-mortem (fix commits, the three anti-vacuity checks); the sibling pattern links the technical source doc, not the shipped feature artifact |
| Scoped advisor consult (plan Step 4.5) and the plan-review panel — both require Task/agent spawns unavailable in this subagent context | technical | pending - assumed: accept the skip — the inline sharp-edges pass plus the pending-assumed rows plus the downstream soleur:review multi-agent stage provide sufficient coverage for a content PR; plan Step 4.5 is advisory by contract and no status: BLOCKED rows remain |
