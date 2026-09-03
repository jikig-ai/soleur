---
title: I built a host discriminator out of an absence, and then fixtured the absence
date: 2026-09-02
category: logic-errors
module: apps/web-platform/infra
issues: [7695, 7674, 7761]
pr: 7754
related:
  - 2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md
  - 2026-08-20-every-instrument-i-checked-my-own-work-with-was-broken.md
  - 2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md
---

# I built a host discriminator out of an absence, and then fixtured the absence

## Problem

`#7695` Merge A extends `SOLEUR_INNGEST_SERVER_PROBE` with the store facts a future Guard 2
reads before clearing a **destructive** volume recut. The degradation direction is inverted
against every other probe in this repo: Guard 2 clears the destroy on a *measured-empty* store,
so `0` is the **clearance condition**. A field that degrades to `0` authorizes the destroy it
exists to withhold. That is the whole reason the two-token vocabulary — `n/a` (does not apply on
this host) and `__UNREADABLE__` (applied, unanswerable) — exists.

`inngest-bootstrap.sh` is the **shared** renderer for the dedicated inngest host and the
co-located web host, so the new fields had to be scoped to the dedicated host at runtime. I
scoped them on *"is `/mnt/data` a mountpoint"* and wrote the premise into the comment: the web
host has no `/mnt/data`.

It does. `cloud-init.yml` (the `mkdir -p /mnt/data` / `scsi-0HC_Volume_${workspaces_volume_id}`
fstab line / `mount /mnt/data` runcmd trio) mounts the **workspaces** volume there. So on web-1
the test was true, and the probe would have walked every user's repository tree hourly, shipped
the aggregate byte count off-box, and emitted a store measurement from the wrong host into the
clearance condition for a destroy.

## Solution

Four changes, in `apps/web-platform/infra/inngest-bootstrap.sh` and its suite. The delivery
deviations are recorded as a dated addendum on the plan
(`knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md`, `## Addendum
— 2026-09-02 (#7695, Merge A as delivered)`) — read that for what Merge B must decide.

1. **The role test is now a positive identity assertion**, not an absence: `DOPPLER_PROJECT ==
   soleur-inngest`, this codebase's canonical dedicated-vs-web discriminator, reaching the unit
   via `EnvironmentFile=-/etc/default/inngest-server`. `host_role` is itself emitted, so the
   consumer can *require* a self-identifying row rather than infer the host from `instance_id`.
2. **`redis_keys` is not shipped at all.** It could never authenticate in production (redis runs
   `--requirepass`; the probe unit carries no credential), and the fix was unavailable to this
   merge: supplying it means `doppler run`, but `/usr/bin/doppler` is a symlink created only by
   `cloud-init-inngest.yml`, so the shared unit would have failed `203/EXEC` on the web host and
   silently ended the hourly liveness marker on the host that actually serves. `latch_flushed_at`
   and `latch_lines` went with it — no consumer, and `latch_lines` degraded to `0` on the
   not-latched path.
3. **`flush_latched` inherits `data_bytes`' unreadability.** `[ -f ]` cannot report failure: it
   returns false for "absent" and for "cannot read the directory" alike. `findmnt` reads
   `/proc/self/mountinfo`, not the device, so a Hetzner volume detached while still mounted
   leaves the mount entry standing and every read gives EIO — a bare test would have emitted
   `flush_latched=false`, a positive claim about a store never read. `du` *does* report failure,
   so the silent field is keyed off the loud one.
4. **Every pre-emit call is bounded** (`timeout 5 findmnt`, `timeout 15 du`) with
   `TimeoutStartSec` raised to cover the budget — a bound that fires degrades one field, a unit
   timeout loses the whole row, and a held `activating` unit blocks `OnUnitActiveSec` from
   re-firing.

Suite: 289/289, floor pinned at the exact dispatched count. Latch suite 45/45.

## Key Insight

**Four insights, each general beyond this subsystem.**

**A discriminator built from an absence discriminates nothing, and its fixture will agree with
it.** The test arm I labelled "the web-host case" ran in a CI sandbox that has no `/mnt/data`. It
proved the *no-mount* case and called it the web-host case. The sandbox lacking the thing is not
a fixture for the host that has it — so the arm validated nothing about web-1 and would have
passed against the exact probe that walks every user's repo tree hourly. The rewritten arm stubs
the mount, the byte count **and** a latch file into existence and changes only `DOPPLER_PROJECT`:
if the discriminator ever stops discriminating, that arm is what goes red.

**A field whose production path is structurally dead while only its fixture seam is tested reads
as covered.** Every `redis_keys` test drove `PROBE_REDIS_CLI_CMD`; production would have taken
the unauthenticated path and read `__UNREADABLE__` forever. The only path the tests exercised and
the only path production takes were disjoint. When Guard 2 later found the field permanently
unreadable, the pressure would have been to relax the gate rather than fix the auth. Ship the
field or drop it; do not half-ship it.

**Assert the value that must never appear, not the token you expect.** The claim this whole
change rests on is *never 0*. Sixteen of twenty-four mutants survived the first 250-assertion
battery, and three of them were literally `__UNREADABLE__` -> `0` — green, because every
assertion asked "is it the token I expect?" and none asked "is it the one value that must never
appear?". Positive expectations are satisfied by the correct answer *and* by any answer the arm
happens not to reach. Negative space is not.

