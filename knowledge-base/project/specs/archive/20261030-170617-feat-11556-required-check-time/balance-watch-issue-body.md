Deferred from #11556 during brainstorm on 2026-10-29 (Productize Candidate `ci-shard-balance-watch`).

Mandated-By: wg-when-deferring-a-capability-create-a

## What was deferred

A scheduled probe or required ratchet that flags `suite-shard-legs.tsv` drift before it becomes a 50-min leg: specifically **floor-priced or never-measured manifest rows above a cost bound** (the `ci-pr-affected-replay` failure mode — priced 1.2 s floor, measured 24.9 min), and optionally a leg-balance assertion vs the committed `suite-durations.tsv`. The `ci-leg-balance-9232` daily sweep closed 2026-09-30; nothing sweeps drift today — regen is manual per `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.

## Why deferred

Out of scope for the Lever-A slice (#11562): adding scheduled machinery inherits the bot-PR/synthetic-checks surface and inflates the PR. The slice ships the surgery + a manual `--runs 5` regen; recurrence prevention is a separate, smaller change once the surgery proves the shape.

## Re-evaluation criteria

If a floor-priced suite > ~5 min lands twice more, or after the Lever-A slice ships and one manual regen cadence has been observed — whichever first. Machinery class; likely an advisory scheduled workflow first, ratchet second. Epic: #11556. Brainstorm: `knowledge-base/project/brainstorms/2026-10-29-required-check-time-brainstorm.md`.
