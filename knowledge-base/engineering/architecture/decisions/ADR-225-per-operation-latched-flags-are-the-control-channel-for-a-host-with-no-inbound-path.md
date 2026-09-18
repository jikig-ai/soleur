---
title: Per-operation latched flags are the control channel for a host with no inbound path
status: accepted
date: 2026-09-18
related: [6894, 6178, 7228, 7674, 7761]
related_adrs: [ADR-100-inngest-dedicated-single-host-singleton-control-plane, ADR-142-inngest-redis-aof-zero-data-loss-luks-migration, ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host]
brand_survival_threshold: aggregate pattern
---

# ADR-225: Per-operation latched flags are the control channel for a host with no inbound path

## Status

`accepted`. Describes the pattern two independent FSMs on the dedicated Inngest host already
implement (`INNGEST_CUTOVER_FLIP`, #6178; `INNGEST_LUKS_CUTOVER`, #6894), and fixes the rules a third
one must follow — the point being that the second one was written by copying the first without a
written contract, and the copy diverged in four places that each had to be argued from scratch.

## Context

The dedicated Inngest host (ADR-100) has **no inbound path**: deny-all public ingress, no SSH, and
the `/hooks` webhook channel terminates on web-1 — measured 12/12, so `/hooks/deploy-status` cannot
reach it at all. Every operator action on that host therefore has to be something the host PULLS.

What it pulls is a Doppler secret. A systemd timer fires a root oneshot every 30s; the oneshot reads
one named value and acts on it. The operator's entire vocabulary is "write this value".

That shape has a property that is easy to miss and expensive to rediscover: **the flag is not a
message, it is a latch.** Nobody acknowledges it, nothing removes it, and it outlives the host — the
Doppler config survives a replace, while anything on the root disk does not (#7228: a flip completed,
the host was replaced, the new host inherited `done` with no local marker, and its guard refused to
start the scheduler; the recovery the guard named had no verb that wrote it).

Three more facts constrain the design, all measured rather than assumed:

- `doppler run` injects the WHOLE config unless bounded, so any name in it lands in the environment
  of a root script. That made Doppler config-write access equivalent to root command execution on
  this host (#7761).
- A write to a host that is not listening recovers nothing AND parks the flag in a state the next
  dispatch refuses — manufacturing a dead end out of an outage (#7674).
- Absence of telemetry is also what a retention lapse looks like, so an off-host reader can prove a
  row's PRESENCE and can never prove its absence means anything.

## Decision

**A no-inbound host is controlled by ONE latched flag PER OPERATION, whose terminal states are
no-ops, whose writer gates on the host being audible, and whose effect is confirmed from the host's
own telemetry — never from the writer's exit code.**

Six rules. Each is a thing that went wrong somewhere in this repo.

### 1. One flag per operation, never one flag per host

`INNGEST_CUTOVER_FLIP` owns the one authorized `FLUSHALL`. `INNGEST_LUKS_CUTOVER` owns a copy that
preserves data. They are separate names with separate FSMs, because a shared flag means one terminal
value authorises two opposite actions, and the wrong one is unrecoverable. The test is not "are these
related operations" — flip and cutover are both "the cutover" in conversation — but **"would I be
willing to run either of them on seeing this value".**

### 2. Terminal states are no-ops, and the error trap drives the flag terminal

`done`, `rolled-back` and `aborted` do nothing and exit 0. That, not an epoch token or a nonce, is
what makes a 30s poll safe: a completed run leaves the flag terminal, so every subsequent tick
refuses before touching anything. An unhandled failure drives the flag terminal too — which stops the
poll LOUDLY rather than leaving a half-done operation re-entering every 30 seconds.

### 3. The latch records completion-with-verification, never entry

A latch written on entry answers "did something start". The question that matters on re-entry is "is
the work still valid" — and after a reboot the answer can be no even though the latch exists. So the
latch is written after the verification passes, and the resume arm **re-verifies rather than trusting
it**: `INNGEST_LUKS_CUTOVER=copied` re-runs T2 and re-copies a stale copy.

### 4. The writer gates on the host being AUDIBLE, on that operation's own tag

Before writing, the dispatch requires recent journald rows from the unit that will act on the write,
under **its own `SyslogIdentifier`**. Borrowing a sibling unit's rows is the trap: the flip timer is
enabled on a host where the LUKS trio never installed, so a shared-tag liveness check would report
"ready to act" for a unit that does not exist. A read-path failure is `unreadable` and refuses
fail-closed; it is not a statement about the host.

This gate is strictly dominant, which is why it is unconditional: writing to a silent host forfeits
nothing, because the write achieves nothing.

### 5. The effect is confirmed from the host's telemetry, within a window anchored at the write

The dispatch polls Better Stack for a terminal flag row, with the window starting at the moment of
the write. Anchoring earlier lets a terminal row from a PREVIOUS run satisfy the confirm — the same
stale-read class as reading a cached measurement. A timeout is reported as "no terminal flag within
Ns", never as success, and never as a claim about the store.

### 6. The injected secret set is bounded, and the script's own seams are argv-gated

`--only-secrets <explicit list>` on the `doppler run`, so a name in the config cannot reach the
script's environment. Because that flag's `--no-exit-on-missing-only-secrets` companion (needed: an
un-armed host legitimately has no flag) makes a mis-authored list degrade quietly, the script asserts
each name it needs is non-empty before use. Fixture seams are read from the environment ONLY when
argv carries `--fixture-seams`, because argv is the one channel `doppler run` cannot supply.

## The verification-does-not-actuate waiver, and its bounds

Rule 5 says the operator's verdict comes from the host's telemetry. That raises an obvious question:
if we trust telemetry to confirm, why not let telemetry **trigger** — close the loop and have the
host act on what it observes?

**Waived, with bounds.** Verification may read anything; it may never actuate. Concretely: no code
path may take a Better Stack row, a probe field or any other off-host reading as the AUTHORITY for a
destructive or state-moving action on this host. The authority is always a latched flag a human
approved through the reviewer-gated environment.

Why the asymmetry is principled rather than timid:

- **A read that fails is recoverable; an actuation that fires on a bad read is not.** Confirmation
  reads fail closed into "unknown", which costs a re-dispatch. An actuation on a stale or partial row
  spends the irreversible action.
- **Absence is unprovable from off-host.** A missing row is equally consistent with "nothing
  happened", "Vector is down" and "retention dropped it". A trigger keyed on absence therefore fires
  on an outage of the observability path itself.
- **The row is attacker-influenceable at the margins.** Probe rows carry free text; this repo has
  already measured a case where a crafted tail supplied a trusted field to a consumer parsing with a
  greedy match (#7500). A confirmation read that is wrong wastes a dispatch; an actuation that is
  wrong executes.

The bound in the other direction, so this does not become an excuse for an unobservable system: every
refusal, every phase and every terminal state MUST be emitted. If a state an operator needs is not in
a row, that is a gap in the emitter — not grounds for opening a shell on a host that has no shell.

## Consequences

- A new operation on this host costs a new flag NAME, a new FSM with terminal no-ops, a new
  `SyslogIdentifier` in the Vector allowlist, a `--only-secrets` entry, and a dispatch verb with the
  four guards. That is the price of the pattern and it is deliberately not zero.
- The poll cadence is the retry mechanism. A transient failure is retried in 30s with no operator
  action; a persistent one lands on a terminal flag with a reason, which is the operator's cue.
- Two things this pattern does NOT give you: ordering between flags (they are independent latches —
  if op B must follow op A, B's own guard must assert A's postcondition), and any notion of "cancel"
  (a write in flight is acted on; the only cancel is a guard that refuses).
- The unit performing mount work must NOT allocate a private mount namespace: `ReadWritePaths=`,
  `ProtectSystem=` and `PrivateTmp=` each imply one (`man systemd.exec`), and a mount made inside it
  vanishes when the oneshot exits, leaving the consuming service on the old device. Sandboxing that is
  correct for a flag-reading oneshot is wrong for a mount-moving one; the decision is made per unit
  and written down, never inherited by copy.

## Alternatives considered

| Option | Why not |
| --- | --- |
| One `HOST_OP` flag with a verb value | One terminal value authorising several actions; a stale `done` from a different op reads as this op's success. Rule 1 exists because of this. |
| A queue (SQS/Redis) the host consumes | An inbound dependency with its own credentials and its own outage modes, to carry one string. The Doppler read is already on the host's critical path for everything else. |
| Poll a git ref / an artifact instead of Doppler | Same latch semantics, worse secrecy story (the value is sometimes a credential-adjacent id), and a second delivery path to keep alive. |
| Telemetry-triggered actuation (close the loop) | Waived above, with bounds. |
| Nonce/epoch token per dispatch | Considered and cut (#6894 Fork D): terminal no-ops already make re-fire safe, and a nonce adds a second piece of state that can disagree with the flag. |
