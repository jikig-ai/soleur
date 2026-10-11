# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-11-feat-arm-heartbeats-status-and-arm-one-plan.md
- Status: complete

### Errors
- Issue names plugins/soleur/scripts/arm-heartbeats.sh; real path is apps/web-platform/infra/arm-heartbeats.sh (noted in plan; mention in PR body).
- Live field shapes (paused vs paused_at, period, grace) never read live by this repo; resolver refuses to arm if period/grace missing. Owner's first --status run is the first live read.

### Decisions
- id override is an optional 4th positional parameter on arm_one; six per-merge call lines and the inngest block stay byte-identical.
- Resolver: exact name, paginate via pagination.next under pinned base (cap 20 pages), every page needs a .data array, \x1f delimiter, no de-dup of matches, --id is the independent anchor.
- --arm-one: fixed 150 s deadline (ceiling period+grace-40), private mktemp books file, sweep recovery command printed before first PATCH; rc 0 armed/no-op, 1 refused/failed, 2 no beat and rolled back.
- Tests ST*/AO* with mutation rows M22-M33; ASSERT_FLOOR ratchet; terraform-target-parity bs_api count pin 2 to 3.
- Runbook step 7 gets doppler run invocations; ADR-117 amended; PR Closes #9980, Refs #9438; no workflow edits, no production call.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan
