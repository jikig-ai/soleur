# Decision challenges — feat-one-shot-8210-git-data-boot-reopen

Headless plan-review (2026-09-18). Taste findings surfaced here, not auto-applied (ADR-084). `ship` Phase 6 renders these into the PR body and files the `action-required` issue.

## T1 — Fifth `boot_complete` boolean: TERMINAL (chosen) vs reported-only

- **Source:** code-simplicity-reviewer (P1-3) argued `luks_reopen_unit` is a third belt for one fact (the arm-item WARNING emit + the rehearsal reset arm) and should be at most a projected tag like `nft_metadata_drop`, with zero reader edits.
- **Planner's default:** keep it TERMINAL in both readers. The reset arm runs only in rehearsals; on the LIVE host the `git-data-host-replace` boot-signal poll is the only reader that can FAIL on an unarmed unit, and a WARNING emit is not read by any poll. Cost: the reader sweep (8 touch points, all one-token edits) — Phase 3.2.
- **If the operator prefers reported-only:** drop Phase 3.2 except the emit tag + `git-data-emit.test.sh` roster; delete Guard 3 M2/M3; accept that an unarmed unit on a replaced live host is an email warning, not a poll FAIL.

## T2 — Payload-queue cadence: one rehearsal + one replace after the LAST payload PR

- **Source:** CTO devex (P2-5). #8101 and #8211 will each re-hold the rung-2 gate; each rehearsal now costs ~40 min + an environment approval + a reset; each replace destroys/recreates the host.
- **Planner's default:** recorded as a cadence NOTE on PM1 (not a scope change): if #8101/#8211 are about to merge, run PM1/PM2/PM4 once after the last of them; a held gate in between is the safe state because the store is not user-enabled. If the operator wants THIS fix on the live host sooner, dispatch PM1 in the merging session as written.

## T3 — Shared roster lib for the boolean vocabulary (declined)

- **Source:** CTO devex (P1-4) proposed `scripts/lib/git-data-boot-booleans.sh` as the single source both readers derive their loop/regex/projection from.
- **Planner's default:** declined as new mechanism; the existing AC30-parity check in `git-data-emit.test.sh` is the single source that REDs when the producer and a roster disagree, and the two readers' SQL projections are one column each. Revisit when a SIXTH boolean lands (#8101/#8211).
