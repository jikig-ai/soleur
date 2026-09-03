---
title: "ADR-199 — destroying a state volume is authorized by a MEASURED empty store on a dark host, never by an intent to destroy it"
status: accepted
date: 2026-09-03
tags: [infrastructure, encryption-at-rest, destructive-apply, gates, observability, inngest]
related_adrs: [ADR-142, ADR-140, ADR-119, ADR-100, ADR-096, ADR-193]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/betterstack-log-query.md
---

# ADR-199 — destructive clearance is a measurement, not an intent

## Status

`accepted`. The invariant is true the moment this ADR merges: `apply_target=inngest-volume-recut`
exists in `.github/workflows/apply-web-platform-infra.yml` and cannot reach `terraform plan`
without `inngest_host_dark_gate` returning the literal `dark`.

Bounds — does not amend — [ADR-142](./ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md).
See its `## Addendum — 2026-09-03 (#7695)`: the two decisions govern disjoint worlds and this gate
decides which world you are in at dispatch time.

## Context

`hcloud_volume.inngest_redis` is a plaintext ext4 volume holding the Inngest Redis AOF — in-flight
job payloads, i.e. user prompts and agent output. It is the encryption-posture ledger's
highest-sensitivity plaintext row (`tracking_issue: #6894`).

Two migration shapes exist in this repo and they have opposite risk profiles:

- **Preserve-and-copy** (ADR-142): provision a second volume, quiesce, copy bytes, swap the mount.
  Safe for a populated store. Expensive, multi-step, and it preserves nothing when there is nothing
  there.
