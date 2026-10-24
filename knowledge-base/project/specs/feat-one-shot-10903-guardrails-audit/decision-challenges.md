# Decision challenges — feat-one-shot-10903-guardrails-audit

Plan: `knowledge-base/project/plans/2026-10-24-content-guardrail-audit-spoke-plan.md`
Context: one-shot pipeline plan phase on Devin CLI subagent — no Agent/Task tool, so
technical rulings are recorded as `pending - assumed:` defaults per the pipeline's
technical-ruling convention, and no named review panel could be spawned (self-review only).

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Publish date / filename date for the spoke post — the brief says "blog scheduled (not with-merge); slot AFTER the arc synthesis (#10902) publishes" but names no date | operator (schedule) | pending - assumed: 2026-10-27 (first Tue-Thu day of the arc's publish week; arc post file already on main). If the operator wants a different slot, filename + frontmatter date + redirect-pair key move together (plan AC11); note the post is live on merge regardless of the date field |
| Final title — brief's working title 1 ("We Audited 102 Guardrails. Only Four Belong in Every Repository.") vs a founder-first re-angle per the Blog note ("title names the founder's problem or the outcome") | taste | pending - assumed: keep the brief's working title 1 as default; the content-writer step may re-angle per the Blog note (unattended runs always re-angle); slug is pinned either way |
| Census figure to publish — brief pins 102; audit doc on main tallies 57 hooks + 47 lints = 104 today (two members landed post-census: commit-target-roots.sh 2026-10-22, lint-hcloud-token-readonly-no-fallback.sh 2026-10-23); doc's hooks header still reads "56 files" against its own 57-row table | technical | pending - assumed: publish the dated census (102 at 2026-10-21) — matches the fact-check pin and the already-published arc post; audit-doc header nit (56 vs 57 rows) is a pre-existing main defect, out of scope for a content PR |
| pillar: series membership — declare `pillar: billion-dollar-solo-founder` only, or also append a members[] row in `_data/pillars.js` | technical | pending - assumed: declare the key only — the arc post sets the precedent (declares the key, no member row); adding a member row is a series-edit decision, not this PR's |
| Scoped advisor consult (plan Step 4.5) and plan-review panel — both require Task/agent spawns | technical | pending - assumed: skipped; no Agent tool in this Devin subagent context. Self-review pass applied the sharp-edges catalogue inline; residual risk noted for the parent pipeline (review skill still runs at its own stage) |
