# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7964-tenant-integration-red/knowledge-base/project/plans/2026-09-21-fix-tenant-integration-shared-fixture-contention-plan.md
- Status: complete

### Errors
- Skill tool unavailable in subagent — plan and deepen-plan executed inline from cached SKILL.md files; disclosed via `Reviewed-Coverage: sequential-fallback`.
- Writer-census correction during deepen-plan: scheduled-realtime-probe.yml is a second CI consumer of dev_scheduled (subscribe-only reader, not a writer).

### Decisions
- 2026-09-08 failure mechanism recorded as UNKNOWN; plan fixes the verified open gap (absent cross-ref serialization) plus fail-closed drift detection.
- Mutex: pg_advisory_xact_lock over DATABASE_URL_POOLER; session-lock fallback pinned to DATABASE_URL direct only. (Superseded in review phase — session arm collapsed to always-xact.)
- Deliberate fail-open divergence from the #7553 precedent: proceed-with-banner + fail-closed drift probe (M2) to avoid recreating queue-starvation red.
- Rejected: per-run tenant IDs (in force), repo-wide mutex (infeasible), per-run schema/Supabase branch, auto-revert, run-migrations.sh txn lock.
- New test registers via run_suite in scripts/test-all.sh.

### Components Invoked
- plan skill (inline), deepen-plan skill (inline)
- scripts/lint-guard-contract.py — PASS

## Work Phase (implementation)
- scripts/dev-suite-mutex.sh: acquire/release/probe; pg_advisory_xact_lock over DATABASE_URL_POOLER (session-scoped arm later collapsed in review — always-xact). Banners: WAITING/ACQUIRED/CONTENDED_PROCEEDING/RELEASED/UNAVAILABLE/HELD_BY/FREE/HOLDER_LOST/RELEASE_FAILED.
- tests/scripts/test-dev-suite-mutex.sh: stub-psql suite, 32 assertions; mutation-verified (lock-call removal -> 12 FAILs; marker-check removal -> 7 FAILs). Registered in scripts/test-all.sh.
- Positive control vs dev pooler (doppler soleur/dev_scheduled): session A ACQUIRED after 750ms mode=xact; session B WAITING -> CONTENDED_PROCEEDING after 3s budget. NOTE: holder identity reports 'Supavisor' — transaction-mode pooling masks client PGAPPNAME; banner still proves a holder exists.
- WAITING grace scaled to quarter-budget clamped [250ms,1500ms] — a free acquire pays ~750ms connect latency which must not masquerade as contention.
- dev-migration-drift-probe/action.yml: new fail-on-ledger-drift input; ledger probe severity switches warning->error + exit 1. YAML parsed; both run: blocks bash -n clean.
- tenant-integration.yml: Acquire step before drift probe; Release step if:always() at job end (local-only, no Doppler); fail-on-rpc-body-drift + fail-on-ledger-drift = github.event_name != 'pull_request'; detect-changes anchors extended with scripts/dev-suite-mutex.sh + .github/actions/dev-migration-drift-probe/.
- actionlint tenant-integration.yml: clean. Fixture ratchets (cd-containment/operand/relative): all pass, P1a baseline unchanged at 9. lint-guard-contract: 28/0.

## Review Phase (post-panel fixes)
- 11-lens panel (2 design + 7 code + test-design + structural-enum): no P1 on mechanism; convergent P2s fixed inline:
  - Session-lock arm COLLAPSED to always-xact (simplicity dissent) — the :6543 session-over-pooler refusal is gone because the leak class is now unexpressible.
  - WAIT_S 240 -> 180: full-budget wait + ~2-3min setup vs timeout-minutes:15 left a 5-9min section unfinishable (performance+architecture convergence).
  - hashtext -> hashtextextended(name, 0) (repo precedent: migs 029/093/116/133); pg_locks classid/objid decomposition updated to the int8 high/low words.
  - SET LOCAL application_name = '<identity>' added inside the holder txn — server-side GUC survives the Supavisor startup-packet mask (best-effort attribution restore).
  - Identity now charset-normalized to [A-Za-z0-9._/-] (space/quote smuggling into banner fields + SQL literal closed).
  - STATE_DIR local fallback -> local-$PPID (two concurrent local/agent sessions no longer share `local` and kill each other's holder).
  - is_our_holder fails SAFE: unreadable /proc falls back to `ps -o args=`, unverifiable -> never signalled.
  - release() now assert_fixture_dir-guards STATE_DIR before rm -f; deadline path TERM->grace->KILL (no unbounded wait).
  - CONTENDED next= points at `gh run list` (concurrent-run attribution), not the pooler-masked probe.
- Drift probe fail-closed completed: under fail-on-ledger-drift/fail-on-rpc-body-drift, "cannot measure" (psql failure, git fetch failure, missing marker JSON) is now ::error:: + exit 1 — the flag reaches the probe's own failure paths, not just measured drift.
- scheduled-dev-migration-drift.yml now forwards fail-on-ledger-drift: 'true' (its 'warning-only' header was already stale — rpc-body drift already fails loud there).
- tenant-integration.yml: fail-on-* scoped to `event_name == 'push' || (workflow_dispatch && ref == main)` (dispatch on a feature branch no longer reds on drift it didn't cause); identity run_id-first; post-section re-probe added under if: always() inside the mutex window (attributes drift to the run that produced it).
- tests/scripts/test-dev-suite-mutex.sh -> 54 assertions: DISABLE valve, refused/unwritable STATE_DIR, holder_exited, probe-failure fallthrough + query_failed, both HOLDER_LOST arms, WAIT_S coercion, hostile-identity sanitize, unknown-subcommand, ON_ERROR_STOP + timeout-pin + SET LOCAL assertions, chunked-sleep shape pin; stub gained STUB_FAIL=connect|probe and STUB_DIE arms + ARGV logging.
- tests/scripts/test-dev-suite-mutex-wiring.sh (new, 13 assertions): acquire/release wiring, if:always(), no-doppler release, section ordering, detect-changes anchors, HOLD_S>timeout + WAIT_S margin as arithmetic, run_id-first, fail-on-ledger-drift on both probes + scheduled cron.

## Coverage-consult fix (post-panel)
- P1-class gap the panel missed: a single pg_sleep(HOLD_S) parks the backend in a latch wait that never touches the client socket — killing the holder would NOT release the lock until the sleep ended (~19.5min zombie hold). Fixed: holder SQL emits chunked pg_sleep(10) statements + a remainder, so each statement boundary forces a result write; the first write to a dead socket EPIPEs and aborts the transaction (~10-20s release latency).
- Hardening: probe psql calls bounded (PGCONNECT_TIMEOUT=10 + timeout 120, -w) and git fetch bounded (timeout 60) — a stalled call inside the mutex window extends the hold for all waiters; marker-map jq validity guarded under fail-closed.
- Live-verification recipe (needs dev creds): `doppler run -p soleur -c dev_scheduled -- bash scripts/dev-suite-mutex.sh acquire` then `kill -9 $(cat $STATE_DIR/holder.pid)` and poll `psql $DATABASE_URL -c "SELECT count(*) FROM pg_locks WHERE locktype='advisory'"` — the lock row must disappear within ~10-20s.
