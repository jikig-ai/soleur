# Decision Challenges — feat-one-shot-11602-7596-inngest-vector-delivery

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #7596 scope given the emit-leg anomaly (allowlist baked in v1.1.61, identifier never shipped) | technical | Ruled by CTO agent, 2026-10-30: Option A — verification machinery only (probe + Guard A4 + enrollment); the replace is a diagnostic instrument. Blind emit-side edit (B) disqualified — undiagnosed path, unverifiable off-box, contaminates the experiment. Diagnostic-issue-now (C) disqualified — zero added discriminating power. Sharpening: probe discriminates legs (leg_unit/leg_journald/pre_replace); directive maps verdicts to the diagnostic follow-up. |
| Close mechanism for both trackers | technical | Ruled by CTO agent, 2026-10-30: Refs + sweeper-driven measured close (exit-0 contract executes each issue's own acceptance). `Closes` would false-close at merge on zero evidence. earliest= reflects the replace dependency; pre-replace states report TRANSIENT, never FAIL. |
| The `inngest-host-replace` dispatch itself | operator (production-mutating) | Deferred — owner-only, fresh per-command go required (hr-prod-host-config-change-immutable-redeploy); window tracked by epic #10390 bucket 2 and the issues themselves. |
| Daily TRANSIENT comment noise (~30/mo per tracker while pre-replace, no sweeper dedup) | taste | Accepted inline in plan Observability: bounded, reason-strings informative; mitigation = bump `earliest=` to the window date once scheduled. Persisted for ship's `action-required` rendering. |
| MIN_DT floor + `_BOOT_ID` match = two mechanisms for "current generation" | taste | Kept: CTO-ruling sharpening requires positive `_BOOT_ID` resolution for PASS (unresolvable → TRANSIENT `boot_id_unresolvable`); the fallback arm is already spec'd at ~10 lines. If it grows a third arm, drop `_BOOT_ID` per seat note. |
