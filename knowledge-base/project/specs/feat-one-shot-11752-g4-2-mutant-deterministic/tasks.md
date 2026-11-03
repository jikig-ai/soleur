# Tasks: feat-one-shot-11752-g4-2-mutant-deterministic

Plan: knowledge-base/project/plans/2026-11-03-fix-g4-2-mutant-deterministic-sigpipe-plan.md (Ref #11752 only)

## Phase 0 Baseline
- 0.1 Reproduce: run apps/web-platform/infra/inngest-luks-key-probe.test.sh once (expect rc=1, 157 vs 158)
- 0.2 Run .claude/hooks/grep-q-pipe-guard.test.sh on the unedited tree (green baseline)

## Phase 1 Forced SIGPIPE run
- 1.1 In pred_early_exit_rc, after the 20-run loop, add the argv-gated tr shim (drain, kill -s PIPE $$; else exec absolute real tr)
- 1.2 Add the tr-fired marker check (missing marker counts as bad) and the pristine summary check
- 1.3 Reword the stub comment (~line 127) and the pristine assertion description; leave EXPECTED_ASSERTIONS=158 and the G4-2 expect_red text unchanged
- 1.4 Cat the generated shim once to confirm the `-d \n` gate text

## Phase 2 Bookkeeping ratchet
- 2.1 Run grep-q-pipe-guard.test.sh, read the unlisted-pair FAIL
- 2.2 Add the PRODUCER_JOIN exempt deliberate-fault row for (suite, tr)
- 2.3 Recompute and set PJ_TRIPLES, extend its comment
- 2.4 Run plugins/soleur/test/fixture-relative-assert.test.sh; regenerate baseline only on a delta

## Phase 3 Proof (one suite at a time)
- 3.1 Five sequential green runs of the suite (158 passed), keep the G4-2 RED line and the pristine early-exit line from each
- 3.2 One run with PROBE_SUITE_TARGET at a scratch mutant (0:0:141 removed): pristine early-exit row must FAIL
- 3.3 Scratch checks M4 (gate broken) and M5 (no drain) read RED

## Phase 4 Ship
- 4.1 Commit, push, wait for CI (deploy-script-tests 2/4); PR body Ref #11752 only
- 4.2 After merge verify main CI green, then close #11752 against its re-evaluation trigger
