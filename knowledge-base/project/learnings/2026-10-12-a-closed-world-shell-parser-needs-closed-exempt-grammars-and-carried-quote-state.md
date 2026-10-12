# Learning: a closed-world shell parser needs closed exempt grammars and carried quote state

PR #10110 / issue #10065 (sandbox `/proc` suite parity, tuple battery of 199 rows).

## Problem

The guard parses shell statements to decide which ones may touch `/proc`. Review rounds 1-2 found it fail open in five distinct ways. The five lessons below are one defect class: each exemption or inference was wider than the evidence behind it.

## Solution / Key Insights

1. **A closed-world parser needs closed exempt grammars.** If the parser rejects everything it does not recognise, every exemption must be a closed, enumerated grammar. A free-form "looks like data" exemption reopens the world.
2. **Quote state must carry across lines and `$( )` contexts.** Resetting quote state per line, or entering `$( )` with a fresh state, lets a quoted newline or a nested substitution hide a statement from the scan. Carry one state through the whole script; push and pop it at `$( )` boundaries.
3. **A wrapper allowlist is open-ended.** `env`, `nice`, `timeout`, `xargs`, `sudo -u` and others forward their arguments as a command. Treat any statement that does not lead with a known data verb as a possible wrapper and scan its tail, rather than enumerating wrappers.
4. **Count-from-source wrappers lose arm-deletion pinning.** A test that derives its expected row count from the source (`MIN_ROWS` computed from the arms it finds) passes when an arm is deleted, because the count shrinks with it. Pin the count as a literal (`MIN_ROWS=199`) so deleting an arm turns the suite red.
5. **Capability attribution is inferred, not measured.** Saying "this denial is the AppArmor profile" from the observed errno is an inference. Claim the AppArmor half only after CI runs the profiled docker suite (AC14), not from the unconfined local override.

## Session Errors

1. **Pipeline skills (qa, compound, ship) did not run in the previous session because skills were unavailable.** Recovery: resumed here with `soleur:go`. Prevention: one-off; the handoff recorded the gap and this session ran the steps in order.
2. **PR sat BEHIND main with a CANCELLED/FAILURE-heavy check rollup at resume.** Recovery: ship step syncs main and re-runs CI. Prevention: check `mergeStateStatus` before reading a rollup (a stale rollup after a superseded run reads as failures).

Triage: both one-off; no fix-now or filed items.

## Tags

category: logic-errors
module: sandbox-proc-guard
