# Session state — web-2 LUKS rebirth workflow (#9372)

## Plan phase
- Plan: knowledge-base/project/plans/2026-10-05-feat-web2-luks-rebirth-workflow-plan.md (the planning subagent returned nothing; `soleur:plan` ran inline).
- Rulings: CTO (shape, two graded plans, pins, crash windows, no refusal to format on missing escrow, flip precondition, emptiness rules), CPO (APPROVE-WITH-CONDITIONS, ten conditions folded in), CLO (NO LEGAL BLOCKER with conditions), architecture review (PROCEED-WITH-FIXES, all applied).

### Errors
- The planning subagent returned no plan file (the one-shot fallback ran the plan inline).
- A plan-fix script aborted on an exact-string replace while the same command had already appended a "fixes applied" appendix and committed it, so the appendix briefly described edits that were not applied (fixed in the next commit).
- A process-kill by command-line pattern is blocked by a hook (it self-matches); the background task was stopped by its task id instead.
- A background test run hung because a curl shim read stdin unconditionally (fixed: it reads only when the config arrives on stdin).
- The working directory drifted into a sibling worktree after a `cd` into another PR's worktree (returned; nothing modified there).
- `test-all.sh --affected` was refused as a full-gate run while a sibling worktree ran the full battery (re-run with the TEST_GROUP form).

## Work phase
Offline only: nothing was dispatched, applied, minted or written to Doppler. Delivered: a two-mode plan gate with fixtures, a state classifier, emptiness evidence, a never-pooled reader, a recovery check, an orchestrator script tested against a fake Hetzner/Terraform world, the dispatch-only workflow and its structural/behavioral/mutation suite, the reboot-proof requirement in the marker judge and the follow-through, registrations, a parity pin, a C4 clause, a runbook and an ADR-263 addendum.

## Open for the owner (not blockers of this PR)
- Every dispatch needs the owner's explicit go-ahead (plan_only first).
- The retirement change (delete apply-web-escrow-create.yml, flip the rotation HALT create exemption) must merge before an apply dispatch; the closing checklist is in the runbook and the ADR addendum.
- Decision date 2026-10-15 for the dispatch or an exception extension (the exception expires 2026-10-22).
