# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-27-feat-git-data-cutover-proof-on-luks-mapper-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None

### Decisions
- Scope is the proof half of #8211 PR2; flip/rollback/redeploy/startup-line/D6 replace stay on #8211 (blocked on #8209, #5914, #8572, #8573). PR uses `Ref #8211`; split recorded in an ADR-239 amendment.
- `refuse_if_cut_over` inverts to `refuse_if_not_on_mapper` (`store_not_on_mapper`); new single-session `store-verified` probe (source re-check, non-empty FS UUID, `/etc/git-data/store-verified` bound to that UUID, `.cutover-freeze` absent) before the existing count and fence probes.
- Separate `dmsetup` LUKS2 check cut (DC-1 in decision-challenges.md); freeze probe kept (DC-2).
- Step 5.2 discharge fail-closed on a three-part chain (clear run, `boot_complete plaintext_empty=yes`, Doppler flag history).
- Suite floors move to exact `-ne`; RB script↔runbook coverage check; ADR-220 amendment entry; post-merge docs PR (PM4).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, learnings-researcher, git-history-analyzer, cto, clo, cpo, spec-flow-analyzer, dhh/kieran/code-simplicity/architecture reviewers, security-sentinel, test-design-reviewer, observability-coverage-reviewer, user-impact-reviewer
