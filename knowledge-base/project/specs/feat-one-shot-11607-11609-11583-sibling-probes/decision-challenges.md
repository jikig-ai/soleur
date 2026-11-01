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
| Zot probe is dormant (tracker #8651 closed 2026-09-30, past 14-day closed-lookback; no open tracker enrolls it) — fix it anyway vs retire it | technical | ruled inline — port anyway: #11607 names it for the fix, the script documents #8651's evidence contract, and the recovery is the only way it can ever grade its (already-aged) newest web-2 run on re-enrollment. A "delete instead" proposal would be operator scope anyway |
| Rehearsal collector failure semantics on unrecoverable attribution-expired logs — silent zero (pre-change) vs UNREAD (this plan) | technical | ruled inline — UNREAD: the script's own header contract ("never prints a zero for a read that did not run", `:43-44`) resolves it; no fork |
| Zot tripwire scope — success-conclusion jobs only vs all jobs | technical | ruled inline — success-only, mirroring 10585: a failure job's unreadable trail keeps the best-effort `continue` posture (carried residual, stated) |
| #11609 discharged by `Closes #11609` in the PR body (no code change) | — | prescribed verbatim by the batch brief; not a decision |
| #11583 carried as context only — never `Closes` | — | prescribed verbatim by the batch brief + the issue body itself ("don't close it") |
