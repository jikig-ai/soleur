# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-05-fix-cross-pipeline-web-1-swap-serialization-plan.md
- Status: complete

### Errors
None. CWD verified on first tool call. All deepen-plan halt gates passed; all cited PR/issue numbers (#6060 OPEN, #6051/#6040/#5966 CLOSED, #3220 OPEN) and AGENTS.md rule IDs verified live.

### Decisions
- Scope: #6060 is a 3-item deferred-hardening tracker. Implement only item (c) (cross-pipeline web-1-swap serialization) now; formally defer (a) and (b) with sharpened inline triage. `Ref #6060` (not `Closes`); tracker stays open for (a)/(b).
- Design pivot (Fable consult): replaced first-draft runs-API polling gate with a job-level shared `web-1-swap` concurrency group — atomic (no TOCTOU), bidirectional, queue-not-fail, zero custom code.
- P1 completeness fix (architecture-strategist): the premise was "three swap jobs" — there are four. `apply-deploy-pipeline-fix.yml`'s `apply` job also swaps web-1 and was unserialized. Corrected to a 4-member group with an allow-list drift guard; added the lock-hold-duration invariant (P2) to the ADR.
- Verified harm (spec-flow): primary harm is a `lock_contention` RED release (Verify step has no `exit_code=1` case) + web-1 tag-downgrade, not merely the transient 521.
- Threshold downgrade (code-simplicity): `single-user incident` → `aggregate pattern`; cut a LARP AC and an internals-coupling grep.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: 3x Explore, spec-flow-analyzer, architecture-strategist, code-simplicity-reviewer, claude (fable)
- Tools: WebFetch, gh/git/grep
