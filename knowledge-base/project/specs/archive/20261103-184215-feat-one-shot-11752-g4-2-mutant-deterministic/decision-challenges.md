# Decision challenges: feat-one-shot-11752-g4-2-mutant-deterministic

Technical forks ruled by the CTO agent (no operator question asked, per hr-technical-fork-is-not-an-operator-question).

| Item | Class | Ruling |
|------|-------|--------|
| How to make the G4-2 mutant deterministic: (A) forced `tr` shim that drains stdin then `kill -s PIPE $$`, (B) shim that waits for the cs stub's exit by pid polling then execs the real `tr`, (C) sleep-delay shim | technical | Ruled by CTO agent, 2026-11-03: Option A - the shim yields PIPESTATUS `0 0 141 4` by construction; B and C reproduce the kernel SIGPIPE path only through timing or pid polling, which is still a race and adds its own failure mode, and G4-2 needs the pipeline status, not the kernel path. |
| Fold the forced run into `pred_early_exit_rc` or add a separate predicate | technical | Ruled by CTO agent, 2026-11-03: fold in, after the 20 natural-race runs - the assertion count stays exactly 158 and the existing pristine `assert_true` remains the must-PASS partner of the G4-2 `expect_red`. |
| Shim scope and bookkeeping constraints | technical | Ruled by CTO agent, 2026-11-03: gate the shim on argv exactly `-d \n` and `exec` the real `tr` by absolute path otherwise (the script also runs `tr` at inngest-cutover-flip.sh:258 and :590); the shim touches a marker file and a missing marker counts as `bad` (no vacuous pristine pass); add a `PRODUCER_JOIN` `exempt` `deliberate-fault` row for (suite, tr) in .claude/hooks/grep-q-pipe-guard.test.sh and bump `PJ_TRIPLES` (317 to the measured value). |
