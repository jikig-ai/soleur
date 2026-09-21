# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7964-tenant-integration-red/knowledge-base/project/plans/2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md
- Status: complete

### Errors
- Skill tool unavailable in subagent — plan and deepen-plan executed inline from cached SKILL.md files; disclosed via `Reviewed-Coverage: sequential-fallback`.
- Writer-census correction during deepen-plan: scheduled-realtime-probe.yml is a second CI consumer of dev_scheduled (subscribe-only reader, not a writer).

### Decisions
- 2026-09-08 failure mechanism recorded as UNKNOWN; plan fixes the verified open gap (absent cross-ref serialization) plus fail-closed drift detection.
- Mutex: pg_advisory_xact_lock over DATABASE_URL_POOLER; session-lock fallback pinned to DATABASE_URL direct only.
- Deliberate fail-open divergence from the #7553 precedent: proceed-with-banner + fail-closed drift probe (M2) to avoid recreating queue-starvation red.
- Rejected: per-run tenant IDs (in force), repo-wide mutex (infeasible), per-run schema/Supabase branch, auto-revert, run-migrations.sh txn lock.
- New test registers via run_suite in scripts/test-all.sh.

### Components Invoked
- plan skill (inline), deepen-plan skill (inline)
- scripts/lint-guard-contract.py — PASS

## Work Phase (implementation)
- scripts/dev-suite-mutex.sh: acquire/release/probe; pg_advisory_xact_lock over DATABASE_URL_POOLER, session-scoped pg_advisory_lock over DATABASE_URL only (coupling is structural — session mode unreachable while pooler set). Banners: WAITING/ACQUIRED/CONTENDED_PROCEEDING/RELEASED/UNAVAILABLE/HELD_BY/FREE.
- tests/scripts/test-dev-suite-mutex.sh: stub-psql suite, 32 assertions; mutation-verified (lock-call removal -> 12 FAILs; marker-check removal -> 7 FAILs). Registered in scripts/test-all.sh.
- Positive control vs dev pooler (doppler soleur/dev_scheduled): session A ACQUIRED after 750ms mode=xact; session B WAITING -> CONTENDED_PROCEEDING after 3s budget. NOTE: holder identity reports 'Supavisor' — transaction-mode pooling masks client PGAPPNAME; banner still proves a holder exists.
- WAITING grace scaled to quarter-budget clamped [250ms,1500ms] — a free acquire pays ~750ms connect latency which must not masquerade as contention.
- dev-migration-drift-probe/action.yml: new fail-on-ledger-drift input; ledger probe severity switches warning->error + exit 1. YAML parsed; both run: blocks bash -n clean.
- tenant-integration.yml: Acquire step before drift probe; Release step if:always() at job end (local-only, no Doppler); fail-on-rpc-body-drift + fail-on-ledger-drift = github.event_name != 'pull_request'; detect-changes anchors extended with scripts/dev-suite-mutex.sh + .github/actions/dev-migration-drift-probe/.
- actionlint tenant-integration.yml: clean. Fixture ratchets (cd-containment/operand/relative): all pass, P1a baseline unchanged at 9. lint-guard-contract: 28/0.
