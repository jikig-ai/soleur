# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-11-fix-revoke-definer-rpc-residual-grants-plan.md
- Status: complete

### Errors
None. Two stale issue premises re-scoped (test/rls-fuzz/rpc-cases.ts does not exist; harness #6256 still OPEN; ADR-103 citation is wrong). The link-check "BROKEN" flag was decision-challenges.md, a Phase-4 file-to-create, not a broken reference.

### Decisions
- Scope expanded from 1 to 5 functions: sibling audit found the identical revoke-from-public-only defect on 4 concurrency-slot RPCs (acquire/release/touch_conversation_slot + release_slot_on_archive trigger fn). Folded all 5 into one migration.
- Two stale issue premises re-scoped (Phase 0.6): un-baseline test.fails AC converted to cross-ref note (durable guard is verify/128 sentinel); ADR-103 citation flagged wrong.
- Fix shape pinned to canonical repo precedent (migration+verify+down triad of 069_jti_deny_grant_restore). All target RPCs called only via createServiceClient — revoking anon/authenticated is behavior-preserving.
- Threshold = single-user incident (requires_cpo_signoff: true): write-IDOR slot RPCs let one attacker lock out/grief another user.
- Deepen review applied 4 corrections: guarded down migration against re-opening IDOR (P2-1); corrected durability reasoning naming DROP+CREATE re-grant vector with verify/128 guard (P2-2); made ALTER DEFAULT PRIVILEGES root-cause a /ship follow-up (P2-3); fixed inverted Sharp Edge — wrong has_function_privilege signature hard-fails release pipeline under ON_ERROR_STOP=1 (pinned 4-arg acquire signature).

### Components Invoked
- Skill: soleur:plan (#6306)
- Skill: soleur:deepen-plan
- Agent: soleur:engineering:review:data-integrity-guardian
- Agent: soleur:engineering:review:security-sentinel
