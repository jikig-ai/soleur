# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-docs-runbook-ejections-residual-plan.md
- Status: complete (plan + deepen run by planning subagent; sequential-fallback — child skills and CTO lens ran inline in the subagent)

### Errors
- `gh pr view 12377 --json merged` failed (field is `mergedAt`/`state: MERGED`) — retried; #12377 confirmed merged 2026-11-08T17:35:29Z.
- `collision-precheck.sh 12428` hit was PR #12430 — the auto-draft on this branch, not a foreign duplicate.
- `markdown-lint.sh` reported new artifacts "not in scope" (untracked by design); verified via pinned `node_modules/.bin/markdownlint`.
- First Enhancement Summary edit consumed the `## Research Insights` heading — restored; plan re-verified.

### Decisions
- Ledger scope: criterion-a alone, b/c/d named `unmeasured`, re-ruling operator-reserved (Ruled by CTO agent inline, 2026-11-08).
- §4 placement: sibling bullet — window-listing residual is a different class than the per-sha `?head_sha=` read.
- Issue disposition: `Ref #12428`, issue stays OPEN — pipeline-runner amendment of the subagent's `Closes` ruling: the issue's deferred item is the corroboration build or budget-owner acceptance, not the record; #10949 precedent keeps ruled-residual trackers open until criteria fire.
- Bound attribution: not-evaluable bucket (58/382), `runs_via=head-sha` 300/300 — classifier coverage is the fix, not more reads.
- Sequential-fallback: planning research, deepen gates, review lenses and CTO rulings all ran inline; `Reviewed-Coverage: sequential-fallback` disclosed in the PR body.

### Components Invoked
soleur:plan (subagent, inline), soleur:deepen-plan (subagent, inline gates), CTO lens (inline), collision-precheck, markdownlint, technical-ruling-gate, pr-overlap-preflight, pipeline-tally

## Operator Constraints
- The 2026-11-07 budget-owner go-ahead covered only the #10862 criterion-a evidence re-run; it does NOT authorize the go/no-go re-ruling, criteria b/c/d measurement, `CI_PR_AFFECTED` activation, or ruleset changes — those stay operator-owned (ADR-276).
- This run is docs-only: runbook prose recording the re-run evidence and the ejections-listing residual. It authorizes nothing beyond the edit itself.

## Review/Compound Phase
- Review: 4-seat non-code panel (git-history, pattern-recognition, security-sentinel, code-quality) as report-only subagents + consolidated fix-round verifier. FIX-ROUND: PASS.
- Findings: 1 P2 (re-run provenance — ran inside #12377, not "after ship") + 5 P3, all fixed inline (`5d89f596f1`).
- Compound assessment: the P2 class (inherited provenance phrasing; in-PR evidence vs post-merge verification — "shipped" means merged in runbook vocabulary) is already covered by `learnings/2026-09-18-three-sentences-i-pasted-from-the-plan-were-inherited-not-measured.md`; no new learning/rule — the constraint was discovered via a visible review finding (discoverability exit).
- QA: docs-only — AC1–AC6 greps + markdown-lint all green post-fix.
- Ship: #12428 filed as residual tracker (stays OPEN); PR #12430 ready, auto-merge armed, merge queue.
