# ADR-158 — Delivery is not activation: a config channel must reconcile the units it configures

- **Status:** Accepted
- **Date:** 2026-08-02
- **PR:** #7146
- **Issue:** #7103 (residuals R1–R5 of #7095); soak enrolled on #7170
- **Related:** [ADR-154](./ADR-154-repair-the-credential-channel-not-the-host.md) (the credential
  channel this builds on, and the SSH handler-bootstrap leg that can be dead on a host with no
  replacement path), [ADR-148](./ADR-148-web-host-replacement-is-a-distinct-gated-dispatch.md)
  (why `-replace` is unavailable here),
  `apps/web-platform/infra/infra-config-apply.sh` (the handler that now reconciles),
  `apps/web-platform/infra/infra-config-install.sh` (the shape gate that had to ship first),
  `scripts/betterstack-assert-absence.sh` (the absence assertion that refuses to guess)

> **Ordinal.** Renumbered 155 -> 158 at `/ship` time. Three sibling PRs landed ADR-155 (cross-gate
> exemption markers), ADR-156 and ADR-157 on `origin/main` while this pipeline was open. The
> collision was invisible on the un-rebased branch — `check-adr-ordinals.sh` sees only the local
> tree, so it stayed green here and would have gone red on `main` post-squash. The `/work`-time note
> this replaces called the ordinal provisional and named the re-check; the re-check is what caught
> it, one rebase later.

## Context

#7095 restored production by delivering a re-deliverable Doppler credential to `web-1`, plus systemd
drop-ins re-pointing `vector.service` and `inngest-heartbeat.service` at it. The delivery worked. The
files landed with the right bytes, the gate verified them, and the apply reported success.

The units kept running the environment they had been started with.

systemd reads a drop-in when the unit is (re)started, and nothing restarted them. So the channel
built to repair the credential reported that it had, while the processes it exists to repair carried
on with the revoked one. Nothing in the system was lying; nothing in it was checking either.

Four of the five residuals on #7103 share one shape, and it is worth stating plainly because it is
the thing this ADR is about:

> **The system repeatedly reported a state it had not established.**

A credential landed on disk and was called active. A telemetry query returned zero and was called
clean. A digest of the empty string was called ACTIVE. A test suite that skipped a red runner was
called green.

Each of those is a different subsystem. The common factor is not a bug in any of them; it is that in
each case *the absence of evidence was recorded as evidence of success*.

## Decision

**Three propositions.**

### 1. A channel that delivers configuration must reconcile the units that consume it, and must
report per-unit whether it succeeded.

`infra-config-apply.sh` now restarts the units whose drop-ins it delivers, and emits a verdict for
each into its status JSON (`schema_version: 2`, a `restarts` array). The CI gate adjudicates that
array; a delivered-but-unactivated unit fails it.

Reconciliation is folded into the handler rather than exposed as a separate `restart-unit` webhook.
The event requiring the restart *is* the delivery, so coupling them means the decision is made where
the delivery outcome is already known. A separate remote-triggerable restart primitive on the one
host that cannot be replaced buys nothing and widens the attack surface.

### 2. Activation is graded on effect, never on exit code.

`systemctl try-restart` exits 0 on a unit that is `failed` — it is defined as a no-op there — and on
a `Type=simple` unit a 0 means *forked*, not *running*. So the handler re-reads `ActiveState` and
`ExecMainStartTimestamp` after a settle, and calls the restart successful only when the unit is
active **and** its start timestamp advanced.

The staleness predicate is a single clause:

```
stale(unit) := ExecMainStartTimestamp(unit) < max(mtime(drop-in), mtime(credential))
```

which also heals a credential rotation predating the code. Its failure modes get *distinct* enum
values — `unit_inactive`, `noop_not_active`, `restart_did_not_advance`, `sudo_denied`,
`timestamp_unparseable`. A denied `sudo` is a provisioning defect and must never share an enum with
a property of the unit; #5934 is the case where a swallowed denial became a silent no-op nobody
noticed until the next incident.

