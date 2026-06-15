# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md
- Status: complete

### Errors
None. CWD verified; deepen-plan halt gates 4.6/4.7/4.8 passed; 4.9 UI-gate no-op (no UI surface).

### Decisions
- Root cause (live-reproduced against dev-Supabase): dev-env schema-vs-ledger DRIFT, not a code bug on main. Orphan unmerged migration `104_routine_runs.sql` (open WIP PR #5342 feat-routines-management) applied to dev at 14:02 UTC via ALLOW_UNMERGED_DEV_APPLY=1. Its `routine_runs` WORM `no_update` trigger contradicts its `ON DELETE SET NULL` FK to `users` → every auth.users delete cascade trips `P0001: routine_runs is append-only (WORM)`, surfacing as GoTrue 500 unexpected_failure.
- Corrected the one-shot ARGUMENTS premise: "bisect merged migrations" cannot find it (culprit is on an open PR, never merged); FK is SET NULL (not missing ON DELETE); a fix migration on main is wrong (main schema is correct).
- Fix shape: (1) revert dev orphan via idempotent script, (2) escalate drift gate to BLOCKING on push:main only (warn on PR), (3) regression test asserting minimal-user deletability, (4) main-side Art-17 fold-in: `denied_jti.founder_id ON DELETE RESTRICT` un-handled by cascade, (5) cross-PR follow-through to fix WORM-vs-SET-NULL in PR #5342.
- Brand-survival threshold = single-user incident (GDPR Art-17); requires_cpo_signoff: true.
- Code-review overlap: #3370 acknowledged (same drift family), #3364 deferred (orthogonal).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agents: general-purpose ×2 (root-cause), general-purpose/sonnet ×1 (deepen-plan verify)