- **Destroy-and-recut** (the #6895 registry pattern): `-replace` the volume so it is born raw, and
  let cloud-init `luksFormat` it. Cheap and single-step. Catastrophic against a populated store.

ADR-142 forbade the second shape here on a premise stated unconditionally: the AOF is *sole-copy
non-disposable state*. At the time that was the only reading available — nothing in the repo could
measure how much state the volume held. `probe_schema=3` changed that.

**The failure mode this ADR exists to prevent is not a wrong choice between the two shapes. It is
choosing the destructive one on a REMEMBERED fact.** Every other authorization layer on this
dispatch — a reviewer approving an environment, a confirm literal being typed, a volume id being
pinned, a plan document matching a shape — is satisfiable in full while the host is serving live
traffic and the store holds armed reminders. All four authorize by INTENT. None of them looks.

## Decision

**A dispatch that destroys a state volume must prove, from telemetry, that the state is not there —
and a gate that cannot see the host must never conclude the host is dark.**

Concretely, three commitments:

### 1. The clearance condition is a conjunction over ONE row, not a disjunction over a window

Twenty predicates (`tests/scripts/lib/inngest-host-dark-gate.sh`, G1..G20), all read from a single
`SOLEUR_INNGEST_SERVER_PROBE` row on the current `boot_id`, plus four re-reads taken synchronously
at dispatch time. Fields from two different rows may never be assembled into a verdict: that would
authorize on a state that never simultaneously existed.

The emptiness claim rests on `redis_keys == 0` **conjoined with** `data_mount_src` pinned to the
physical device. `redis_keys` alone is a statement about a Redis *process*; the recut destroys a
*block device*. Today's mount is `mount … || true` with `nofail`, so a failed mount leaves
`/mnt/data` on the ephemeral root disk and Redis reports an empty store while the volume holds a
populated AOF. The mount pin is what bridges process to device, and without it every other
predicate is measuring the wrong object.

### 2. The decision function is a POSITIVE ALLOWLIST

It proceeds only on the literal `dark`. Every other token aborts — `unreadable` included.

This deliberately inverts the posture of a monitoring pre-filter, and the inversion is the point.
A pre-filter may only ADD a refusal, so a read failure there degrades safely. Here the gate is
authorizing an irreversible destroy, so an unreadable signal must abort.

**Measured, not argued.** On 2026-09-03 the Better Stack ClickHouse read path returned HTTP 503
(`{"exception":"This source is currently under maintenance."}`) for an entire working session.
`scripts/followthroughs/inngest-host-not-serving-7674.sh` returned `TRANSIENT reason=query_failed
rc=22` throughout and refused to convert a broken read into a host verdict. That refusal is the
correct behaviour and it is this ADR's evidence: a gate written the other way would have read the
outage as "no rows, therefore quiet, therefore dark" and cleared a destroy on a host nobody could
see. The failure is not hypothetical and this ADR does not argue it hypothetically.

### 3. Verdict tokens stay DISTINCT when their remedies differ

`scripts/inngest-dedicated-host-classify.sh` collapses `silent`, `unreadable` and a pre-schema row
into one `probe-unavailable` verdict. That is right for a pager — all three mean "go look". It is
wrong for a gate, because the three have different remedies and only one of them is a wait. This
gate therefore reuses that script's host-conjunction query filter and its `R_SPOOF` fixture shape,
and NOT its function.

The distinction that matters most in practice is `stale_schema`: it is the EXPECTED verdict for
every dispatch until the host is replaced, because the running host's `boot_id` has been unchanged
for weeks and it emits no `probe_schema` at all. Collapsed into `unreadable` it would tell the
operator to retry forever against a host that can never satisfy the gate. Kept distinct it says
"replace the host first", which is actionable. It is also the mechanical interlock that makes the
apparatus-then-recut ordering a CONSTRAINT rather than operator discipline: before the new emitter
is live the recut is unreachable by construction.

### The soundness of a ≤90-minute-old emptiness claim

The probe fires hourly, so the chosen row can be up to ~90 minutes old. The argument that this
still authorizes an apply is a MONOTONICITY argument and it lives in the gate source, not only
here: `inngest-server` is the only writer that can INCREASE the key count; G8∧G9 prove it was
neither running nor answering on the newest row; G19 re-reads `INNGEST_CUTOVER_FLIP` synchronously
and refuses anything but `rolled-back`/`aborted`, so no concurrent `FLUSHALL` can be authorized;
and armed reminders firing only CONSUME keys. The count therefore cannot increase between the row
and the apply.

**"Only writer that can increase" is the measured form, and it is not what a first draft of this
paragraph said.** That draft claimed `inngest-server` was the only writer at all, and that Redis was
"reachable from nothing else on the box". Both are false. `redis-cli` has three in-repo callers
against this instance — the flip FSM's `FLUSHALL` (a writer), the probe's `INFO keyspace` (a
reader), and a test — and the loopback bind comes from `inngest-redis.conf`, not from the unit,
with `--requirepass` as the on-box control. The corrected claim is a monotonicity property over all
three callers rather than an exclusivity claim over one, and it is strictly stronger: the only
non-server writer sets the count to zero. Recorded rather than silently reworded, because shipping
a guard whose stated justification is false is the defect class this ADR exists to name.

## Consequences

- **The common path is a refusal, and that is correct.** Until the host is replaced, every dispatch
  verdicts `stale_schema`. A gate whose expected outcome is "no" is not a broken gate.
- **`redis_keys > 0` routes to ADR-142, with no override.** There is no `[ack-destroy]` bypass and
  no operator flag that skips Guard 2. Enumeration is also unavailable on a dark host
  (`inngest-enumerate-reminders.sh` queries `127.0.0.1:8288`), so non-empty and non-enumerable
  together mean preserve-and-copy is the only lawful route.
- **A second id-pin exists, against a second source.** Guard 1 pins the plan's
  `.change.before.id`; Guard 2 pins the LIVE Hetzner attachment. They can disagree — a plan is a
  projection of state, and state can be wrong about the world — and it is the world that gets
  destroyed.
- **The ledger row keeps its exception at this merge.** The apparatus ships INERT: the device
  becomes `crypto_LUKS` only when the gated dispatch runs. Flipping `mechanism` to `luks` now would
  be a false at-rest claim about user prompts and agent output for an unbounded window.
- **A drop-one battery is keyed on PREDICATES, not verdict tokens.** Several predicates share a
  token (three map to `wrong_host`, two to `host_serving`, four to `unreadable`), so a token-keyed
  battery needs about half the cases and cannot tell that one was deleted. This is a general
  property of any gate whose verdict vocabulary is smaller than its predicate set.
- **`G12` and `G13` may not be merged.** `[[ "__UNREADABLE__" -eq 0 ]]` is TRUE under bash
  arithmetic coercion, so a single "is the count zero" check reads the emitter's own
  cannot-measure sentinel as the clearing value.
- **Cost.** Twenty predicates plus two batteries is more machinery than the four intent layers put
  together. That asymmetry is the decision: the layers that authorize are cheap because they encode
  a human's belief, and the layer that measures is expensive because it has to be right about the
  world at a moment nobody is watching.

## Alternatives considered

- **Trust the four intent layers.** Rejected: all four are satisfiable while the host serves.
  A reviewer approving an environment is approving a plan, not a measurement.
- **Reuse `inngest-dedicated-host-classify.sh` as the decision function.** Rejected: its
  `probe-unavailable` verdict collapses three states whose remedies are disjoint, and one of them
  (`stale_schema`) is the common path here.
- **Rest the emptiness claim on `data_bytes` alone and drop `redis_keys`.** This was the shipped
  reading for one merge, on a stated premise — that crediting the probe required wrapping its
  `ExecStart` in `doppler run`, which would `203/EXEC` on the co-located web host. **The premise was
  false**: the unit already carried two tolerant `EnvironmentFile=` lines and a plain script
  `ExecStart`, so a third single-variable env file was shape-identical to what was there. Recorded
  as a rejected alternative rather than omitted, because the reasoning that produced it — arguing
  from "the unit needs a secret" to "the unit must run under `doppler run`" without reading the unit
  — is the failure this ADR's whole posture is against.
- **A size ceiling on `data_bytes`.** Rejected: any ceiling would be an invented number. The honest
  guard is that the figure was measured at all, since it is the only surviving audit record of what
  is about to be destroyed.
- **Amend ADR-142 to permit a destroy when the store looks empty.** Rejected: that makes the
  sole-copy protection conditional on a reader's judgement. Bounding it instead leaves ADR-142
  categorical and puts the conditionality in a gate that must measure before it may proceed.

## Addendum — 2026-09-03 (review of this ADR's own delivery)

Appended, not merged into the text above, because three of the claims that text makes were
falsified by measuring them and the superseded wording is the useful part of the record.

**1. The recency bound was never a recency bound.** Commitment 1 says the twenty predicates read
"a single `SOLEUR_INNGEST_SERVER_PROBE` row on the current `boot_id`", and the gate implemented
that as: choose the newest row CARRYING `probe_schema=`, then compare its `boot_id` against the
newest row's. `boot_id` is CONSTANT across every row of one boot, so a row from ninety minutes ago
and a row from ten seconds ago compared equal — the check that reads like a staleness bound was
not one, and this ADR cited it as though it were.

The field order made it maximally adverse: the emitter writes `http_code` and `server_active`
BEFORE `probe_schema`, so a newest row truncated in between carries the live proof that the host is
SERVING, satisfies the boot pin, and is then discarded in favour of an older row that says the
opposite. Constructed and executed during review: a newest row reading `http_code=200
server_active=active` with no `probe_schema=` returned **`dark`, rc 0**.

Two changes. The chosen row must now BE the newest row — a newest row that cannot be graded is
`unreadable`, never a licence to reach further back. And G3 is now the wall-clock bound this ADR's
own "≤90-minute-old" heading always assumed and never enforced: the newest row must be no older
than `--max-row-age` (5400s), with a row dated in the FUTURE refused separately, since that is the
sign shape a `-le` bound on a signed difference waves through.

**2. The monotonicity argument's treatment of the raced `FLUSHALL` was wrong.** The paragraph above
says no concurrent `FLUSHALL` can be authorized and treats the raced write as the one write that
cannot make a zero reading stale. `run_preflush_flip` in `inngest-cutover-flip.sh` runs
stop → FLUSHALL → assert → record_flush_latch → **start_server**, and the `flushed` resume arm
calls `start_server` with no flush at all. The raced transition's LAST act starts the only writer
that can increase the count. Its trigger is also outside GitHub's reach: `inngest-cutover-flip.timer`
is `OnBootSec=30s` / `OnUnitActiveSec=30s` and polls a Doppler flag, so the
`deploy-inngest-restart` concurrency group — which serialises workflow JOBS — cannot serialise it.
G19 therefore SAMPLES the flag; it does not hold it. The residual window between G19's read and the
apply is real and is now recorded in the gate source rather than argued away.

**3. Clearance is not encryption, and the gate could have cleared a plan that produced neither.**
`hcloud_volume.inngest_redis` declared `format = "ext4"` under a `lifecycle { ignore_changes =
[format] }`, with a long comment arguing the line had to stay because removing it is ForceNew and
would queue a replace that makes `apply_target=inngest-host` abort permanently. Measured against
live state rather than argued:

    line removed, lifecycle kept:   hcloud_volume.inngest_redis  actions=["no-op"]

and on the recut plan itself (`-replace=hcloud_volume.inngest_redis`):

    with    format = "ext4":  after.format=ext4
    without format = "ext4":  after.format=null

`ignore_changes` suppresses DIFFS, never CREATES. So every predicate in this ADR could have held,
the destroy could have been correctly authorized, and the replacement volume would have been
created ext4 — mounted plaintext by cloud-init ARM 1, spending the one-shot empty-store window on
an unencrypted store while the workflow printed "The new volume is RAW" twice. The line is gone,
and Guard 1 now reads `.change.after.format` from the plan and refuses unless it is null: the
property is enforced against the plan, not against the config staying as it is.

This is the sharpest form of the distinction this ADR is built on. Clearance answers "may this be
destroyed"; it says nothing about what replaces it. A gate that measures the destroy and not the
create is a gate that can be entirely correct and still leave the fleet in the state it exists to
prevent.

**4. The recut does not finish the cutover, and nothing said so.** The dispatch's success text read
"the LUKS cut happens on the next boot". The cut lives in cloud-init `runcmd`, which is
FIRST-BOOT-ONLY. What runs on boot 2+ is `inngest-luks-open.service`, whose script OPENS and never
formats: against a raw device it takes `reopen_skip_plaintext` or fails `reopen_not_luks`, so
nothing is formatted, `/mnt/data` never mounts, and `inngest-redis.service`'s mount guard refuses
the start. Guard 1 requires `hcloud_server.inngest` to show ZERO actions, so this dispatch cannot
reboot or replace the host **by construction** — that is the three-dispatch split working, but it
makes the ordering the operator's to own:

    1. merge  ->  2. inngest-host-replace  (new cloud-init live; emits probe_schema=3;
                                            ARM 1 mounts the existing ext4 volume plaintext)
    3. inngest-volume-recut                (Guard 2 can now read schema-3 rows; volume born raw)
    4. inngest-host-replace                (fresh FIRST boot; ARM 3 luksFormats the raw device)

Step 4 is not optional and was not stated anywhere. Both the success and the failure paths now name
it, with the reason, and the suite greps the superseded wording so a partial revert reddens.

**5. The documented recovery aborted.** The failure path prescribed re-dispatching
`inngest-volume-recut`, on the reasoning that Guard 1's recovery bare-create arm would accept it.
That arm is real, but the dispatch never reaches Guard 1: Guard 2 runs BEFORE the plan and grades
the LIVE host, so after a partial apply it returns `id_pin_mismatch`, `mount_mismatch` and
`redis_down` in turn. The reachable route is `apply_target=inngest-host`, whose additive-only guard
admits a bare create of an absent volume — and which, with `format` gone, creates it raw.