**A floor that dispatches through the counter it protects is not a floor.** The latch suite's
`LATCH_MIN_ASSERTIONS` check called `fail()`; one edit dropping `FAIL=$((FAIL + 1))` made all 45
assertions *and* the floor go green together. `inngest.test.sh` had no floor at all — deleting
the entire new block reported `232/232 passed, 0 failed`, exit 0. Both suites now carry an
instrument self-test upstream of every assertion (drive `pass`/`fail` once each, refuse to
continue unless both counters moved) and report their floors with `printf` + `exit 1` per
ADR-193. This is the second consecutive PR in this subsystem where the instrument, not the
system, was the defect — see
`2026-08-20-every-instrument-i-checked-my-own-work-with-was-broken.md` and
`2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md`.

## Correction — 2026-09-03: the second reason in this learning was itself unverified

Appended, not edited; the body above stands as the record of what I believed.

The "field whose production path is structurally dead" insight is sound and the field genuinely
could not authenticate. But the sentence explaining why the fix was *unavailable* — that supplying
the credential "means `doppler run`", which would `203/EXEC` on the shared web host — is **false**,
and I never read the unit to check it. The probe unit already carries two tolerant
`EnvironmentFile=-` lines and a plain script `ExecStart`; a third one-variable env file touches
nothing else, and `web-probe-envwrite.sh` had already established that exact pattern.

So the learning has a second, sharper version of its own lesson: I correctly identified that a
field's production path was dead, then asserted an unverified structural claim about the remedy
in the same breath — and the remedy claim, not the diagnosis, is what decided the scope. **A
correct diagnosis is what makes the proposed fix go unchecked.** That is the documented
`work/SKILL.md` rule about measuring an issue's prescribed remedy, applied to a remedy I
prescribed myself.

Cost: the claim reached four sites (this file, the plan's §D2, PR #7754's body, and its immutable
commit message) before a CTO review read the unit and refuted it in one grep. Merge B re-adds the
field at `probe_schema=3`. The plan's `## Addendum — 2026-09-03` carries the full reversal.

## Session Errors

**Wrote a load-bearing premise into a comment without running the command that falsifies it.**
"the web host has no `/mnt/data`" — refuted by one `grep` of `cloud-init.yml`. Three review
agents converged on it independently; none of my own gates could, because the fixture agreed with
the premise. **Prevention:** for every causal or universal claim a diff's *prose* adds, name the
command that would falsify it and run it before writing the sentence. Already a review-skill rule;
it needs to fire at authoring time, not only at review time.

**Half-shipped a field whose credential task I did not deliver.** Plan task 1.6 said "add the
Redis credential"; I added the field and not the credential, and the fixture seam hid it.
**Prevention:** when a plan task pairs a *field* with an *enabling capability*, treat the pair as
atomic — if the capability is not delivered, the field does not ship.

**Left three unbounded network/filesystem calls before an unconditional emit** in a script whose
every other capture is bounded and whose own comment explains why. **Prevention:** when adding a
capture to a script that already bounds its captures, copy the bound, not just the shape.

**Put a password on `redis-cli`'s argv**, where `/proc/<pid>/cmdline` exposes it host-wide to the
co-resident `deploy` user, and discarded the stderr that warns about it. Moot now (the call is
gone), but the pattern was being propagated into a second file. **Prevention:** `REDISCLI_AUTH`,
never `-a`. Filed the pre-existing instance as part of #7761's context.

**Mirrored a bit into a second file using a different predicate than the one the consumer uses.**
`emit_state`'s `flush_latched` used `[ -f ]` with no mount gate and without
`flush_already_performed`'s documented "completed before this change shipped" arm, so a host in
terminal `done` would have emitted `{"flag":"done","flush_latched":false}` every 30 seconds — a
self-contradictory row from the source of truth. Reverted; `inngest-cutover-flip.sh` is
byte-identical to `main`. **Prevention:** a mirror calls the predicate; it never re-derives it.

**Reverted a file with `git checkout -- <path>` and then asserted for four commits that it was
byte-identical to `main`.** `git checkout --` restores from the INDEX/HEAD, and the change was
already committed, so it restored the change. The claim went into a commit message, a compound
learning, a review trailer and a filed issue before `git diff --stat origin/main...HEAD` at
ship-time Phase 4 contradicted it. **Prevention:** a revert is not done until `git diff
origin/main...HEAD -- <path>` prints nothing. `git checkout origin/main -- <path>` is the form
that reverts a committed change; `git checkout -- <path>` only discards working-tree edits.

**Set `latch_lines=0` on the not-latched path, 41 lines below my own comment saying neither token
is ever `0`.** Its sibling `latch_flushed_at` correctly stayed `n/a`. Field dropped.
**Prevention:** when a file states a degradation contract, grep the contract's forbidden value
across the block that implements it before committing.

**Wrote a stray undefined `$LATCH_DIRMARK` into a test running under `set -u`.** One-off; caught
by the run.

**`gh issue create` rejected for a missing `--milestone`.** Already hook-enforced; the hook did
its job. One-off.

**Prior-phase errors from PR #7692 (same session, before compaction)** — the trailer-block
invalidation from a bare `Ref #7674`, the `git filter-branch` ancestry break, the `git ls-files`
unmerged-path triple-count that made me mis-read a guard-vacuity RED, the stale 13:40 measurement
reported as current, and ending a turn on a preflight continuation point — were compounded in
that PR's own cycle and are not re-litigated here.

## Tags

category: logic-errors
module: apps/web-platform/infra
