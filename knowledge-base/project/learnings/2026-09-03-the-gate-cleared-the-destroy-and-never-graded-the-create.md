---
title: The gate cleared the destroy and never graded the create
date: 2026-09-03
category: logic-errors
module: apps/web-platform/infra
issues: [7695, 7674, 6894]
pr: 7778
related:
  - 2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md
  - 2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md
  - 2026-08-20-every-instrument-i-checked-my-own-work-with-was-broken.md
  - 2026-08-12-every-blocking-finding-was-the-defect-class-the-pr-existed-to-close.md
---

# The gate cleared the destroy and never graded the create

## Problem

Merge B of #7695 ships a gated `inngest-volume-recut` dispatch: destroy the plaintext ext4 volume
holding the Inngest Redis AOF so the next boot cuts it to LUKS. The AOF holds user prompts and
agent output, the destroy is irreversible, and the store is empty exactly once — so the whole merge
is an apparatus for answering *may this be destroyed right now*. Twenty predicates in Guard 2 for
the world, eleven counters in Guard 1 for the plan, a required-reviewer environment, a confirm
literal, a physical-id pin checked against two independent sources.

All of it was correct, and it would still have produced an unencrypted volume.

`hcloud_volume.inngest_redis` declared `format = "ext4"` under a
`lifecycle { ignore_changes = [format] }`, with thirteen lines of comment arguing the attribute had
to stay: `format` is ForceNew, so removing it queues a replace, and `apply_target=inngest-host`
carries an additive-only destroy guard that would then abort *permanently*, disabling the recovery
dispatch for a host that is already not serving. Plausible, specific, and load-bearing enough that
it had already survived one review pass.

Measured against live state instead of argued:

```
line removed, lifecycle kept:   hcloud_volume.inngest_redis  actions=["no-op"]
```

No replace is queued. `ignore_changes = [format]` suppresses exactly that diff — the argument
reasoned about ForceNew while ignoring the four lines directly beneath it. And on the recut plan
(`-replace=hcloud_volume.inngest_redis`):

```
with    format = "ext4":  after.format=ext4
without format = "ext4":  after.format=null
```

`ignore_changes` suppresses DIFFS, never CREATES. So the sequence was: twenty predicates prove the
store is empty and the host is dark → the destroy is correctly authorized → the replacement volume
is created **ext4** → cloud-init's ARM 1 mounts it plaintext → the one-shot empty-store window is
spent producing an unencrypted store, while the workflow prints "The new volume is RAW" twice.

## What was actually wrong

**A destructive-change gate that grades only the destroy is answering half the question.**
Clearance answers *may this be destroyed*. It says nothing about what replaces it. Every layer in
this apparatus pointed at the thing being removed and none at the thing being created — and for a
one-shot window, the create is where the value is.

The same shape ran through everything else review found in this branch, all of it in gates that
were green:

- **G3 was a recency bound that bounded nothing.** Row selection took the newest row *carrying*
  `probe_schema=`, then compared its `boot_id` against the newest row's. `boot_id` is CONSTANT
  across every row of one boot, so a row from ninety minutes ago compared equal to one from ten
  seconds ago. Worse, the emitter writes `http_code` and `server_active` *before* `probe_schema`,
  so a newest row truncated in between carries the live proof the host is SERVING, satisfies the
  boot pin, and is discarded for an older row saying the opposite. Constructed: a newest row
  reading `http_code=200 server_active=active` with no `probe_schema=` returned `dark`, rc 0. The
  ADR cited that pin as though it were a staleness bound. A check that reads like the guarantee and
  is not one is worse than no check, because the prose starts leaning on it.
- **G10's clearing value was zero and its query had no positive control.** Every way the query
  could be wrong — an undecodable envelope, a mis-targeted query, a channel that never reaches the
  source — produced the same zero that means "nothing ran". Note the polarity: elsewhere a dropped
  row pushed toward a refusal; here it pushed toward `dark`.
- **The documented recovery aborted.** The failure path prescribed re-dispatching the recut,
  reasoning from Guard 1's recovery bare-create arm. The arm is real; the dispatch never reaches
  Guard 1, because Guard 2 runs first and grades the live host. Three consecutive aborts.
- **The cutover did not finish and the success text said it did.** "The LUKS cut happens on the
  next boot" — the cut is in cloud-init `runcmd`, which is FIRST-BOOT-ONLY, and Guard 1 requires
  the host to show zero actions, so this dispatch cannot reboot it *by construction*. A fourth
  dispatch is mandatory and was named nowhere.
- **Two legal retractions never propagated.** PA-13's corrections were written into PA-13; PA-14
  still read `bound to 127.0.0.1` and still governed its tier pin by "PA-13's 30-day SQLite
  window". Found by grepping the OLD wording. Grepping the new one is structurally blind.

## The fix

Guard 1 reads `.change.after.format` and refuses unless it is null — the property is enforced
against the plan, not against the config staying the way it is. G3 became a wall-clock bound with
an injectable clock. G10 got a positive control. Both operator-facing texts were corrected and are
pinned by arms that grep the *superseded* wording so a partial revert reddens.

## Learning

**A gate over a destructive change must grade the replacement, not only the removal.** Ask, for
every clearance gate: if every predicate holds and the apply succeeds, what exists afterwards, and
which counter measured it? For a one-shot window the create is the irreversible half.

**When a comment argues at length that a suppression makes an attribute safe, run the plan.**
`ignore_changes`, `prevent_destroy`, `ignore_errors` and their kin all describe what happens to a
DIFF. None of them describe what happens on a CREATE, and a resource being replaced is created.
The length of the argument was the signal — thirteen lines of justification for one attribute is a
claim nobody has measured.

**A predicate that cannot distinguish two states is not a predicate, however it reads.** `boot_id`
is constant within a boot; comparing it to itself is `x == x`. The way to catch this class is not
review but a fixture on the far side: for every bound, write the case that must be REFUSED for
being out of bounds, and watch it fail before the bound exists.

**Anti-vacuity machinery is itself vacuity-prone, one level up.** Both suites self-tested
`pass()`/`fail()` and neither self-tested `expect()`/`check()` — the wrappers every arm actually
goes through. Replacing either wrapper body with a bare `pass` produced a full green run, rc 0,
with every floor reporting healthy. One suite's floor compared against 55 while printing 71; the
drop-one floor counted CALLS, so twenty `predicate G1` lines would have satisfied a floor of 20.
Whatever mechanism proves the arms ran, drive it in the direction that must FAIL and roll the
counters back.

**A drop-one battery is structurally blind to the too-aggressive direction.** All twenty cases
assert a refusal, so a gate hardened into "refuse everything" passes all of them — and a gate that
passes its tests while refusing the operator is still broken. Twelve guard mutations survived both
batteries here; four of the fixtures that close them are must-PASS directions.
