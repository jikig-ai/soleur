# Decision challenges — feat-one-shot-10003-egress-gw-tcp-open-retry

Taste calls surfaced by plan-review (headless run; not auto-applied). Each keeps the plan's current choice unless the operator redirects.

1. **Inline `gw_diag` vs separate function (taste).** Simplicity review: inlining saves about 6 lines and one extraction check. Plan keeps the split so the diagnostics are one named, separately extractable unit. Alternative: inline and extract only `wait_for_gw_tcp`.
2. **Avoid the `discoverability_test.credentials_required` declaration (taste).** DHH/simplicity: the declaration forces a `BASELINE_DECLARED_PROBES` bump in an unrelated bun suite. Plan keeps the Better Stack probe (the only honest read of `egress_gw_probe`) and takes the mechanical bump. Alternative: declare a local probe that verifies code, not deployed state.
3. **Test-apparatus size (taste).** DHH/CTO/simplicity: the original 8-row mutation matrix, 3 harness rows, rollback simulation and 4 neighbour-suite runs exceeded the 25-line fix. Plan cut to 5 mutations, 2 harness rows, no rollback simulation, 2 neighbour suites. Remaining ritual (PR-body matrix lines, claims ledger) is retained because the operator's brief asks for falsification of comment sentences and the repo's guard-contract gate requires a matrix.
4. **Post-merge owner (strategy).** CTO: nobody is armed to run post-merge verification if the session ends. Plan names the same-session ship post-merge phase as owner with a handoff comment on #10003 as fallback. Alternative: enroll a follow-through tracker.