### 3. An absence assertion must prove its own channel is alive, or report that it cannot.

"Zero rows", "the query could not answer", and "this host stopped shipping logs" are the same empty
stdout. `scripts/betterstack-assert-absence.sh` therefore has four outcomes — `clean`, `present`,
`unshipping`, `unknown` — and `clean` is reachable only with a host-scoped positive control read back
**through the sink**. The control is emitted outside the `doppler run` wrapper, because a control
gated behind the credential whose failure it certifies is not a control.

## Consequences

**A restart capability now exists on the host, so the config it activates must be validated.** This
is the ordering constraint that governs the change: `infra-config-install.sh` validates
`*.service.d/*.conf` content against a permitted-directive whitelist, and that gate ships *before*
the `DROPIN_TRY_RESTART` sudoers grant. systemd merges drop-ins after the unit body, and
`vector.service` runs `User=deploy`, so an unvalidated drop-in could set `User=root` or replace
`ExecStart=`. Granting a root restart of a unit whose configuration can be written without validation
converts a delivery capability into an execution capability. Delivery-then-activation is not a
refactor of the same privilege; it is a new one.

**Writes stay unconditional; only `changed` is derived.** Making the write content-conditional would
drop the per-apply re-assertion of `640 root:deploy` on the credential — a dest whose DAC drifted
still matches on content, so it would be skipped and reported `ok` while the one channel able to
repair it stopped repairing it. `changed` exists to preserve mtime on an identical rewrite, without
which the predicate over-fires on every apply forever.

**The gate's activation contract is staged.** A handler predating it emits no `schema_version`, and
the only route to replacing that handler is the SSH bootstrap leg that ADR-154 records can be dead.
Failing on absence would red the adjudication step, which skips the `if: success()`-gated redeploy —
so files would land and activation would never happen. It warns and passes; the hard-on-absent flip
is a follow-up, recorded on #7103.

**One deliberate narrowing.** The gate does *not* fail on a unit that is merely inactive and was
never restarted. Every case where the handler acted and the restart did not take is already covered
by the failure enums. `inngest-heartbeat.service` is created by `inngest-bootstrap.sh` and is
therefore co-location dependent, so failing on it would permanently red the deploy gate on a
correct host — a worse outcome than the one guarded against. "Is this unit actually shipping?" is
proposition 3's question, answered at the sink where "not running" and "not supposed to be running"
are distinguishable.

**AC12 cannot be verified pre-merge.** Its measurement path runs through the component this repairs,
so it is enrolled as a post-apply soak on its own issue (#7170) rather than on #7103 — the sweeper
closes issues on PASS, and closing #7103 with B1–B7 still open is the outcome its exit gate exists
to prevent.

## Alternatives considered

| Option | Why not |
|---|---|
| A `restart-unit` webhook hook | Adds a remote-triggerable restart primitive to the one host with no replacement path, decouples the restart from the event requiring it, and falsifies the `tunnel -> hetzner` C4 description. |
| Accept it; units refresh on host recreate | The host cannot be recreated (cx33, orderable in 0 of 3 EU DCs). The telemetry plane ages out silently and proposition 3 has no live channel to assert against. |
| Reconcile inside `infra-config-install.sh`, which is already root | Genuinely attractive — zero new sudoers alias, one fewer file on the SSH leg. Rejected on the real reason: the installer is reachable through a **bare-command** grant that permits any arguments, and its own header records that the security boundary is therefore the helper, not sudoers. Adding a unit-restart capability there widens that boundary from *write these dests* to *write these dests and restart units*. It is also per-file and stateless, while the decision is per-unit and needs the whole delivery outcome. |
| Fail the gate on any `active != active` | Would red the deploy gate permanently on a host where a co-location-dependent unit legitimately does not run. See the narrowing above. |
