# Decision Challenges — feat-one-shot-11607-11609-11583-sibling-probes

Headless one-shot pipeline (no TTY, no agent-spawn tool in the Devin planning
subagent). `Reviewed-Coverage: sequential-fallback` — gates that prescribe
spawned agents (advisor consult, domain leaders, plan-review panel, functional
discovery, spec-flow analyzer) were adjudicated sequentially inline by the
planning orchestrator.

## Mechanism adoptions (not rulings)

The design carries no open technical fork. Every load-bearing choice is either
prescribed verbatim by issue #11607's own fix-shape sketch or forced by the
semantics each probe already implements — recording them as challenges would
manufacture discretion that does not exist:

- Region-slice anchor (`##[group]Run` header `ts >= started_at[0:19]`, EOF or
  next-header bound, global BOM/CR strip): prescribed by the issue and proven
  twice on `origin/main` (`git-data-boot-poll-8178.sh:202-209`,
  `web-first-deploy-10585.sh` post-26ec69c3).
- `startedAt` (camelCase) extraction from `gh run view --json jobs` for both
  siblings: forced by their existing jobs source — neither uses the REST
  `gh api …/jobs` call the 10585 probe consumes.
- Job-name field-1 pre-filter inside the rehearsal `step_region`: forced by
  the collector's whole-run logs (multiple job sections per file); the only
  new mechanism vs either prior port, and the alternative (unscoped slice)
  can open a sibling job's region.
- Re-attribution into `<job>\t<step>\t<ts> <content>` region files consumed by
  the unchanged `lcount`/`lfirst`/refs awks: the rehearsal script's own
  failed-read-≠-zero contract forces it — a divergent second parse grammar
  would be the drift vector, not an option.
- Tripwire wording `TRANSIENT:` in the zot probe: the probe's own exit
  vocabulary (`:27`), a compatibility constraint, not a choice.
- `tr -d '\357\273\277'` rejected for file normalization (deletes the three
  bytes independently; corrupts other UTF-8): bash `${var//…/}` or `sed -i`
  exact-sequence only.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Zot probe is dormant (tracker #8651 closed 2026-09-30, past 14-day closed-lookback; no open tracker enrolls it) — fix it anyway vs retire it | technical | Ruled by CTO agent, 2026-11-01: port anyway - #11607 names the script verbatim and dormancy sharpens rather than removes the case (any re-enrollment faces a newest web-2 run already inside the expired window); retire/delete is operator scope, not a technical fork |
| Rehearsal collector failure semantics on unrecoverable attribution-expired logs — silent zero (pre-change) vs UNREAD (this plan) | technical | Ruled by CTO agent, 2026-11-01: UNREAD(token) on unrecoverable attribution-expired logs, never silent zero - the script's own header contract ("a failed read and a zero count are different facts, and this script never prints a zero for a read that did not run", `:43-44`) resolves it; pre-change it could certify `unwound no` on readings never made |
| Zot tripwire scope — success-conclusion jobs only vs all jobs | technical | Ruled by CTO agent, 2026-11-01: success-conclusion jobs only - mirrors the merged 10585 precedent (`web-first-deploy-10585.sh:342`); a failure job already surfaces red and its unrecoverable trail keeps the stated best-effort `continue` residual; recovery itself stays conclusion-agnostic |
| #11609 discharged by `Closes #11609` in the PR body (no code change) | operator (scope) | Prescribed verbatim by the operator's batch brief; not a decision |
| #11583 carried as context only — never `Closes` | operator (scope) | Prescribed verbatim by the operator's batch brief + the issue body itself ("don't close it") |
